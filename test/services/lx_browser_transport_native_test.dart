import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:cyrene_music/services/lx_quickjs_runtime.dart';
import 'package:cyrene_music/services/resolution_request.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'switching during fetch discards old callbacks and keeps new source usable',
    () async {
      final overrides = HttpOverrides.current;
      HttpOverrides.global = null;
      addTearDown(() => HttpOverrides.global = overrides);
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final runtime = LxQuickJsRuntime();
      final received = StreamController<HttpRequest>();
      server.listen(received.add);
      final requests = StreamIterator(received.stream);
      addTearDown(() async {
        await runtime.dispose();
        await requests.cancel();
        await received.close();
        await server.close(force: true);
      });
      for (var i = 0; i < 5; i++) {
        await runtime.loadScript('''
        lx.on(lx.EVENT_NAMES.request, async () => {
          const response = await fetch('http://127.0.0.1:${server.port}/');
          await response.text();
          throw new Error('stale callback executed');
        });
        lx.send(lx.EVENT_NAMES.inited, {sources: {tx: {qualitys: ['128k']}}});
      ''');
        final pending = runtime.getMusicUrl(
          source: 'tx',
          songId: 'old',
          quality: '128k',
        );
        final cancelled = expectLater(
          pending,
          throwsA(isA<ResolutionCancelled>()),
        );
        expect(
          await requests.moveNext().timeout(const Duration(seconds: 3)),
          isTrue,
        );
        final request = requests.current;
        await runtime.loadScript('''
        lx.on(lx.EVENT_NAMES.request, () => 'https://example.com/new.mp3');
        lx.send(lx.EVENT_NAMES.inited, {sources: {tx: {qualitys: ['128k']}}});
      ''');
        request.response.write('late response');
        await request.response.close();
        await cancelled;
        expect(
          await runtime.getMusicUrl(
            source: 'tx',
            songId: 'new',
            quality: '128k',
          ),
          'https://example.com/new.mp3',
        );
      }
      await Future<void>.delayed(const Duration(milliseconds: 100));
    },
    skip: Platform.environment['CYRENE_LX_NATIVE_TEST'] != '1',
  );
  test(
    'fetch preserves HTTP errors, UTF-8 and literal response text',
    () async {
      final overrides = HttpOverrides.current;
      HttpOverrides.global = null;
      addTearDown(() => HttpOverrides.global = overrides);
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      const body = '中文 ` \${notJavascript}';
      server.listen((request) async {
        request.response.statusCode = 520;
        request.response.headers.set('content-type', 'text/plain');
        request.response.headers.set('x-test', 'preserved');
        request.response.add(utf8.encode(body));
        await request.response.close();
      });
      final runtime = LxQuickJsRuntime();
      addTearDown(() async {
        await runtime.dispose();
        await server.close(force: true);
      });
      await runtime.loadScript('''
      lx.on(lx.EVENT_NAMES.request, async () => {
        const response = await fetch('http://127.0.0.1:${server.port}/');
        const text = await response.text();
        if (response.status !== 520 || response.ok ||
            response.headers.get('x-test') !== 'preserved' ||
            text !== ${jsonEncode(body)}) throw new Error('response corrupted');
        return 'https://example.com/verified.mp3';
      });
      lx.send(lx.EVENT_NAMES.inited, {sources: {tx: {qualitys: ['128k']}}});
    ''');
      expect(
        await runtime.getMusicUrl(source: 'tx', songId: '1', quality: '128k'),
        'https://example.com/verified.mp3',
      );
    },
    skip: Platform.environment['CYRENE_LX_NATIVE_TEST'] != '1',
  );
}
