import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:cyrene_music/models/track.dart';
import 'package:cyrene_music/services/auth_service.dart';
import 'package:cyrene_music/services/favorite_service.dart';
import 'package:cyrene_music/services/url_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _RealHttp extends HttpOverrides {}

Track track(String id, [MusicSource source = MusicSource.netease]) => Track(
  id: id,
  name: 'song-$id',
  artists: '',
  album: '',
  picUrl: '',
  source: source,
);
Map<String, dynamic> favorite(String id, [String source = 'netease']) => {
  'trackId': id,
  'name': 'song-$id',
  'artists': '',
  'album': '',
  'picUrl': '',
  'source': source,
  'addedAt': '2026-10-16T00:00:00Z',
};
Future<void> reply(HttpRequest request, Object body, {int status = 200}) async {
  request.response.statusCode = status;
  request.response.headers.contentType = ContentType.json;
  request.response.write(jsonEncode(body));
  await request.response.close();
}

Future<void> withServer(
  Future<void> Function(HttpRequest) handle,
  Future<void> Function(FavoriteService, String url) verify,
) async {
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  final sub = server.listen(handle);
  await HttpOverrides.runZoned(() async {
    final auth = AuthService();
    await auth.ensureInitialized();
    await UrlService().initialize();
    final url = 'http://127.0.0.1:${server.port}';
    UrlService().useCustomSource(url);
    await auth.loginWithToken(
      token: 'test-token',
      userJson: {
        'id': 1,
        'email': 'test@example.invalid',
        'username': 'test',
        'isVerified': true,
      },
    );
    try {
      await verify(FavoriteService(), url);
    } finally {
      auth.onSessionEnded = null;
      await auth.logout();
      await sub.cancel();
      await server.close(force: true);
    }
  }, createHttpClient: _RealHttp().createHttpClient);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test(
    'late initial list preserves successful additions and unrelated server rows without refetching',
    () async {
      final started = Completer<void>(), release = Completer<void>();
      var reads = 0;
      await withServer(
        (request) async {
          if (request.method == 'GET') {
            reads++;
            started.complete();
            await release.future;
            await reply(request, {
              'status': 200,
              'favorites': [favorite('old')],
            });
          } else {
            await reply(request, {'status': 200});
          }
        },
        (service, url) async {
          final load = service.loadFavorites();
          await started.future;
          final joined = service.loadFavorites();
          expect(await service.addFavorite(track('new')), true);
          release.complete();
          await Future.wait([load, joined]);
          expect(service.isFavorite(track('new')), true);
          expect(service.isFavorite(track('old')), true);
          expect(service.favorites.map((f) => f.id).toList(), ['new', 'old']);
          expect(service.isLoading, false);
          expect(reads, 1);
        },
      );
    },
  );

  test(
    'late refreshed list cannot resurrect a removed favorite, including same ID on another platform',
    () async {
      final started = Completer<void>(), release = Completer<void>();
      var reads = 0;
      await withServer(
        (request) async {
          if (request.method == 'GET') {
            if (++reads == 2) {
              started.complete();
              await release.future;
            }
            await reply(request, {
              'status': 200,
              'favorites': [
                favorite('1'),
                favorite('1', 'qq'),
                favorite('other'),
              ],
            });
          } else {
            await reply(request, {'status': 200});
          }
        },
        (service, url) async {
          await service.loadFavorites();
          final refresh = service.loadFavorites();
          await started.future;
          expect(
            await service.removeFavorite(track('1', MusicSource.qq)),
            true,
          );
          release.complete();
          await refresh;
          expect(service.isFavorite(track('1', MusicSource.qq)), false);
          expect(service.isFavorite(track('1')), true);
          expect(service.isFavorite(track('other')), true);
          expect(service.favorites.length, 2);
          expect(reads, 2);
        },
      );
    },
  );

  test(
    'a read that already includes the added song does not create duplicate rows',
    () async {
      final started = Completer<void>(), release = Completer<void>();
      await withServer(
        (request) async {
          if (request.method == 'GET') {
            started.complete();
            await release.future;
            await reply(request, {
              'status': 200,
              'favorites': [favorite('1')],
            });
          } else {
            await reply(request, {'status': 200});
          }
        },
        (service, url) async {
          final load = service.loadFavorites();
          await started.future;
          expect(await service.addFavorite(track('1')), true);
          release.complete();
          await load;
          expect(service.favorites.length, 1);
        },
      );
    },
  );

  test('failed mutations do not change the in-flight list result', () async {
    final started = Completer<void>(), release = Completer<void>();
    await withServer(
      (request) async {
        if (request.method == 'GET') {
          started.complete();
          await release.future;
          await reply(request, {
            'status': 200,
            'favorites': [favorite('1')],
          });
        } else {
          await reply(request, {'status': 503}, status: 503);
        }
      },
      (service, url) async {
        final load = service.loadFavorites();
        await started.future;
        expect(await service.removeFavorite(track('1')), false);
        expect(await service.addFavorite(track('2')), false);
        release.complete();
        await load;
        expect(service.isFavorite(track('1')), true);
        expect(service.isFavorite(track('2')), false);
      },
    );
  });

  test(
    'mutation completing after the read also wins over the read result',
    () async {
      final started = Completer<void>(), release = Completer<void>();
      await withServer(
        (request) async {
          if (request.method == 'POST') {
            started.complete();
            await release.future;
            await reply(request, {'status': 200});
          } else {
            await reply(request, {'status': 200, 'favorites': []});
          }
        },
        (service, url) async {
          final add = service.addFavorite(track('1'));
          await started.future;
          await service.loadFavorites();
          release.complete();
          expect(await add, true);
          expect(service.isFavorite(track('1')), true);
          expect(service.favorites.length, 1);
        },
      );
    },
  );

  test(
    'backend switch clears favorites and invalidates late mutations even after switching back',
    () async {
      final started = Completer<void>(), release = Completer<void>();
      await withServer(
        (request) async {
          if (request.method == 'GET') {
            await reply(request, {
              'status': 200,
              'favorites': [favorite('old')],
            });
          } else {
            started.complete();
            await release.future;
            await reply(request, {'status': 200});
          }
        },
        (service, url) async {
          await service.loadFavorites();
          expect(service.favorites.length, 1);
          final add = service.addFavorite(track('new'));
          await started.future;
          UrlService().useCustomSource('$url/other');
          expect(service.favorites, isEmpty);
          UrlService().useCustomSource(url);
          release.complete();
          expect(await add, false);
          expect(service.favorites, isEmpty);
        },
      );
    },
  );
}
