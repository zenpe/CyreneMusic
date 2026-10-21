import 'dart:async';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:flutter_test/flutter_test.dart';
import 'package:cyrene_music/services/navidrome_api.dart';

void main() {
  test(
    'aborting lyrics preserves the shared client for subsequent requests',
    () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final client = http.Client();
      final requested = Completer<void>();
      final subscription = server.listen((request) async {
        if (request.uri.path.contains('getLyricsBySongId')) {
          requested
              .complete(); // Keep this response open until the client aborts.
        } else {
          request.response.write('{"subsonic-response":{"status":"ok"}}');
          await request.response.close();
        }
      });
      final api = NavidromeApi(
        baseUrl: 'http://127.0.0.1:${server.port}',
        username: 'test',
        password: 'test',
        client: client,
      );
      final abort = Completer<void>();
      try {
        final request = api.fetchLyrics('123', abort.future);
        final failed = expectLater(
          request,
          throwsA(isA<NavidromeApiException>()),
        );
        await requested.future.timeout(const Duration(seconds: 2));
        abort.complete();
        await failed.timeout(const Duration(seconds: 2));
        expect(await api.ping(), isTrue);
      } finally {
        client.close();
        await subscription.cancel();
        await server.close(force: true);
      }
    },
  );
}
