import 'package:cyrene_music/models/track.dart';
import 'package:cyrene_music/pages/home_page/personal_recommendation_cards.dart';
import 'package:cyrene_music/utils/theme_manager.dart';
import 'package:fluent_ui/fluent_ui.dart' as fluent;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  for (final framework in [ThemeFramework.material, ThemeFramework.fluent]) {
    testWidgets('daily preview and FM actions adapt to layout ($framework)', (
      tester,
    ) async {
      SharedPreferences.setMockInitialValues({});
      await tester.runAsync(() async {
        await ThemeManager().ensureSettingsLoaded();
        ThemeManager().setThemeFramework(framework);
      });
      await tester.binding.setSurfaceSize(const Size(1200, 1600));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      for (final width in [320.0, 1000.0]) {
        var opened = false;
        int? played;
        var fmPlayed = 0;
        var refreshed = 0;
        final songs = List.generate(
          30,
          (i) => <String, dynamic>{
            'id': i + 1,
            'name': '每日歌曲 ${i + 1}',
            'ar': [
              {'name': '歌手 ${i + 1}'},
            ],
          },
        );
        final content = Align(
          alignment: Alignment.topLeft,
          child: SizedBox(
            width: width,
            child: SingleChildScrollView(
              child: Column(
                children: [
                  DailySongsPreview(
                    songs: songs,
                    onOpenAll: () => opened = true,
                    onPlay: (index) => played = index,
                  ),
                  const SizedBox(height: 24),
                  PersonalFmPreview(
                    track: Track(
                      id: 100,
                      name: 'FM 歌曲',
                      artists: 'FM 歌手',
                      album: '专辑',
                      picUrl: '',
                    ),
                    playing: false,
                    loading: false,
                    onPlayPause: () => fmPlayed++,
                    onRefresh: () => refreshed++,
                  ),
                ],
              ),
            ),
          ),
        );
        await tester.pumpWidget(
          framework == ThemeFramework.fluent
              ? fluent.FluentApp(home: fluent.ScaffoldPage(content: content))
              : MaterialApp(home: Scaffold(body: content)),
        );
        await tester.pumpAndSettle();
        expect(find.text('每日歌曲 1'), findsOneWidget);
        expect(find.text('每日歌曲 3'), findsOneWidget);
        expect(
          find.text('每日歌曲 6'),
          width >= 720 ? findsOneWidget : findsNothing,
        );
        expect(find.text('每日歌曲 7'), findsNothing);
        expect(find.text('FM 歌曲'), findsOneWidget);
        expect(find.text('FM 歌手'), findsOneWidget);
        await tester.tap(find.text('每日歌曲 2'));
        expect(played, 1);
        await tester.tap(find.text('查看全部'));
        expect(opened, isTrue);
        await tester.tap(find.text('播放全部'));
        expect(played, 0);
        await tester.ensureVisible(find.text('播放'));
        await tester.tap(find.text('播放'));
        await tester.tap(find.text('换一批'));
        expect(fmPlayed, 1);
        expect(refreshed, 1);
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull, reason: '$framework, $width');
      }
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }
  testWidgets('FM loading disables actions and paused state offers play', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    await tester.runAsync(() async {
      await ThemeManager().ensureSettingsLoaded();
      ThemeManager().setThemeFramework(ThemeFramework.material);
    });
    var actions = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PersonalFmPreview(
            track: null,
            playing: false,
            loading: true,
            onPlayPause: () => actions++,
            onRefresh: () => actions++,
          ),
        ),
      ),
    );
    await tester.tap(find.text('正在加载…'));
    await tester.tap(find.text('换一批'));
    expect(actions, 0);
    expect(find.text('正在寻找合你口味的歌曲…'), findsOneWidget);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PersonalFmPreview(
            track: null,
            playing: true,
            loading: false,
            error: '网络暂不可用',
            onPlayPause: () => actions++,
            onRefresh: () => actions++,
          ),
        ),
      ),
    );
    expect(find.text('暂停'), findsOneWidget);
    expect(find.text('网络暂不可用'), findsOneWidget);
    await tester.tap(find.text('暂停'));
    expect(actions, 1);
    expect(tester.takeException(), isNull);
  });
}
