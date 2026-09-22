import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:just_audio/just_audio.dart' as ja;

import 'package:cyrene_music/services/playback/audio_engine.dart';
import 'package:cyrene_music/services/playback/engine_event.dart';
import 'package:cyrene_music/services/playback/engine_host.dart';
import 'package:cyrene_music/services/playback/playable_source.dart';

void main() {
  test('单一 engine 的错误保留源头 epoch，供协调器丢弃旧事件', () async {
    final engines = <FakeEngine>[];
    final host = EngineHost(
      engineFactory: () {
        final engine = FakeEngine();
        engines.add(engine);
        return engine;
      },
    );
    final events = <EngineEvent>[];
    final subscription = host.events.listen(events.add);

    await host.play('a', generation: 1);
    await host.play('b', generation: 2);
    final engine = engines.single;

    engine.emitError(
      const EngineError(
        type: EngineErrorType.sourceLoad,
        message: 'late old error',
        retriable: true,
        epoch: 1,
      ),
    );
    engine.emitError(
      const EngineError(
        type: EngineErrorType.sourceLoad,
        message: 'current error',
        retriable: true,
        epoch: 2,
      ),
    );
    await Future<void>.delayed(Duration.zero);

    final failures = events.whereType<EngineFailureEvent>().toList();
    expect(failures, hasLength(2));
    expect(failures.map((event) => event.epoch), [1, 2]);
    expect(failures.last.error.message, 'current error');

    await subscription.cancel();
    await host.dispose();
  });

  test('排队中的切歌只执行最新 generation', () async {
    final engine = FakeEngine();
    final host = EngineHost(engineFactory: () => engine);
    final gate = Completer<void>();
    engine.playGate = gate;

    final first = host.play('a', generation: 1);
    await Future<void>.delayed(Duration.zero);
    final second = host.play('b', generation: 2);
    final third = host.play('c', generation: 3);

    gate.complete();
    await Future.wait([first, second, third]);

    expect(engine.playedUrls, ['a', 'c']);
    await host.dispose();
  });

  test('排队中的音量写入会合并为最后一个值', () async {
    final engine = FakeEngine();
    final host = EngineHost(engineFactory: () => engine);
    final gate = Completer<void>();
    engine.playGate = gate;

    final play = host.play('a', generation: 1);
    await Future<void>.delayed(Duration.zero);
    final firstVolume = host.setVolume(0.2);
    final lastVolume = host.setVolume(0.8);

    gate.complete();
    await Future.wait([play, firstVolume, lastVolume]);

    expect(engine.volumeWrites, [0.8]);
    await host.dispose();
  });
}

class FakeEngine implements AudioEngine {
  final _position = StreamController<Duration>.broadcast();
  final _duration = StreamController<Duration>.broadcast();
  final _bufferedPosition = StreamController<Duration>.broadcast();
  final _state = StreamController<EngineState>.broadcast();
  final _completion = StreamController<bool>.broadcast();
  final _errors = StreamController<EngineError>.broadcast();
  final List<String> playedUrls = <String>[];
  final List<double> volumeWrites = <double>[];
  Completer<void>? playGate;

  @override
  Duration duration = Duration.zero;

  @override
  Duration position = Duration.zero;

  @override
  Duration bufferedPosition = Duration.zero;

  @override
  bool isPlaying = false;

  @override
  double playbackSpeed = 1.0;

  @override
  EngineStartupTiming? get lastStartupTiming => null;

  @override
  Stream<Duration> get positionStream => _position.stream;

  @override
  Stream<Duration> get durationStream => _duration.stream;

  @override
  Stream<Duration> get bufferedPositionStream => _bufferedPosition.stream;

  @override
  Stream<EngineState> get stateStream => _state.stream;

  @override
  Stream<bool> get completionStream => _completion.stream;

  @override
  Stream<EngineError> get errorStream => _errors.stream;

  @override
  Future<void> play(
    String url, {
    required int generation,
    bool isLocal = false,
    Map<String, String>? headers,
    bool autoPlay = true,
    Duration? initialPosition,
    bool preload = true,
  }) async {
    playedUrls.add(url);
    final gate = playGate;
    playGate = null;
    await gate?.future;
  }

  @override
  Future<void> playAudioSource(
    ja.AudioSource source, {
    required int generation,
    String? sourceUrl,
    bool autoPlay = true,
    Duration? initialPosition,
    bool preload = true,
  }) async {}

  @override
  Future<void> playSource(
    PlayableSource source, {
    required int generation,
    bool autoPlay = true,
    Duration? initialPosition,
    bool preload = true,
  }) async {}

  @override
  Future<void> pause() async {}

  @override
  Future<void> resume() async {}

  @override
  Future<void> seek(Duration position) async {}

  @override
  Future<void> stop() async {}

  @override
  Future<void> setVolume(double volume) async {
    volumeWrites.add(volume);
  }

  @override
  Future<void> setPlaybackSpeed(double speed) async {
    playbackSpeed = speed;
  }

  void emitError(EngineError error) => _errors.add(error);

  @override
  Future<void> dispose() async {
    // Intentionally leave the error controller open: a native callback can
    // arrive after dispose, which is the race EngineHost must isolate.
    await _position.close();
    await _duration.close();
    await _bufferedPosition.close();
    await _state.close();
    await _completion.close();
  }
}
