import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:cyrene_music/services/lx_quickjs_runtime.dart';
import 'package:cyrene_music/services/resolution_request.dart';
import 'package:flutter_test/flutter_test.dart';

// Requires the flutter_js native library on PATH; opted into by native CI.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'real QuickJS abort releases serialization and isolates late responses',
    () async {
      final overrides = HttpOverrides.current;
      HttpOverrides.global = null;
      addTearDown(() => HttpOverrides.global = overrides);
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final slowSeen = Completer<void>();
      final requests = <String>[];
      final subscription = server.listen((request) async {
        requests.add(request.uri.path);
        if (request.uri.path == '/slow') {
          if (!slowSeen.isCompleted) slowSeen.complete();
          return;
        }
        request.response.write(
          jsonEncode({'url': 'https://example.com/new.mp3'}),
        );
        await request.response.close();
      });
      final runtime = LxQuickJsRuntime();
      addTearDown(() async {
        await runtime.dispose();
        await subscription.cancel();
        await server.close(force: true);
      });
      await runtime.loadScript('''
      lx.on(lx.EVENT_NAMES.request, async ({info}) => {
        if (info.musicInfo.songmid === 'stubborn') {
          await new Promise(resolve => {
            lx.request('http://127.0.0.1:${server.port}/slow', {}, err => {
              if (!err) resolve();
            });
          });
          return 'unused';
        }
        const response = await lx.request('http://127.0.0.1:${server.port}/' + info.musicInfo.songmid, {});
        return JSON.parse(response.body).url;
      });
      lx.send(lx.EVENT_NAMES.inited, {sources: {tx: {qualitys: ['128k']}}});
    ''');
      final owner = ResolutionRequest();
      final old = owner.run(
        () =>
            runtime.getMusicUrl(source: 'tx', songId: 'slow', quality: '128k'),
      );
      final cancelled = expectLater(old, throwsA(isA<ResolutionCancelled>()));
      await slowSeen.future.timeout(const Duration(seconds: 2));
      owner.cancel();
      final url = await runtime
          .getMusicUrl(source: 'tx', songId: 'new', quality: '128k')
          .timeout(const Duration(seconds: 2));
      await cancelled;
      expect(url, 'https://example.com/new.mp3');
      expect(requests, ['/slow', '/new']);
      // A black-box script that ignores cancellation must not poison the next
      // operation. This exercises the actual context-rebuild fallback.
      final stubbornOwner = ResolutionRequest();
      final stubborn = stubbornOwner.run(
        () => runtime.getMusicUrl(
          source: 'tx',
          songId: 'stubborn',
          quality: '128k',
        ),
      );
      final stubbornCancelled = expectLater(
        stubborn,
        throwsA(isA<ResolutionCancelled>()),
      );
      while (requests.length < 3) {
        await Future<void>.delayed(const Duration(milliseconds: 5));
      }
      stubbornOwner.cancel();
      expect(
        await runtime
            .getMusicUrl(source: 'tx', songId: 'recovered', quality: '128k')
            .timeout(const Duration(seconds: 2)),
        'https://example.com/new.mp3',
      );
      await stubbornCancelled;
      expect(runtime.isScriptReady, isTrue);
    },
    skip: Platform.environment['CYRENE_LX_NATIVE_TEST'] != '1',
  );
}
