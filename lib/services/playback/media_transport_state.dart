import 'package:audio_service/audio_service.dart';

import 'playback_view_state.dart';

/// Read-only projection for system media controls. Engine pauses remain visible
/// when no user command is pending (for example an audio-focus interruption).
class MediaTransportState {
  final bool playing;
  final AudioProcessingState processingState;

  const MediaTransportState(this.playing, this.processingState);

  factory MediaTransportState.project({
    required PlaybackSwitchPhase phase,
    required bool desiredPlaying,
    required bool enginePlaying,
    bool? pendingPlaying,
    bool buffering = false,
  }) {
    switch (phase) {
      case PlaybackSwitchPhase.idle:
        return const MediaTransportState(false, AudioProcessingState.idle);
      case PlaybackSwitchPhase.failed:
        return const MediaTransportState(false, AudioProcessingState.error);
      case PlaybackSwitchPhase.resolving:
      case PlaybackSwitchPhase.loadingSource:
      case PlaybackSwitchPhase.ready:
        return MediaTransportState(
          pendingPlaying ?? desiredPlaying,
          enginePlaying
              ? AudioProcessingState.ready
              : AudioProcessingState.loading,
        );
      case PlaybackSwitchPhase.playing:
      case PlaybackSwitchPhase.paused:
        return MediaTransportState(
          pendingPlaying ?? (phase == PlaybackSwitchPhase.playing),
          buffering
              ? AudioProcessingState.buffering
              : AudioProcessingState.ready,
        );
    }
  }
}
