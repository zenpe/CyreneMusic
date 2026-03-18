import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../../models/track.dart';
import '../../models/song_detail.dart';
import '../../models/lyric_line.dart';
import '../../utils/lyric_parser.dart';
import '../../utils/toast_utils.dart';
import '../../utils/metadata_reader.dart';
import '../music_service.dart';
import '../audio_source_service.dart';
import '../cache_service.dart';
import '../proxy_service.dart';
import '../play_history_service.dart';
import '../playback_mode_service.dart';
import '../playlist_queue_service.dart';
import '../audio_quality_service.dart';
import '../listening_stats_service.dart';
import '../desktop_lyric_service.dart';
import '../android_floating_lyric_service.dart';
import '../player_background_service.dart';
import '../local_library_service.dart';
import '../url_service.dart';
import '../notification_service.dart';
import '../persistent_storage_service.dart';
import '../equalizer_service.dart';

import 'command_queue.dart';
import 'audio_engine.dart';
import 'cover_manager.dart';
import 'playback_session_snapshot.dart';
import 'playback_session_store.dart';

/// 播放状态枚举（复用 PlayerService 的定义）
enum PBState { idle, loading, playing, paused, error }

/// 核心播放服务
///
/// 统一管理队列状态（原 PlaylistQueueService）和播放控制（原 PlayerService）。
/// `currentTrack` 是 `_queue[_currentIndex]` 的派生——不再是独立字段。
class PlaybackService extends ChangeNotifier {
  static final PlaybackService _instance = PlaybackService._internal();
  factory PlaybackService() => _instance;

  // ══════════════════════════════════════════════════════
  // 队列状态（原 PlaylistQueueService）
  // ══════════════════════════════════════════════════════
  final List<Track> _queue = [];
  int _currentIndex = -1;
  QueueSource _source = QueueSource.none;
  Map<String, ImageProvider> _coverProviders = {};

  // ══════════════════════════════════════════════════════
  // 随机播放（原 PlaylistQueueService shuffle）
  // ══════════════════════════════════════════════════════
  List<int> _shuffledIndices = [];
  int _shufflePosition = -1;
  final Random _random = Random();

  // ══════════════════════════════════════════════════════
  // 组合
  // ══════════════════════════════════════════════════════
  final CommandQueue _commands = CommandQueue();
  late final AudioEngine _engine;
  final List<StreamSubscription> _engineSubs = [];
  final CoverManager coverManager = CoverManager();

  // ══════════════════════════════════════════════════════
  // 播放状态
  // ══════════════════════════════════════════════════════
  PBState _state = PBState.idle;
  SongDetail? _currentSong;
  int _playGeneration = 0;
  int _consecutiveErrors = 0;
  static const int _maxConsecutiveErrors = 3;
  Duration _duration = Duration.zero;
  Duration _position = Duration.zero;
  Duration _bufferedPosition = Duration.zero;
  String? _errorMessage;
  String? _currentTempFilePath;
  double _volume = 0.7;
  double _playbackSpeed = 1.0;
  bool _isAudioSourceNotConfigured = false;
  String? _retriedTrackKey;
  String? _lastPreloadedTargetKey;
  bool _preloadingNext = false;
  int _preloadOp = 0;
  final Map<String, SongDetail> _prefetchedPlayableDetails = {};

  static const int _switchFadeSteps = 8;
  static const Duration _switchFadeStepDelay = Duration(milliseconds: 15);
  static const Duration _trackSwitchSettleDelay = Duration(milliseconds: 80);
  static const int _maxPrefetchedPlayableDetails = 4;

  // 高频进度更新（解耦 ChangeNotifier，避免重建 widget 树）
  final ValueNotifier<Duration> positionNotifier = ValueNotifier(Duration.zero);
  final ValueNotifier<Duration> bufferedPositionNotifier =
      ValueNotifier(Duration.zero);

  // 听歌统计
  Timer? _statsTimer;
  DateTime? _playStartTime;

  // 播放状态保存
  Timer? _stateSaveTimer;
  Timer? _sessionPersistDebounce;
  Duration? _pendingRestorePosition;
  bool _hasRestoredSessionOnStartup = false;

  // 桌面/悬浮歌词
  List<LyricLine> _lyrics = [];
  int _currentLyricIndex = -1;
  DateTime _lastNativeSyncTime = DateTime.fromMillisecondsSinceEpoch(0);

  // 音源配置回调
  void Function()? onAudioSourceNotConfigured;

  // ══════════════════════════════════════════════════════
  // 派生属性
  // ══════════════════════════════════════════════════════
  Track? get currentTrack =>
      _currentIndex >= 0 && _currentIndex < _queue.length
          ? _queue[_currentIndex]
          : _preloadedTrack;  // 降级到预载轨道

  List<Track> get queue => List.unmodifiable(_queue);
  int get currentIndex => _currentIndex;
  QueueSource get source => _source;
  bool get hasQueue => _queue.isNotEmpty;
  bool get isPlaying => _state == PBState.playing;
  bool get isPaused => _state == PBState.paused;
  bool get isLoading => _state == PBState.loading;
  PBState get state => _state;
  SongDetail? get currentSong => _currentSong;
  Duration get duration => _duration;
  Duration get position => _position;
  Duration get bufferedPosition => _bufferedPosition;
  String? get errorMessage => _errorMessage;
  double get volume => _volume;
  double get playbackSpeed => _playbackSpeed;
  bool get isAudioSourceNotConfigured => _isAudioSourceNotConfigured;

  bool get hasNext {
    if (_queue.isNotEmpty) return _currentIndex < _queue.length - 1;
    return PlayHistoryService().history.length >= 2;
  }

  bool get hasPrevious {
    if (_queue.isNotEmpty) return _currentIndex > 0;
    return PlayHistoryService().history.length >= 3;
  }

  // 预载轨道（用于启动时显示 MiniPlayer）
  Track? _preloadedTrack;

  // 均衡器 — 委托给 EqualizerService
  static List<int> get kEqualizerFrequencies => EqualizerService.kEqualizerFrequencies;
  List<double> get equalizerGains => EqualizerService().equalizerGains;
  bool get equalizerEnabled => EqualizerService().equalizerEnabled;
  bool get isEqualizerAvailable => EqualizerService().isEqualizerAvailable;

  // ══════════════════════════════════════════════════════
  // 初始化
  // ══════════════════════════════════════════════════════
  PlaybackService._internal() {
    _engine = createEngine();

    // 监听引擎状态
    _engineSubs.add(_engine.stateStream.listen(_onEngineStateChanged));
    _engineSubs.add(_engine.positionStream.listen(_onPositionChanged));
    _engineSubs.add(_engine.durationStream.listen(_onDurationChanged));
    _engineSubs.add(
      _engine.bufferedPositionStream.listen(_onBufferedPositionChanged),
    );
    _engineSubs.add(_engine.completionStream.listen(_onCompletion));
    _engineSubs.add(_engine.errorStream.listen(_onEngineError));
  }

  Future<void> initialize() async {
    // 加载保存的音量设置
    final savedVolume = PersistentStorageService().getDouble('player_volume');
    if (savedVolume != null) {
      _volume = savedVolume.clamp(0.0, 1.0);
    }
    final savedSpeed = PersistentStorageService().getDouble('player_speed');
    if (savedSpeed != null) {
      _playbackSpeed = savedSpeed.clamp(0.5, 2.0);
    }
    await _engine.setPlaybackSpeed(_playbackSpeed);

    EqualizerService().loadSettings();
    await EqualizerService().applyEqualizer();

    // 桌面歌词播放控制回调
    if (Platform.isWindows) {
      DesktopLyricService().setPlaybackControlCallback((action) {
        switch (action) {
          case 'play_pause':
            isPlaying ? pause() : resume();
            break;
          case 'previous':
            previous();
            break;
          case 'next':
            next();
            break;
        }
      });
    }

    // 监听播放模式变化，触发预缓存
    PlaybackModeService().addListener(_precacheNextCover);

    print('[PlaybackService] 初始化完成');
  }

  Future<bool> restoreSessionOnStartup() async {
    if (_hasRestoredSessionOnStartup) return currentTrack != null;
    _hasRestoredSessionOnStartup = true;

    try {
      final snapshot = await PlaybackSessionStore().loadSnapshot();
      if (snapshot == null || !snapshot.isValid) return false;

      await _restoreFromSnapshot(snapshot);
      _scheduleSessionPersist();
      return true;
    } catch (e) {
      print('[PlaybackService] 恢复本地播放会话失败: $e');
      return false;
    }
  }

  PlaybackSessionSnapshot? _buildSessionSnapshot() {
    final sessionQueue = _queue.isNotEmpty
        ? List<Track>.from(_queue)
        : (currentTrack != null ? [currentTrack!] : const <Track>[]);
    if (sessionQueue.isEmpty) return null;

    final currentIndex = _queue.isNotEmpty
        ? _currentIndex.clamp(0, sessionQueue.length - 1)
        : 0;
    final state = switch (_state) {
      PBState.playing => PlaybackSessionState.playing,
      PBState.paused => PlaybackSessionState.paused,
      _ => PlaybackSessionState.idle,
    };

    return PlaybackSessionSnapshot(
      version: 1,
      savedAt: DateTime.now(),
      queue: sessionQueue,
      currentIndex: currentIndex,
      source: _queue.isNotEmpty ? _source : QueueSource.none,
      position: _position,
      state: state,
      playbackMode: PlaybackModeService().currentMode,
    );
  }

  Future<void> _restoreFromSnapshot(PlaybackSessionSnapshot snapshot) async {
    await PlaybackModeService().setMode(snapshot.playbackMode);

    _pendingRestorePosition =
        snapshot.position > Duration.zero ? snapshot.position : null;

    if (snapshot.state == PlaybackSessionState.playing) {
      await playNow(snapshot.queue, snapshot.currentIndex, snapshot.source);
      _pendingRestorePosition =
          snapshot.position > Duration.zero ? snapshot.position : null;
      await _applyPendingRestorePosition();
      return;
    }

    _resetPreloadState();
    _queue
      ..clear()
      ..addAll(snapshot.queue);
    _currentIndex = snapshot.currentIndex.clamp(0, snapshot.queue.length - 1);
    _source = snapshot.source;
    _coverProviders.clear();
    _state = PBState.idle;
    _currentSong = null;
    _errorMessage = null;
    _isAudioSourceNotConfigured = false;
    _duration = Duration.zero;
    _bufferedPosition = Duration.zero;
    _position = snapshot.position;
    positionNotifier.value = snapshot.position;
    bufferedPositionNotifier.value = Duration.zero;
    if (currentTrack != null) {
      await coverManager.updateCover(currentTrack!.picUrl, notify: false, force: true);
    } else {
      coverManager.setCover(null, notify: false);
      coverManager.themeColorNotifier.value = null;
    }
    notifyListeners();
  }

  // ══════════════════════════════════════════════════════
  // 引擎事件处理
  // ══════════════════════════════════════════════════════
  void _onEngineStateChanged(EngineState s) {
    switch (s) {
      case EngineState.playing:
        _state = PBState.playing;
        _consecutiveErrors = 0;
        _retriedTrackKey = null;
        _errorMessage = null;
        _schedulePreloadNextTrack();
        _startListeningTimeTracking();
        _startStateSaveTimer();
        if (Platform.isWindows) DesktopLyricService().setPlayingState(true);
        if (Platform.isAndroid) AndroidFloatingLyricService().setPlayingState(true);
        _scheduleSessionPersist();
        break;
      case EngineState.paused:
        _state = PBState.paused;
        _pauseListeningTimeTracking();
        _stopStateSaveTimer();
        if (Platform.isWindows) DesktopLyricService().setPlayingState(false);
        if (Platform.isAndroid) AndroidFloatingLyricService().setPlayingState(false);
        _scheduleSessionPersist();
        break;
      case EngineState.idle:
        _state = PBState.idle;
        _pauseListeningTimeTracking();
        _stopStateSaveTimer();
        if (Platform.isWindows) DesktopLyricService().setPlayingState(false);
        if (Platform.isAndroid) AndroidFloatingLyricService().setPlayingState(false);
        _scheduleSessionPersist();
        break;
    }
    notifyListeners();
  }

  void _onPositionChanged(Duration pos) {
    _position = pos;
    positionNotifier.value = pos;
    _updateFloatingLyric();
    _syncPositionToNative(pos);
  }

  void _onDurationChanged(Duration dur) {
    _duration = dur;
    notifyListeners();
  }

  void _onBufferedPositionChanged(Duration buffered) {
    _bufferedPosition = buffered;
    bufferedPositionNotifier.value = buffered;
  }

  void _onEngineError(EngineError error) {
    final track = currentTrack;
    if (track == null || _state == PBState.error) return;

    final trackKey = '${track.source.name}_${track.id}';
    final canRetry = _canRetryOnError(error) && _retriedTrackKey != trackKey;

    if (canRetry) {
      _retriedTrackKey = trackKey;
      print('[PlaybackService] 引擎错误，尝试自动重试: $error');
      unawaited(_commands.enqueue(() async {
        final current = currentTrack;
        if (current == null) return;
        final currentKey = '${current.source.name}_${current.id}';
        if (currentKey != trackKey) return;
        await _playCurrentTrack();
      }));
      return;
    }

    _state = PBState.error;
    _errorMessage = _buildErrorMessage(error);
    _isAudioSourceNotConfigured = false;
    notifyListeners();
    _autoSkipOnError();
  }

  bool _canRetryOnError(EngineError error) {
    switch (error.type) {
      case EngineErrorType.networkTimeout:
        return true;
      case EngineErrorType.accessDenied:
      case EngineErrorType.sourceLoad:
      case EngineErrorType.playback:
      case EngineErrorType.unknown:
        return error.retriable;
      case EngineErrorType.unsupportedFormat:
        return false;
    }
  }

  String _buildErrorMessage(EngineError error) {
    switch (error.type) {
      case EngineErrorType.unsupportedFormat:
        return '播放失败: 当前格式不受支持';
      case EngineErrorType.accessDenied:
        return '播放失败: 资源访问受限';
      case EngineErrorType.networkTimeout:
        return '播放失败: 网络超时';
      default:
        return '播放失败: ${error.message}';
    }
  }

  void _onCompletion(bool completed) {
    if (!completed) return;
    _position = Duration.zero;
    _playNextAuto();
  }

  // ══════════════════════════════════════════════════════
  // 队列操作（经 CommandQueue 串行）
  // ══════════════════════════════════════════════════════

  /// 替换队列并播放指定曲目
  Future<void> playNow(
    List<Track> tracks,
    int index,
    QueueSource source, {
    Map<String, ImageProvider>? coverProviders,
  }) {
    return _commands.enqueue(() async {
      _resetPreloadState();
      _pendingRestorePosition = null;
      _queue
        ..clear()
        ..addAll(tracks);
      _currentIndex = index.clamp(0, tracks.length - 1);
      _source = source;
      _coverProviders = coverProviders ?? {};
      _resetShuffle();
      _preloadedTrack = null;
      await _playCurrentTrack();
      _scheduleSessionPersist();
    });
  }

  /// 下一首播放（插入到当前之后）
  Future<void> playNext(Track track) {
    return _commands.enqueue(() async {
      _resetPreloadState();
      _pendingRestorePosition = null;
      _removeDuplicate(track);
      final insertAt = (_currentIndex + 1).clamp(0, _queue.length);
      _queue.insert(insertAt, track);
      _resetShuffle();
      notifyListeners();
      _scheduleSessionPersist();
    });
  }

  /// 加入队列末尾
  Future<void> addToQueue(Track track) {
    return _commands.enqueue(() async {
      _resetPreloadState();
      _pendingRestorePosition = null;
      _queue.add(track);
      _resetShuffle();
      notifyListeners();
      _scheduleSessionPersist();
    });
  }

  /// 批量加入队列末尾
  Future<void> addAllToQueue(List<Track> tracks) {
    return _commands.enqueue(() async {
      _resetPreloadState();
      _pendingRestorePosition = null;
      _queue.addAll(tracks);
      _resetShuffle();
      notifyListeners();
      _scheduleSessionPersist();
    });
  }

  /// 跳转到队列中某首
  Future<void> jumpTo(int index) {
    return _commands.enqueue(() async {
      if (index < 0 || index >= _queue.length) return;
      _resetPreloadState();
      _pendingRestorePosition = null;
      _currentIndex = index;
      await _playCurrentTrack();
      _scheduleSessionPersist();
    });
  }

  /// 移除队列中某首
  Future<void> removeAt(int index) {
    return _commands.enqueue(() async {
      if (index < 0 || index >= _queue.length) return;
      _resetPreloadState();
      _pendingRestorePosition = null;
      _queue.removeAt(index);
      if (_queue.isEmpty) {
        _currentIndex = -1;
        _source = QueueSource.none;
        await _engine.stop();
        _state = PBState.idle;
      } else if (index < _currentIndex) {
        _currentIndex--;
      } else if (index == _currentIndex) {
        _currentIndex = _currentIndex.clamp(0, _queue.length - 1);
        await _playCurrentTrack();
      }
      _resetShuffle();
      notifyListeners();
      _scheduleSessionPersist();
    });
  }

  /// 拖拽排序
  Future<void> reorder(int oldIndex, int newIndex) {
    return _commands.enqueue(() async {
      if (oldIndex < 0 || oldIndex >= _queue.length) return;
      if (newIndex < 0 || newIndex > _queue.length) return;
      _resetPreloadState();
      _pendingRestorePosition = null;

      final track = _queue.removeAt(oldIndex);
      _queue.insert(newIndex, track);

      // 维护 currentIndex 指向不变
      if (oldIndex == _currentIndex) {
        _currentIndex = newIndex;
      } else if (oldIndex < _currentIndex && newIndex >= _currentIndex) {
        _currentIndex--;
      } else if (oldIndex > _currentIndex && newIndex <= _currentIndex) {
        _currentIndex++;
      }
      _resetShuffle();
      notifyListeners();
      _scheduleSessionPersist();
    });
  }

  /// 清空队列
  Future<void> clearQueue() {
    return _commands.enqueue(() async {
      _resetPreloadState();
      _pendingRestorePosition = null;
      _queue.clear();
      _currentIndex = -1;
      _source = QueueSource.none;
      _coverProviders.clear();
      _resetShuffle();
      await _engine.stop();
      _state = PBState.idle;
      _currentSong = null;
      notifyListeners();
      await PlaybackSessionStore().clear();
    });
  }

  // ══════════════════════════════════════════════════════
  // 播放控制
  // ══════════════════════════════════════════════════════

  Future<void> resume() async {
    // 预载态：播放器尚未初始化，走完整播放
    if (_state == PBState.idle && currentTrack != null) {
      if (_queue.isNotEmpty && _currentIndex >= 0) {
        await _commands.enqueue(() async {
          await _playCurrentTrack();
          await _applyPendingRestorePosition();
        });
      } else if (_preloadedTrack != null) {
        await playNow([_preloadedTrack!], 0, QueueSource.none);
      }
      _scheduleSessionPersist();
      return;
    }
    await _engine.resume();
    _startListeningTimeTracking();
    _scheduleSessionPersist();
  }

  Future<void> pause() async {
    await _engine.pause();
    _pauseListeningTimeTracking();
    _scheduleSessionPersist();
  }

  Future<void> seek(Duration position) async {
    await _engine.seek(position);
    _position = position;
    positionNotifier.value = position;
    _syncPositionToNative(position, force: true);
    _pendingRestorePosition = null;
    _scheduleSessionPersist();
  }

  Future<void> next() async {
    final mode = PlaybackModeService().currentMode;
    if (mode == PlaybackMode.shuffle) {
      await _playRandomNext();
    } else {
      // sequential, loopAll, repeatOne: 手动切歌都走顺序（允许循环）
      await _playSequentialNext();
    }
  }

  Future<void> previous() async {
    final mode = PlaybackModeService().currentMode;
    if (mode == PlaybackMode.shuffle) {
      await _playRandomPrevious();
    } else {
      // sequential, loopAll, repeatOne: 手动切歌都走顺序（允许循环）
      await _playSequentialPrevious();
    }
  }

  Future<void> stop() async {
    await _engine.stop();
    await _cleanupCurrentTempFile();
    _pauseListeningTimeTracking();
    _state = PBState.idle;
    _currentSong = null;
    _preloadedTrack = null;
    _errorMessage = null;
    _duration = Duration.zero;
    _position = Duration.zero;
    _bufferedPosition = Duration.zero;
    positionNotifier.value = Duration.zero;
    bufferedPositionNotifier.value = Duration.zero;
    coverManager.setCover(null, notify: false);
    notifyListeners();
    _pendingRestorePosition = null;
    _scheduleSessionPersist();
  }

  Future<void> togglePlayPause() async {
    isPlaying ? await pause() : await resume();
  }

  Future<void> retryCurrentTrack() async {
    return _commands.enqueue(() async {
      if (currentTrack == null) return;
      _state = PBState.loading;
      _errorMessage = null;
      _isAudioSourceNotConfigured = false;
      notifyListeners();
      await _playCurrentTrack();
    });
  }

  Future<void> setVolume(double vol) async {
    final clamped = vol.clamp(0.0, 1.0);
    if ((clamped - _volume).abs() < 0.001) return;
    _volume = clamped;
    await _engine.setVolume(clamped);
    _saveVolumeThrottled();
    notifyListeners();
  }

  Future<void> setPlaybackSpeed(double speed) async {
    final clamped = speed.clamp(0.5, 2.0);
    if ((clamped - _playbackSpeed).abs() < 0.001) return;
    _playbackSpeed = clamped;
    await _engine.setPlaybackSpeed(clamped);
    PersistentStorageService().setDouble('player_speed', _playbackSpeed);
    notifyListeners();
  }

  /// 预载轨道（不播放）：设置 currentTrack 和封面，使 MiniPlayer 以暂停态显示
  Future<void> preload(Track track, {ImageProvider? coverProvider}) async {
    if (currentTrack != null) return;
    _preloadedTrack = track;
    _state = PBState.idle;
    _duration = Duration.zero;
    _position = Duration.zero;

    if (coverProvider != null) {
      coverManager.setCover(coverProvider, url: track.picUrl, notify: false);
    } else {
      await coverManager.updateCover(track.picUrl, notify: false, force: true);
    }

    notifyListeners();
    _scheduleSessionPersist();
  }

  /// 播放网络电台流
  Future<void> playRadioStream(String streamUrl, Track radioTrack) async {
    return _commands.enqueue(() async {
      await _cleanupCurrentTempFile();
      _state = PBState.loading;
      _preloadedTrack = null;
      _currentSong = null;
      _errorMessage = null;
      ++_playGeneration;
      _duration = Duration.zero;
      _position = Duration.zero;
      positionNotifier.value = Duration.zero;
      coverManager.setCover(null, notify: false);
      coverManager.themeColorNotifier.value = null;

      // 设置电台的 track 到队列
      _queue
        ..clear()
        ..add(radioTrack);
      _currentIndex = 0;
      _source = QueueSource.radio;

      notifyListeners();
      await _playWithSoftSwitch(streamUrl);
      _state = PBState.playing;
      _startListeningTimeTracking();
      notifyListeners();
    });
  }

  // ══════════════════════════════════════════════════════
  // 队列辅助
  // ══════════════════════════════════════════════════════

  String _coverKey(Track t) => '${t.source.name}_${t.id}';

  ImageProvider? getCoverProvider(Track track) {
    return _coverProviders[_coverKey(track)] ??
        (track.picUrl.isNotEmpty ? _coverProviders[track.picUrl] : null);
  }

  void updateCoverProvider(Track track, ImageProvider provider) {
    _coverProviders[_coverKey(track)] = provider;
    if (track.picUrl.isNotEmpty) _coverProviders[track.picUrl] = provider;
  }

  void updateCoverProviders(Map<String, ImageProvider> providers) {
    _coverProviders.addAll(providers);
  }

  int _indexOfTrack(Track track) {
    return _queue.indexWhere(
      (t) => t.id.toString() == track.id.toString() && t.source == track.source,
    );
  }

  void _removeDuplicate(Track track) {
    final existing = _indexOfTrack(track);
    if (existing != -1) {
      _queue.removeAt(existing);
      if (existing <= _currentIndex) {
        _currentIndex = (_currentIndex - 1).clamp(-1, _queue.length);
      }
    }
  }

  void _resetShuffle() {
    _shuffledIndices.clear();
    _shufflePosition = -1;
  }

  /// 预测下一首（不改变索引）
  Track? peekNext(dynamic mode) {
    if (_queue.isEmpty) return null;
    final modeStr = mode.toString();
    if (modeStr.contains('repeatOne')) {
      return _currentIndex >= 0 ? _queue[_currentIndex] : null;
    }
    if (modeStr.contains('shuffle')) {
      if (_shuffledIndices.isEmpty) return null;
      final nextPos = _shufflePosition + 1;
      if (nextPos < _shuffledIndices.length) return _queue[_shuffledIndices[nextPos]];
      return _queue[_shuffledIndices[0]];
    }
    final nextIdx = _currentIndex + 1;
    if (nextIdx < _queue.length) return _queue[nextIdx];
    return _queue[0];
  }

  /// 预测上一首（不改变索引）
  Track? peekPrevious(dynamic mode) {
    if (_queue.isEmpty) return null;
    final modeStr = mode.toString();
    if (modeStr.contains('shuffle')) {
      if (_shuffledIndices.isEmpty || _shufflePosition <= 0) return null;
      return _queue[_shuffledIndices[_shufflePosition - 1]];
    }
    final prevIdx = _currentIndex - 1;
    if (prevIdx >= 0) return _queue[prevIdx];
    return _queue[_queue.length - 1];
  }

  /// 队列信息字符串
  String getQueueInfo() {
    if (_queue.isEmpty) return '无播放队列';
    return '${_source.name} (${_currentIndex + 1}/${_queue.length})';
  }

  // ══════════════════════════════════════════════════════
  // 播放核心内部
  // ══════════════════════════════════════════════════════

  Future<void> _playCurrentTrack() async {
    final track = currentTrack;
    if (track == null) return;

    _resetPreloadState();
    _preloadedTrack = null;
    final gen = ++_playGeneration;
    final requestedKey = '${track.source.name}_${track.id}';
    bool isStale() {
      final ct = currentTrack;
      if (gen != _playGeneration || ct == null) return true;
      return '${ct.source.name}_${ct.id}' != requestedKey;
    }

    try {
      _state = PBState.loading;
      _currentSong = null;
      _errorMessage = null;
      _isAudioSourceNotConfigured = false;
      _duration = Duration.zero;
      _position = Duration.zero;
      positionNotifier.value = Duration.zero;
      notifyListeners();

      // 音源配置检查（本地音乐不需要）
      if (track.source != MusicSource.local && !AudioSourceService().isConfigured) {
        _state = PBState.error;
        _errorMessage = '音源未配置，请在设置中配置音源';
        _isAudioSourceNotConfigured = true;
        notifyListeners();
        onAudioSourceNotConfigured?.call();
        return;
      }

      // Apple Music 歌单换源限制
      final isFromPlaylist = _source == QueueSource.playlist;
      if (isFromPlaylist && track.source == MusicSource.apple) {
        _state = PBState.error;
        _errorMessage = '由于Apple接口限制，通过该接口导入的音乐需要换源才能播放！';
        notifyListeners();
        _notifyAppleMusicRestriction(track);
        return;
      }

      // 封面
      final existingProvider = getCoverProvider(track);
      if (existingProvider != null) {
        coverManager.setCover(existingProvider, url: track.picUrl, notify: false);
      } else {
        await coverManager.updateCover(track.picUrl, notify: false, force: existingProvider == null);
      }
      if (isStale()) return;

      // 预缓存下一首封面
      _precacheNextCover();

      // Wakelock
      if (Platform.isAndroid || Platform.isIOS) WakelockPlus.enable();

      // 播放历史 & 统计
      PlayHistoryService().addToHistory(track);
      ListeningStatsService().recordPlayCount(track);

      final selectedQuality = AudioQualityService().currentQuality;
      final qualityStr = selectedQuality.toString().split('.').last;

      // ──── 缓存命中 ────
      final isCached = CacheService().isCached(track);
      if (isCached) {
        final metadata = CacheService().getCachedMetadata(track);
        final cachedFilePath = await CacheService().getCachedFilePath(track);
        if (isStale()) return;

        if (cachedFilePath != null && metadata != null) {
          _currentTempFilePath = cachedFilePath;
          _currentSong = SongDetail(
            id: track.id, name: track.name, url: cachedFilePath,
            pic: metadata.picUrl, arName: metadata.artists, alName: metadata.album,
            level: metadata.quality, size: metadata.fileSize.toString(),
            lyric: metadata.lyric, tlyric: metadata.tlyric, source: track.source,
          );
          if (metadata.picUrl != track.picUrl) {
            await coverManager.updateCover(metadata.picUrl, notify: false);
          }
          _loadLyricsForFloatingDisplay();
          await _playWithSoftSwitch(cachedFilePath, isLocal: true);

          // 后台补歌词
          if (_currentSong!.lyric.isEmpty) {
            _bgUpdateLyrics(track, selectedQuality, qualityStr, requestedKey, isStale);
          }

          await coverManager.extractThemeColor(metadata.picUrl);
          return;
        }
      }

      // ──── 本地文件 ────
      if (track.source == MusicSource.local) {
        final filePath = track.id is String ? track.id as String : '';
        if (filePath.isEmpty || !(await File(filePath).exists())) {
          if (isStale()) return;
          _state = PBState.error;
          _errorMessage = '本地文件不存在';
          notifyListeners();
          _autoSkipOnError();
          return;
        }
        var lyricText = LocalLibraryService().getLyricByTrackId(filePath);
        if (lyricText.isEmpty) {
          final embedded = await MetadataReader.extractLyrics(filePath);
          if (embedded != null && embedded.isNotEmpty) lyricText = embedded;
        }
        _currentSong = SongDetail(
          id: filePath, name: track.name, pic: track.picUrl,
          arName: track.artists, alName: track.album, level: 'local', size: '',
          url: filePath, lyric: lyricText, tlyric: '', source: MusicSource.local,
        );
        _loadLyricsForFloatingDisplay();
        await _playWithSoftSwitch(filePath, isLocal: true);
        await coverManager.extractThemeColor(track.picUrl);
        return;
      }

      // ──── 网络获取 ────
      var songDetail = _takePrefetchedSongDetail(track, selectedQuality);
      songDetail ??= await MusicService().fetchSongDetail(
        songId: track.id, quality: selectedQuality,
        source: track.source, title: track.name, artist: track.artists,
      );
      if (isStale()) return;

      if (songDetail == null || songDetail.url.isEmpty) {
        _state = PBState.error;
        _errorMessage = '无法获取播放链接';
        notifyListeners();
        _autoSkipOnError();
        return;
      }

      songDetail = _normalizeSongDetailForPlayback(track, songDetail);

      _currentSong = songDetail;
      if (songDetail.pic != track.picUrl) {
        await coverManager.updateCover(songDetail.pic, notify: false);
        if (isStale()) return;
      }
      _loadLyricsForFloatingDisplay();

      // Apple Music 特殊播放
      if (track.source == MusicSource.apple) {
        final isDecrypted = songDetail.url.contains('/apple/stream');
        if (isDecrypted) {
          final durationMs = await _getAppleStreamDuration(songDetail.url);
          if (durationMs != null && durationMs > 0) {
            _duration = Duration(milliseconds: durationMs);
            notifyListeners();
          }
        }
        await _playWithSoftSwitch(songDetail.url);
        if (!isCached) {
          final shouldSkip = songDetail.url.toLowerCase().contains('.m3u8');
          if (!shouldSkip) _cacheSongInBackground(track, songDetail, qualityStr);
        }
        await coverManager.extractThemeColor(songDetail.pic);
        return;
      }

      // QQ / 酷狗
      if (track.source == MusicSource.qq || track.source == MusicSource.kugou) {
        final platform = track.source == MusicSource.qq ? 'qq' : 'kugou';
        final mobileDirect = Platform.isAndroid || Platform.isIOS;

        // 第一阶段：移动端统一直连 + headers，不走本地/服务端代理链。
        if (mobileDirect) {
          final headers = _buildPlaybackHeaders(track.source);
          try {
            await _playWithSoftSwitch(songDetail.url, headers: headers);
          } catch (e) {
            final tempPath = await _downloadAndPlay(songDetail, headers: headers);
            if (tempPath != null) {
              _currentTempFilePath = tempPath;
            } else {
              throw Exception('移动端直连与下载回退均失败: $e');
            }
          }
        } else {
          final proxyReady = await _ensureLocalProxyRunning(platform);
          if (proxyReady) {
            final proxyUrl = ProxyService().getProxyUrl(songDetail.url, platform);
            try {
              await _playWithSoftSwitch(proxyUrl);
            } catch (_) {
              final tempPath = await _downloadAndPlay(songDetail);
              if (tempPath != null) _currentTempFilePath = tempPath;
            }
          } else {
            final tempPath = await _downloadAndPlay(songDetail);
            if (tempPath != null) _currentTempFilePath = tempPath;
          }
        }
      } else {
        // 网易云等直接播放
        await _playWithSoftSwitch(songDetail.url);
      }

      // 异步缓存
      final shouldSkipCache = songDetail.source == MusicSource.apple ||
          songDetail.url.toLowerCase().contains('.m3u8');
      if (!isCached && !shouldSkipCache) {
        _cacheSongInBackground(track, songDetail, qualityStr);
      }

      await coverManager.extractThemeColor(songDetail.pic);
    } on EngineReportedException {
      // 错误已通过 errorStream 进入 _onEngineError，避免重复进入 catch 路径造成连跳。
      if (isStale()) return;
      return;
    } on AudioSourceNotConfiguredException catch (e) {
      if (isStale()) return;
      _state = PBState.error;
      _errorMessage = e.message;
      _isAudioSourceNotConfigured = true;
      notifyListeners();
      onAudioSourceNotConfigured?.call();
    } catch (e) {
      if (isStale()) return;
      _state = PBState.error;
      _errorMessage = '播放失败: $e';
      _isAudioSourceNotConfigured = false;
      notifyListeners();
      _autoSkipOnError();
    }
  }

  // ══════════════════════════════════════════════════════
  // 自动播放 / 切歌
  // ══════════════════════════════════════════════════════

  Future<void> _playNextAuto() async {
    final mode = PlaybackModeService().currentMode;
    switch (mode) {
      case PlaybackMode.repeatOne:
        if (currentTrack != null) {
          await _commands.enqueue(() async {
            await _waitForTrackSwitchSettle();
            final replayed = await _replayCurrentSourceForRepeatOne();
            if (!replayed) {
              await _playCurrentTrack();
            }
          });
        }
        break;
      case PlaybackMode.loopAll:
        await _playSequentialNext();
        break;
      case PlaybackMode.shuffle:
        await _playRandomNext();
        break;
      case PlaybackMode.sequential:
        await _playSequentialNextOrStop();
        break;
    }
  }

  /// 顺序播放模式：播完最后一首停止
  Future<void> _playSequentialNextOrStop() async {
    return _commands.enqueue(() async {
      if (_queue.isNotEmpty) {
        final nextIdx = _currentIndex + 1;
        if (nextIdx < _queue.length) {
          _currentIndex = nextIdx;
          await _waitForTrackSwitchSettle();
          await _playCurrentTrack();
          return;
        }
        // 到末尾了，停止播放
        await _engine.stop();
        _state = PBState.idle;
        _pauseListeningTimeTracking();
        _stopStateSaveTimer();
        notifyListeners();
        return;
      }
      // 无队列，用播放历史
      final nextTrack = PlayHistoryService().getNextTrack();
      if (nextTrack != null) {
        _queue
          ..clear()
          ..add(nextTrack);
        _currentIndex = 0;
        _source = QueueSource.history;
        await _waitForTrackSwitchSettle();
        await _playCurrentTrack();
      }
    });
  }

  Future<void> _playSequentialNext() async {
    return _commands.enqueue(() async {
      if (_queue.isNotEmpty) {
        final nextIdx = _currentIndex + 1;
        if (nextIdx < _queue.length) {
          _currentIndex = nextIdx;
          await _waitForTrackSwitchSettle();
          await _playCurrentTrack();
          return;
        }
        // 列表循环
        _currentIndex = 0;
        await _waitForTrackSwitchSettle();
        await _playCurrentTrack();
        return;
      }
      // 无队列，用播放历史
      final nextTrack = PlayHistoryService().getNextTrack();
      if (nextTrack != null) {
        _queue
          ..clear()
          ..add(nextTrack);
        _currentIndex = 0;
        _source = QueueSource.history;
        await _waitForTrackSwitchSettle();
        await _playCurrentTrack();
      }
    });
  }

  Future<void> _playSequentialPrevious() async {
    return _commands.enqueue(() async {
      if (_queue.isNotEmpty) {
        final prevIdx = _currentIndex - 1;
        if (prevIdx >= 0) {
          _currentIndex = prevIdx;
          await _playCurrentTrack();
          return;
        }
        // 列表循环
        _currentIndex = _queue.length - 1;
        await _playCurrentTrack();
        return;
      }
      final history = PlayHistoryService().history;
      if (history.length >= 3) {
        final prevTrack = history[2].toTrack();
        _queue
          ..clear()
          ..add(prevTrack);
        _currentIndex = 0;
        _source = QueueSource.history;
        await _playCurrentTrack();
      }
    });
  }

  // ── 随机播放 ──

  void _generateShuffledIndices() {
    _shuffledIndices = List.generate(_queue.length, (i) => i);
    for (int i = _shuffledIndices.length - 1; i > 0; i--) {
      final j = _random.nextInt(i + 1);
      final temp = _shuffledIndices[i];
      _shuffledIndices[i] = _shuffledIndices[j];
      _shuffledIndices[j] = temp;
    }
    if (_currentIndex >= 0 && _shuffledIndices.isNotEmpty && _shuffledIndices[0] == _currentIndex) {
      final swapIdx = _random.nextInt(_shuffledIndices.length - 1) + 1;
      final temp = _shuffledIndices[0];
      _shuffledIndices[0] = _shuffledIndices[swapIdx];
      _shuffledIndices[swapIdx] = temp;
    }
    _shufflePosition = -1;
  }

  Future<void> _playRandomNext() async {
    return _commands.enqueue(() async {
      if (_queue.isEmpty) {
        // 从历史随机
        final history = PlayHistoryService().history;
        if (history.length >= 2) {
          final idx = _random.nextInt(history.length - 1) + 1;
          _queue
            ..clear()
            ..add(history[idx].toTrack());
          _currentIndex = 0;
          _source = QueueSource.history;
          await _waitForTrackSwitchSettle();
          await _playCurrentTrack();
        }
        return;
      }
      if (_shuffledIndices.isEmpty || _shufflePosition >= _shuffledIndices.length - 1) {
        _generateShuffledIndices();
      }
      _shufflePosition++;
      _currentIndex = _shuffledIndices[_shufflePosition];
      await _waitForTrackSwitchSettle();
      await _playCurrentTrack();
    });
  }

  Future<void> _playRandomPrevious() async {
    return _commands.enqueue(() async {
      if (_queue.isEmpty || _shuffledIndices.isEmpty || _shufflePosition <= 0) return;
      _shufflePosition--;
      _currentIndex = _shuffledIndices[_shufflePosition];
      await _playCurrentTrack();
    });
  }

  // ══════════════════════════════════════════════════════
  // 兼容接口 (供 PlaylistQueueService facade 调用)
  // ══════════════════════════════════════════════════════

  /// setQueue 兼容：替换队列（不自动播放，仅更新状态）
  void setQueueSilent(List<Track> tracks, int index, QueueSource source, {Map<String, ImageProvider>? coverProviders}) {
    _resetPreloadState();
    _pendingRestorePosition = null;
    _queue
      ..clear()
      ..addAll(tracks);
    _currentIndex = index;
    _source = source;
    _coverProviders
      ..clear()
      ..addAll(coverProviders ?? {});
    _resetShuffle();
    notifyListeners();
    _scheduleSessionPersist();
  }

  /// getNext 兼容：更新索引到下一首并返回
  Track? peekAndAdvanceNext() {
    if (_queue.isEmpty) return null;
    final mode = PlaybackModeService().currentMode;
    if (mode == PlaybackMode.shuffle) {
      if (_shuffledIndices.isEmpty || _shufflePosition >= _shuffledIndices.length - 1) {
        _generateShuffledIndices();
      }
      _shufflePosition++;
      _currentIndex = _shuffledIndices[_shufflePosition];
      notifyListeners();
      return _queue[_currentIndex];
    }
    final nextIdx = _currentIndex + 1;
    if (nextIdx < _queue.length) {
      _currentIndex = nextIdx;
      notifyListeners();
      return _queue[_currentIndex];
    }
    // 列表循环
    _currentIndex = 0;
    notifyListeners();
    return _queue[0];
  }

  /// getPrevious 兼容：更新索引到上一首并返回
  Track? peekAndAdvancePrevious() {
    if (_queue.isEmpty) return null;
    final mode = PlaybackModeService().currentMode;
    if (mode == PlaybackMode.shuffle) {
      if (_shuffledIndices.isEmpty || _shufflePosition <= 0) return null;
      _shufflePosition--;
      _currentIndex = _shuffledIndices[_shufflePosition];
      notifyListeners();
      return _queue[_currentIndex];
    }
    final prevIdx = _currentIndex - 1;
    if (prevIdx >= 0) {
      _currentIndex = prevIdx;
      notifyListeners();
      return _queue[_currentIndex];
    }
    // 列表循环
    _currentIndex = _queue.length - 1;
    notifyListeners();
    return _queue[_currentIndex];
  }

  /// getRandomTrack 兼容
  Track? getRandomTrack() {
    if (_queue.isEmpty) return null;
    if (_shuffledIndices.isEmpty || _shufflePosition >= _shuffledIndices.length - 1) {
      _generateShuffledIndices();
    }
    _shufflePosition++;
    _currentIndex = _shuffledIndices[_shufflePosition];
    notifyListeners();
    return _queue[_currentIndex];
  }

  /// getRandomPrevious 兼容
  Track? getRandomPrevious() {
    if (_queue.isEmpty || _shuffledIndices.isEmpty || _shufflePosition <= 0) return null;
    _shufflePosition--;
    _currentIndex = _shuffledIndices[_shufflePosition];
    notifyListeners();
    return _queue[_currentIndex];
  }

  // ══════════════════════════════════════════════════════
  // 辅助方法（从 PlayerService 提取）
  // ══════════════════════════════════════════════════════

  void _syncPositionToNative(Duration position, {bool force = false}) {
    if (!Platform.isAndroid) return;
    final now = DateTime.now();
    if (force || now.difference(_lastNativeSyncTime).inMilliseconds > 500) {
      AndroidFloatingLyricService().updatePosition(position);
      _lastNativeSyncTime = now;
    }
  }

  void _precacheNextCover() {
    try {
      final nextTrack = peekNext(PlaybackModeService().currentMode);
      if (nextTrack == null || nextTrack.picUrl.isEmpty) return;
      final url = nextTrack.picUrl;
      if (!url.startsWith('http')) return;
      final provider = CachedNetworkImageProvider(url);
      final stream = provider.resolve(ImageConfiguration.empty);
      late ImageStreamListener listener;
      listener = ImageStreamListener((_, __) {
        stream.removeListener(listener);
        final bg = PlayerBackgroundService();
        if (bg.enableGradient && bg.backgroundType == PlayerBackgroundType.adaptive) {
          coverManager.precacheThemeColor(url);
        }
      }, onError: (_, __) {
        stream.removeListener(listener);
      });
      stream.addListener(listener);
    } catch (_) {}
  }

  void _resetPreloadState() {
    _lastPreloadedTargetKey = null;
    _preloadingNext = false;
    _preloadOp++;
  }

  String _buildTrackIdentity(Track track) => '${track.source.name}_${track.id}';

  String _buildPrefetchCacheKey(Track track, AudioQuality quality) {
    return '${_buildTrackIdentity(track)}_${quality.toString()}';
  }

  SongDetail? _takePrefetchedSongDetail(Track track, AudioQuality quality) {
    final key = _buildPrefetchCacheKey(track, quality);
    return _prefetchedPlayableDetails.remove(key);
  }

  void _savePrefetchedSongDetail(Track track, AudioQuality quality, SongDetail detail) {
    final key = _buildPrefetchCacheKey(track, quality);
    _prefetchedPlayableDetails[key] = detail;
    if (_prefetchedPlayableDetails.length > _maxPrefetchedPlayableDetails) {
      final oldestKey = _prefetchedPlayableDetails.keys.first;
      _prefetchedPlayableDetails.remove(oldestKey);
    }
  }

  SongDetail _normalizeSongDetailForPlayback(Track track, SongDetail detail) {
    var normalized = detail;

    if (normalized.name.isEmpty || normalized.arName.isEmpty || normalized.pic.isEmpty) {
      normalized = SongDetail(
        id: normalized.id,
        name: normalized.name.isNotEmpty ? normalized.name : track.name,
        pic: normalized.pic.isNotEmpty ? normalized.pic : track.picUrl,
        arName: normalized.arName.isNotEmpty ? normalized.arName : track.artists,
        alName: normalized.alName.isNotEmpty ? normalized.alName : track.album,
        level: normalized.level,
        size: normalized.size,
        url: normalized.url,
        lyric: normalized.lyric,
        tlyric: normalized.tlyric,
        source: normalized.source,
      );
    }

    if (track.source == MusicSource.apple && !normalized.url.contains('/apple/stream')) {
      final baseUrl = UrlService().baseUrl;
      final salableAdamId = Uri.encodeComponent(track.id.toString());
      normalized = SongDetail(
        id: normalized.id,
        name: normalized.name,
        pic: normalized.pic,
        arName: normalized.arName,
        alName: normalized.alName,
        level: normalized.level,
        size: normalized.size,
        url: '$baseUrl/apple/stream?salableAdamId=$salableAdamId',
        lyric: normalized.lyric,
        tlyric: normalized.tlyric,
        source: normalized.source,
      );
    }

    return normalized;
  }

  Future<void> _waitForTrackSwitchSettle() async {
    if (!_engine.isPlaying) {
      return;
    }
    await Future.delayed(_trackSwitchSettleDelay);
  }

  Future<void> _safeSetEngineVolume(double volume) async {
    try {
      await _engine.setVolume(volume);
    } catch (_) {}
  }

  Future<void> _playWithSoftSwitch(
    String url, {
    bool isLocal = false,
    Map<String, String>? headers,
  }) async {
    final targetVolume = _volume.clamp(0.0, 1.0);
    final canFade = _engine.isPlaying && targetVolume > 0;

    if (!canFade) {
      await _engine.play(url, isLocal: isLocal, headers: headers);
      await _safeSetEngineVolume(targetVolume);
      return;
    }

    final stepVolume = targetVolume / _switchFadeSteps;
    for (int i = _switchFadeSteps; i > 0; i--) {
      await _safeSetEngineVolume(stepVolume * (i - 1));
      await Future.delayed(_switchFadeStepDelay);
    }

    try {
      await _engine.play(url, isLocal: isLocal, headers: headers);
    } catch (e) {
      await _safeSetEngineVolume(targetVolume);
      rethrow;
    }

    for (int i = 1; i <= _switchFadeSteps; i++) {
      await _safeSetEngineVolume(stepVolume * i);
      await Future.delayed(_switchFadeStepDelay);
    }
  }

  void _schedulePreloadNextTrack() {
    unawaited(_preloadNextTrack());
  }

  Future<void> _preloadNextTrack() async {
    if (_preloadingNext) return;
    final nextTrack = peekNext(PlaybackModeService().currentMode);
    final current = currentTrack;
    if (nextTrack == null || current == null) return;

    final nextKey = '${nextTrack.source.name}_${nextTrack.id}';
    final currentKey = '${current.source.name}_${current.id}';
    if (nextKey == currentKey || nextKey == _lastPreloadedTargetKey) return;
    if (nextTrack.source != MusicSource.local && !AudioSourceService().isConfigured) {
      return;
    }

    _preloadingNext = true;
    final op = ++_preloadOp;
    try {
      await _preloadTrackSource(nextTrack);
      if (op == _preloadOp) {
        _lastPreloadedTargetKey = nextKey;
      }
    } catch (e) {
      print('[PlaybackService] 预加载下一首失败: $e');
    } finally {
      _preloadingNext = false;
    }
  }

  Future<bool> _replayCurrentSourceForRepeatOne() async {
    final track = currentTrack;
    final song = _currentSong;
    if (track == null || song == null || song.url.isEmpty) return false;

    final url = song.url;
    final isLocal = track.source == MusicSource.local || !url.startsWith('http');
    Map<String, String>? headers;
    if (!isLocal &&
        (Platform.isAndroid || Platform.isIOS) &&
        (track.source == MusicSource.qq || track.source == MusicSource.kugou)) {
      headers = _buildPlaybackHeaders(track.source);
    }

    try {
      await _playWithSoftSwitch(url, isLocal: isLocal, headers: headers);
      return true;
    } on EngineReportedException {
      // 已由 _onEngineError 处理重试/跳过策略。
      return true;
    } catch (e) {
      print('[PlaybackService] repeatOne 复用当前音源失败，回退重新拉流: $e');
      return false;
    }
  }

  Future<void> _preloadTrackSource(Track track) async {
    if (track.source == MusicSource.local) {
      final filePath = track.id is String ? track.id as String : '';
      if (filePath.isEmpty || !(await File(filePath).exists())) return;
      await _engine.preload(filePath, isLocal: true);
      return;
    }

    // 命中本地缓存时跳过预加载：缓存播放已是本地文件链路。
    if (CacheService().isCached(track)) return;

    final selectedQuality = AudioQualityService().currentQuality;
    var detail = await MusicService().fetchSongDetail(
      songId: track.id,
      quality: selectedQuality,
      source: track.source,
      title: track.name,
      artist: track.artists,
    );
    if (detail == null || detail.url.isEmpty) return;
    detail = _normalizeSongDetailForPlayback(track, detail);
    _savePrefetchedSongDetail(track, selectedQuality, detail);
    final url = detail.url;

    Map<String, String>? headers;
    if ((Platform.isAndroid || Platform.isIOS) &&
        (track.source == MusicSource.qq || track.source == MusicSource.kugou)) {
      headers = _buildPlaybackHeaders(track.source);
    }
    await _engine.preload(url, headers: headers);
  }

  Map<String, String> _buildPlaybackHeaders(MusicSource source) {
    final headers = <String, String>{
      'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36',
    };
    if (source == MusicSource.qq) {
      headers['Referer'] = 'https://y.qq.com/';
      headers['Origin'] = 'https://y.qq.com';
    } else if (source == MusicSource.kugou) {
      headers['Referer'] = 'https://www.kugou.com/';
      headers['Origin'] = 'https://www.kugou.com';
    }
    return headers;
  }

  String _getServerProxyUrl(String originalUrl, String platform) {
    final baseUrl = UrlService().baseUrl;
    final encodedUrl = Uri.encodeComponent(originalUrl);
    return '$baseUrl/audio-proxy/stream?url=$encodedUrl&platform=$platform';
  }

  Future<bool> _ensureLocalProxyRunning(String platform) async {
    if (ProxyService().isRunning) return true;
    return await ProxyService().start();
  }

  Future<String?> _downloadViaProxyAndPlay(String proxyUrl, String songName, [String? level]) async {
    try {
      final tempDir = await getTemporaryDirectory();
      final ts = DateTime.now().millisecondsSinceEpoch;
      final ext = AudioQualityService.getExtensionFromLevel(level);
      final path = '${tempDir.path}/temp_audio_$ts.$ext';
      final response = await http.get(Uri.parse(proxyUrl));
      if (response.statusCode == 200) {
        await File(path).writeAsBytes(response.bodyBytes);
        await _playWithSoftSwitch(path, isLocal: true);
        return path;
      }
    } catch (e) {
      print('[PlaybackService] 代理下载异常: $e');
    }
    return null;
  }

  Future<String?> _downloadAndPlay(
    SongDetail songDetail, {
    Map<String, String>? headers,
  }) async {
    final client = http.Client();
    try {
      final tempDir = await getTemporaryDirectory();
      final ts = DateTime.now().millisecondsSinceEpoch;
      final ext = AudioQualityService.getExtensionFromLevel(songDetail.level);
      final path = '${tempDir.path}/temp_audio_$ts.$ext';
      final requestHeaders = headers ?? _buildPlaybackHeaders(songDetail.source);
      final request = http.Request('GET', Uri.parse(songDetail.url))
        ..headers.addAll(requestHeaders);

      final response = await client
          .send(request)
          .timeout(const Duration(seconds: 20));

      if (response.statusCode != 200) {
        print('[PlaybackService] 下载音频失败: HTTP ${response.statusCode}');
        return null;
      }

      final bytesBuilder = BytesBuilder(copy: false);
      var downloadedBytes = 0;
      final totalBytes = response.contentLength ?? 0;
      var nextProgressMark = 20;

      await for (final chunk in response.stream.timeout(const Duration(seconds: 20))) {
        bytesBuilder.add(chunk);
        downloadedBytes += chunk.length;

        if (totalBytes > 0) {
          final progress = (downloadedBytes * 100 / totalBytes).floor();
          if (progress >= nextProgressMark) {
            print('[PlaybackService] 下载中: $progress% ($downloadedBytes/$totalBytes)');
            nextProgressMark += 20;
          }
        }
      }

      final bytes = bytesBuilder.takeBytes();
      if (bytes.isEmpty) {
        print('[PlaybackService] 下载音频失败: 响应为空');
        return null;
      }

      await File(path).writeAsBytes(bytes);
      await _playWithSoftSwitch(path, isLocal: true);
      return path;
    } on TimeoutException {
      print('[PlaybackService] 下载音频超时');
    } catch (e) {
      print('[PlaybackService] 下载音频失败: $e');
    } finally {
      client.close();
    }
    return null;
  }

  Future<int?> _getAppleStreamDuration(String streamUrl) async {
    try {
      final request = http.Request('HEAD', Uri.parse(streamUrl));
      request.headers['User-Agent'] = 'Mozilla/5.0';
      final client = http.Client();
      try {
        final response = await client.send(request).timeout(const Duration(seconds: 30));
        final ms = response.headers['x-duration-ms'];
        if (ms != null) return int.tryParse(ms);
        final sec = response.headers['x-content-duration'];
        if (sec != null) {
          final d = double.tryParse(sec);
          if (d != null && d > 0) return (d * 1000).round();
        }
      } finally {
        client.close();
      }
    } catch (_) {}
    return null;
  }

  void _notifyAppleMusicRestriction(Track track) {
    NotificationService().showNotification(
      id: DateTime.now().millisecondsSinceEpoch % 100000,
      title: 'Apple Music 播放限制',
      body: '由于Apple接口限制，"${track.name}" 需要换源才能播放！',
    );
    if (Platform.isAndroid || Platform.isIOS) {
      ToastUtils.error('由于Apple接口限制，该音乐需换源播放');
    }
  }

  Future<void> _cacheSongInBackground(Track track, SongDetail detail, String quality) async {
    try {
      await CacheService().cacheSong(track, detail, quality);
    } catch (_) {}
  }

  Future<void> _cleanupCurrentTempFile() async {
    if (_currentTempFilePath != null) {
      try {
        final f = File(_currentTempFilePath!);
        if (await f.exists()) await f.delete();
      } catch (_) {} finally {
        _currentTempFilePath = null;
      }
    }
  }

  void _bgUpdateLyrics(Track track, dynamic quality, String qualityStr, String requestedKey, bool Function() isStale) {
    MusicService().fetchSongDetail(
      songId: track.id, source: track.source, quality: quality,
      title: track.name, artist: track.artists,
    ).then((detail) {
      if (isStale()) return;
      final ct = currentTrack;
      if (ct == null || '${ct.source.name}_${ct.id}' != requestedKey) return;
      if (detail != null && detail.lyric.isNotEmpty && _currentSong != null) {
        _currentSong = SongDetail(
          id: _currentSong!.id, name: detail.name.isNotEmpty ? detail.name : _currentSong!.name,
          url: _currentSong!.url, pic: detail.pic.isNotEmpty ? detail.pic : _currentSong!.pic,
          arName: detail.arName.isNotEmpty ? detail.arName : _currentSong!.arName,
          alName: detail.alName.isNotEmpty ? detail.alName : _currentSong!.alName,
          level: _currentSong!.level, size: _currentSong!.size,
          lyric: detail.lyric, tlyric: detail.tlyric, source: _currentSong!.source,
        );
        CacheService().cacheSong(track, _currentSong!, qualityStr);
        notifyListeners();
        _loadLyricsForFloatingDisplay();
      }
    }).catchError((_) {});
  }

  // ── 播放失败自动跳过 ──

  void _autoSkipOnError() {
    _consecutiveErrors++;
    if (_consecutiveErrors >= _maxConsecutiveErrors) {
      print('[PlaybackService] 连续 $_consecutiveErrors 首播放失败，停止自动跳过');
      return;
    }
    if (_queue.isEmpty || _queue.length <= 1) return;
    print('[PlaybackService] 播放失败，2 秒后自动跳到下一首 ($_consecutiveErrors/$_maxConsecutiveErrors)');
    Future.delayed(const Duration(seconds: 2), () {
      if (_state != PBState.error) return; // 用户已手动操作
      _playNextAuto();
    });
  }

  // ── 听歌统计 ──

  void _startListeningTimeTracking() {
    if (_statsTimer != null && _statsTimer!.isActive) return;
    _playStartTime = DateTime.now();
    _statsTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      if (_playStartTime != null) {
        final elapsed = DateTime.now().difference(_playStartTime!).inSeconds;
        if (elapsed > 0) {
          ListeningStatsService().accumulateListeningTime(elapsed);
          _playStartTime = DateTime.now();
        }
      }
    });
  }

  void _pauseListeningTimeTracking() {
    if (_statsTimer != null) {
      if (_playStartTime != null) {
        final elapsed = DateTime.now().difference(_playStartTime!).inSeconds;
        if (elapsed > 0) {
          ListeningStatsService().accumulateListeningTime(elapsed);
        }
      }
      _statsTimer?.cancel();
      _statsTimer = null;
      _playStartTime = null;
    }
  }

  // ── 本地播放会话保存 ──

  void _startStateSaveTimer() {
    if (_stateSaveTimer != null && _stateSaveTimer!.isActive) return;
    _stateSaveTimer = Timer.periodic(const Duration(seconds: 10), (_) {
      _scheduleSessionPersist();
    });
  }

  void _stopStateSaveTimer() {
    _stateSaveTimer?.cancel();
    _stateSaveTimer = null;
  }

  void _scheduleSessionPersist() {
    _sessionPersistDebounce?.cancel();
    _sessionPersistDebounce = Timer(
      const Duration(milliseconds: 600),
      () => unawaited(_persistSessionNow()),
    );
  }

  Future<void> _persistSessionNow() async {
    final snapshot = _buildSessionSnapshot();
    if (snapshot == null) {
      await PlaybackSessionStore().clear();
      return;
    }
    await PlaybackSessionStore().saveSnapshot(snapshot);
  }

  Future<void> _applyPendingRestorePosition() async {
    final pending = _pendingRestorePosition;
    if (pending == null || pending <= Duration.zero) return;
    _pendingRestorePosition = null;
    await Future.delayed(const Duration(milliseconds: 500));
    await seek(pending);
  }

  // ── 音量保存 ──
  Timer? _saveVolumeTimer;
  void _saveVolumeThrottled() {
    _saveVolumeTimer?.cancel();
    _saveVolumeTimer = Timer(const Duration(milliseconds: 1000), () {
      PersistentStorageService().setDouble('player_volume', _volume);
    });
  }

  // ── 歌词 ──

  void _loadLyricsForFloatingDisplay() {
    final song = _currentSong;
    final track = currentTrack;

    if (Platform.isWindows && DesktopLyricService().isVisible && track != null) {
      DesktopLyricService().setSongInfo(title: track.name, artist: track.artists, albumCover: track.picUrl);
    }

    if (song == null || song.lyric.isEmpty) {
      _lyrics = [];
      _currentLyricIndex = -1;
      if (Platform.isWindows && DesktopLyricService().isVisible) DesktopLyricService().setLyricText('');
      if (Platform.isAndroid && AndroidFloatingLyricService().isVisible) {
        AndroidFloatingLyricService().setLyricText('');
        AndroidFloatingLyricService().setLyricsData([]);
      }
      return;
    }

    try {
      switch (song.source.name) {
        case 'netease':
          _lyrics = LyricParser.parseNeteaseLyric(
            song.lyric, translation: song.tlyric.isNotEmpty ? song.tlyric : null,
            yrcLyric: song.yrc.isNotEmpty ? song.yrc : null,
            yrcTranslation: song.ytlrc.isNotEmpty ? song.ytlrc : null,
          );
          break;
        case 'qq':
          _lyrics = LyricParser.parseQQLyric(
            song.lyric, translation: song.tlyric.isNotEmpty ? song.tlyric : null,
            qrcLyric: song.qrc.isNotEmpty ? song.qrc : null,
            qrcTranslation: song.qrcTrans.isNotEmpty ? song.qrcTrans : null,
          );
          break;
        case 'kugou':
          _lyrics = LyricParser.parseKugouLyric(
            song.lyric, translation: song.tlyric.isNotEmpty ? song.tlyric : null,
          );
          break;
        default:
          _lyrics = LyricParser.parseNeteaseLyric(
            song.lyric, translation: song.tlyric.isNotEmpty ? song.tlyric : null,
            yrcLyric: song.yrc.isNotEmpty ? song.yrc : null,
            yrcTranslation: song.ytlrc.isNotEmpty ? song.ytlrc : null,
          );
      }
      _currentLyricIndex = -1;

      if (Platform.isAndroid && AndroidFloatingLyricService().isVisible) {
        Future.microtask(() {
          final data = _lyrics.map((line) => {
            'time': line.startTime.inMilliseconds,
            'text': line.text,
            'translation': line.translation ?? '',
          }).toList();
          AndroidFloatingLyricService().setLyricsData(data);
        });
      }
      _updateFloatingLyric();
    } catch (e) {
      _lyrics = [];
      _currentLyricIndex = -1;
    }
  }

  void _updateFloatingLyric() {
    if (_lyrics.isEmpty) return;
    final isWin = Platform.isWindows && DesktopLyricService().isVisible;
    final isAndroid = Platform.isAndroid && AndroidFloatingLyricService().isVisible;
    if (!isWin && !isAndroid) return;

    try {
      final newIdx = LyricParser.findCurrentLineIndex(_lyrics, _position);
      if (newIdx != _currentLyricIndex && newIdx >= 0) {
        _currentLyricIndex = newIdx;
        final line = _lyrics[newIdx];
        int? durationMs;
        if (newIdx + 1 < _lyrics.length) {
          durationMs = _lyrics[newIdx + 1].startTime.inMilliseconds - line.startTime.inMilliseconds;
        } else {
          durationMs = 3000;
        }
        if (isWin) {
          DesktopLyricService().setLyricText(line.text, durationMs: durationMs);
          DesktopLyricService().setTranslationText(
            (line.translation != null && line.translation!.isNotEmpty) ? line.translation! : '',
          );
        }
        if (isAndroid) {
          String displayText = line.text;
          if (line.translation != null && line.translation!.isNotEmpty) {
            displayText = '${line.text}\n${line.translation}';
          }
          AndroidFloatingLyricService().setLyricText(displayText);
        }
      }
    } catch (_) {}
  }

  /// 手动更新悬浮歌词（供后台服务调用）
  Future<void> updateFloatingLyricManually() async {
    _syncPositionToNative(_position);
  }

  // ── 均衡器 ──
  Future<void> updateEqualizer(List<double> gains) async {
    await EqualizerService().updateEqualizer(gains);
    notifyListeners();
  }

  Future<void> setEqualizerEnabled(bool enabled) async {
    await EqualizerService().setEqualizerEnabled(enabled);
    notifyListeners();
  }

  // ── 清除会话 ──
  Future<void> clearSession() async {
    await _engine.stop();
    _state = PBState.idle;
    _currentSong = null;
    _queue.clear();
    _currentIndex = -1;
    _source = QueueSource.none;
    _preloadedTrack = null;
    _position = Duration.zero;
    _duration = Duration.zero;
    _bufferedPosition = Duration.zero;
    _errorMessage = null;
    positionNotifier.value = Duration.zero;
    bufferedPositionNotifier.value = Duration.zero;
    coverManager.setCover(null, notify: false);
    coverManager.themeColorNotifier.value = null;
    _coverProviders.clear();
    _resetShuffle();
    await _cleanupCurrentTempFile();
    _stopStateSaveTimer();
    _pendingRestorePosition = null;
    _pauseListeningTimeTracking();
    notifyListeners();
    await PlaybackSessionStore().clear();
    if (Platform.isAndroid) {
      AndroidFloatingLyricService().setPlayingState(false);
      AndroidFloatingLyricService().updatePosition(Duration.zero);
    }
  }

  /// 强制释放所有资源
  Future<void> forceDispose() async {
    try {
      await _cleanupCurrentTempFile();
      await CacheService().cleanTempFiles();
      await ProxyService().stop();
      _state = PBState.idle;
      _currentSong = null;
      _preloadedTrack = null;
      _position = Duration.zero;
      _duration = Duration.zero;
      _bufferedPosition = Duration.zero;
      coverManager.setCover(null, notify: false);
      _sessionPersistDebounce?.cancel();
      await _engine.dispose();
    } catch (e) {
      print('[PlaybackService] 释放资源失败: $e');
    }
  }

  @override
  void dispose() {
    for (final sub in _engineSubs) {
      sub.cancel();
    }
    _engineSubs.clear();
    PlaybackModeService().removeListener(_precacheNextCover);
    _pauseListeningTimeTracking();
    _stopStateSaveTimer();
    _sessionPersistDebounce?.cancel();
    _cleanupCurrentTempFile();
    _engine.dispose();
    ProxyService().stop();
    coverManager.dispose();
    positionNotifier.dispose();
    bufferedPositionNotifier.dispose();
    super.dispose();
  }
}
