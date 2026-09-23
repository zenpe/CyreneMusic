import 'package:cyrene_music/models/track.dart';
import 'package:cyrene_music/services/lyric/lyric_snapshot.dart';
import 'package:cyrene_music/services/playback/playback_view_state.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final track = Track(
    id: 1,
    name: 'Target',
    artists: 'Artist',
    album: 'Album',
    picUrl: 'https://example.test/cover.jpg',
  );

  test('resolving target keeps play intent while timeline is unavailable', () {
    final state = PlaybackViewState(
      generation: 7,
      track: track,
      song: null,
      switchPhase: PlaybackSwitchPhase.resolving,
      desiredPlaying: true,
      enginePlaying: false,
      position: Duration.zero,
      duration: null,
      bufferedPosition: Duration.zero,
      lyricState: LyricLoadState.loading,
      lyricSnapshot: null,
    );

    expect(state.isSwitching, isTrue);
    expect(state.desiredPlaying, isTrue);
    expect(state.timelineReady, isFalse);
    expect(state.canSeek, isFalse);
  });

  test('pause intent is independent from an in-flight track switch', () {
    final state = PlaybackViewState(
      generation: 8,
      track: track,
      song: null,
      switchPhase: PlaybackSwitchPhase.loadingSource,
      desiredPlaying: false,
      enginePlaying: true,
      position: Duration.zero,
      duration: null,
      bufferedPosition: Duration.zero,
      lyricState: LyricLoadState.loading,
      lyricSnapshot: null,
    );

    expect(state.isSwitching, isTrue);
    expect(state.desiredPlaying, isFalse);
    expect(state.enginePlaying, isTrue);
  });

  test('committed playback enables seeking only with engine duration', () {
    final state = PlaybackViewState(
      generation: 9,
      track: track,
      song: null,
      switchPhase: PlaybackSwitchPhase.playing,
      desiredPlaying: true,
      enginePlaying: true,
      position: const Duration(seconds: 12),
      duration: const Duration(minutes: 3),
      bufferedPosition: const Duration(seconds: 30),
      lyricState: LyricLoadState.empty,
      lyricSnapshot: null,
    );

    expect(state.isSwitching, isFalse);
    expect(state.timelineReady, isTrue);
    expect(state.canSeek, isTrue);
  });
}
