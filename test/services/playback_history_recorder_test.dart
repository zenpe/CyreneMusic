import 'package:cyrene_music/models/track.dart';
import 'package:cyrene_music/services/playback/playback_history_recorder.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final track = Track(
    id: 1,
    name: 'Track',
    artists: 'Artist',
    album: 'Album',
    picUrl: '',
    source: MusicSource.netease,
  );

  test('records history and play count once per playback transaction', () {
    final history = <Track>[];
    final playCounts = <Track>[];
    final recorder = PlaybackHistoryRecorder(
      addToHistory: history.add,
      recordPlayCount: playCounts.add,
      accumulateListeningTime: (_) {},
    );

    expect(recorder.recordStarted(transactionId: 7, track: track), isTrue);
    expect(recorder.recordStarted(transactionId: 7, track: track), isFalse);
    expect(history, [track]);
    expect(playCounts, [track]);
  });
}
