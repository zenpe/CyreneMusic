import 'dart:io';

import 'package:cyrene_music/services/persistent_storage_service.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const pathProviderChannel = MethodChannel('plugins.flutter.io/path_provider');
  late Directory tempDir;
  final storage = PersistentStorageService();

  setUpAll(() async {
    tempDir = await Directory.systemTemp.createTemp('cyrene_music_test_');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(pathProviderChannel, (call) async {
      switch (call.method) {
        case 'getApplicationSupportDirectory':
        case 'getApplicationDocumentsDirectory':
        case 'getTemporaryDirectory':
          return tempDir.path;
        default:
          return tempDir.path;
      }
    });

    SharedPreferences.setMockInitialValues(<String, Object>{});
    await storage.initialize();
  });

  tearDown(() async {
    await storage.clear();
  });

  tearDownAll(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(pathProviderChannel, null);
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  group('PersistentStorageService convenience bools', () {
    test('defaults are false when keys are absent', () {
      expect(storage.termsAccepted, isFalse);
      expect(storage.themeConfigured, isFalse);
      expect(storage.enableLocalMode, isFalse);
    });

    test('set/get for termsAccepted is consistent', () async {
      await storage.setTermsAccepted(true);
      expect(storage.termsAccepted, isTrue);

      await storage.setTermsAccepted(false);
      expect(storage.termsAccepted, isFalse);
    });

    test('set/get for themeConfigured is consistent', () async {
      await storage.setThemeConfigured(true);
      expect(storage.themeConfigured, isTrue);

      await storage.setThemeConfigured(false);
      expect(storage.themeConfigured, isFalse);
    });

    test('set/get for enableLocalMode is consistent', () async {
      await storage.setEnableLocalMode(true);
      expect(storage.enableLocalMode, isTrue);

      await storage.setEnableLocalMode(false);
      expect(storage.enableLocalMode, isFalse);
    });
  });
}
