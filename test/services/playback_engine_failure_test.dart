import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:cyrene_music/models/track.dart';
import 'package:cyrene_music/services/auth_service.dart';
import 'package:cyrene_music/services/playback/audio_engine.dart';
import 'package:cyrene_music/services/playback/engine_host.dart';
import 'package:cyrene_music/services/playback/playable_source.dart';
import 'package:cyrene_music/services/playback/playback_service.dart';
import 'package:cyrene_music/services/playback/queue_controller.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  tearDownAll(() async {
    AuthService().onSessionEnded = null;
    await AuthService().logout();
  });

  for (final retriable in [false, true]) {
    test(
      'load failure finishes without an error stream (retry=$retriable)',
      () async {
        SharedPreferences.setMockInitialValues({
          'auth_token': 'local-test-token',
          'current_user': jsonEncode({
            'id': 1,
            'username': 'test',
            'email': 'test@example.invalid',
          }),
        });
        final auth = AuthService();
        await auth.ensureInitialized();
        final engine = _FailingEngine(retriable);
        final playback = PlaybackService.forTesting(
          engine: EngineHost(engineFactory: () => engine),
        );
        // Existing local content takes resolution/network variability out of the
        // test; the production switch chain still reaches the native load stage.
        final track = Track(
          id: File('pubspec.yaml').absolute.path,
          name: 'load failure',
          artists: '',
          album: '',
          picUrl: '',
          source: MusicSource.local,
        );
        try {
          await playback
              .playNow([track], 0, QueueSource.none)
              .timeout(const Duration(seconds: 2));
          expect(
            engine.loads,
            retriable ? 2 : 1,
            reason: playback.errorMessage,
          );
          expect(playback.state, PBState.error);
          expect(playback.isTrackSwitchPending, isFalse);
          if (retriable) {
            final second = Track(
              id: File('android/app/build.gradle.kts').absolute.path,
              name: 'second load failure',
              artists: '',
              album: '',
              picUrl: '',
              source: MusicSource.local,
            );
            await playback.playNow([track, second], 0, QueueSource.none);
            engine.loads = 0;
            await playback.next().timeout(const Duration(seconds: 2));
            // Navigation gives each candidate one load attempt instead of
            // spending its budget rebuilding the same failed candidate.
            expect(engine.loads, 2);
            expect(playback.state, PBState.error);
            expect(playback.isTrackSwitchPending, isFalse);
            expect(playback.pendingPlaybackIntent, isNull);
          }
          expect(playback.pendingPlaybackIntent, isNull);
          expect(playback.errorMessage, contains('播放失败'));
          await playback.resume().timeout(const Duration(seconds: 2));
          expect(engine.loads, greaterThan(retriable ? 2 : 1));
          expect(playback.state, PBState.error);
          expect(playback.isTrackSwitchPending, isFalse);
        } finally {
          playback.dispose();
        }
      },
    );
  }
}

class _FailingEngine extends Fake implements AudioEngine {
  _FailingEngine(this.retriable);
  final bool retriable;
  int loads = 0;
  @override
  bool get isPlaying => false;
  @override
  Stream<Duration> get positionStream => const Stream.empty();
  @override
  Stream<Duration> get durationStream => const Stream.empty();
  @override
  Stream<Duration> get bufferedPositionStream => const Stream.empty();
  @override
  Stream<EngineState> get stateStream => const Stream.empty();
  @override
  Stream<bool> get completionStream => const Stream.empty();
  @override
  Stream<EngineError> get errorStream => const Stream.empty();
  @override
  Stream<EngineSourceCommit> get sourceCommitStream => const Stream.empty();
  @override
  Future<void> playSource(
    PlayableSource source, {
    required int generation,
    bool autoPlay = true,
    Duration? initialPosition,
    bool preload = true,
    Duration? loadTimeout,
  }) async {
    loads++;
    throw EngineReportedException(
      EngineError(
        type: EngineErrorType.sourceLoad,
        message: 'audio load failed',
        retriable: retriable,
        epoch: generation,
      ),
    );
  }

  @override
  Future<void> invalidatePreparedSlots() async {}
  @override
  Future<void> stop() async {}
  @override
  Future<void> dispose() async {}
}
