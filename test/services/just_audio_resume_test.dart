import 'dart:async';

import 'package:cyrene_music/services/playback/audio_engine.dart';
import 'package:cyrene_music/services/playback/engine_host.dart';
import 'package:cyrene_music/services/playback/playable_source.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_audio/just_audio.dart' as ja;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late ControlledAudioPlayer player;
  late EngineHost host;
  setUp(() async {
    player = ControlledAudioPlayer();
    host = EngineHost(
      engineFactory: () => JustAudioEngine(playerFactory: () => player),
    );
    await host.play(
      'https://example.test/a.mp3',
      generation: 1,
      autoPlay: false,
    );
    await host.setVolume(0.6);
  });
  tearDown(() async {
    await host.dispose();
    await player.states.close();
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
}

/// Only the native player is replaced. Tests execute the production engine,
/// deferred output preparation and EngineHost command queue.
class ControlledAudioPlayer extends Fake implements ja.AudioPlayer {
  final states = StreamController<ja.PlayerState>.broadcast();
  Completer<void>? nextMute;
  Completer<void>? _playLifetime;
  int playCalls = 0;
  @override
  bool playing = false;
  @override
  double volume = 1;
  @override
  ja.ProcessingState processingState = ja.ProcessingState.ready;
  @override
  Duration get position => Duration.zero;
  @override
  Duration get bufferedPosition => const Duration(seconds: 2);
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
  Stream<ja.PlayerState> get playerStateStream => states.stream;
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
  Future<void> setSpeed(double speed) async {}
  @override
  Future<Duration?> setAudioSource(
    ja.AudioSource source, {
    bool preload = true,
    int? initialIndex,
    Duration? initialPosition,
  }) async {
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
    states.add(ja.PlayerState(false, processingState));
    _playLifetime?.complete();
    _playLifetime = null;
  }

  @override
  Future<void> stop() => pause();
  @override
  Future<void> dispose() async {}
}
