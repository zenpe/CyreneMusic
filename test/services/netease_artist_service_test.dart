import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:cyrene_music/services/netease_artist_service.dart';
import 'package:cyrene_music/services/url_service.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _RealHttp extends HttpOverrides {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<void> withServer(
    Future<void> Function(HttpRequest) handle,
    Future<void> Function(NeteaseArtistDetailService) verify,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final subscription = server.listen(handle);
    await HttpOverrides.runZoned(() async {
      await UrlService().initialize();
      UrlService().useCustomSource('http://127.0.0.1:${server.port}');
      try {
        await verify(NeteaseArtistDetailService());
      } finally {
        await subscription.cancel();
        await server.close(force: true);
      }
    }, createHttpClient: _RealHttp().createHttpClient);
  }

  Future<void> reply(
    HttpRequest request,
    Object body, {
    int status = 200,
  }) async {
    request.response.statusCode = status;
    request.response.headers.contentType = ContentType.json;
    request.response.write(jsonEncode(body));
    await request.response.close();
  }

  test('genuine no matches succeeds; blank query sends no request', () async {
    var calls = 0;
    await withServer(
      (request) async {
        calls++;
        expect(request.uri.path, '/artist/search');
        final form = Uri.splitQueryString(
          await utf8.decoder.bind(request).join(),
        );
        expect(form, {'keywords': 'test', 'limit': '20'});
        await reply(request, {'status': 200, 'result': []});
      },
      (service) async {
        expect(await service.searchArtists(' '), isEmpty);
        expect(calls, 0);
        expect(await service.searchArtists(' test '), isEmpty);
        expect(calls, 1);
      },
    );
  });

  test('upstream failure is visible and same query can be retried', () async {
    var calls = 0;
    await withServer(
      (request) async {
        if (++calls == 1) {
          await reply(request, {'status': 502}, status: 502);
        } else {
          await reply(request, {
            'status': 200,
            'result': [
              {'id': 1, 'name': 'Singer', 'picUrl': ''},
            ],
          });
        }
      },
      (service) async {
        await expectLater(
          service.searchArtists('test'),
          throwsA(isA<ArtistSearchException>()),
        );
        final results = await service.searchArtists('test');
        expect(results.single.name, 'Singer');
        expect(calls, 2);
      },
    );
  });

  test('server timeout has a clear error instead of no matches', () async {
    await withServer(
      (request) => reply(request, {'status': 504}, status: 504),
      (service) async {
        await expectLater(
          service.searchArtists('test'),
          throwsA(
            isA<ArtistSearchException>().having(
              (e) => e.message,
              'message',
              '搜索超时，请重试',
            ),
          ),
        );
      },
    );
  });

  test(
    'malformed successful responses are not treated as no matches',
    () async {
      var calls = 0;
      final bodies = [
        {'status': 200},
        {
          'status': 200,
          'result': [{}],
        },
        {
          'status': 200,
          'result': [
            {'id': -1, 'name': 'Singer'},
          ],
        },
      ];
      await withServer((request) => reply(request, bodies[calls++]), (
        service,
      ) async {
        for (var i = 0; i < bodies.length; i++) {
          await expectLater(
            service.searchArtists('test'),
            throwsA(isA<ArtistSearchException>()),
          );
        }
      });
    },
  );

  test(
    'cancellation releases pending search and a new search succeeds',
    () async {
      final started = Completer<void>();
      final token = CancelToken();
      await withServer(
        (request) async {
          final form = Uri.splitQueryString(
            await utf8.decoder.bind(request).join(),
          );
          if (form['keywords'] == 'old') {
            started.complete();
            return;
          }
          await reply(request, {'status': 200, 'result': []});
        },
        (service) async {
          final old = service.searchArtists('old', cancelToken: token);
          final assertion = expectLater(old, throwsA(isA<DioException>()));
          await started.future;
          token.cancel('new search');
          await assertion;
          expect(await service.searchArtists('new'), isEmpty);
        },
      );
    },
  );

  test(
    'background ID lookup keeps its limit and exact-name preference',
    () async {
      await withServer(
        (request) async {
          final form = Uri.splitQueryString(
            await utf8.decoder.bind(request).join(),
          );
          expect(form['limit'], '5');
          await reply(request, {
            'status': 200,
            'result': [
              {'id': 1, 'name': 'Other'},
              {'id': 2, 'name': 'Singer'},
            ],
          });
        },
        (service) async {
          expect(await service.resolveArtistIdByName('singer'), 2);
        },
      );
    },
  );

  test('background ID lookup still degrades on failure', () async {
    await withServer(
      (request) => reply(request, {'status': 502}, status: 502),
      (service) async {
        expect(await service.resolveArtistIdByName('test'), isNull);
      },
    );
  });
}
