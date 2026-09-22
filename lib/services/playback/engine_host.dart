import 'dart:async';

import 'package:just_audio/just_audio.dart' as ja;

import 'audio_engine.dart';
import 'command_queue.dart';
import 'engine_event.dart';
import 'playable_source.dart';

/// Owns the native player boundary.
///
/// Owns the single native player for the process. Native operations are
/// serialized here; source attribution is handled by the engine's epoch gate.
class EngineHost implements AudioEngine {
  final AudioEngine Function() _engineFactory;
  final CommandQueue _writes = CommandQueue();
  final _positionController = StreamController<Duration>.broadcast();
  final _durationController = StreamController<Duration>.broadcast();
  final _bufferedPositionController = StreamController<Duration>.broadcast();
  final _stateController = StreamController<EngineState>.broadcast();
  final _completionController = StreamController<bool>.broadcast();
  final _errorController = StreamController<EngineError>.broadcast();
  final _eventController = StreamController<EngineEvent>.broadcast();

  AudioEngine? _active;
  final List<StreamSubscription<dynamic>> _subscriptions = [];
  int _activeEpoch = 0;
  bool _disposed = false;
  bool _isPlaying = false;
  double _volume = 0.7;
  double _playbackSpeed = 1.0;
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  Duration _bufferedPosition = Duration.zero;
  int _latestRequestedGeneration = 0;
  int _volumeRevision = 0;

  EngineHost({AudioEngine Function()? engineFactory})
    : _engineFactory = engineFactory ?? createEngine {
    _installInitialHandle();
  }

  @override
  Duration get duration => _duration;

  @override
  Duration get position => _position;

  @override
  Duration get bufferedPosition => _bufferedPosition;

  @override
  bool get isPlaying => _isPlaying;

  @override
  double get playbackSpeed => _active?.playbackSpeed ?? 1.0;

  @override
  EngineStartupTiming? get lastStartupTiming => _active?.lastStartupTiming;

  @override
  Stream<Duration> get positionStream => _positionController.stream;

  @override
  Stream<Duration> get durationStream => _durationController.stream;

  @override
  Stream<Duration> get bufferedPositionStream =>
      _bufferedPositionController.stream;

  @override
  Stream<EngineState> get stateStream => _stateController.stream;

  @override
  Stream<bool> get completionStream => _completionController.stream;

  @override
  Stream<EngineError> get errorStream => _errorController.stream;

  Stream<EngineEvent> get events => _eventController.stream;

  void _installInitialHandle() {
    final engine = _engineFactory();
    _active = engine;
    _bind(engine);
  }

  void _bind(AudioEngine engine) {
    bool current() => !_disposed && identical(_active, engine);

    _subscriptions.add(
      engine.positionStream.listen((value) {
        if (!current()) return;
        _position = value;
        _positionController.add(value);
        _eventController.add(EnginePositionEvent(_activeEpoch, value));
      }),
    );
    _subscriptions.add(
      engine.durationStream.listen((value) {
        if (!current()) return;
        _duration = value;
        _durationController.add(value);
        _eventController.add(EngineDurationEvent(_activeEpoch, value));
      }),
    );
    _subscriptions.add(
      engine.bufferedPositionStream.listen((value) {
        if (!current()) return;
        _bufferedPosition = value;
        _bufferedPositionController.add(value);
        _eventController.add(EngineBufferedPositionEvent(_activeEpoch, value));
      }),
    );
    _subscriptions.add(
      engine.stateStream.listen((state) {
        if (!current()) return;
        _isPlaying = state == EngineState.playing;
        _stateController.add(state);
        _eventController.add(EngineStateEvent(_activeEpoch, state));
      }),
    );
    _subscriptions.add(
      engine.completionStream.listen((completed) {
        if (!current() || !completed) return;
        _isPlaying = false;
        _position = Duration.zero;
        _stateController.add(EngineState.idle);
        _completionController.add(true);
        _eventController.add(EngineStateEvent(_activeEpoch, EngineState.idle));
        _eventController.add(EngineCompletedEvent(_activeEpoch));
      }),
    );
    _subscriptions.add(
      engine.errorStream.listen((error) {
        if (!current()) return;
        final eventError = _withEpoch(error, _activeEpoch);
        _errorController.add(eventError);
        _eventController.add(EngineFailureEvent(eventError.epoch, eventError));
      }),
    );
  }

  EngineError _withEpoch(EngineError error, int epoch) {
    final effectiveEpoch = error.epoch == 0 ? epoch : error.epoch;
    return EngineError(
      type: error.type,
      message: error.message,
      sourceUrl: error.sourceUrl,
      cause: error.cause,
      retriable: error.retriable,
      epoch: effectiveEpoch,
    );
  }

  Future<void> _cancelSubscriptions() async {
    final subscriptions = List<StreamSubscription<dynamic>>.from(
      _subscriptions,
    );
    _subscriptions.clear();
    for (final subscription in subscriptions) {
      await subscription.cancel();
    }
  }

  void _beginEpoch(int epoch) {
    _activeEpoch = epoch;
    _isPlaying = false;
    _position = Duration.zero;
    _duration = Duration.zero;
    _bufferedPosition = Duration.zero;
  }

  Future<T> _write<T>(Future<T> Function() action) {
    return _writes.enqueue(action);
  }

  @override
  Future<void> play(
    String url, {
    required int generation,
    bool isLocal = false,
    Map<String, String>? headers,
    bool autoPlay = true,
    Duration? initialPosition,
    bool preload = true,
  }) {
    _latestRequestedGeneration = generation;
    return _write(() async {
      if (generation != _latestRequestedGeneration) return;
      _beginEpoch(generation);
      await _active!.play(
        url,
        generation: generation,
        isLocal: isLocal,
        headers: headers,
        autoPlay: autoPlay,
        initialPosition: initialPosition,
        preload: preload,
      );
    });
  }

  @override
  Future<void> playSource(
    PlayableSource source, {
    required int generation,
    bool autoPlay = true,
    Duration? initialPosition,
    bool preload = true,
  }) {
    _latestRequestedGeneration = generation;
    return _write(() async {
      if (generation != _latestRequestedGeneration) return;
      _beginEpoch(generation);
      await _active!.playSource(
        source,
        generation: generation,
        autoPlay: autoPlay,
        initialPosition: initialPosition,
        preload: preload,
      );
    });
  }

  @override
  Future<void> playAudioSource(
    ja.AudioSource source, {
    required int generation,
    String? sourceUrl,
    bool autoPlay = true,
    Duration? initialPosition,
    bool preload = true,
  }) {
    _latestRequestedGeneration = generation;
    return _write(() async {
      if (generation != _latestRequestedGeneration) return;
      _beginEpoch(generation);
      await _active!.playAudioSource(
        source,
        generation: generation,
        sourceUrl: sourceUrl,
        autoPlay: autoPlay,
        initialPosition: initialPosition,
        preload: preload,
      );
    });
  }

  @override
  Future<void> pause() => _write(() => _active?.pause() ?? Future.value());

  @override
  Future<void> resume() => _write(() => _active?.resume() ?? Future.value());

  @override
  Future<void> seek(Duration position) =>
      _write(() => _active?.seek(position) ?? Future.value());

  @override
  Future<void> stop() => _write(() async {
    await _active?.stop();
    _isPlaying = false;
    _stateController.add(EngineState.idle);
    _eventController.add(EngineStateEvent(_activeEpoch, EngineState.idle));
  });

  @override
  Future<void> setVolume(double volume) {
    _volume = volume.clamp(0.0, 1.0);
    final revision = ++_volumeRevision;
    return _write(() async {
      if (revision != _volumeRevision) return;
      await _active?.setVolume(_volume);
    });
  }

  @override
  Future<void> setPlaybackSpeed(double speed) => _write(() async {
    _playbackSpeed = speed.clamp(0.5, 2.0);
    await _active?.setPlaybackSpeed(_playbackSpeed);
  });

  @override
  Future<void> dispose() => _write(() async {
    _disposed = true;
    final old = _active;
    _active = null;
    await _cancelSubscriptions();
    if (old != null) {
      try {
        await old.dispose();
      } catch (_) {}
    }
    await _positionController.close();
    await _durationController.close();
    await _bufferedPositionController.close();
    await _stateController.close();
    await _completionController.close();
    await _errorController.close();
    await _eventController.close();
  });
}
