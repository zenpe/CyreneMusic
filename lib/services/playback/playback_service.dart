import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:http/http.dart' as http;
import 'package:just_audio/just_audio.dart' as ja;
import 'package:path_provider/path_provider.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../../models/track.dart';
import '../../models/song_detail.dart';
import '../../models/lyric_line.dart';
import '../../utils/lyric_parser.dart';
import '../../utils/toast_utils.dart';
import '../../utils/metadata_reader.dart';
import '../../utils/image_utils.dart';
import '../../utils/audio_request_headers.dart';
import '../music_service.dart';
import '../audio_source_service.dart';
import '../cache_service.dart';
import '../proxy_service.dart';
import '../play_history_service.dart';
import '../playback_mode_service.dart';
import '../playlist_queue_service.dart';
import '../audio_quality_service.dart';
import '../developer_mode_service.dart';
import '../listening_stats_service.dart';
import '../desktop_lyric_service.dart';
import '../android_floating_lyric_service.dart';
import '../player_background_service.dart';
import '../local_library_service.dart';
import '../url_service.dart';
import '../notification_service.dart';
import '../persistent_storage_service.dart';
import '../equalizer_service.dart';
import '../lyric/lyric_service.dart';
import '../lyric/lyric_snapshot.dart';

import 'command_queue.dart';
import 'audio_engine.dart';
import 'cover_manager.dart';
import 'cyrene_stream_source.dart';
import 'playback_session_snapshot.dart';
import 'playback_session_store.dart';
import 'playable_source.dart';

/// 播放状态枚举（复用 PlayerService 的定义）
enum PBState { idle, loading, playing, paused, error }

class _PrefetchedPlayablePlanEntry {
  final _TrackSwitchPlaybackPlan plan;
  final DateTime expiresAt;

  const _PrefetchedPlayablePlanEntry({
    required this.plan,
    required this.expiresAt,
  });

  bool get isExpired => DateTime.now().isAfter(expiresAt);
}

enum _SongDetailRequestState { running, completed, failed, expired }

class _SongDetailRequestEntry {
  final String key;
  final DateTime startedAt;
  final DateTime hardDeadline;
  final Future<SongDetail?> future;
  _SongDetailRequestState state;

  _SongDetailRequestEntry({
    required this.key,
    required this.startedAt,
    required this.hardDeadline,
    required this.future,
    this.state = _SongDetailRequestState.running,
  });

  bool get isReusable =>
      state == _SongDetailRequestState.running &&
      DateTime.now().isBefore(hardDeadline);

  void markCompleted() {
    state = _SongDetailRequestState.completed;
  }

  void markFailed() {
    state = _SongDetailRequestState.failed;
  }

  void markExpired() {
    state = _SongDetailRequestState.expired;
  }
}

class TrackSwitchTransaction {
  final int token;
  final int pendingToken;
  final Track track;
  final String reason;
  final String requestedKey;
  final AudioQuality selectedQuality;
  final String qualityStr;

  const TrackSwitchTransaction({
    required this.token,
    required this.pendingToken,
    required this.track,
    required this.reason,
    required this.requestedKey,
    required this.selectedQuality,
    required this.qualityStr,
  });
}

class _ResolvedTrackSwitchSong {
  final SongDetail songDetail;
  final CyreneFileInfo? cacheInfo;
  final bool isCached;
  final bool shouldRefreshCachedMetadata;
  final bool shouldRefreshExistingCacheMetadata;

  const _ResolvedTrackSwitchSong({
    required this.songDetail,
    required this.cacheInfo,
    required this.isCached,
    required this.shouldRefreshCachedMetadata,
    required this.shouldRefreshExistingCacheMetadata,
  });
}

class _TrackSwitchPlaybackPlan {
  final _ResolvedTrackSwitchSong resolvedSong;
  final bool usesCachedStream;
  final PlayableSource source;
  final String? retainedTempFilePath;
  final String? coverRefreshUrl;
  final String themeImageUrl;
  final String themeReason;
  final bool shouldWriteBackgroundCache;
  final String? cacheMetadataRefreshReason;

  const _TrackSwitchPlaybackPlan({
    required this.resolvedSong,
    required this.usesCachedStream,
    required this.source,
    required this.retainedTempFilePath,
    required this.coverRefreshUrl,
    required this.themeImageUrl,
    required this.themeReason,
    required this.shouldWriteBackgroundCache,
    required this.cacheMetadataRefreshReason,
  });
}

/// 核心播放服务
///
/// 统一管理队列状态（原 PlaylistQueueService）和播放控制（原 PlayerService）。
/// 主播放器展示态与队列指针解耦：
/// `currentTrack/currentSong/display*` 只读取 active*，
/// `_currentIndex` 只表示队列当前指针，pending* 表示待切换目标。
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
  Track? _activeTrack;
  SongDetail? _activeSong;
  int _activePlaybackToken = 0;
  Track? _pendingTrack;
  int _pendingSwitchToken = 0;
  String? _pendingReason;
  int _playGeneration = 0;
  int _consecutiveErrors = 0;
  static const int _maxConsecutiveErrors = 3;
  Duration _duration = Duration.zero;
  Duration _position = Duration.zero;
  Duration _bufferedPosition = Duration.zero;
  String? _errorMessage;
  String? _currentTempFilePath;
  CyreneFileInfo? _currentCachedStreamInfo;
  final Set<String> _cacheBypassKeys = <String>{};
  final Map<String, _SongDetailRequestEntry> _pendingSongDetailRequests =
      <String, _SongDetailRequestEntry>{};
  double _volume = 0.7;
  double _playbackSpeed = 1.0;
  bool _isAudioSourceNotConfigured = false;
  String? _retriedTrackKey;
  String? _lastPreloadedTargetKey;
  bool _preloadingNext = false;
  int _preloadOp = 0;
  final Map<String, _PrefetchedPlayablePlanEntry> _prefetchedPlayablePlans = {};
  Timer? _preloadTriggerTimer;
  bool _preloadDependencyListenersBound = false;

  static const int _switchFadeSteps = 8;
  static const Duration _switchFadeStepDelay = Duration(milliseconds: 15);
  static const Duration _trackSwitchSettleDelay = Duration(milliseconds: 80);
  static const Duration _preloadTriggerDelay = Duration(seconds: 3);
  static const Duration _prefetchedSongDetailTtl = Duration(minutes: 5);
  static const Duration _playSongDetailTimeout = Duration(seconds: 12);
  static const Duration _preloadSongDetailTimeout = Duration(seconds: 8);
  static const Duration _lyricSongDetailTimeout = Duration(seconds: 6);
  static const Duration _songDetailRequestHardTimeout =
      Duration(seconds: 18);
  static const int _maxPrefetchedPlayableDetails = 4;
  static const int _maxCacheBypassKeys = 64;

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
  Track? get activeTrack => _activeTrack;
  SongDetail? get activeSong => _activeSong;
  int get activePlaybackToken => _activePlaybackToken;
  Track? get pendingTrack => _pendingTrack;
  int? get pendingSwitchToken =>
      _pendingTrack == null ? null : _pendingSwitchToken;
  String? get pendingReason => _pendingReason;

  Track? get currentTrack => _activeTrack;

  List<Track> get queue => List.unmodifiable(_queue);
  int get currentIndex => _currentIndex;
  QueueSource get source => _source;
  bool get hasQueue => _queue.isNotEmpty;
  bool get isPlaying => _state == PBState.playing;
  bool get isPaused => _state == PBState.paused;
  bool get isLoading => _state == PBState.loading;
  PBState get state => _state;
  LyricLoadState get lyricLoadState => LyricService().currentState;
  LyricSnapshot? get lyricSnapshot => LyricService().currentSnapshot;
  SongDetail? get currentSong => _activeSong;
  String get displayTitle {
    final songName = _activeSong?.name;
    if (songName != null && songName.isNotEmpty) return songName;
    final trackName = _activeTrack?.name;
    if (trackName != null && trackName.isNotEmpty) return trackName;
    return '';
  }
  String get displayArtist {
    final songArtist = _activeSong?.arName;
    if (songArtist != null && songArtist.isNotEmpty) return songArtist;
    final trackArtist = _activeTrack?.artists;
    if (trackArtist != null && trackArtist.isNotEmpty) return trackArtist;
    return '';
  }
  String get displayAlbum {
    final songAlbum = _activeSong?.alName;
    if (songAlbum != null && songAlbum.isNotEmpty) return songAlbum;
    final trackAlbum = _activeTrack?.album;
    if (trackAlbum != null && trackAlbum.isNotEmpty) return trackAlbum;
    return '';
  }
  String? get displayCoverUrl {
    final coverUrl = coverManager.currentUrl;
    if (coverUrl != null && coverUrl.isNotEmpty) return coverUrl;
    final songPic = _activeSong?.pic;
    if (songPic != null && songPic.isNotEmpty) return songPic;
    final trackPic = _activeTrack?.picUrl;
    if (trackPic != null && trackPic.isNotEmpty) return trackPic;
    return null;
  }
  String get pendingDisplayTitle {
    final trackName = _pendingTrack?.name;
    if (trackName != null && trackName.isNotEmpty) return trackName;
    return '';
  }
  String get pendingDisplayArtist {
    final trackArtist = _pendingTrack?.artists;
    if (trackArtist != null && trackArtist.isNotEmpty) return trackArtist;
    return '';
  }
  String get pendingDisplayAlbum {
    final trackAlbum = _pendingTrack?.album;
    if (trackAlbum != null && trackAlbum.isNotEmpty) return trackAlbum;
    return '';
  }
  String? get pendingDisplayCoverUrl {
    final trackPic = _pendingTrack?.picUrl;
    if (trackPic != null && trackPic.isNotEmpty) return trackPic;
    return null;
  }
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
    _bindPreloadDependencyListeners();

    print('[PlaybackService] 初始化完成');
  }

  Future<bool> restoreSessionOnStartup({required bool autoPlay}) async {
    if (_hasRestoredSessionOnStartup) return currentTrack != null;
    _hasRestoredSessionOnStartup = true;

    try {
      final snapshot = await PlaybackSessionStore().loadSnapshot();
      if (snapshot == null || !snapshot.isValid) return false;

      await _restoreFromSnapshot(snapshot, autoPlay: autoPlay);
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
        : (_activeTrack != null ? [_activeTrack!] : const <Track>[]);
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

  Future<void> _restoreFromSnapshot(
    PlaybackSessionSnapshot snapshot, {
    required bool autoPlay,
  }) async {
    await PlaybackModeService().setMode(snapshot.playbackMode);

    _pendingRestorePosition =
        snapshot.position > Duration.zero ? snapshot.position : null;

    if (autoPlay) {
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
    _activeTrack = _trackAtQueuePointer();
    _activeSong = null;
    _clearPendingTrack();
    _setLyricLoadState(
      LyricLoadState.idle,
      track: _activeTrack,
      notify: false,
    );
    _errorMessage = null;
    _isAudioSourceNotConfigured = false;
    _duration = Duration.zero;
    _bufferedPosition = Duration.zero;
    _position = snapshot.position;
    positionNotifier.value = snapshot.position;
    bufferedPositionNotifier.value = Duration.zero;
    if (_activeTrack != null) {
      coverManager.updateCoverNonBlocking(
        _activeTrack!.picUrl,
        notify: false,
        force: true,
      );
    } else {
      coverManager.setCoverImmediate(null, notify: false);
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
        _startListeningTimeTracking();
        _startStateSaveTimer();
        if (Platform.isWindows) DesktopLyricService().setPlayingState(true);
        if (Platform.isAndroid) AndroidFloatingLyricService().setPlayingState(true);
        _scheduleSessionPersist();
        _schedulePreloadNextTrack();
        break;
      case EngineState.paused:
        _state = PBState.paused;
        _pauseListeningTimeTracking();
        _stopStateSaveTimer();
        if (Platform.isWindows) DesktopLyricService().setPlayingState(false);
        if (Platform.isAndroid) AndroidFloatingLyricService().setPlayingState(false);
        _cancelScheduledPreload();
        _scheduleSessionPersist();
        break;
      case EngineState.idle:
        _state = PBState.idle;
        _pauseListeningTimeTracking();
        _stopStateSaveTimer();
        if (Platform.isWindows) DesktopLyricService().setPlayingState(false);
        if (Platform.isAndroid) AndroidFloatingLyricService().setPlayingState(false);
        _cancelScheduledPreload();
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
    final track = _pendingTrack ?? currentTrack;
    if (track == null || _state == PBState.error) return;

    final trackKey = _buildTrackIdentity(track);
    final cacheQuality = _currentCachedStreamInfo?.metadata.quality;
    final shouldRetryWithoutCache =
        cacheQuality != null && _retriedTrackKey != trackKey;
    final canRetry =
        shouldRetryWithoutCache ||
        (_canRetryOnError(error) && _retriedTrackKey != trackKey);

    if (canRetry) {
      _retriedTrackKey = trackKey;
      if (cacheQuality != null) {
        print('[PlaybackService] 缓存流播放失败，绕过当前缓存后重试: $error');
      } else {
        print('[PlaybackService] 引擎错误，尝试自动重试: $error');
      }
      unawaited(_commands.enqueue(() async {
        final current = _pendingTrack ?? currentTrack;
        if (current == null) return;
        final currentKey = _buildTrackIdentity(current);
        if (currentKey != trackKey) return;
        if (cacheQuality != null) {
          _rememberCacheBypassKey(
            _cachePlaybackKey(current, cacheQuality),
            reason: 'engine-retry',
          );
          _currentCachedStreamInfo = null;
        }
        await _playCurrentTrack(reason: 'engine-retry');
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
      await _playCurrentTrack(reason: 'play-now');
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
      await _playCurrentTrack(reason: 'jump-to');
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
        _activeTrack = null;
        _activeSong = null;
        _clearPendingTrack();
        _duration = Duration.zero;
        _position = Duration.zero;
        _bufferedPosition = Duration.zero;
        positionNotifier.value = Duration.zero;
        bufferedPositionNotifier.value = Duration.zero;
        coverManager.setCoverImmediate(null, notify: false);
        coverManager.themeColorNotifier.value = null;
        _setLyricLoadState(LyricLoadState.idle, notify: false);
      } else if (index < _currentIndex) {
        _currentIndex--;
      } else if (index == _currentIndex) {
        _currentIndex = _currentIndex.clamp(0, _queue.length - 1);
        await _playCurrentTrack(reason: 'remove-current');
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
      _activeTrack = null;
      _activeSong = null;
      _clearPendingTrack();
      _duration = Duration.zero;
      _position = Duration.zero;
      _bufferedPosition = Duration.zero;
      positionNotifier.value = Duration.zero;
      bufferedPositionNotifier.value = Duration.zero;
      coverManager.setCoverImmediate(null, notify: false);
      coverManager.themeColorNotifier.value = null;
      _setLyricLoadState(LyricLoadState.idle, notify: false);
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
          await _playCurrentTrack(reason: 'resume');
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
    _preloadedTrack = null;
    _clearPendingTrack();
    _errorMessage = null;
    _duration = Duration.zero;
    _position = Duration.zero;
    _bufferedPosition = Duration.zero;
    positionNotifier.value = Duration.zero;
    bufferedPositionNotifier.value = Duration.zero;
    if (_activeTrack != null) {
      _primeDisplayStateForTrack(_activeTrack!);
    } else {
      coverManager.setCoverImmediate(null, notify: false);
      _setLyricLoadState(LyricLoadState.idle, notify: false);
    }
    notifyListeners();
    _pendingRestorePosition = null;
    _scheduleSessionPersist();
  }

  Future<void> togglePlayPause() async {
    isPlaying ? await pause() : await resume();
  }

  Future<void> retryCurrentTrack() async {
    return _commands.enqueue(() async {
      if (_trackAtQueuePointer() == null && _activeTrack == null) return;
      _state = PBState.loading;
      _errorMessage = null;
      _isAudioSourceNotConfigured = false;
      notifyListeners();
      await _playCurrentTrack(reason: 'manual-retry');
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
    _activeTrack = track;
    _activeSong = null;
    _activePlaybackToken++;
    _clearPendingTrack();
    _state = PBState.idle;
    _duration = Duration.zero;
    _position = Duration.zero;
    _setLyricLoadState(LyricLoadState.idle, track: track, notify: false);

    if (coverProvider != null) {
      coverManager.setCoverImmediate(coverProvider, url: track.picUrl, notify: false);
    } else {
      coverManager.updateCoverNonBlocking(
        track.picUrl,
        notify: false,
        force: true,
      );
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
      _clearPendingTrack();
      _errorMessage = null;
      final gen = ++_playGeneration;
      _duration = Duration.zero;
      _position = Duration.zero;
      positionNotifier.value = Duration.zero;
      coverManager.setCoverImmediate(null, notify: false);
      coverManager.themeColorNotifier.value = null;

      // 设置电台的 track 到队列
      _queue
        ..clear()
        ..add(radioTrack);
      _currentIndex = 0;
      _source = QueueSource.radio;

      _stagePendingTrack(radioTrack, reason: 'radio');
      notifyListeners();
      await _playWithSoftSwitch(streamUrl);
      _commitActivePresentation(radioTrack, playbackToken: gen, notify: false);
      _state = PBState.playing;
      _startListeningTimeTracking();
      notifyListeners();
    });
  }

  // ══════════════════════════════════════════════════════
  // 队列辅助
  // ══════════════════════════════════════════════════════

  String _coverKey(Track t) => _buildTrackIdentity(t);

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

  void _primeDisplayStateForTrack(Track track) {
    final existingProvider = getCoverProvider(track);
    if (existingProvider != null) {
      coverManager.setCoverImmediate(existingProvider, url: track.picUrl, notify: false);
      return;
    }
    coverManager.updateCoverNonBlocking(track.picUrl, notify: false, force: true);
  }

  Track? _trackAtQueuePointer() {
    if (_currentIndex < 0 || _currentIndex >= _queue.length) return null;
    return _queue[_currentIndex];
  }

  void _stagePendingTrack(
    Track track, {
    required String reason,
  }) {
    _pendingTrack = track;
    _pendingReason = reason;
    _pendingSwitchToken++;
  }

  void _clearPendingTrack() {
    _pendingTrack = null;
    _pendingReason = null;
  }

  void _commitActivePresentation(
    Track track, {
    SongDetail? songDetail,
    required int playbackToken,
    bool notify = true,
  }) {
    _activeTrack = track;
    _activeSong = songDetail;
    _activePlaybackToken = playbackToken;
    _clearPendingTrack();
    _preloadedTrack = null;
    _primeDisplayStateForTrack(track);
    if (notify) {
      notifyListeners();
    }
  }

  void _applyResolvedSongDetail(
    SongDetail songDetail, {
    bool notify = true,
  }) {
    _activeSong = songDetail;
    if (notify) {
      notifyListeners();
    }
  }

  TrackSwitchTransaction? _prepareTrackSwitchTransaction({
    required String reason,
  }) {
    final track = _trackAtQueuePointer() ?? _activeTrack;
    if (track == null) return null;

    _resetPreloadState(clearPrefetchedDetails: false);
    _preloadedTrack = null;
    _stagePendingTrack(track, reason: reason);
    final token = ++_playGeneration;
    final selectedQuality = AudioQualityService().currentQuality;
    final tx = TrackSwitchTransaction(
      token: token,
      pendingToken: _pendingSwitchToken,
      track: track,
      reason: reason,
      requestedKey: _buildTrackIdentity(track),
      selectedQuality: selectedQuality,
      qualityStr: selectedQuality.value,
    );

    _state = PBState.loading;
    _errorMessage = null;
    _isAudioSourceNotConfigured = false;
    notifyListeners();

    if (track.source != MusicSource.local && !AudioSourceService().isConfigured) {
      _state = PBState.error;
      _errorMessage = '音源未配置，请在设置中配置音源';
      _isAudioSourceNotConfigured = true;
      notifyListeners();
      onAudioSourceNotConfigured?.call();
      return null;
    }

    final isFromPlaylist = _source == QueueSource.playlist;
    if (isFromPlaylist && track.source == MusicSource.apple) {
      _state = PBState.error;
      _errorMessage = '由于Apple接口限制，通过该接口导入的音乐需要换源才能播放！';
      notifyListeners();
      _notifyAppleMusicRestriction(track);
      return null;
    }

    _precacheNextCover();
    if (Platform.isAndroid || Platform.isIOS) {
      WakelockPlus.enable();
    }
    PlayHistoryService().addToHistory(track);
    ListeningStatsService().recordPlayCount(track);
    return tx;
  }

  bool _isTrackSwitchTransactionStale(TrackSwitchTransaction tx) {
    final pending = _pendingTrack;
    if (tx.token != _playGeneration) return true;
    if (tx.pendingToken != _pendingSwitchToken) return true;
    return !_matchesTrackIdentity(pending, tx.requestedKey);
  }

  Future<_ResolvedTrackSwitchSong?> _resolveSongDetailStage(
    TrackSwitchTransaction tx,
    bool Function() isStale,
  ) async {
    final track = tx.track;
    _currentCachedStreamInfo = null;
    final cachePlaybackKey = _cachePlaybackKey(track, tx.qualityStr);

    final cacheInfo = _cacheBypassKeys.contains(cachePlaybackKey)
        ? null
        : await CacheService().getCyreneFileInfo(
            track,
            quality: tx.qualityStr,
          );
    if (isStale()) return null;

    final isCached = cacheInfo != null;
    final shouldRefreshCachedMetadata =
        cacheInfo != null && _needsCachedMetadataRefresh(cacheInfo.metadata);

    if (cacheInfo != null && cacheInfo.metadata.quality == tx.qualityStr) {
      return _ResolvedTrackSwitchSong(
        songDetail: _buildCachedSongDetail(
          track,
          cacheInfo.metadata,
          playbackUrl: cacheInfo.metadata.originalUrl.isNotEmpty
              ? cacheInfo.metadata.originalUrl
              : cacheInfo.filePath,
        ),
        cacheInfo: cacheInfo,
        isCached: true,
        shouldRefreshCachedMetadata: shouldRefreshCachedMetadata,
        shouldRefreshExistingCacheMetadata: false,
      );
    }

    if (cacheInfo != null && cacheInfo.metadata.quality != tx.qualityStr) {
      print(
        '[PlaybackService] 跳过缓存命中，音质不匹配: ${cacheInfo.metadata.quality} != ${tx.qualityStr}',
      );
    }

    if (track.source == MusicSource.local) {
      final filePath = track.id is String ? track.id as String : '';
      if (filePath.isEmpty || !(await File(filePath).exists())) {
        if (isStale()) return null;
        _state = PBState.error;
        _errorMessage = '本地文件不存在';
        notifyListeners();
        _autoSkipOnError();
        return null;
      }
      var lyricText = LocalLibraryService().getLyricByTrackId(filePath);
      if (lyricText.isEmpty) {
        final embedded = await MetadataReader.extractLyrics(filePath);
        if (embedded != null && embedded.isNotEmpty) lyricText = embedded;
      }
      if (isStale()) return null;
      return _ResolvedTrackSwitchSong(
        songDetail: SongDetail(
          id: filePath,
          name: track.name,
          pic: track.picUrl,
          arName: track.artists,
          alName: track.album,
          level: 'local',
          size: '',
          url: filePath,
          lyric: lyricText,
          tlyric: '',
          source: MusicSource.local,
        ),
        cacheInfo: null,
        isCached: false,
        shouldRefreshCachedMetadata: false,
        shouldRefreshExistingCacheMetadata: false,
      );
    }

    final songDetail = await _fetchSongDetailWithTimeout(
      songId: track.id,
      quality: tx.selectedQuality,
      source: track.source,
      title: track.name,
      artist: track.artists,
      timeout: _playSongDetailTimeout,
      purpose: 'playback',
      fetchLyrics: false,
    );
    if (isStale()) return null;

    if (songDetail == null || songDetail.url.isEmpty) {
      _state = PBState.error;
      _errorMessage = '无法获取播放链接';
      notifyListeners();
      _autoSkipOnError();
      return null;
    }

    final normalizedSong = _normalizeSongDetailForPlayback(track, songDetail);
    return _ResolvedTrackSwitchSong(
      songDetail: normalizedSong,
      cacheInfo: cacheInfo,
      isCached: isCached,
      shouldRefreshCachedMetadata: false,
      shouldRefreshExistingCacheMetadata:
          cacheInfo != null && _needsCachedMetadataRefresh(cacheInfo.metadata),
    );
  }

  Future<_TrackSwitchPlaybackPlan?> _resolvePlayableSourceStage(
    TrackSwitchTransaction tx,
    _ResolvedTrackSwitchSong resolvedSong,
    bool Function() isStale,
  ) async {
    final track = tx.track;
    final songDetail = resolvedSong.songDetail;
    final cacheInfo = resolvedSong.cacheInfo;

    if (cacheInfo != null && cacheInfo.metadata.quality == tx.qualityStr) {
      if (Platform.isAndroid || Platform.isIOS) {
        final playableSource = CachedCyrenePlayableSource.stream(
          cacheInfo: cacheInfo,
          playbackAudioSource: CyreneStreamSource(
            filePath: cacheInfo.filePath,
            payloadOffset: cacheInfo.payloadOffset,
            audioLength: cacheInfo.audioLength,
            contentType: cacheInfo.contentType,
          ),
        );
        return _TrackSwitchPlaybackPlan(
          resolvedSong: resolvedSong,
          usesCachedStream: true,
          source: playableSource,
          retainedTempFilePath: null,
          coverRefreshUrl: cacheInfo.metadata.picUrl,
          themeImageUrl: cacheInfo.metadata.picUrl,
          themeReason: 'cache-hit',
          shouldWriteBackgroundCache: false,
          cacheMetadataRefreshReason: null,
        );
      }

      final proxyReady = await _ensureLocalProxyRunning('cache');
      if (isStale()) return null;
      if (proxyReady) {
        final playableSource = CachedCyrenePlayableSource.proxy(
          cacheInfo: cacheInfo,
          playbackUrl: ProxyService().getCyreneStreamUrl(cacheInfo),
        );
        return _TrackSwitchPlaybackPlan(
          resolvedSong: resolvedSong,
          usesCachedStream: true,
          source: playableSource,
          retainedTempFilePath: null,
          coverRefreshUrl: cacheInfo.metadata.picUrl,
          themeImageUrl: cacheInfo.metadata.picUrl,
          themeReason: 'cache-hit',
          shouldWriteBackgroundCache: false,
          cacheMetadataRefreshReason: null,
        );
      }

      _markCachePlaybackBypassed(
        track,
        tx.qualityStr,
        reason: 'proxy-unavailable',
      );
      _logPlaybackDebug(
        '[PlaybackService] 桌面缓存命中回退网络链路: '
        '${_buildTrackIdentity(track)} quality=${tx.qualityStr}',
        toDeveloperPanel: true,
      );
    }

    if (track.source == MusicSource.local) {
      final filePath = songDetail.url;
      return _TrackSwitchPlaybackPlan(
        resolvedSong: resolvedSong,
        usesCachedStream: false,
        source: LocalFilePlayableSource(filePath),
        retainedTempFilePath: null,
        coverRefreshUrl: null,
        themeImageUrl: track.picUrl,
        themeReason: 'local-file',
        shouldWriteBackgroundCache: false,
        cacheMetadataRefreshReason: null,
      );
    }

    if (track.source == MusicSource.apple) {
      if (songDetail.url.contains('/apple/stream')) {
        final durationMs = await _getAppleStreamDuration(songDetail.url);
        if (isStale()) return null;
        if (durationMs != null && durationMs > 0) {
          _duration = Duration(milliseconds: durationMs);
        }
      }
      return _TrackSwitchPlaybackPlan(
        resolvedSong: resolvedSong,
        usesCachedStream: false,
        source: DirectHttpPlayableSource(songDetail.url),
        retainedTempFilePath: null,
        coverRefreshUrl: songDetail.pic,
        themeImageUrl: songDetail.pic,
        themeReason: 'apple-playback',
        shouldWriteBackgroundCache:
            !resolvedSong.isCached &&
            !songDetail.url.toLowerCase().contains('.m3u8'),
        cacheMetadataRefreshReason:
            resolvedSong.shouldRefreshExistingCacheMetadata
                ? 'apple-network-fallback'
                : null,
      );
    }

    if (track.source == MusicSource.qq || track.source == MusicSource.kugou) {
      final platform = track.source == MusicSource.qq ? 'qq' : 'kugou';
      final mobileDirect = Platform.isAndroid || Platform.isIOS;
      PlayableSource? source;
      String? retainedTempFilePath;

      if (mobileDirect) {
        source = DirectHttpPlayableSource(
          songDetail.url,
          requestHeaders: _buildPlaybackHeaders(track.source),
        );
      } else {
        final proxyReady = await _ensureLocalProxyRunning(platform);
        if (isStale()) return null;
        if (proxyReady) {
          source = ProxyHttpPlayableSource(
            ProxyService().getProxyUrl(songDetail.url, platform),
            originalUrl: songDetail.url,
          );
        } else {
          throw Exception('桌面代理不可用，已禁用切歌下载回退');
        }
      }

      return _TrackSwitchPlaybackPlan(
        resolvedSong: resolvedSong,
        usesCachedStream: false,
        source: source!,
        retainedTempFilePath: retainedTempFilePath,
        coverRefreshUrl: songDetail.pic,
        themeImageUrl: songDetail.pic,
        themeReason: 'network-playback',
        shouldWriteBackgroundCache:
            !resolvedSong.isCached &&
            songDetail.source != MusicSource.apple &&
            !songDetail.url.toLowerCase().contains('.m3u8'),
        cacheMetadataRefreshReason:
            resolvedSong.shouldRefreshExistingCacheMetadata
                ? 'network-fallback'
                : null,
      );
    }

    if (isStale()) return null;

    return _TrackSwitchPlaybackPlan(
      resolvedSong: resolvedSong,
      usesCachedStream: false,
      source: DirectHttpPlayableSource(songDetail.url),
      retainedTempFilePath: null,
      coverRefreshUrl: songDetail.pic,
      themeImageUrl: songDetail.pic,
      themeReason: 'network-playback',
      shouldWriteBackgroundCache:
          !resolvedSong.isCached &&
          songDetail.source != MusicSource.apple &&
          !songDetail.url.toLowerCase().contains('.m3u8'),
      cacheMetadataRefreshReason:
          resolvedSong.shouldRefreshExistingCacheMetadata
              ? 'network-fallback'
              : null,
    );
  }

  Future<_TrackSwitchPlaybackPlan?> _commitPlaybackStage(
    TrackSwitchTransaction tx,
    _TrackSwitchPlaybackPlan plan,
    bool Function() isStale,
  ) async {
    var committedPlan = plan;
    if (plan.usesCachedStream && plan.source is CachedCyrenePlayableSource) {
      final cachedSource = plan.source as CachedCyrenePlayableSource;
      final playedFromStream = await _playCachedStreamSource(cachedSource.cacheInfo);
      if (!playedFromStream) {
        if (isStale()) return null;
        final fallbackResolvedSong = await _resolveSongDetailStage(tx, isStale);
        if (fallbackResolvedSong == null || isStale()) return null;
        final fallbackPlan =
            await _resolvePlayableSourceStage(tx, fallbackResolvedSong, isStale);
        if (fallbackPlan == null || isStale()) return null;
        committedPlan = fallbackPlan;
        await _playPlayableSourceWithSoftSwitch(committedPlan.source);
      }
    } else {
      await _playPlayableSourceWithSoftSwitch(plan.source);
    }
    if (isStale()) {
      _currentCachedStreamInfo = null;
      final retainedTempFilePath = committedPlan.retainedTempFilePath;
      await _deleteTempFilePath(retainedTempFilePath);
      return null;
    }
    await _replaceCurrentTempFilePath(committedPlan.retainedTempFilePath);
    return isStale() ? null : committedPlan;
  }

  void _commitPresentationStage(
    TrackSwitchTransaction tx,
    _TrackSwitchPlaybackPlan plan,
    bool Function() isStale,
  ) {
    if (isStale()) return;

    final track = tx.track;
    final songDetail = plan.resolvedSong.songDetail;
    final initialLyricState = _deriveLyricLoadStateForPlan(
      track,
      songDetail,
      plan,
      tx.qualityStr,
    );
    _commitActivePresentation(
      track,
      songDetail: songDetail,
      playbackToken: tx.token,
    );
    LyricService().bindCurrentTrack(
      track: track,
      playbackToken: tx.token,
      song: songDetail,
      state: initialLyricState,
      notify: false,
    );
    _loadLyricsForFloatingDisplay();

    final coverRefreshUrl = plan.coverRefreshUrl;
    if (coverRefreshUrl != null && coverRefreshUrl.isNotEmpty) {
      _scheduleCoverRefresh(
        track,
        coverRefreshUrl,
        reason: plan.themeReason,
      );
    }

    if (plan.themeImageUrl.isNotEmpty) {
      _scheduleThemeColorRefresh(
        track,
        plan.themeImageUrl,
        reason: plan.themeReason,
      );
    }

    bool isPresentationStale() {
      final pending = _pendingTrack;
      if (pending != null && !_matchesTrackIdentity(pending, tx.requestedKey)) {
        return true;
      }
      if (_activePlaybackToken != tx.token) return true;
      return !_matchesTrackIdentity(_activeTrack, tx.requestedKey);
    }

    void requestLyricsForPresentation() {
      unawaited(
        LyricService().requestLyrics(
          track: track,
          playbackToken: tx.token,
          quality: tx.qualityStr,
          refreshKey: _lyricRefreshKey(track),
          adapter: _buildLyricRequestAdapter(
            track,
            quality: tx.selectedQuality,
            qualityStr: tx.qualityStr,
          ),
        ),
      );
    }

    if (plan.usesCachedStream && plan.resolvedSong.shouldRefreshCachedMetadata) {
      if (!isPresentationStale()) {
        requestLyricsForPresentation();
      }
      return;
    }

    if (plan.shouldWriteBackgroundCache) {
      _cacheSongInBackground(track, songDetail, tx.qualityStr);
      if (_shouldScheduleDeferredSupplementalRefresh(songDetail)) {
        if (!isPresentationStale()) {
          requestLyricsForPresentation();
        }
      }
      return;
    }

    if (_shouldScheduleDeferredSupplementalRefresh(songDetail)) {
      if (!isPresentationStale()) {
        requestLyricsForPresentation();
      }
      return;
    }

    final refreshReason = plan.cacheMetadataRefreshReason;
    if (plan.resolvedSong.isCached &&
        plan.resolvedSong.shouldRefreshExistingCacheMetadata &&
        refreshReason != null) {
      _refreshCachedMetadataFromResolvedSong(
        track,
        songDetail,
        tx.qualityStr,
        reason: refreshReason,
      );
    }
  }

  SongDetail _buildCachedSongDetail(
    Track track,
    CacheMetadata metadata, {
    required String playbackUrl,
  }) {
    return SongDetail(
      id: track.id,
      name: metadata.songName.isNotEmpty ? metadata.songName : track.name,
      url: playbackUrl,
      pic: metadata.picUrl,
      arName: metadata.artists,
      alName: metadata.album,
      level: metadata.quality,
      size: metadata.fileSize.toString(),
      lyric: metadata.lyric,
      tlyric: metadata.tlyric,
      yrc: metadata.yrc,
      ytlrc: metadata.ytlrc,
      qrc: metadata.qrc,
      qrcTrans: metadata.qrcTrans,
      source: track.source,
    );
  }

  SongDetail _mergeSupplementalSongDetail(
    SongDetail current,
    SongDetail supplemental,
  ) {
    return SongDetail(
      id: current.id,
      name: supplemental.name.isNotEmpty ? supplemental.name : current.name,
      pic: supplemental.pic.isNotEmpty ? supplemental.pic : current.pic,
      arName: supplemental.arName.isNotEmpty ? supplemental.arName : current.arName,
      alName: supplemental.alName.isNotEmpty ? supplemental.alName : current.alName,
      level: current.level,
      size: current.size,
      url: current.url,
      lyric: supplemental.lyric.isNotEmpty ? supplemental.lyric : current.lyric,
      tlyric: supplemental.tlyric.isNotEmpty
          ? supplemental.tlyric
          : current.tlyric,
      yrc: supplemental.yrc.isNotEmpty ? supplemental.yrc : current.yrc,
      ytlrc: supplemental.ytlrc.isNotEmpty
          ? supplemental.ytlrc
          : current.ytlrc,
      qrc: supplemental.qrc.isNotEmpty ? supplemental.qrc : current.qrc,
      qrcTrans: supplemental.qrcTrans.isNotEmpty
          ? supplemental.qrcTrans
          : current.qrcTrans,
      source: current.source,
    );
  }

  SongDetail _buildCacheRefreshSongDetail(
    SongDetail current,
    SongDetail normalizedDetail,
  ) {
    return SongDetail(
      id: current.id,
      name: normalizedDetail.name.isNotEmpty ? normalizedDetail.name : current.name,
      pic: normalizedDetail.pic.isNotEmpty ? normalizedDetail.pic : current.pic,
      arName: normalizedDetail.arName.isNotEmpty
          ? normalizedDetail.arName
          : current.arName,
      alName: normalizedDetail.alName.isNotEmpty
          ? normalizedDetail.alName
          : current.alName,
      level: current.level,
      size: current.size,
      url: normalizedDetail.url.isNotEmpty ? normalizedDetail.url : current.url,
      lyric: normalizedDetail.lyric.isNotEmpty
          ? normalizedDetail.lyric
          : current.lyric,
      tlyric: normalizedDetail.tlyric.isNotEmpty
          ? normalizedDetail.tlyric
          : current.tlyric,
      yrc: normalizedDetail.yrc.isNotEmpty ? normalizedDetail.yrc : current.yrc,
      ytlrc: normalizedDetail.ytlrc.isNotEmpty
          ? normalizedDetail.ytlrc
          : current.ytlrc,
      qrc: normalizedDetail.qrc.isNotEmpty ? normalizedDetail.qrc : current.qrc,
      qrcTrans: normalizedDetail.qrcTrans.isNotEmpty
          ? normalizedDetail.qrcTrans
          : current.qrcTrans,
      source: current.source,
    );
  }

  bool _isSameSongPresentation(SongDetail a, SongDetail b) {
    return a.name == b.name &&
        a.pic == b.pic &&
        a.arName == b.arName &&
        a.alName == b.alName &&
        a.lyric == b.lyric &&
        a.tlyric == b.tlyric &&
        a.yrc == b.yrc &&
        a.ytlrc == b.ytlrc &&
        a.qrc == b.qrc &&
        a.qrcTrans == b.qrcTrans;
  }

  bool _hasAnyLyrics(SongDetail song) {
    return song.lyric.isNotEmpty ||
        song.yrc.isNotEmpty ||
        song.qrc.isNotEmpty;
  }

  bool _hasAnyLyricPayload(SongDetail song) {
    return song.lyric.isNotEmpty ||
        song.tlyric.isNotEmpty ||
        song.yrc.isNotEmpty ||
        song.ytlrc.isNotEmpty ||
        song.qrc.isNotEmpty ||
        song.qrcTrans.isNotEmpty;
  }

  LyricRequestAdapter _buildLyricRequestAdapter(
    Track track, {
    required dynamic quality,
    required String qualityStr,
  }) {
    return LyricRequestAdapter(
      fetch: LyricRequestFetchAdapter(
        useLyricOnlyFetch: _shouldUseLyricOnlySupplementalFetch(),
        fetchLyricOnlyDetail: () {
          return MusicService()
              .fetchLyricOnlySongDetail(
                songId: track.id,
                source: track.source,
                title: track.name,
                artist: track.artists,
              )
              .timeout(
                _lyricSongDetailTimeout,
                onTimeout: () {
                _logPlaybackDebug(
                  '[PlaybackService] 纯歌词补全超时: '
                  '${_lyricRefreshKey(track)} after '
                  '${_lyricSongDetailTimeout.inSeconds}s',
                  toDeveloperPanel: true,
                );
                  return null;
                },
              );
        },
        fetchFullDetail: () => _fetchSongDetailWithTimeout(
          songId: track.id,
          source: track.source,
          quality: quality,
          title: track.name,
          artist: track.artists,
          timeout: _lyricSongDetailTimeout,
          purpose: 'lyric-service',
          fetchLyrics: true,
        ),
        normalizeSongDetail: (detail) => _normalizeSongDetailForPlayback(
          track,
          detail,
        ),
      ),
      presentation: LyricRequestPresentationAdapter(
        isSamePresentation: _isSameSongPresentation,
        currentSong: () => _activeSong,
        applyResolvedSongDetail: (detail) => _applyResolvedSongDetail(detail),
        refreshFloatingLyrics: _loadLyricsForFloatingDisplay,
      ),
      cache: LyricRequestCacheAdapter(
        mergeSupplementalSongDetail: _mergeSupplementalSongDetail,
        buildCacheRefreshSongDetail: _buildCacheRefreshSongDetail,
        cacheSongInBackground: (detail) =>
            _cacheSongInBackground(track, detail, qualityStr),
      ),
      hasAnyLyricPayload: _hasAnyLyricPayload,
      log: _logPlaybackDebug,
    );
  }

  LyricPrefetchAdapter _buildLyricPrefetchAdapter(
    Track track, {
    required String qualityStr,
  }) {
    return LyricPrefetchAdapter(
      fetchLyricOnlyDetail: () {
        return MusicService()
            .fetchLyricOnlySongDetail(
              songId: track.id,
              source: track.source,
              title: track.name,
              artist: track.artists,
            )
            .timeout(
              _lyricSongDetailTimeout,
              onTimeout: () {
                _logPlaybackDebug(
                  '[PlaybackService] 纯歌词预取超时: '
                  '${_lyricRefreshKey(track)} after '
                  '${_lyricSongDetailTimeout.inSeconds}s',
                  toDeveloperPanel: true,
                );
                return null;
              },
            );
      },
      normalizeSongDetail: (detail) => _normalizeSongDetailForPlayback(
        track,
        detail,
      ),
      hasAnyLyricPayload: _hasAnyLyricPayload,
      log: _logPlaybackDebug,
    );
  }

  bool _shouldScheduleDeferredSupplementalRefresh(SongDetail song) {
    if (song.source == MusicSource.local) return false;
    final sourceType = AudioSourceService().sourceType;
    if (sourceType != AudioSourceType.lxmusic &&
        sourceType != AudioSourceType.tunehub) {
      return false;
    }
    return song.lyric.isEmpty &&
        song.tlyric.isEmpty &&
        song.yrc.isEmpty &&
        song.ytlrc.isEmpty &&
        song.qrc.isEmpty &&
        song.qrcTrans.isEmpty;
  }

  bool _shouldUseLyricOnlySupplementalFetch() {
    final sourceType = AudioSourceService().sourceType;
    return sourceType == AudioSourceType.lxmusic ||
        sourceType == AudioSourceType.tunehub ||
        sourceType == AudioSourceType.navidrome;
  }

  bool _needsCachedMetadataRefresh(CacheMetadata metadata) {
    return metadata.songName.isEmpty ||
        metadata.artists.isEmpty ||
        metadata.album.isEmpty ||
        metadata.picUrl.isEmpty ||
        metadata.originalUrl.isEmpty ||
        (metadata.lyric.isEmpty &&
            metadata.yrc.isEmpty &&
            metadata.qrc.isEmpty);
  }

  String _trackLogKey(Track track, [String? quality]) {
    final base = _buildTrackIdentity(track);
    if (quality == null || quality.isEmpty) return base;
    return '${base}_$quality';
  }

  String _cachePlaybackKey(Track track, String quality) {
    return '${_buildTrackIdentity(track)}_$quality';
  }

  String _lyricRefreshKey(Track track) {
    return 'lyric_${_buildTrackIdentity(track)}';
  }

  String _describePlayableSource(PlayableSource source) {
    final kind = source.runtimeType.toString();
    final target = source.sourceUrl ?? source.playbackPathOrUrl ?? '<none>';
    return '$kind -> $target';
  }

  void _logPlaybackDebug(
    String message, {
    bool toDeveloperPanel = false,
  }) {
    print(message);
    if (toDeveloperPanel) {
      DeveloperModeService().addLog(message);
    }
  }

  void _setLyricLoadState(
    LyricLoadState nextState, {
    Track? track,
    bool notify = true,
    String? error,
  }) {
    final targetTrack = track ?? _activeTrack;
    if (targetTrack == null) {
      if (nextState == LyricLoadState.idle) {
        LyricService().clearCurrent(notify: notify);
      }
      return;
    }
    LyricService().syncState(
      track: targetTrack,
      playbackToken: _activePlaybackToken,
      song: _activeSong,
      state: nextState,
      error: error,
      notify: notify,
    );
  }

  LyricLoadState _deriveLyricLoadStateForPlan(
    Track track,
    SongDetail songDetail,
    _TrackSwitchPlaybackPlan plan,
    String qualityStr,
  ) {
    if (_hasAnyLyricPayload(songDetail)) {
      return LyricLoadState.ready;
    }
    return _shouldRequestLyricsForPlan(track, songDetail, plan, qualityStr)
        ? LyricLoadState.idle
        : LyricLoadState.empty;
  }

  bool _shouldRequestLyricsForPlan(
    Track track,
    SongDetail songDetail,
    _TrackSwitchPlaybackPlan plan,
    String qualityStr,
  ) {
    final lyricRefreshKey = _lyricRefreshKey(track);
    final refreshAlreadySettled = LyricService().isRefreshSettled(
      lyricRefreshKey,
    );
    return !refreshAlreadySettled &&
        ((plan.usesCachedStream &&
                plan.resolvedSong.shouldRefreshCachedMetadata) ||
            _shouldScheduleDeferredSupplementalRefresh(songDetail));
  }

  void _rememberCacheBypassKey(
    String cacheKey, {
    required String reason,
  }) {
    if (_cacheBypassKeys.remove(cacheKey)) {
      _cacheBypassKeys.add(cacheKey);
      return;
    }
    if (_cacheBypassKeys.length >= _maxCacheBypassKeys) {
      final evicted = _cacheBypassKeys.first;
      _cacheBypassKeys.remove(evicted);
      _logPlaybackDebug('[PlaybackService] 清理最旧缓存绕过标记: $evicted');
    }
    _cacheBypassKeys.add(cacheKey);
    _logPlaybackDebug(
      '[PlaybackService] 标记缓存绕过($reason): $cacheKey',
      toDeveloperPanel: true,
    );
  }

  void _markCachePlaybackBypassed(
    Track? track,
    String quality, {
    required String reason,
  }) {
    if (track == null || quality.isEmpty) return;
    _rememberCacheBypassKey(
      _cachePlaybackKey(track, quality),
      reason: reason,
    );
  }

  void _refreshCachedMetadataFromResolvedSong(
    Track track,
    SongDetail detail,
    String quality, {
    required String reason,
  }) {
    final refreshKey = _lyricRefreshKey(track);
    if (LyricService().isRefreshSettled(refreshKey)) {
      return;
    }
    _logPlaybackDebug(
      '[PlaybackService] 回写缓存元数据($reason): $refreshKey',
      toDeveloperPanel: true,
    );
    unawaited(
      _cacheSongInBackground(track, detail, quality).then((cached) {
        if (cached) {
          LyricService().markRefreshSettled(refreshKey);
        }
      }).catchError((Object e) {
        _logPlaybackDebug(
          '[PlaybackService] 回写缓存元数据失败($reason): $refreshKey, $e',
          toDeveloperPanel: true,
        );
      }),
    );
  }

  String _songDetailRequestKey({
    required dynamic songId,
    required MusicSource source,
    required dynamic quality,
    required bool fetchLyrics,
  }) {
    final lyricKey = fetchLyrics ? 'with-lyrics' : 'playback-only';
    return '${_buildTrackIdentityFromParts(source, songId)}_${quality.toString()}_$lyricKey';
  }

  Future<void> _deleteTempFilePath(String? filePath) async {
    if (filePath == null || filePath.isEmpty) return;
    try {
      final file = File(filePath);
      if (await file.exists()) {
        await file.delete();
      }
    } catch (_) {}
  }

  Future<void> _replaceCurrentTempFilePath(String? filePath) async {
    final previousPath = _currentTempFilePath;
    if (previousPath == filePath) return;
    _currentTempFilePath = filePath;
    await _deleteTempFilePath(previousPath);
  }

  void _scheduleCoverRefresh(
    Track track,
    String imageUrl, {
    required String reason,
  }) {
    if (imageUrl.isEmpty || imageUrl == track.picUrl) return;
    try {
      print(
        '[PlaybackService] 调度封面补全($reason): ${_trackLogKey(track)} -> $imageUrl',
      );
      coverManager.updateCoverNonBlocking(
        imageUrl,
        notify: true,
        force: true,
      );
    } catch (e) {
      print('[PlaybackService] 调度封面补全失败($reason): ${_trackLogKey(track)}, $e');
    }
  }

  void _scheduleThemeColorRefresh(
    Track track,
    String imageUrl, {
    required String reason,
  }) {
    if (imageUrl.isEmpty) return;
    try {
      print('[PlaybackService] 调度主题色提取($reason): ${_trackLogKey(track)}');
      coverManager.extractThemeColorNonBlocking(imageUrl);
    } catch (e) {
      print('[PlaybackService] 调度主题色提取失败($reason): ${_trackLogKey(track)}, $e');
    }
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

  Future<void> _playCurrentTrack({
    String reason = 'queue-switch',
  }) async {
    // 1. prepareTarget
    final tx = _prepareTrackSwitchTransaction(reason: reason);
    if (tx == null) return;
    final totalSw = Stopwatch()..start();

    void logTx(String message) {
      _logPlaybackDebug(
        '[PlaybackService] [TrackSwitch tx=${tx.token} pending=${tx.pendingToken} '
        'track=${tx.requestedKey} quality=${tx.qualityStr} reason=${tx.reason}] '
        '$message',
        toDeveloperPanel: true,
      );
    }

    logTx('start');

    bool isStale() {
      return _isTrackSwitchTransactionStale(tx);
    }

    try {
      final prefetchedPlan = _takePrefetchedPlayablePlan(
        tx.track,
        tx.selectedQuality,
      );
      if (prefetchedPlan != null) {
        logTx(
          'prefetch hit usesCached=${prefetchedPlan.usesCachedStream} '
          'source=${_describePlayableSource(prefetchedPlan.source)} '
          'elapsed=${totalSw.elapsedMilliseconds}ms',
        );
        final committedPlan = await _commitPlaybackStage(
          tx,
          prefetchedPlan,
          isStale,
        );
        if (committedPlan == null) return;
        logTx(
          'commitPlayback(prefetch) done source=${_describePlayableSource(committedPlan.source)} '
          'elapsed=${totalSw.elapsedMilliseconds}ms',
        );
        _commitPresentationStage(tx, committedPlan, isStale);
        logTx('commitPresentation done total=${totalSw.elapsedMilliseconds}ms');
        return;
      }

      // 2. resolveSongDetail
      final songDetailSw = Stopwatch()..start();
      final resolvedSong = await _resolveSongDetailStage(tx, isStale);
      if (resolvedSong == null || isStale()) return;
      logTx(
        'resolveSongDetail done ${songDetailSw.elapsedMilliseconds}ms '
        'isCached=${resolvedSong.isCached} '
        'refreshCachedMeta=${resolvedSong.shouldRefreshCachedMetadata} '
        'refreshExistingMeta=${resolvedSong.shouldRefreshExistingCacheMetadata} '
        'url=${resolvedSong.songDetail.url}',
      );

      // 3. resolvePlayableSource
      final sourceSw = Stopwatch()..start();
      final playbackPlan =
          await _resolvePlayableSourceStage(tx, resolvedSong, isStale);
      if (playbackPlan == null || isStale()) return;
      logTx(
        'resolvePlayableSource done ${sourceSw.elapsedMilliseconds}ms '
        'usesCached=${playbackPlan.usesCachedStream} '
        'source=${_describePlayableSource(playbackPlan.source)} '
        'shouldWriteBackgroundCache=${playbackPlan.shouldWriteBackgroundCache}',
      );

      // 4. commitPlayback
      final commitSw = Stopwatch()..start();
      final committedPlan = await _commitPlaybackStage(
        tx,
        playbackPlan,
        isStale,
      );
      if (committedPlan == null) return;
      logTx(
        'commitPlayback done ${commitSw.elapsedMilliseconds}ms '
        'source=${_describePlayableSource(committedPlan.source)}',
      );

      // 5. commitPresentation
      _commitPresentationStage(tx, committedPlan, isStale);
      logTx('commitPresentation done total=${totalSw.elapsedMilliseconds}ms');
    } on EngineReportedException {
      // 错误已通过 errorStream 进入 _onEngineError，避免重复进入 catch 路径造成连跳。
      if (isStale()) return;
      logTx('engine reported error after ${totalSw.elapsedMilliseconds}ms');
      return;
    } on AudioSourceNotConfiguredException catch (e) {
      if (isStale()) return;
      _state = PBState.error;
      _errorMessage = e.message;
      _isAudioSourceNotConfigured = true;
      notifyListeners();
      logTx(
        'audio source not configured after ${totalSw.elapsedMilliseconds}ms: ${e.message}',
      );
      onAudioSourceNotConfigured?.call();
    } catch (e) {
      if (isStale()) return;
      _state = PBState.error;
      _errorMessage = '播放失败: $e';
      _isAudioSourceNotConfigured = false;
      notifyListeners();
      logTx('failed after ${totalSw.elapsedMilliseconds}ms: $e');
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
              await _playCurrentTrack(reason: 'repeat-one-reload');
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
          await _playCurrentTrack(reason: 'auto-next-stop-mode');
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
        await _playCurrentTrack(reason: 'history-next-stop-mode');
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
          await _playCurrentTrack(reason: 'manual-next');
          return;
        }
        // 列表循环
        _currentIndex = 0;
        await _waitForTrackSwitchSettle();
        await _playCurrentTrack(reason: 'manual-next-loop');
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
        await _playCurrentTrack(reason: 'history-next');
      }
    });
  }

  Future<void> _playSequentialPrevious() async {
    return _commands.enqueue(() async {
      if (_queue.isNotEmpty) {
        final prevIdx = _currentIndex - 1;
        if (prevIdx >= 0) {
          _currentIndex = prevIdx;
          await _playCurrentTrack(reason: 'manual-previous');
          return;
        }
        // 列表循环
        _currentIndex = _queue.length - 1;
        await _playCurrentTrack(reason: 'manual-previous-loop');
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
        await _playCurrentTrack(reason: 'history-previous');
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
          await _playCurrentTrack(reason: 'history-random-next');
        }
        return;
      }
      if (_shuffledIndices.isEmpty || _shufflePosition >= _shuffledIndices.length - 1) {
        _generateShuffledIndices();
      }
      _shufflePosition++;
      _currentIndex = _shuffledIndices[_shufflePosition];
      await _waitForTrackSwitchSettle();
      await _playCurrentTrack(reason: 'shuffle-next');
    });
  }

  Future<void> _playRandomPrevious() async {
    return _commands.enqueue(() async {
      if (_queue.isEmpty || _shuffledIndices.isEmpty || _shufflePosition <= 0) return;
      _shufflePosition--;
      _currentIndex = _shuffledIndices[_shufflePosition];
      await _playCurrentTrack(reason: 'shuffle-previous');
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
      final provider = CachedNetworkImageProvider(
        url,
        headers: getImageHeaders(url),
      );
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

  void _bindPreloadDependencyListeners() {
    if (_preloadDependencyListenersBound) return;
    AudioQualityService().addListener(_handlePreloadInputsChanged);
    AudioSourceService().addListener(_handlePreloadInputsChanged);
    _preloadDependencyListenersBound = true;
  }

  void _unbindPreloadDependencyListeners() {
    if (!_preloadDependencyListenersBound) return;
    AudioQualityService().removeListener(_handlePreloadInputsChanged);
    AudioSourceService().removeListener(_handlePreloadInputsChanged);
    _preloadDependencyListenersBound = false;
  }

  void _handlePreloadInputsChanged() {
    _resetPreloadState();
    if (_state == PBState.playing) {
      _schedulePreloadNextTrack();
    }
  }

  void _cancelScheduledPreload() {
    _preloadTriggerTimer?.cancel();
    _preloadTriggerTimer = null;
  }

  void _resetPreloadState({bool clearPrefetchedDetails = true}) {
    _cancelScheduledPreload();
    _lastPreloadedTargetKey = null;
    _preloadingNext = false;
    _preloadOp++;
    if (clearPrefetchedDetails) {
      _prefetchedPlayablePlans.clear();
    }
  }

  String _buildTrackIdentityFromParts(MusicSource source, dynamic songId) {
    return '${source.name}_$songId';
  }

  String _buildTrackIdentity(Track track) {
    return _buildTrackIdentityFromParts(track.source, track.id);
  }

  bool _matchesTrackIdentity(Track? track, String trackKey) {
    return track != null && _buildTrackIdentity(track) == trackKey;
  }

  String _buildPrefetchCacheKey(Track track, AudioQuality quality) {
    return '${_buildTrackIdentity(track)}_${quality.toString()}';
  }

  void _pruneExpiredPrefetchedPlayablePlans() {
    _prefetchedPlayablePlans.removeWhere(
      (_, entry) => entry.isExpired,
    );
  }

  _TrackSwitchPlaybackPlan? _takePrefetchedPlayablePlan(
    Track track,
    AudioQuality quality,
  ) {
    _pruneExpiredPrefetchedPlayablePlans();
    final key = _buildPrefetchCacheKey(track, quality);
    final entry = _prefetchedPlayablePlans.remove(key);
    if (entry == null || entry.isExpired) {
      return null;
    }
    return entry.plan;
  }

  void _savePrefetchedPlayablePlan(
    Track track,
    AudioQuality quality,
    _TrackSwitchPlaybackPlan plan,
  ) {
    _pruneExpiredPrefetchedPlayablePlans();
    final key = _buildPrefetchCacheKey(track, quality);
    _prefetchedPlayablePlans[key] = _PrefetchedPlayablePlanEntry(
      plan: plan,
      expiresAt: DateTime.now().add(_prefetchedSongDetailTtl),
    );
    if (_prefetchedPlayablePlans.length > _maxPrefetchedPlayableDetails) {
      final oldestKey = _prefetchedPlayablePlans.keys.first;
      _prefetchedPlayablePlans.remove(oldestKey);
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
        yrc: normalized.yrc,
        ytlrc: normalized.ytlrc,
        qrc: normalized.qrc,
        qrcTrans: normalized.qrcTrans,
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
        yrc: normalized.yrc,
        ytlrc: normalized.ytlrc,
        qrc: normalized.qrc,
        qrcTrans: normalized.qrcTrans,
        source: normalized.source,
      );
    }

    return normalized;
  }

  Future<SongDetail?> _fetchSongDetailWithTimeout({
    required dynamic songId,
    required dynamic quality,
    required MusicSource source,
    required String title,
    required String artist,
    required Duration timeout,
    required String purpose,
    bool fetchLyrics = true,
  }) async {
    final requestKey = _songDetailRequestKey(
      songId: songId,
      source: source,
      quality: quality,
      fetchLyrics: fetchLyrics,
    );
    final request = _acquireSongDetailRequest(
      requestKey: requestKey,
      songId: songId,
      quality: quality,
      source: source,
      title: title,
      artist: artist,
      purpose: purpose,
      fetchLyrics: fetchLyrics,
    );

    try {
      return await request
          .timeout(
            timeout,
            onTimeout: () {
              print(
                '[PlaybackService] 获取歌曲详情超时($purpose): '
                '$requestKey after ${timeout.inSeconds}s',
              );
              return null;
            },
          );
    } on AudioSourceNotConfiguredException {
      rethrow;
    } catch (e) {
      print(
        '[PlaybackService] 获取歌曲详情失败($purpose): '
        '$requestKey, $e',
      );
      return null;
    }
  }

  Future<SongDetail?> _acquireSongDetailRequest({
    required String requestKey,
    required dynamic songId,
    required dynamic quality,
    required MusicSource source,
    required String title,
    required String artist,
    required String purpose,
    required bool fetchLyrics,
  }) {
    final existing = _pendingSongDetailRequests[requestKey];
    if (existing != null) {
      if (existing.isReusable) {
        print('[PlaybackService] 复用进行中的歌曲详情请求($purpose): $requestKey');
        return existing.future;
      }
      if (existing.state == _SongDetailRequestState.running) {
        existing.markExpired();
      }
      print(
        '[PlaybackService] 丢弃不可复用的歌曲详情请求($purpose): '
        '$requestKey, state=${existing.state}',
      );
      if (identical(_pendingSongDetailRequests[requestKey], existing)) {
        _pendingSongDetailRequests.remove(requestKey);
      }
    }

    final startedAt = DateTime.now();
    final hardDeadline = startedAt.add(_songDetailRequestHardTimeout);
    final completer = Completer<SongDetail?>();
    late final _SongDetailRequestEntry entry;
    entry = _SongDetailRequestEntry(
      key: requestKey,
      startedAt: startedAt,
      hardDeadline: hardDeadline,
      future: completer.future,
    );
    _pendingSongDetailRequests[requestKey] = entry;

    unawaited(() async {
      var timedOut = false;
      try {
        final detail = await MusicService()
            .fetchSongDetail(
              songId: songId,
              quality: quality,
              source: source,
              title: title,
              artist: artist,
              fetchLyrics: fetchLyrics,
            )
            .timeout(
              _songDetailRequestHardTimeout,
              onTimeout: () {
                timedOut = true;
                print(
                  '[PlaybackService] 歌曲详情共享请求硬超时: '
                  '$requestKey after ${_songDetailRequestHardTimeout.inSeconds}s',
                );
                return null;
              },
            );
        if (timedOut) {
          entry.markExpired();
        } else {
          entry.markCompleted();
        }
        if (!completer.isCompleted) {
          completer.complete(detail);
        }
      } on AudioSourceNotConfiguredException catch (e, st) {
        entry.markFailed();
        if (!completer.isCompleted) {
          completer.completeError(e, st);
        }
      } catch (e, st) {
        entry.markFailed();
        if (!completer.isCompleted) {
          completer.completeError(e, st);
        }
      } finally {
        if (identical(_pendingSongDetailRequests[requestKey], entry)) {
          _pendingSongDetailRequests.remove(requestKey);
        }
      }
    }());

    return entry.future;
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
    await _performSoftSwitch(
      () => _engine.play(url, isLocal: isLocal, headers: headers),
    );
  }

  Future<void> _playPlayableSourceWithSoftSwitch(PlayableSource source) async {
    await _performSoftSwitch(() => _engine.playSource(source));
  }

  Future<void> _playAudioSourceWithSoftSwitch(
    ja.AudioSource source, {
    String? sourceUrl,
  }) async {
    await _performSoftSwitch(
      () => _engine.playAudioSource(source, sourceUrl: sourceUrl),
    );
  }

  Future<void> _performSoftSwitch(
    Future<void> Function() startPlayback,
  ) async {
    final targetVolume = _volume.clamp(0.0, 1.0);
    final canFade = _engine.isPlaying && targetVolume > 0;
    final fadeGeneration = _playGeneration;

    if (!canFade) {
      await startPlayback();
      await _safeSetEngineVolume(targetVolume);
      return;
    }

    final stepVolume = targetVolume / _switchFadeSteps;
    for (int i = _switchFadeSteps; i > 0; i--) {
      await _safeSetEngineVolume(stepVolume * (i - 1));
      await Future.delayed(_switchFadeStepDelay);
    }

    try {
      await startPlayback();
    } catch (e) {
      await _safeSetEngineVolume(targetVolume);
      rethrow;
    }

    unawaited(_fadeInAfterSwitch(stepVolume, fadeGeneration));
  }

  Future<void> _fadeInAfterSwitch(double stepVolume, int fadeGeneration) async {
    for (int i = 1; i <= _switchFadeSteps; i++) {
      if (fadeGeneration != _playGeneration) return;
      await _safeSetEngineVolume(stepVolume * i);
      await Future.delayed(_switchFadeStepDelay);
    }
  }

  void _schedulePreloadNextTrack() {
    if (_state != PBState.playing) return;
    final current = currentTrack;
    if (current == null) return;

    final scheduledTrackKey = _buildTrackIdentity(current);
    final scheduledOp = _preloadOp;
    _cancelScheduledPreload();
    _preloadTriggerTimer = Timer(_preloadTriggerDelay, () {
      _preloadTriggerTimer = null;
      final playingTrack = currentTrack;
      if (scheduledOp != _preloadOp ||
          _state != PBState.playing ||
          playingTrack == null ||
          _buildTrackIdentity(playingTrack) != scheduledTrackKey) {
        return;
      }
      unawaited(_preloadNextTrack());
    });
  }

  Future<void> _preloadNextTrack() async {
    if (_preloadingNext) return;
    final nextTrack = peekNext(PlaybackModeService().currentMode);
    final current = currentTrack;
    if (nextTrack == null || current == null) return;

    final selectedQuality = AudioQualityService().currentQuality;
    final nextIdentity = _buildTrackIdentity(nextTrack);
    final nextKey = _buildPrefetchCacheKey(nextTrack, selectedQuality);
    final currentIdentity = _buildTrackIdentity(current);
    if (nextTrack.source != MusicSource.local) {
      unawaited(
        LyricService().prefetchLyrics(
          track: nextTrack,
          quality: selectedQuality.value,
          refreshKey: _lyricRefreshKey(nextTrack),
          adapter: _buildLyricPrefetchAdapter(
            nextTrack,
            qualityStr: selectedQuality.value,
          ),
        ),
      );
    }

    if (nextIdentity == currentIdentity || nextKey == _lastPreloadedTargetKey) {
      return;
    }
    if (nextTrack.source != MusicSource.local && !AudioSourceService().isConfigured) {
      return;
    }

    _preloadingNext = true;
    final op = ++_preloadOp;
    try {
      await _preloadTrackSource(nextTrack, selectedQuality, op);
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
    final song = _activeSong;
    if (track == null || song == null || song.url.isEmpty) return false;

    final cachedStreamInfo = _currentCachedStreamInfo;
    if (cachedStreamInfo != null) {
      final replayedFromCache = await _playCachedStreamSource(cachedStreamInfo);
      if (replayedFromCache) {
        return true;
      }
    }

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

  Future<bool> _playCachedStreamSource(CyreneFileInfo cacheInfo) async {
    try {
      final track = _pendingTrack ?? currentTrack;
      final sw = Stopwatch()..start();
      late final PlayableSource source;
      if (Platform.isAndroid || Platform.isIOS) {
        source = CachedCyrenePlayableSource.stream(
          cacheInfo: cacheInfo,
          playbackAudioSource: CyreneStreamSource(
            filePath: cacheInfo.filePath,
            payloadOffset: cacheInfo.payloadOffset,
            audioLength: cacheInfo.audioLength,
            contentType: cacheInfo.contentType,
          ),
        );
      } else {
        final proxyReady = await _ensureLocalProxyRunning('cache');
        if (!proxyReady) {
          _markCachePlaybackBypassed(
            track,
            cacheInfo.metadata.quality,
            reason: 'proxy-unavailable',
          );
          print(
            '[PlaybackService] 缓存流式播放跳过: 本地缓存代理不可用 '
            'track=${track != null ? _buildTrackIdentity(track) : '<unknown>'} '
            'quality=${cacheInfo.metadata.quality}',
          );
          return false;
        }
        source = CachedCyrenePlayableSource.proxy(
          cacheInfo: cacheInfo,
          playbackUrl: ProxyService().getCyreneStreamUrl(cacheInfo),
        );
      }

      await _playPlayableSourceWithSoftSwitch(source);
      print(
        '[PlaybackService] 缓存流式播放已提交 ${sw.elapsedMilliseconds}ms '
        'source=${_describePlayableSource(source)}',
      );

      _currentCachedStreamInfo = cacheInfo;
      if (track != null) {
        _cacheBypassKeys.remove(
          _cachePlaybackKey(track, cacheInfo.metadata.quality),
        );
      }
      await _replaceCurrentTempFilePath(null);
      return true;
    } catch (e) {
      print('[PlaybackService] 缓存流式播放失败，回退网络链路: $e');
      _markCachePlaybackBypassed(
        _pendingTrack ?? currentTrack,
        cacheInfo.metadata.quality,
        reason: 'stream-start-failed',
      );
      _currentCachedStreamInfo = null;
      return false;
    }
  }

  Future<_TrackSwitchPlaybackPlan?> _buildPrefetchedPlayablePlan(
    Track track,
    AudioQuality selectedQuality,
  ) async {
    final qualityStr = selectedQuality.value;
    final cacheInfo = _cacheBypassKeys.contains(_cachePlaybackKey(track, qualityStr))
        ? null
        : await CacheService().getCyreneFileInfo(
            track,
            quality: qualityStr,
          );

    if (cacheInfo != null && cacheInfo.metadata.quality == qualityStr) {
      final cachedSong = _buildCachedSongDetail(
        track,
        cacheInfo.metadata,
        playbackUrl: cacheInfo.metadata.originalUrl.isNotEmpty
            ? cacheInfo.metadata.originalUrl
            : cacheInfo.filePath,
      );
      final CachedCyrenePlayableSource? cachedSource;
      if (Platform.isAndroid || Platform.isIOS) {
        cachedSource = CachedCyrenePlayableSource.stream(
          cacheInfo: cacheInfo,
          playbackAudioSource: CyreneStreamSource(
            filePath: cacheInfo.filePath,
            payloadOffset: cacheInfo.payloadOffset,
            audioLength: cacheInfo.audioLength,
            contentType: cacheInfo.contentType,
          ),
        );
      } else {
        final proxyReady = await _ensureLocalProxyRunning('cache');
        if (!proxyReady) {
          _logPlaybackDebug(
            '[PlaybackService] 跳过缓存预取: 本地缓存代理不可用 '
            'track=${_buildTrackIdentity(track)} quality=$qualityStr',
            toDeveloperPanel: true,
          );
          return null;
        }
        cachedSource = CachedCyrenePlayableSource.proxy(
          cacheInfo: cacheInfo,
          playbackUrl: ProxyService().getCyreneStreamUrl(cacheInfo),
        );
      }
      return _TrackSwitchPlaybackPlan(
        resolvedSong: _ResolvedTrackSwitchSong(
          songDetail: cachedSong,
          cacheInfo: cacheInfo,
          isCached: true,
          shouldRefreshCachedMetadata:
              _needsCachedMetadataRefresh(cacheInfo.metadata),
          shouldRefreshExistingCacheMetadata: false,
        ),
        usesCachedStream: true,
        source: cachedSource,
        retainedTempFilePath: null,
        coverRefreshUrl: cacheInfo.metadata.picUrl,
        themeImageUrl: cacheInfo.metadata.picUrl,
        themeReason: 'cache-hit',
        shouldWriteBackgroundCache: false,
        cacheMetadataRefreshReason: null,
      );
    }

    if (track.source == MusicSource.local) {
      return null;
    }

    var detail = await _fetchSongDetailWithTimeout(
      songId: track.id,
      quality: selectedQuality,
      source: track.source,
      title: track.name,
      artist: track.artists,
      timeout: _preloadSongDetailTimeout,
      purpose: 'preload',
      fetchLyrics: false,
    );
    if (detail == null || detail.url.isEmpty) return null;

    detail = _normalizeSongDetailForPlayback(track, detail);
    final resolvedSong = _ResolvedTrackSwitchSong(
      songDetail: detail,
      cacheInfo: cacheInfo,
      isCached: cacheInfo != null,
      shouldRefreshCachedMetadata: false,
      shouldRefreshExistingCacheMetadata:
          cacheInfo != null && _needsCachedMetadataRefresh(cacheInfo.metadata),
    );

    if (track.source == MusicSource.apple) {
      return _TrackSwitchPlaybackPlan(
        resolvedSong: resolvedSong,
        usesCachedStream: false,
        source: DirectHttpPlayableSource(detail.url),
        retainedTempFilePath: null,
        coverRefreshUrl: detail.pic,
        themeImageUrl: detail.pic,
        themeReason: 'apple-playback',
        shouldWriteBackgroundCache:
            !resolvedSong.isCached && !detail.url.toLowerCase().contains('.m3u8'),
        cacheMetadataRefreshReason:
            resolvedSong.shouldRefreshExistingCacheMetadata
                ? 'apple-network-fallback'
                : null,
      );
    }

    if (track.source == MusicSource.qq || track.source == MusicSource.kugou) {
      if (Platform.isAndroid || Platform.isIOS) {
        return _TrackSwitchPlaybackPlan(
          resolvedSong: resolvedSong,
          usesCachedStream: false,
          source: DirectHttpPlayableSource(
            detail.url,
            requestHeaders: _buildPlaybackHeaders(track.source),
          ),
          retainedTempFilePath: null,
          coverRefreshUrl: detail.pic,
          themeImageUrl: detail.pic,
          themeReason: 'network-playback',
          shouldWriteBackgroundCache:
              !resolvedSong.isCached && !detail.url.toLowerCase().contains('.m3u8'),
          cacheMetadataRefreshReason:
              resolvedSong.shouldRefreshExistingCacheMetadata
                  ? 'network-fallback'
                  : null,
        );
      }

      final platform = track.source == MusicSource.qq ? 'qq' : 'kugou';
      final proxyReady = await _ensureLocalProxyRunning(platform);
      if (!proxyReady) return null;
      return _TrackSwitchPlaybackPlan(
        resolvedSong: resolvedSong,
        usesCachedStream: false,
        source: ProxyHttpPlayableSource(
          ProxyService().getProxyUrl(detail.url, platform),
          originalUrl: detail.url,
        ),
        retainedTempFilePath: null,
        coverRefreshUrl: detail.pic,
        themeImageUrl: detail.pic,
        themeReason: 'network-playback',
        shouldWriteBackgroundCache:
            !resolvedSong.isCached && !detail.url.toLowerCase().contains('.m3u8'),
        cacheMetadataRefreshReason:
            resolvedSong.shouldRefreshExistingCacheMetadata
                ? 'network-fallback'
                : null,
      );
    }

    return _TrackSwitchPlaybackPlan(
      resolvedSong: resolvedSong,
      usesCachedStream: false,
      source: DirectHttpPlayableSource(detail.url),
      retainedTempFilePath: null,
      coverRefreshUrl: detail.pic,
      themeImageUrl: detail.pic,
      themeReason: 'network-playback',
      shouldWriteBackgroundCache:
          !resolvedSong.isCached && !detail.url.toLowerCase().contains('.m3u8'),
      cacheMetadataRefreshReason:
          resolvedSong.shouldRefreshExistingCacheMetadata
              ? 'network-fallback'
              : null,
    );
  }

  Future<void> _preloadTrackSource(
    Track track,
    AudioQuality selectedQuality,
    int op,
  ) async {
    final plan = await _buildPrefetchedPlayablePlan(track, selectedQuality);
    if (op != _preloadOp || plan == null) return;
    _savePrefetchedPlayablePlan(track, selectedQuality, plan);
  }

  Map<String, String> _buildPlaybackHeaders(MusicSource source) {
    return buildAudioRequestHeaders(source);
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

  Future<String?> _downloadSongToTempFile(
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

  Future<String?> _downloadAndPlay(
    SongDetail songDetail, {
    Map<String, String>? headers,
  }) async {
    final path = await _downloadSongToTempFile(songDetail, headers: headers);
    if (path == null) return null;
    await _playWithSoftSwitch(path, isLocal: true);
    return path;
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

  Future<bool> _cacheSongInBackground(Track track, SongDetail detail, String quality) async {
    final key = _trackLogKey(track, quality);
    try {
      _logPlaybackDebug(
        '[PlaybackService] 后台缓存请求: $key url=${detail.url} '
        'source=${track.source.name}',
        toDeveloperPanel: true,
      );
      final cached = await CacheService().cacheSong(track, detail, quality);
      if (!cached) {
        _logPlaybackDebug(
          '[PlaybackService] 后台缓存未写入: $key',
          toDeveloperPanel: true,
        );
      } else {
        _logPlaybackDebug(
          '[PlaybackService] 后台缓存写入成功: $key',
          toDeveloperPanel: true,
        );
      }
      return cached;
    } catch (e) {
      _logPlaybackDebug(
        '[PlaybackService] 后台缓存失败: $key, $e',
        toDeveloperPanel: true,
      );
      return false;
    }
  }

  Future<void> _cleanupCurrentTempFile() async {
    _currentCachedStreamInfo = null;
    if (_currentTempFilePath != null) {
      try {
        final f = File(_currentTempFilePath!);
        if (await f.exists()) await f.delete();
      } catch (_) {} finally {
        _currentTempFilePath = null;
      }
    }
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

  /// 立即持久化当前播放会话（跳过防抖），用于生命周期关键时刻。
  Future<void> persistSessionImmediately() async {
    _sessionPersistDebounce?.cancel();
    await _persistSessionNow();
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

  void _clearFloatingLyricsDisplay() {
    _lyrics = [];
    _currentLyricIndex = -1;
    if (Platform.isWindows && DesktopLyricService().isVisible) {
      DesktopLyricService().setLyricText('');
      DesktopLyricService().setTranslationText('');
    }
    if (Platform.isAndroid && AndroidFloatingLyricService().isVisible) {
      AndroidFloatingLyricService().setLyricText('');
      AndroidFloatingLyricService().setLyricsData([]);
    }
  }

  void _loadLyricsForFloatingDisplay() {
    final snapshot = LyricService().currentSnapshot;
    final song = _activeSong;
    final track = currentTrack;
    final coverUrl = song != null && song.pic.isNotEmpty
        ? song.pic
        : (track?.picUrl ?? '');

    if (Platform.isWindows && DesktopLyricService().isVisible && track != null) {
      DesktopLyricService().setSongInfo(
        title: song?.name.isNotEmpty == true ? song!.name : track.name,
        artist: song?.arName.isNotEmpty == true ? song!.arName : track.artists,
        albumCover: coverUrl,
      );
    }

    if (snapshot == null || snapshot.lines.isEmpty) {
      _clearFloatingLyricsDisplay();
      return;
    }

    try {
      _lyrics = List<LyricLine>.from(snapshot.lines);
      _currentLyricIndex = -1;
      if (_lyrics.isEmpty) {
        _clearFloatingLyricsDisplay();
        return;
      }

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
      _clearFloatingLyricsDisplay();
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
    _activeTrack = null;
    _activeSong = null;
    _queue.clear();
    _currentIndex = -1;
    _source = QueueSource.none;
    _preloadedTrack = null;
    _clearPendingTrack();
    _position = Duration.zero;
    _duration = Duration.zero;
    _bufferedPosition = Duration.zero;
    _errorMessage = null;
    _currentCachedStreamInfo = null;
    _cacheBypassKeys.clear();
    _pendingSongDetailRequests.clear();
    LyricService().clearAll(notify: false);
    positionNotifier.value = Duration.zero;
    bufferedPositionNotifier.value = Duration.zero;
    coverManager.setCoverImmediate(null, notify: false);
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
      _resetPreloadState();
      await _cleanupCurrentTempFile();
      await CacheService().cleanTempFiles();
      await ProxyService().stop();
      _state = PBState.idle;
      _activeTrack = null;
      _activeSong = null;
      _preloadedTrack = null;
      _clearPendingTrack();
      _position = Duration.zero;
      _duration = Duration.zero;
      _bufferedPosition = Duration.zero;
      _currentCachedStreamInfo = null;
      _cacheBypassKeys.clear();
      _pendingSongDetailRequests.clear();
      LyricService().clearAll(notify: false);
      coverManager.setCoverImmediate(null, notify: false);
      _sessionPersistDebounce?.cancel();
      await _engine.dispose();
    } catch (e) {
      print('[PlaybackService] 释放资源失败: $e');
    }
  }

  @override
  void dispose() {
    _resetPreloadState();
    _unbindPreloadDependencyListeners();
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
