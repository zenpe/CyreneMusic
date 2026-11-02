import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluent_ui/fluent_ui.dart' as fluent;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:cyrene_music/widgets/server_selection.dart';
import 'package:cyrene_music/pages/auth/auth_page.dart';
import 'package:cyrene_music/pages/auth/fluent_auth_page.dart';
import 'package:cyrene_music/pages/settings_page/server_settings_page.dart';
import 'package:cyrene_music/services/url_service.dart';
import 'package:cyrene_music/widgets/material/material_settings_widgets.dart';
import 'package:cyrene_music/widgets/fluent_settings_card.dart';

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  if (binding is AutomatedTestWidgetsFlutterBinding) {
    binding.defaultTestTimeout = const Timeout(Duration(seconds: 60));
  }
  const secureStorage = MethodChannel(
    'plugins.it_nomads.com/flutter_secure_storage',
  );
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    binding.defaultBinaryMessenger.setMockMethodCallHandler(
      secureStorage,
      (_) async => null,
    );
  });
  tearDown(() {
    binding.defaultBinaryMessenger.setMockMethodCallHandler(
      secureStorage,
      null,
    );
  });

  for (final fluentStyle in [false, true]) {
    testWidgets('recover invalid server before login, fluent=$fluentStyle', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await UrlService().initialize();
      UrlService().useCustomSource('https://wrong.example.invalid:59028');
      final home = fluentStyle
          ? const Scaffold(body: FluentAuthPage(embedded: true))
          : const AuthPage(embedded: true);
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: const [fluent.FluentLocalizations.delegate],
          home: fluentStyle
              ? fluent.FluentTheme(data: fluent.FluentThemeData(), child: home)
              : home,
        ),
      );
      await tester.pumpAndSettle();
      final fields = find.byType(EditableText);
      await tester.enterText(fields.at(0), 'testuser');
      await tester.enterText(fields.at(1), 'test-password');
      tester.testTextInput.hide();
      await tester.pumpAndSettle();
      expect(find.textContaining('wrong.example.invalid'), findsOneWidget);

      Future<void> back() async {
        if (fluentStyle) {
          await tester.tap(find.byIcon(fluent.FluentIcons.back));
        } else {
          await tester.pageBack();
        }
        await tester.pumpAndSettle();
      }

      // Opening settings and going back without a change preserves the form.
      await tester.tap(find.text('更换'));
      await tester.pumpAndSettle();
      await back();
      expect(
        tester.widget<EditableText>(fields.at(1)).controller.text,
        'test-password',
      );

      await tester.tap(find.text('更换'));
      await tester.pumpAndSettle();
      expect(find.byType(ServerSettingsPage), findsOneWidget);
      expect(find.text('音源设置'), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.tap(
        find.widgetWithText(
          fluentStyle ? FluentSettingsTile : MD3SettingsTile,
          '服务器设置',
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('官方服务器'));
      await tester.pumpAndSettle();
      expect(UrlService().isUsingOfficialSource, true);
      await back();
      expect(find.byType(ServerSelection), findsOneWidget);
      expect(find.text('当前服务器：官方服务器'), findsOneWidget);
      final inputs = tester.widgetList<EditableText>(fields).toList();
      expect(inputs[0].controller.text, 'testuser');
      expect(inputs[1].controller.text, isEmpty);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
    });
  }
}
