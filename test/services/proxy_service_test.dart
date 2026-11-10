import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:cyrene_music/services/proxy_service.dart';
import 'package:cyrene_music/services/playback/audio_transport_failure.dart';
import 'package:cyrene_music/services/structured_log_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late ProxyService proxy;
  late HttpServer origin;
  late HttpClient client;
  late Future<void> Function(HttpRequest) respond;
  final requests = <HttpRequest>[];
  final logs = <String>[];
  setUp(() async {
    requests.clear();
    logs.clear();
    StructuredLogService.sink = logs.add;
    proxy = ProxyService.forTesting(
      headerTimeout: const Duration(milliseconds: 150),
      idleTimeout: const Duration(milliseconds: 150),
    );
    origin = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    respond = (request) async {
      request.response.write('audio');
      await request.response.close();
    };
    origin.listen((request) {
      requests.add(request);
      unawaited(respond(request).catchError((Object _) {}));
    });
    client = HttpClient();
    expect(await proxy.start(), isTrue);
  });
  tearDown(() async {
    client.close(force: true);
    await proxy.stop();
    await origin.close(force: true);
    StructuredLogService.sink = null;
  });
  String route([String path = '/audio?vkey=private-test']) =>
      proxy.getProxyUrl('http://127.0.0.1:${origin.port}$path', 'qq');
  Future<HttpClientResponse> get(String url) async =>
      (await client.getUrl(Uri.parse(url))).close();

  test(
    'stop wins over an in-flight start and no listener is resurrected',
    () async {
      await proxy.stop();
      final starting = proxy.start();
      final stopping = proxy.stop();
      await Future.wait([starting, stopping]);
      expect(proxy.isRunning, isFalse);
      expect(await proxy.start(), isTrue);
      expect(await utf8.decodeStream(await get(route())), 'audio');
    },
  );

  test(
    'concurrent startup has one loopback listener; restart invalidates routes',
    () async {
      final old = route();
      final port = proxy.port;
      expect(
        await Future.wait(List.generate(8, (_) => proxy.start())),
        everyElement(isTrue),
      );
      expect(proxy.port, port);
      final uri = Uri.parse(old);
      expect(uri.host, '127.0.0.1');
      expect(uri.query, isEmpty);
      await proxy.stop();
      expect(await proxy.start(), isTrue);
      final stale = uri.replace(port: proxy.port).toString();
      expect((await get(stale)).statusCode, 410);
      final fresh = await get(route());
      expect(await utf8.decodeStream(fresh), 'audio');
    },
  );

  test(
    'Range and HEAD preserve bytes and headers without forwarding credentials',
    () async {
      respond = (request) async {
        request.response.statusCode = 206;
        request.response.headers.set('content-range', 'bytes 1-3/5');
        request.response.headers.set('accept-ranges', 'bytes');
        request.response.contentLength = 3;
        if (request.method != 'HEAD') request.response.add([1, 2, 3]);
        await request.response.close();
      };
      final url = route();
      final request = await client.getUrl(Uri.parse(url));
      request.headers.set('range', 'bytes=1-3');
      request.headers.set('authorization', 'private-auth');
      final response = await request.close();
      expect(response.statusCode, 206);
      expect(response.headers.value('content-range'), 'bytes 1-3/5');
      expect(await response.expand((bytes) => bytes).toList(), [1, 2, 3]);
      expect(requests.single.headers.value('range'), 'bytes=1-3');
      expect(requests.single.headers.value('referer'), 'https://y.qq.com/');
      expect(requests.single.headers.value('authorization'), isNull);
      final head = await (await client.headUrl(Uri.parse(url))).close();
      expect(head.statusCode, 206);
      expect(head.contentLength, 3);
      expect(await head.expand((b) => b).toList(), isEmpty);
    },
  );

  for (final status in [401, 403, 404, 410, 429, 503]) {
    test('HTTP $status remains attributable to only its source', () async {
      respond = (r) async {
        r.response.statusCode = status;
        await r.response.close();
      };
      final failed = route();
      final next = route();
      final response = await get(failed);
      await response.drain<void>();
      expect(response.statusCode, status);
      expect(proxy.failureFor(failed)?.statusCode, status);
      expect(proxy.failureFor(next), isNull);
      expect(logs.join(), isNot(contains('private-test')));
      expect(logs.join(), contains('audio_proxy.failed'));
      proxy.release(failed);
      expect(proxy.failureFor(failed), isNull);
      respond = (r) async {
        r.response.write('recovered');
        await r.response.close();
      };
      expect(await utf8.decodeStream(await get(next)), 'recovered');
    });
  }

  test('hung response headers time out and a later song still works', () async {
    final gate = Completer<void>();
    respond = (_) => gate.future;
    final url = route();
    final response = await get(url).timeout(const Duration(seconds: 2));
    await response.drain<void>();
    expect(response.statusCode, 504);
    expect(proxy.failureFor(url)?.timedOut, isTrue);
    expect(proxy.failureFor(url)?.stage, AudioTransportStage.connect);
    gate.complete();
    respond = (r) async {
      r.response.write('next');
      await r.response.close();
    };
    expect(await utf8.decodeStream(await get(route())), 'next');
  });

  test('idle audio read terminates and records the read stage', () async {
    final gate = Completer<void>();
    respond = (r) async {
      r.response.bufferOutput = false;
      r.response.add([1, 2]);
      await r.response.flush();
      await gate.future;
    };
    final url = route();
    final response = await get(url);
    try {
      await response.drain<void>().timeout(const Duration(seconds: 2));
    } on HttpException {
      /* truncated stream */
    }
    expect(proxy.failureFor(url)?.timedOut, isTrue);
    expect(proxy.failureFor(url)?.stage, AudioTransportStage.read);
    gate.complete();
  });

  test(
    'release cancels outstanding connection without poisoning the next route',
    () async {
      final started = Completer<void>();
      final gate = Completer<void>();
      respond = (_) async {
        started.complete();
        await gate.future;
      };
      final old = route();
      final pending = get(old)
          .then<void>((r) => r.drain<void>(), onError: (Object _) {});
      await started.future;
      proxy.release(old);
      await pending.timeout(const Duration(seconds: 1));
      expect(proxy.failureFor(old), isNull);
      gate.complete();
      respond = (r) async {
        r.response.write('next');
        await r.response.close();
      };
      expect(await utf8.decodeStream(await get(route())), 'next');
    },
  );

  test(
    'release during an active body stream cannot throw synchronously',
    () async {
      final gate = Completer<void>();
      respond = (request) async {
        request.response.bufferOutput = false;
        request.response.add(List<int>.filled(64 * 1024, 1));
        await request.response.flush();
        await gate.future;
      };
      final old = route();
      final response = await get(old);
      final received = Completer<void>();
      final done = Completer<void>();
      response.listen(
        (_) {
          if (!received.isCompleted) received.complete();
        },
        onError: (Object _) {},
        onDone: done.complete,
      );
      await received.future.timeout(const Duration(seconds: 2));
      expect(() => proxy.release(old), returnsNormally);
      await done.future.timeout(const Duration(seconds: 2));
      expect(proxy.failureFor(old), isNull);
      gate.complete();
      respond = (request) async {
        request.response.write('next');
        await request.response.close();
      };
      expect(await utf8.decodeStream(await get(route())), 'next');
    },
  );

  test(
    'HLS segments, relative key URLs and large manifests retain their parent',
    () async {
      respond = (r) async {
        if (r.uri.path == '/redirect') {
          await r.response.redirect(Uri.parse('/hls/index.m3u8'));
          return;
        }
        if (r.uri.path.endsWith('.m3u8')) {
          r.response.headers.contentType = ContentType(
            'application',
            'vnd.apple.mpegurl',
          );
          r.response.write(
            '#EXTM3U\n#EXT-X-KEY:METHOD=AES-128,URI="key.bin"\n',
          );
          r.response.write(
            List.generate(300, (i) => 'segment$i.ts').join('\n'),
          );
        } else {
          r.response.write('segment');
        }
        await r.response.close();
      };
      final root = route('/redirect');
      final manifest = await utf8.decodeStream(await get(root));
      final child = manifest.split('\n').last;
      expect(manifest, isNot(contains('key.bin')));
      expect(await utf8.decodeStream(await get(child)), 'segment');
      expect(requests.last.uri.path, '/hls/segment299.ts');
      expect(await utf8.decodeStream(await get(root)), manifest);
      proxy.release(root);
      expect((await get(child)).statusCode, 410);
    },
  );
}
