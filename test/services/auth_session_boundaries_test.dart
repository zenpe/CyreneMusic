import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:cyrene_music/models/track.dart';
import 'package:cyrene_music/services/auth_service.dart';
import 'package:cyrene_music/services/api/auth_token_store.dart';
import 'package:cyrene_music/services/favorite_service.dart';
import 'package:cyrene_music/services/listening_stats_service.dart';
import 'package:cyrene_music/services/url_service.dart';

Map<String, dynamic> user(int id) => {
  'id': id,
  'email': 'test$id@example.invalid',
  'username': 'test$id',
  'isVerified': true,
};

Future<void> reply(HttpRequest request, Object body, {int status = 200}) async {
  request.response.statusCode = status;
  request.response.headers.contentType = ContentType.json;
  request.response.write(jsonEncode(body));
  await request.response.close();
}

Future<void> withServer(
  Future<void> Function(HttpRequest) handle,
  Future<void> Function(AuthService) body,
) async {
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  final subscription = server.listen(handle);
  final realHttp = RealHttpOverrides();
  await HttpOverrides.runZoned(() async {
    final auth = AuthService();
    await auth.ensureInitialized();
    await UrlService().initialize();
    UrlService().useCustomSource(
      'http://${server.address.address}:${server.port}',
    );
    await auth.loginWithToken(token: 'token-a', userJson: user(1));
    try {
      await body(auth);
    } finally {
      auth.onSessionEnded = null;
      await auth.logout();
      await subscription.cancel();
      await server.close(force: true);
    }
  }, createHttpClient: realHttp.createHttpClient);
}

class RealHttpOverrides extends HttpOverrides {}

final track = Track(
  id: '1',
  name: 'song',
  artists: 'artist',
  album: 'album',
  picUrl: '',
  source: MusicSource.netease,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  for (final status in [429, 503]) {
    test(
      'password login failure $status leaves session logged out and explains the failure',
      () async {
        await withServer(
          (request) async {
            expect(request.uri.path, '/auth/login');
            expect(request.headers.value('Authorization'), isNull);
            request.response.headers.set('Retry-After', '37');
            await reply(
              request,
              status == 429 ? {'code': 429, 'message': '操作过于频繁'} : {},
              status: status,
            );
          },
          (auth) async {
            await auth.logout();
            final result = await auth.login(
              account: 'test',
              password: 'test-only-password',
            );
            expect(result['success'], false);
            expect(
              result['message'],
              status == 429 ? '操作过于频繁，请在 37 秒后重试' : '登录服务暂时不可用，请稍后重试',
            );
            expect(auth.isLoggedIn, false);
            expect(AuthTokenStore.token, isNull);
          },
        );
      },
    );
  }

  for (final switchAccount in [false, true]) {
    test(
      'late username update cannot overwrite ${switchAccount ? 'new account' : 'logout'}',
      () async {
        final received = Completer<void>();
        final release = Completer<void>();
        await withServer(
          (request) async {
            expect(request.headers.value('Authorization'), 'Bearer token-a');
            received.complete();
            await release.future;
            await reply(request, {'code': 200, 'message': 'updated'});
          },
          (auth) async {
            final update = auth.updateUsername('changed-name');
            await received.future.timeout(const Duration(seconds: 5));
            if (switchAccount) {
              await auth.loginWithToken(token: 'token-b', userJson: user(2));
            } else {
              await auth.logout();
            }
            release.complete();
            expect((await update)['success'], false);
            expect(auth.currentUser?.username, switchAccount ? 'test2' : null);
            final saved = (await SharedPreferences.getInstance()).getString(
              'current_user',
            );
            expect(
              saved == null ? null : jsonDecode(saved)['username'],
              switchAccount ? 'test2' : null,
            );
          },
        );
      },
    );
  }

  test('current-session username update still persists', () async {
    await withServer((request) => reply(request, {'code': 200}), (auth) async {
      expect((await auth.updateUsername('newname'))['success'], true);
      expect(auth.currentUser?.username, 'newname');
      final saved = (await SharedPreferences.getInstance()).getString(
        'current_user',
      );
      expect(jsonDecode(saved!)['username'], 'newname');
    });
  });

  for (final status in [200, 401]) {
    for (final switchAccount in [false, true]) {
      test(
        'late validation $status cannot overwrite ${switchAccount ? 'new account' : 'logout'}',
        () async {
          final received = Completer<void>();
          final release = Completer<void>();
          await withServer(
            (request) async {
              expect(request.headers.value('Authorization'), 'Bearer token-a');
              received.complete();
              await release.future;
              await reply(request, {
                'code': status,
                'data': user(1),
              }, status: status);
            },
            (auth) async {
              final validation = auth.validateToken();
              await received.future.timeout(const Duration(seconds: 5));
              if (switchAccount) {
                await auth.loginWithToken(token: 'token-b', userJson: user(2));
              } else {
                await auth.logout();
              }
              release.complete();
              await validation;
              expect(auth.isLoggedIn, switchAccount);
              expect(auth.currentUser?.id, switchAccount ? 2 : null);
              expect(AuthTokenStore.token, switchAccount ? 'token-b' : null);
            },
          );
        },
      );
    }
  }

  test('temporary server error preserves authentication', () async {
    await withServer((request) => reply(request, {'code': 503}, status: 503), (
      auth,
    ) async {
      expect(await auth.validateToken(), isTrue);
      expect(auth.currentUser?.id, 1);
      expect(AuthTokenStore.token, 'token-a');
    });
  });

  test(
    'logout clears access immediately and waits for playback cancellation',
    () async {
      final auth = AuthService();
      await auth.ensureInitialized();
      await auth.loginWithToken(token: 'token-a', userJson: user(1));
      final stopped = Completer<void>();
      var calls = 0;
      auth.onSessionEnded = () {
        calls++;
        return stopped.future;
      };
      var completed = false;
      final logout = auth.logout().then((_) => completed = true);
      expect(auth.isLoggedIn, isFalse);
      expect(AuthTokenStore.token, isNull);
      expect(calls, 1);
      expect(completed, isFalse);
      // An old logout's delayed cleanup must not clear the replacement login.
      await auth.loginWithToken(token: 'token-b', userJson: user(2));
      stopped.complete();
      await logout;
      expect(auth.currentUser?.id, 2);
      expect(AuthTokenStore.token, 'token-b');
      expect(
        (await SharedPreferences.getInstance()).getString('auth_token'),
        'token-b',
      );
      auth.onSessionEnded = null;
      await auth.logout();
    },
  );

  test('late favorites read cannot repopulate another account', () async {
    final received = Completer<void>();
    final release = Completer<void>();
    await withServer(
      (request) async {
        received.complete();
        await release.future;
        await reply(request, {
          'status': 200,
          'favorites': [
            {
              'trackId': '1',
              'name': 'song',
              'artists': 'artist',
              'album': 'album',
              'picUrl': '',
              'source': 'netease',
              'addedAt': '2026-10-12T00:00:00Z',
            },
          ],
        });
      },
      (auth) async {
        final service = FavoriteService();
        final load = service.loadFavorites();
        await received.future.timeout(const Duration(seconds: 5));
        await auth.loginWithToken(token: 'token-b', userJson: user(2));
        release.complete();
        await load;
        expect(service.favorites, isEmpty);
        expect(service.isLoading, isFalse);
      },
    );
  });

  test('late favorite mutation cannot add data to another account', () async {
    final received = Completer<void>();
    final release = Completer<void>();
    await withServer(
      (request) async {
        received.complete();
        await release.future;
        await reply(request, {'status': 200});
      },
      (auth) async {
        final service = FavoriteService();
        final add = service.addFavorite(track);
        await received.future.timeout(const Duration(seconds: 5));
        await auth.loginWithToken(token: 'token-b', userJson: user(2));
        release.complete();
        expect(await add, isFalse);
        expect(service.isFavorite(track), isFalse);
      },
    );
  });

  test('late favorite removal cannot commit in another account', () async {
    final received = Completer<void>();
    final release = Completer<void>();
    await withServer(
      (request) async {
        received.complete();
        await release.future;
        await reply(request, {'status': 200});
      },
      (auth) async {
        final service = FavoriteService();
        final removal = service.removeFavorite(track);
        await received.future.timeout(const Duration(seconds: 5));
        await auth.loginWithToken(token: 'token-b', userJson: user(2));
        release.complete();
        expect(await removal, isFalse);
      },
    );
  });

  test('same-account failed statistics remain retryable', () async {
    final sent = <int>[];
    await withServer(
      (request) async {
        final data =
            jsonDecode(await utf8.decoder.bind(request).join())
                as Map<String, dynamic>;
        sent.add(data['seconds'] as int);
        await reply(request, {
          'status': sent.length == 1 ? 503 : 200,
        }, status: sent.length == 1 ? 503 : 200);
      },
      (auth) async {
        final service = ListeningStatsService();
        service.accumulateListeningTime(30);
        await service.syncNow();
        await service.syncNow();
        expect(sent, [30, 30]);
      },
    );
  });

  test(
    'failed statistics upload cannot restore old seconds to new account',
    () async {
      final received = Completer<void>();
      final release = Completer<void>();
      final sentSeconds = <int>[];
      final headers = <String?>[];
      await withServer(
        (request) async {
          headers.add(request.headers.value('Authorization'));
          final data =
              jsonDecode(await utf8.decoder.bind(request).join())
                  as Map<String, dynamic>;
          sentSeconds.add(data['seconds'] as int);
          if (sentSeconds.length == 1) {
            received.complete();
            await release.future;
            await reply(request, {'code': 503}, status: 503);
          } else {
            await reply(request, {
              'status': 200,
              'data': {'totalListeningTime': 5},
            });
          }
        },
        (auth) async {
          final service = ListeningStatsService();
          service.accumulateListeningTime(30);
          final oldSync = service.syncNow();
          await received.future.timeout(const Duration(seconds: 5));
          await auth.loginWithToken(token: 'token-b', userJson: user(2));
          service.accumulateListeningTime(5);
          release.complete();
          await oldSync;
          await service.syncNow();
          expect(sentSeconds, [30, 5]);
          expect(headers, ['Bearer token-a', 'Bearer token-b']);
        },
      );
    },
  );

  test('unsent statistics are cleared on logout', () async {
    final sentSeconds = <int>[];
    await withServer(
      (request) async {
        final data =
            jsonDecode(await utf8.decoder.bind(request).join())
                as Map<String, dynamic>;
        sentSeconds.add(data['seconds'] as int);
        await reply(request, {
          'status': 200,
          'data': {'totalListeningTime': 5},
        });
      },
      (auth) async {
        final service = ListeningStatsService();
        service.accumulateListeningTime(30);
        await auth.logout();
        service.accumulateListeningTime(99);
        await auth.loginWithToken(token: 'token-b', userJson: user(2));
        service.accumulateListeningTime(5);
        await service.syncNow();
        expect(sentSeconds, [5]);
      },
    );
  });

  test('old statistics response cannot overwrite new account totals', () async {
    final received = Completer<void>();
    final release = Completer<void>();
    var reads = 0;
    await withServer(
      (request) async {
        final first = reads++ == 0;
        if (first) {
          received.complete();
          await release.future;
        }
        await reply(request, {
          'status': 200,
          'data': {
            'totalListeningTime': first ? 30 : 5,
            'totalPlayCount': 0,
            'playCounts': [],
          },
        });
      },
      (auth) async {
        final service = ListeningStatsService();
        final oldRead = service.fetchStats();
        await received.future.timeout(const Duration(seconds: 5));
        await auth.loginWithToken(token: 'token-b', userJson: user(2));
        await service.fetchStats();
        release.complete();
        expect(await oldRead, isNull);
        expect(service.statsData?.totalListeningTime, 5);
      },
    );
  });
}
