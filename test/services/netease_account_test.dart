import 'dart:convert';
import 'dart:io';
import 'package:cyrene_music/services/netease_login_service.dart';
import 'package:cyrene_music/services/netease_recommend_service.dart';
import 'package:cyrene_music/services/url_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _RealHttp extends HttpOverrides {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  Future<void> withServer(
    Future<void> Function(HttpRequest) handler,
    Future<void> Function(NeteaseLoginService) test,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final sub = server.listen(handler);
    await HttpOverrides.runZoned(() async {
      await UrlService().initialize();
      UrlService().useCustomSource('http://127.0.0.1:${server.port}');
      try {
        await test(NeteaseLoginService());
      } finally {
        await sub.cancel();
        await server.close(force: true);
      }
    }, createHttpClient: _RealHttp().createHttpClient);
  }

  Future<void> reply(HttpRequest r, Object body, {int status = 200}) async {
    r.response.statusCode = status;
    r.response.headers.contentType = ContentType.json;
    r.response.write(jsonEncode(body));
    await r.response.close();
  }

  test(
    'credentials are refused over non-loopback HTTP before any network request',
    () async {
      var calls = 0;
      await withServer(
        (r) async {
          calls++;
          await reply(r, {});
        },
        (s) async {
          UrlService().useCustomSource('http://192.0.2.1:8080');
          await expectLater(
            s.completeBinding('attempt', 'MUSIC_U=private'),
            throwsA(
              isA<NeteaseAccountException>().having(
                (e) => e.code,
                'code',
                'HTTPS_REQUIRED',
              ),
            ),
          );
          expect(calls, 0);
        },
      );
    },
  );
  test(
    'only HTTPS and explicit local loopback permit credential submission',
    () {
      for (final url in [
        'https://example.com',
        'http://127.0.0.1:8080',
        'http://localhost:8080',
        'http://[::1]:8080',
      ]) {
        expect(isNeteaseCredentialTransportAllowed(url), isTrue, reason: url);
      }
      for (final url in [
        'http://192.168.3.39:8080',
        'http://example.com',
        'http://localhost.example.com',
        'http://127.0.0.1.example.com',
        'https:',
        'file:///tmp/socket',
      ]) {
        expect(isNeteaseCredentialTransportAllowed(url), isFalse, reason: url);
      }
    },
  );
  test('same-machine web login can submit and confirm its binding', () async {
    await withServer(
      (r) async {
        expect(r.uri.path, '/accounts/netease/bind-sessions/attempt/complete');
        final body = jsonDecode(await utf8.decoder.bind(r).join());
        expect(body['cookie'], 'MUSIC_U=local-test');
        await reply(r, {
          'code': 200,
          'data': {'revision': 1},
        });
      },
      (s) async {
        await s.completeBinding('attempt', 'MUSIC_U=local-test');
        expect(s.bindingRevision, 1);
      },
    );
  });
  test(
    'binding revision changes notify once and account metadata is server owned',
    () async {
      var revision = 3;
      var notifications = 0;
      await withServer(
        (r) => reply(r, {
          'code': 200,
          'data': {
            'netease': {'bound': true, 'revision': revision, 'uid': '101'},
          },
        }),
        (s) async {
          void listener() {
            notifications++;
          }

          s.addListener(listener);
          try {
            expect((await s.fetchBindings())['data']['netease']['uid'], '101');
            expect(s.bindingRevision, 3);
            await s.fetchBindings();
            expect(notifications, 1);
            revision = 4;
            await s.fetchBindings();
            expect(notifications, 2);
          } finally {
            s.removeListener(listener);
          }
        },
      );
    },
  );
  test(
    'recommendations never reuse auth-only cache across a binding change',
    () async {
      var requests = 0;
      await withServer(
        (r) async {
          requests++;
          await reply(r, {
            'code': 200,
            'recommend': [
              {'id': requests},
            ],
          });
        },
        (s) async {
          final api = NeteaseRecommendService();
          expect((await api.fetchDailySongs()).single['id'], 1);
          expect((await api.fetchDailySongs()).single['id'], 2);
          expect((await api.fetchDailyPlaylists()).single['id'], 3);
          expect((await api.fetchDailyPlaylists()).single['id'], 4);
        },
      );
    },
  );
  test(
    'platform expiry preserves the business error and does not become Cyapi unauthorized',
    () async {
      await withServer(
        (r) => reply(r, {
          'code': 409,
          'error': 'NETEASE_LOGIN_EXPIRED',
          'message': '重新绑定',
        }, status: 409),
        (s) async {
          await expectLater(
            NeteaseRecommendService().fetchDailySongs(),
            throwsA(
              isA<NeteaseAccountException>().having(
                (e) => e.code,
                'code',
                'NETEASE_LOGIN_EXPIRED',
              ),
            ),
          );
        },
      );
    },
  );
  test(
    'multi playlist import uses atomic endpoint and stable operation identity',
    () async {
      await withServer(
        (r) async {
          expect(r.method, 'POST');
          expect(r.uri.path, '/playlists/import');
          final body = jsonDecode(await utf8.decoder.bind(r).join());
          expect(body, {
            'source': 'netease',
            'sourcePlaylistId': '42',
            'name': 'list',
            'operationId': 'retry-id',
          });
          await reply(r, {'code': 200, 'data': {}});
        },
        (s) => s.importPlaylist(
          id: '42',
          name: 'list',
          follow: false,
          operationId: 'retry-id',
        ),
      );
    },
  );
  test(
    'library business codes survive response parsing for deliberate retry',
    () async {
      await withServer(
        (r) => reply(r, {
          'code': 'SOURCE_ALREADY_FOLLOWED',
          'message': '已关注',
        }, status: 409),
        (s) async {
          await expectLater(
            s.importPlaylist(
              id: '42',
              name: 'list',
              follow: true,
              operationId: 'op',
            ),
            throwsA(
              isA<NeteaseAccountException>().having(
                (e) => e.code,
                'code',
                'SOURCE_ALREADY_FOLLOWED',
              ),
            ),
          );
        },
      );
    },
  );
}
