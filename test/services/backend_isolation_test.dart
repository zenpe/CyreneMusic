import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:cyrene_music/services/api/api_client.dart';
import 'package:cyrene_music/services/api/auth_token_store.dart';
import 'package:cyrene_music/services/auth_service.dart';
import 'package:cyrene_music/services/listening_stats_service.dart';
import 'package:cyrene_music/services/structured_log_service.dart';
import 'package:cyrene_music/services/url_service.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _RealHttp extends HttpOverrides {}

Future<void> reply(HttpRequest request, Object body, {int status = 200}) async {
  request.response.statusCode = status;
  request.response.headers.contentType = ContentType.json;
  request.response.write(jsonEncode(body));
  await request.response.close();
}

Map<String, dynamic> stats(int count) => {
  'status': 200,
  'data': {'totalListeningTime': 30, 'totalPlayCount': count, 'playCounts': []},
};

Future<void> withBackends(
  Future<void> Function(String backend, HttpRequest request) handle,
  Future<void> Function(String a, String b, AuthService auth) verify,
) async {
  final a = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  final b = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  final subs = [
    a.listen((r) => handle('a', r)),
    b.listen((r) => handle('b', r)),
  ];
  await HttpOverrides.runZoned(() async {
    final auth = AuthService();
    await auth.ensureInitialized();
    await UrlService().initialize();
    final aUrl = 'http://127.0.0.1:${a.port}';
    final bUrl = 'http://127.0.0.1:${b.port}';
    UrlService().useCustomSource(aUrl);
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
      await verify(aUrl, bUrl, auth);
    } finally {
      auth.onSessionEnded = null;
      await auth.logout();
      for (final sub in subs) {
        await sub.cancel();
      }
      await a.close(force: true);
      await b.close(force: true);
    }
  }, createHttpClient: _RealHttp().createHttpClient);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test(
    'transport failures retain their stage without logging credentials',
    () async {
      final lines = <String>[];
      await withBackends(
        (_, request) async {
          await Future<void>.delayed(const Duration(milliseconds: 300));
          await reply(request, {'status': 200});
        },
        (a, b, auth) async {
          StructuredLogService.sink = lines.add;
          try {
            final result = await ApiClient().getJson(
              '/probe?token=private-query',
              timeout: const Duration(milliseconds: 50),
            );
            expect(result.isNetworkError, isTrue);
            final events = lines.map(
              (line) => jsonDecode(line) as Map<String, dynamic>,
            );
            final event = events.singleWhere(
              (e) => e['event'] == 'api.transport_failed',
            );
            expect(event['failure_kind'], 'receiveTimeout');
            expect(event['path'], '/probe');
            expect(event['host'], '127.0.0.1');
            expect(event['status'], 0);
            expect(jsonEncode(event), isNot(contains('private-query')));
            expect(jsonEncode(event), isNot(contains('test-token')));
          } finally {
            StructuredLogService.sink = null;
          }
        },
      );
    },
  );

  test(
    'GET cache and deduplication are isolated across backend switches, including A-B-A',
    () async {
      final calls = {'a': 0, 'b': 0};
      await withBackends(
        (backend, request) async {
          calls[backend] = calls[backend]! + 1;
          await reply(request, {'backend': backend});
        },
        (a, b, auth) async {
          final api = ApiClient();
          Future<String> read() async =>
              (await api.getJson(
                    '/probe',
                    cacheTtl: const Duration(minutes: 1),
                  )).data['backend']
                  as String;
          expect(await read(), 'a');
          expect(await read(), 'a');
          final revision = UrlService().backendRevision;
          UrlService().useCustomSource(a); // No effective URL change.
          expect(UrlService().backendRevision, revision);
          expect(await read(), 'a');
          UrlService().useCustomSource(b);
          expect(await read(), 'b');
          expect(await read(), 'b');
          UrlService().useCustomSource(a);
          expect(await read(), 'a');
          expect(calls, {'a': 2, 'b': 1});
        },
      );
    },
  );

  test(
    'new backend does not join a pending old request or cache its late result',
    () async {
      final started = Completer<void>(), release = Completer<void>();
      var bCalls = 0;
      await withBackends(
        (backend, request) async {
          if (backend == 'a') {
            started.complete();
            await release.future;
          } else {
            bCalls++;
          }
          await reply(request, {'backend': backend});
        },
        (a, b, auth) async {
          final api = ApiClient();
          final old = api.getJson(
            '/probe',
            cacheTtl: const Duration(minutes: 1),
          );
          await started.future;
          UrlService().useCustomSource(b);
          expect(
            (await api.getJson(
              '/probe',
              cacheTtl: const Duration(minutes: 1),
            )).data['backend'],
            'b',
          );
          release.complete();
          expect((await old).ok, false);
          expect(
            (await api.getJson(
              '/probe',
              cacheTtl: const Duration(minutes: 1),
            )).data['backend'],
            'b',
          );
          expect(bCalls, 1);
        },
      );
    },
  );

  test(
    'old 401 after A-B-A cannot invalidate login or disturb the new in-flight request',
    () async {
      final oldStarted = Completer<void>(), newStarted = Completer<void>();
      final releaseOld = Completer<void>(), releaseNew = Completer<void>();
      var calls = 0;
      await withBackends(
        (backend, request) async {
          expect(backend, 'a');
          if (++calls == 1) {
            oldStarted.complete();
            await releaseOld.future;
            await reply(request, {}, status: 401);
          } else {
            newStarted.complete();
            await releaseNew.future;
            await reply(request, {'fresh': true});
          }
        },
        (a, b, auth) async {
          final original = AuthTokenStore.onUnauthorized;
          var unauthorized = 0;
          AuthTokenStore.onUnauthorized = () => unauthorized++;
          try {
            final api = ApiClient();
            final old = api.getJson('/probe');
            await oldStarted.future;
            UrlService().useCustomSource(b);
            UrlService().useCustomSource(a);
            final fresh = api.getJson('/probe');
            await newStarted.future;
            releaseOld.complete();
            expect((await old).ok, false);
            final joined = api.getJson('/probe');
            releaseNew.complete();
            expect((await fresh).data['fresh'], true);
            expect((await joined).data['fresh'], true);
            expect(calls, 2);
            expect(unauthorized, 0);
            expect(auth.isLoggedIn, true);
          } finally {
            AuthTokenStore.onUnauthorized = original;
          }
        },
      );
    },
  );

  test(
    'a queued relative request never silently moves to the new backend',
    () async {
      var bCalls = 0;
      await withBackends(
        (backend, request) async {
          if (backend == 'b') bCalls++;
          await reply(request, {});
        },
        (a, b, auth) async {
          final pending = ApiClient().getJson('/queued');
          UrlService().useCustomSource(b);
          expect((await pending).ok, false);
          expect(bCalls, 0);
        },
      );
    },
  );

  test(
    'explicit unrelated absolute URL requests survive configured-backend changes',
    () async {
      final started = Completer<void>(), release = Completer<void>();
      await withBackends(
        (backend, request) async {
          expect(backend, 'b');
          started.complete();
          await release.future;
          await reply(request, {'external': true});
        },
        (a, b, auth) async {
          final request = ApiClient().getJson('$b/external', auth: false);
          await started.future;
          UrlService().useCustomSource('$a/other-base');
          release.complete();
          expect((await request).data['external'], true);
        },
      );
    },
  );

  test('byte and stream requests reject stale responses too', () async {
    final started = Completer<void>(), release = Completer<void>();
    var calls = 0;
    await withBackends(
      (backend, request) async {
        expect(backend, 'a');
        if (++calls == 2) started.complete();
        await release.future;
        await reply(request, {});
      },
      (a, b, auth) async {
        final bytes = ApiClient().requestBytes('/bytes');
        final stream = ApiClient().requestStream('/stream');
        final streamCheck = expectLater(stream, throwsA(isA<DioException>()));
        await started.future;
        UrlService().useCustomSource(b);
        release.complete();
        expect((await bytes).ok, false);
        await streamCheck;
      },
    );
  });

  test(
    'statistics cache and pending refresh reset immediately on backend change',
    () async {
      final started = Completer<void>(), release = Completer<void>();
      var aCalls = 0;
      await withBackends(
        (backend, request) async {
          if (backend == 'a' && ++aCalls == 2) {
            started.complete();
            await release.future;
          }
          await reply(request, stats(backend == 'a' ? 1 : 2));
        },
        (a, b, auth) async {
          final service = ListeningStatsService();
          expect((await service.fetchStats())?.totalPlayCount, 1);
          final old = service.fetchStats(forceRefresh: true);
          await started.future;
          UrlService().useCustomSource(b);
          expect(service.statsData, isNull);
          expect((await service.fetchStats())?.totalPlayCount, 2);
          release.complete();
          expect(await old, isNull);
          expect(service.statsData?.totalPlayCount, 2);
          UrlService().useCustomSource(a);
          expect((await service.fetchStats())?.totalPlayCount, 1);
          expect(aCalls, 3);
        },
      );
    },
  );

  test(
    'failed old-backend upload cannot restore its seconds into the new backend',
    () async {
      final started = Completer<void>(), release = Completer<void>();
      final sentToB = <int>[];
      await withBackends(
        (backend, request) async {
          final body =
              jsonDecode(await utf8.decoder.bind(request).join()) as Map;
          if (backend == 'a') {
            started.complete();
            await release.future;
            await reply(request, {}, status: 503);
          } else {
            sentToB.add(body['seconds'] as int);
            await reply(request, {'status': 200});
          }
        },
        (a, b, auth) async {
          final service = ListeningStatsService();
          service.accumulateListeningTime(30);
          final old = service.syncNow();
          await started.future;
          UrlService().useCustomSource(b);
          service.accumulateListeningTime(5);
          release.complete();
          await old;
          await service.syncNow();
          expect(sentToB, [5]);
        },
      );
    },
  );
}
