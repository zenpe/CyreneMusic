import 'dart:io';

import 'package:cyrene_music/models/track.dart';
import 'package:cyrene_music/utils/audio_http_request.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  test(
    'cache recomputes headers across official to third-party redirect',
    () async {
      final seen = <http.Request>[];
      final client = AudioHttpClient(
        MockClient((request) async {
          seen.add(request);
          if (seen.length == 1) {
            return http.Response(
              '',
              302,
              headers: {'location': 'https://cdn-img.gitcode.com/audio'},
            );
          }
          return http.Response(
            'audio',
            request.headers.containsKey('referer') ? 403 : 200,
          );
        }),
        MusicSource.qq,
      );
      try {
        final response = await client.send(
          http.Request(
              'GET',
              Uri.https('isure.stream.qqmusic.qq.com', '/audio'),
            )
            ..headers['Range'] = 'bytes=0-'
            ..headers['Authorization'] = 'secret',
        );
        expect(response.statusCode, 200);
        expect(await response.stream.bytesToString(), 'audio');
        expect(seen.first.headers['referer'], 'https://y.qq.com/');
        expect(seen.last.headers['referer'], isNull);
        expect(seen.last.headers['origin'], isNull);
        expect(seen.last.headers['range'], 'bytes=0-');
        expect(seen.last.headers['authorization'], isNull);
        expect(seen.every((request) => !request.followRedirects), isTrue);
      } finally {
        client.close();
      }
    },
  );

  test('cache rejects non-HTTP redirect targets', () async {
    final client = AudioHttpClient(
      MockClient(
        (_) async =>
            http.Response('', 302, headers: {'location': 'file:///private'}),
      ),
      MusicSource.qq,
    );
    try {
      await expectLater(
        client.get(Uri.https('cdn.test', '/')),
        throwsA(isA<HttpException>()),
      );
    } finally {
      client.close();
    }
  });
}
