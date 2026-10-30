import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluent_ui/fluent_ui.dart' as fluent;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:cyrene_music/models/track.dart';
import 'package:cyrene_music/utils/theme_manager.dart';
import 'package:cyrene_music/widgets/track_action_menu.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));
  final track = Track(
    id: '1',
    name: '测试歌曲',
    artists: '歌手',
    album: '专辑',
    picUrl: '',
    source: MusicSource.netease,
  );
  for (final framework in ThemeFramework.values) {
    for (final canRemove in [false, true]) {
      testWidgets(
        'track removal callback is available only when supplied: $framework/$canRemove',
        (tester) async {
          ThemeManager().setThemeFramework(framework);
          var removed = 0;
          final home = Scaffold(
            body: Center(
              child: TrackMoreButton(
                track: track,
                deleteLabel: '从歌单移除',
                onDelete: canRemove ? () => removed++ : null,
              ),
            ),
          );
          await tester.pumpWidget(
            MaterialApp(
              builder: (context, child) => framework == ThemeFramework.fluent
                  ? fluent.FluentTheme(
                      data: fluent.FluentThemeData(),
                      child: child!,
                    )
                  : child!,
              home: home,
            ),
          );
          await tester.pumpAndSettle();
          await tester.tap(find.byType(TrackMoreButton));
          await tester.pumpAndSettle();
          expect(find.text('从历史记录中删除'), findsNothing);
          expect(find.text('从歌单移除'), canRemove ? findsOneWidget : findsNothing);
          if (canRemove) {
            expect(removed, 0);
            await tester.tap(find.text('从歌单移除'));
            await tester.pumpAndSettle();
            expect(removed, 1);
            expect(find.text('从歌单移除'), findsNothing);
          }
          expect(tester.takeException(), isNull);
          await tester.pumpWidget(const SizedBox());
          await tester.pumpAndSettle();
        },
      );
    }
  }
}
