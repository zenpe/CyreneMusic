import 'dart:async';

import 'package:cyrene_music/services/playback/audio_engine.dart';
import 'package:cyrene_music/services/playback/audio_transport_failure.dart';
import 'package:cyrene_music/services/playback/engine_failure_policy.dart';
import 'package:cyrene_music/services/playback/engine_host.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:media_kit/media_kit.dart' as mk;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const policy = EngineFailurePolicy();

  test('temporary stream interruption does not blacklist a playback URL', () {
    for (final stage in [
      AudioTransportStage.connect,
      AudioTransportStage.read,
    ]) {
      final error = mapMediaKitFailure(
        'Failed to open local audio',
        transport: AudioTransportFailure(stage, timedOut: true),
      );
      expect(policy.canRetry(error, isLocal: false), isTrue);
      expect(policy.shouldRefreshUrl(error), isFalse);
    }
  });

  test(
    'signed URL digits cannot turn an unknown load error into access denied',
    () {
      final error = mapMediaKitFailure(
        'Failed to open http://localhost:8888/proxy?url=https%3A%2F%2Fcdn.test%2F403.mp3&key=401formatnetwork',
      );
      expect(error.type, EngineErrorType.sourceLoad);
      expect(error.httpStatus, isNull);
      expect(policy.message(error), isNot(contains('http')));
      expect(policy.message(error), isNot(contains('key=')));
      expect(policy.canRetry(error, isLocal: false), isFalse);
    },
  );

  for (final status in [401, 403, 404, 410, 429, 503]) {
    test('desktop HTTP $status uses the same recovery evidence as mobile', () {
      final error = mapMediaKitFailure(
        'Failed to open local audio',
        transport: AudioTransportFailure(
          AudioTransportStage.upstream,
          statusCode: status,
        ),
      );
      expect(error.httpStatus, status);
      expect(policy.canRetry(error, isLocal: false), status != 429);
      expect(
        policy.shouldRefreshUrl(error),
        [401, 403, 404, 410].contains(status),
      );
      expect(policy.message(error), isNot(contains('Failed')));
      expect(mapMediaKitFailure('HTTP error $status').httpStatus, status);
    });
  }

  test(
    'synchronous ready state does not wait for a second stream event',
    () async {
      final player = ControlledDesktopPlayer();
      final engine = MediaKitEngine(playerFactory: () => player);
      try {
        await engine
            .play('https://audio.test/ready', generation: 1)
            .timeout(const Duration(seconds: 1));
        expect(player.plays, 1);
        expect(engine.canResumeSource(1), isTrue);
      } finally {
        await engine.dispose();
        await player.events.close();
      }
    },
  );

  for (final stage in ['open', 'initialize_volume']) {
    test(
      'new selection cancels hung $stage; late completion cannot autoplay',
      () async {
        final old = ControlledDesktopPlayer();
        final ready = ControlledDesktopPlayer();
        final gate = Completer<void>();
        if (stage == 'open') {
          old.openGate = gate;
        } else {
          old.volumeGate = gate;
        }
        var creates = 0;
        final host = EngineHost(
          minimumSourceLoadTime: Duration.zero,
          engineFactory: () => MediaKitEngine(
            playerFactory: () => creates++ == 0 ? old : ready,
            nativeCleanupTimeout: const Duration(milliseconds: 50),
          ),
        );
        final failures = <EngineError>[];
        final sub = host.errorStream.listen(failures.add);
        try {
          final first = host.play('https://audio.test/old', generation: 1);
          await (stage == 'open'
              ? old.openStarted.future
              : old.volumeStarted.future);
          final second = host.play('https://audio.test/new', generation: 2);
          await Future.wait([
            first,
            second,
          ]).timeout(const Duration(seconds: 1));
          gate.complete();
          await Future<void>.delayed(const Duration(milliseconds: 10));
          expect(old.disposed, isTrue);
          expect(old.plays, 0);
          expect(ready.plays, 1);
          expect(host.canResumeSource(2), isTrue);
          expect(failures, isEmpty);
        } finally {
          if (!gate.isCompleted) gate.complete();
          await sub.cancel();
          await host.dispose();
          await old.events.close();
          await ready.events.close();
        }
      },
    );
  }

  test(
    'pause during open keeps the loaded source paused and resumable',
    () async {
      final player = ControlledDesktopPlayer()..openGate = Completer<void>();
      final host = EngineHost(
        engineFactory: () => MediaKitEngine(playerFactory: () => player),
      );
      try {
        final loading = host.play('https://audio.test/pause', generation: 1);
        await player.openStarted.future;
        await host.pause();
        player.openGate!.complete();
        await loading.timeout(const Duration(seconds: 1));
        expect(player.plays, 0);
        expect(player.state.playing, isFalse);
        expect(host.canResumeSource(1), isTrue);
        await host.resume();
        expect(player.plays, 1);
      } finally {
        await host.dispose();
        await player.events.close();
      }
    },
  );

  test(
    'load deadline spans initialization and open; timed out handle is retired',
    () async {
      final player = ControlledDesktopPlayer()
        ..delay = const Duration(milliseconds: 35);
      final engine = MediaKitEngine(
        playerFactory: () => player,
        nativeCleanupTimeout: const Duration(milliseconds: 50),
      );
      final failures = <EngineError>[];
      final sub = engine.errorStream.listen(failures.add);
      try {
        await expectLater(
          engine.play(
            'https://audio.test/slow',
            generation: 1,
            loadTimeout: const Duration(milliseconds: 80),
          ),
          throwsA(isA<EngineReportedException>()),
        );
        await Future<void>.delayed(Duration.zero);
        expect(player.disposed, isTrue);
        expect(player.plays, 0);
        expect(failures.single.cause, isA<NativePlaybackTimeout>());
        expect(policy.canRetry(failures.single, isLocal: false), isFalse);
      } finally {
        await sub.cancel();
        await engine.dispose();
        await player.events.close();
      }
    },
  );
}

class ControlledDesktopPlayer extends Fake implements mk.Player {
  final events = _DesktopStreams();
  Completer<void>? openGate;
  Completer<void>? volumeGate;
  final openStarted = Completer<void>();
  final volumeStarted = Completer<void>();
  Duration delay = Duration.zero;
  int plays = 0;
  bool disposed = false;
  @override
  mk.PlayerState state = const mk.PlayerState();
  @override
  mk.PlayerStream get stream => events;
  @override
  mk.PlatformPlayer? get platform => null;
  @override
  Future<void> setVolume(double volume) async {
    if (!volumeStarted.isCompleted) volumeStarted.complete();
    await volumeGate?.future;
    await Future<void>.delayed(delay);
  }

  @override
  Future<void> setRate(double rate) async => Future<void>.delayed(delay);
  @override
  Future<void> open(mk.Playable media, {bool play = true}) async {
    if (!openStarted.isCompleted) openStarted.complete();
    await openGate?.future;
    await Future<void>.delayed(delay);
    state = const mk.PlayerState(
      duration: Duration(seconds: 30),
      buffer: Duration(seconds: 2),
    );
  }

  @override
  Future<void> play() async {
    plays++;
    state = state.copyWith(playing: true);
    events.playingEvents.add(true);
  }

  @override
  Future<void> pause() async {
    state = state.copyWith(playing: false);
    events.playingEvents.add(false);
  }

  @override
  Future<void> stop() async {
    state = const mk.PlayerState();
  }

  @override
  Future<void> dispose() async {
    disposed = true;
  }
}

class _DesktopStreams extends Fake implements mk.PlayerStream {
  final playingEvents = StreamController<bool>.broadcast();
  @override
  Stream<bool> get playing => playingEvents.stream;
  @override
  Stream<Duration> get position => const Stream.empty();
  @override
  Stream<Duration> get duration => const Stream.empty();
  @override
  Stream<Duration> get buffer => const Stream.empty();
  @override
  Stream<double> get rate => const Stream.empty();
  @override
  Stream<bool> get completed => const Stream.empty();
  @override
  Stream<String> get error => const Stream.empty();
  Future<void> close() => playingEvents.close();
}
