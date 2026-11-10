import 'dart:async';
import 'dart:convert';

import 'package:cyrene_music/models/version_info.dart';
import 'package:cyrene_music/services/version_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

Map<String, dynamic> releaseJson({String tag = 'v1.4.0'}) => {
  'tag_name': tag,
  'draft': false,
  'prerelease': false,
  'body': '更新说明',
  'assets': VersionInfo.assets.values
      .map(
        (name) => {
          'name': name,
          'size': 100,
          'state': 'uploaded',
          'browser_download_url':
              '${VersionInfo.repository}/releases/download/$tag/$name',
        },
      )
      .toList(),
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('stable semantic comparison is numeric and ignores build metadata', () {
    expect(VersionInfo.compare('1.10.0', '1.9.9'), greaterThan(0));
    expect(VersionInfo.compare('2.0.0', '1.99.99'), greaterThan(0));
    expect(VersionInfo.compare('1.4.0+99', '1.4.0+1'), 0);
    expect(VersionInfo.compare('1.3.9', '1.4.0'), lessThan(0));
    for (final value in ['1.4', '1.4.0-beta', '01.4.0', '1.x.0']) {
      expect(() => VersionInfo.compare(value, '1.4.0'), throwsFormatException);
    }
  });

  test('only stable, published tags are eligible', () {
    for (final tag in [
      '1.4.0',
      'v1.4.0-beta',
      'v1.4.0+2',
      'v01.4.0',
      'latest',
    ]) {
      expect(
        () => VersionInfo.fromRelease(releaseJson(tag: tag)),
        throwsFormatException,
      );
    }
    for (final key in ['draft', 'prerelease']) {
      expect(
        () => VersionInfo.fromRelease(releaseJson()..[key] = true),
        throwsFormatException,
      );
    }
  });

  test('matches exact assets and canonical official URLs; unsupported has no package', () {
    final release = VersionInfo.fromRelease(releaseJson());
    expect(
      release.platformDownloadUrl('windows-x64'),
      endsWith('/cyrene_music-windows-x64.zip'),
    );
    expect(
      release.platformDownloadUrl('android-arm64'),
      endsWith('/app-release.apk'),
    );
    expect(release.platformDownloadUrl('android-x64'), isNull);
    expect(release.platformDownloadUrl('unsupported'), isNull);
    expect(
      release.releasePage,
      '${VersionInfo.repository}/releases/tag/v1.4.0',
    );
    expect(
      VersionInfo.fromRelease(release.toJson()).platformDownloads,
      release.platformDownloads,
    );
    for (final change in [
      {'name': 'other.apk'},
      {'size': 0},
      {'state': 'new'},
      {'browser_download_url': 'https://untrusted.example/app-release.apk'},
      {'browser_download_url': '/download/app-release.apk'},
    ]) {
      final data = releaseJson();
      final assets = data['assets'] as List;
      (assets[1] as Map).addAll(change);
      expect(
        VersionInfo.fromRelease(data).platformDownloadUrl('android-arm64'),
        isNull,
      );
    }
    final noAssets = releaseJson()..['assets'] = [];
    expect(VersionInfo.fromRelease(noAssets).platformDownloads, isEmpty);
  });

  test(
    'fixed GitHub request has no music backend or login credentials',
    () async {
      final service = VersionService.forTesting(
        loadVersion: () async => '1.3.9',
        client: MockClient((request) async {
          expect(request.url, VersionService.endpoint);
          expect(request.headers.containsKey('authorization'), isFalse);
          expect(request.headers.containsKey('cookie'), isFalse);
          return http.Response(
            jsonEncode(releaseJson()),
            200,
            headers: {'content-type': 'application/json; charset=utf-8'},
          );
        }),
      );
      expect((await service.checkForUpdate())?.version, '1.4.0');
      expect(service.hasUpdate, isTrue);
      expect(service.lastError, isNull);
    },
  );

  test(
    'defaults enabled; old preference is preserved and toggling never requests',
    () async {
      for (final enabled in [null, false, true]) {
        SharedPreferences.setMockInitialValues({
          'auto_update_enabled': ?enabled,
        });
        var requests = 0;
        final service = VersionService.forTesting(
          loadVersion: () async => '1.3.9',
          client: MockClient((_) async {
            requests++;
            return http.Response('{}', 500);
          }),
        );
        await service.initialize();
        expect(service.isEnabled, enabled ?? true);
        await service.setEnabled(false);
        await service.checkForUpdate(silent: true);
        expect(requests, 0);
        await service.setEnabled(true);
        expect(requests, 0);
      }
    },
  );

  test('one successful daily check; manual bypasses; cache persists across restart', () async {
    var now = DateTime.utc(2026, 11, 2), requests = 0;
    final client = MockClient((_) async {
      requests++;
      return http.Response(
        jsonEncode(releaseJson()),
        200,
        headers: {'content-type': 'application/json; charset=utf-8'},
      );
    });
    VersionService makeService() => VersionService.forTesting(
      loadVersion: () async => '1.3.9',
      client: client,
      now: () => now,
    );
    final service = makeService();
    await service.checkForUpdate(silent: true);
    await service.checkForUpdate(silent: true);
    expect(requests, 1);
    final restarted = makeService();
    await restarted.initialize();
    expect(restarted.hasVisibleUpdate, isTrue);
    await restarted.checkForUpdate(silent: true);
    expect(requests, 1);
    await restarted.checkForUpdate();
    expect(requests, 2);
    now = now.add(const Duration(hours: 24));
    await restarted.checkForUpdate(silent: true);
    expect(requests, 3);
  });

  test(
    'concurrent manual and automatic callers share request and result',
    () async {
      var requests = 0;
      final response = Completer<http.Response>();
      final entered = Completer<void>();
      final service = VersionService.forTesting(
        loadVersion: () async => '1.3.9',
        client: MockClient((_) {
          requests++;
          entered.complete();
          return response.future;
        }),
      );
      final automatic = service.checkForUpdate(silent: true);
      await entered.future;
      final manual = service.checkForUpdate();
      response.complete(
        http.Response(
          jsonEncode(releaseJson()),
          200,
          headers: {'content-type': 'application/json; charset=utf-8'},
        ),
      );
      expect(await manual, same(await automatic));
      expect(requests, 1);
      expect(service.isChecking, isFalse);
    },
  );

  test('failures have short backoff, preserve cache and never become latest success', () async {
    var now = DateTime.utc(2026, 11, 2), requests = 0, fail = false;
    final service = VersionService.forTesting(
      loadVersion: () async => '1.3.9',
      now: () => now,
      client: MockClient((_) async {
        requests++;
        return fail
            ? http.Response('limited', 429)
            : http.Response(
                jsonEncode(releaseJson()),
                200,
                headers: {'content-type': 'application/json; charset=utf-8'},
              );
      }),
    );
    await service.checkForUpdate();
    fail = true;
    expect(await service.checkForUpdate(), isNull);
    expect(service.lastError, contains('检查失败'));
    expect(service.hasUpdate, isTrue);
    expect(requests, 2);
    await service.checkForUpdate(silent: true);
    expect(requests, 2);
    now = now.add(const Duration(minutes: 15));
    await service.checkForUpdate(silent: true);
    expect(requests, 3);
    await service.checkForUpdate();
    expect(requests, 4);
  });

  test('manual check ignores suppression; ignore affects automatic notices and badge', () async {
    final service = VersionService.forTesting(
      loadVersion: () async => '1.3.9',
      client: MockClient(
        (_) async => http.Response(
          jsonEncode(releaseJson()),
          200,
          headers: {'content-type': 'application/json; charset=utf-8'},
        ),
      ),
    );
    final release = (await service.checkForUpdate())!;
    await service.ignoreCurrentVersion(release.version);
    expect(await service.shouldShowUpdateDialog(release), isFalse);
    expect(service.hasVisibleUpdate, isFalse);
    expect(await service.checkForUpdate(), isNotNull);
    expect(service.hasUpdate, isTrue);
    service.markVersionReminded('1.5.0');
    expect(
      await service.shouldShowUpdateDialog(
        VersionInfo(version: '1.5.0', changelog: ''),
      ),
      isFalse,
    );
    expect(
      await service.shouldShowUpdateDialog(
        VersionInfo(version: '1.6.0', changelog: ''),
      ),
      isTrue,
    );
  });

  for (final status in [403, 404, 429, 500]) {
    test('HTTP $status is a failure, not up to date', () async {
      final service = VersionService.forTesting(
        loadVersion: () async => '1.3.9',
        client: MockClient((_) async => http.Response('{}', status)),
      );
      expect(await service.checkForUpdate(), isNull);
      expect(service.lastError, isNotNull);
      expect(service.hasUpdate, isFalse);
    });
  }

  for (final body in ['bad-json', '{}', '[]']) {
    test('malformed response $body is a failure', () async {
      final service = VersionService.forTesting(
        loadVersion: () async => '1.3.9',
        client: MockClient(
          (_) async => http.Response(
            body,
            200,
            headers: {'content-type': 'application/json; charset=utf-8'},
          ),
        ),
      );
      expect(await service.checkForUpdate(), isNull);
      expect(service.lastError, isNotNull);
    });
  }

  test('timeout is a failure', () async {
    final service = VersionService.forTesting(
      loadVersion: () async => '1.3.9',
      client: MockClient((_) => Future.error(TimeoutException('timeout'))),
    );
    expect(await service.checkForUpdate(), isNull);
    expect(service.lastError, isNotNull);
  });

  test('unknown installed version does not guess or request', () async {
    var requests = 0;
    final service = VersionService.forTesting(
      loadVersion: () async => throw StateError('unavailable'),
      client: MockClient((_) async {
        requests++;
        return http.Response('{}', 500);
      }),
    );
    expect(await service.checkForUpdate(), isNull);
    expect(service.currentVersion, '未知');
    expect(service.lastError, isNotNull);
    expect(requests, 0);
  });

  test('equal or older release does not offer downgrade', () async {
    for (final installed in ['1.4.0', '1.4.0+99', '1.5.0']) {
      final service = VersionService.forTesting(
        loadVersion: () async => installed,
        client: MockClient(
          (_) async => http.Response(
            jsonEncode(releaseJson()),
            200,
            headers: {'content-type': 'application/json; charset=utf-8'},
          ),
        ),
      );
      expect(await service.checkForUpdate(), isNotNull);
      expect(service.hasUpdate, isFalse);
      expect(service.lastError, isNull);
    }
  });
}
