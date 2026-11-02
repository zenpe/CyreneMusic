import 'package:cyrene_music/services/auth_service.dart';
import 'package:cyrene_music/services/api/auth_token_store.dart';
import 'package:cyrene_music/services/url_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'custom backend cold start restores session even when auth starts first',
    () async {
      const user = '{"id":1,"username":"zen","email":"zen@example.test"}';
      SharedPreferences.setMockInitialValues({
        'backend_source_type': 'custom',
        'custom_base_url': 'https://nas.example:59028',
        'current_user': user,
        'auth_token': 'saved-token',
        'remembered_login_account': 'zen',
      });
      final secureCalls = <MethodCall>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
            (call) async {
              secureCalls.add(call);
              return null;
            },
          );
      final auth = AuthService();
      await Future.wait([
        auth.ensureInitialized(),
        UrlService().initialize(),
        UrlService().initialize(),
      ]);
      expect(UrlService().baseUrl, 'https://nas.example:59028');
      expect(UrlService().backendRevision, 0);
      expect(auth.isLoggedIn, isTrue);
      expect(secureCalls.where((call) => call.method == 'delete'), isEmpty);
      expect(auth.currentUser!.username, 'zen');
      expect(AuthTokenStore.token, 'saved-token');
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('auth_token'), 'saved-token');
      expect(prefs.getString('current_user'), user);
      UrlService().useCustomSource('https://nas.example:59028');
      expect(auth.isLoggedIn, isTrue);
      UrlService().useCustomSource('https://other.example');
      expect(auth.isLoggedIn, isFalse);
      expect(AuthTokenStore.token, isNull);
      await Future<void>.delayed(Duration.zero);
      expect(prefs.getString('auth_token'), isNull);
      expect(prefs.getString('remembered_login_account'), 'zen');
      expect(
        secureCalls.where((call) => call.method == 'delete'),
        hasLength(1),
      );
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
            null,
          );
    },
  );
}
