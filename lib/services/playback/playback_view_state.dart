import 'package:flutter/foundation.dart';

import '../../models/song_detail.dart';
import '../../models/track.dart';
import '../lyric/lyric_snapshot.dart';

enum PlaybackSwitchPhase {
  idle,
  resolving,
  loadingSource,
  ready,
  playing,
  paused,
  failed,
}

@immutable
class PlaybackViewState {
  final int generation;
  final Track? track;
  final SongDetail? song;
  final PlaybackSwitchPhase switchPhase;
  final bool desiredPlaying;
  final bool enginePlaying;
  final bool isBuffering;

  /// The native item has changed but the displayed timeline is still the old one.
  final bool isSourceTransitionPending;
  final bool? pendingPlaying;
  final Duration position;
  final Duration? duration;
  final Duration bufferedPosition;
  final LyricLoadState lyricState;
  final LyricSnapshot? lyricSnapshot;

  const PlaybackViewState({
    required this.generation,
    required this.track,
    required this.song,
    required this.switchPhase,
    required this.desiredPlaying,
    required this.enginePlaying,
    this.isBuffering = false,
    this.isSourceTransitionPending = false,
    this.pendingPlaying,
    required this.position,
    required this.duration,
    required this.bufferedPosition,
    required this.lyricState,
    required this.lyricSnapshot,
  });

  bool get isSwitching =>
      switchPhase == PlaybackSwitchPhase.resolving ||
      switchPhase == PlaybackSwitchPhase.loadingSource;

  bool get timelineReady => duration != null;
  bool get canSeek =>
      timelineReady && !isSwitching && !isSourceTransitionPending;

  /// The state presented by interactive controls. During a switch the latest
  /// transport intent wins; after commit, actual playback phase wins.
  bool get effectivePlaying => switch (switchPhase) {
    PlaybackSwitchPhase.idle || PlaybackSwitchPhase.failed => false,
    PlaybackSwitchPhase.resolving ||
    PlaybackSwitchPhase.loadingSource ||
    PlaybackSwitchPhase.ready => pendingPlaying ?? desiredPlaying,
    PlaybackSwitchPhase.playing || PlaybackSwitchPhase.paused =>
      pendingPlaying ?? switchPhase == PlaybackSwitchPhase.playing,
  };
}
