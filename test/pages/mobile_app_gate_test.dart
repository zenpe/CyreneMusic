import 'dart:io';
import 'dart:convert';

import 'package:cyrene_music/pages/desktop_app_gate.dart';
import 'package:cyrene_music/services/url_service.dart';

import 'package:cyrene_music/pages/mobile_app_gate.dart';
import 'package:cyrene_music/pages/auth/auth_page.dart';
import 'package:cyrene_music/services/auth_service.dart';
import 'package:cyrene_music/services/persistent_storage_service.dart';
import 'package:cyrene_music/widgets/terms_consent.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  const pathProvider = MethodChannel('plugins.flutter.io/path_provider');
  const secureStorage = MethodChannel(
    'plugins.it_nomads.com/flutter_secure_storage',
  );
  late Directory directory;
  late AuthService auth;
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    directory = await Directory.systemTemp.createTemp('cyrene-gate-test-');
    binding.defaultBinaryMessenger.setMockMethodCallHandler(
      pathProvider,
      (_) async => directory.path,
    );
    binding.defaultBinaryMessenger.setMockMethodCallHandler(
      secureStorage,
      (_) async => null,
    );
    await PersistentStorageService().initialize();
    auth = AuthService();
    await auth.ensureInitialized();
    await auth.logout();
    await PersistentStorageService().setTermsAccepted(false);
  });
  tearDownAll(() async {
    await PersistentStorageService().forceBackup();
    binding.defaultBinaryMessenger.setMockMethodCallHandler(pathProvider, null);
    binding.defaultBinaryMessenger.setMockMethodCallHandler(
      secureStorage,
      null,
    );
    await directory.delete(recursive: true);
  });

  testWidgets('login advances the existing setup route to agreement', (
    tester,
  ) async {
    await tester.pumpWidget(const MaterialApp(home: MobileAppGate()));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.byType(AuthPage), findsOneWidget);
    expect(find.byType(AgreementConfirmation), findsNothing);

    await tester.runAsync(
      () => auth.loginWithToken(
        token: 'test-token',
        userJson: {
          'id': 1,
          'email': 'test@example.invalid',
          'username': 'test',
          'isVerified': true,
        },
      ),
    );
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.byType(AuthPage), findsNothing);
    expect(find.byType(AgreementConfirmation), findsOneWidget);

    await tester.runAsync(auth.logout);
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.byType(AuthPage), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });
  for (final desktopMaterial in [false, true]) {
    testWidgets(
      'HTTP 401 returns to login and dismisses pushed pages, desktopMaterial=$desktopMaterial',
      (tester) async {
        final navigatorKey = GlobalKey<NavigatorState>();
        late HttpServer server;
        await tester.runAsync(() async {
          await auth.logout();
          await PersistentStorageService().setTermsAccepted(false);
          await UrlService().initialize();
          server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
          server.listen((request) async {
            request.response.statusCode = HttpStatus.unauthorized;
            request.response.headers.contentType = ContentType.json;
            request.response.write(
              jsonEncode({'code': 401, 'message': 'expired'}),
            );
            await request.response.close();
          });
          UrlService().useCustomSource('http://127.0.0.1:${server.port}');
        });
        addTearDown(() => server.close(force: true));
        await tester.pumpWidget(
          MaterialApp(
            navigatorKey: navigatorKey,
            home: desktopMaterial
                ? const DesktopAppGate(useMaterialLayout: true)
                : const MobileAppGate(),
          ),
        );
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 10)),
        );
        await tester.pump(const Duration(milliseconds: 100));
        expect(find.byType(AuthPage), findsOneWidget);
        await tester.runAsync(
          () => auth.loginWithToken(
            token: 'revoked-token',
            userJson: {
              'id': 1,
              'email': 'test@example.invalid',
              'username': 'test',
              'isVerified': true,
            },
          ),
        );
        await tester.pump(const Duration(milliseconds: 100));
        expect(find.byType(AgreementConfirmation), findsOneWidget);
        navigatorKey.currentState!.push<void>(
          MaterialPageRoute(
            builder: (_) => const Scaffold(body: Text('pushed settings page')),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text('pushed settings page'), findsOneWidget);

        await tester.runAsync(() async {
          final realHttp = _RealHttpOverrides();
          await HttpOverrides.runZoned(() async {
            expect(await auth.validateToken(), false);
          }, createHttpClient: realHttp.createHttpClient);
        });
        await tester.pumpAndSettle();
        expect(auth.isLoggedIn, false);
        expect(auth.token, isNull);
        expect(find.text('pushed settings page'), findsNothing);
        expect(find.byType(AuthPage), findsOneWidget);
        expect(navigatorKey.currentState!.canPop(), false);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pumpAndSettle();
      },
    );
  }
}

class _RealHttpOverrides extends HttpOverrides {}
