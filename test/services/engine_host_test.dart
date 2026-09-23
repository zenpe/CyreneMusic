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

  test('预备窗口通过 EngineHost 写队列串行执行', () async {
    final engine = FakeEngine();
    final host = EngineHost(engineFactory: () => engine);
    final gate = Completer<void>();
    engine.playGate = gate;
    final slot = _slot('current', 1);

    final play = host.play('a', generation: 1);
    await Future<void>.delayed(Duration.zero);
    final prepare = host.preparePlaybackWindow(
      PreparedPlaybackWindow(current: slot, next: _slot('next', 1)),
    );

    expect(engine.preparedWindows, isEmpty);
    gate.complete();
    await Future.wait([play, prepare]);
    expect(engine.preparedWindows, hasLength(1));
    await host.dispose();
  });

  test('原生当前 source 变化通过 EngineHost 保留 active epoch', () async {
    final engine = FakeEngine();
    final host = EngineHost(engineFactory: () => engine);
    final events = <EngineEvent>[];
    final subscription = host.events.listen(events.add);

    await host.play('a', generation: 7);
    engine.emitCurrentSourceKey('next');
    await Future<void>.delayed(Duration.zero);

    final sourceChanges = events
        .whereType<EngineSourceCommittedEvent>()
        .toList();
    expect(sourceChanges, hasLength(1));
    expect(sourceChanges.single.epoch, 7);
    expect(sourceChanges.single.key, 'next');

    await subscription.cancel();
    await host.dispose();
  });

  test('排队中的 prepared 激活只执行最新 generation', () async {
    final engine = FakeEngine();
    final host = EngineHost(engineFactory: () => engine);
    final gate = Completer<void>();
    engine.playGate = gate;

    final play = host.play('a', generation: 1);
    await Future<void>.delayed(Duration.zero);
    final stale = host.activatePreparedSlot(
      'b',
      generation: 2,
      queueRevision: 1,
    );
    final latest = host.activatePreparedSlot(
      'c',
      generation: 3,
      queueRevision: 1,
    );

    gate.complete();
    await Future.wait([play, stale, latest]);
    expect(engine.activatedKeys, ['c']);
    await host.dispose();
  });

  test('prepared 激活期间提交的 source 使用新 generation', () async {
    final engine = FakeEngine();
    final host = EngineHost(engineFactory: () => engine);
    final events = <EngineEvent>[];
    final subscription = host.events.listen(events.add);

    await host.play('a', generation: 1);
    engine.sourceKeyOnActivation = 'b';

    expect(
      await host.activatePreparedSlot(
        'b',
        generation: 2,
        queueRevision: 1,
      ),
      isTrue,
    );
    await Future<void>.delayed(Duration.zero);

    final sourceChanges = events
        .whereType<EngineSourceCommittedEvent>()
        .toList();
    expect(sourceChanges, hasLength(1));
    expect(sourceChanges.single.epoch, 2);
    expect(sourceChanges.single.key, 'b');

    await subscription.cancel();
    await host.dispose();
  });

  test('prepared 激活失败后恢复原 active epoch', () async {
    final engine = FakeEngine();
    final host = EngineHost(engineFactory: () => engine);
    final events = <EngineEvent>[];
    final subscription = host.events.listen(events.add);

    await host.play('a', generation: 4);
    engine.activationResult = false;

    expect(
      await host.activatePreparedSlot(
        'b',
        generation: 5,
        queueRevision: 1,
      ),
      isFalse,
    );
    engine.emitCurrentSourceKey('a');
    await Future<void>.delayed(Duration.zero);

    final sourceChanges = events
        .whereType<EngineSourceCommittedEvent>()
        .toList();
    expect(sourceChanges, hasLength(1));
    expect(sourceChanges.single.epoch, 4);
    expect(sourceChanges.single.key, 'a');

    await subscription.cancel();
    await host.dispose();
  });
}

PreparedPlaybackSlot _slot(String key, int queueRevision) =>
    PreparedPlaybackSlot(
      key: key,
      source: LocalFilePlayableSource('$key.mp3'),
      expiresAt: DateTime.now().add(const Duration(minutes: 1)),
      queueRevision: queueRevision,
    );

class FakeEngine implements AudioEngine {
  @override
  Stream<String?> get currentSourceKeyStream => _sourceKeys.stream;
  final _position = StreamController<Duration>.broadcast();
  final _duration = StreamController<Duration>.broadcast();
  final _bufferedPosition = StreamController<Duration>.broadcast();
  final _state = StreamController<EngineState>.broadcast();
  final _completion = StreamController<bool>.broadcast();
  final _errors = StreamController<EngineError>.broadcast();
  final _sourceKeys = StreamController<String?>.broadcast();
  final List<String> playedUrls = <String>[];
  final List<double> volumeWrites = <double>[];
  final List<PreparedPlaybackWindow> preparedWindows =
      <PreparedPlaybackWindow>[];
  final List<String> activatedKeys = <String>[];
  Completer<void>? playGate;
  bool activationResult = true;
  String? sourceKeyOnActivation;

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
  Future<void> preparePlaybackWindow(PreparedPlaybackWindow window) async {
    preparedWindows.add(window);
  }

  @override
  Future<bool> activatePreparedSlot(
    String key, {
    required int generation,
    required int queueRevision,
    bool autoPlay = true,
    Duration? initialPosition,
  }) async {
    activatedKeys.add(key);
    final sourceKey = sourceKeyOnActivation;
    if (sourceKey != null) _sourceKeys.add(sourceKey);
    return activationResult;
  }

  @override
  Future<void> bindCurrentPreparedSlot(PreparedPlaybackSlot slot) async {}

  @override
  Future<void> invalidatePreparedSlots() async {}

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

  void emitCurrentSourceKey(String key) => _sourceKeys.add(key);

  @override
  Future<void> dispose() async {
    // Intentionally leave the error controller open: a native callback can
    // arrive after dispose, which is the race EngineHost must isolate.
    await _position.close();
    await _duration.close();
    await _bufferedPosition.close();
    await _state.close();
    await _completion.close();
    await _sourceKeys.close();
  }
}
