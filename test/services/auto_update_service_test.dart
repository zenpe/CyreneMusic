import 'dart:async';
import 'dart:io';

import 'package:cyrene_music/models/version_info.dart';
import 'package:cyrene_music/services/auto_update_service.dart';
import 'package:cyrene_music/services/download_file_writer.dart';
import 'package:cyrene_music/services/update_package_downloader.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:open_filex/open_filex.dart';

void main() {
  test('download URLs retain external hosts and signed query parameters', () {
    const signed = 'https://cdn.example.com/app.apk?token=a%2Fb&x=1';
    expect(
      UpdatePackageDownloader.resolveUrl(
        signed,
        'https://api.example.com',
      ).toString(),
      signed,
    );
    expect(
      UpdatePackageDownloader.resolveUrl(
        'files/app.apk',
        'https://api.example.com/v1',
      ).toString(),
      'https://api.example.com/v1/files/app.apk',
    );
    expect(
      UpdatePackageDownloader.resolveUrl(
        '/app.apk',
        'https://api.example.com/v1',
      ).path,
      '/app.apk',
    );
    for (final invalid in ['', 'file:///tmp/app.apk', 'javascript:alert(1)']) {
      expect(
        () => UpdatePackageDownloader.resolveUrl(
          invalid,
          'https://api.example.com',
        ),
        throwsFormatException,
      );
    }
  });

  late Directory directory;
  late HttpServer server;
  late UpdatePackageDownloader downloader;
  Uri url(String path) => Uri.parse('http://127.0.0.1:${server.port}/$path');
  VersionInfo version(String path) => VersionInfo(
    version: '99.0.0',
    changelog: '',
    forceUpdate: false,
    downloadUrl: url(path).toString(),
  );

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('cyrene_update_test_');
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    downloader = UpdatePackageDownloader(
      writer: DownloadFileWriter(
        connectionTimeout: const Duration(seconds: 1),
        idleTimeout: const Duration(milliseconds: 300),
      ),
    );
  });
  tearDown(() async {
    await server.close(force: true);
    await directory.delete(recursive: true);
  });

  for (final stallBody in [false, true]) {
    test(
      'timeout removes incomplete attempt and retry works (body=$stallBody)',
      () async {
        var calls = 0;
        server.listen((request) async {
          if (++calls == 1) {
            if (stallBody) {
              request.response.add([1]);
              await request.response.flush();
            }
            return;
          }
          request.response.add([4, 5, 6]);
          await request.response.close();
        });
        await expectLater(
          downloader.download(url('app.apk'), directory),
          throwsA(isA<TimeoutException>()),
        );
        expect(await directory.list().toList(), isEmpty);
        final file = await downloader.download(url('app.apk'), directory);
        expect(await file.readAsBytes(), [4, 5, 6]);
      },
    );
  }

  for (final platform in [TargetPlatform.android, TargetPlatform.windows]) {
    for (final outcome in [
      ResultType.done,
      ResultType.permissionDenied,
      ResultType.noAppToOpen,
    ]) {
      test(
        '$platform installer $outcome is reported without claiming install success',
        () async {
          server.listen((request) async {
            request.response.add([1, 2, 3]);
            await request.response.close();
          });
          var launched = 0;
          final service = AutoUpdateService.forTesting(
            platform: platform,
            downloadDirectory: () async => directory,
            downloader: downloader,
            openInstaller: (path) async {
              expect(await File(path).readAsBytes(), [1, 2, 3]);
              launched++;
              return OpenResult(type: outcome, message: outcome.name);
            },
          );
          addTearDown(service.dispose);
          await service.startUpdate(
            versionInfo: version(
              platform == TargetPlatform.android ? 'app.apk' : 'setup.exe',
            ),
          );
          expect(launched, 1);
          expect(service.isUpdating, isFalse);
          expect(service.requiresRestart, isFalse);
          expect(service.lastSuccessAt, isNull);
          if (outcome == ResultType.done) {
            expect(service.lastError, isNull);
            expect(service.statusMessage, contains('已打开安装程序'));
          } else {
            expect(service.lastError, isNotNull);
            expect(service.statusMessage, contains('更新失败'));
          }
        },
      );
    }
  }

  test(
    'failed download never launches installer and releases update state',
    () async {
      server.listen((request) async {
        request.response.statusCode = 503;
        await request.response.close();
      });
      final service = AutoUpdateService.forTesting(
        platform: TargetPlatform.android,
        downloadDirectory: () async => directory,
        downloader: downloader,
        openInstaller: (_) async => throw StateError('must not launch'),
      );
      addTearDown(service.dispose);
      await service.startUpdate(versionInfo: version('app.apk'));
      expect(service.isUpdating, isFalse);
      expect(service.lastError, contains('503'));
      expect(await directory.list().toList(), isEmpty);
    },
  );
}
