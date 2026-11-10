import 'dart:async';
import 'dart:convert';

import 'package:cyrene_music/models/version_info.dart';
import 'package:cyrene_music/services/version_service.dart';
import 'package:cyrene_music/utils/theme_manager.dart';
import 'package:cyrene_music/widgets/client_update_section.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluent_ui/fluent_ui.dart' as fluent;
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../services/version_service_test.dart' show releaseJson;

class _DelayedIgnoreService extends VersionService {
  final saved = Completer<void>();
  int writes = 0;

  _DelayedIgnoreService()
    : super.forTesting(
        client: MockClient((_) async => http.Response('{}', 500)),
        loadVersion: () async => '1.3.9',
      );

  @override
  Future<void> ignoreCurrentVersion(String version) {
    writes++;
    return saved.future;
  }
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  Future<void> mount(
    WidgetTester tester,
    VersionService service, {
    VersionInfo? release,
    Future<bool> Function(Uri)? openBrowser,
    bool fluentTheme = false,
    bool section = false,
  }) async {
    ThemeManager().setThemeFramework(
      fluentTheme ? ThemeFramework.fluent : ThemeFramework.material,
    );
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: const [fluent.FluentLocalizations.delegate],
        builder: (context, child) => fluentTheme
            ? fluent.FluentTheme(data: fluent.FluentThemeData(), child: child!)
            : child!,
        home: Scaffold(
          body: section
              ? ClientUpdateSection(service: service)
              : ClientUpdateDialog(
                  service: service,
                  release: release,
                  openBrowser: openBrowser,
                ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  for (final fluentTheme in [false, true]) {
    testWidgets(
      'browser download only; complete Windows ZIP instructions ($fluentTheme)',
      (tester) async {
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
        final release = await service.checkForUpdate();
        final urls = <Uri>[];
        await mount(
          tester,
          service,
          release: release,
          fluentTheme: fluentTheme,
          openBrowser: (url) async {
            urls.add(url);
            return true;
          },
        );
        expect(find.text('发现新版本 1.4.0'), findsOneWidget);
        expect(find.textContaining('压缩包全部内容'), findsOneWidget);
        expect(urls, isEmpty);
        await tester.tap(find.text('浏览器下载'));
        await tester.pumpAndSettle();
        expect(
          urls.single.toString(),
          release!.platformDownloadUrl('windows-x64'),
        );
        expect(find.textContaining('更新已完成'), findsNothing);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('manual failure offers retry and release page, never latest', (
    tester,
  ) async {
    var requests = 0;
    final service = VersionService.forTesting(
      loadVersion: () async => '1.3.9',
      client: MockClient((_) async {
        requests++;
        return requests == 1
            ? http.Response('{}', 404)
            : http.Response(
                jsonEncode(releaseJson(tag: 'v1.3.9')),
                200,
                headers: {'content-type': 'application/json; charset=utf-8'},
              );
      }),
    );
    final urls = <Uri>[];
    await mount(
      tester,
      service,
      openBrowser: (url) async {
        urls.add(url);
        return true;
      },
    );
    expect(find.text('检查失败'), findsOneWidget);
    expect(find.text('当前已是最新版本'), findsNothing);
    await tester.tap(find.text('发行页'));
    await tester.pumpAndSettle();
    expect(urls.single.toString(), VersionInfo.latestReleasePage);
    await tester.tap(find.text('重试'));
    await tester.pumpAndSettle();
    expect(find.text('当前已是最新版本'), findsOneWidget);
    expect(requests, 2);
  });

  testWidgets('failed browser launch leaves selectable canonical fallback', (
    tester,
  ) async {
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
    final release = await service.checkForUpdate();
    await mount(
      tester,
      service,
      release: release,
      openBrowser: (_) async => false,
    );
    await tester.tap(find.text('浏览器下载'));
    await tester.pumpAndSettle();
    expect(find.textContaining('无法打开浏览器'), findsOneWidget);
    expect(find.byType(SelectableText), findsOneWidget);
    expect(find.text('发行页'), findsOneWidget);
  });

  testWidgets('unsupported ABI offers release page without guessing package', (
    tester,
  ) async {
    final service = VersionService.forTesting(
      loadVersion: () async => '1.3.9',
      platformKey: 'android-x64',
      client: MockClient(
        (_) async => http.Response(
          jsonEncode(releaseJson()),
          200,
          headers: {'content-type': 'application/json; charset=utf-8'},
        ),
      ),
    );
    final release = await service.checkForUpdate();
    await mount(tester, service, release: release);
    expect(find.text('浏览器下载'), findsNothing);
    expect(find.text('发行页'), findsOneWidget);
    expect(find.textContaining('没有适合当前设备'), findsOneWidget);
  });

  testWidgets('automatic check updates badge without dialog or browser', (
    tester,
  ) async {
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
    await service.initialize();
    await mount(tester, service, section: true);
    await service.checkForUpdate(silent: true);
    await tester.pumpAndSettle();
    expect(find.text('自动检查更新'), findsOneWidget);
    expect(find.textContaining('发现新版本 1.4.0'), findsOneWidget);
    expect(find.byType(ClientUpdateDialog), findsNothing);
    expect(find.text('一键更新'), findsNothing);
  });

  testWidgets('closing check early never pops the next page', (tester) async {
    final response = Completer<http.Response>();
    final service = VersionService.forTesting(
      loadVersion: () async => '1.3.9',
      client: MockClient((_) => response.future),
    );
    await service.initialize();
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () =>
                  showClientUpdateDialog(context, service: service),
              child: const Text('check'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('check'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('关闭'));
    await tester.pumpAndSettle();
    response.complete(
      http.Response(
        jsonEncode(releaseJson()),
        200,
        headers: {'content-type': 'application/json; charset=utf-8'},
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('check'), findsOneWidget);
    expect(find.byType(ClientUpdateDialog), findsNothing);
    expect(tester.takeException(), isNull);
  });
  Future<void> openDelayedIgnoreDialog(
    WidgetTester tester,
    _DelayedIgnoreService service, {
    bool fluentTheme = false,
  }) async {
    ThemeManager().setThemeFramework(
      fluentTheme ? ThemeFramework.fluent : ThemeFramework.material,
    );
    await service.initialize();
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: const [fluent.FluentLocalizations.delegate],
        builder: (context, child) => fluentTheme
            ? fluent.FluentTheme(data: fluent.FluentThemeData(), child: child!)
            : child!,
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              child: const Text('home'),
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (context) => Scaffold(
                    body: TextButton(
                      child: const Text('settings'),
                      onPressed: () => showClientUpdateDialog(
                        context,
                        service: service,
                        release: VersionInfo(
                          version: '1.4.0',
                          changelog: 'notes',
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('home'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('settings'));
    await tester.pumpAndSettle();
  }

  for (final fluentTheme in [false, true]) {
    testWidgets(
      'ignore completion during exit never pops settings ($fluentTheme)',
      (tester) async {
        final service = _DelayedIgnoreService();
        await openDelayedIgnoreDialog(
          tester,
          service,
          fluentTheme: fluentTheme,
        );
        await tester.tap(find.text('忽略此版本'));
        await tester.pump();
        await tester.tap(find.text('稍后'));
        await tester.pump(const Duration(milliseconds: 10));
        service.saved.complete();
        await tester.pumpAndSettle();
        expect(find.text('settings'), findsOneWidget);
        expect(find.byType(ClientUpdateDialog), findsNothing);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'pending ignore rejects duplicate writes and closes only dialog',
    (tester) async {
      final service = _DelayedIgnoreService();
      await openDelayedIgnoreDialog(tester, service);
      await tester.tap(find.text('忽略此版本'));
      await tester.tap(find.text('忽略此版本'));
      expect(service.writes, 1);
      service.saved.complete();
      await tester.pumpAndSettle();
      expect(find.text('settings'), findsOneWidget);
      expect(find.byType(ClientUpdateDialog), findsNothing);
    },
  );

  testWidgets(
    'ignore completion after dismissal does not update disposed state',
    (tester) async {
      final service = _DelayedIgnoreService();
      await openDelayedIgnoreDialog(tester, service);
      await tester.tap(find.text('忽略此版本'));
      await tester.pump();
      Navigator.of(tester.element(find.byType(ClientUpdateDialog))).pop();
      await tester.pumpAndSettle();
      service.saved.complete();
      await tester.pumpAndSettle();
      expect(find.text('settings'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('failed ignore stays on dialog and displays recoverable error', (
    tester,
  ) async {
    final service = _DelayedIgnoreService();
    await openDelayedIgnoreDialog(tester, service);
    await tester.tap(find.text('忽略此版本'));
    await tester.pump();
    service.saved.completeError(StateError('write failed'));
    await tester.pumpAndSettle();
    expect(find.byType(ClientUpdateDialog), findsOneWidget);
    expect(find.text('保存失败，请重试。'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.tap(find.text('稍后'));
    await tester.pumpAndSettle();
    expect(find.text('settings'), findsOneWidget);
  });
}
