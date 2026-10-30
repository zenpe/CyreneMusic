import 'package:cyrene_music/utils/app_feedback.dart';
import 'package:cyrene_music/widgets/feedback_boundary.dart';
import 'package:cyrene_music/widgets/server_address_editor.dart';
import 'package:cyrene_music/services/navigation_provider.dart';
import 'package:cyrene_music/services/url_service.dart';
import 'package:cyrene_music/utils/theme_manager.dart';
import 'package:fluent_ui/fluent_ui.dart' as fluent;
import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });
  tearDown(AppFeedback.dismissAll);
  testWidgets('tab, backend, theme, and lifecycle changes clear old feedback', (
    tester,
  ) async {
    late BuildContext page;
    await tester.pumpWidget(
      MaterialApp(
        home: FeedbackBoundary(
          child: Scaffold(
            body: Builder(
              builder: (context) {
                page = context;
                return const Text('home');
              },
            ),
          ),
        ),
      ),
    );
    Future<void> show() async {
      AppFeedback.of(page).info('old');
      await tester.pump();
      expect(find.text('old'), findsOneWidget);
    }

    await show();
    NavigationProvider().navigateTo(1);
    await tester.pump();
    expect(find.text('old'), findsNothing);
    await show();
    UrlService().useCustomSource('https://feedback-test.invalid');
    await tester.pump();
    expect(find.text('old'), findsNothing);
    await show();
    final previousColor = ThemeManager().seedColor;
    ThemeManager().setSeedColor(Colors.orange);
    await tester.pump();
    expect(find.text('old'), findsNothing);
    await show();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    await tester.pump();
    expect(find.text('old'), findsNothing);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpWidget(const SizedBox());
    NavigationProvider().reset();
    ThemeManager().setSeedColor(previousColor);
  });
  for (final style in ServerEditorStyle.values) {
    testWidgets('$style server validation stays inline and preserves input', (
      tester,
    ) async {
      UrlService().useOfficialSource();
      final original = UrlService().baseUrl;
      final editor = ServerAddressEditor(style: style);
      final Widget app = switch (style) {
        ServerEditorStyle.material => MaterialApp(home: Scaffold(body: editor)),
        ServerEditorStyle.fluent => fluent.FluentApp(home: editor),
        ServerEditorStyle.cupertino => CupertinoApp(
          home: CupertinoPageScaffold(child: editor),
        ),
      };
      await tester.pumpWidget(app);
      final input = find.byType(EditableText);
      await tester.enterText(input, 'bad-address');
      await tester.tap(find.text('保存'));
      await tester.pump();
      expect(find.text('请输入有效的 http:// 或 https:// 地址'), findsOneWidget);
      expect(find.text('bad-address'), findsOneWidget);
      expect(UrlService().baseUrl, original);
      expect(find.byKey(const ValueKey('app-feedback-surface')), findsNothing);
      await tester.enterText(input, '');
      await tester.tap(find.text('保存'));
      await tester.pump();
      expect(find.text('请输入服务器地址'), findsOneWidget);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  }
}
