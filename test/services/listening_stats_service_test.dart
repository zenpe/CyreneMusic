import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:cyrene_music/models/track.dart';
import 'package:cyrene_music/services/auth_service.dart';
import 'package:cyrene_music/services/listening_stats_service.dart';
import 'package:cyrene_music/services/url_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _RealHttp extends HttpOverrides {}

Map<String, dynamic> user(int id) => {
  'id': id,
  'email': 'test$id@example.invalid',
  'username': 'test$id',
  'isVerified': true,
};
Map<String, dynamic> summary(int count) => {
  'status': 200,
  'data': {'totalListeningTime': 30, 'totalPlayCount': count, 'playCounts': []},
};
Map<String, dynamic> record(String id, String source) => {
  'track_id': id,
  'source': source,
  'track_name': 'Song',
  'play_count': 2,
  'last_played_at': '2026-10-16 01:00:00',
};

Future<void> reply(HttpRequest request, Object body, {int status = 200}) async {
  request.response.statusCode = status;
  request.response.headers.contentType = ContentType.json;
  request.response.write(jsonEncode(body));
  await request.response.close();
}

Future<void> withServer(
  Future<void> Function(HttpRequest) handle,
  Future<void> Function(AuthService, ListeningStatsService) verify,
) async {
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  final sub = server.listen(handle);
  await HttpOverrides.runZoned(() async {
    final auth = AuthService();
    await auth.ensureInitialized();
    await UrlService().initialize();
    UrlService().useCustomSource('http://127.0.0.1:${server.port}');
    await auth.loginWithToken(token: 'token-a', userJson: user(1));
    final service = ListeningStatsService();
    try {
      await verify(auth, service);
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
    'concurrent reads merge; repeated entry uses cache; explicit refresh reads again',
    () async {
      var calls = 0;
      await withServer(
        (request) async {
          expect(request.method, 'GET');
          expect(request.uri.path, '/stats');
          await reply(request, summary(++calls));
        },
        (auth, service) async {
          service.accumulateListeningTime(25);
          final results = await Future.wait(
            List.generate(10, (_) => service.fetchStats()),
          );
          expect(calls, 1);
          expect(results.every((r) => r?.totalPlayCount == 1), true);
          expect((await service.fetchStats())?.totalPlayCount, 1);
          expect(calls, 1);
          expect(
            (await service.fetchStats(forceRefresh: true))?.totalPlayCount,
            2,
          );
          expect(calls, 2);
        },
      );
    },
  );

  test('forced refresh also joins an existing request', () async {
    final started = Completer<void>(), release = Completer<void>();
    var calls = 0;
    await withServer(
      (request) async {
        calls++;
        started.complete();
        await release.future;
        await reply(request, summary(5));
      },
      (auth, service) async {
        final first = service.fetchStats();
        await started.future;
        final second = service.fetchStats(forceRefresh: true);
        release.complete();
        expect((await first)?.totalPlayCount, 5);
        expect((await second)?.totalPlayCount, 5);
        expect(calls, 1);
      },
    );
  });

  test(
    'failed refresh keeps last data and allows a successful retry',
    () async {
      var calls = 0;
      await withServer(
        (request) async {
          calls++;
          await reply(
            request,
            calls == 2 ? {} : summary(calls),
            status: calls == 2 ? 503 : 200,
          );
        },
        (auth, service) async {
          await service.fetchStats();
          expect(await service.fetchStats(forceRefresh: true), isNull);
          expect(service.lastError, isNotNull);
          expect(service.statsData?.totalPlayCount, 1);
          expect(
            (await service.fetchStats(forceRefresh: true))?.totalPlayCount,
            3,
          );
          expect(service.lastError, isNull);
        },
      );
    },
  );

  test(
    'first load failure is not cached as successful empty statistics',
    () async {
      var calls = 0;
      await withServer(
        (request) => reply(
          request,
          ++calls == 1 ? {'status': 200, 'data': {}} : summary(4),
        ),
        (auth, service) async {
          expect(await service.fetchStats(), isNull);
          expect(service.statsData, isNull);
          expect(service.lastError, isNotNull);
          expect((await service.fetchStats())?.totalPlayCount, 4);
          expect(calls, 2);
        },
      );
    },
  );

  test(
    'session changes discard cached data and old requests cannot overwrite the new account',
    () async {
      final started = Completer<void>(), release = Completer<void>();
      var calls = 0;
      await withServer(
        (request) async {
          final first = ++calls == 1;
          if (first) {
            started.complete();
            await release.future;
          }
          await reply(request, summary(first ? 99 : 2));
        },
        (auth, service) async {
          final old = service.fetchStats();
          await started.future;
          await auth.loginWithToken(token: 'token-b', userJson: user(2));
          expect(service.statsData, isNull);
          expect((await service.fetchStats())?.totalPlayCount, 2);
          release.complete();
          expect(await old, isNull);
          expect(service.statsData?.totalPlayCount, 2);
          await auth.logout();
          expect(service.statsData, isNull);
          expect(await service.fetchStats(), isNull);
          expect(calls, 2);
        },
      );
    },
  );

  test(
    'upload acknowledgements do not trigger another statistics read',
    () async {
      final paths = <String>[];
      await withServer(
        (request) async {
          paths.add(request.uri.path);
          await reply(request, {'status': 200, 'message': 'ok'});
        },
        (auth, service) async {
          service.accumulateListeningTime(30);
          await service.syncNow();
          await service.recordPlayCount(
            Track(
              id: '1',
              name: 'Song',
              artists: '',
              album: '',
              picUrl: '',
              source: MusicSource.qq,
            ),
          );
          expect(paths, ['/stats/listening-time', '/stats/play-count']);
        },
      );
    },
  );

  test(
    'full records use their own page endpoint and retain identical IDs from different platforms',
    () async {
      await withServer(
        (request) async {
          expect(request.uri.path, '/stats/records');
          expect(request.uri.queryParameters, {'page': '2', 'limit': '20'});
          await reply(request, {
            'status': 200,
            'data': {
              'page': 2,
              'hasMore': false,
              'records': [record('1', 'qq'), record('1', 'netease')],
            },
          });
        },
        (auth, service) async {
          final page = await service.fetchRecords(page: 2);
          expect(page.records.length, 2);
          expect(page.hasMore, false);
          expect(service.statsData, isNull);
        },
      );
    },
  );

  test(
    'records errors are explicit and the same page can be retried',
    () async {
      var calls = 0;
      await withServer(
        (request) => reply(
          request,
          ++calls == 1
              ? {'status': 502}
              : {
                  'status': 200,
                  'data': {'page': 1, 'records': [], 'hasMore': false},
                },
          status: calls == 1 ? 502 : 200,
        ),
        (auth, service) async {
          await expectLater(service.fetchRecords(), throwsStateError);
          expect((await service.fetchRecords()).records, isEmpty);
          expect(calls, 2);
        },
      );
    },
  );
}
