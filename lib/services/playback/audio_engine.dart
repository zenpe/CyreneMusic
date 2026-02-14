import 'dart:async';
import 'dart:io';

import 'package:just_audio/just_audio.dart' as ja;
import 'package:media_kit/media_kit.dart' as mk;

import '../android_equalizer_service.dart';
import '../equalizer_service.dart';
import '../persistent_storage_service.dart';

/// 统一播放状态
enum EngineState { idle, playing, paused }

/// 引擎错误类型
enum EngineErrorType {
  networkTimeout,
  accessDenied,
  unsupportedFormat,
  sourceLoad,
  playback,
  unknown,
}

/// 引擎错误事件
class EngineError {
  final EngineErrorType type;
  final String message;
  final String? sourceUrl;
  final Object? cause;
  final bool retriable;

  const EngineError({
    required this.type,
    required this.message,
    this.sourceUrl,
    this.cause,
    this.retriable = false,
  });

  @override
  String toString() {
    return 'EngineError(type: $type, retriable: $retriable, sourceUrl: $sourceUrl, message: $message)';
  }
}

/// 引擎内部已上报到 `errorStream` 的异常包装。
/// 调用方可据此避免与 `errorStream` 重复处理同一错误。
class EngineReportedException implements Exception {
  final EngineError error;

  const EngineReportedException(this.error);

  @override
  String toString() => 'EngineReportedException($error)';
}

/// 统一音频引擎接口
abstract class AudioEngine {
  Future<void> play(
    String url, {
    bool isLocal = false,
    Map<String, String>? headers,
  });
  Future<void> pause();
  Future<void> resume();
  Future<void> seek(Duration position);
  Future<void> stop();
  Future<void> setVolume(double volume);
  Future<void> setPlaybackSpeed(double speed);
  Future<void> preload(
    String url, {
    bool isLocal = false,
    Map<String, String>? headers,
  });
  Future<void> dispose();

  Stream<Duration> get positionStream;
  Stream<Duration> get durationStream;
  Stream<Duration> get bufferedPositionStream;
  Stream<EngineState> get stateStream;
  Stream<bool> get completionStream;
  Stream<EngineError> get errorStream;

  Duration get duration;
  Duration get position;
  Duration get bufferedPosition;
  bool get isPlaying;
  double get playbackSpeed;
}

/// 根据平台选择引擎
AudioEngine createEngine() {
  if (Platform.isWindows || Platform.isMacOS || Platform.isLinux) {
    return MediaKitEngine();
  }
  return JustAudioEngine();
}

// ─────────────────────────────────────────────────────────
// JustAudio 实现（Android / iOS）
// ─────────────────────────────────────────────────────────
class JustAudioEngine implements AudioEngine, EqualizerCapable {
  JustAudioEngine() {
    EqualizerService().setBackend(this);
  }

  ja.AudioPlayer? _player;
  ja.AudioPlayer? _preloadPlayer;
  double _currentVolume = 1.0;
  double _playbackSpeed = 1.0;
  bool _hasSource = false;
  int? _androidAudioSessionId;
  bool _equalizerEnabled = true;
  List<double> _equalizerGains = List.filled(10, 0.0);
  List<int> _equalizerFrequencies = EqualizerService.kEqualizerFrequencies;

  final _positionController = StreamController<Duration>.broadcast();
  final _durationController = StreamController<Duration>.broadcast();
  final _bufferedPositionController = StreamController<Duration>.broadcast();
  final _stateController = StreamController<EngineState>.broadcast();
  final _completionController = StreamController<bool>.broadcast();
  final _errorController = StreamController<EngineError>.broadcast();

  StreamSubscription<Duration>? _positionSub;
  StreamSubscription<Duration?>? _durationSub;
  StreamSubscription<Duration>? _bufferedPositionSub;
  StreamSubscription<ja.PlayerState>? _playerStateSub;
  StreamSubscription<ja.PlaybackEvent>? _eventSub;
  StreamSubscription<int?>? _androidSessionSub;

  Duration _duration = Duration.zero;
  Duration _position = Duration.zero;
  Duration _bufferedPosition = Duration.zero;
  bool _isPlaying = false;

  @override
  Duration get duration => _duration;

  @override
  Duration get position => _position;

  @override
  Duration get bufferedPosition => _bufferedPosition;

  @override
  bool get isPlaying => _isPlaying;

  @override
  double get playbackSpeed => _playbackSpeed;

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

  Future<void> _ensurePlayer() async {
    if (_player != null) return;

    // 移动端不使用 MediaKit 均衡器实现，避免 native EQ 路径影响播放稳定性。
    EqualizerService().setBackend(this);

    final player = ja.AudioPlayer();
    _player = player;

    final savedVolume = PersistentStorageService().getDouble('player_volume');
    _currentVolume = (savedVolume ?? 0.7).clamp(0.0, 1.0);
    await player.setVolume(_currentVolume);
    await player.setSpeed(_playbackSpeed);

    _positionSub = player.positionStream.listen((pos) {
      _position = pos;
      _positionController.add(pos);
    });

    _durationSub = player.durationStream.listen((dur) {
      _duration = dur ?? Duration.zero;
      _durationController.add(_duration);
    });

    _bufferedPositionSub = player.bufferedPositionStream.listen((buffered) {
      _bufferedPosition = buffered;
      _bufferedPositionController.add(buffered);
    });

    _playerStateSub = player.playerStateStream.listen((state) {
      final processing = state.processingState;
      if (processing == ja.ProcessingState.completed) {
        _isPlaying = false;
        _position = Duration.zero;
        _stateController.add(EngineState.idle);
        _completionController.add(true);
        return;
      }

      if (state.playing) {
        _isPlaying = true;
        _stateController.add(EngineState.playing);
        return;
      }

      if (_isPlaying) {
        _isPlaying = false;
        if (processing == ja.ProcessingState.idle) {
          _stateController.add(EngineState.idle);
        } else {
          _stateController.add(EngineState.paused);
        }
      }
    });

    _eventSub = player.playbackEventStream.listen(
      (_) {},
      onError: (Object e, StackTrace st) {
        _emitError(_mapJustAudioError(e));
        if (!_stateController.isClosed) {
          _stateController.add(EngineState.idle);
        }
      },
    );

    if (Platform.isAndroid) {
      _androidSessionSub = player.androidAudioSessionIdStream.listen((id) {
        _androidAudioSessionId = id;
        if (id != null && id > 0) {
          unawaited(_attachAndApplyAndroidEqualizer(id));
        }
      });
    }
  }

  Future<void> _ensurePreloadPlayer() async {
    if (_preloadPlayer != null) return;
    final preloadPlayer = ja.AudioPlayer();
    _preloadPlayer = preloadPlayer;
    await preloadPlayer.setVolume(0.0);
    await preloadPlayer.setSpeed(_playbackSpeed);
  }

  void _emitError(EngineError error) {
    if (!_errorController.isClosed) {
      _errorController.add(error);
    }
    print('[JustAudioEngine] $error');
  }

  EngineError _mapJustAudioError(
    Object error, {
    String? sourceUrl,
    bool retriable = false,
  }) {
    if (error is TimeoutException) {
      return EngineError(
        type: EngineErrorType.networkTimeout,
        message: error.message ?? 'Operation timeout',
        sourceUrl: sourceUrl,
        cause: error,
        retriable: true,
      );
    }

    if (error is ja.PlayerException) {
      final code = error.code;
      final message = error.message ?? error.toString();
      final lower = message.toLowerCase();

      if (code == 401 || code == 403 || lower.contains('forbidden')) {
        return EngineError(
          type: EngineErrorType.accessDenied,
          message: message,
          sourceUrl: sourceUrl,
          cause: error,
          retriable: false,
        );
      }

      if (lower.contains('decoder') ||
          lower.contains('format') ||
          lower.contains('unsupported')) {
        return EngineError(
          type: EngineErrorType.unsupportedFormat,
          message: message,
          sourceUrl: sourceUrl,
          cause: error,
          retriable: false,
        );
      }

      return EngineError(
        type: EngineErrorType.sourceLoad,
        message: message,
        sourceUrl: sourceUrl,
        cause: error,
        retriable: retriable || lower.contains('network') || lower.contains('io'),
      );
    }

    if (error is ja.PlayerInterruptedException) {
      return EngineError(
        type: EngineErrorType.sourceLoad,
        message: error.message ?? error.toString(),
        sourceUrl: sourceUrl,
        cause: error,
        retriable: true,
      );
    }

    return EngineError(
      type: EngineErrorType.unknown,
      message: error.toString(),
      sourceUrl: sourceUrl,
      cause: error,
      retriable: retriable,
    );
  }

  void _fireAndForgetPlay() {
    final player = _player;
    if (player == null) return;
    unawaited(
      player.play().catchError((Object e, StackTrace st) {
        _emitError(_mapJustAudioError(e));
        if (!_stateController.isClosed) {
          _stateController.add(EngineState.idle);
        }
      }),
    );
  }

  Future<void> _attachAndApplyAndroidEqualizer(int sessionId) async {
    final attached = await AndroidEqualizerService().attachToSession(sessionId);
    if (!attached) return;
    await _applyAndroidEqualizerIfReady();
  }

  Future<void> _applyAndroidEqualizerIfReady() async {
    if (!Platform.isAndroid) return;
    final sessionId = _androidAudioSessionId;
    if (sessionId == null || sessionId <= 0) return;

    final attached = await AndroidEqualizerService().attachToSession(sessionId);
    if (!attached) return;
    await AndroidEqualizerService().apply(
      enabled: _equalizerEnabled,
      gains: _equalizerGains,
      frequencies: _equalizerFrequencies,
    );
  }

  Future<void> _recreatePlayer() async {
    await _disposePlayerOnly();
    await _ensurePlayer();
  }

  Future<void> _disposePlayerOnly() async {
    await _positionSub?.cancel();
    await _durationSub?.cancel();
    await _bufferedPositionSub?.cancel();
    await _playerStateSub?.cancel();
    await _eventSub?.cancel();
    await _androidSessionSub?.cancel();
    _positionSub = null;
    _durationSub = null;
    _bufferedPositionSub = null;
    _playerStateSub = null;
    _eventSub = null;
    _androidSessionSub = null;

    final player = _player;
    _player = null;
    if (player != null) {
      try {
        await player.stop();
      } catch (_) {}
      try {
        await player.dispose();
      } catch (_) {}
    }

    _hasSource = false;
    _isPlaying = false;
    _position = Duration.zero;
    _duration = Duration.zero;
    _bufferedPosition = Duration.zero;
    _androidAudioSessionId = null;
    if (Platform.isAndroid) {
      await AndroidEqualizerService().release();
    }
  }

  Future<void> _disposePreloadPlayerOnly() async {
    final preloadPlayer = _preloadPlayer;
    _preloadPlayer = null;
    if (preloadPlayer != null) {
      try {
        await preloadPlayer.stop();
      } catch (_) {}
      try {
        await preloadPlayer.dispose();
      } catch (_) {}
    }
  }

  @override
  Future<void> play(
    String url, {
    bool isLocal = false,
    Map<String, String>? headers,
  }) async {
    await _ensurePlayer();

    if (_isPlaying) {
      await _player!.setVolume(0);
      await _player!.stop();
    }

    final source = isLocal
        ? ja.AudioSource.file(url)
        : ja.AudioSource.uri(Uri.parse(url), headers: headers);

    try {
      await _player!
          .setAudioSource(source)
          .timeout(const Duration(seconds: 15));
      _hasSource = true;
    } on TimeoutException catch (e) {
      final mapped = _mapJustAudioError(
        e,
        sourceUrl: url,
        retriable: true,
      );
      _emitError(mapped);
      await _recreatePlayer();
      throw EngineReportedException(mapped);
    } catch (e) {
      final mapped = _mapJustAudioError(e, sourceUrl: url);
      _emitError(mapped);
      await _recreatePlayer();
      throw EngineReportedException(mapped);
    }

    await _player!.setVolume(_currentVolume);
    await _player!.setSpeed(_playbackSpeed);
    _fireAndForgetPlay();
  }

  @override
  Future<void> pause() async {
    await _player?.pause();
  }

  @override
  Future<void> resume() async {
    await _ensurePlayer();
    if (!_hasSource) {
      _emitError(
        const EngineError(
          type: EngineErrorType.sourceLoad,
          message: 'resume() called without an active source',
          retriable: false,
        ),
      );
      return;
    }
    _fireAndForgetPlay();
  }

  @override
  Future<void> seek(Duration position) async {
    await _player?.seek(position);
    _position = position;
  }

  @override
  Future<void> stop() async {
    await _player?.stop();
    _hasSource = false;
    _isPlaying = false;
    if (!_stateController.isClosed) {
      _stateController.add(EngineState.idle);
    }
  }

  @override
  Future<void> setVolume(double volume) async {
    _currentVolume = volume.clamp(0.0, 1.0);
    await _player?.setVolume(_currentVolume);
  }

  @override
  Future<void> setPlaybackSpeed(double speed) async {
    _playbackSpeed = speed.clamp(0.5, 2.0);
    await _player?.setSpeed(_playbackSpeed);
    await _preloadPlayer?.setSpeed(_playbackSpeed);
  }

  @override
  Future<void> preload(
    String url, {
    bool isLocal = false,
    Map<String, String>? headers,
  }) async {
    await _ensurePreloadPlayer();
    final source = isLocal
        ? ja.AudioSource.file(url)
        : ja.AudioSource.uri(Uri.parse(url), headers: headers);

    try {
      await _preloadPlayer!
          .setAudioSource(source)
          .timeout(const Duration(seconds: 10));
    } on TimeoutException {
      await _disposePreloadPlayerOnly();
      await _ensurePreloadPlayer();
      rethrow;
    } catch (_) {
      await _disposePreloadPlayerOnly();
      await _ensurePreloadPlayer();
      rethrow;
    }
  }

  @override
  Future<void> dispose() async {
    await _disposePlayerOnly();
    await _disposePreloadPlayerOnly();
    EqualizerService().setBackend(null);
    await _positionController.close();
    await _durationController.close();
    await _bufferedPositionController.close();
    await _stateController.close();
    await _completionController.close();
    await _errorController.close();
  }

  @override
  bool get supportsEqualizer => Platform.isAndroid;

  @override
  Future<void> applyEqualizer(
    bool enabled,
    List<double> gains,
    List<int> frequencies,
  ) async {
    _equalizerEnabled = enabled;
    _equalizerGains = List<double>.from(gains);
    _equalizerFrequencies = List<int>.from(frequencies);

    if (!Platform.isAndroid) return;
    await _applyAndroidEqualizerIfReady();
  }
}

// ─────────────────────────────────────────────────────────
// MediaKit 实现（Windows / macOS / Linux）
// ─────────────────────────────────────────────────────────
class MediaKitEngine implements AudioEngine, EqualizerCapable {
  MediaKitEngine() {
    EqualizerService().setBackend(this);
  }

  static Future<void>? _mediaKitInitFuture;

  mk.Player? _player;
  double _currentVolume = 70; // MediaKit 音量 0-100
  double _playbackSpeed = 1.0;
  bool _hasMedia = false;

  final _positionController = StreamController<Duration>.broadcast();
  final _durationController = StreamController<Duration>.broadcast();
  final _bufferedPositionController = StreamController<Duration>.broadcast();
  final _stateController = StreamController<EngineState>.broadcast();
  final _completionController = StreamController<bool>.broadcast();
  final _errorController = StreamController<EngineError>.broadcast();

  StreamSubscription<bool>? _playingSub;
  StreamSubscription<Duration>? _positionSub;
  StreamSubscription<Duration?>? _durationSub;
  StreamSubscription<Duration>? _bufferSub;
  StreamSubscription<double>? _rateSub;
  StreamSubscription<bool>? _completedSub;
  StreamSubscription<String>? _errorSub;

  Duration _duration = Duration.zero;
  Duration _position = Duration.zero;
  Duration _bufferedPosition = Duration.zero;
  bool _isPlaying = false;

  @override
  Duration get duration => _duration;

  @override
  Duration get position => _position;

  @override
  Duration get bufferedPosition => _bufferedPosition;

  @override
  bool get isPlaying => _isPlaying;

  @override
  double get playbackSpeed => _playbackSpeed;

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

  Future<void> _ensureMediaKitInitialized() {
    _mediaKitInitFuture ??= Future<void>(() {
      try {
        mk.MediaKit.ensureInitialized();
      } catch (e) {
        print('[MediaKitEngine] MediaKit.ensureInitialized 失败: $e');
        rethrow;
      }
    });
    return _mediaKitInitFuture!;
  }

  void _emitError(EngineError error) {
    if (!_errorController.isClosed) {
      _errorController.add(error);
    }
    print('[MediaKitEngine] $error');
  }

  EngineError _mapMediaKitError(String message, {String? sourceUrl}) {
    final lower = message.toLowerCase();
    if (lower.contains('403') ||
        lower.contains('401') ||
        lower.contains('forbidden')) {
      return EngineError(
        type: EngineErrorType.accessDenied,
        message: message,
        sourceUrl: sourceUrl,
        retriable: false,
      );
    }
    if (lower.contains('timeout') ||
        lower.contains('timed out') ||
        lower.contains('network')) {
      return EngineError(
        type: EngineErrorType.networkTimeout,
        message: message,
        sourceUrl: sourceUrl,
        retriable: true,
      );
    }
    if (lower.contains('decoder') ||
        lower.contains('unsupported') ||
        lower.contains('format')) {
      return EngineError(
        type: EngineErrorType.unsupportedFormat,
        message: message,
        sourceUrl: sourceUrl,
        retriable: false,
      );
    }
    return EngineError(
      type: EngineErrorType.sourceLoad,
      message: message,
      sourceUrl: sourceUrl,
      retriable: true,
    );
  }

  Future<void> _ensurePlayer() async {
    if (_player != null) return;
    await _ensureMediaKitInitialized();

    _player = mk.Player(
      configuration: const mk.PlayerConfiguration(
        title: 'Cyrene Music',
        ready: null,
      ),
    );

    // 注入桌面端均衡器
    EqualizerService().setBackend(this);
    await EqualizerService().applyEqualizer();

    final savedVolume = PersistentStorageService().getDouble('player_volume');
    if (savedVolume != null) {
      _currentVolume = (savedVolume.clamp(0.0, 1.0)) * 100;
      await _player!.setVolume(_currentVolume);
    } else {
      _currentVolume = 70;
      await _player!.setVolume(70);
    }
    await _player!.setRate(_playbackSpeed);

    _playingSub = _player!.stream.playing.listen((playing) {
      if (playing) {
        _isPlaying = true;
        _stateController.add(EngineState.playing);
      } else if (_isPlaying) {
        _isPlaying = false;
        _stateController.add(EngineState.paused);
      }
    });

    _positionSub = _player!.stream.position.listen((pos) {
      _position = pos;
      _positionController.add(pos);
    });

    _durationSub = _player!.stream.duration.listen((dur) {
      _duration = dur ?? Duration.zero;
      _durationController.add(_duration);
    });

    _bufferSub = _player!.stream.buffer.listen((buffer) {
      _bufferedPosition = buffer;
      _bufferedPositionController.add(buffer);
    });

    _rateSub = _player!.stream.rate.listen((rate) {
      _playbackSpeed = rate;
    });

    _completedSub = _player!.stream.completed.listen((completed) {
      if (completed) {
        _isPlaying = false;
        _position = Duration.zero;
        _stateController.add(EngineState.idle);
        _completionController.add(true);
      }
    });

    _errorSub = _player!.stream.error.listen((message) {
      _emitError(_mapMediaKitError(message));
    });
  }

  @override
  Future<void> play(
    String url, {
    bool isLocal = false,
    Map<String, String>? headers,
  }) async {
    await _ensurePlayer();
    if (_isPlaying) {
      await _player!.setVolume(0);
      await _player!.stop();
    }
    try {
      await _player!.open(mk.Media(url, httpHeaders: headers));
      _hasMedia = true;
    } catch (e) {
      final mapped = EngineError(
        type: EngineErrorType.sourceLoad,
        message: e.toString(),
        sourceUrl: url,
        cause: e,
        retriable: true,
      );
      _emitError(mapped);
      throw EngineReportedException(mapped);
    }

    await _player!.setVolume(_currentVolume);
    await _player!.setRate(_playbackSpeed);
    await _player!.play();
  }

  @override
  Future<void> pause() async {
    await _player?.pause();
  }

  @override
  Future<void> resume() async {
    if (!_hasMedia) {
      _emitError(
        const EngineError(
          type: EngineErrorType.sourceLoad,
          message: 'resume() called without an active media',
          retriable: false,
        ),
      );
      return;
    }
    await _player?.play();
  }

  @override
  Future<void> seek(Duration position) async {
    await _player?.seek(position);
    _position = position;
  }

  @override
  Future<void> stop() async {
    await _player?.stop();
    _hasMedia = false;
  }

  @override
  Future<void> setVolume(double volume) async {
    _currentVolume = (volume.clamp(0.0, 1.0)) * 100;
    await _player?.setVolume(_currentVolume);
  }

  @override
  Future<void> setPlaybackSpeed(double speed) async {
    _playbackSpeed = speed.clamp(0.5, 2.0);
    await _player?.setRate(_playbackSpeed);
  }

  @override
  Future<void> preload(
    String url, {
    bool isLocal = false,
    Map<String, String>? headers,
  }) async {
    // 当前桌面实现为单播放器模型，预加载不做实际打开，避免打断当前播放。
    return;
  }

  @override
  Future<void> dispose() async {
    await _playingSub?.cancel();
    await _positionSub?.cancel();
    await _durationSub?.cancel();
    await _bufferSub?.cancel();
    await _rateSub?.cancel();
    await _completedSub?.cancel();
    await _errorSub?.cancel();
    _player?.dispose();
    _player = null;
    EqualizerService().setBackend(null);
    await _positionController.close();
    await _durationController.close();
    await _bufferedPositionController.close();
    await _stateController.close();
    await _completionController.close();
    await _errorController.close();
  }

  @override
  bool get supportsEqualizer => true;

  @override
  Future<void> applyEqualizer(
    bool enabled,
    List<double> gains,
    List<int> frequencies,
  ) async {
    final player = _player;
    if (player == null) return;

    if (!enabled) {
      await (player.platform as dynamic)?.setProperty('af', '');
      return;
    }

    final filterBuffer = StringBuffer();
    for (int i = 0; i < gains.length && i < frequencies.length; i++) {
      final gain = gains[i];
      if (gain.abs() <= 0.1) continue;

      if (filterBuffer.isNotEmpty) filterBuffer.write(',');
      filterBuffer.write(
        'equalizer=f=${frequencies[i]}:width_type=o:width=1:g=${gain.toStringAsFixed(1)}',
      );
    }

    final filterString = filterBuffer.toString();
    await (player.platform as dynamic)?.setProperty('af', filterString);
  }
}
