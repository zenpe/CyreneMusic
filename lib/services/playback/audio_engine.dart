import 'dart:async';
import 'dart:io';

import 'package:just_audio/just_audio.dart' as ja;
import 'package:media_kit/media_kit.dart' as mk;

import '../equalizer_service.dart';
import '../persistent_storage_service.dart';

/// 统一播放状态
enum EngineState { idle, playing, paused }

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
  Future<void> dispose();

  Stream<Duration> get positionStream;
  Stream<EngineState> get stateStream;
  Stream<bool> get completionStream;
  Stream<Duration> get durationStream;
  Duration get duration;
  Duration get position;
  bool get isPlaying;
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
class JustAudioEngine implements AudioEngine {
  ja.AudioPlayer? _player;
  double _currentVolume = 1.0;

  final _positionController = StreamController<Duration>.broadcast();
  final _stateController = StreamController<EngineState>.broadcast();
  final _completionController = StreamController<bool>.broadcast();
  final _durationController = StreamController<Duration>.broadcast();

  StreamSubscription<Duration>? _positionSub;
  StreamSubscription<Duration?>? _durationSub;
  StreamSubscription<ja.PlayerState>? _playerStateSub;
  StreamSubscription<ja.PlaybackEvent>? _eventSub;

  Duration _duration = Duration.zero;
  Duration _position = Duration.zero;
  bool _isPlaying = false;

  @override
  Duration get duration => _duration;

  @override
  Duration get position => _position;

  @override
  bool get isPlaying => _isPlaying;

  @override
  Stream<Duration> get positionStream => _positionController.stream;

  @override
  Stream<EngineState> get stateStream => _stateController.stream;

  @override
  Stream<bool> get completionStream => _completionController.stream;

  @override
  Stream<Duration> get durationStream => _durationController.stream;

  Future<void> _ensurePlayer() async {
    if (_player != null) return;

    // 移动端不使用 MediaKit 均衡器实现，避免 native EQ 路径影响播放稳定性。
    EqualizerService().setPlayer(null, useMediaKit: false);

    final player = ja.AudioPlayer();
    _player = player;

    final savedVolume = PersistentStorageService().getDouble('player_volume');
    _currentVolume = (savedVolume ?? 0.7).clamp(0.0, 1.0);
    await player.setVolume(_currentVolume);

    _positionSub = player.positionStream.listen((pos) {
      _position = pos;
      _positionController.add(pos);
    });

    _durationSub = player.durationStream.listen((dur) {
      _duration = dur ?? Duration.zero;
      _durationController.add(_duration);
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
        if (!_stateController.isClosed) {
          _stateController.add(EngineState.idle);
        }
        print('[JustAudioEngine] playbackEventStream 异常: $e');
      },
    );
  }

  void _fireAndForgetPlay() {
    final player = _player;
    if (player == null) return;
    unawaited(
      player.play().catchError((Object e, StackTrace st) {
        if (!_stateController.isClosed) {
          _stateController.add(EngineState.idle);
        }
        print('[JustAudioEngine] play 异常: $e');
      }),
    );
  }

  Future<void> _recreatePlayer() async {
    await _disposePlayerOnly();
    await _ensurePlayer();
  }

  Future<void> _disposePlayerOnly() async {
    await _positionSub?.cancel();
    await _durationSub?.cancel();
    await _playerStateSub?.cancel();
    await _eventSub?.cancel();
    _positionSub = null;
    _durationSub = null;
    _playerStateSub = null;
    _eventSub = null;

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

    _isPlaying = false;
    _position = Duration.zero;
    _duration = Duration.zero;
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
    } on TimeoutException {
      await _recreatePlayer();
      rethrow;
    } catch (_) {
      await _recreatePlayer();
      rethrow;
    }

    await _player!.setVolume(_currentVolume);
    _fireAndForgetPlay();
  }

  @override
  Future<void> pause() async {
    await _player?.pause();
  }

  @override
  Future<void> resume() async {
    await _ensurePlayer();
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
  Future<void> dispose() async {
    await _disposePlayerOnly();
    await _positionController.close();
    await _stateController.close();
    await _completionController.close();
    await _durationController.close();
  }
}

// ─────────────────────────────────────────────────────────
// MediaKit 实现（Windows / macOS / Linux）
// ─────────────────────────────────────────────────────────
class MediaKitEngine implements AudioEngine {
  static Future<void>? _mediaKitInitFuture;

  mk.Player? _player;
  double _currentVolume = 70; // MediaKit 音量 0-100

  final _positionController = StreamController<Duration>.broadcast();
  final _stateController = StreamController<EngineState>.broadcast();
  final _completionController = StreamController<bool>.broadcast();
  final _durationController = StreamController<Duration>.broadcast();

  StreamSubscription<bool>? _playingSub;
  StreamSubscription<Duration>? _positionSub;
  StreamSubscription<Duration?>? _durationSub;
  StreamSubscription<bool>? _completedSub;

  Duration _duration = Duration.zero;
  Duration _position = Duration.zero;
  bool _isPlaying = false;

  @override
  Duration get duration => _duration;

  @override
  Duration get position => _position;

  @override
  bool get isPlaying => _isPlaying;

  @override
  Stream<Duration> get positionStream => _positionController.stream;

  @override
  Stream<EngineState> get stateStream => _stateController.stream;

  @override
  Stream<bool> get completionStream => _completionController.stream;

  @override
  Stream<Duration> get durationStream => _durationController.stream;

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
    EqualizerService().setPlayer(_player, useMediaKit: true);
    await EqualizerService().applyEqualizer();

    final savedVolume = PersistentStorageService().getDouble('player_volume');
    if (savedVolume != null) {
      _currentVolume = (savedVolume.clamp(0.0, 1.0)) * 100;
      await _player!.setVolume(_currentVolume);
    } else {
      _currentVolume = 70;
      await _player!.setVolume(70);
    }

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

    _completedSub = _player!.stream.completed.listen((completed) {
      if (completed) {
        _isPlaying = false;
        _position = Duration.zero;
        _stateController.add(EngineState.idle);
        _completionController.add(true);
      }
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
    await _player!.open(mk.Media(url, httpHeaders: headers));
    await _player!.setVolume(_currentVolume);
    await _player!.play();
  }

  @override
  Future<void> pause() async {
    await _player?.pause();
  }

  @override
  Future<void> resume() async {
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
  }

  @override
  Future<void> setVolume(double volume) async {
    _currentVolume = (volume.clamp(0.0, 1.0)) * 100;
    await _player?.setVolume(_currentVolume);
  }

  @override
  Future<void> dispose() async {
    await _playingSub?.cancel();
    await _positionSub?.cancel();
    await _durationSub?.cancel();
    await _completedSub?.cancel();
    _player?.dispose();
    _player = null;
    EqualizerService().setPlayer(null, useMediaKit: false);
    await _positionController.close();
    await _stateController.close();
    await _completionController.close();
    await _durationController.close();
  }
}
