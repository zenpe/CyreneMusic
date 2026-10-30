import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:cyrene_music/pages/settings_page/third_party_accounts_page.dart';
import 'package:cyrene_music/services/auth_service.dart';
import 'package:cyrene_music/services/url_service.dart';
import 'package:cyrene_music/utils/theme_manager.dart';
import 'package:fluent_ui/fluent_ui.dart' as fluent;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _RealHttp extends HttpOverrides {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  for (final isFluent in [false, true]) {
    testWidgets(
      'binding page retains its request across parent rebuilds ($isFluent)',
      (tester) async {
        SharedPreferences.setMockInitialValues({});
        final rebuild = ValueNotifier<int>(0);
        late HttpServer server;
        late StreamSubscription<HttpRequest> subscription;
        var requests = 0;
        await tester.runAsync(() async {
          server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
          subscription = server.listen((r) async {
            requests++;
            r.response.headers.contentType = ContentType.json;
            r.response.write(
              jsonEncode({
                'code': 200,
                'data': {
                  'netease': {
                    'supported': true,
                    'bound': false,
                    'status': 'unbound',
                    'revision': 0,
                  },
                  'kugou': {'supported': false},
                },
              }),
            );
            await r.response.close();
          });
          await UrlService().initialize();
          UrlService().useCustomSource('http://127.0.0.1:${server.port}');
          await AuthService().ensureInitialized();
          await AuthService().loginWithToken(
            token: 'widget-test',
            userJson: {
              'id': 1,
              'username': 'test',
              'email': 'test@example.invalid',
              'isVerified': true,
            },
          );
          await ThemeManager().ensureSettingsLoaded();
          ThemeManager().setThemeFramework(
            isFluent ? ThemeFramework.fluent : ThemeFramework.material,
          );
        });
        await HttpOverrides.runZoned(() async {
          try {
            final content = ValueListenableBuilder<int>(
              valueListenable: rebuild,
              builder: (_, value, child) =>
                  ThirdPartyAccountsContent(embed: value >= 0),
            );
            await tester.pumpWidget(
              isFluent
                  ? fluent.FluentApp(
                      home: fluent.ScaffoldPage(content: content),
                    )
                  : MaterialApp(home: Scaffold(body: content)),
            );
            for (var i = 0; i < 12; i++) {
              await tester.runAsync(
                () => Future<void>.delayed(const Duration(milliseconds: 15)),
              );
              await tester.pump(const Duration(milliseconds: 20));
            }
            expect(find.text('去绑定'), findsOneWidget);
            final initial = requests;
            expect(initial, lessThanOrEqualTo(2));
            for (var i = 0; i < 20; i++) {
              rebuild.value++;
              await tester.pump(const Duration(milliseconds: 16));
              await tester.runAsync(
                () => Future<void>.delayed(const Duration(milliseconds: 5)),
              );
              await tester.pump();
            }
            expect(
              requests,
              initial,
              reason: 'A parent rebuild must not create a new binding request',
            );
            expect(find.text('去绑定'), findsOneWidget);
            expect(tester.takeException(), isNull);
          } finally {
            await tester.pumpWidget(const SizedBox.shrink());
            await tester.runAsync(() async {
              AuthService().onSessionEnded = null;
              await AuthService().logout();
              await subscription.cancel();
              await server.close(force: true);
            });
            await tester.pump(const Duration(seconds: 4));
            rebuild.dispose();
          }
        }, createHttpClient: _RealHttp().createHttpClient);
      },
    );
  }
}
