import 'package:cyrene_music/services/developer_mode_service.dart';
import 'package:cyrene_music/services/search_service.dart';
import 'package:cyrene_music/utils/theme_manager.dart';
import 'package:cyrene_music/widgets/search_widget.dart';
import 'package:fluent_ui/fluent_ui.dart' as fluent;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  for (final framework in [ThemeFramework.material, ThemeFramework.fluent]) {
    testWidgets(
      '${framework.name} always shows platform tabs with legacy merge enabled',
      (tester) async {
        SharedPreferences.setMockInitialValues({
          'search_result_merge_enabled': true,
        });
        await tester.runAsync(() async {
          await DeveloperModeService().initialize();
          await ThemeManager().ensureSettingsLoaded();
        });
        ThemeManager().setThemeFramework(framework);
        SearchService().clear();
        final search = SearchWidget(onClose: () {});
        await tester.pumpWidget(
          framework == ThemeFramework.fluent
              ? fluent.FluentApp(home: Material(child: search))
              : MaterialApp(home: Scaffold(body: search)),
        );
        await tester.pumpAndSettle();
        expect(find.byKey(const ValueKey('netease_tab')), findsOneWidget);
        expect(find.text('歌手'), findsOneWidget);
        for (final label in ['网易云', 'QQ音乐', '酷狗']) {
          expect(find.text(label), findsOneWidget);
          expect(find.bySemanticsLabel(label), findsWidgets);
        }
        expect(find.byKey(const ValueKey('songs_tab')), findsNothing);

        final tabs = find.byWidgetPredicate(
          (widget) =>
              widget.runtimeType.toString() ==
              (framework == ThemeFramework.fluent
                  ? '_FluentPivotTabs'
                  : '_SearchExpressiveTabs'),
        );
        final buttons = find.descendant(
          of: tabs,
          matching: framework == ThemeFramework.fluent
              ? find.byType(fluent.HoverButton)
              : find.byType(GestureDetector),
        );
        expect(buttons, findsNWidgets(4));
        await tester.tap(buttons.at(1));
        await tester.pumpAndSettle();
        expect(find.byKey(const ValueKey('qq_tab')), findsOneWidget);
        await tester.tap(buttons.at(2));
        await tester.pumpAndSettle();
        expect(find.byKey(const ValueKey('kugou_tab')), findsOneWidget);
        await tester.tap(buttons.at(3));
        await tester.pumpAndSettle();
        expect(find.byKey(const ValueKey('artists_tab')), findsOneWidget);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pumpAndSettle();
      },
    );
  }
}
