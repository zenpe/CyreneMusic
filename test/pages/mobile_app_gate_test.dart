import 'dart:io';

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
}
