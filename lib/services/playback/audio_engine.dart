import 'dart:async';
import 'dart:io';

import 'package:just_audio/just_audio.dart' as ja;
import 'package:media_kit/media_kit.dart' as mk;

import '../android_equalizer_service.dart';
import '../equalizer_service.dart';
import '../persistent_storage_service.dart';
import '../structured_log_service.dart';
import 'playable_source.dart';

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
    bool autoPlay = true,
    Duration? initialPosition,
    bool preload = true,
  });
  Future<void> playAudioSource(
    ja.AudioSource source, {
    String? sourceUrl,
    bool autoPlay = true,
    Duration? initialPosition,
    bool preload = true,
  });
  Future<void> playSource(
    PlayableSource source, {
    bool autoPlay = true,
    Duration? initialPosition,
    bool preload = true,
  }) async {
    final customSource = source.audioSource;
    if (customSource != null) {
      await playAudioSource(
        customSource,
        sourceUrl: source.sourceUrl,
        autoPlay: autoPlay,
        initialPosition: initialPosition,
        preload: preload,
      );
      return;
    }

    final pathOrUrl = source.playbackPathOrUrl;
    if (pathOrUrl == null || pathOrUrl.isEmpty) {
      throw StateError('PlayableSource has no playable path or url');
    }
    await play(
      pathOrUrl,
      isLocal: source.isLocal,
      headers: source.headers,
      autoPlay: autoPlay,
      initialPosition: initialPosition,
      preload: preload,
    );
  }

  Future<void> pause();
  Future<void> resume();
  Future<void> seek(Duration position);
  Future<void> stop();
  Future<void> setVolume(double volume);
  Future<void> setPlaybackSpeed(double speed);
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
  double _currentVolume = 1.0;
  double _playbackSpeed = 1.0;
  bool _hasSource = false;
  int? _androidAudioSessionId;
  bool _androidEqualizerDirty = true;
  bool _needsDeferredVolumeRestore = false;
  bool _equalizerEnabled = true;
  List<double> _equalizerGains = List.filled(10, 0.0);
  List<int> _equalizerFrequencies = EqualizerService.kEqualizerFrequencies;
  static const int _eqVolumeFadeSteps = 4;
  static const Duration _eqVolumeFadeStepDelay = Duration(milliseconds: 12);
  // play() 前只做一次短等待，避免为等 session 过度拉长首播启动时延。
  // 如果这次没等到，真正的兜底会在播放 kick-off 后、仍保持静音时重试。
  static const Duration _prePlayEqWaitTimeout = Duration(milliseconds: 120);
  static const Duration _postPlayRestoreDelay = Duration(milliseconds: 70);
  int _playTicket = 0;

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
    await player.setVolume(0);
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
      _androidSessionSub = player.androidAudioSessionIdStream.listen(
        _handleAndroidAudioSessionIdChanged,
      );
    }
  }

  void _handleAndroidAudioSessionIdChanged(int? id) {
    final previousId = _androidAudioSessionId;
    _androidAudioSessionId = id;
    if (id == null || id <= 0) return;

    final isNewSession = previousId != id;
    if (isNewSession) {
      _androidEqualizerDirty = true;
    }
    if (!_androidEqualizerDirty) return;

    if (_isPlaying) {
      unawaited(_applyAndroidEqualizerWithOutputGuard(playTicket: _playTicket));
      return;
    }

    unawaited(_applyAndroidEqualizerIfReady());
  }

  void _emitError(EngineError error) {
    if (!_errorController.isClosed) {
      _errorController.add(error);
    }
    StructuredLogService.event(
      'audio_engine.error',
      level: LogLevel.error,
      fields: {
        'engine': 'just_audio',
        'failure_kind': error.type.name,
        'retriable': error.retriable,
        'source_url': error.sourceUrl,
      },
      error: error.cause ?? error.message,
    );
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
        retriable:
            retriable || lower.contains('network') || lower.contains('io'),
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

  void _fireAndForgetPlay({bool restoreVolumeAfterStart = true}) {
    final player = _player;
    if (player == null) return;
    final playTicket = ++_playTicket;
    unawaited(() async {
      try {
        if (restoreVolumeAfterStart) {
          if (player.volume > 0.001) {
            await player.setVolume(0);
          }
          await _primeAndroidEqualizerBeforePlaybackStart();
        }
        final playFuture = player.play();
        if (restoreVolumeAfterStart) {
          unawaited(
            _completeDeferredOutputAfterPlaybackKickoff(player, playTicket),
          );
        } else if (Platform.isAndroid && _androidEqualizerDirty) {
          unawaited(
            _applyAndroidEqualizerWithOutputGuard(playTicket: playTicket),
          );
        }
        await playFuture;
      } catch (e) {
        // 使已排队的 deferred output 失效，避免 play() 失败后仍对白跑的
        // ticket 执行 EQ/apply/fade。
        if (_isCurrentPlayTicket(player, playTicket)) {
          _playTicket++;
        }
        _emitError(_mapJustAudioError(e));
        if (!_stateController.isClosed) {
          _stateController.add(EngineState.idle);
        }
      }
    }());
  }

  Future<void> _primeAndroidEqualizerBeforePlaybackStart() async {
    if (!Platform.isAndroid || !_androidEqualizerDirty) return;
    await _waitForAndroidAudioSessionReady(timeout: _prePlayEqWaitTimeout);
    await _applyAndroidEqualizerIfReady();
  }

  Future<void> _completeDeferredOutputAfterPlaybackKickoff(
    ja.AudioPlayer player,
    int playTicket,
  ) async {
    await Future.delayed(_postPlayRestoreDelay);
    if (!_isCurrentPlayTicket(player, playTicket)) return;

    if (Platform.isAndroid && _androidEqualizerDirty) {
      await _waitForAndroidAudioSessionReady(timeout: _prePlayEqWaitTimeout);
      if (!_isCurrentPlayTicket(player, playTicket)) return;
      await _applyAndroidEqualizerIfReady();
    }

    if (!_isCurrentPlayTicket(player, playTicket)) return;
    _needsDeferredVolumeRestore = false;
    await _fadePlayerVolume(player, _currentVolume, playTicket: playTicket);
  }

  Future<void> _waitForAndroidAudioSessionReady({
    Duration timeout = const Duration(milliseconds: 400),
  }) async {
    if (!Platform.isAndroid) return;
    final deadline = DateTime.now().add(timeout);
    while (DateTime.now().isBefore(deadline)) {
      final sessionId = _androidAudioSessionId;
      if (sessionId != null && sessionId > 0) {
        return;
      }
      await Future.delayed(const Duration(milliseconds: 20));
    }
    StructuredLogService.event(
      'audio_engine.session_timeout',
      level: LogLevel.warning,
      fields: {'engine': 'just_audio', 'timeout_ms': timeout.inMilliseconds},
    );
  }

  Future<bool> _applyAndroidEqualizerIfReady() async {
    if (!Platform.isAndroid) return false;
    final sessionId = _androidAudioSessionId;
    if (sessionId == null || sessionId <= 0) return false;

    final attached = await AndroidEqualizerService().attachToSession(sessionId);
    if (!attached) return false;
    final applied = await AndroidEqualizerService().apply(
      enabled: _equalizerEnabled,
      gains: _equalizerGains,
      frequencies: _equalizerFrequencies,
    );
    if (applied) {
      _androidEqualizerDirty = false;
    }
    return applied;
  }

  bool _isCurrentPlayTicket(ja.AudioPlayer player, int playTicket) {
    return identical(_player, player) && _playTicket == playTicket;
  }

  Future<void> _applyAndroidEqualizerWithOutputGuard({int? playTicket}) async {
    final player = _player;
    if (player == null || !Platform.isAndroid) return;
    if (playTicket != null && !_isCurrentPlayTicket(player, playTicket)) return;
    // 播放中补应用 EQ 可以接受更长的等待窗口，因为此时优先保证最终效果完整，
    // 不需要像首播前那样严格压缩首响时延。
    if (_androidAudioSessionId == null || _androidAudioSessionId! <= 0) {
      await _waitForAndroidAudioSessionReady();
    }
    if (_androidAudioSessionId == null || _androidAudioSessionId! <= 0) return;
    if (playTicket != null && !_isCurrentPlayTicket(player, playTicket)) return;

    final shouldDuck = _isPlaying && _currentVolume > 0;
    if (shouldDuck) {
      await _fadePlayerVolume(player, 0, playTicket: playTicket);
    }
    try {
      await _applyAndroidEqualizerIfReady();
    } finally {
      if ((playTicket == null || _isCurrentPlayTicket(player, playTicket)) &&
          shouldDuck) {
        await _fadePlayerVolume(player, _currentVolume, playTicket: playTicket);
      }
    }
  }

  Future<void> _fadePlayerVolume(
    ja.AudioPlayer player,
    double targetVolume, {
    int? playTicket,
  }) async {
    final clampedTarget = targetVolume.clamp(0.0, 1.0);
    final startVolume = player.volume.clamp(0.0, 1.0);
    if ((startVolume - clampedTarget).abs() < 0.001) {
      if (playTicket != null && !_isCurrentPlayTicket(player, playTicket))
        return;
      await player.setVolume(clampedTarget);
      return;
    }

    for (int step = 1; step <= _eqVolumeFadeSteps; step++) {
      if (playTicket != null && !_isCurrentPlayTicket(player, playTicket))
        return;
      if (_player != player) return;
      final t = step / _eqVolumeFadeSteps;
      final nextVolume = startVolume + ((clampedTarget - startVolume) * t);
      await player.setVolume(nextVolume.clamp(0.0, 1.0));
      await Future.delayed(_eqVolumeFadeStepDelay);
    }
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
    _androidEqualizerDirty = true;
    _needsDeferredVolumeRestore = false;
    if (Platform.isAndroid) {
      await AndroidEqualizerService().release();
    }
  }

  @override
  Future<void> play(
    String url, {
    bool isLocal = false,
    Map<String, String>? headers,
    bool autoPlay = true,
    Duration? initialPosition,
    bool preload = true,
  }) async {
    final source = isLocal
        ? ja.AudioSource.file(url)
        : ja.AudioSource.uri(Uri.parse(url), headers: headers);
    await playAudioSource(
      source,
      sourceUrl: url,
      autoPlay: autoPlay,
      initialPosition: initialPosition,
      preload: preload,
    );
  }

  @override
  Future<void> playSource(
    PlayableSource source, {
    bool autoPlay = true,
    Duration? initialPosition,
    bool preload = true,
  }) async {
    final customSource = source.audioSource;
    if (customSource != null) {
      await playAudioSource(
        customSource,
        sourceUrl: source.sourceUrl,
        autoPlay: autoPlay,
        initialPosition: initialPosition,
        preload: preload,
      );
      return;
    }

    final pathOrUrl = source.playbackPathOrUrl;
    if (pathOrUrl == null || pathOrUrl.isEmpty) {
      throw StateError('PlayableSource has no playable path or url');
    }
    await play(
      pathOrUrl,
      isLocal: source.isLocal,
      headers: source.headers,
      autoPlay: autoPlay,
      initialPosition: initialPosition,
      preload: preload,
    );
  }

  @override
  Future<void> playAudioSource(
    ja.AudioSource source, {
    String? sourceUrl,
    bool autoPlay = true,
    Duration? initialPosition,
    bool preload = true,
  }) async {
    await _ensurePlayer();
    final player = _player!;
    await player.setVolume(0);

    if (_isPlaying || _hasSource) {
      await player.stop();
    }
    _hasSource = false;

    try {
      await player
          .setAudioSource(
            source,
            initialPosition: initialPosition,
            preload: preload,
          )
          .timeout(const Duration(seconds: 15));
      _hasSource = true;
    } on TimeoutException catch (e) {
      final mapped = _mapJustAudioError(
        e,
        sourceUrl: sourceUrl,
        retriable: true,
      );
      _emitError(mapped);
      await _recreatePlayer();
      throw EngineReportedException(mapped);
    } catch (e) {
      final mapped = _mapJustAudioError(e, sourceUrl: sourceUrl);
      _emitError(mapped);
      await _recreatePlayer();
      throw EngineReportedException(mapped);
    }

    _position = initialPosition ?? Duration.zero;
    _positionController.add(_position);
    _androidEqualizerDirty = Platform.isAndroid;
    _needsDeferredVolumeRestore = !autoPlay;
    await player.setSpeed(_playbackSpeed);
    if (autoPlay) {
      _fireAndForgetPlay();
    }
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
    if (_isPlaying) return;
    final needsVolumeRestore =
        _needsDeferredVolumeRestore ||
        (Platform.isAndroid && _androidEqualizerDirty);
    _fireAndForgetPlay(restoreVolumeAfterStart: needsVolumeRestore);
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
  }

  @override
  Future<void> dispose() async {
    await _disposePlayerOnly();
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
    _androidEqualizerDirty = true;
    if (_isPlaying) {
      await _applyAndroidEqualizerWithOutputGuard();
    }
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
        StructuredLogService.event(
          'audio_engine.initialize_failed',
          level: LogLevel.error,
          fields: const {'engine': 'media_kit'},
          error: e,
        );
        rethrow;
      }
    });
    return _mediaKitInitFuture!;
  }

  void _emitError(EngineError error) {
    if (!_errorController.isClosed) {
      _errorController.add(error);
    }
    StructuredLogService.event(
      'audio_engine.error',
      level: LogLevel.error,
      fields: {
        'engine': 'media_kit',
        'failure_kind': error.type.name,
        'retriable': error.retriable,
        'source_url': error.sourceUrl,
      },
      error: error.cause ?? error.message,
    );
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
    bool autoPlay = true,
    Duration? initialPosition,
    bool preload = true,
  }) async {
    await _ensurePlayer();
    final player = _player!;
    if (_isPlaying || _hasMedia) {
      await player.setVolume(0);
      await player.stop();
    }
    try {
      await player.open(mk.Media(url, httpHeaders: headers), play: false);
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

    if (initialPosition != null && initialPosition > Duration.zero) {
      await player.seek(initialPosition);
      _position = initialPosition;
    } else {
      _position = Duration.zero;
    }
    _positionController.add(_position);
    await player.setVolume(_currentVolume);
    await player.setRate(_playbackSpeed);
    if (autoPlay) {
      await player.play();
    }
  }

  @override
  Future<void> playSource(
    PlayableSource source, {
    bool autoPlay = true,
    Duration? initialPosition,
    bool preload = true,
  }) async {
    final customSource = source.audioSource;
    if (customSource != null) {
      await playAudioSource(
        customSource,
        sourceUrl: source.sourceUrl,
        autoPlay: autoPlay,
        initialPosition: initialPosition,
        preload: preload,
      );
      return;
    }

    final pathOrUrl = source.playbackPathOrUrl;
    if (pathOrUrl == null || pathOrUrl.isEmpty) {
      throw StateError('PlayableSource has no playable path or url');
    }
    await play(
      pathOrUrl,
      isLocal: source.isLocal,
      headers: source.headers,
      autoPlay: autoPlay,
      initialPosition: initialPosition,
      preload: preload,
    );
  }

  @override
  Future<void> playAudioSource(
    ja.AudioSource source, {
    String? sourceUrl,
    bool autoPlay = true,
    Duration? initialPosition,
    bool preload = true,
  }) async {
    throw UnsupportedError(
      'Custom audio sources are only supported on just_audio platforms.',
    );
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
