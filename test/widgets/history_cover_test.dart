import 'package:cached_network_image/cached_network_image.dart';
import 'package:cyrene_music/models/track.dart';
import 'package:cyrene_music/pages/home_page/home_widgets.dart';
import 'package:cyrene_music/services/play_history_service.dart';
import 'package:cyrene_music/utils/theme_manager.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets(
    'recent history uses a placeholder without loading invalid URLs',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      final history = PlayHistoryService();
      await tester.pump();
      await tester.runAsync(() => ThemeManager().ensureSettingsLoaded());
      ThemeManager().setThemeFramework(ThemeFramework.material);
      for (final url in [
        '',
        '   ',
        'not-a-url',
        'https://',
        'file:///missing',
      ]) {
        history.history
          ..clear()
          ..add(
            PlayHistoryItem(
              id: 'test',
              name: '测试歌曲',
              artists: '测试歌手',
              album: '',
              picUrl: url,
              source: MusicSource.netease,
              playedAt: DateTime(2026),
            ),
          );
        await tester.pumpWidget(
          MaterialApp(
            key: ValueKey(url),
            home: const Scaffold(body: HistorySection()),
          ),
        );
        await tester.pump();
        expect(find.byType(CachedNetworkImage), findsNothing, reason: url);
        expect(find.byIcon(Icons.music_note_rounded), findsOneWidget);
        expect(find.textContaining('测试歌曲'), findsOneWidget);
        expect(tester.takeException(), isNull, reason: url);
      }
      history.history.clear();
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}
