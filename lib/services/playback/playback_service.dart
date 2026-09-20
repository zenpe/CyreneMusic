import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:http/http.dart' as http;
import 'package:wakelock_plus/wakelock_plus.dart';

import '../../models/track.dart';
import '../../models/song_detail.dart';
import '../../models/lyric_line.dart';
import '../../utils/lyric_parser.dart';
import '../../utils/toast_utils.dart';
import '../../utils/image_utils.dart';
import '../../utils/audio_request_headers.dart';
import '../music_service.dart';
import '../audio_source_service.dart';
import '../cache_service.dart';
import '../proxy_service.dart';
import '../play_history_service.dart';
import '../playback_mode_service.dart';
import '../audio_quality_service.dart';
import '../developer_mode_service.dart';
import '../desktop_lyric_service.dart';
import '../android_floating_lyric_service.dart';
import '../player_background_service.dart';
import '../url_service.dart';
import '../notification_service.dart';
import '../persistent_storage_service.dart';
import '../equalizer_service.dart';
import '../lyric/lyric_service.dart';
import '../lyric/lyric_snapshot.dart';
import '../lx_runtime_interface.dart';
import '../structured_log_service.dart';

import 'command_queue.dart';
import 'audio_engine.dart';
import 'engine_host.dart';
import 'engine_event.dart';
import 'cover_manager.dart';
import 'cyrene_stream_source.dart';
import 'playback_session_snapshot.dart';
import 'playback_session_manager.dart';
import 'playback_problem.dart';
import 'playback_stability_tracker.dart';
import 'playback_failure_policy.dart';
import 'playback_transaction.dart';
import 'playback_history_recorder.dart';
import 'playback_request_router.dart';
import 'playback_session.dart';
import 'queue_controller.dart';
import 'playable_source.dart';
import 'source_health_tracker.dart';
import 'track_resolver.dart';

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

class TrackSwitchTransaction {
  final int token;
  final int pendingToken;
  final int requestEpoch;
  final PlaybackSession session;
  final Track track;
  final String reason;
  final String requestedKey;
  final AudioQuality selectedQuality;
  final String qualityStr;
  final PlaybackRequestIntent intent;
  final bool forceRemoteResolution;

  const TrackSwitchTransaction({
    required this.token,
    required this.pendingToken,
    this.requestEpoch = 0,
    required this.session,
    required this.track,
    required this.reason,
    required this.requestedKey,
    required this.selectedQuality,
    required this.qualityStr,
    required this.intent,
    this.forceRemoteResolution = false,
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

/// 播放协调器及兼容服务
///
/// 保留原有公共 API，具体领域状态委托给 QueueController、TrackResolver、
/// PlaybackHistoryRecorder 和 PlaybackSessionManager。
/// 主播放器展示态与队列指针解耦：
/// `currentTrack/currentSong/display*` 只读取 active*，
/// `_currentIndex` 只表示队列当前指针，pending* 表示待切换目标。
class PlaybackService extends ChangeNotifier {
  static final PlaybackService _instance = PlaybackService._internal();
  factory PlaybackService() => _instance;

  // ══════════════════════════════════════════════════════
  // 队列状态（原 PlaylistQueueService）
  // ══════════════════════════════════════════════════════
  final QueueController _queueController = QueueController();
  List<Track> get _queue => _queueController.tracks;
  int get _currentIndex => _queueController.currentIndex;
  QueueSource get _source => _queueController.source;

  final Random _random = Random();

  // ══════════════════════════════════════════════════════
  // 组合
  // ══════════════════════════════════════════════════════
  final CommandQueue _commands = CommandQueue();
  final PlaybackRequestRouter _requestRouter = PlaybackRequestRouter();
  late final EngineHost _engine;
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
  PlaybackRequestIntent? _pendingIntent;
  PlaybackRequestIntent _activeIntent = PlaybackRequestIntent.manual;
  int _pendingSwitchToken = 0;
  String? _pendingReason;
  int _consecutiveErrors = 0;
  int _detachedSwitchSeq = 0;
  Duration _duration = Duration.zero;
  Duration _position = Duration.zero;
  Duration _bufferedPosition = Duration.zero;
  String? _errorMessage;
  String? _currentTempFilePath;
  CyreneFileInfo? _currentCachedStreamInfo;
  final Set<String> _cacheBypassKeys = <String>{};
  final PlaybackProblemStore _problemStore = PlaybackProblemStore();
  final PlaybackFailurePolicy _failurePolicy = const PlaybackFailurePolicy();
  final PlaybackTransactionGuard _transactionGuard = PlaybackTransactionGuard();
  final PlaybackHistoryRecorder _historyRecorder = PlaybackHistoryRecorder();
  late final PlaybackSessionManager _sessionManager;
  final SourceHealthTracker _sourceHealthTracker = SourceHealthTracker();
  final TrackResolver _trackResolver = TrackResolver();

  /// 播放稳定性判定：playing 持续满阈值且进度前进才算播放成功。
  /// 门控失败计数清零、历史记录、预载等成功副作用，避免"播 1s 失败
  /// 但计数被清零"的连跳循环。
  late final PlaybackStabilityTracker _stabilityTracker;
  PlaybackSession? _currentSession;
  Track? _stableCacheTrack;
  SongDetail? _stableCacheSong;
  String? _stableCacheQuality;
  double _volume = 0.7;
  double _playbackSpeed = 1.0;
  bool _isAudioSourceNotConfigured = false;
  String? _retriedTrackKey;
  String? _lastPreloadedTargetKey;
  bool _preloadingNext = false;
  int _preloadOp = 0;
  final Map<String, _PrefetchedPlayablePlanEntry> _prefetchedPlayablePlans = {};
  Timer? _preloadTriggerTimer;
  Timer? _autoSkipTimer;
  bool _preloadDependencyListenersBound = false;

  static const int _switchFadeSteps = 8;
  static const Duration _switchFadeStepDelay = Duration(milliseconds: 15);
  static const Duration _trackSwitchSettleDelay = Duration(milliseconds: 80);
  static const Duration _preloadTriggerDelay = Duration(seconds: 3);
  static const Duration _prefetchedSongDetailTtl = Duration(minutes: 5);
  static const Duration _playSongDetailTimeout = Duration(seconds: 12);
  static const Duration _preloadSongDetailTimeout = Duration(seconds: 8);
  static const Duration _lyricSongDetailTimeout = Duration(seconds: 6);
  static const int _maxPrefetchedPlayableDetails = 4;
  static const int _maxCacheBypassKeys = 64;

  // 高频进度更新（解耦 ChangeNotifier，避免重建 widget 树）
  final ValueNotifier<Duration> positionNotifier = ValueNotifier(Duration.zero);
  final ValueNotifier<Duration> bufferedPositionNotifier = ValueNotifier(
    Duration.zero,
  );
  final ValueNotifier<PlaybackProblem?> problemNotifier = ValueNotifier(null);
  final ValueNotifier<SourceHealthSnapshot?> sourceHealthNotifier =
      ValueNotifier(null);

  // 播放状态保存
  Duration? _pendingRestorePosition;
  bool _hasRestoredSessionOnStartup = false;

  // 桌面/悬浮歌词
  List<LyricLine> _lyrics = [];
  int _currentLyricIndex = -1;
  DateTime _lastNativeSyncTime = DateTime.fromMillisecondsSinceEpoch(0);

  // 音源配置回调
  void Function()? onAudioSourceNotConfigured;
  void Function(PlaybackProblem problem)? onPlaybackFailure;

  // ══════════════════════════════════════════════════════
  // 派生属性
  // ══════════════════════════════════════════════════════
  Track? get activeTrack => _activeTrack;
  SongDetail? get activeSong => _activeSong;
  int get activePlaybackToken => _activePlaybackToken;
  PlaybackSession? get currentSession => _currentSession;
  Track? get pendingTrack => _pendingTrack;
  int? get pendingSwitchToken =>
      _pendingTrack == null ? null : _pendingSwitchToken;
  String? get pendingReason => _pendingReason;

  Track? get currentTrack => _activeTrack;

  List<Track> get queue => _queueController.tracks;
  int get currentIndex => _queueController.currentIndex;
  QueueSource get source => _queueController.source;
  bool get hasQueue => _queueController.isNotEmpty;
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
  PlaybackProblem? get currentProblem => problemNotifier.value;
  bool isCurrentPlaybackProblem(PlaybackProblem problem) {
    final current = _problemStore.current;
    return current?.id == problem.id &&
        current?.transactionId == problem.transactionId &&
        _playGeneration == problem.transactionId;
  }

  SourceHealthSnapshot? get sourceHealth => sourceHealthNotifier.value;
  int get _playGeneration => _transactionGuard.currentToken;
  double get volume => _volume;
  double get playbackSpeed => _playbackSpeed;
  bool get isAudioSourceNotConfigured => _isAudioSourceNotConfigured;

  bool get hasNext {
    if (_queueController.isNotEmpty) return _queueController.hasNext;
    return PlayHistoryService().history.length >= 2;
  }

  bool get hasPrevious {
    if (_queueController.isNotEmpty) return _queueController.hasPrevious;
    return PlayHistoryService().history.length >= 3;
  }

  // 预载轨道（用于启动时显示 MiniPlayer）
  Track? _preloadedTrack;

  // 均衡器 — 委托给 EqualizerService
  static List<int> get kEqualizerFrequencies =>
      EqualizerService.kEqualizerFrequencies;
  List<double> get equalizerGains => EqualizerService().equalizerGains;
  bool get equalizerEnabled => EqualizerService().equalizerEnabled;
  bool get isEqualizerAvailable => EqualizerService().isEqualizerAvailable;

  // ══════════════════════════════════════════════════════
  // 初始化
  // ══════════════════════════════════════════════════════
  PlaybackService._internal() {
    _sessionManager = PlaybackSessionManager(
      snapshotBuilder: _buildSessionSnapshot,
    );
    _engine = EngineHost();
    _stabilityTracker = PlaybackStabilityTracker(
      isPlaying: () => _state == PBState.playing,
      position: () => _position,
    );
    _stabilityTracker.onStable = _onStablePlayback;

    // 监听引擎状态
    // 所有引擎事件统一从带 epoch 的协议进入协调器；不再分别订阅裸的
    // position/state/error stream，避免其中一条漏掉会话归属校验。
    _engineSubs.add(_engine.events.listen(_onEngineEvent));
    AudioSourceService().addListener(_syncActiveSourceHealth);
    _syncActiveSourceHealth();
  }

  void _onEngineEvent(EngineEvent event) {
    if (event.epoch != _playGeneration) {
      if (event is EngineFailureEvent) {
        print('[PlaybackService] 丢弃旧纪元引擎事件: ${event.error}');
      }
      return;
    }
    switch (event) {
      case EngineStateEvent(:final state):
        _onEngineStateChanged(state);
      case EnginePositionEvent(:final position):
        _onPositionChanged(position);
      case EngineDurationEvent(:final duration):
        _onDurationChanged(duration);
      case EngineBufferedPositionEvent(:final position):
        _onBufferedPositionChanged(position);
      case EngineCompletedEvent():
        _onCompletion(true);
      case EngineFailureEvent(:final error):
        _onEngineError(error);
    }
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

  Future<bool> restoreSessionOnStartup({
    required bool autoPlay,
    Future<void> Function()? beforeDeferredAutoPlay,
  }) async {
    if (_hasRestoredSessionOnStartup) return currentTrack != null;
    _hasRestoredSessionOnStartup = true;

    try {
      final snapshot = await _sessionManager.load();
      if (snapshot == null || !snapshot.isValid) return false;

      await _restoreFromSnapshot(
        snapshot,
        autoPlay: autoPlay,
        beforeDeferredAutoPlay: beforeDeferredAutoPlay,
      );
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
    Future<void> Function()? beforeDeferredAutoPlay,
  }) async {
    final restorePosition = snapshot.position > Duration.zero
        ? snapshot.position
        : null;
    await PlaybackModeService().setMode(snapshot.playbackMode);

    _pendingRestorePosition = restorePosition;

    if (autoPlay) {
      // Android 启动恢复链路需要 staged autoplay：先挂 source，再在 resume 前完成
      // media service 等附属初始化，避免首次出声附近的时序扰动。
      final shouldStageStartupAutoPlay = Platform.isAndroid;
      await playNow(
        snapshot.queue,
        snapshot.currentIndex,
        snapshot.source,
        intent: PlaybackRequestIntent.restore,
        autoPlay: !shouldStageStartupAutoPlay,
        initialPosition: restorePosition,
        preload: !shouldStageStartupAutoPlay,
      );
      if (restorePosition != null) {
        _position = restorePosition;
        positionNotifier.value = restorePosition;
      }
      _pendingRestorePosition = null;
      if (shouldStageStartupAutoPlay) {
        if (beforeDeferredAutoPlay != null) {
          await beforeDeferredAutoPlay();
        }
        await _engine.resume();
      }
      return;
    }

    _resetPreloadState();
    _queueController.replace(
      snapshot.queue,
      snapshot.currentIndex,
      snapshot.source,
    );
    _state = PBState.idle;
    _activeTrack = _trackAtQueuePointer();
    _activeSong = null;
    _clearPendingTrack();
    _setLyricLoadState(LyricLoadState.idle, track: _activeTrack, notify: false);
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
        _updateSessionPhase(PlaybackPhase.playing);
        _cancelAutoSkipTimer();
        _state = PBState.playing;
        // 注意：此处不清零 _consecutiveErrors/_retriedTrackKey，也不触发
        // 历史记录/预载——这些成功副作用统一等播放稳定后执行
        // （见 _onStablePlayback），避免"起播 1 秒即失败"被误判为成功。
        _errorMessage = null;
        _clearPlaybackProblem();
        _startStateSaveTimer();
        if (Platform.isWindows) DesktopLyricService().setPlayingState(true);
        if (Platform.isAndroid)
          AndroidFloatingLyricService().setPlayingState(true);
        _scheduleSessionPersist();
        _stabilityTracker.onPlaybackStarted(_playGeneration);
        break;
      case EngineState.paused:
        _updateSessionPhase(PlaybackPhase.paused);
        _state = PBState.paused;
        _stabilityTracker.onPlaybackInterrupted();
        _pauseListeningTimeTracking();
        _stopStateSaveTimer();
        if (Platform.isWindows) DesktopLyricService().setPlayingState(false);
        if (Platform.isAndroid)
          AndroidFloatingLyricService().setPlayingState(false);
        _cancelScheduledPreload();
        _scheduleSessionPersist();
        break;
      case EngineState.idle:
        _updateSessionPhase(PlaybackPhase.idle);
        _state = PBState.idle;
        _stabilityTracker.onPlaybackInterrupted();
        _pauseListeningTimeTracking();
        _stopStateSaveTimer();
        if (Platform.isWindows) DesktopLyricService().setPlayingState(false);
        if (Platform.isAndroid)
          AndroidFloatingLyricService().setPlayingState(false);
        _cancelScheduledPreload();
        _scheduleSessionPersist();
        break;
    }
    notifyListeners();
  }

  /// 播放已稳定（持续 ≥3s 且进度前进）：此时才承认播放成功，
  /// 执行成功副作用并重置失败追踪状态。
  void _onStablePlayback() {
    _consecutiveErrors = 0;
    _retriedTrackKey = null;
    _startListeningTimeTracking();
    _schedulePreloadNextTrack();
    _recordPlaybackStarted();
    final track = _stableCacheTrack;
    final song = _stableCacheSong;
    final quality = _stableCacheQuality;
    _stableCacheTrack = null;
    _stableCacheSong = null;
    _stableCacheQuality = null;
    if (track != null && song != null && quality != null) {
      unawaited(_cacheSongInBackground(track, song, quality));
    }
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
    // 纪元守卫：错误携带引擎源头纪元，属于旧纪元的迟到错误直接丢弃，
    // 避免旧歌错误触发新歌的重试/跳歌/报错。
    if (error.epoch != _playGeneration) {
      print('[PlaybackService] 丢弃旧纪元引擎错误: $error');
      return;
    }
    _updateSessionPhase(PlaybackPhase.failed);
    final track = _pendingTrack ?? currentTrack;
    if (track == null || _state == PBState.error) return;
    final failureIntent = _pendingIntent ?? _activeIntent;

    final trackKey = _buildTrackIdentity(track);
    final cacheQuality = _currentCachedStreamInfo?.metadata.quality;
    final shouldRetryWithoutCache =
        cacheQuality != null && _retriedTrackKey != trackKey;
    final canRetry =
        shouldRetryWithoutCache ||
        (_canRetryOnError(error) && _retriedTrackKey != trackKey);

    if (canRetry) {
      _retriedTrackKey = trackKey;
      final requestEpoch = _requestRouter.begin();
      if (cacheQuality != null) {
        print('[PlaybackService] 缓存流播放失败，绕过当前缓存后重试: $error');
      } else {
        print('[PlaybackService] 引擎错误，强制重新解析后重试: $error');
      }
      final current = _pendingTrack ?? currentTrack;
      if (current == null || _buildTrackIdentity(current) != trackKey) return;
      if (cacheQuality != null) {
        _rememberCacheBypassKey(
          _cachePlaybackKey(current, cacheQuality),
          reason: 'engine-retry',
        );
        _currentCachedStreamInfo = null;
      }
      // 强制远端重解析：预取/缓存的 URL 已被证明失败（常见为 CDN
      // 直链过期），复用只会再次失败。forceRemoteResolution 同时
      // 会丢弃同曲预取计划。
      unawaited(
        _playCurrentTrack(
          reason: 'engine-retry',
          intent: failureIntent,
          requestEpoch: requestEpoch,
          forceRemoteResolution: true,
        ),
      );
      return;
    }

    _state = PBState.error;
    _errorMessage = _buildErrorMessage(error);
    _isAudioSourceNotConfigured = false;
    notifyListeners();
    _reportPlaybackFailure(
      track,
      _errorMessage!,
      kind: _problemKindForEngineError(error),
      recoveryActions: error.type == EngineErrorType.unsupportedFormat
          ? const {}
          : const {PlaybackRecoveryAction.retry},
    );
    _autoSkipOnError(failureIntent);
  }

  void _updateSessionPhase(PlaybackPhase phase) {
    final session = _currentSession;
    if (session == null) return;
    _currentSession = session.copyWith(phase: phase);
  }

  void _reportPlaybackFailure(
    Track track,
    String message, {
    PlaybackProblemKind kind = PlaybackProblemKind.unknown,
    Set<PlaybackRecoveryAction> recoveryActions = const {
      PlaybackRecoveryAction.retry,
    },
    bool emitEffect = true,
  }) {
    final problem = _problemStore.report(
      transactionId: _playGeneration,
      track: track,
      kind: kind,
      message: message,
      recoveryActions: recoveryActions,
    );
    if (problem == null) return;
    problemNotifier.value = problem;
    if (emitEffect) {
      onPlaybackFailure?.call(problem);
    }
  }

  void _clearPlaybackProblem() {
    if (_problemStore.clear()) {
      problemNotifier.value = null;
    }
  }

  PlaybackProblemKind _problemKindForEngineError(EngineError error) {
    switch (error.type) {
      case EngineErrorType.unsupportedFormat:
        return PlaybackProblemKind.unsupportedFormat;
      case EngineErrorType.accessDenied:
        return PlaybackProblemKind.accessDenied;
      case EngineErrorType.networkTimeout:
        return PlaybackProblemKind.networkTimeout;
      case EngineErrorType.sourceLoad:
      case EngineErrorType.playback:
        return PlaybackProblemKind.engineFailure;
      case EngineErrorType.unknown:
        return PlaybackProblemKind.unknown;
    }
  }

  PlaybackProblemKind _problemKindForResolutionFailure(
    LxRuntimeFailure? failure,
  ) {
    switch (failure?.kind) {
      case LxRuntimeFailureKind.scriptRejected:
      case LxRuntimeFailureKind.notReady:
        return PlaybackProblemKind.sourceInvalid;
      case LxRuntimeFailureKind.timeout:
        return PlaybackProblemKind.networkTimeout;
      case LxRuntimeFailureKind.requestFailed:
      case null:
        return PlaybackProblemKind.resourceUnavailable;
    }
  }

  Set<PlaybackRecoveryAction> _recoveryActionsForResolutionFailure(
    LxRuntimeFailure? failure,
  ) {
    switch (failure?.kind) {
      case LxRuntimeFailureKind.scriptRejected:
      case LxRuntimeFailureKind.notReady:
        return const {
          PlaybackRecoveryAction.retry,
          PlaybackRecoveryAction.switchSource,
        };
      case LxRuntimeFailureKind.timeout:
      case LxRuntimeFailureKind.requestFailed:
      case null:
        return const {
          PlaybackRecoveryAction.retry,
          PlaybackRecoveryAction.switchSource,
        };
    }
  }

  String _resolutionFailureMessage(LxRuntimeFailure? failure) {
    switch (failure?.kind) {
      case LxRuntimeFailureKind.scriptRejected:
        return '当前音源脚本已被服务端拒绝（完整性验证失败），请重新导入或切换音源';
      case LxRuntimeFailureKind.notReady:
        return '当前音源尚未就绪，请稍后重试或重新导入音源';
      case LxRuntimeFailureKind.timeout:
        return '获取播放链接超时，请检查网络后重试';
      case LxRuntimeFailureKind.requestFailed:
        return '音源请求失败，未返回可播放链接，请切换音源后重试';
      case null:
        return '音源未返回可播放链接，请切换音源后重试';
    }
  }

  String? _activeLxSourceFingerprint() {
    final sourceService = AudioSourceService();
    final source = sourceService.activeSource;
    if (source == null || source.type != AudioSourceType.lxmusic) return null;
    // 健康状态必须绑定所有会影响远端请求的配置。音源可能在原 ID
    // 下编辑 endpoint/API key；只绑定脚本会复用旧的熔断状态，阻断新配置。
    final requestConfig = <Object?>[
      source.id,
      source.type.name,
      source.version,
      source.url,
      source.apiKey,
      source.scriptContent,
      source.scriptSource,
      source.urlPathTemplate,
      source.supportedPlatforms.join(','),
    ].join('\u0000');
    return '${source.id}:${requestConfig.hashCode}';
  }

  void _syncActiveSourceHealth() {
    final fingerprint = _activeLxSourceFingerprint();
    sourceHealthNotifier.value = fingerprint == null
        ? null
        : _sourceHealthTracker.snapshot(fingerprint);
  }

  SourceHealthFailureKind _sourceHealthFailureKind(LxRuntimeFailure? failure) {
    switch (failure?.kind) {
      case LxRuntimeFailureKind.scriptRejected:
        return SourceHealthFailureKind.systemicRejection;
      case LxRuntimeFailureKind.timeout:
        return SourceHealthFailureKind.transientTimeout;
      case LxRuntimeFailureKind.notReady:
        return SourceHealthFailureKind.runtimeNotReady;
      case LxRuntimeFailureKind.requestFailed:
      case null:
        return SourceHealthFailureKind.trackSpecific;
    }
  }

  SourceHealthSnapshot _recordSourceResolutionFailure(
    String fingerprint,
    LxRuntimeFailure? failure,
  ) {
    final snapshot = _sourceHealthTracker.recordFailure(
      fingerprint,
      _sourceHealthFailureKind(failure),
    );
    if (_activeLxSourceFingerprint() == fingerprint) {
      sourceHealthNotifier.value = snapshot;
    }
    return snapshot;
  }

  void _recordSourceResolutionSuccess(String fingerprint) {
    final snapshot = _sourceHealthTracker.recordSuccess(fingerprint);
    if (_activeLxSourceFingerprint() == fingerprint) {
      sourceHealthNotifier.value = snapshot;
    }
  }

  void _recordPlaybackStarted() {
    final track = _activeTrack;
    if (track == null) return;
    _historyRecorder.recordStarted(
      transactionId: _activePlaybackToken,
      track: track,
    );
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
    // 切换窗口内旧纪元的 completed 事件不会到达引擎层闸门；此处再按代次
    // 兜底，防止 stop()/arm() 交错时残留的完成事件触发提前切歌。
    if (_pendingTrack != null) return;
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
    bool autoPlay = true,
    Duration? initialPosition,
    bool preload = true,
    PlaybackRequestIntent intent = PlaybackRequestIntent.manual,
  }) {
    final requestEpoch = _requestRouter.begin();
    // 队列指针和 pending session 必须在第一次 await 前切换。否则旧的
    // 解析任务会占住 CommandQueue，后续点击虽然最终会被丢弃，但用户仍
    // 要等旧请求完成后才看到新歌。
    _resetPreloadState();
    _pendingRestorePosition = null;
    _queueController.replace(
      tracks,
      index,
      source,
      coverProviders: coverProviders,
    );
    _preloadedTrack = null;
    return _playCurrentTrack(
      reason: 'play-now',
      intent: intent,
      requestEpoch: requestEpoch,
      autoPlay: autoPlay,
      initialPosition: initialPosition,
      preload: preload,
    ).whenComplete(_scheduleSessionPersist);
  }

  /// 下一首播放（插入到当前之后）
  Future<void> playNext(Track track) {
    return _commands.enqueue(() async {
      _resetPreloadState();
      _pendingRestorePosition = null;
      _queueController.insertNext(track);
      notifyListeners();
      _scheduleSessionPersist();
    });
  }

  /// 加入队列末尾
  Future<void> addToQueue(Track track) {
    return _commands.enqueue(() async {
      _resetPreloadState();
      _pendingRestorePosition = null;
      _queueController.append(track);
      notifyListeners();
      _scheduleSessionPersist();
    });
  }

  /// 批量加入队列末尾
  Future<void> addAllToQueue(List<Track> tracks) {
    return _commands.enqueue(() async {
      _resetPreloadState();
      _pendingRestorePosition = null;
      _queueController.appendAll(tracks);
      notifyListeners();
      _scheduleSessionPersist();
    });
  }

  /// 跳转到队列中某首
  Future<void> jumpTo(int index) {
    final requestEpoch = _requestRouter.begin();
    if (!_queueController.jumpTo(index)) return Future<void>.value();
    _resetPreloadState();
    _pendingRestorePosition = null;
    return _playCurrentTrack(
      reason: 'jump-to',
      requestEpoch: requestEpoch,
    ).whenComplete(_scheduleSessionPersist);
  }

  /// 移除队列中某首
  Future<void> removeAt(int index) {
    return _commands.enqueue(() async {
      _resetPreloadState();
      _pendingRestorePosition = null;
      final removal = _queueController.removeAt(index);
      if (!removal.removed) return;
      if (removal.becameEmpty) {
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
      } else if (removal.removedCurrent) {
        await _playCurrentTrack(reason: 'remove-current');
      }
      notifyListeners();
      _scheduleSessionPersist();
    });
  }

  /// 拖拽排序
  Future<void> reorder(int oldIndex, int newIndex) {
    return _commands.enqueue(() async {
      _resetPreloadState();
      _pendingRestorePosition = null;
      if (!_queueController.reorder(oldIndex, newIndex)) return;
      notifyListeners();
      _scheduleSessionPersist();
    });
  }

  /// 清空队列
  Future<void> clearQueue() {
    // 先于 CommandQueue 失效当前事务。清空操作可能排在一个正在解析或
    // 淡出的播放命令之后，不能等到队列真正执行时才取消旧切换。
    _invalidateCurrentPlayback();
    return _commands.enqueue(() async {
      _resetPreloadState();
      _cancelAutoSkipTimer();
      _pendingRestorePosition = null;
      _queueController.clear();
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
      _clearPlaybackProblem();
      notifyListeners();
      await _sessionManager.clear();
    });
  }

  // ══════════════════════════════════════════════════════
  // 播放控制
  // ══════════════════════════════════════════════════════

  Future<void> resume() async {
    // 预载态：播放器尚未初始化，走完整播放
    if (_state == PBState.idle && currentTrack != null) {
      if (_queue.isNotEmpty && _currentIndex >= 0) {
        final requestEpoch = _requestRouter.begin();
        final restorePosition = _takePendingRestorePosition();
        await _playCurrentTrack(
          reason: 'resume',
          requestEpoch: requestEpoch,
          autoPlay: restorePosition == null,
          initialPosition: restorePosition,
        );
        if (restorePosition != null && _requestRouter.isCurrent(requestEpoch)) {
          _position = restorePosition;
          positionNotifier.value = restorePosition;
          await _engine.resume();
        }
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
    final requestEpoch = _requestRouter.begin();
    final mode = PlaybackModeService().currentMode;
    if (mode == PlaybackMode.shuffle) {
      await _playRandomNext(requestEpoch: requestEpoch);
    } else {
      // sequential, loopAll, repeatOne: 手动切歌都走顺序（允许循环）
      await _playSequentialNext(requestEpoch: requestEpoch);
    }
  }

  Future<void> previous() async {
    final requestEpoch = _requestRouter.begin();
    final mode = PlaybackModeService().currentMode;
    if (mode == PlaybackMode.shuffle) {
      await _playRandomPrevious(requestEpoch: requestEpoch);
    } else {
      // sequential, loopAll, repeatOne: 手动切歌都走顺序（允许循环）
      await _playSequentialPrevious(requestEpoch: requestEpoch);
    }
  }

  Future<void> stop() async {
    _invalidateCurrentPlayback();
    _cancelAutoSkipTimer();
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

  Future<void> retryCurrentTrack({
    PlaybackProblem? expectedProblem,
    bool forceRemoteResolution = false,
  }) async {
    final requestEpoch = _requestRouter.begin();
    if (expectedProblem != null && !isCurrentPlaybackProblem(expectedProblem)) {
      return;
    }
    if (_trackAtQueuePointer() == null && _activeTrack == null) return;
    _state = PBState.loading;
    _errorMessage = null;
    _isAudioSourceNotConfigured = false;
    notifyListeners();
    return _playCurrentTrack(
      reason: 'manual-retry',
      intent: PlaybackRequestIntent.retry,
      requestEpoch: requestEpoch,
      forceRemoteResolution: forceRemoteResolution,
    );
  }

  Future<bool> revalidateActiveSource() async {
    final fingerprint = _activeLxSourceFingerprint();
    if (fingerprint == null ||
        (_trackAtQueuePointer() == null && _activeTrack == null)) {
      return false;
    }
    sourceHealthNotifier.value = _sourceHealthTracker.prepareManualProbe(
      fingerprint,
    );
    await retryCurrentTrack(forceRemoteResolution: true);
    return true;
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
      coverManager.setCoverImmediate(
        coverProvider,
        url: track.picUrl,
        notify: false,
      );
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
    final requestEpoch = _requestRouter.begin();
    return _commands.enqueue(() async {
      await _cleanupCurrentTempFile();
      _state = PBState.loading;
      _preloadedTrack = null;
      _clearPendingTrack();
      _errorMessage = null;
      final gen = _transactionGuard.begin();
      _duration = Duration.zero;
      _position = Duration.zero;
      positionNotifier.value = Duration.zero;
      coverManager.setCoverImmediate(null, notify: false);
      coverManager.themeColorNotifier.value = null;

      // 电台播放也必须建立完整 session，否则软切换的纪元闸门会将
      // 该路径误判为过期请求，导致引擎不启动但 UI 仍显示 playing。
      _currentSession = PlaybackSession(
        epoch: gen,
        requestEpoch: requestEpoch,
        trackKey: _buildTrackIdentity(radioTrack),
        phase: PlaybackPhase.resolving,
      );

      // 设置电台的 track 到队列
      _queueController.replace([radioTrack], 0, QueueSource.radio);

      _stagePendingTrack(
        radioTrack,
        reason: 'radio',
        intent: PlaybackRequestIntent.manual,
      );
      notifyListeners();
      await _playWithSoftSwitch(streamUrl);
      if (!_canStartPlayback(gen)) return;
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
    return _queueController.coverProviderFor(track, _coverKey(track));
  }

  void updateCoverProvider(Track track, ImageProvider provider) {
    _queueController.updateCoverProvider(track, _coverKey(track), provider);
  }

  void updateCoverProviders(Map<String, ImageProvider> providers) {
    _queueController.updateCoverProviders(providers);
  }

  void _primeDisplayStateForTrack(Track track) {
    final existingProvider = getCoverProvider(track);
    if (existingProvider != null) {
      coverManager.setCoverImmediate(
        existingProvider,
        url: track.picUrl,
        notify: false,
      );
      return;
    }
    coverManager.updateCoverNonBlocking(
      track.picUrl,
      notify: false,
      force: true,
    );
  }

  Track? _trackAtQueuePointer() {
    return _queueController.currentTrack;
  }

  void _stagePendingTrack(
    Track track, {
    required String reason,
    required PlaybackRequestIntent intent,
  }) {
    _pendingTrack = track;
    _pendingReason = reason;
    _pendingIntent = intent;
    _pendingSwitchToken++;
  }

  void _clearPendingTrack() {
    _pendingTrack = null;
    _pendingReason = null;
    _pendingIntent = null;
  }

  void _commitActivePresentation(
    Track track, {
    SongDetail? songDetail,
    required int playbackToken,
    PlaybackRequestIntent intent = PlaybackRequestIntent.manual,
    bool notify = true,
  }) {
    _activeTrack = track;
    _activeSong = songDetail;
    _activePlaybackToken = playbackToken;
    _activeIntent = intent;
    _clearPendingTrack();
    _preloadedTrack = null;
    _primeDisplayStateForTrack(track);
    if (notify) {
      notifyListeners();
    }
  }

  void _applyResolvedSongDetail(SongDetail songDetail, {bool notify = true}) {
    _activeSong = songDetail;
    if (notify) {
      notifyListeners();
    }
  }

  TrackSwitchTransaction? _prepareTrackSwitchTransaction({
    required String reason,
    required PlaybackRequestIntent intent,
    int? requestEpoch,
    bool forceRemoteResolution = false,
  }) {
    final track = _trackAtQueuePointer() ?? _activeTrack;
    if (track == null) return null;

    _resetPreloadState(clearPrefetchedDetails: false);
    _preloadedTrack = null;
    _cancelAutoSkipTimer();
    _stagePendingTrack(track, reason: reason, intent: intent);
    final token = _transactionGuard.begin();
    final selectedQuality = AudioQualityService().currentQuality;
    final tx = TrackSwitchTransaction(
      token: token,
      pendingToken: _pendingSwitchToken,
      requestEpoch: requestEpoch ?? _requestRouter.currentEpoch,
      session: PlaybackSession(
        epoch: token,
        requestEpoch: requestEpoch ?? _requestRouter.currentEpoch,
        trackKey: _buildTrackIdentity(track),
        phase: PlaybackPhase.resolving,
      ),
      track: track,
      reason: reason,
      requestedKey: _buildTrackIdentity(track),
      selectedQuality: selectedQuality,
      qualityStr: selectedQuality.value,
      intent: intent,
      forceRemoteResolution: forceRemoteResolution,
    );
    _currentSession = tx.session;

    _state = PBState.loading;
    _errorMessage = null;
    _clearPlaybackProblem();
    _isAudioSourceNotConfigured = false;
    notifyListeners();

    if (track.source != MusicSource.local &&
        !AudioSourceService().isConfigured) {
      _state = PBState.error;
      _errorMessage = '音源未配置，请在设置中配置音源';
      _isAudioSourceNotConfigured = true;
      notifyListeners();
      _reportPlaybackFailure(
        track,
        _errorMessage!,
        kind: PlaybackProblemKind.sourceNotConfigured,
        recoveryActions: const {PlaybackRecoveryAction.openSourceSettings},
        emitEffect: false,
      );
      onAudioSourceNotConfigured?.call();
      return null;
    }

    final isFromPlaylist = _source == QueueSource.playlist;
    if (isFromPlaylist && track.source == MusicSource.apple) {
      _state = PBState.error;
      _errorMessage = '由于Apple接口限制，通过该接口导入的音乐需要换源才能播放！';
      notifyListeners();
      _reportPlaybackFailure(
        track,
        _errorMessage!,
        kind: PlaybackProblemKind.resourceUnavailable,
        recoveryActions: const {PlaybackRecoveryAction.switchSource},
      );
      _notifyAppleMusicRestriction(track);
      return null;
    }

    _precacheNextCover();
    if (Platform.isAndroid || Platform.isIOS) {
      WakelockPlus.enable();
    }
    return tx;
  }

  bool _isTrackSwitchTransactionStale(TrackSwitchTransaction tx) {
    final pending = _pendingTrack;
    if (!_transactionGuard.isCurrent(tx.token)) return true;
    if (tx.requestEpoch != 0 && !_requestRouter.isCurrent(tx.requestEpoch)) {
      return true;
    }
    if (tx.pendingToken != _pendingSwitchToken) return true;
    return !_matchesTrackIdentity(pending, tx.requestedKey);
  }

  bool _canStartPlayback(int generation) {
    final session = _currentSession;
    return _transactionGuard.isCurrent(generation) &&
        session != null &&
        session.epoch == generation &&
        _requestRouter.isCurrent(session.requestEpoch) &&
        session.phase != PlaybackPhase.idle &&
        session.phase != PlaybackPhase.failed;
  }

  void _beginReplaySession(int requestEpoch) {
    final track = currentTrack;
    if (track == null) return;
    final token = _transactionGuard.begin();
    _currentSession = PlaybackSession(
      epoch: token,
      requestEpoch: requestEpoch,
      trackKey: _buildTrackIdentity(track),
      phase: PlaybackPhase.resolving,
    );
  }

  void _invalidateCurrentPlayback() {
    _requestRouter.begin();
    _transactionGuard.begin();
    _pendingSwitchToken++;
    _stabilityTracker.onPlaybackInterrupted();
    _stableCacheTrack = null;
    _stableCacheSong = null;
    _stableCacheQuality = null;
    _updateSessionPhase(PlaybackPhase.idle);
  }

  Future<_ResolvedTrackSwitchSong?> _resolveSongDetailStage(
    TrackSwitchTransaction tx,
    bool Function() isStale,
  ) async {
    final track = tx.track;
    _currentCachedStreamInfo = null;
    final cachePlaybackKey = _cachePlaybackKey(track, tx.qualityStr);
    final lookup = await _trackResolver.lookupLocalOrCache(
      track: track,
      quality: tx.qualityStr,
      skipCache:
          tx.forceRemoteResolution ||
          _cacheBypassKeys.contains(cachePlaybackKey),
    );
    if (isStale()) return null;

    final cacheInfo = lookup.cacheInfo;
    final cachedOrLocalDetail = lookup.resolvedDetail;
    if (cachedOrLocalDetail != null) {
      return _ResolvedTrackSwitchSong(
        songDetail: cachedOrLocalDetail,
        cacheInfo: cacheInfo,
        isCached: lookup.isCached,
        shouldRefreshCachedMetadata: lookup.shouldRefreshCachedMetadata,
        shouldRefreshExistingCacheMetadata: false,
      );
    }

    if (cacheInfo != null && cacheInfo.metadata.quality != tx.qualityStr) {
      print(
        '[PlaybackService] 跳过缓存命中，音质不匹配: ${cacheInfo.metadata.quality} != ${tx.qualityStr}',
      );
    }

    if (lookup.localFileMissing) {
      _state = PBState.error;
      _errorMessage = '本地文件不存在';
      notifyListeners();
      _reportPlaybackFailure(
        track,
        _errorMessage!,
        kind: PlaybackProblemKind.localFileMissing,
        recoveryActions: const {},
      );
      _autoSkipOnError(tx.intent);
      return null;
    }

    final lxSourceFingerprint = _activeLxSourceFingerprint();
    final sourceRequestAllowed =
        lxSourceFingerprint == null ||
        _sourceHealthTracker.allowRequest(lxSourceFingerprint);
    if (lxSourceFingerprint != null) {
      sourceHealthNotifier.value = _sourceHealthTracker.snapshot(
        lxSourceFingerprint,
      );
    }
    if (!sourceRequestAllowed) {
      _state = PBState.error;
      _errorMessage = '当前音源连续解析失败，已暂停请求，请重新导入或切换音源';
      notifyListeners();
      _reportPlaybackFailure(
        track,
        _errorMessage!,
        kind: PlaybackProblemKind.sourceInvalid,
        recoveryActions: const {
          PlaybackRecoveryAction.switchSource,
          PlaybackRecoveryAction.reimportSource,
        },
      );
      return null;
    }

    final resolution = await _trackResolver.resolve(
      songId: track.id,
      quality: tx.selectedQuality,
      source: track.source,
      title: track.name,
      artist: track.artists,
      timeout: _playSongDetailTimeout,
      fetchLyrics: false,
    );
    final songDetail = resolution.detail;
    if (isStale()) {
      if (lxSourceFingerprint != null) {
        _sourceHealthTracker.cancelRequest(lxSourceFingerprint);
        _syncActiveSourceHealth();
      }
      return null;
    }
    final isSameLxSource =
        lxSourceFingerprint != null &&
        _activeLxSourceFingerprint() == lxSourceFingerprint;
    if (lxSourceFingerprint != null && !isSameLxSource) {
      _sourceHealthTracker.cancelRequest(lxSourceFingerprint);
    }
    if (songDetail == null || songDetail.url.isEmpty) {
      final lxFailure = isSameLxSource ? resolution.lxFailure : null;
      final sourceHealth = !isSameLxSource
          ? null
          : _recordSourceResolutionFailure(lxSourceFingerprint, lxFailure);
      final circuitOpen = sourceHealth?.isCircuitOpen ?? false;
      _state = PBState.error;
      _errorMessage = _resolutionFailureMessage(lxFailure);
      notifyListeners();
      _reportPlaybackFailure(
        track,
        circuitOpen ? '当前音源连续解析失败，请重新导入或切换音源' : _errorMessage!,
        kind: circuitOpen
            ? PlaybackProblemKind.sourceInvalid
            : _problemKindForResolutionFailure(lxFailure),
        recoveryActions: circuitOpen
            ? const {
                PlaybackRecoveryAction.switchSource,
                PlaybackRecoveryAction.reimportSource,
              }
            : _recoveryActionsForResolutionFailure(lxFailure),
      );
      if (!circuitOpen) _autoSkipOnError(tx.intent);
      return null;
    }

    if (isSameLxSource) {
      _recordSourceResolutionSuccess(lxSourceFingerprint);
    }

    final normalizedSong = _normalizeSongDetailForPlayback(track, songDetail);
    return _ResolvedTrackSwitchSong(
      songDetail: normalizedSong,
      cacheInfo: cacheInfo,
      isCached: lookup.isCached,
      shouldRefreshCachedMetadata: false,
      shouldRefreshExistingCacheMetadata:
          cacheInfo != null && needsCachedMetadataRefresh(cacheInfo.metadata),
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
        source: source,
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
    bool Function() isStale, {
    bool autoPlay = true,
    Duration? initialPosition,
    bool preload = true,
  }) async {
    var committedPlan = plan;
    if (plan.usesCachedStream && plan.source is CachedCyrenePlayableSource) {
      final cachedSource = plan.source as CachedCyrenePlayableSource;
      final playedFromStream = await _playCachedStreamSource(
        cachedSource.cacheInfo,
        autoPlay: autoPlay,
        initialPosition: initialPosition,
        preload: preload,
      );
      if (!playedFromStream) {
        if (isStale()) return null;
        final fallbackResolvedSong = await _resolveSongDetailStage(tx, isStale);
        if (fallbackResolvedSong == null || isStale()) return null;
        final fallbackPlan = await _resolvePlayableSourceStage(
          tx,
          fallbackResolvedSong,
          isStale,
        );
        if (fallbackPlan == null || isStale()) return null;
        committedPlan = fallbackPlan;
        await _playPlayableSourceWithSoftSwitch(
          committedPlan.source,
          autoPlay: autoPlay,
          initialPosition: initialPosition,
          preload: preload,
        );
      }
    } else {
      await _playPlayableSourceWithSoftSwitch(
        plan.source,
        autoPlay: autoPlay,
        initialPosition: initialPosition,
        preload: preload,
      );
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
      intent: tx.intent,
    );
    _stableCacheTrack = null;
    _stableCacheSong = null;
    _stableCacheQuality = null;
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
      _scheduleCoverRefresh(track, coverRefreshUrl, reason: plan.themeReason);
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

    if (plan.usesCachedStream &&
        plan.resolvedSong.shouldRefreshCachedMetadata) {
      if (!isPresentationStale()) {
        requestLyricsForPresentation();
      }
      return;
    }

    if (plan.shouldWriteBackgroundCache) {
      _stableCacheTrack = track;
      _stableCacheSong = songDetail;
      _stableCacheQuality = tx.qualityStr;
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

  SongDetail _mergeSupplementalSongDetail(
    SongDetail current,
    SongDetail supplemental,
  ) {
    return SongDetail(
      id: current.id,
      name: supplemental.name.isNotEmpty ? supplemental.name : current.name,
      pic: supplemental.pic.isNotEmpty ? supplemental.pic : current.pic,
      arName: supplemental.arName.isNotEmpty
          ? supplemental.arName
          : current.arName,
      alName: supplemental.alName.isNotEmpty
          ? supplemental.alName
          : current.alName,
      level: current.level,
      size: current.size,
      url: current.url,
      lyric: supplemental.lyric.isNotEmpty ? supplemental.lyric : current.lyric,
      tlyric: supplemental.tlyric.isNotEmpty
          ? supplemental.tlyric
          : current.tlyric,
      yrc: supplemental.yrc.isNotEmpty ? supplemental.yrc : current.yrc,
      ytlrc: supplemental.ytlrc.isNotEmpty ? supplemental.ytlrc : current.ytlrc,
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
      name: normalizedDetail.name.isNotEmpty
          ? normalizedDetail.name
          : current.name,
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
    return song.lyric.isNotEmpty || song.yrc.isNotEmpty || song.qrc.isNotEmpty;
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
        useLyricOnlyFetch: _shouldUseLyricOnlySupplementalFetch(track),
        allowFullDetailFallback:
            _shouldAllowFullDetailFallbackForLyricOnlyFetch(track),
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
        normalizeSongDetail: (detail) =>
            _normalizeSongDetailForPlayback(track, detail),
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
      normalizeSongDetail: (detail) =>
          _normalizeSongDetailForPlayback(track, detail),
      hasAnyLyricPayload: _hasAnyLyricPayload,
      log: _logPlaybackDebug,
    );
  }

  bool _shouldScheduleDeferredSupplementalRefresh(SongDetail song) {
    if (song.source == MusicSource.local) return false;
    final lyricPayloadMissing =
        song.lyric.isEmpty &&
        song.tlyric.isEmpty &&
        song.yrc.isEmpty &&
        song.ytlrc.isEmpty &&
        song.qrc.isEmpty &&
        song.qrcTrans.isEmpty;
    if (!lyricPayloadMissing) {
      return false;
    }
    if (song.source == MusicSource.navidrome) {
      // Navidrome 歌词补全走独立 API，不依赖当前全局音源类型。
      return true;
    }
    final sourceType = AudioSourceService().sourceType;
    if (sourceType != AudioSourceType.lxmusic &&
        sourceType != AudioSourceType.tunehub) {
      return false;
    }
    return true;
  }

  bool _shouldUseLyricOnlySupplementalFetch(Track track) {
    if (track.source == MusicSource.navidrome) {
      return true;
    }
    final sourceType = AudioSourceService().sourceType;
    return sourceType == AudioSourceType.lxmusic ||
        sourceType == AudioSourceType.tunehub;
  }

  bool _shouldAllowFullDetailFallbackForLyricOnlyFetch(Track track) {
    // Navidrome 歌词补全只走 getLyricsBySongId，不再回退完整详情二次请求。
    return track.source != MusicSource.navidrome;
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

  void _logPlaybackDebug(String message, {bool toDeveloperPanel = false}) {
    StructuredLogService.event(
      'playback.debug',
      level: LogLevel.debug,
      fields: {'message': message},
    );
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

  void _rememberCacheBypassKey(String cacheKey, {required String reason}) {
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
    _rememberCacheBypassKey(_cachePlaybackKey(track, quality), reason: reason);
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
      _cacheSongInBackground(track, detail, quality)
          .then((cached) {
            if (cached) {
              LyricService().markRefreshSettled(refreshKey);
            }
          })
          .catchError((Object e) {
            _logPlaybackDebug(
              '[PlaybackService] 回写缓存元数据失败($reason): $refreshKey, $e',
              toDeveloperPanel: true,
            );
          }),
    );
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
      coverManager.updateCoverNonBlocking(imageUrl, notify: true, force: true);
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

  void _resetShuffle() {
    _queueController.resetShuffle();
  }

  /// 预测下一首（不改变索引）
  Track? peekNext(dynamic mode) {
    final modeStr = mode.toString();
    final resolvedMode = modeStr.contains('repeatOne')
        ? PlaybackMode.repeatOne
        : modeStr.contains('shuffle')
        ? PlaybackMode.shuffle
        : PlaybackMode.loopAll;
    return _queueController.peekNext(resolvedMode);
  }

  /// 预测上一首（不改变索引）
  Track? peekPrevious(dynamic mode) {
    final modeStr = mode.toString();
    final resolvedMode = modeStr.contains('repeatOne')
        ? PlaybackMode.repeatOne
        : modeStr.contains('shuffle')
        ? PlaybackMode.shuffle
        : PlaybackMode.loopAll;
    return _queueController.peekPrevious(resolvedMode);
  }

  /// 队列信息字符串
  String getQueueInfo() {
    if (_queue.isEmpty) return '无播放队列';
    return '${_source.name} (${_currentIndex + 1}/${_queue.length})';
  }

  // ══════════════════════════════════════════════════════
  // 播放核心内部
  // ══════════════════════════════════════════════════════

  /// 以 latest-wins 方式发起切歌：先推进队列指针的调用方在完成指针推进
  /// 后，把重解析/装载流程脱离命令队列执行。连续快速切歌时，旧的脱离
  /// 流程被序号取代而中止，不会阻塞或排队后续请求（此前整段解析最长
  /// 12s 串行占用 CommandQueue，表现为连点切歌"卡住"）。
  ///
  /// 解析中途被取代的流程由 _isTrackSwitchTransactionStale 兑现中止。
  void _startDetachedTrackSwitch(
    String reason, {
    PlaybackRequestIntent intent = PlaybackRequestIntent.manual,
    int? requestEpoch,
  }) {
    final effectiveRequestEpoch = requestEpoch ?? _requestRouter.begin();
    final seq = ++_detachedSwitchSeq;
    unawaited(() async {
      await _waitForTrackSwitchSettle();
      if (seq != _detachedSwitchSeq) {
        _logPlaybackDebug('[PlaybackService] 切歌请求已被更新的请求取代，取消: $reason');
        return;
      }
      if (!_requestRouter.isCurrent(effectiveRequestEpoch)) return;
      await _playCurrentTrack(
        reason: reason,
        intent: intent,
        requestEpoch: effectiveRequestEpoch,
      );
    }());
  }

  Future<void> _playCurrentTrack({
    String reason = 'queue-switch',
    PlaybackRequestIntent intent = PlaybackRequestIntent.manual,
    int? requestEpoch,
    bool autoPlay = true,
    Duration? initialPosition,
    bool preload = true,
    bool forceRemoteResolution = false,
  }) async {
    // 1. prepareTarget
    final tx = _prepareTrackSwitchTransaction(
      reason: reason,
      intent: intent,
      requestEpoch: requestEpoch,
      forceRemoteResolution: forceRemoteResolution,
    );
    if (tx == null) return;
    final trace = OperationTrace(
      'playback.switch',
      context: {
        'transaction_id': tx.token,
        'pending_id': tx.pendingToken,
        'track_id': tx.requestedKey,
        'source': tx.track.source.name,
        'quality': tx.qualityStr,
        'reason': tx.reason,
        'intent': tx.intent.name,
      },
    );

    bool isStale() {
      return _isTrackSwitchTransactionStale(tx);
    }

    try {
      if (tx.forceRemoteResolution) {
        // 手动探测必须走远端解析，丢弃同曲目的预取计划，避免后续重试
        // 再次复用旧的缓存/预取结果。
        _discardPrefetchedPlayablePlan(tx.track, tx.selectedQuality);
      }
      final prefetchedPlan = tx.forceRemoteResolution
          ? null
          : _takePrefetchedPlayablePlan(tx.track, tx.selectedQuality);
      if (prefetchedPlan != null) {
        trace.mark(
          'prefetch_hit',
          fields: {
            'cache': prefetchedPlan.usesCachedStream ? 'hit' : 'miss',
            'playable_source': _describePlayableSource(prefetchedPlan.source),
          },
        );
        final committedPlan = await _commitPlaybackStage(
          tx,
          prefetchedPlan,
          isStale,
          autoPlay: autoPlay,
          initialPosition: initialPosition,
          preload: preload,
        );
        if (committedPlan == null) return;
        trace.mark(
          'engine_ready',
          fields: {
            'prefetched': true,
            'playable_source': _describePlayableSource(committedPlan.source),
          },
        );
        _commitPresentationStage(tx, committedPlan, isStale);
        trace.mark('presentation_committed');
        return;
      }

      // 2. resolveSongDetail
      final resolvedSong = await _resolveSongDetailStage(tx, isStale);
      if (resolvedSong == null || isStale()) return;
      trace.mark(
        'track_resolved',
        fields: {
          'cache': resolvedSong.isCached ? 'hit' : 'miss',
          'refresh_cached_metadata': resolvedSong.shouldRefreshCachedMetadata,
          'refresh_existing_metadata':
              resolvedSong.shouldRefreshExistingCacheMetadata,
        },
      );

      // 3. resolvePlayableSource
      final playbackPlan = await _resolvePlayableSourceStage(
        tx,
        resolvedSong,
        isStale,
      );
      if (playbackPlan == null || isStale()) return;
      trace.mark(
        'source_ready',
        fields: {
          'cache': playbackPlan.usesCachedStream ? 'hit' : 'miss',
          'playable_source': _describePlayableSource(playbackPlan.source),
          'background_cache': playbackPlan.shouldWriteBackgroundCache,
        },
      );

      // 4. commitPlayback
      final committedPlan = await _commitPlaybackStage(
        tx,
        playbackPlan,
        isStale,
        autoPlay: autoPlay,
        initialPosition: initialPosition,
        preload: preload,
      );
      if (committedPlan == null) return;
      trace.mark(
        'engine_ready',
        fields: {
          'playable_source': _describePlayableSource(committedPlan.source),
        },
      );

      // 5. commitPresentation
      _commitPresentationStage(tx, committedPlan, isStale);
      trace.mark('presentation_committed');
    } on EngineReportedException {
      // 错误已通过 errorStream 进入 _onEngineError，避免重复进入 catch 路径造成连跳。
      if (isStale()) return;
      trace.mark('engine_failed', level: LogLevel.error);
      return;
    } on AudioSourceNotConfiguredException catch (e) {
      if (isStale()) return;
      _state = PBState.error;
      _errorMessage = e.message;
      _isAudioSourceNotConfigured = true;
      notifyListeners();
      _reportPlaybackFailure(
        tx.track,
        e.message,
        kind: PlaybackProblemKind.sourceNotConfigured,
        recoveryActions: const {PlaybackRecoveryAction.openSourceSettings},
        emitEffect: false,
      );
      trace.mark('source_not_configured', level: LogLevel.warning, error: e);
      onAudioSourceNotConfigured?.call();
    } catch (e) {
      if (isStale()) return;
      _state = PBState.error;
      _errorMessage = '播放失败: $e';
      _isAudioSourceNotConfigured = false;
      notifyListeners();
      _reportPlaybackFailure(tx.track, _errorMessage!);
      trace.mark('failed', level: LogLevel.error, error: e);
      _autoSkipOnError(tx.intent);
    }
  }

  // ══════════════════════════════════════════════════════
  // 自动播放 / 切歌
  // ══════════════════════════════════════════════════════

  Future<void> _playNextAuto() async {
    final requestEpoch = _requestRouter.begin();
    final mode = PlaybackModeService().currentMode;
    switch (mode) {
      case PlaybackMode.repeatOne:
        if (currentTrack != null) {
          await _waitForTrackSwitchSettle();
          if (!_requestRouter.isCurrent(requestEpoch)) return;
          _beginReplaySession(requestEpoch);
          final replayed = await _replayCurrentSourceForRepeatOne();
          if (!replayed && _requestRouter.isCurrent(requestEpoch)) {
            await _playCurrentTrack(
              reason: 'repeat-one-reload',
              intent: PlaybackRequestIntent.automatic,
              requestEpoch: requestEpoch,
            );
          }
        }
        break;
      case PlaybackMode.loopAll:
        await _playSequentialNext(
          intent: PlaybackRequestIntent.automatic,
          requestEpoch: requestEpoch,
        );
        break;
      case PlaybackMode.shuffle:
        await _playRandomNext(
          intent: PlaybackRequestIntent.automatic,
          requestEpoch: requestEpoch,
        );
        break;
      case PlaybackMode.sequential:
        await _playSequentialNextOrStop(
          intent: PlaybackRequestIntent.automatic,
          requestEpoch: requestEpoch,
        );
        break;
    }
  }

  /// 顺序播放模式：播完最后一首停止
  Future<void> _playSequentialNextOrStop({
    PlaybackRequestIntent intent = PlaybackRequestIntent.manual,
    int? requestEpoch,
  }) async {
    return _commands.enqueue(() async {
      if (requestEpoch != null && !_requestRouter.isCurrent(requestEpoch)) {
        return;
      }
      if (_queue.isNotEmpty) {
        final nextIdx = _currentIndex + 1;
        if (nextIdx < _queue.length) {
          _queueController.jumpTo(nextIdx);
          // latest-wins：解析/装载脱离命令队列，连点时旧流程被序号取代
          _startDetachedTrackSwitch(
            'auto-next-stop-mode',
            intent: intent,
            requestEpoch: requestEpoch,
          );
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
        _queueController.replace([nextTrack], 0, QueueSource.history);
        _startDetachedTrackSwitch(
          'history-next-stop-mode',
          intent: intent,
          requestEpoch: requestEpoch,
        );
      }
    });
  }

  Future<void> _playSequentialNext({
    PlaybackRequestIntent intent = PlaybackRequestIntent.manual,
    int? requestEpoch,
  }) async {
    return _commands.enqueue(() async {
      if (requestEpoch != null && !_requestRouter.isCurrent(requestEpoch)) {
        return;
      }
      if (_queue.isNotEmpty) {
        final wrapped = _currentIndex + 1 >= _queue.length;
        _queueController.advanceNext(shuffle: false);
        // latest-wins：解析/装载脱离命令队列，连点时旧流程被序号取代
        _startDetachedTrackSwitch(
          wrapped ? 'manual-next-loop' : 'manual-next',
          intent: intent,
          requestEpoch: requestEpoch,
        );
        return;
      }
      // 无队列，用播放历史
      final nextTrack = PlayHistoryService().getNextTrack();
      if (nextTrack != null) {
        _queueController.replace([nextTrack], 0, QueueSource.history);
        _startDetachedTrackSwitch(
          'history-next',
          intent: intent,
          requestEpoch: requestEpoch,
        );
      }
    });
  }

  Future<void> _playSequentialPrevious({int? requestEpoch}) async {
    if (requestEpoch != null && !_requestRouter.isCurrent(requestEpoch)) {
      return;
    }
    if (_queue.isNotEmpty) {
      final wrapped = _currentIndex - 1 < 0;
      _queueController.advancePrevious(shuffle: false);
      return _playCurrentTrack(
        reason: wrapped ? 'manual-previous-loop' : 'manual-previous',
        requestEpoch: requestEpoch,
      );
    }
    final history = PlayHistoryService().history;
    if (history.length >= 3) {
      final prevTrack = history[2].toTrack();
      _queueController.replace([prevTrack], 0, QueueSource.history);
      return _playCurrentTrack(
        reason: 'history-previous',
        requestEpoch: requestEpoch,
      );
    }
  }

  // ── 随机播放 ──

  Future<void> _playRandomNext({
    PlaybackRequestIntent intent = PlaybackRequestIntent.manual,
    int? requestEpoch,
  }) async {
    if (requestEpoch != null && !_requestRouter.isCurrent(requestEpoch)) {
      return;
    }
    if (_queue.isEmpty) {
      // 从历史随机
      final history = PlayHistoryService().history;
      if (history.length >= 2) {
        final idx = _random.nextInt(history.length - 1) + 1;
        _queueController.replace(
          [history[idx].toTrack()],
          0,
          QueueSource.history,
        );
        await _waitForTrackSwitchSettle();
        if (requestEpoch == null || _requestRouter.isCurrent(requestEpoch)) {
          await _playCurrentTrack(
            reason: 'history-random-next',
            intent: intent,
            requestEpoch: requestEpoch,
          );
        }
      }
      return;
    }
    _queueController.advanceRandom();
    // latest-wins：解析/装载脱离命令队列，连点时旧流程被序号取代
    _startDetachedTrackSwitch(
      'shuffle-next',
      intent: intent,
      requestEpoch: requestEpoch,
    );
  }

  Future<void> _playRandomPrevious({int? requestEpoch}) async {
    if (requestEpoch != null && !_requestRouter.isCurrent(requestEpoch)) {
      return;
    }
    if (_queueController.advanceRandomPrevious() == null) return;
    return _playCurrentTrack(
      reason: 'shuffle-previous',
      requestEpoch: requestEpoch,
    );
  }

  // ══════════════════════════════════════════════════════
  // 兼容接口 (供 PlaylistQueueService facade 调用)
  // ══════════════════════════════════════════════════════

  /// setQueue 兼容：替换队列（不自动播放，仅更新状态）
  void setQueueSilent(
    List<Track> tracks,
    int index,
    QueueSource source, {
    Map<String, ImageProvider>? coverProviders,
  }) {
    _resetPreloadState();
    _pendingRestorePosition = null;
    _queueController.replace(
      tracks,
      index,
      source,
      coverProviders: coverProviders,
    );
    notifyListeners();
    _scheduleSessionPersist();
  }

  /// getNext 兼容：更新索引到下一首并返回
  Track? peekAndAdvanceNext() {
    final mode = PlaybackModeService().currentMode;
    final track = _queueController.advanceNext(
      shuffle: mode == PlaybackMode.shuffle,
    );
    if (track != null) notifyListeners();
    return track;
  }

  /// getPrevious 兼容：更新索引到上一首并返回
  Track? peekAndAdvancePrevious() {
    final mode = PlaybackModeService().currentMode;
    final track = _queueController.advancePrevious(
      shuffle: mode == PlaybackMode.shuffle,
    );
    if (track != null) notifyListeners();
    return track;
  }

  /// getRandomTrack 兼容
  Track? getRandomTrack() {
    final track = _queueController.advanceRandom();
    if (track != null) notifyListeners();
    return track;
  }

  /// getRandomPrevious 兼容
  Track? getRandomPrevious() {
    final track = _queueController.advanceRandomPrevious();
    if (track != null) notifyListeners();
    return track;
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
      listener = ImageStreamListener(
        (_, __) {
          stream.removeListener(listener);
          final bg = PlayerBackgroundService();
          if (bg.enableGradient &&
              bg.backgroundType == PlayerBackgroundType.adaptive) {
            coverManager.precacheThemeColor(url);
          }
        },
        onError: (_, __) {
          stream.removeListener(listener);
        },
      );
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
    _prefetchedPlayablePlans.removeWhere((_, entry) => entry.isExpired);
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

  void _discardPrefetchedPlayablePlan(Track track, AudioQuality quality) {
    _prefetchedPlayablePlans.remove(_buildPrefetchCacheKey(track, quality));
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

    if (normalized.name.isEmpty ||
        normalized.arName.isEmpty ||
        normalized.pic.isEmpty) {
      normalized = SongDetail(
        id: normalized.id,
        name: normalized.name.isNotEmpty ? normalized.name : track.name,
        pic: normalized.pic.isNotEmpty ? normalized.pic : track.picUrl,
        arName: normalized.arName.isNotEmpty
            ? normalized.arName
            : track.artists,
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

    if (track.source == MusicSource.apple &&
        !normalized.url.contains('/apple/stream')) {
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
    required AudioQuality quality,
    required MusicSource source,
    required String title,
    required String artist,
    required Duration timeout,
    required String purpose,
    bool fetchLyrics = true,
  }) async {
    final result = await _trackResolver.resolve(
      songId: songId,
      quality: quality,
      source: source,
      title: title,
      artist: artist,
      timeout: timeout,
      fetchLyrics: fetchLyrics,
    );
    if (result.timedOut) {
      print('[PlaybackService] 获取歌曲详情超时($purpose)');
    }
    return result.detail;
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
    bool autoPlay = true,
    Duration? initialPosition,
    bool preload = true,
  }) async {
    await _performSoftSwitch(
      (generation) => _engine.play(
        url,
        generation: generation,
        isLocal: isLocal,
        headers: headers,
        autoPlay: autoPlay,
        initialPosition: initialPosition,
        preload: preload,
      ),
      allowFadeIn: autoPlay,
    );
  }

  Future<void> _playPlayableSourceWithSoftSwitch(
    PlayableSource source, {
    bool autoPlay = true,
    Duration? initialPosition,
    bool preload = true,
  }) async {
    await _performSoftSwitch(
      (generation) => _engine.playSource(
        source,
        generation: generation,
        autoPlay: autoPlay,
        initialPosition: initialPosition,
        preload: preload,
      ),
      allowFadeIn: autoPlay,
    );
  }

  Future<void> _performSoftSwitch(
    Future<void> Function(int generation) startPlayback, {
    bool allowFadeIn = true,
  }) async {
    // 源头纪元捕获：必须在任何 await 之前读取。当前事务已在
    // _prepareTrackSwitchTransaction 中 begin()，此处的 _playGeneration
    // 即本次装载的目标纪元；引擎据此将装载期事件与旧歌隔离。
    final generation = _playGeneration;
    final targetVolume = _volume.clamp(0.0, 1.0);
    final canFade = allowFadeIn && _engine.isPlaying && targetVolume > 0;
    final fadeGeneration = generation;
    _updateSessionPhase(PlaybackPhase.arming);

    if (!canFade) {
      if (!_canStartPlayback(generation)) return;
      await startPlayback(generation);
      return;
    }

    final stepVolume = targetVolume / _switchFadeSteps;
    for (int i = _switchFadeSteps; i > 0; i--) {
      if (!_canStartPlayback(generation)) return;
      await _safeSetEngineVolume(stepVolume * (i - 1));
      await Future.delayed(_switchFadeStepDelay);
    }

    // stop()/new request may have invalidated the transaction while the fade
    // was awaiting native volume writes or timers. EngineHost serializes
    // writes but cannot infer whether a queued generation is obsolete.
    if (!_canStartPlayback(generation)) return;
    try {
      await startPlayback(generation);
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
    if (nextTrack.source != MusicSource.local &&
        !AudioSourceService().isConfigured) {
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
    final isLocal =
        track.source == MusicSource.local || !url.startsWith('http');
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

  Future<bool> _playCachedStreamSource(
    CyreneFileInfo cacheInfo, {
    bool autoPlay = true,
    Duration? initialPosition,
    bool preload = true,
  }) async {
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

      await _playPlayableSourceWithSoftSwitch(
        source,
        autoPlay: autoPlay,
        initialPosition: initialPosition,
        preload: preload,
      );
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
    final cacheInfo =
        _cacheBypassKeys.contains(_cachePlaybackKey(track, qualityStr))
        ? null
        : await CacheService().getCyreneFileInfo(track, quality: qualityStr);

    if (cacheInfo != null && cacheInfo.metadata.quality == qualityStr) {
      final cachedSong = buildCachedSongDetail(
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
          shouldRefreshCachedMetadata: needsCachedMetadataRefresh(
            cacheInfo.metadata,
          ),
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
          cacheInfo != null && needsCachedMetadataRefresh(cacheInfo.metadata),
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
            !resolvedSong.isCached &&
            !detail.url.toLowerCase().contains('.m3u8'),
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
              !resolvedSong.isCached &&
              !detail.url.toLowerCase().contains('.m3u8'),
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
            !resolvedSong.isCached &&
            !detail.url.toLowerCase().contains('.m3u8'),
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

  Future<int?> _getAppleStreamDuration(String streamUrl) async {
    try {
      final request = http.Request('HEAD', Uri.parse(streamUrl));
      request.headers['User-Agent'] = 'Mozilla/5.0';
      final client = http.Client();
      try {
        final response = await client
            .send(request)
            .timeout(const Duration(seconds: 30));
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

  Future<bool> _cacheSongInBackground(
    Track track,
    SongDetail detail,
    String quality,
  ) async {
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
      } catch (_) {
      } finally {
        _currentTempFilePath = null;
      }
    }
  }

  // ── 播放失败自动跳过 ──

  void _cancelAutoSkipTimer() {
    _autoSkipTimer?.cancel();
    _autoSkipTimer = null;
  }

  void _autoSkipOnError(PlaybackRequestIntent intent) {
    _consecutiveErrors++;
    final decision = _failurePolicy.evaluate(
      intent: intent,
      consecutiveFailures: _consecutiveErrors,
      queueLength: _queue.length,
    );
    if (decision.reachedFailureLimit) {
      print('[PlaybackService] 连续 $_consecutiveErrors 首播放失败，停止自动跳过');
      return;
    }
    if (!decision.shouldAutoSkip) return;
    print(
      '[PlaybackService] 自动播放失败，${decision.delay.inSeconds} 秒后跳到下一首 '
      '($_consecutiveErrors/${_failurePolicy.maxConsecutiveFailures})',
    );
    final failedGeneration = _playGeneration;
    _autoSkipTimer?.cancel();
    _autoSkipTimer = Timer(decision.delay, () {
      _autoSkipTimer = null;
      if (_state != PBState.error || _playGeneration != failedGeneration) {
        return;
      }
      unawaited(_playNextAuto());
    });
  }

  // ── 听歌统计 ──

  void _startListeningTimeTracking() {
    _historyRecorder.startListening();
  }

  void _pauseListeningTimeTracking() {
    _historyRecorder.pauseListening();
  }

  // ── 本地播放会话保存 ──

  void _startStateSaveTimer() {
    _sessionManager.startPeriodicSave();
  }

  void _stopStateSaveTimer() {
    _sessionManager.stopPeriodicSave();
  }

  void _scheduleSessionPersist() {
    _sessionManager.schedulePersist();
  }

  /// 立即持久化当前播放会话（跳过防抖），用于生命周期关键时刻。
  Future<void> persistSessionImmediately() async {
    await _sessionManager.persistImmediately();
  }

  Duration? _takePendingRestorePosition() {
    final pending = _pendingRestorePosition;
    _pendingRestorePosition = null;
    if (pending == null || pending <= Duration.zero) return null;
    return pending;
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

    if (Platform.isWindows &&
        DesktopLyricService().isVisible &&
        track != null) {
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
          final data = _lyrics
              .map(
                (line) => {
                  'time': line.startTime.inMilliseconds,
                  'text': line.text,
                  'translation': line.translation ?? '',
                },
              )
              .toList();
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
    final isAndroid =
        Platform.isAndroid && AndroidFloatingLyricService().isVisible;
    if (!isWin && !isAndroid) return;

    try {
      final newIdx = LyricParser.findCurrentLineIndex(_lyrics, _position);
      if (newIdx != _currentLyricIndex && newIdx >= 0) {
        _currentLyricIndex = newIdx;
        final line = _lyrics[newIdx];
        int? durationMs;
        if (newIdx + 1 < _lyrics.length) {
          durationMs =
              _lyrics[newIdx + 1].startTime.inMilliseconds -
              line.startTime.inMilliseconds;
        } else {
          durationMs = 3000;
        }
        if (isWin) {
          DesktopLyricService().setLyricText(line.text, durationMs: durationMs);
          DesktopLyricService().setTranslationText(
            (line.translation != null && line.translation!.isNotEmpty)
                ? line.translation!
                : '',
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
    _queueController.clear();
    _preloadedTrack = null;
    _clearPendingTrack();
    _position = Duration.zero;
    _duration = Duration.zero;
    _bufferedPosition = Duration.zero;
    _errorMessage = null;
    _currentCachedStreamInfo = null;
    _cacheBypassKeys.clear();
    _trackResolver.clear();
    LyricService().clearAll(notify: false);
    positionNotifier.value = Duration.zero;
    bufferedPositionNotifier.value = Duration.zero;
    coverManager.setCoverImmediate(null, notify: false);
    coverManager.themeColorNotifier.value = null;
    _queueController.clearCoverProviders();
    _resetShuffle();
    await _cleanupCurrentTempFile();
    _stopStateSaveTimer();
    _pendingRestorePosition = null;
    _pauseListeningTimeTracking();
    notifyListeners();
    await _sessionManager.clear();
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
      _trackResolver.clear();
      LyricService().clearAll(notify: false);
      coverManager.setCoverImmediate(null, notify: false);
      _sessionManager.dispose();
      _historyRecorder.dispose();
      await _engine.dispose();
    } catch (e) {
      print('[PlaybackService] 释放资源失败: $e');
    }
  }

  @override
  void dispose() {
    _resetPreloadState();
    _unbindPreloadDependencyListeners();
    _stabilityTracker.dispose();
    AudioSourceService().removeListener(_syncActiveSourceHealth);
    for (final sub in _engineSubs) {
      sub.cancel();
    }
    _engineSubs.clear();
    PlaybackModeService().removeListener(_precacheNextCover);
    _pauseListeningTimeTracking();
    _stopStateSaveTimer();
    _sessionManager.dispose();
    _historyRecorder.dispose();
    _cleanupCurrentTempFile();
    _engine.dispose();
    ProxyService().stop();
    coverManager.dispose();
    positionNotifier.dispose();
    bufferedPositionNotifier.dispose();
    problemNotifier.dispose();
    sourceHealthNotifier.dispose();
    super.dispose();
  }
}
