import 'dart:async';
import 'dart:convert';

import 'package:cyrene_music/services/structured_log_service.dart';
import 'package:cyrene_music/services/playback/audio_engine.dart';
import 'package:cyrene_music/services/playback/engine_host.dart';
import 'package:cyrene_music/services/playback/engine_event.dart';
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
      // These tests intentionally exercise native deadlines in milliseconds,
      // independently of the production pre-load admission policy.
      minimumSourceLoadTime: Duration.zero,
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
      await handle.indices.close();
      await handle.errors.close();
    }
  });

  test(
    'official HTTP error code preserves status and playback epoch',
    () async {
      final received = <EngineError>[];
      final subscription = host.errorStream.listen(received.add);
      player.errors.add(ja.PlayerException(429, 'Source error', 0));
      await Future<void>.delayed(Duration.zero);
      expect(received, hasLength(1));
      expect(received.single.httpStatus, 429);
      expect(received.single.epoch, 1);
      await subscription.cancel();
    },
  );

  test('disabled playlist trial retains the single-source fallback', () async {
    final baselinePlayer = ControlledAudioPlayer();
    final baseline = EngineHost(
      engineFactory: () => JustAudioEngine(
        playerFactory: () => baselinePlayer,
        allowPlaylistPreload: false,
      ),
    );
    try {
      await baseline.play('https://example.test/a.mp3', generation: 1);
      final current = _currentPreparedSlot();
      await baseline.bindCurrentPreparedSlot(current);
      await baseline.preparePlaybackWindow(
        PreparedPlaybackWindow(current: current, next: _nextPreparedSlot()),
      );
      expect(baselinePlayer.insertCalls, 0);
      expect(baselinePlayer.sequence, hasLength(1));
      expect(
        await baseline.activatePreparedSlot(
          'next',
          generation: 2,
          queueRevision: 1,
        ),
        isFalse,
      );
      await baseline.play('https://example.test/b.mp3', generation: 2);
      expect(baselinePlayer.sequence, hasLength(1));
      expect(baselinePlayer.playing, isTrue);
    } finally {
      await baseline.dispose();
      await baselinePlayer.states.close();
      await baselinePlayer.indices.close();
      await baselinePlayer.errors.close();
    }
  });

  test('pause after resume stays paused without delayed output work', () async {
    final writes = player.volumeWrites.length;
    await host.resume();
    await host.pause();
    await Future<void>.delayed(const Duration(milliseconds: 100));

    expect(player.playCalls, 1);
    expect(player.playing, isFalse);
    expect(player.volumeWrites.length, writes);
  });

  test(
    'position seek waits for native readiness beyond control timeout',
    () async {
      player.seekDelay = const Duration(milliseconds: 150);
      await host
          .seek(const Duration(seconds: 10))
          .timeout(const Duration(seconds: 1));
      expect(player.disposed, isFalse);
    },
  );

  test(
    'natural prepared advancement publishes state after source commit',
    () async {
      await host.resume();
      await Future<void>.delayed(const Duration(milliseconds: 100));
      final current = _currentPreparedSlot();
      await host.bindCurrentPreparedSlot(current);
      await host.preparePlaybackWindow(
        PreparedPlaybackWindow(current: current, next: _nextPreparedSlot()),
      );
      final events = <EngineEvent>[];
      final subscription = host.events.listen(events.add);
      player.currentIndexValue = 1;
      player.indices.add(1);
      await Future<void>.delayed(const Duration(milliseconds: 50));
      final commitIndex = events.indexWhere(
        (event) => event is EngineSourceCommittedEvent && event.epoch == 2,
      );
      final stateIndex = events.indexWhere(
        (event) =>
            event is EngineStateEvent &&
            event.epoch == 2 &&
            event.state == EngineState.playing,
      );
      expect(commitIndex, greaterThanOrEqualTo(0));
      expect(stateIndex, greaterThan(commitIndex));
      expect(host.isPlaying, isTrue);
      await subscription.cancel();
    },
  );

  test(
    'natural next failure before ready belongs to next without commit',
    () async {
      final current = _currentPreparedSlot();
      await host.bindCurrentPreparedSlot(current);
      await host.preparePlaybackWindow(
        PreparedPlaybackWindow(current: current, next: _nextPreparedSlot()),
      );
      final events = <EngineEvent>[];
      final subscription = host.events.listen(events.add);
      player.currentIndexValue = 1;
      player.processingState = ja.ProcessingState.buffering;
      player.indices.add(1);
      player.errors.add(ja.PlayerException(403, 'Source error', 1));
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(events.whereType<EngineFailureEvent>().single.epoch, 2);
      expect(events.whereType<EngineSourceCommittedEvent>(), isEmpty);
      await subscription.cancel();
    },
  );

  test('error index alone cannot adopt an unselected prepared song', () async {
    final current = _currentPreparedSlot();
    await host.bindCurrentPreparedSlot(current);
    await host.preparePlaybackWindow(
      PreparedPlaybackWindow(current: current, next: _nextPreparedSlot()),
    );
    final failures = <EngineError>[];
    final subscription = host.errorStream.listen(failures.add);
    player.errors.add(ja.PlayerException(403, 'Source error', 1));
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(failures.single.epoch, 1);
    await subscription.cancel();
  });

  test('prepared seek uses load budget beyond control timeout', () async {
    final current = _currentPreparedSlot();
    await host.bindCurrentPreparedSlot(current);
    await host.preparePlaybackWindow(
      PreparedPlaybackWindow(current: current, next: _nextPreparedSlot()),
    );
    player.seekDelay = const Duration(milliseconds: 150);
    expect(
      await host.activatePreparedSlot(
        'next',
        generation: 2,
        queueRevision: 1,
        autoPlay: false,
        loadTimeout: const Duration(seconds: 1),
      ),
      isTrue,
    );
    expect(player.disposed, isFalse);
    expect(host.lastStartupTiming?.preparedActivation, isTrue);
    expect(host.lastStartupTiming?.setSourceMs, greaterThanOrEqualTo(150));
  });

  test('prepared seek remains bounded by total load deadline', () async {
    final current = _currentPreparedSlot();
    await host.bindCurrentPreparedSlot(current);
    await host.preparePlaybackWindow(
      PreparedPlaybackWindow(current: current, next: _nextPreparedSlot()),
    );
    player.seekDelay = const Duration(milliseconds: 150);
    expect(
      await host.activatePreparedSlot(
        'next',
        generation: 2,
        queueRevision: 1,
        autoPlay: false,
        loadTimeout: const Duration(milliseconds: 40),
      ),
      isFalse,
    );
    expect(player.disposed, isTrue);
    expect(host.canResumeSource(1), isFalse);
    expect(host.canResumeSource(2), isFalse);
    await expectLater(
      host.play(
        'https://example.test/expired.mp3',
        generation: 3,
        loadTimeout: Duration.zero,
      ),
      throwsA(isA<EngineReportedException>()),
    );
    expect(players, hasLength(1));
    await host.play('https://example.test/recovery.mp3', generation: 3);
    expect(player.playing, isTrue);
    expect(host.canResumeSource(3), isTrue);
  });

  test(
    'retained playing state is published after replacement commits',
    () async {
      await host.play('https://example.test/first.mp3', generation: 2);
      await Future<void>.delayed(Duration.zero);
      expect(host.isPlaying, isTrue);
      player.suppressRepeatedPlayEvent = true;
      final states = <EngineState>[];
      final subscription = host.stateStream.listen(states.add);
      await host.play('https://example.test/replacement.mp3', generation: 3);
      await Future<void>.delayed(Duration.zero);
      expect(player.playing, isTrue);
      expect(host.isPlaying, isTrue);
      expect(states.last, EngineState.playing);
      await subscription.cancel();
    },
  );

  test('non-autoplay replacement pauses a retained playing player', () async {
    await host.play('https://example.test/first.mp3', generation: 2);
    player.suppressRepeatedPlayEvent = true;
    await host.play(
      'https://example.test/paused.mp3',
      generation: 3,
      autoPlay: false,
    );
    await Future<void>.delayed(Duration.zero);
    expect(player.playing, isFalse);
    expect(host.isPlaying, isFalse);
  });

  test(
    'paused replacement stops output before native loading begins',
    () async {
      await host.resume();
      final started = Completer<void>();
      final release = Completer<void>();
      player.nextSourceLoadStarted = started;
      player.nextSourceLoad = release;
      final replacement = host.play(
        'https://example.test/paused.mp3',
        generation: 2,
        autoPlay: false,
      );
      await started.future;
      expect(player.playing, isFalse);
      release.complete();
      await replacement;
      expect(player.playing, isFalse);
    },
  );

  test(
    'pause during a successful load wins over final playing snapshot',
    () async {
      await host.play('https://example.test/first.mp3', generation: 2);
      final started = Completer<void>();
      final release = Completer<void>();
      player.nextSourceLoadStarted = started;
      player.nextSourceLoad = release;
      final load = host.play('https://example.test/next.mp3', generation: 3);
      await started.future;
      final pause = host.pause();
      release.complete();
      await Future.wait([load, pause]);
      await Future<void>.delayed(Duration.zero);
      expect(player.playing, isFalse);
      expect(host.isPlaying, isFalse);
    },
  );

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
      expect(errors.single.cause, isA<NativePlaybackTimeout>());
      expect(
        (errors.single.cause as NativePlaybackTimeout).stage,
        'load_source',
      );
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

  test('ordinary source switching and resume do not write volume', () async {
    final writes = player.volumeWrites.length;
    await host.resume();
    await host.play('https://example.test/second.mp3', generation: 2);
    await host.play('https://example.test/next.mp3', generation: 3);
    await Future<void>.delayed(const Duration(milliseconds: 100));
    expect(player.volumeWrites.length, writes);
    expect(player.volume, 0.6);
    expect(player.disposed, isFalse);
    expect(player.playing, isTrue);
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

  test(
    'background insert timeout preserves current audio and controls',
    () async {
      await host.resume();
      final current = _currentPreparedSlot();
      await host.bindCurrentPreparedSlot(current);
      final old = player;
      old.insertGate = Completer<void>();
      final failures = <EngineError>[];
      final subscription = host.errorStream.listen(failures.add);
      await host.preparePlaybackWindow(
        PreparedPlaybackWindow(current: current, next: _nextPreparedSlot()),
      );
      expect(old.disposed, isFalse);
      expect(old.playing, isTrue);
      expect(failures, isEmpty);
      await host.pause();
      expect(old.playing, isFalse);
      await host.resume();
      expect(old.playing, isTrue);
      old.insertGate!.complete();
      await Future<void>.delayed(Duration.zero);
      expect(
        await host.activatePreparedSlot(
          'next',
          generation: 2,
          queueRevision: 1,
        ),
        isTrue,
      );
      expect(player, same(old));
      expect(failures, isEmpty);
      await subscription.cancel();
    },
  );

  test(
    'late rejected preload is contained and replacement still plays',
    () async {
      await host.resume();
      final current = _currentPreparedSlot();
      await host.bindCurrentPreparedSlot(current);
      final old = player;
      old.insertGate = Completer<void>();
      await host.preparePlaybackWindow(
        PreparedPlaybackWindow(current: current, next: _nextPreparedSlot()),
      );
      old.insertGate!.completeError(StateError('insert rejected'));
      await Future<void>.delayed(Duration.zero);
      expect(old.playing, isTrue);
      await host.play('https://example.test/replacement.mp3', generation: 3);
      expect(player, same(old));
      expect(player.playing, isTrue);
    },
  );

  test(
    'preparing the same valid next slot retains its native source',
    () async {
      final current = _currentPreparedSlot();
      final next = _nextPreparedSlot();
      await host.bindCurrentPreparedSlot(current);
      await host.preparePlaybackWindow(
        PreparedPlaybackWindow(current: current, next: next),
      );
      await host.preparePlaybackWindow(
        PreparedPlaybackWindow(current: current, next: _nextPreparedSlot()),
      );
      expect(player.insertCalls, 1);
      expect(player.removeCalls, 0);
      expect(
        await host.activatePreparedSlot(
          'next',
          generation: 2,
          queueRevision: 1,
        ),
        isTrue,
      );
    },
  );

  test('all source startup stages share one deadline', () async {
    player.speed = 0.75;
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

  test(
    'source replacement does not reapply unchanged playback speed',
    () async {
      player.speedDelay = const Duration(seconds: 2);
      await host
          .play('https://example.test/same-speed.mp3', generation: 2)
          .timeout(const Duration(seconds: 1));
      expect(player.playing, isTrue);
      expect(player.speed, 1.0);
    },
  );

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
    old.seekDelay = const Duration(milliseconds: 150);
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
    await host.resume();
    await host.pause();
    await host.setVolume(0.35);
    await host.resume();
    await Future<void>.delayed(const Duration(milliseconds: 100));

    expect(player.playCalls, 2);
    expect(player.playing, isTrue);
    expect(player.volume, 0.35);
  });

  test(
    'stop invalidates an outstanding resume without restarting audio',
    () async {
      await host.resume();
      await host.stop();
      await Future<void>.delayed(const Duration(milliseconds: 100));
      expect(player.playCalls, 1);
      expect(player.playing, isFalse);
    },
  );

  test('source replacement invalidates old resume', () async {
    await host.resume();
    await host.play(
      'https://example.test/b.mp3',
      generation: 2,
      autoPlay: false,
    );
    await Future<void>.delayed(const Duration(milliseconds: 100));
    expect(player.playCalls, 1);
    expect(player.playing, isFalse);
    await host.resume();
    await Future<void>.delayed(const Duration(milliseconds: 100));
    expect(player.playing, isTrue);
    expect(player.volume, 0.6);
  });

  test('prepared activation starts without additional volume writes', () async {
    final writes = player.volumeWrites.length;
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
    expect(player.volumeWrites.length, writes);
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
    'buffered playing flag alone does not complete startup while buffering',
    () async {
      player.processingState = ja.ProcessingState.buffering;
      var finished = false;
      final load = host
          .play('https://example.test/buffering.mp3', generation: 2)
          .then((_) => finished = true);
      for (var i = 0; i < 50 && player.playCalls == 0; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 1));
      }
      expect(player.playCalls, 1);
      await Future<void>.delayed(const Duration(milliseconds: 5));
      expect(finished, isFalse);
      player.processingState = ja.ProcessingState.ready;
      player.states.add(ja.PlayerState(true, ja.ProcessingState.ready));
      await load.timeout(const Duration(seconds: 1));
      expect(finished, isTrue);
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

  Future<void> enableSingleSource() async {
    await host.dispose();
    player = ControlledAudioPlayer();
    players.add(player);
    host = EngineHost(
      minimumSourceLoadTime: Duration.zero,
      engineFactory: () => JustAudioEngine(
        playerFactory: () {
          if (player.disposed) {
            player = ControlledAudioPlayer();
            players.add(player);
          }
          return player;
        },
        allowPlaylistPreload: false,
        nativeOperationTimeout: const Duration(milliseconds: 100),
      ),
    );
    await host.play(
      'https://example.test/a.mp3',
      generation: 1,
      autoPlay: false,
    );
  }

  test(
    'single-source prefetch never loads the next item into the player',
    () async {
      await enableSingleSource();
      await host.resume();
      final active = player.sequence.single;
      await host.bindCurrentPreparedSlot(_currentPreparedSlot());
      await host.preparePlaybackWindow(
        PreparedPlaybackWindow(
          current: _currentPreparedSlot(),
          next: _nextPreparedSlot(),
        ),
      );
      expect(player.insertCalls, 0);
      expect(player.sequence, hasLength(1));
      expect(identical(player.sequence.single, active), isTrue);
      expect(player.playing, isTrue);
      expect(
        await host.activatePreparedSlot(
          'next',
          generation: 2,
          queueRevision: 1,
        ),
        isFalse,
      );
      expect(player.disposed, isFalse);
    },
  );

  test('single-source invalidation leaves current playback intact', () async {
    await enableSingleSource();
    await host.resume();
    await host.bindCurrentPreparedSlot(_currentPreparedSlot());
    final active = player.sequence.single;
    await host.invalidatePreparedSlots();
    expect(identical(player.sequence.single, active), isTrue);
    expect(player.playing, isTrue);
    expect(player.removeCalls, 0);
  });

  test(
    'official source replacement retains one item and paused intent',
    () async {
      await enableSingleSource();
      final original = player;
      for (var generation = 2; generation <= 4; generation++) {
        await host.play(
          'https://example.test/$generation.mp3',
          generation: generation,
          autoPlay: false,
        );
        expect(identical(player, original), isTrue);
        expect(player.sequence, hasLength(1));
        expect(player.currentIndex, 0);
        expect(player.playing, isFalse);
      }
      expect(player.insertCalls, 0);
      expect(player.removeCalls, 0);
    },
  );

  test(
    'official source rejection releases the player and allows recovery',
    () async {
      await enableSingleSource();
      final failed = player;
      player.nextSourceError = ja.PlayerException(403, 'Forbidden', 0);
      await expectLater(
        host.play(
          'https://example.test/bad.mp3',
          generation: 2,
          autoPlay: false,
        ),
        throwsA(
          isA<EngineReportedException>().having(
            (e) => e.error.type,
            'type',
            EngineErrorType.accessDenied,
          ),
        ),
      );
      expect(failed.disposed, isTrue);
      await host.play(
        'https://example.test/recover.mp3',
        generation: 3,
        autoPlay: false,
      );
      expect(identical(player, failed), isFalse);
      expect(player.sequence, hasLength(1));
      expect(player.playing, isFalse);
    },
  );

  test(
    'official source timeout isolates late completion from the new player',
    () async {
      await enableSingleSource();
      final failed = player;
      final loading = Completer<void>();
      player.nextSourceLoad = loading;
      await expectLater(
        host.play(
          'https://example.test/slow.mp3',
          generation: 2,
          autoPlay: false,
          loadTimeout: const Duration(milliseconds: 25),
        ),
        throwsA(isA<EngineReportedException>()),
      );
      expect(failed.disposed, isTrue);
      await host.play(
        'https://example.test/recover.mp3',
        generation: 3,
        autoPlay: false,
      );
      loading.complete();
      await Future<void>.delayed(Duration.zero);
      expect(identical(player, failed), isFalse);
      expect(player.sequence, hasLength(1));
      expect(player.playing, isFalse);
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

PreparedPlaybackSlot _nextPreparedSlot() => PreparedPlaybackSlot(
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

/// Only the native player is replaced. Tests execute the production engine,
/// deferred output preparation and EngineHost command queue.
class ControlledAudioPlayer extends Fake implements ja.AudioPlayer {
  Object? nextSourceError;
  final states = StreamController<ja.PlayerState>.broadcast();
  final indices = StreamController<int?>.broadcast();
  int currentIndexValue = 0;
  Duration seekDelay = Duration.zero;
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
  final volumeWrites = <double>[];
  Completer<void>? nextSourceLoadStarted;
  Completer<void>? nextSourceLoad;
  Completer<void>? _playLifetime;
  int playCalls = 0;
  bool suppressRepeatedPlayEvent = false;
  bool disposed = false;
  @override
  double speed = 1;
  Duration sourceLoadDelay = Duration.zero;
  Duration speedDelay = Duration.zero;
  Completer<void>? stopGate;
  Completer<void>? disposeGate;
  Completer<void>? insertGate;
  int insertCalls = 0;
  int removeCalls = 0;
  Object? removeError;
  ja.PlayerException? nextSeekError;
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
  int? get currentIndex => currentIndexValue;
  @override
  List<ja.IndexedAudioSource> sequence = [];
  @override
  Stream<Duration> get positionStream => const Stream.empty();
  @override
  Stream<Duration?> get durationStream => const Stream.empty();
  @override
  Stream<Duration> get bufferedPositionStream => const Stream.empty();
  @override
  Stream<int?> get currentIndexStream => indices.stream;
  @override
  Stream<ja.PlaybackEvent> get playbackEventStream => const Stream.empty();
  final errors = StreamController<ja.PlayerException>.broadcast();
  @override
  Stream<ja.PlayerException> get errorStream => errors.stream;
  @override
  Stream<ja.PlayerState> get playerStateStream => trackedStates;
  @override
  Future<void> setVolume(double value) async {
    volumeWrites.add(value);
    volume = value;
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
    final error = nextSourceError;
    nextSourceError = null;
    if (error != null) throw error;
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
  Future<void> seek(Duration? position, {int? index}) async {
    final error = nextSeekError;
    nextSeekError = null;
    if (error != null) {
      errors.add(error);
      return Completer<void>().future;
    }
    await Future<void>.delayed(seekDelay);
    if (index != null) currentIndexValue = index;
  }

  @override
  Future<void> play() {
    playCalls++;
    final wasPlaying = playing;
    playing = true;
    if (!wasPlaying || !suppressRepeatedPlayEvent) {
      states.add(ja.PlayerState(true, processingState));
    }
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
    insertCalls++;
    await insertGate?.future;
    sequence.insert(index, source as ja.IndexedAudioSource);
  }

  @override
  Future<void> removeAudioSourceAt(int index) async {
    removeCalls++;
    if (removeError != null) throw removeError!;
    sequence.removeAt(index);
    if (index < currentIndexValue) currentIndexValue--;
  }
}
