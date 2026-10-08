import 'package:audio_service/audio_service.dart';
import 'package:cyrene_music/services/playback/media_transport_state.dart';
import 'package:cyrene_music/services/playback/playback_control_intent.dart';
import 'package:cyrene_music/services/playback/playback_view_state.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  MediaTransportState project(
    PlaybackSwitchPhase phase, {
    bool desired = true,
    bool engine = false,
    bool? pending,
  }) => MediaTransportState.project(
    phase: phase,
    desiredPlaying: desired,
    enginePlaying: engine,
    pendingPlaying: pending,
  );

  test('loading retains pause action; old audible track stays ready', () {
    final buffering = project(PlaybackSwitchPhase.loadingSource);
    expect(buffering.playing, isTrue);
    expect(buffering.processingState, AudioProcessingState.loading);
    final oldTrack = project(PlaybackSwitchPhase.resolving, engine: true);
    expect(oldTrack.playing, isTrue);
    expect(oldTrack.processingState, AudioProcessingState.ready);
    expect(
      project(PlaybackSwitchPhase.loadingSource, desired: false).playing,
      isFalse,
    );
  });

  test('explicit pending command wins over delayed engine acknowledgement', () {
    expect(
      project(PlaybackSwitchPhase.playing, pending: false).playing,
      isFalse,
    );
    expect(project(PlaybackSwitchPhase.paused, pending: true).playing, isTrue);
  });

  test('system pause is not concealed by retained play intent', () {
    final paused = project(PlaybackSwitchPhase.paused, desired: true);
    expect(paused.playing, isFalse);
    expect(paused.processingState, AudioProcessingState.ready);
  });

  test('stop and final failure cannot retain pending play state', () {
    expect(project(PlaybackSwitchPhase.idle, pending: true).playing, isFalse);
    expect(project(PlaybackSwitchPhase.failed, pending: true).playing, isFalse);
  });

  test('old completion cannot clear a newer command or survive stop', () {
    final intent = PlaybackControlIntent();
    final resume = intent.begin(true);
    final pause = intent.begin(false);
    intent.settle(resume);
    expect(intent.isCurrent(resume), isFalse);
    expect(intent.pendingPlaying, isFalse);
    intent.settle(pause);
    expect(intent.pendingPlaying, isNull);
    final next = intent.begin(true);
    intent.invalidate();
    expect(intent.isCurrent(next), isFalse);
  });
}
