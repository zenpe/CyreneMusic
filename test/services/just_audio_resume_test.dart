import 'dart:async';
import 'dart:convert';

import 'package:cyrene_music/services/structured_log_service.dart';
import 'package:cyrene_music/services/playback/audio_engine.dart';
import 'package:cyrene_music/services/playback/engine_host.dart';
import 'package:cyrene_music/services/playback/playable_source.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_audio/just_audio.dart' as ja;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late ControlledAudioPlayer player;
  late EngineHost host;
  late List<ControlledAudioPlayer> players;
  setUp(() async {
    player = ControlledAudioPlayer();
    players = [player];
    host = EngineHost(
      engineFactory: () => JustAudioEngine(
        playerFactory: () {
          if (player.disposed) {
            player = ControlledAudioPlayer();
            players.add(player);
          }
          return player;
        },
        bufferingStallThreshold: const Duration(milliseconds: 20),
        nativeOperationTimeout: const Duration(milliseconds: 100),
        nativeCleanupTimeout: const Duration(milliseconds: 40),
      ),
    );
    await host.play(
      'https://example.test/a.mp3',
      generation: 1,
      autoPlay: false,
    );
    await host.setVolume(0.6);
  });
  tearDown(() async {
    StructuredLogService.sink = null;
    await host.dispose();
    for (final handle in players) {
      await handle.states.close();
    }
  });

  test('pause cancels a resume waiting for output preparation', () async {
    final preparation = Completer<void>();
    player.nextMute = preparation;
    await host.resume();
    await host.pause();
    preparation.complete();
    await Future<void>.delayed(const Duration(milliseconds: 100));

    expect(player.playCalls, 0);
    expect(player.playing, isFalse);
  });

  test(
    'hung load and cleanup release the queue and isolate late callbacks',
    () async {
      final old = player;
      final load = Completer<void>();
      old.nextSourceLoad = load;
      old.stopGate = Completer<void>();
      old.disposeGate = Completer<void>();
      await host.setPlaybackSpeed(1.25);
      final errors = <EngineError>[];
      final subscription = host.errorStream.listen(errors.add);
      final failed = expectLater(
        host.play(
          'https://example.test/stuck.mp3',
          generation: 2,
          loadTimeout: const Duration(milliseconds: 20),
        ),
        throwsA(isA<EngineReportedException>()),
      );
      final next = host.play('https://example.test/next.mp3', generation: 3);
      await Future.wait([failed, next]).timeout(const Duration(seconds: 1));
      expect(player, isNot(same(old)));
      expect(player.playCalls, 1);
      expect(player.volume, 0.6);
      expect(player.speed, 1.25);
      expect(errors, hasLength(1));
      expect(errors.single.epoch, 2);
      load.complete();
      old.states.add(ja.PlayerState(true, ja.ProcessingState.completed));
      await Future<void>.delayed(const Duration(milliseconds: 100));
      expect(host.isPlaying, isTrue);
      expect(old.playCalls, 0);
      old.stopGate!.complete();
      old.disposeGate!.complete();
      await subscription.cancel();
    },
  );

  test('mute timeout does not block the next source or late resume', () async {
    final old = player;
    final resumeMute = Completer<void>();
    old.nextMute = resumeMute;
    await host.resume();
    final loadMute = Completer<void>();
    old.nextMute = loadMute;
    await expectLater(
      host.play('https://example.test/stuck.mp3', generation: 2),
      throwsA(isA<EngineReportedException>()),
    );
    await host.play('https://example.test/next.mp3', generation: 3);
    resumeMute.complete();
    loadMute.complete();
    await Future<void>.delayed(const Duration(milliseconds: 100));
    expect(old.playCalls, 0);
    expect(player.playCalls, 1);
  });

  test(
    'pause requested during a timed-out load prevents later autoplay',
    () async {
      player.nextSourceLoad = Completer<void>();
      final failed = expectLater(
        host.play(
          'https://example.test/stuck.mp3',
          generation: 2,
          loadTimeout: const Duration(milliseconds: 20),
        ),
        throwsA(isA<EngineReportedException>()),
      );
      final next = host.play('https://example.test/next.mp3', generation: 3);
      final pause = host.pause();
      await Future.wait([
        failed,
        next,
        pause,
      ]).timeout(const Duration(seconds: 1));
      expect(player.playCalls, 0);
      expect(host.isPlaying, isFalse);
    },
  );

  test('preload timeout releases a queued manual source load', () async {
    final current = PreparedPlaybackSlot(
      key: 'current',
      source: const DirectHttpPlayableSource('https://example.test/a.mp3'),
      expiresAt: DateTime.now().add(const Duration(minutes: 5)),
      queueRevision: 1,
      generation: 1,
      preparedFromGeneration: 1,
      queueEntryId: 1,
      trackKey: 'a',
      nonce: 1,
    );
    final nextSlot = PreparedPlaybackSlot(
      key: 'next',
      source: const DirectHttpPlayableSource('https://example.test/b.mp3'),
      expiresAt: DateTime.now().add(const Duration(minutes: 5)),
      queueRevision: 1,
      generation: 2,
      preparedFromGeneration: 1,
      queueEntryId: 2,
      trackKey: 'b',
      nonce: 2,
    );
    await host.bindCurrentPreparedSlot(current);
    final old = player;
    old.insertGate = Completer<void>();
    final prepare = host.preparePlaybackWindow(
      PreparedPlaybackWindow(current: current, next: nextSlot),
    );
    final next = host.play('https://example.test/manual.mp3', generation: 3);
    await Future.wait([prepare, next]).timeout(const Duration(seconds: 1));
    expect(player, isNot(same(old)));
    expect(player.playCalls, 1);
    old.insertGate!.complete();
    await Future<void>.delayed(const Duration(milliseconds: 100));
    expect(host.isPlaying, isTrue);
  });

  test('all source startup stages share one deadline', () async {
    player.sourceLoadDelay = const Duration(milliseconds: 60);
    player.speedDelay = const Duration(milliseconds: 60);
    await expectLater(
      host.play(
        'https://example.test/slow.mp3',
        generation: 2,
        loadTimeout: const Duration(milliseconds: 100),
      ),
      throwsA(isA<EngineReportedException>()),
    );
    await host.play('https://example.test/next.mp3', generation: 3);
    expect(player.playCalls, 1);
  });

  test('failed prepared activation allows a normal source load', () async {
    final slot = PreparedPlaybackSlot(
      key: 'current',
      source: const DirectHttpPlayableSource('https://example.test/a.mp3'),
      expiresAt: DateTime.now().add(const Duration(minutes: 5)),
      queueRevision: 1,
      generation: 1,
      preparedFromGeneration: 1,
      queueEntryId: 1,
      trackKey: 'a',
      nonce: 1,
    );
    await host.bindCurrentPreparedSlot(slot);
    final old = player;
    old.nextMute = Completer<void>();
    expect(
      await host.activatePreparedSlot(
        'current',
        generation: 2,
        queueRevision: 1,
        loadTimeout: const Duration(milliseconds: 20),
      ),
      isFalse,
    );
    await host.play('https://example.test/normal.mp3', generation: 3);
    expect(player, isNot(same(old)));
    expect(player.playCalls, 1);
  });

  test('hung stop releases the queue for a new playback request', () async {
    final old = player;
    old.stopGate = Completer<void>();
    final stop = expectLater(
      host.stop(),
      throwsA(isA<EngineReportedException>()),
    );
    final next = host.play('https://example.test/next.mp3', generation: 2);
    await Future.wait([stop, next]).timeout(const Duration(seconds: 1));
    expect(player, isNot(same(old)));
    expect(player.playCalls, 1);
    old.stopGate!.complete();
  });

  test(
    'prepared ready timeout cancels its listener even when cleanup hangs',
    () async {
      await host.bindCurrentPreparedSlot(_currentPreparedSlot());
      final old = player;
      old.processingState = ja.ProcessingState.loading;
      old.stopGate = Completer<void>();
      old.disposeGate = Completer<void>();
      expect(
        await host.activatePreparedSlot(
          'current',
          generation: 2,
          queueRevision: 1,
          autoPlay: false,
          loadTimeout: const Duration(milliseconds: 20),
        ),
        isFalse,
      );
      expect(old.stateListeners, 0);
      await host.play('https://example.test/next.mp3', generation: 3);
      expect(player.playCalls, 1);
      old.stopGate!.complete();
      old.disposeGate!.complete();
    },
  );

  test('prepared ready success removes only the temporary listener', () async {
    await host.bindCurrentPreparedSlot(_currentPreparedSlot());
    player.processingState = ja.ProcessingState.loading;
    final listening = Completer<void>();
    player.nextStateListener = listening;
    final activation = host.activatePreparedSlot(
      'current',
      generation: 2,
      queueRevision: 1,
      autoPlay: false,
    );
    await listening.future.timeout(const Duration(seconds: 1));
    expect(player.stateListeners, 2);
    player.processingState = ja.ProcessingState.ready;
    player.states.add(ja.PlayerState(false, ja.ProcessingState.ready));
    expect(await activation, isTrue);
    expect(player.stateListeners, 1);
  });

  test(
    'closed prepared state stream ends waiting and releases its listener',
    () async {
      await host.bindCurrentPreparedSlot(_currentPreparedSlot());
      player.processingState = ja.ProcessingState.loading;
      final listening = Completer<void>();
      player.nextStateListener = listening;
      final activation = host.activatePreparedSlot(
        'current',
        generation: 2,
        queueRevision: 1,
        autoPlay: false,
      );
      await listening.future.timeout(const Duration(seconds: 1));
      await player.states.close();
      expect(await activation.timeout(const Duration(seconds: 1)), isFalse);
      expect(player.stateListeners, 0);
    },
  );

  test('cancelled resume can resume again at the latest user volume', () async {
    final preparation = Completer<void>();
    player.nextMute = preparation;
    await host.resume();
    await host.pause();
    await host.setVolume(0.35);
    await host.resume();
    preparation.complete();
    await Future<void>.delayed(const Duration(milliseconds: 100));

    expect(player.playCalls, 1);
    expect(player.playing, isTrue);
    expect(player.volume, 0.35);
  });

  test(
    'stop invalidates an outstanding resume without restarting audio',
    () async {
      final preparation = Completer<void>();
      player.nextMute = preparation;
      await host.resume();
      await host.stop();
      preparation.complete();
      await Future<void>.delayed(const Duration(milliseconds: 100));
      expect(player.playCalls, 0);
    },
  );

  test('source replacement invalidates old resume', () async {
    final preparation = Completer<void>();
    player.nextMute = preparation;
    await host.resume();
    await host.play(
      'https://example.test/b.mp3',
      generation: 2,
      autoPlay: false,
    );
    preparation.complete();
    await Future<void>.delayed(const Duration(milliseconds: 100));
    expect(player.playCalls, 0);
    await host.resume();
    await Future<void>.delayed(const Duration(milliseconds: 100));
    expect(player.playing, isTrue);
    expect(player.volume, 0.6);
  });

  test('prepared activation completes startup and restores volume', () async {
    final current = PreparedPlaybackSlot(
      key: 'current',
      source: const DirectHttpPlayableSource('https://example.test/a.mp3'),
      expiresAt: DateTime.now().add(const Duration(minutes: 5)),
      queueRevision: 1,
      generation: 2,
      preparedFromGeneration: 1,
      queueEntryId: 1,
      trackKey: 'netease_1',
      nonce: 1,
    );
    await host.bindCurrentPreparedSlot(current);
    final activated = await host
        .activatePreparedSlot('current', generation: 2, queueRevision: 1)
        .timeout(const Duration(seconds: 1));
    expect(activated, isTrue);
    expect(player.playing, isTrue);
    expect(player.volume, 0.6);
    await Future<void>.delayed(const Duration(milliseconds: 100));
  });

  test(
    'first play completes and pause does not wait for play lifetime',
    () async {
      await host
          .play('https://example.test/b.mp3', generation: 2)
          .timeout(const Duration(seconds: 1));
      expect(player.playing, isTrue);
      expect(player.volume, 0.6);
      await host.pause().timeout(const Duration(seconds: 1));
      expect(player.playing, isFalse);
      await Future<void>.delayed(const Duration(milliseconds: 100));
    },
  );

  test(
    'buffering diagnostics close the observation without recovery',
    () async {
      final lines = <String>[];
      StructuredLogService.sink = lines.add;
      player.currentBufferedPosition = Duration.zero;
      player.processingState = ja.ProcessingState.buffering;
      player.states.add(ja.PlayerState(true, ja.ProcessingState.buffering));

      await Future<void>.delayed(const Duration(milliseconds: 40));
      player.processingState = ja.ProcessingState.ready;
      player.states.add(ja.PlayerState(true, ja.ProcessingState.ready));
      await Future<void>.delayed(Duration.zero);

      final events = lines
          .map((line) => jsonDecode(line) as Map<String, dynamic>)
          .where(
            (event) => (event['event'] as String).startsWith(
              'audio_engine.buffering_',
            ),
          )
          .toList();
      expect(events.map((event) => event['event']), [
        'audio_engine.buffering_started',
        'audio_engine.buffering_stalled',
        'audio_engine.buffering_ended',
      ]);
      expect(events[1]['stall_kind'], 'buffer_starved');
      expect(events[2]['outcome'], 'ready');
      expect(player.playCalls, 0);
    },
  );

  test('source replacement cancels the previous buffering timer', () async {
    final lines = <String>[];
    StructuredLogService.sink = lines.add;
    player.processingState = ja.ProcessingState.buffering;
    player.states.add(ja.PlayerState(true, ja.ProcessingState.buffering));
    await Future<void>.delayed(Duration.zero);

    await host.play(
      'https://example.test/replacement.mp3',
      generation: 2,
      autoPlay: false,
    );
    await Future<void>.delayed(const Duration(milliseconds: 40));

    final events = lines
        .map((line) => jsonDecode(line) as Map<String, dynamic>)
        .where(
          (event) =>
              (event['event'] as String).startsWith('audio_engine.buffering_'),
        )
        .toList();
    expect(events.map((event) => event['event']), [
      'audio_engine.buffering_started',
      'audio_engine.buffering_ended',
    ]);
    expect(events.last['outcome'], 'source_replaced');
  });

  test('late buffering from the old source is ignored while arming', () async {
    final lines = <String>[];
    StructuredLogService.sink = lines.add;
    final sourceLoadStarted = Completer<void>();
    final releaseSourceLoad = Completer<void>();
    player.nextSourceLoadStarted = sourceLoadStarted;
    player.nextSourceLoad = releaseSourceLoad;

    final replacement = host.play(
      'https://example.test/replacement.mp3',
      generation: 2,
      autoPlay: false,
    );
    try {
      await sourceLoadStarted.future.timeout(const Duration(seconds: 1));
      player.states.add(ja.PlayerState(true, ja.ProcessingState.buffering));
      await Future<void>.delayed(Duration.zero);
    } finally {
      if (!releaseSourceLoad.isCompleted) releaseSourceLoad.complete();
    }
    await replacement;
    await Future<void>.delayed(const Duration(milliseconds: 40));

    final bufferingEvents = lines
        .map((line) => jsonDecode(line) as Map<String, dynamic>)
        .where(
          (event) =>
              (event['event'] as String).startsWith('audio_engine.buffering_'),
        );
    expect(bufferingEvents, isEmpty);
  });
}

PreparedPlaybackSlot _currentPreparedSlot() => PreparedPlaybackSlot(
  key: 'current',
  source: const DirectHttpPlayableSource('https://example.test/a.mp3'),
  expiresAt: DateTime.now().add(const Duration(minutes: 5)),
  queueRevision: 1,
  generation: 1,
  preparedFromGeneration: 1,
  queueEntryId: 1,
  trackKey: 'a',
  nonce: 1,
);

/// Only the native player is replaced. Tests execute the production engine,
/// deferred output preparation and EngineHost command queue.
class ControlledAudioPlayer extends Fake implements ja.AudioPlayer {
  final states = StreamController<ja.PlayerState>.broadcast();
  int stateListeners = 0;
  Completer<void>? nextStateListener;
  late final Stream<ja.PlayerState> trackedStates = Stream.multi((controller) {
    stateListeners++;
    nextStateListener?.complete();
    nextStateListener = null;
    final subscription = states.stream.listen(
      controller.addSync,
      onError: controller.addErrorSync,
      onDone: controller.closeSync,
    );
    controller.onCancel = () {
      stateListeners--;
      return subscription.cancel();
    };
  }, isBroadcast: true);
  Completer<void>? nextMute;
  Completer<void>? nextSourceLoadStarted;
  Completer<void>? nextSourceLoad;
  Completer<void>? _playLifetime;
  int playCalls = 0;
  bool disposed = false;
  @override
  double speed = 1;
  Duration sourceLoadDelay = Duration.zero;
  Duration speedDelay = Duration.zero;
  Completer<void>? stopGate;
  Completer<void>? disposeGate;
  Completer<void>? insertGate;
  @override
  bool playing = false;
  @override
  double volume = 1;
  @override
  ja.ProcessingState processingState = ja.ProcessingState.ready;
  @override
  Duration get position => Duration.zero;
  Duration currentBufferedPosition = const Duration(seconds: 2);
  @override
  Duration get bufferedPosition => currentBufferedPosition;
  @override
  Duration? get duration => const Duration(minutes: 3);
  @override
  int? get currentIndex => 0;
  @override
  List<ja.IndexedAudioSource> sequence = [];
  @override
  Stream<Duration> get positionStream => const Stream.empty();
  @override
  Stream<Duration?> get durationStream => const Stream.empty();
  @override
  Stream<Duration> get bufferedPositionStream => const Stream.empty();
  @override
  Stream<int?> get currentIndexStream => const Stream.empty();
  @override
  Stream<ja.PlaybackEvent> get playbackEventStream => const Stream.empty();
  @override
  Stream<ja.PlayerState> get playerStateStream => trackedStates;
  @override
  Future<void> setVolume(double value) async {
    volume = value;
    if (value == 0 && nextMute != null) {
      final gate = nextMute!;
      nextMute = null;
      await gate.future;
    }
  }

  @override
  Future<void> setSpeed(double value) async {
    await Future<void>.delayed(speedDelay);
    speed = value;
  }

  @override
  Future<Duration?> setAudioSource(
    ja.AudioSource source, {
    bool preload = true,
    int? initialIndex,
    Duration? initialPosition,
  }) async {
    final started = nextSourceLoadStarted;
    nextSourceLoadStarted = null;
    if (started != null && !started.isCompleted) started.complete();
    final sourceLoad = nextSourceLoad;
    nextSourceLoad = null;
    if (sourceLoad != null) await sourceLoad.future;
    await Future<void>.delayed(sourceLoadDelay);
    sequence = [source as ja.IndexedAudioSource];
    return duration;
  }

  @override
  Future<void> seek(Duration? position, {int? index}) async {}
  @override
  Future<void> play() {
    playCalls++;
    playing = true;
    states.add(ja.PlayerState(true, processingState));
    return (_playLifetime ??= Completer<void>()).future;
  }

  @override
  Future<void> pause() async {
    playing = false;
    if (!states.isClosed) states.add(ja.PlayerState(false, processingState));
    _playLifetime?.complete();
    _playLifetime = null;
  }

  @override
  Future<void> stop() async {
    await pause();
    await stopGate?.future;
  }

  @override
  Future<void> dispose() async {
    disposed = true;
    await disposeGate?.future;
  }

  @override
  Future<void> insertAudioSource(int index, ja.AudioSource source) async {
    await insertGate?.future;
  }
}
