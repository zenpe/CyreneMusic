import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:cyrene_music/services/lx_quickjs_runtime.dart';
import 'package:cyrene_music/services/lx_runtime_interface.dart';
import 'package:cyrene_music/services/resolution_request.dart';
import 'package:cyrene_music/services/structured_log_service.dart';
import 'package:flutter_test/flutter_test.dart';

// Requires the flutter_js native library on PATH; opted into by native CI.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'native callback preserves JSON and failures retain safe HTTP facts',
    () async {
      final overrides = HttpOverrides.current;
      HttpOverrides.global = null;
      addTearDown(() => HttpOverrides.global = overrides);
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final subscription = server.listen((request) async {
        request.response.write(
          jsonEncode({'code': 200, 'url': 'https://example.invalid/audio.mp3'}),
        );
        await request.response.close();
      });
      final events = <Map<String, dynamic>>[];
      StructuredLogService.sink = (line) =>
          events.add(jsonDecode(line) as Map<String, dynamic>);
      final runtime = LxQuickJsRuntime();
      addTearDown(() async {
        StructuredLogService.sink = null;
        await runtime.dispose();
        await subscription.cancel();
        await server.close(force: true);
      });
      await runtime.loadScript('''
      lx.on(lx.EVENT_NAMES.request, ({info}) => new Promise((resolve, reject) => {
        lx.request('http://127.0.0.1:${server.port}/music', {}, (err, resp, body) => {
          if (err) return reject(err);
          if (body !== resp.body || body.code !== 200) return reject(new Error('body contract'));
          if (info.musicInfo.songmid === 'bad') return reject(new Error('script rejected result'));
          resolve(body.url);
        });
      }));
      lx.send(lx.EVENT_NAMES.inited, {sources: {wy: {qualitys: ['128k']}}});
    ''');
      expect(
        await runtime.getMusicUrl(
          source: 'wy',
          songId: 'good',
          quality: '128k',
        ),
        'https://example.invalid/audio.mp3',
      );
      expect(
        await runtime.getMusicUrl(source: 'wy', songId: 'bad', quality: '128k'),
        isNull,
      );
      final failure = events.lastWhere(
        (event) => event['event'] == 'lx.music_url_failed',
      );
      expect(failure['last_http_status'], 200);
      expect(failure['last_body_type'], 'object');
      expect(failure['last_business_code'], 200);
      expect(jsonEncode(failure), isNot(contains('audio.mp3')));
    },
    skip: Platform.environment['CYRENE_LX_NATIVE_TEST'] != '1',
  );
  test(
    'outer deadline abort retains HTTP phase and warning diagnostics',
    () async {
      final overrides = HttpOverrides.current;
      HttpOverrides.global = null;
      addTearDown(() => HttpOverrides.global = overrides);
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final seen = Completer<void>();
      final ended = Completer<Map<String, dynamic>>();
      StructuredLogService.sink = (line) {
        final event = jsonDecode(line) as Map<String, dynamic>;
        if (event['event'] == 'lx.http_transport_ended' && !ended.isCompleted) {
          ended.complete(event);
        }
      };
      final subscription = server.listen((request) => seen.complete());
      final runtime = LxQuickJsRuntime();
      addTearDown(() async {
        StructuredLogService.sink = null;
        await runtime.dispose();
        await subscription.cancel();
        await server.close(force: true);
      });
      await runtime.loadScript('''
        lx.on(lx.EVENT_NAMES.request, async () => {
          const response = await lx.request('http://127.0.0.1:${server.port}/slow', {});
          return response.body.url;
        });
        lx.send(lx.EVENT_NAMES.inited, {sources: {tx: {qualitys: ['128k']}}});
      ''');
      final owner = ResolutionRequest();
      final cancelled = expectLater(
        owner.run(
          () => runtime.getMusicUrl(
            source: 'tx',
            songId: 'slow',
            quality: '128k',
          ),
        ),
        throwsA(isA<ResolutionCancelled>()),
      );
      await seen.future.timeout(const Duration(seconds: 2));
      owner.failure = const LxRuntimeFailure(
        kind: LxRuntimeFailureKind.timeout,
        message: 'outer deadline',
      );
      owner.cancel();
      await cancelled;
      final event = await ended.future.timeout(const Duration(seconds: 2));
      expect(event['outcome'], 'timeout');
      expect(event['level'], 'warning');
      expect(event['stage'], 'response_headers');
      expect(event['connection_ready'], isTrue);
      expect(event['response_wait_ms'], isNonNegative);
    },
    skip: Platform.environment['CYRENE_LX_NATIVE_TEST'] != '1',
  );
  test(
    'real QuickJS abort isolates late responses and abandoned promises',
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
        return response.body.url;
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
      // operation or require resetting the shared context.
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

  test(
    'real QuickJS slow HTTP does not block another resolution',
    () async {
      final overrides = HttpOverrides.current;
      HttpOverrides.global = null;
      addTearDown(() => HttpOverrides.global = overrides);
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final slowSeen = Completer<void>();
      final releaseSlow = Completer<void>();
      final paths = <String>[];
      final subscription = server.listen((request) async {
        paths.add(request.uri.path);
        if (request.uri.path == '/slow') {
          slowSeen.complete();
          await releaseSlow.future;
        }
        request.response.write(
          jsonEncode({'url': 'https://example.com${request.uri.path}.mp3'}),
        );
        await request.response.close();
      });
      final runtime = LxQuickJsRuntime();
      addTearDown(() async {
        if (!releaseSlow.isCompleted) releaseSlow.complete();
        await runtime.dispose();
        await subscription.cancel();
        await server.close(force: true);
      });
      await runtime.loadScript('''
      lx.on(lx.EVENT_NAMES.request, async ({info}) => {
        const id = info.musicInfo.songmid;
        const response = await lx.request('http://127.0.0.1:${server.port}/' + id, {});
        // Exercise a second HTTP request after a Promise/timer continuation.
        await new Promise(resolve => setTimeout(resolve, 20));
        return lx.request('http://127.0.0.1:${server.port}/' + id + '-final', {}).then(response => response.body.url);
      });
      lx.send(lx.EVENT_NAMES.inited, {sources: {tx: {qualitys: ['128k']}}});
    ''');
      final slow = runtime.getMusicUrl(
        source: 'tx',
        songId: 'slow',
        quality: '128k',
      );
      await slowSeen.future.timeout(const Duration(seconds: 2));
      final fast = await runtime
          .getMusicUrl(source: 'tx', songId: 'fast', quality: '128k')
          .timeout(const Duration(seconds: 2));
      expect(fast, 'https://example.com/fast-final.mp3');
      expect(paths, ['/slow', '/fast', '/fast-final']);
      releaseSlow.complete();
      expect(await slow, 'https://example.com/slow-final.mp3');
    },
    skip: Platform.environment['CYRENE_LX_NATIVE_TEST'] != '1',
  );

  test(
    'real QuickJS failures stay with their request owner',
    () async {
      final runtime = LxQuickJsRuntime();
      addTearDown(runtime.dispose);
      await runtime.loadScript('''
      lx.on(lx.EVENT_NAMES.request, ({info}) => new Promise((resolve, reject) => {
        setTimeout(() => {
          if (info.musicInfo.songmid === 'bad') reject(new Error('bad track'));
          else resolve('https://example.com/good.mp3');
        }, info.musicInfo.songmid === 'bad' ? 50 : 80);
      }));
      lx.send(lx.EVENT_NAMES.inited, {sources: {tx: {qualitys: ['128k']}}});
    ''');
      final badOwner = ResolutionRequest();
      final goodOwner = ResolutionRequest();
      final results = await Future.wait([
        badOwner.run(
          () =>
              runtime.getMusicUrl(source: 'tx', songId: 'bad', quality: '128k'),
        ),
        goodOwner.run(
          () => runtime.getMusicUrl(
            source: 'tx',
            songId: 'good',
            quality: '128k',
          ),
        ),
      ]);
      expect(results, [null, 'https://example.com/good.mp3']);
      expect(badOwner.failure?.message, contains('bad track'));
      expect(goodOwner.failure, isNull);
    },
    skip: Platform.environment['CYRENE_LX_NATIVE_TEST'] != '1',
  );
  test(
    'real QuickJS cancelling one timer does not cancel another resolution',
    () async {
      final runtime = LxQuickJsRuntime();
      addTearDown(runtime.dispose);
      await runtime.loadScript('''
        lx.on(lx.EVENT_NAMES.request, ({info}) => new Promise(resolve => {
          setTimeout(() => resolve('https://example.com/' + info.musicInfo.songmid + '.mp3'), 100);
        }));
        lx.send(lx.EVENT_NAMES.inited, {sources: {tx: {qualitys: ['128k']}}});
      ''');
      final owner = ResolutionRequest();
      final old = owner.run(
        () => runtime.getMusicUrl(source: 'tx', songId: 'old', quality: '128k'),
      );
      final cancelled = expectLater(old, throwsA(isA<ResolutionCancelled>()));
      final current = runtime.getMusicUrl(
        source: 'tx',
        songId: 'current',
        quality: '128k',
      );
      await Future<void>.delayed(const Duration(milliseconds: 30));
      owner.cancel();
      expect(await current, 'https://example.com/current.mp3');
      await cancelled;
      expect(runtime.isScriptReady, isTrue);
    },
    skip: Platform.environment['CYRENE_LX_NATIVE_TEST'] != '1',
  );

  test(
    'real QuickJS source replacement cancels all old resolutions',
    () async {
      final runtime = LxQuickJsRuntime();
      addTearDown(runtime.dispose);
      await runtime.loadScript('''
      lx.on(lx.EVENT_NAMES.request, () => new Promise(resolve => {
        setTimeout(() => resolve('https://example.com/old.mp3'), 1000);
      }));
      lx.send(lx.EVENT_NAMES.inited, {sources: {tx: {qualitys: ['128k']}}});
    ''');
      final first = runtime.getMusicUrl(
        source: 'tx',
        songId: '1',
        quality: '128k',
      );
      final second = runtime.getMusicUrl(
        source: 'tx',
        songId: '2',
        quality: '128k',
      );
      final checks = [
        expectLater(first, throwsA(isA<ResolutionCancelled>())),
        expectLater(second, throwsA(isA<ResolutionCancelled>())),
      ];
      await Future<void>.delayed(const Duration(milliseconds: 20));
      await runtime.loadScript('''
      lx.on(lx.EVENT_NAMES.request, () => 'https://example.com/replaced.mp3');
      lx.send(lx.EVENT_NAMES.inited, {sources: {tx: {qualitys: ['128k']}}});
    ''');
      await Future.wait(checks);
      expect(
        await runtime.getMusicUrl(source: 'tx', songId: '3', quality: '128k'),
        'https://example.com/replaced.mp3',
      );
    },
    skip: Platform.environment['CYRENE_LX_NATIVE_TEST'] != '1',
  );

  test(
    'real QuickJS admission is bounded and capacity returns after completion',
    () async {
      final runtime = LxQuickJsRuntime();
      addTearDown(runtime.dispose);
      await runtime.loadScript('''
        let calls = 0;
        lx.on(lx.EVENT_NAMES.request, () => new Promise(resolve => {
          const call = ++calls;
          setTimeout(() => resolve('https://example.com/' + call + '.mp3'), 100);
        }));
        lx.send(lx.EVENT_NAMES.inited, {sources: {tx: {qualitys: ['128k']}}});
      ''');
      final active = List.generate(
        4,
        (i) => runtime.getMusicUrl(source: 'tx', songId: '$i', quality: '128k'),
      );
      final excessOwner = ResolutionRequest();
      expect(
        await excessOwner.run(
          () => runtime.getMusicUrl(
            source: 'tx',
            songId: 'excess',
            quality: '128k',
          ),
        ),
        isNull,
      );
      expect(excessOwner.failure?.message, contains('通道繁忙'));
      expect(
        await Future.wait(active),
        List.generate(4, (i) => 'https://example.com/${i + 1}.mp3'),
      );
      expect(
        await runtime.getMusicUrl(
          source: 'tx',
          songId: 'retry',
          quality: '128k',
        ),
        'https://example.com/5.mp3',
      );
    },
    skip: Platform.environment['CYRENE_LX_NATIVE_TEST'] != '1',
  );
}
