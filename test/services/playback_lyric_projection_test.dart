import 'package:cyrene_music/services/lyric/lyric_snapshot.dart';
import 'package:cyrene_music/services/playback/playback_lyric_projection.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  LyricSnapshot snapshot(
    String trackKey,
    int generation,
    LyricLoadState state,
  ) {
    return LyricSnapshot(
      trackKey: trackKey,
      playbackToken: generation,
      state: state,
      lines: const [],
      lyric: state == LyricLoadState.ready ? '[00:00.00]line' : '',
      tlyric: '',
      yrc: '',
      ytlrc: '',
      qrc: '',
      qrcTrans: '',
      updatedAt: DateTime(2026),
    );
  }

  test('pending lyric loading does not replace active lyrics', () {
    final projection = PlaybackLyricProjection();
    final active = snapshot('track-a', 1, LyricLoadState.ready);
    final pending = snapshot('track-b', 2, LyricLoadState.loading);

    projection.capture(
      active,
      activeTrackKey: 'track-a',
      activeGeneration: 1,
      pendingTrackKey: null,
      pendingGeneration: 1,
    );
    projection.beginPending();
    projection.capture(
      pending,
      activeTrackKey: 'track-a',
      activeGeneration: 1,
      pendingTrackKey: 'track-b',
      pendingGeneration: 2,
    );

    expect(projection.activeFor(trackKey: 'track-a', generation: 1), active);
    expect(projection.pendingFor(trackKey: 'track-b', generation: 2), pending);
  });

  test('matching pending lyrics are promoted with the playback commit', () {
    final projection = PlaybackLyricProjection();
    final pending = snapshot('track-b', 2, LyricLoadState.ready);
    projection.capture(
      pending,
      activeTrackKey: 'track-a',
      activeGeneration: 1,
      pendingTrackKey: 'track-b',
      pendingGeneration: 2,
    );

    expect(
      projection.promote(trackKey: 'track-b', generation: 2),
      same(pending),
    );
    expect(projection.activeFor(trackKey: 'track-b', generation: 2), pending);
    expect(projection.pendingFor(trackKey: 'track-b', generation: 2), isNull);
  });

  test('mismatched track or generation cannot enter presentation state', () {
    final projection = PlaybackLyricProjection();
    final stale = snapshot('track-a', 1, LyricLoadState.ready);

    expect(
      projection.capture(
        stale,
        activeTrackKey: 'track-a',
        activeGeneration: 2,
        pendingTrackKey: 'track-b',
        pendingGeneration: 3,
      ),
      PlaybackLyricCapture.none,
    );
    expect(projection.activeFor(trackKey: 'track-a', generation: 2), isNull);
    expect(projection.pendingFor(trackKey: 'track-b', generation: 3), isNull);
  });
}
