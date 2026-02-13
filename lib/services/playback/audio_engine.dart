import 'dart:async';
import 'dart:io';

import 'package:audioplayers/audioplayers.dart' as ap;
import 'package:media_kit/media_kit.dart' as mk;

import '../equalizer_service.dart';
import '../persistent_storage_service.dart';

/// 统一播放状态
enum EngineState { idle, playing, paused }

/// 统一音频引擎接口
///
/// 收敛 PlayerService 中 `if (_useMediaKit) ... else ...` 分支到此处。
/// 各引擎实现仅负责底层播放控制，不涉及队列/封面/歌词等上层逻辑。
abstract class AudioEngine {
  Future<void> play(String url, {bool isLocal = false});
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
  if (Platform.isWindows || Platform.isMacOS || Platform.isLinux || Platform.isAndroid) {
    return MediaKitEngine();
  }
  return AudioPlayersEngine();
}

// ─────────────────────────────────────────────────────────
// AudioPlayers 实现（iOS / Web）
// ─────────────────────────────────────────────────────────
class AudioPlayersEngine implements AudioEngine {
  ap.AudioPlayer? _player;

  final _positionController = StreamController<Duration>.broadcast();
  final _stateController = StreamController<EngineState>.broadcast();
  final _completionController = StreamController<bool>.broadcast();
  final _durationController = StreamController<Duration>.broadcast();

  Duration _duration = Duration.zero;
  Duration _position = Duration.zero;
  bool _isPlaying = false;

  @override Duration get duration => _duration;
  @override Duration get position => _position;
  @override bool get isPlaying => _isPlaying;

  @override Stream<Duration> get positionStream => _positionController.stream;
  @override Stream<EngineState> get stateStream => _stateController.stream;
  @override Stream<bool> get completionStream => _completionController.stream;
  @override Stream<Duration> get durationStream => _durationController.stream;

  Future<void> _ensurePlayer() async {
    if (_player != null) return;
    _player = ap.AudioPlayer();

    if (Platform.isAndroid) {
      try {
        await _player!.setAudioContext(
          ap.AudioContext(
            android: const ap.AudioContextAndroid(
              isSpeakerphoneOn: false,
              stayAwake: true,
              contentType: ap.AndroidContentType.music,
              usageType: ap.AndroidUsageType.media,
              audioFocus: ap.AndroidAudioFocus.gain,
            ),
          ),
        );
      } catch (e) {
        print('[AudioPlayersEngine] setAudioContext 失败: $e');
      }
    }

    // 恢复保存的音量
    final savedVolume = PersistentStorageService().getDouble('player_volume');
    if (savedVolume != null) {
      await _player!.setVolume(savedVolume.clamp(0.0, 1.0));
    }

    _player!.onPlayerStateChanged.listen((state) {
      switch (state) {
        case ap.PlayerState.playing:
          _isPlaying = true;
          _stateController.add(EngineState.playing);
          break;
        case ap.PlayerState.paused:
          _isPlaying = false;
          _stateController.add(EngineState.paused);
          break;
        case ap.PlayerState.stopped:
          _isPlaying = false;
          _stateController.add(EngineState.idle);
          break;
        case ap.PlayerState.completed:
          _isPlaying = false;
          _position = Duration.zero;
          _stateController.add(EngineState.idle);
          _completionController.add(true);
          break;
        default:
          break;
      }
    });

    _player!.onPositionChanged.listen((pos) {
      _position = pos;
      _positionController.add(pos);
    });

    _player!.onDurationChanged.listen((dur) {
      _duration = dur;
      _durationController.add(dur);
    });
  }

  @override
  Future<void> play(String url, {bool isLocal = false}) async {
    await _ensurePlayer();
    if (isLocal) {
      await _player!.play(ap.DeviceFileSource(url));
    } else {
      await _player!.play(ap.UrlSource(url));
    }
  }

  @override
  Future<void> pause() async {
    await _player?.pause();
  }

  @override
  Future<void> resume() async {
    await _player?.resume();
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
    await _player?.setVolume(volume.clamp(0.0, 1.0));
  }

  @override
  Future<void> dispose() async {
    await _player?.stop();
    await _player?.dispose();
    _player = null;
    await _positionController.close();
    await _stateController.close();
    await _completionController.close();
    await _durationController.close();
  }
}

// ─────────────────────────────────────────────────────────
// MediaKit 实现（Windows / macOS / Linux / Android）
// ─────────────────────────────────────────────────────────
class MediaKitEngine implements AudioEngine {
  mk.Player? _player;

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

  @override Duration get duration => _duration;
  @override Duration get position => _position;
  @override bool get isPlaying => _isPlaying;

  @override Stream<Duration> get positionStream => _positionController.stream;
  @override Stream<EngineState> get stateStream => _stateController.stream;
  @override Stream<bool> get completionStream => _completionController.stream;
  @override Stream<Duration> get durationStream => _durationController.stream;

  Future<void> _ensurePlayer() async {
    if (_player != null) return;

    _player = mk.Player(
      configuration: const mk.PlayerConfiguration(
        title: 'Cyrene Music',
        ready: null,
      ),
    );

    // Android 缓冲优化
    if (Platform.isAndroid) {
      try {
        await (_player!.platform as dynamic)?.setProperty('audio-buffer', '10.0');
        await (_player!.platform as dynamic)?.setProperty('cache', 'yes');
        await (_player!.platform as dynamic)?.setProperty('demuxer-max-bytes', '10485760');
        await (_player!.platform as dynamic)?.setProperty('demuxer-max-back-bytes', '5242880');
        await (_player!.platform as dynamic)?.setProperty('demuxer-readahead-secs', '30');
      } catch (e) {
        print('[MediaKitEngine] 优化参数应用失败: $e');
      }
    }

    // 注入均衡器
    EqualizerService().setPlayer(_player, useMediaKit: true);
    await EqualizerService().applyEqualizer();

    // 恢复保存的音量
    final savedVolume = PersistentStorageService().getDouble('player_volume');
    if (savedVolume != null) {
      await _player!.setVolume((savedVolume.clamp(0.0, 1.0)) * 100);
    } else {
      await _player!.setVolume(70);
    }

    _playingSub = _player!.stream.playing.listen((playing) {
      if (playing) {
        _isPlaying = true;
        _stateController.add(EngineState.playing);
      } else {
        if (_isPlaying) {
          _isPlaying = false;
          _stateController.add(EngineState.paused);
        }
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
  Future<void> play(String url, {bool isLocal = false}) async {
    await _ensurePlayer();
    // MediaKit 用 mk.Media 统一处理本地和网络
    try {
      await _player!.seek(Duration.zero);
    } catch (_) {}
    await _player!.open(mk.Media(url));
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
    // MediaKit 音量范围是 0-100
    await _player?.setVolume((volume.clamp(0.0, 1.0)) * 100);
  }

  @override
  Future<void> dispose() async {
    await _playingSub?.cancel();
    await _positionSub?.cancel();
    await _durationSub?.cancel();
    await _completedSub?.cancel();
    _player?.dispose();
    _player = null;
    await _positionController.close();
    await _stateController.close();
    await _completionController.close();
    await _durationController.close();
  }
}
