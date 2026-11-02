import 'package:cyrene_music/models/track.dart';
import 'package:cyrene_music/services/playback/playback_service.dart';
import 'package:cyrene_music/services/playlist_queue_service.dart';
import 'package:cyrene_music/services/playback_mode_service.dart';
import 'package:cyrene_music/widgets/collection_play_controls.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('collection labels and icons follow ordinary mode changes', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final modes = PlaybackModeService();
    await tester.runAsync(() => modes.setMode(PlaybackMode.loopAll));
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: Row(
            children: [
              PlayAllIcon(Icons.play_arrow),
              PlayAllLabel('播放全部 (12)'),
            ],
          ),
        ),
      ),
    );
    expect(find.text('播放全部 (12)'), findsOneWidget);
    expect(find.byIcon(Icons.play_arrow), findsOneWidget);
    await tester.runAsync(() => modes.setMode(PlaybackMode.shuffle));
    await tester.pump();
    expect(find.text('随机播放 (12)'), findsOneWidget);
    expect(find.byIcon(Icons.shuffle_rounded), findsOneWidget);
    await tester.runAsync(() => modes.setMode(PlaybackMode.sequential));
    await tester.pump();
    expect(find.text('播放全部 (12)'), findsOneWidget);
  });

  testWidgets('FM hides ordinary mode controls and leaving FM restores them', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final playback = PlaybackService();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: OrdinaryPlaybackModeBuilder(
            builder: (_, _) => const Text('普通播放模式'),
          ),
        ),
      ),
    );
    expect(find.text('普通播放模式'), findsOneWidget);
    final track = Track(
      id: 1,
      name: 'Song',
      artists: '',
      album: '',
      picUrl: '',
      source: MusicSource.local,
    );
    playback.setQueueSilent([track], 0, QueueSource.neteaseFm);
    await tester.pump();
    expect(find.text('普通播放模式'), findsNothing);
    playback.setQueueSilent([track], 0, QueueSource.album);
    await tester.pump();
    expect(find.text('普通播放模式'), findsOneWidget);
    playback.setQueueSilent([], 0, QueueSource.none);
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();
  });
}
