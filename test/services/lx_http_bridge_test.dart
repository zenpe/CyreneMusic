import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:cyrene_music/services/lx_http_bridge.dart';

void main() {
  test('closes a slow request at the caller deadline', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final requestSeen = Completer<void>();
    final serverTask = server.first.then((request) async {
      requestSeen.complete();
      await Future<void>.delayed(const Duration(milliseconds: 200));
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
      timeout: const Duration(milliseconds: 20),
    );

    await requestSeen.future;
    await expectLater(request, throwsA(isA<TimeoutException>()));
    await serverTask;
    await server.close(force: true);
  });
}
