import '../lyric/lyric_snapshot.dart';

enum PlaybackLyricCapture { none, active, pending, cleared }

/// Keeps fetched lyric snapshots aligned with the active and pending playback
/// identities. Fetching remains owned by LyricService; presentation ownership
/// stays with PlaybackService through this projection.
class PlaybackLyricProjection {
  LyricSnapshot? _active;
  LyricSnapshot? _pending;

  LyricSnapshot? activeFor({
    required String? trackKey,
    required int generation,
  }) {
    return matching(_active, trackKey: trackKey, generation: generation);
  }

  LyricSnapshot? pendingFor({
    required String? trackKey,
    required int generation,
  }) {
    return matching(_pending, trackKey: trackKey, generation: generation);
  }

  PlaybackLyricCapture capture(
    LyricSnapshot? snapshot, {
    required String? activeTrackKey,
    required int activeGeneration,
    required String? pendingTrackKey,
    required int pendingGeneration,
  }) {
    if (snapshot == null) {
      if (activeTrackKey == null && pendingTrackKey == null) {
        clearAll();
        return PlaybackLyricCapture.cleared;
      }
      return PlaybackLyricCapture.none;
    }

    if (matches(
      snapshot,
      trackKey: pendingTrackKey,
      generation: pendingGeneration,
    )) {
      _pending = snapshot;
      return PlaybackLyricCapture.pending;
    }
    if (matches(
      snapshot,
      trackKey: activeTrackKey,
      generation: activeGeneration,
    )) {
      _active = snapshot;
      return PlaybackLyricCapture.active;
    }
    return PlaybackLyricCapture.none;
  }

  LyricSnapshot? promote({
    required String trackKey,
    required int generation,
    LyricSnapshot? fallback,
  }) {
    _active =
        matching(_pending, trackKey: trackKey, generation: generation) ??
        matching(fallback, trackKey: trackKey, generation: generation);
    _pending = null;
    return _active;
  }

  void beginPending() => _pending = null;

  void clearPending() => _pending = null;

  void clearActive() => _active = null;

  void clearAll() {
    _active = null;
    _pending = null;
  }

  static LyricSnapshot? matching(
    LyricSnapshot? snapshot, {
    required String? trackKey,
    required int generation,
  }) {
    return matches(snapshot, trackKey: trackKey, generation: generation)
        ? snapshot
        : null;
  }

  static bool matches(
    LyricSnapshot? snapshot, {
    required String? trackKey,
    required int generation,
  }) {
    return snapshot != null &&
        trackKey != null &&
        snapshot.playbackToken == generation &&
        snapshot.trackKey == trackKey;
  }
}
