import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:cyrene_music/pages/profile_page.dart';
import 'package:cyrene_music/services/auth_service.dart';
import 'package:cyrene_music/services/listening_stats_service.dart';
import 'package:cyrene_music/services/url_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _RealHttp extends HttpOverrides {}

Future<void> setupServer(
  WidgetTester tester,
  Future<void> Function(HttpRequest) handle,
  Future<void> Function() verify,
) async {
  late HttpServer server;
  late StreamSubscription<HttpRequest> sub;
  late AuthService auth;
  await tester.runAsync(() async {
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    sub = server.listen(handle);
    auth = AuthService();
    await auth.ensureInitialized();
    await UrlService().initialize();
    UrlService().useCustomSource('http://127.0.0.1:${server.port}');
    await auth.loginWithToken(
      token: 'test-token',
      userJson: {
        'id': 1,
        'email': 'test@example.invalid',
        'username': 'test',
        'isVerified': true,
      },
    );
  });
  await HttpOverrides.runZoned(() async {
    try {
      await verify();
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.runAsync(() async {
        auth.onSessionEnded = null;
        await auth.logout();
        await sub.cancel();
        await server.close(force: true);
      });
    }
  }, createHttpClient: _RealHttp().createHttpClient);
}

Future<void> reply(HttpRequest request, {bool fail = false}) async {
  request.response.statusCode = fail ? 503 : 200;
  request.response.headers.contentType = ContentType.json;
  request.response.write(
    jsonEncode(
      fail
          ? {'status': 503}
          : {
              'status': 200,
              'data': request.uri.path == '/stats'
                  ? {
                      'totalListeningTime': 30,
                      'totalPlayCount': 1,
                      'playCounts': [],
                    }
                  : {'page': 1, 'records': [], 'hasMore': false},
            },
    ),
  );
  await request.response.close();
}

Future<void> settleIO(WidgetTester tester, bool Function() ready) async {
  for (var i = 0; i < 50 && !ready(); i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
    await tester.pump();
  }
  expect(ready(), true);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets(
    'statistics failure offers retry and recovers without forcing an upload',
    (tester) async {
      var fail = true;
      final paths = <String>[];
      await setupServer(
        tester,
        (request) async {
          paths.add(request.uri.path);
          expect(request.method, 'GET');
          await reply(request, fail: fail);
        },
        () async {
          await tester.runAsync(
            () => tester.pumpWidget(const MaterialApp(home: ProfilePage())),
          );
          await settleIO(tester, () => find.text('重试').evaluate().isNotEmpty);
          fail = false;
          await tester.runAsync(() => tester.tap(find.text('重试')));
          await tester.pump();
          await settleIO(
            tester,
            () => find.text('暂无播放记录').evaluate().isNotEmpty,
          );
          expect(paths.where((p) => p == '/stats').length, 2);
          expect(paths.where((p) => p == '/stats/records').length, 2);
          expect(tester.takeException(), isNull);
        },
      );
    },
  );

  testWidgets(
    'leaving while statistics are loading cannot update a disposed page',
    (tester) async {
      final release = Completer<void>();
      var started = 0;
      await setupServer(
        tester,
        (request) async {
          started++;
          await release.future;
          await reply(request);
        },
        () async {
          await tester.runAsync(
            () => tester.pumpWidget(const MaterialApp(home: ProfilePage())),
          );
          await settleIO(tester, () => started == 2);
          await tester.pumpWidget(const SizedBox.shrink());
          release.complete();
          await tester.runAsync(() => ListeningStatsService().fetchStats());
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 20)),
          );
          await tester.pump();
          expect(tester.takeException(), isNull);
        },
      );
    },
  );
}
