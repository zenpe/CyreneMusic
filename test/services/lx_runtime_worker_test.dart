import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:cyrene_music/services/lx_quickjs_runtime.dart';
import 'package:cyrene_music/services/lx_runtime_interface.dart';
import 'package:cyrene_music/services/resolution_request.dart';
import 'package:cyrene_music/services/structured_log_service.dart';
import 'package:flutter_test/flutter_test.dart';

const _init =
    "lx.send(lx.EVENT_NAMES.inited, {sources: {tx: {qualitys: ['128k']}}});";
const _counterScript =
    '''
  let calls = 0;
  lx.on(lx.EVENT_NAMES.request, ({info}) => {
    const call = ++calls;
    return new Promise(resolve => setTimeout(() => resolve('https://example.com/' + call + '.mp3'),
      info.musicInfo.songmid === 'slow' ? 200 : 1));
  });
  $_init
''';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final native = Platform.environment['CYRENE_LX_NATIVE_TEST'] == '1';
  setUp(() {
    StructuredLogService.sink = (_) {};
  });
  tearDown(() {
    StructuredLogService.sink = null;
  });

  Future<String?> resolve(
    LxQuickJsRuntime host,
    String id, {
    Duration? timeout,
  }) => host.getMusicUrl(
    source: 'tx',
    songId: id,
    quality: '128k',
    timeout: timeout,
  );
  Future<void> startSlow(
    LxQuickJsRuntime host,
    Future<String?> Function() start,
    void Function(Future<String?>) observe,
  ) async {
    final started = Completer<void>();
    StructuredLogService.sink = (line) {
      if (jsonDecode(line)['event'] == 'lx.music_url_started' &&
          !started.isCompleted) {
        started.complete();
      }
    };
    observe(start());
    await started.future.timeout(const Duration(seconds: 3));
  }

  test(
    'CPU-heavy initialization and resolution leave UI event loop responsive',
    () async {
      final host = LxQuickJsRuntime(executionTurn: const Duration(seconds: 1));
      addTearDown(host.dispose);
      var ticks = 0;
      final timer = Timer.periodic(
        const Duration(milliseconds: 20),
        (_) => ticks++,
      );
      addTearDown(timer.cancel);
      await host.loadScript('''
      const end = Date.now() + 350; while (Date.now() < end) {}
      lx.on(lx.EVENT_NAMES.request, () => {
        const until = Date.now() + 350; while (Date.now() < until) {}
        return 'https://example.com/cpu.mp3';
      }); $_init
    ''');
      expect(ticks, greaterThanOrEqualTo(5));
      ticks = 0;
      expect(await resolve(host, 'cpu'), 'https://example.com/cpu.mp3');
      expect(ticks, greaterThanOrEqualTo(5));
    },
    skip: !native,
  );

  for (final expire in [false, true]) {
    test(
      'queued ${expire ? 'expiry' : 'cancellation'} preserves running context and cache',
      () async {
        final host = LxQuickJsRuntime();
        addTearDown(host.dispose);
        await host.loadScript(_counterScript);
        late Future<String?> slow;
        await startSlow(
          host,
          () => resolve(host, 'slow'),
          (future) => slow = future,
        );
        final owner = ResolutionRequest();
        final queued = owner.run(
          () => resolve(
            host,
            'queued',
            timeout: expire ? const Duration(milliseconds: 20) : null,
          ),
        );
        if (expire) {
          expect(await queued, isNull);
          expect(owner.failure?.kind, LxRuntimeFailureKind.timeout);
        } else {
          final check = expectLater(
            queued,
            throwsA(isA<ResolutionCancelled>()),
          );
          owner.cancel();
          await check;
        }
        expect(await slow, 'https://example.com/1.mp3');
        expect(await resolve(host, 'next'), 'https://example.com/2.mp3');
      },
      skip: !native,
    );
  }

  test(
    'foreground overtakes queued preload without dropping script state',
    () async {
      final host = LxQuickJsRuntime();
      addTearDown(host.dispose);
      await host.loadScript(_counterScript);
      late Future<String?> slow;
      await startSlow(
        host,
        () => resolve(host, 'slow'),
        (future) => slow = future,
      );
      final preload = ResolutionRequest.inContext(
        purpose: 'preload',
        action: () {
          final owner = ResolutionRequest();
          return owner.run(() => resolve(host, 'preload'));
        },
      );
      final foreground = resolve(host, 'foreground');
      expect(await slow, 'https://example.com/1.mp3');
      expect(await foreground, 'https://example.com/2.mp3');
      expect(await preload, 'https://example.com/3.mp3');
    },
    skip: !native,
  );

  test('running cancellation discards context before the next request', () async {
    final host = LxQuickJsRuntime();
    addTearDown(host.dispose);
    await host.loadScript(_counterScript);
    final owner = ResolutionRequest();
    late Future<void> cancelled;
    await startSlow(
      host,
      () => owner.run(() => resolve(host, 'slow')),
      (future) =>
          cancelled = expectLater(future, throwsA(isA<ResolutionCancelled>())),
    );
    owner.cancel();
    expect(await resolve(host, 'next'), 'https://example.com/1.mp3');
    await cancelled;
    // The old timer would have resolved by now, but cannot mutate the new cache.
    await Future<void>.delayed(const Duration(milliseconds: 220));
    expect(await resolve(host, 'again'), 'https://example.com/2.mp3');
  }, skip: !native);

  test(
    'synchronous crypto bridge and asynchronous zlib preserve binary slices',
    () async {
      final host = LxQuickJsRuntime();
      addTearDown(host.dispose);
      final vectors =
          jsonDecode(
                File('test/support/lx_utils_vectors.json').readAsStringSync(),
              )
              as Map;
      await host.loadScript('''
      lx.on(lx.EVENT_NAMES.request, async () => {
        const vectors = ${jsonEncode(vectors)};
        const b = lx.utils.buffer, c = lx.utils.crypto;
        function slice(value) {
          const bytes = b.from(value, 'base64');
          const padded = new Uint8Array(bytes.length + 4); padded.set(bytes, 2);
          return padded.subarray(2, padded.length - 2);
        }
        for (const v of vectors.aes) {
          if (b.bufToString(c.aesEncrypt(slice(v.data), v.mode, slice(v.key), slice(v.iv)), 'base64') !== v.value) throw Error('AES mismatch');
        }
        for (const v of vectors.rsa) {
          if (b.bufToString(c.rsaEncrypt(slice(v.data), v.key), 'base64') !== v.value) throw Error('RSA mismatch');
        }
        const z = lx.utils.zlib;
        if (b.bufToString(await z.inflate(slice(vectors.zlib.compressed)), 'base64') !== vectors.zlib.data) throw Error('inflate mismatch');
        const encoded = await z.deflate(slice(vectors.zlib.data));
        if (b.bufToString(await z.inflate(encoded), 'base64') !== vectors.zlib.data) throw Error('deflate mismatch');
        if (c.randomBytes(16).length !== 16) throw Error('random bytes');
        return 'https://example.com/compatible.mp3';
      }); $_init
    ''');
      expect(
        await resolve(host, 'utils'),
        'https://example.com/compatible.mp3',
        reason: host.lastFailure?.message,
      );
    },
    skip: !native,
  );

  test(
    'immediate script rejection is observed before microtask drain completes',
    () async {
      final host = LxQuickJsRuntime();
      addTearDown(host.dispose);
      await host.loadScript('''
      lx.on(lx.EVENT_NAMES.request, async ({info}) => {
        if (info.musicInfo.songmid === 'bad') throw new Error('script failure');
        return 'https://example.com/good.mp3';
      }); $_init
    ''');
      expect(await resolve(host, 'bad'), isNull);
      expect(host.lastFailure?.kind, LxRuntimeFailureKind.requestFailed);
      expect(await resolve(host, 'good'), 'https://example.com/good.mp3');
    },
    skip: !native,
  );

  test(
    'transport evidence survives await and stays distinct from script failure',
    () async {
      final socket = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      final port = socket.port;
      await socket.close();
      final host = LxQuickJsRuntime();
      addTearDown(host.dispose);
      await host.loadScript('''
      lx.on(lx.EVENT_NAMES.request, async () => {
        const result = await lx.request('http://127.0.0.1:$port/refused', {});
        return result.body;
      }); $_init
    ''');
      expect(await resolve(host, 'connect'), isNull);
      expect(host.lastFailure?.kind, LxRuntimeFailureKind.transientNetwork);
    },
    skip: !native,
  );

  test(
    'disposing during async initialization exits cleanly and can restart',
    () async {
      final host = LxQuickJsRuntime();
      addTearDown(host.dispose);
      final loading = host.loadScript('setTimeout(() => {}, 60000);');
      await Future<void>.delayed(const Duration(milliseconds: 100));
      await host.dispose().timeout(const Duration(seconds: 2));
      expect(await loading, isNull);
      expect(host.isInitialized, isFalse);
      expect(host.isScriptReady, isFalse);
      await host.loadScript(_counterScript);
      expect(await resolve(host, 'restart'), 'https://example.com/1.mp3');
    },
    skip: !native,
  );

  test(
    'native contexts execute concurrently without sharing callbacks or budgets',
    () async {
      final hosts = List.generate(3, (_) => LxQuickJsRuntime());
      addTearDown(() => Future.wait(hosts.map((host) => host.dispose())));
      await Future.wait(
        hosts.indexed.map((entry) async {
          final (index, host) = entry;
          await host.loadScript('''
        const end = Date.now() + 150; while (Date.now() < end) {}
        lx.on(lx.EVENT_NAMES.request, async () => {
          await new Promise(resolve => setTimeout(resolve, 10));
          const until = Date.now() + 150; while (Date.now() < until) {}
          return 'https://example.com/context-$index.mp3';
        }); $_init
      ''');
          expect(
            await resolve(host, 'cpu'),
            'https://example.com/context-$index.mp3',
          );
        }),
      );
    },
    skip: !native,
  );

  test(
    'successful resolution retains settlement of background HTTP after its deadline',
    () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final subscription = server.listen((_) {});
      final host = LxQuickJsRuntime();
      addTearDown(() async {
        await host.dispose();
        await subscription.cancel();
        await server.close(force: true);
      });
      await host.loadScript('''
      let settled = false;
      lx.on(lx.EVENT_NAMES.request, ({info}) => {
        if (info.musicInfo.songmid === 'start') {
          lx.request('http://127.0.0.1:${server.port}/renew', {}, () => settled = true);
          return 'https://example.com/start.mp3';
        }
        return 'https://example.com/' + (settled ? 'settled' : 'pending') + '.mp3';
      }); $_init
    ''');
      expect(
        await resolve(
          host,
          'start',
          timeout: const Duration(milliseconds: 150),
        ),
        'https://example.com/start.mp3',
      );
      await Future<void>.delayed(const Duration(milliseconds: 300));
      expect(await resolve(host, 'check'), 'https://example.com/settled.mp3');
    },
    skip: !native,
  );
}
