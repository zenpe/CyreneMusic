import 'dart:async';
import 'dart:io';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:cyrene_music/services/lx_http_bridge.dart';
import 'package:cyrene_music/services/resolution_request.dart';
import 'package:cyrene_music/services/structured_log_service.dart';

void main() {
  setUp(LxHttpBridge.close);
  tearDown(LxHttpBridge.close);

  test('GET and POST retain headers, JSON, form and byte bodies', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final received = <Map<String, Object?>>[];
    final connections = <int>{};
    final subscription = server.listen((request) async {
      connections.add(request.connectionInfo!.remotePort);
      received.add({
        'method': request.method,
        'query': request.uri.query,
        'type': request.headers.contentType?.mimeType,
        'body': await utf8.decoder.bind(request).join(),
        'custom': request.headers.value('x-test'),
      });
      request.response.headers.contentType = ContentType.json;
      request.response.write('{"code":200}');
      await request.response.close();
    });
    addTearDown(() async {
      await subscription.cancel();
      await server.close(force: true);
    });
    final address = 'http://127.0.0.1:${server.port}/api?q=ok';
    final get = await LxHttpBridge.performHttpRequest(address, {
      'headers': {'X-Test': 'ok', 'Content-Type': 'application/json'},
    });
    expect(get['body'], {'code': 200});
    await LxHttpBridge.performHttpRequest(address, {
      'method': 'POST',
      'body': {'a': 1},
    });
    await LxHttpBridge.performHttpRequest(address, {
      'method': 'POST',
      'form': {'a': 'a b'},
    });
    await LxHttpBridge.performHttpRequest(address, {
      'method': 'POST',
      'body': [65, 66],
    });
    expect(received[0], {
      'method': 'GET',
      'query': 'q=ok',
      'type': null,
      'body': '',
      'custom': 'ok',
    });
    expect(received[1]['body'], '{"a":1}');
    expect(received[1]['type'], 'application/json');
    expect(received[2]['body'], 'a=a%20b');
    expect(received[2]['type'], 'application/x-www-form-urlencoded');
    expect(received[3]['body'], 'AB');
    expect(connections, hasLength(1), reason: 'completed requests reuse TCP');
  });

  for (final (partialBody, deadline) in [
    (false, false),
    (true, false),
    (false, true),
    (true, true),
  ]) {
    test(
      'abort isolates an active peer (body=$partialBody, timeout=$deadline)',
      () async {
        final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
        final slowStarted = Completer<void>();
        final peerStarted = Completer<void>();
        final releasePeer = Completer<void>();
        final subscription = server.listen((request) async {
          if (request.uri.path == '/slow') {
            if (partialBody) {
              request.response.contentLength = 100;
              request.response.write('{');
              await request.response.flush();
            }
            slowStarted.complete();
            // Intentionally leave this response open until the caller aborts.
            return;
          }
          if (request.uri.path == '/peer') {
            peerStarted.complete();
            await releasePeer.future;
          }
          request.response.headers.contentType = ContentType.json;
          request.response.write('{"ok":true}');
          await request.response.close();
        });
        addTearDown(() async {
          if (!releasePeer.isCompleted) releasePeer.complete();
          LxHttpBridge.close();
          await subscription.cancel();
          await server.close(force: true);
        });
        final base = 'http://127.0.0.1:${server.port}';
        final owner = ResolutionRequest();
        final cancelled = expectLater(
          LxHttpBridge.performHttpRequest(
            '$base/slow',
            {},
            request: owner,
            timeout: Duration(seconds: deadline ? 1 : 5),
          ),
          throwsA(
            deadline ? isA<TimeoutException>() : isA<ResolutionCancelled>(),
          ),
        );
        final peer = LxHttpBridge.performHttpRequest('$base/peer', {});
        await Future.wait([
          slowStarted.future,
          peerStarted.future,
        ]).timeout(const Duration(seconds: 3));
        if (!deadline) owner.cancel();
        await cancelled.timeout(const Duration(seconds: 3));
        releasePeer.complete();
        expect((await peer)['body'], {'ok': true});
        expect(
          (await LxHttpBridge.performHttpRequest('$base/after', {}))['body'],
          {'ok': true},
        );
      },
    );
  }

  test(
    'partial response records body timeout within shared deadline',
    () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final records = <Map<String, dynamic>>[];
      StructuredLogService.sink = (line) => records.add(jsonDecode(line));
      final subscription = server.listen((request) {
        request.response.headers.contentType = ContentType.json;
        request.response.contentLength = 100;
        request.response.write('{"code":');
        unawaited(request.response.flush().catchError((Object _) {}));
      });
      addTearDown(() async {
        StructuredLogService.sink = null;
        await subscription.cancel();
        await server.close(force: true);
      });
      await expectLater(
        LxHttpBridge.performHttpRequest(
          'http://127.0.0.1:${server.port}/partial',
          {},
          timeout: const Duration(milliseconds: 200),
          requestId: 'test-http',
        ),
        throwsA(isA<TimeoutException>()),
      );
      final headers = records.singleWhere(
        (e) => e['event'] == 'lx.http_headers_received',
      );
      final ended = records.singleWhere(
        (e) => e['event'] == 'lx.http_transport_ended',
      );
      expect(headers['status'], 200);
      expect(headers['content_length'], 100);
      expect(ended['stage'], 'body');
      expect(ended['request_id'], 'test-http');
    },
  );

  test('closes a slow request at the caller deadline', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final requestSeen = Completer<void>();
    final serverTask = server.first.then((request) async {
      requestSeen.complete();
      await Future<void>.delayed(const Duration(seconds: 1));
      try {
        request.response.write('{}');
        await request.response.close();
      } catch (_) {
        // The deadline intentionally closes the client connection.
      }
    });

    final request = LxHttpBridge.performHttpRequest(
      'http://${server.address.address}:${server.port}/slow',
      const <String, dynamic>{},
      timeout: const Duration(milliseconds: 500),
    );

    // Attach the error handler before waiting for server-side observation.
    // Otherwise a busy test runner can let the deadline expire unhandled.
    final timedOut = expectLater(request, throwsA(isA<TimeoutException>()));
    await requestSeen.future.timeout(const Duration(seconds: 2));
    await timedOut;
    await serverTask;
    await server.close(force: true);
  });
}
