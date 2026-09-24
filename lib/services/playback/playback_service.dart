import 'dart:async';
import 'dart:io';

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
import 'playback_session_snapshot.dart';
import 'playback_session_manager.dart';
import 'playback_problem.dart';
import 'playback_stability_tracker.dart';
import 'playback_candidate_planner.dart';
import 'playback_transition.dart';
import 'playback_transition_coordinator.dart';
import 'playback_transaction.dart';
import 'playback_view_state.dart';
import 'playback_history_recorder.dart';
import 'playback_request_router.dart';
import 'playback_session.dart';
import 'playback_performance_metrics.dart';
import 'playback_resolver_registry.dart';
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

class TrackSwitchTiming {
  final Stopwatch totalSw = Stopwatch()..start();
  int settleMs = 0;
  int lookupMs = 0;
  int remoteResolveMs = 0;
  int planPrepareMs = 0;
  int softFadeOutMs = 0;
  int engineStartupMs = 0;
  int engineEnsurePlayerMs = 0;
  int engineMuteMs = 0;
  int engineStopMs = 0;
  int engineSetSourceMs = 0;
  int enginePlayToReadyMs = 0;
  int preparedActivationMs = 0;
  int remoteResolutionAttempts = 0;
  bool audioCacheHit = false;
  bool prefetched = false;
  bool preparedEngineHit = false;
  bool l1MemoryCached = false;
}

class TrackSwitchTransaction {
  final int token;
  final int pendingToken;
  final int requestEpoch;
  final PlaybackSession session;
  final Track track;
  final int? queueEntryId;
  final String reason;
  final String requestedKey;
  final AudioQuality selectedQuality;
  final String qualityStr;
  final PlaybackRequestIntent intent;
  final bool forceRemoteResolution;
  final int queueRevision;
  final TrackSwitchTiming timing;
  final PlaybackTransitionBudget? budget;
  final List<int>? navigationOrder;
  final bool allowActiveFallback;
  final PlaybackSession? previousSession;
  final LyricLoadState? previousLyricState;
  bool budgetExhausted = false;

  TrackSwitchTransaction({
    required this.token,
    required this.pendingToken,
    this.requestEpoch = 0,
    required this.session,
    required this.track,
    required this.queueEntryId,
    required this.reason,
    required this.requestedKey,
    required this.selectedQuality,
    required this.qualityStr,
    required this.intent,
    required this.queueRevision,
    this.forceRemoteResolution = false,
    this.budget,
    this.navigationOrder,
    required this.allowActiveFallback,
    this.previousSession,
    this.previousLyricState,
    TrackSwitchTiming? timing,
  }) : timing = timing ?? TrackSwitchTiming();
}

class _ResolvedTrackSwitchSong {
  final SongDetail songDetail;
  final CachedAudioFileInfo? cacheInfo;
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
  final bool usesCachedFile;
  final PlayableSource source;
  final String? retainedTempFilePath;
  final String? coverRefreshUrl;
  final String themeImageUrl;
  final String themeReason;
  final bool shouldWriteBackgroundCache;
  final String? cacheMetadataRefreshReason;

  const _TrackSwitchPlaybackPlan({
    required this.resolvedSong,
    required this.usesCachedFile,
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
  int? _activeQueueEntryId;
  PlayableSource? _activePlayableSource;
  SongDetail? _activeSong;
  SongDetail? _pendingSong;
  int _activePlaybackToken = 0;
  Track? _pendingTrack;
  int? _pendingQueueEntryId;
  PlaybackRequestIntent? _pendingIntent;
  PlaybackRequestIntent _activeIntent = PlaybackRequestIntent.manual;
  int _pendingSwitchToken = 0;
  String? _pendingReason;
  int? _deferredEngineRetryGeneration;
  final TransactionEventGate<EngineState> _engineStateCommitGate =
      TransactionEventGate<EngineState>();
  int? _scanningRequestEpoch;
  Duration _duration = Duration.zero;
  Duration _position = Duration.zero;
  Duration _bufferedPosition = Duration.zero;
  Duration _presentationDuration = Duration.zero;
  Duration _presentationBufferedPosition = Duration.zero;
  bool _pendingTimelineReady = false;
  bool _desiredPlaying = false;
  String? _errorMessage;
  Track? _lastFailedTrack;
  int? _lastFailedQueueEntryId;
  String? _currentTempFilePath;
  CachedAudioFileInfo? _currentCachedFileInfo;

  void _setCurrentCachedFileInfo(CachedAudioFileInfo? next) {
    final previous = _currentCachedFileInfo;
    if (identical(previous, next)) return;
    if (next != null) CacheService().pinCachedFile(next);
    _currentCachedFileInfo = next;
    if (previous != null && previous.cacheKey != next?.cacheKey) {
      CacheService().unpinCachedFile(previous);
    }
  }

  final Set<String> _cacheBypassKeys = <String>{};
  final PlaybackProblemStore _problemStore = PlaybackProblemStore();
  final PlaybackCandidatePlanner _candidatePlanner =
      const PlaybackCandidatePlanner();
  final PlaybackTransitionCoordinator _transitionCoordinator =
      const PlaybackTransitionCoordinator();
  final PlaybackTransactionGuard _transactionGuard = PlaybackTransactionGuard();
  final PlaybackHistoryRecorder _historyRecorder = PlaybackHistoryRecorder();
  late final PlaybackSessionManager _sessionManager;
  final SourceHealthTracker _sourceHealthTracker = SourceHealthTracker();
  final TrackResolver _trackResolver = TrackResolver();
  final PlaybackPerformanceMetrics _performanceMetrics =
      PlaybackPerformanceMetrics();

  /// 播放稳定性判定：playing 持续满阈值且进度前进才算播放成功。
  /// 门控失败计数清零、历史记录、预载等成功副作用，避免"播 1s 失败
  /// 但计数被清零"的连跳循环。
  late final PlaybackStabilityTracker _stabilityTracker;
  PlaybackSession? _currentSession;
  TrackSwitchTransaction? _currentSwitchTx;
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
  final Map<String, _TrackSwitchPlaybackPlan> _nativePreparedPlans = {};
  int _nextNativePlaybackToken = -1;
  Timer? _preloadTriggerTimer;
  bool _preloadDependencyListenersBound = false;
  bool _autoNextInFlight = false;
  int _autoNextFlightId = 0;
  PlaybackRequestIntent _nativeActivationIntent =
      PlaybackRequestIntent.automatic;

  static const Duration _resolutionRetryDelay = Duration(milliseconds: 300);
  static const Duration _trackSwitchSettleDelay = Duration(milliseconds: 80);
  static const Duration _preloadTriggerDelay = Duration(milliseconds: 600);
  static const Duration _prefetchedSongDetailTtl = Duration(minutes: 5);
  static const Duration _playSongDetailTimeout = Duration(seconds: 12);
  static const Duration _preloadSongDetailTimeout = Duration(seconds: 8);
  static const Duration _lyricSongDetailTimeout = Duration(seconds: 6);
  static const int _maxPrefetchedPlayableDetails = 4;
  static const int _maxCacheBypassKeys = 64;

  // 高频进度更新（解耦 ChangeNotifier，避免重建 widget 树）
  final ValueNotifier<Duration> positionNotifier = ValueNotifier(Duration.zero);
  final ValueNotifier<Duration> presentationPositionNotifier = ValueNotifier(
    Duration.zero,
  );
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
  int? get activeQueueEntryId => _activeQueueEntryId;
  SongDetail? get activeSong => _activeSong;
  int get activePlaybackToken => _activePlaybackToken;
  PlaybackSession? get currentSession => _currentSession;
  Track? get pendingTrack => _pendingTrack;
  int? get pendingSwitchToken =>
      _pendingTrack == null ? null : _pendingSwitchToken;
  String? get pendingReason => _pendingReason;

  Track? get currentTrack => _activeTrack;
  Track? get displayTrack => _activeTrack ?? _pendingTrack;

  List<Track> get queue => _queueController.tracks;
  int get currentIndex => _queueController.currentIndex;
  QueueSource get source => _queueController.source;
  bool get hasQueue => _queueController.isNotEmpty;
  bool get isPlaying => _state == PBState.playing;
  bool get isPaused => _state == PBState.paused;
  bool get isLoading => _state == PBState.loading;
  bool get isTrackSwitchPending => _pendingTrack != null;
  PBState get state => _state;
  LyricLoadState get lyricLoadState => LyricService().currentState;
  LyricSnapshot? get lyricSnapshot => LyricService().currentSnapshot;
  SongDetail? get currentSong => _activeSong;
  String get displayTitle {
    final trackName = _activeTrack?.name;
    if (trackName != null && trackName.isNotEmpty) return trackName;
    final songName = _activeSong?.name;
    if (songName != null && songName.isNotEmpty) return songName;
    final pendingName = _pendingTrack?.name;
    if (pendingName != null && pendingName.isNotEmpty) return pendingName;
    return '';
  }

  String get displayArtist {
    final trackArtist = _activeTrack?.artists;
    if (trackArtist != null && trackArtist.isNotEmpty) return trackArtist;
    final songArtist = _activeSong?.arName;
    if (songArtist != null && songArtist.isNotEmpty) return songArtist;
    final pendingArtist = _pendingTrack?.artists;
    if (pendingArtist != null && pendingArtist.isNotEmpty) return pendingArtist;
    return '';
  }

  String get displayAlbum {
    final trackAlbum = _activeTrack?.album;
    if (trackAlbum != null && trackAlbum.isNotEmpty) return trackAlbum;
    final songAlbum = _activeSong?.alName;
    if (songAlbum != null && songAlbum.isNotEmpty) return songAlbum;
    final pendingAlbum = _pendingTrack?.album;
    if (pendingAlbum != null && pendingAlbum.isNotEmpty) return pendingAlbum;
    return '';
  }

  String? get currentCoverUrl {
    final coverUrl = coverManager.currentUrl;
    if (coverUrl != null && coverUrl.isNotEmpty) return coverUrl;
    final songPic = _activeSong?.pic;
    if (songPic != null && songPic.isNotEmpty) return songPic;
    final trackPic = _activeTrack?.picUrl;
    if (trackPic != null && trackPic.isNotEmpty) return trackPic;
    return null;
  }

  String? get displayCoverUrl {
    if (_activeTrack == null &&
        _pendingTrack != null &&
        _pendingTrack!.picUrl.isNotEmpty) {
      return _pendingTrack!.picUrl;
    }
    return currentCoverUrl;
  }

  String? get pendingCoverUrl {
    if (_pendingTrack != null && _pendingTrack!.picUrl.isNotEmpty) {
      return _pendingTrack!.picUrl;
    }
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

  Duration get duration => _presentationDuration;
  Duration get position => presentationPositionNotifier.value;
  Duration get bufferedPosition => _presentationBufferedPosition;
  PlaybackViewState get viewState {
    final switching = _pendingTrack != null;
    final track = _activeTrack ?? _pendingTrack;
    final generation = _activeTrack != null
        ? _activePlaybackToken
        : _playGeneration;
    final currentSnapshot = LyricService().currentSnapshot;
    final expectedTrackKey = track == null
        ? null
        : '${track.source.name}_${track.id}';
    final snapshot =
        currentSnapshot != null &&
            currentSnapshot.playbackToken == generation &&
            currentSnapshot.trackKey == expectedTrackKey
        ? currentSnapshot
        : null;
    return PlaybackViewState(
      generation: generation,
      track: track,
      song: _activeSong ?? (_activeTrack == null ? _pendingSong : null),
      switchPhase: _viewSwitchPhase,
      desiredPlaying: _desiredPlaying,
      enginePlaying: _engine.isPlaying,
      position: presentationPositionNotifier.value,
      duration: _presentationDuration > Duration.zero
          ? _presentationDuration
          : null,
      bufferedPosition: _presentationBufferedPosition,
      lyricState:
          snapshot?.state ??
          (switching ? LyricLoadState.loading : LyricLoadState.idle),
      lyricSnapshot: snapshot,
    );
  }

  PlaybackSwitchPhase get _viewSwitchPhase {
    if (_pendingTrack != null) {
      if (_state == PBState.error) return PlaybackSwitchPhase.failed;
      return _pendingTimelineReady
          ? PlaybackSwitchPhase.ready
          : (_currentSession?.phase == PlaybackPhase.arming
                ? PlaybackSwitchPhase.loadingSource
                : PlaybackSwitchPhase.resolving);
    }
    return switch (_state) {
      PBState.loading => PlaybackSwitchPhase.loadingSource,
      PBState.playing => PlaybackSwitchPhase.playing,
      PBState.paused => PlaybackSwitchPhase.paused,
      PBState.error => PlaybackSwitchPhase.failed,
      PBState.idle => PlaybackSwitchPhase.idle,
    };
  }

  String? get errorMessage => _errorMessage;
  PlaybackProblem? get currentProblem => problemNotifier.value;
  bool isCurrentPlaybackProblem(PlaybackProblem problem) {
    final current = _problemStore.current;
    return current?.id == problem.id &&
        current?.transactionId == problem.transactionId &&
        _playGeneration == problem.transactionId;
  }

  SourceHealthSnapshot? get sourceHealth => sourceHealthNotifier.value;
  PlaybackPerformanceSnapshot get performanceSnapshot =>
      _performanceMetrics.snapshot;

  /// Clears only the diagnostic counters. Playback state and caches are kept.
  void resetPerformanceMetrics() => _performanceMetrics.reset();

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
    AudioSourceService().addListener(_onAudioSourceConfigChanged);
    _syncActiveSourceHealth();
  }

  void _onEngineEvent(EngineEvent event) {
    if (event.epoch != _playGeneration) {
      if (event is EngineFailureEvent) {
        StructuredLogService.log('[PlaybackService] 丢弃旧纪元引擎事件: ${event.error}');
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
      case EngineSourceCommittedEvent(:final key):
        _onNativeSourceCommitted(key);
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

    PlaybackModeService().addListener(_handlePlaybackModeChanged);
    _bindPreloadDependencyListeners();

    StructuredLogService.log('[PlaybackService] 初始化完成');
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
      StructuredLogService.log('[PlaybackService] 恢复本地播放会话失败: $e');
      return false;
    }
  }

  PlaybackSessionSnapshot? _buildSessionSnapshot() {
    final sessionQueue = _queue.isNotEmpty
        ? List<Track>.from(_queue)
        : (_activeTrack != null ? [_activeTrack!] : const <Track>[]);
    if (sessionQueue.isEmpty) return null;

    final activeIndex = _activeQueueEntryId == null
        ? -1
        : _queueController.indexOfEntryId(_activeQueueEntryId!);
    final currentIndex = _queue.isNotEmpty
        ? (activeIndex >= 0 ? activeIndex : _currentIndex).clamp(
            0,
            sessionQueue.length - 1,
          )
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
      position: presentationPositionNotifier.value,
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
    _activeQueueEntryId = _queueController.currentEntryId;
    _activeSong = null;
    _clearPendingTrack();
    _setLyricLoadState(LyricLoadState.idle, track: _activeTrack, notify: false);
    _errorMessage = null;
    _isAudioSourceNotConfigured = false;
    _duration = Duration.zero;
    _bufferedPosition = Duration.zero;
    _position = snapshot.position;
    _presentationDuration = Duration.zero;
    _presentationBufferedPosition = Duration.zero;
    positionNotifier.value = snapshot.position;
    presentationPositionNotifier.value = snapshot.position;
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
    final session = _currentSession;
    if (_pendingTrack != null && session?.phase == PlaybackPhase.arming) {
      if (_engineStateCommitGate.capture(session!.epoch, s)) return;
    }
    _applyEngineState(s);
  }

  void _applyEngineState(EngineState s, {bool notify = true}) {
    switch (s) {
      case EngineState.playing:
        _updateSessionPhase(PlaybackPhase.playing);
        _state = PBState.playing;
        // 注意：此处不清零 _retriedTrackKey，也不触发
        // 历史记录/预载——这些成功副作用统一等播放稳定后执行
        // （见 _onStablePlayback），避免"起播 1 秒即失败"被误判为成功。
        _errorMessage = null;
        _clearPlaybackProblem();
        _startStateSaveTimer();
        if (Platform.isWindows) DesktopLyricService().setPlayingState(true);
        if (Platform.isAndroid)
          AndroidFloatingLyricService().setPlayingState(true);
        _scheduleSessionPersist();
        _stabilityTracker.onPlaybackStarted(_activePlaybackToken);
        _schedulePreloadNextTrack();
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
    if (notify) notifyListeners();
  }

  /// 播放已稳定（持续 ≥3s 且进度前进）：此时才承认播放成功，
  /// 执行成功副作用并重置失败追踪状态。
  void _onStablePlayback() {
    _retriedTrackKey = null;
    _startListeningTimeTracking();
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
    if (_pendingTrack == null) {
      presentationPositionNotifier.value = pos;
    }
    _updateFloatingLyric();
    _syncPositionToNative(pos);
  }

  void _onDurationChanged(Duration dur) {
    _duration = dur;
    if (_pendingTrack != null) {
      _pendingTimelineReady = dur > Duration.zero;
    } else {
      _presentationDuration = dur;
    }
    notifyListeners();
  }

  void _onBufferedPositionChanged(Duration buffered) {
    _bufferedPosition = buffered;
    bufferedPositionNotifier.value = buffered;
    if (_pendingTrack == null) {
      _presentationBufferedPosition = buffered;
    }
  }

  void _onEngineError(EngineError error) {
    // 纪元守卫：错误携带引擎源头纪元，属于旧纪元的迟到错误直接丢弃，
    // 避免旧歌错误触发新歌的重试/跳歌/报错。
    final belongsToCurrentTransition = error.epoch == _playGeneration;
    final belongsToPreservedActive =
        _pendingTrack == null &&
        _activeTrack != null &&
        error.epoch == _activePlaybackToken;
    if (!belongsToCurrentTransition && !belongsToPreservedActive) {
      StructuredLogService.log('[PlaybackService] 丢弃旧纪元引擎错误: $error');
      return;
    }
    _performanceMetrics.recordEngineFailure();
    final failedDuringArming = _currentSession?.phase == PlaybackPhase.arming;
    _updateSessionPhase(PlaybackPhase.failed);
    final track = _pendingTrack ?? currentTrack;
    if (track == null || _state == PBState.error) return;
    final failureIntent = _pendingIntent ?? _activeIntent;

    final trackKey = _buildTrackIdentity(track);
    final cacheQuality = _currentCachedFileInfo?.metadata.quality;
    final shouldRetryWithoutCache =
        cacheQuality != null && _retriedTrackKey != trackKey;
    final canRetry =
        shouldRetryWithoutCache ||
        (_canRetryOnError(error) && _retriedTrackKey != trackKey);

    if (canRetry) {
      _performanceMetrics.recordEngineRetry();
      _retriedTrackKey = trackKey;
      if (cacheQuality != null) {
        StructuredLogService.log('[PlaybackService] 缓存流播放失败，绕过当前缓存后重试: $error');
      } else {
        StructuredLogService.log('[PlaybackService] 引擎错误，强制重新解析后重试: $error');
      }
      final current = _pendingTrack ?? currentTrack;
      if (current == null || _buildTrackIdentity(current) != trackKey) return;
      if (cacheQuality != null) {
        _rememberCacheBypassKey(
          _cachePlaybackKey(current, cacheQuality),
          reason: 'engine-retry',
        );
        _setCurrentCachedFileInfo(null);
      }
      final switchTx = _currentSwitchTx;
      if (switchTx != null &&
          switchTx.token == error.epoch &&
          switchTx.budget != null &&
          failedDuringArming) {
        _deferredEngineRetryGeneration = error.epoch;
        return;
      }
      final requestEpoch = _requestRouter.begin();
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
    final isIntermediateScanFailure =
        _scanningRequestEpoch != null &&
        _currentSession?.requestEpoch == _scanningRequestEpoch;
    if (emitEffect && !isIntermediateScanFailure) {
      onPlaybackFailure?.call(problem);
    }
  }

  void _clearPlaybackProblem() {
    if (_problemStore.clear()) {
      problemNotifier.value = null;
    }
  }

  PlaybackCandidateAttemptResult _candidateFailureResult({
    TrackSwitchTransaction? transaction,
    bool engineFailure = false,
    bool allowActiveFallback = false,
  }) {
    _engineStateCommitGate.discard(transaction?.token);
    final mayRestoreActive =
        transaction?.allowActiveFallback ?? allowActiveFallback;
    if (!engineFailure &&
        mayRestoreActive &&
        _activeTrack != null &&
        _engine.isPlaying &&
        (_pendingTrack == null ||
            !_matchesTrackIdentity(
              _activeTrack,
              _buildTrackIdentity(_pendingTrack!),
            ))) {
      _state = PBState.playing;
      _errorMessage = null;
      _clearPendingTrack();
      _currentSession =
          transaction?.previousSession?.copyWith(
            phase: PlaybackPhase.playing,
          ) ??
          PlaybackSession(
            epoch: _activePlaybackToken,
            requestEpoch: _requestRouter.currentEpoch,
            trackKey: _buildTrackIdentity(_activeTrack!),
            phase: PlaybackPhase.playing,
          );
      _currentSwitchTx = null;
      final activeSong = _activeSong;
      LyricService().bindCurrentTrack(
        track: _activeTrack!,
        playbackToken: _activePlaybackToken,
        song: activeSong,
        state:
            transaction?.previousLyricState ??
            (activeSong != null && _hasAnyLyricPayload(activeSong)
                ? LyricLoadState.ready
                : LyricLoadState.idle),
        notify: false,
      );
      notifyListeners();
    }
    if (transaction?.budgetExhausted ?? false) {
      return PlaybackCandidateAttemptResult(
        PlaybackCandidateAttemptStatus.budgetExhausted,
        message: _errorMessage,
      );
    }
    final problem = _problemStore.current;
    final sourceFailure =
        problem?.kind == PlaybackProblemKind.sourceNotConfigured ||
        problem?.kind == PlaybackProblemKind.sourceInvalid;
    return PlaybackCandidateAttemptResult(
      sourceFailure
          ? PlaybackCandidateAttemptStatus.sourceFailure
          : engineFailure
          ? PlaybackCandidateAttemptStatus.engineFailure
          : PlaybackCandidateAttemptStatus.trackFailure,
      message: problem?.message ?? _errorMessage,
    );
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
      case LxRuntimeFailureKind.invalidTrackIdentifier:
        return PlaybackProblemKind.resourceUnavailable;
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
      case LxRuntimeFailureKind.invalidTrackIdentifier:
        return const {};
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
      case LxRuntimeFailureKind.invalidTrackIdentifier:
        return failure?.message ?? '歌曲标识不完整，请重新搜索或同步';
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

  void _onAudioSourceConfigChanged() {
    _syncActiveSourceHealth();
    _trackResolver.clear();
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
      case LxRuntimeFailureKind.invalidTrackIdentifier:
        return SourceHealthFailureKind.trackSpecific;
      case LxRuntimeFailureKind.requestFailed:
        return SourceHealthFailureKind.transientTimeout;
      case null:
        return SourceHealthFailureKind.trackSpecific;
    }
  }

  bool _shouldRetryResolutionFailure(LxRuntimeFailure? failure) {
    switch (failure?.kind) {
      case LxRuntimeFailureKind.timeout:
      case LxRuntimeFailureKind.requestFailed:
      case LxRuntimeFailureKind.notReady:
      case null:
        return true;
      case LxRuntimeFailureKind.scriptRejected:
      case LxRuntimeFailureKind.invalidTrackIdentifier:
        return false;
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
    if (_pendingTrack != null || _autoNextInFlight) return;
    final flightId = ++_autoNextFlightId;
    _autoNextInFlight = true;
    final completedTrack = _activeTrack ?? _trackAtQueuePointer();
    _position = Duration.zero;
    StructuredLogService.event(
      'playback.auto_next_requested',
      fields: {
        'flight_id': flightId,
        'generation': _playGeneration,
        'track': completedTrack == null
            ? null
            : _buildTrackIdentity(completedTrack),
        'queue_index': _currentIndex,
        'queue_length': _queue.length,
      },
    );
    unawaited(_runAutoNextFlight(flightId));
  }

  void _onNativeSourceCommitted(String? key) {
    final entryId = _queueEntryIdFromNativeKey(key);
    if (entryId == null || entryId == _activeQueueEntryId) return;
    final queueIndex = _queueController.indexOfEntryId(entryId);
    if (queueIndex < 0) {
      StructuredLogService.log('[PlaybackService] 原生播放源未映射到业务队列: $key');
      return;
    }

    final pendingEntryId = _pendingQueueEntryId;
    if (pendingEntryId != null && pendingEntryId != entryId) {
      StructuredLogService.event(
        'playback.stale_native_source_ignored',
        level: LogLevel.warning,
        fields: {
          'native_entry_id': entryId,
          'pending_entry_id': pendingEntryId,
          'generation': _playGeneration,
        },
      );
      return;
    }

    final track = _queue[queueIndex];
    final quality = AudioQualityService().currentQuality;
    final plan =
        _nativePreparedPlans.remove(key) ??
        _takePrefetchedPlayablePlan(track, quality);
    if (plan == null) {
      StructuredLogService.log('[PlaybackService] 原生播放源缺少预取计划，忽略切歌事件: $key');
      return;
    }

    _autoNextFlightId++;
    _autoNextInFlight = false;
    _resetPreloadState(clearPrefetchedDetails: false);
    final matchingTx = _currentSwitchTx;
    _queueController.commitEntry(
      entryId,
      shuffleTraversalEntryIds: matchingTx?.navigationOrder,
    );
    final activationIntent = _nativeActivationIntent;
    _nativeActivationIntent = PlaybackRequestIntent.automatic;
    final playbackToken =
        matchingTx != null &&
            matchingTx.queueEntryId == entryId &&
            _transactionGuard.isCurrent(matchingTx.token)
        ? matchingTx.token
        : _nextNativePlaybackToken--;
    _activePlayableSource = plan.source;
    _setCurrentCachedFileInfo(plan.resolvedSong.cacheInfo);
    unawaited(_replaceCurrentTempFilePath(plan.retainedTempFilePath));
    _stableCacheTrack = null;
    _stableCacheSong = null;
    _stableCacheQuality = null;
    if (plan.shouldWriteBackgroundCache) {
      _stableCacheTrack = track;
      _stableCacheSong = plan.resolvedSong.songDetail;
      _stableCacheQuality = quality.value;
    }
    _commitActivePresentation(
      track,
      queueEntryId: entryId,
      songDetail: plan.resolvedSong.songDetail,
      playbackToken: playbackToken,
      intent: activationIntent,
    );
    _scheduleCoverRefreshIfNeeded(track, plan);
    _scheduleThemeRefreshIfNeeded(track, plan);
    _loadLyricsForFloatingDisplay();
    _schedulePreloadNextTrack();
    _scheduleSessionPersist();
    notifyListeners();
  }

  void _scheduleCoverRefreshIfNeeded(
    Track track,
    _TrackSwitchPlaybackPlan plan,
  ) {
    final url = plan.coverRefreshUrl;
    if (url != null && url.isNotEmpty) {
      _scheduleCoverRefresh(track, url, reason: plan.themeReason);
    }
  }

  void _scheduleThemeRefreshIfNeeded(
    Track track,
    _TrackSwitchPlaybackPlan plan,
  ) {
    if (plan.themeImageUrl.isNotEmpty) {
      _scheduleThemeColorRefresh(
        track,
        plan.themeImageUrl,
        reason: plan.themeReason,
      );
    }
  }

  Future<void> _runAutoNextFlight(int flightId) async {
    try {
      await _playNextAuto();
    } catch (error) {
      StructuredLogService.event(
        'playback.auto_next_failed',
        level: LogLevel.warning,
        fields: {
          'flight_id': flightId,
          'generation': _playGeneration,
          'state': _state.name,
          'engine_playing': _engine.isPlaying,
        },
        error: error,
      );
    } finally {
      if (_autoNextFlightId == flightId) {
        _autoNextInFlight = false;
      }
    }
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
    _invalidatePreparedWindow();
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
      _invalidatePreparedWindow(reschedule: true);
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
      _invalidatePreparedWindow(reschedule: true);
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
      _invalidatePreparedWindow(reschedule: true);
      notifyListeners();
      _scheduleSessionPersist();
    });
  }

  /// 跳转到队列中某首
  Future<void> jumpTo(int index) async {
    final requestEpoch = _requestRouter.begin();
    final track = index >= 0 && index < _queue.length ? _queue[index] : null;
    final entryId = _queueController.entryIdAt(index);
    if (track == null || entryId == null) return;
    _resetPreloadState();
    _pendingRestorePosition = null;
    await _attemptTrackSwitch(
      reason: 'jump-to',
      requestEpoch: requestEpoch,
      candidateTrack: track,
      candidateEntryId: entryId,
    );
    _scheduleSessionPersist();
  }

  /// 移除队列中某首
  Future<void> removeAt(int index) async {
    final removedEntryId = _queueController.entryIdAt(index);
    final removesActive =
        removedEntryId != null && removedEntryId == _activeQueueEntryId;
    final requestEpoch = removesActive ? _requestRouter.begin() : null;
    final removal = await _commands.enqueue(() async {
      _resetPreloadState();
      _pendingRestorePosition = null;
      final removal = _queueController.removeAt(index);
      if (!removal.removed) return removal;
      _invalidatePreparedWindow(reschedule: !removal.removedCurrent);
      if (removal.becameEmpty) {
        await _engine.stop();
        _state = PBState.idle;
        _activeTrack = null;
        _activeQueueEntryId = null;
        _activeSong = null;
        _clearPendingTrack();
        _duration = Duration.zero;
        _position = Duration.zero;
        _bufferedPosition = Duration.zero;
        _presentationDuration = Duration.zero;
        _presentationBufferedPosition = Duration.zero;
        positionNotifier.value = Duration.zero;
        bufferedPositionNotifier.value = Duration.zero;
        coverManager.setCoverImmediate(null, notify: false);
        coverManager.themeColorNotifier.value = null;
        _setLyricLoadState(LyricLoadState.idle, notify: false);
      }
      notifyListeners();
      _scheduleSessionPersist();
      return removal;
    });
    if (removal.removedCurrent &&
        !removal.becameEmpty &&
        requestEpoch != null &&
        _requestRouter.isCurrent(requestEpoch)) {
      await _runNavigationTransition(
        requestEpoch: requestEpoch,
        intent: PlaybackTransitionIntent.removeCurrent,
        direction: PlaybackTransitionDirection.forward,
        reason: 'remove-current',
      );
    }
  }

  /// 拖拽排序
  Future<void> reorder(int oldIndex, int newIndex) {
    return _commands.enqueue(() async {
      _resetPreloadState();
      _pendingRestorePosition = null;
      if (!_queueController.reorder(oldIndex, newIndex)) return;
      _invalidatePreparedWindow(reschedule: true);
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
      _pendingRestorePosition = null;
      _queueController.clear();
      await _engine.stop();
      _state = PBState.idle;
      _activeTrack = null;
      _activeQueueEntryId = null;
      _activeSong = null;
      _clearPendingTrack();
      _duration = Duration.zero;
      _position = Duration.zero;
      _bufferedPosition = Duration.zero;
      _presentationDuration = Duration.zero;
      _presentationBufferedPosition = Duration.zero;
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
    _desiredPlaying = true;
    notifyListeners();
    if (_pendingTrack != null) {
      return;
    }
    // 预载态：播放器尚未初始化，走完整播放
    if (_state == PBState.idle && currentTrack != null) {
      if (_queue.isNotEmpty && _currentIndex >= 0) {
        final requestEpoch = _requestRouter.begin();
        final restorePosition = _takePendingRestorePosition();
        await _playCurrentTrack(
          reason: 'resume',
          requestEpoch: requestEpoch,
          autoPlay: true,
          initialPosition: restorePosition,
        );
        _desiredPlaying = true;
        if (restorePosition != null && _requestRouter.isCurrent(requestEpoch)) {
          _position = restorePosition;
          positionNotifier.value = restorePosition;
          presentationPositionNotifier.value = restorePosition;
          if (!_engine.isPlaying) {
            await _engine.resume();
          }
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
    _desiredPlaying = false;
    notifyListeners();
    await _engine.pause();
    _pauseListeningTimeTracking();
    _scheduleSessionPersist();
  }

  Future<void> seek(Duration position) async {
    if (!viewState.canSeek) return;
    await _engine.seek(position);
    _position = position;
    positionNotifier.value = position;
    presentationPositionNotifier.value = position;
    _syncPositionToNative(position, force: true);
    _pendingRestorePosition = null;
    _scheduleSessionPersist();
  }

  Future<void> next() async {
    final requestEpoch = _requestRouter.begin();
    await _runNavigationTransition(
      requestEpoch: requestEpoch,
      intent: PlaybackTransitionIntent.manualAdvance,
      direction: PlaybackTransitionDirection.forward,
      reason: 'manual-next',
    );
  }

  Future<void> previous() async {
    final requestEpoch = _requestRouter.begin();
    await _runNavigationTransition(
      requestEpoch: requestEpoch,
      intent: PlaybackTransitionIntent.manualAdvance,
      direction: PlaybackTransitionDirection.backward,
      reason: 'manual-previous',
    );
  }

  Future<void> stop() async {
    _desiredPlaying = false;
    _invalidateCurrentPlayback();
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
    _presentationDuration = Duration.zero;
    _presentationBufferedPosition = Duration.zero;
    positionNotifier.value = Duration.zero;
    presentationPositionNotifier.value = Duration.zero;
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
    _desiredPlaying ? await pause() : await resume();
  }

  Future<void> retryCurrentTrack({
    PlaybackProblem? expectedProblem,
    bool forceRemoteResolution = false,
  }) async {
    final requestEpoch = _requestRouter.begin();
    if (expectedProblem != null && !isCurrentPlaybackProblem(expectedProblem)) {
      return;
    }
    final problemTrack = expectedProblem?.track ?? _problemStore.current?.track;
    final retryTrack =
        _pendingTrack ?? _lastFailedTrack ?? problemTrack ?? _activeTrack;
    if (retryTrack == null) return;
    final retryEntryId =
        _pendingQueueEntryId ??
        _lastFailedQueueEntryId ??
        (_matchesTrackIdentity(
              _queueController.currentTrack,
              _buildTrackIdentity(retryTrack),
            )
            ? _queueController.currentEntryId
            : null);
    _state = PBState.loading;
    _errorMessage = null;
    _isAudioSourceNotConfigured = false;
    notifyListeners();
    await _attemptTrackSwitch(
      reason: 'manual-retry',
      intent: PlaybackRequestIntent.retry,
      requestEpoch: requestEpoch,
      forceRemoteResolution: forceRemoteResolution,
      candidateTrack: retryTrack,
      candidateEntryId: retryEntryId,
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
    _activeQueueEntryId = null;
    _activeSong = null;
    _activePlaybackToken++;
    _clearPendingTrack();
    _state = PBState.idle;
    _duration = Duration.zero;
    _position = Duration.zero;
    _presentationDuration = Duration.zero;
    _presentationBufferedPosition = Duration.zero;
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
        queueEntryId: _queueController.currentEntryId,
        reason: 'radio',
        intent: PlaybackRequestIntent.manual,
      );
      notifyListeners();
      await _playWithSoftSwitch(streamUrl);
      if (!_canStartPlayback(gen)) return;
      _commitActivePresentation(
        radioTrack,
        queueEntryId: _queueController.currentEntryId,
        playbackToken: gen,
        notify: false,
      );
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
    required int? queueEntryId,
    required String reason,
    required PlaybackRequestIntent intent,
    Duration initialPosition = Duration.zero,
  }) {
    _pendingTrack = track;
    _pendingQueueEntryId = queueEntryId;
    _pendingReason = reason;
    _pendingIntent = intent;
    _pendingSong = null;
    _pendingTimelineReady = false;
    if (_activeTrack == null) {
      _position = initialPosition;
      _duration = Duration.zero;
      _bufferedPosition = Duration.zero;
      _presentationDuration = Duration.zero;
      _presentationBufferedPosition = Duration.zero;
      positionNotifier.value = initialPosition;
      bufferedPositionNotifier.value = Duration.zero;
      presentationPositionNotifier.value = initialPosition;
    }
    _pendingSwitchToken++;
  }

  void _clearPendingTrack() {
    _pendingTrack = null;
    _pendingQueueEntryId = null;
    _pendingSong = null;
    _pendingTimelineReady = false;
    _pendingReason = null;
    _pendingIntent = null;
  }

  void _commitActivePresentation(
    Track track, {
    required int? queueEntryId,
    SongDetail? songDetail,
    required int playbackToken,
    PlaybackRequestIntent intent = PlaybackRequestIntent.manual,
    bool notify = true,
  }) {
    _activeTrack = track;
    _activeQueueEntryId = queueEntryId;
    _activeSong = songDetail;
    _activePlaybackToken = playbackToken;
    _activeIntent = intent;
    _lastFailedTrack = null;
    _lastFailedQueueEntryId = null;
    _clearPendingTrack();
    _presentationDuration = _duration;
    _presentationBufferedPosition = _bufferedPosition;
    presentationPositionNotifier.value = _position;
    _preloadedTrack = null;
    _primeDisplayStateForTrack(track);
    final deferredState = _engineStateCommitGate.take(playbackToken);
    if (deferredState != null) {
      _applyEngineState(deferredState, notify: false);
    }
    if (_state == PBState.playing) {
      _stabilityTracker.onPlaybackStarted(playbackToken);
    }
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
    Duration? initialPosition,
    Track? candidateTrack,
    int? candidateEntryId,
    PlaybackTransitionBudget? budget,
    List<int>? navigationOrder,
    bool allowActiveFallback = true,
  }) {
    final track = candidateTrack ?? _trackAtQueuePointer() ?? _activeTrack;
    if (track == null) return null;
    final previousSession = _currentSession;
    final previousLyricSnapshot = LyricService().currentSnapshot;
    final previousLyricState =
        _activeTrack != null &&
            previousLyricSnapshot?.playbackToken == _activePlaybackToken &&
            previousLyricSnapshot?.trackKey ==
                _buildTrackIdentity(_activeTrack!)
        ? previousLyricSnapshot?.state
        : null;
    final queueEntryId =
        candidateEntryId ??
        (_trackAtQueuePointer() == null
            ? _activeQueueEntryId
            : _queueController.currentEntryId);

    _resetPreloadState(clearPrefetchedDetails: false);
    _preloadedTrack = null;
    _stagePendingTrack(
      track,
      queueEntryId: queueEntryId,
      reason: reason,
      intent: intent,
      initialPosition: initialPosition ?? Duration.zero,
    );
    final token = _transactionGuard.begin();
    _engineStateCommitGate.arm(token);
    LyricService().bindCurrentTrack(
      track: track,
      playbackToken: token,
      song: null,
      state: LyricLoadState.loading,
      notify: false,
    );
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
      queueEntryId: queueEntryId,
      reason: reason,
      requestedKey: _buildTrackIdentity(track),
      selectedQuality: selectedQuality,
      qualityStr: selectedQuality.value,
      intent: intent,
      queueRevision: _queueController.structureRevision,
      forceRemoteResolution: forceRemoteResolution,
      budget: budget,
      navigationOrder: navigationOrder,
      allowActiveFallback: allowActiveFallback,
      previousSession: previousSession,
      previousLyricState: previousLyricState,
    );
    _currentSession = tx.session;
    _currentSwitchTx = tx;

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
    if (!_transactionGuard.isCurrent(tx.token)) return true;
    if (tx.requestEpoch != 0 && !_requestRouter.isCurrent(tx.requestEpoch)) {
      return true;
    }
    if (tx.pendingToken != _pendingSwitchToken) return true;
    return _pendingQueueEntryId != tx.queueEntryId ||
        !_matchesTrackIdentity(_pendingTrack, tx.requestedKey);
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
    _scanningRequestEpoch = null;
    _engineStateCommitGate.discard();
    _stabilityTracker.onPlaybackInterrupted();
    _stableCacheTrack = null;
    _stableCacheSong = null;
    _stableCacheQuality = null;
    _updateSessionPhase(PlaybackPhase.idle);
  }

  void _cancelPendingTrackTransition() {
    if (_pendingTrack == null && _scanningRequestEpoch == null) return;
    _requestRouter.begin();
    _transactionGuard.begin();
    _pendingSwitchToken++;
    _scanningRequestEpoch = null;
    _engineStateCommitGate.discard();
    _clearPendingTrack();
    if (_engine.isPlaying && _activeTrack != null) {
      _state = PBState.playing;
    }
  }

  Future<_ResolvedTrackSwitchSong?> _resolveSongDetailStage(
    TrackSwitchTransaction tx,
    bool Function() isStale,
  ) async {
    final track = tx.track;
    _setCurrentCachedFileInfo(null);
    final cachePlaybackKey = _cachePlaybackKey(track, tx.qualityStr);
    final lookupSw = Stopwatch()..start();
    final lookup = await _trackResolver.lookupLocalOrCache(
      track: track,
      quality: tx.qualityStr,
      skipCache:
          tx.forceRemoteResolution ||
          _cacheBypassKeys.contains(cachePlaybackKey),
    );
    tx.timing.lookupMs = lookupSw.elapsedMilliseconds;
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
      StructuredLogService.log(
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
      return null;
    }

    final lxSourceFingerprint = _activeLxSourceFingerprint();
    final resolverFingerprint = _resolverFingerprintFor(track);
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

    TrackResolutionResult? resolution;
    final maxResolutionAttempts = _retriedTrackKey == _buildTrackIdentity(track)
        ? 1
        : 2;
    var isSameLxSource =
        lxSourceFingerprint != null &&
        _activeLxSourceFingerprint() == lxSourceFingerprint;

    for (var attempt = 0; attempt < maxResolutionAttempts; attempt++) {
      if (attempt > 0 && lxSourceFingerprint != null) {
        final retryAllowed = _sourceHealthTracker.allowRequest(
          lxSourceFingerprint,
        );
        sourceHealthNotifier.value = _sourceHealthTracker.snapshot(
          lxSourceFingerprint,
        );
        if (!retryAllowed) break;
      }

      if (tx.forceRemoteResolution) {
        _trackResolver.invalidateTrack(
          track,
          quality: tx.selectedQuality,
          resolverFingerprint: resolverFingerprint,
        );
      }

      final transitionBudget = tx.budget;
      if (transitionBudget != null &&
          !transitionBudget.consumeRemoteRequest()) {
        tx.budgetExhausted = true;
        break;
      }
      final resolveTimeout = transitionBudget == null
          ? _playSongDetailTimeout
          : (transitionBudget.remaining() < _playSongDetailTimeout
                ? transitionBudget.remaining()
                : _playSongDetailTimeout);
      if (resolveTimeout <= Duration.zero) {
        tx.budgetExhausted = true;
        break;
      }

      final remoteSw = Stopwatch()..start();
      tx.timing.remoteResolutionAttempts++;
      resolution = await _trackResolver.resolve(
        songId: track.id,
        quality: tx.selectedQuality,
        source: track.source,
        sourceIds: track.sourceIds,
        title: track.name,
        artist: track.artists,
        timeout: resolveTimeout,
        fetchLyrics: false,
        resolverFingerprint: resolverFingerprint,
        skipMemoryCache: attempt > 0 || tx.forceRemoteResolution,
        acceptResult: () => !isStale(),
      );
      tx.timing.remoteResolveMs += remoteSw.elapsedMilliseconds;
      if (resolution.isL1CacheHit) {
        tx.timing.l1MemoryCached = true;
      }
      if (isStale()) {
        if (lxSourceFingerprint != null) {
          _sourceHealthTracker.cancelRequest(lxSourceFingerprint);
          _syncActiveSourceHealth();
        }
        return null;
      }

      isSameLxSource =
          lxSourceFingerprint != null &&
          _activeLxSourceFingerprint() == lxSourceFingerprint;
      if (lxSourceFingerprint != null && !isSameLxSource) {
        _sourceHealthTracker.cancelRequest(lxSourceFingerprint);
        // The resolver is bound to the source snapshot captured before the
        // request. Never commit a URL resolved by an older active source.
        _syncActiveSourceHealth();
        return null;
      }

      if (resolution.isPlayable) {
        if (isSameLxSource) {
          _recordSourceResolutionSuccess(lxSourceFingerprint);
        }
        break;
      }

      if (isSameLxSource) {
        _recordSourceResolutionFailure(
          lxSourceFingerprint,
          resolution.lxFailure,
        );
      }

      if (attempt + 1 < maxResolutionAttempts &&
          _shouldRetryResolutionFailure(resolution.lxFailure)) {
        _trackResolver.invalidateTrack(
          track,
          quality: tx.selectedQuality,
          resolverFingerprint: resolverFingerprint,
        );
        _state = PBState.loading;
        _errorMessage = '播放地址无效，正在重新获取...';
        _logPlaybackDebug(
          '[PlaybackService] 解析失败，执行一次重试: ${_trackLogKey(track)} '
          'failure=${resolution.lxFailure?.kind.name ?? 'unknown'}',
          toDeveloperPanel: true,
        );
        notifyListeners();
        await Future.delayed(_resolutionRetryDelay);
        continue;
      }
      break;
    }

    final songDetail = resolution?.detail;
    if (resolution == null) {
      if (isSameLxSource) {
        _sourceHealthTracker.cancelRequest(lxSourceFingerprint!);
        _syncActiveSourceHealth();
      }
      return null;
    }
    if (songDetail == null || songDetail.url.isEmpty) {
      final lxFailure = isSameLxSource ? resolution.lxFailure : null;
      final sourceHealth = !isSameLxSource
          ? null
          : _sourceHealthTracker.snapshot(lxSourceFingerprint!);
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
      return null;
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
      return _TrackSwitchPlaybackPlan(
        resolvedSong: resolvedSong,
        usesCachedFile: true,
        source: LocalFilePlayableSource(
          cacheInfo.filePath,
          originalUrl: cacheInfo.metadata.originalUrl,
        ),
        retainedTempFilePath: null,
        coverRefreshUrl: cacheInfo.metadata.picUrl,
        themeImageUrl: cacheInfo.metadata.picUrl,
        themeReason: 'cache-hit',
        shouldWriteBackgroundCache: false,
        cacheMetadataRefreshReason: null,
      );
    }

    if (track.source == MusicSource.local) {
      final filePath = songDetail.url;
      return _TrackSwitchPlaybackPlan(
        resolvedSong: resolvedSong,
        usesCachedFile: false,
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
        usesCachedFile: false,
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
        usesCachedFile: false,
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
      usesCachedFile: false,
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
    if (isStale()) return null;

    if (plan.usesCachedFile && plan.resolvedSong.cacheInfo != null) {
      final playedFromStream = await _playCachedFileSource(
        plan.resolvedSong.cacheInfo!,
        autoPlay: autoPlay,
        initialPosition: initialPosition,
        preload: preload,
        transaction: tx,
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
          transaction: tx,
        );
      }
    } else {
      await _playPlayableSourceWithSoftSwitch(
        plan.source,
        autoPlay: autoPlay,
        initialPosition: initialPosition,
        preload: preload,
        transaction: tx,
      );
    }
    if (isStale()) {
      _setCurrentCachedFileInfo(null);
      final retainedTempFilePath = committedPlan.retainedTempFilePath;
      await _deleteTempFilePath(retainedTempFilePath);
      return null;
    }
    await _replaceCurrentTempFilePath(committedPlan.retainedTempFilePath);
    return isStale() ? null : committedPlan;
  }

  bool _commitPresentationStage(
    TrackSwitchTransaction tx,
    _TrackSwitchPlaybackPlan plan,
    bool Function() isStale,
  ) {
    if (isStale()) return false;

    final track = tx.track;
    final songDetail = _pendingSong ?? plan.resolvedSong.songDetail;
    var committedEntryId = tx.queueEntryId;
    if (committedEntryId != null &&
        !_queueController.commitEntry(
          committedEntryId,
          shuffleTraversalEntryIds: tx.navigationOrder,
        )) {
      committedEntryId = null;
    }
    _activePlayableSource = plan.source;
    _commitActivePresentation(
      track,
      queueEntryId: committedEntryId,
      songDetail: songDetail,
      playbackToken: tx.token,
      intent: tx.intent,
    );
    final timing = tx.timing;
    timing.audioCacheHit = plan.usesCachedFile;
    _performanceMetrics.recordSwitch(
      PlaybackTimingSample(
        totalMs: timing.totalSw.elapsedMilliseconds,
        settleMs: timing.settleMs,
        lookupMs: timing.lookupMs,
        remoteResolveMs: timing.remoteResolveMs,
        planPrepareMs: timing.planPrepareMs,
        softFadeOutMs: timing.softFadeOutMs,
        engineStartupMs: timing.engineStartupMs,
        engineSetSourceMs: timing.engineSetSourceMs,
        enginePlayToReadyMs: timing.enginePlayToReadyMs,
        preparedActivationMs: timing.preparedActivationMs,
        prefetched: timing.prefetched,
        preparedEngineHit: timing.preparedEngineHit,
        l1MemoryCached: timing.l1MemoryCached,
        audioCacheHit: timing.audioCacheHit,
        remoteResolutionAttempts: timing.remoteResolutionAttempts,
      ),
    );
    debugPrint('''
🎵 [切歌耗时剖析] ========================================
歌曲: 《${track.name}》 - ${track.artists} (源: ${track.source.name}, 音质: ${tx.qualityStr})
模式: ${plan.usesCachedFile ? "⚡ 缓存命中" : "🌐 远程网络"} | 预取计划: ${timing.prefetched ? "命中" : "未命中"} | 引擎预备: ${timing.preparedEngineHit ? "命中" : "未命中"}
阶段细分:
  ├─ 0. 切歌防抖等待(Settle):     ${timing.settleMs} ms
  ├─ 1. 本地缓存/文件检索(含校验): ${timing.lookupMs} ms
  ├─ 2. 远程音源接口解析(网络):   ${timing.remoteResolveMs} ms${timing.l1MemoryCached ? ' (⚡ L1内存池命中)' : ''}
  ├─ 3. 播放源计划准备:           ${timing.planPrepareMs} ms
  ├─ 4. 引擎单次静音:              ${timing.softFadeOutMs} ms
  └─ 5. 引擎装载与缓冲出声:       ${timing.engineStartupMs} ms
      ├─ 初始化播放器:             ${timing.engineEnsurePlayerMs} ms
      ├─ 停止旧源:                 ${timing.engineStopMs} ms
      ├─ 装载新源:                 ${timing.engineSetSourceMs} ms
      ├─ Play 到 Ready:            ${timing.enginePlayToReadyMs} ms
      └─ 预备槽位激活:             ${timing.preparedActivationMs} ms
================================ 🏁 真实总耗时: ${timing.totalSw.elapsedMilliseconds} ms
''');
    _stableCacheTrack = null;
    _stableCacheSong = null;
    _stableCacheQuality = null;
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

    if (plan.usesCachedFile && plan.resolvedSong.shouldRefreshCachedMetadata) {
      return true;
    }

    if (plan.shouldWriteBackgroundCache) {
      _stableCacheTrack = track;
      _stableCacheSong = songDetail;
      _stableCacheQuality = tx.qualityStr;
      return true;
    }

    if (_shouldScheduleDeferredSupplementalRefresh(songDetail)) {
      return true;
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
    return true;
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
    required int playbackToken,
  }) {
    return LyricRequestAdapter(
      fetch: LyricRequestFetchAdapter(
        useLyricOnlyFetch: _shouldUseLyricOnlySupplementalFetch(track),
        allowFullDetailFallback:
            _shouldAllowFullDetailFallbackForLyricOnlyFetch(track),
        emptyResultIsAuthoritative: false,
        fetchLyricOnlyDetail: () {
          return MusicService()
              .fetchLyricOnlySongDetail(
                songId: track.id,
                source: track.source,
                sourceIds: track.sourceIds,
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
          sourceIds: track.sourceIds,
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
        currentSong: () {
          if (_pendingTrack != null &&
              _transactionGuard.isCurrent(playbackToken) &&
              _matchesTrackIdentity(
                _pendingTrack,
                _buildTrackIdentity(track),
              )) {
            return _pendingSong;
          }
          if (_activePlaybackToken == playbackToken &&
              _matchesTrackIdentity(_activeTrack, _buildTrackIdentity(track))) {
            return _activeSong;
          }
          return null;
        },
        applyResolvedSongDetail: (detail) {
          if (_pendingTrack != null &&
              _transactionGuard.isCurrent(playbackToken) &&
              _matchesTrackIdentity(
                _pendingTrack,
                _buildTrackIdentity(track),
              )) {
            _pendingSong = detail;
            notifyListeners();
            return;
          }
          if (_activePlaybackToken == playbackToken &&
              _matchesTrackIdentity(_activeTrack, _buildTrackIdentity(track))) {
            _applyResolvedSongDetail(detail);
          }
        },
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
              sourceIds: track.sourceIds,
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
    final resolver = _resolverFingerprintFor(track) ?? 'unavailable';
    return '${_buildTrackIdentity(track)}_${quality}_$resolver';
  }

  String? _resolverFingerprintFor(Track track) {
    return PlaybackResolverRegistry().fingerprintFor(track.source);
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

  void _stagePendingPlanPresentation(
    TrackSwitchTransaction tx,
    _TrackSwitchPlaybackPlan plan,
    bool Function() isStale,
  ) {
    if (isStale()) return;
    final song = plan.resolvedSong.songDetail;
    _pendingSong = song;
    final shouldRequest = _shouldRequestLyricsForPlan(
      tx.track,
      song,
      plan,
      tx.qualityStr,
    );
    final initialState = shouldRequest
        ? LyricLoadState.loading
        : _deriveLyricLoadStateForPlan(tx.track, song, plan, tx.qualityStr);
    LyricService().bindCurrentTrack(
      track: tx.track,
      playbackToken: tx.token,
      song: song,
      state: initialState,
      notify: false,
    );
    notifyListeners();

    if (!shouldRequest) return;
    unawaited(
      LyricService().requestLyrics(
        track: tx.track,
        playbackToken: tx.token,
        quality: tx.qualityStr,
        refreshKey: _lyricRefreshKey(tx.track),
        adapter: _buildLyricRequestAdapter(
          tx.track,
          quality: tx.selectedQuality,
          qualityStr: tx.qualityStr,
          playbackToken: tx.token,
        ),
      ),
    );
  }

  Future<void> _enforceDesiredPlaybackIntent(
    TrackSwitchTransaction tx,
    bool Function() isStale,
    bool autoPlay,
  ) async {
    if (isStale()) return;
    if (_desiredPlaying) {
      // autoPlay=true 已经由装载阶段启动；autoPlay=false 则在这里补一次
      // resume。两种情况都不能暂停当前引擎。
      if (!autoPlay && !_engine.isPlaying) {
        await _engine.resume();
      }
    } else if (_engine.isPlaying) {
      await _engine.pause();
    }
  }

  bool _shouldRequestLyricsForPlan(
    Track track,
    SongDetail songDetail,
    _TrackSwitchPlaybackPlan plan,
    String qualityStr,
  ) {
    return (plan.usesCachedFile &&
            plan.resolvedSong.shouldRefreshCachedMetadata) ||
        _shouldScheduleDeferredSupplementalRefresh(songDetail);
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
    _logPlaybackDebug(
      '[PlaybackService] 回写缓存元数据($reason): $refreshKey',
      toDeveloperPanel: true,
    );
    unawaited(
      _cacheSongInBackground(track, detail, quality).catchError((Object e) {
        _logPlaybackDebug(
          '[PlaybackService] 回写缓存元数据失败($reason): $refreshKey, $e',
          toDeveloperPanel: true,
        );
        return false;
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
      StructuredLogService.log(
        '[PlaybackService] 调度封面补全($reason): ${_trackLogKey(track)} -> $imageUrl',
      );
      coverManager.updateCoverNonBlocking(imageUrl, notify: true, force: true);
    } catch (e) {
      StructuredLogService.log(
        '[PlaybackService] 调度封面补全失败($reason): ${_trackLogKey(track)}, $e',
      );
    }
  }

  void _scheduleThemeColorRefresh(
    Track track,
    String imageUrl, {
    required String reason,
  }) {
    if (imageUrl.isEmpty) return;
    try {
      StructuredLogService.log(
        '[PlaybackService] 调度主题色提取($reason): ${_trackLogKey(track)}',
      );
      coverManager.extractThemeColorNonBlocking(imageUrl);
    } catch (e) {
      StructuredLogService.log(
        '[PlaybackService] 调度主题色提取失败($reason): ${_trackLogKey(track)}, $e',
      );
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
        : modeStr.contains('sequential')
        ? PlaybackMode.sequential
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

  Future<void> _playCurrentTrack({
    String reason = 'queue-switch',
    PlaybackRequestIntent intent = PlaybackRequestIntent.manual,
    int? requestEpoch,
    bool autoPlay = true,
    Duration? initialPosition,
    bool preload = true,
    bool forceRemoteResolution = false,
    int settleMs = 0,
  }) async {
    await _attemptTrackSwitch(
      reason: reason,
      intent: intent,
      requestEpoch: requestEpoch,
      autoPlay: autoPlay,
      initialPosition: initialPosition,
      preload: preload,
      forceRemoteResolution: forceRemoteResolution,
      settleMs: settleMs,
    );
  }

  Future<PlaybackCandidateAttemptResult> _attemptTrackSwitch({
    String reason = 'queue-switch',
    PlaybackRequestIntent intent = PlaybackRequestIntent.manual,
    int? requestEpoch,
    bool autoPlay = true,
    Duration? initialPosition,
    bool preload = true,
    bool forceRemoteResolution = false,
    int settleMs = 0,
    Track? candidateTrack,
    int? candidateEntryId,
    PlaybackTransitionBudget? budget,
    List<int>? navigationOrder,
    bool preserveDesiredPlaying = false,
    bool allowActiveFallback = true,
  }) async {
    // 1. prepareTarget
    final tx = _prepareTrackSwitchTransaction(
      reason: reason,
      intent: intent,
      requestEpoch: requestEpoch,
      forceRemoteResolution: forceRemoteResolution,
      initialPosition: initialPosition,
      candidateTrack: candidateTrack,
      candidateEntryId: candidateEntryId,
      budget: budget,
      navigationOrder: navigationOrder,
      allowActiveFallback: allowActiveFallback,
    );
    if (tx == null) {
      return _candidateFailureResult(allowActiveFallback: allowActiveFallback);
    }
    if (!preserveDesiredPlaying) _desiredPlaying = autoPlay;
    notifyListeners();
    tx.timing.settleMs = settleMs;
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
        tx.timing.prefetched = true;
        trace.mark(
          'prefetch_hit',
          fields: {
            'cache': prefetchedPlan.usesCachedFile ? 'hit' : 'miss',
            'playable_source': _describePlayableSource(prefetchedPlan.source),
          },
        );
        _stagePendingPlanPresentation(tx, prefetchedPlan, isStale);
        final engineAutoPlay = autoPlay && _desiredPlaying;
        final committedPlan = await _commitPlaybackStage(
          tx,
          prefetchedPlan,
          isStale,
          autoPlay: engineAutoPlay,
          initialPosition: initialPosition,
          preload: preload,
        );
        if (committedPlan == null) {
          return isStale()
              ? PlaybackCandidateAttemptResult.cancelled
              : _candidateFailureResult(transaction: tx, engineFailure: true);
        }
        await _enforceDesiredPlaybackIntent(tx, isStale, engineAutoPlay);
        if (isStale()) return PlaybackCandidateAttemptResult.cancelled;
        trace.mark(
          'engine_ready',
          fields: {
            'prefetched': true,
            'playable_source': _describePlayableSource(committedPlan.source),
          },
        );
        _commitPresentationStage(tx, committedPlan, isStale);
        trace.mark('presentation_committed');
        return PlaybackCandidateAttemptResult.committed;
      }

      // 2. resolveSongDetail
      final resolvedSong = await _resolveSongDetailStage(tx, isStale);
      if (resolvedSong == null || isStale()) {
        return isStale()
            ? PlaybackCandidateAttemptResult.cancelled
            : _candidateFailureResult(transaction: tx);
      }
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
      final prepSw = Stopwatch()..start();
      final playbackPlan = await _resolvePlayableSourceStage(
        tx,
        resolvedSong,
        isStale,
      );
      tx.timing.planPrepareMs = prepSw.elapsedMilliseconds;
      if (playbackPlan == null || isStale()) {
        return isStale()
            ? PlaybackCandidateAttemptResult.cancelled
            : _candidateFailureResult(transaction: tx);
      }
      _stagePendingPlanPresentation(tx, playbackPlan, isStale);
      trace.mark(
        'source_ready',
        fields: {
          'cache': playbackPlan.usesCachedFile ? 'hit' : 'miss',
          'playable_source': _describePlayableSource(playbackPlan.source),
          'background_cache': playbackPlan.shouldWriteBackgroundCache,
        },
      );

      // 4. commitPlayback
      final engineAutoPlay = autoPlay && _desiredPlaying;
      final committedPlan = await _commitPlaybackStage(
        tx,
        playbackPlan,
        isStale,
        autoPlay: engineAutoPlay,
        initialPosition: initialPosition,
        preload: preload,
      );
      if (committedPlan == null) {
        return isStale()
            ? PlaybackCandidateAttemptResult.cancelled
            : _candidateFailureResult(transaction: tx, engineFailure: true);
      }
      await _enforceDesiredPlaybackIntent(tx, isStale, engineAutoPlay);
      if (isStale()) return PlaybackCandidateAttemptResult.cancelled;
      trace.mark(
        'engine_ready',
        fields: {
          'playable_source': _describePlayableSource(committedPlan.source),
        },
      );

      // 5. commitPresentation
      _commitPresentationStage(tx, committedPlan, isStale);
      trace.mark('presentation_committed');
      return PlaybackCandidateAttemptResult.committed;
    } on EngineReportedException {
      if (isStale()) return PlaybackCandidateAttemptResult.cancelled;
      trace.mark('engine_failed', level: LogLevel.error);
      if (_deferredEngineRetryGeneration == tx.token) {
        _deferredEngineRetryGeneration = null;
        return _attemptTrackSwitch(
          reason: 'engine-retry',
          intent: intent,
          requestEpoch: requestEpoch,
          autoPlay: autoPlay,
          initialPosition: initialPosition,
          preload: preload,
          forceRemoteResolution: true,
          candidateTrack: tx.track,
          candidateEntryId: tx.queueEntryId,
          budget: budget,
          navigationOrder: navigationOrder,
          preserveDesiredPlaying: true,
          allowActiveFallback: allowActiveFallback,
        );
      }
      return _candidateFailureResult(transaction: tx, engineFailure: true);
    } on AudioSourceNotConfiguredException catch (e) {
      if (isStale()) return PlaybackCandidateAttemptResult.cancelled;
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
      return _candidateFailureResult(transaction: tx);
    } catch (e) {
      if (isStale()) return PlaybackCandidateAttemptResult.cancelled;
      _state = PBState.error;
      _errorMessage = '播放失败: $e';
      _isAudioSourceNotConfigured = false;
      notifyListeners();
      _reportPlaybackFailure(tx.track, _errorMessage!);
      trace.mark('failed', level: LogLevel.error, error: e);
      return _candidateFailureResult(transaction: tx);
    }
  }

  // ══════════════════════════════════════════════════════
  // 自动播放 / 切歌
  // ══════════════════════════════════════════════════════

  Future<bool> _tryActivatePreparedTrack(
    Track track,
    int? requestEpoch,
    PlaybackRequestIntent intent, {
    int? candidateEntryId,
    List<int>? navigationOrder,
    bool preserveDesiredPlaying = false,
  }) async {
    if (requestEpoch != null && !_requestRouter.isCurrent(requestEpoch)) {
      return false;
    }
    final quality = AudioQualityService().currentQuality;
    final plan = _peekPrefetchedPlayablePlan(track, quality);
    if (plan == null) return false;
    final entryId = candidateEntryId ?? _queueController.currentEntryId;
    if (entryId == null) return false;
    final nativeKey = _nativeSourceKeyForEntry(entryId);
    if (!_nativePreparedPlans.containsKey(nativeKey)) return false;

    final tx = _prepareTrackSwitchTransaction(
      reason: 'prepared-activate',
      intent: intent,
      requestEpoch: requestEpoch,
      candidateTrack: track,
      candidateEntryId: entryId,
      navigationOrder: navigationOrder,
    );
    if (tx == null || tx.queueEntryId != entryId) return false;

    if (!preserveDesiredPlaying) _desiredPlaying = true;
    _nativeActivationIntent = intent;
    final activated = await _engine.activatePreparedSlot(
      nativeKey,
      generation: tx.token,
      queueRevision: _queueController.structureRevision,
      autoPlay: _desiredPlaying,
    );
    if (!activated) {
      _nativePreparedPlans.remove(nativeKey);
      _nativeActivationIntent = PlaybackRequestIntent.automatic;
      return false;
    }
    _onNativeSourceCommitted(nativeKey);
    return requestEpoch == null || _requestRouter.isCurrent(requestEpoch);
  }

  Future<void> _runNavigationTransition({
    required int requestEpoch,
    required PlaybackTransitionIntent intent,
    required PlaybackTransitionDirection direction,
    required String reason,
  }) async {
    _desiredPlaying = true;
    notifyListeners();
    await _waitForTrackSwitchSettle();
    if (!_requestRouter.isCurrent(requestEpoch)) return;

    if (_queue.isEmpty) {
      await _playFromHistoryForNavigation(
        requestEpoch: requestEpoch,
        direction: direction,
      );
      return;
    }

    final mode = PlaybackModeService().currentMode;
    final activeEntryId =
        _activeQueueEntryId ?? _queueController.currentEntryId;
    var queueSnapshot = _queueController.snapshot(activeEntryId: activeEntryId);
    if (activeEntryId != null &&
        queueSnapshot.indexOfEntry(activeEntryId) < 0 &&
        queueSnapshot.entries.isNotEmpty) {
      final start = _currentIndex.clamp(0, queueSnapshot.entries.length - 1);
      queueSnapshot = PlaybackQueueSnapshot(
        entries: List<PlaybackQueueEntry>.unmodifiable([
          ...queueSnapshot.entries.skip(start),
          ...queueSnapshot.entries.take(start),
        ]),
        activeEntryId: null,
        structureRevision: queueSnapshot.structureRevision,
      );
    }
    final shuffleOrder = mode == PlaybackMode.shuffle
        ? _queueController.shuffleTraversalEntryIds(
            direction,
            activeEntryId: activeEntryId,
          )
        : const <int>[];
    final plan = _candidatePlanner.plan(
      queue: queueSnapshot,
      mode: mode,
      intent: intent,
      direction: direction,
      shuffleEntryOrder: shuffleOrder,
    );

    if (plan.candidates.isEmpty) {
      if (intent == PlaybackTransitionIntent.automaticAdvance &&
          plan.stopsAtQueueEnd) {
        await _stopAtSequentialQueueEnd();
      }
      return;
    }

    final budget = PlaybackTransitionBudget();
    final playbackIntent = intent == PlaybackTransitionIntent.automaticAdvance
        ? PlaybackRequestIntent.automatic
        : PlaybackRequestIntent.manual;
    final navigationOrder = mode == PlaybackMode.shuffle
        ? <int>[
            if (activeEntryId != null) activeEntryId,
            ...plan.candidates.map((candidate) => candidate.entryId),
          ]
        : null;
    _scanningRequestEpoch = requestEpoch;

    final result = await _transitionCoordinator.run(
      plan: plan,
      budget: budget,
      isCurrent: () => _requestRouter.isCurrent(requestEpoch),
      attempt: (candidate, transitionBudget, isCurrent) async {
        if (!isCurrent()) return PlaybackCandidateAttemptResult.cancelled;
        if (_queueController.indexOfEntryId(candidate.entryId) < 0) {
          return const PlaybackCandidateAttemptResult(
            PlaybackCandidateAttemptStatus.trackFailure,
            message: '歌曲已从播放队列移除',
          );
        }

        final activated = await _tryActivatePreparedTrack(
          candidate.track,
          requestEpoch,
          playbackIntent,
          candidateEntryId: candidate.entryId,
          navigationOrder: navigationOrder,
          preserveDesiredPlaying: true,
        );
        if (activated) {
          return _activeQueueEntryId == candidate.entryId
              ? PlaybackCandidateAttemptResult.committed
              : const PlaybackCandidateAttemptResult(
                  PlaybackCandidateAttemptStatus.engineFailure,
                );
        }
        if (!isCurrent()) return PlaybackCandidateAttemptResult.cancelled;

        return _attemptTrackSwitch(
          reason: reason,
          intent: playbackIntent,
          requestEpoch: requestEpoch,
          candidateTrack: candidate.track,
          candidateEntryId: candidate.entryId,
          budget: transitionBudget,
          navigationOrder: navigationOrder,
          preserveDesiredPlaying: true,
          allowActiveFallback: intent == PlaybackTransitionIntent.manualAdvance,
        );
      },
    );

    if (_scanningRequestEpoch == requestEpoch) {
      _scanningRequestEpoch = null;
    }
    if (!_requestRouter.isCurrent(requestEpoch) ||
        result.status == PlaybackTransitionResultStatus.cancelled) {
      return;
    }
    if (result.status == PlaybackTransitionResultStatus.committed) {
      if (result.skippedCount > 0) {
        StructuredLogService.event(
          'playback.navigation_recovered',
          fields: {
            'reason': reason,
            'skipped_count': result.skippedCount,
            'entry_id': result.committedCandidate?.entryId,
          },
        );
      }
      return;
    }

    _finishFailedNavigation(
      result,
      reason: reason,
      allowActiveFallback: intent == PlaybackTransitionIntent.manualAdvance,
    );
  }

  Future<void> _playFromHistoryForNavigation({
    required int requestEpoch,
    required PlaybackTransitionDirection direction,
  }) async {
    Track? track;
    if (direction == PlaybackTransitionDirection.forward) {
      track = PlayHistoryService().getNextTrack();
    } else {
      final history = PlayHistoryService().history;
      if (history.length >= 3) track = history[2].toTrack();
    }
    if (track == null || !_requestRouter.isCurrent(requestEpoch)) return;
    _queueController.replace([track], 0, QueueSource.history);
    await _playCurrentTrack(
      reason: direction == PlaybackTransitionDirection.forward
          ? 'history-next'
          : 'history-previous',
      requestEpoch: requestEpoch,
    );
  }

  Future<void> _stopAtSequentialQueueEnd() async {
    await _engine.stop();
    _desiredPlaying = false;
    _state = PBState.idle;
    _clearPendingTrack();
    _pauseListeningTimeTracking();
    _stopStateSaveTimer();
    notifyListeners();
    _scheduleSessionPersist();
  }

  void _finishFailedNavigation(
    PlaybackTransitionResult result, {
    required String reason,
    required bool allowActiveFallback,
  }) {
    _lastFailedTrack = result.lastFailedCandidate?.track;
    _lastFailedQueueEntryId = result.lastFailedCandidate?.entryId;
    final activeStillPlaying =
        allowActiveFallback && _activeTrack != null && _engine.isPlaying;
    if (activeStillPlaying) {
      _state = PBState.playing;
      _errorMessage = null;
      _clearPendingTrack();
    } else {
      _desiredPlaying = false;
      _state = PBState.error;
    }
    StructuredLogService.event(
      'playback.navigation_failed',
      level: LogLevel.warning,
      fields: {
        'reason': reason,
        'status': result.status.name,
        'skipped_count': result.skippedCount,
        'last_entry_id': result.lastFailedCandidate?.entryId,
      },
    );
    final problem = _problemStore.current;
    if (problem != null &&
        problem.kind != PlaybackProblemKind.sourceNotConfigured) {
      onPlaybackFailure?.call(problem);
    }
    notifyListeners();
  }

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
      case PlaybackMode.shuffle:
      case PlaybackMode.sequential:
        await _runNavigationTransition(
          requestEpoch: requestEpoch,
          intent: PlaybackTransitionIntent.automaticAdvance,
          direction: PlaybackTransitionDirection.forward,
          reason: 'automatic-next',
        );
        break;
    }
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
    _cancelPendingTrackTransition();
    _resetPreloadState();
    _pendingRestorePosition = null;
    _queueController.replace(
      tracks,
      index,
      source,
      coverProviders: coverProviders,
    );
    _invalidatePreparedWindow(reschedule: true);
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
    _invalidatePreparedWindow(reschedule: true);
  }

  void _invalidatePreparedWindow({bool reschedule = false}) {
    _nativePreparedPlans.clear();
    unawaited(_engine.invalidatePreparedSlots());
    if (reschedule && _state == PBState.playing) {
      _schedulePreloadNextTrack();
    }
  }

  void _handlePlaybackModeChanged() {
    _cancelPendingTrackTransition();
    _precacheNextCover();
    _handlePreloadInputsChanged();
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

  String _nativeSourceKeyForEntry(int entryId) => 'queue-entry:$entryId';

  int? _queueEntryIdFromNativeKey(String? key) {
    if (key == null || !key.startsWith('queue-entry:')) return null;
    return int.tryParse(key.substring('queue-entry:'.length));
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

  _TrackSwitchPlaybackPlan? _peekPrefetchedPlayablePlan(
    Track track,
    AudioQuality quality,
  ) {
    _pruneExpiredPrefetchedPlayablePlans();
    return _prefetchedPlayablePlans[_buildPrefetchCacheKey(track, quality)]
        ?.plan;
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
    TrackSourceIds sourceIds = const TrackSourceIds(),
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
      sourceIds: sourceIds,
      title: title,
      artist: artist,
      timeout: timeout,
      fetchLyrics: fetchLyrics,
      resolverFingerprint: PlaybackResolverRegistry().fingerprintFor(source),
    );
    if (result.timedOut) {
      StructuredLogService.log('[PlaybackService] 获取歌曲详情超时($purpose)');
    }
    return result.detail;
  }

  Future<void> _waitForTrackSwitchSettle() async {
    if (!_engine.isPlaying) {
      return;
    }
    await Future.delayed(_trackSwitchSettleDelay);
  }

  Future<void> _playWithSoftSwitch(
    String url, {
    bool isLocal = false,
    Map<String, String>? headers,
    bool autoPlay = true,
    Duration? initialPosition,
    bool preload = true,
    TrackSwitchTransaction? transaction,
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
      transaction: transaction,
    );
  }

  Future<void> _playPlayableSourceWithSoftSwitch(
    PlayableSource source, {
    bool autoPlay = true,
    Duration? initialPosition,
    bool preload = true,
    TrackSwitchTransaction? transaction,
  }) async {
    await _performSoftSwitch(
      (generation) => _engine.playSource(
        source,
        generation: generation,
        autoPlay: autoPlay,
        initialPosition: initialPosition,
        preload: preload,
      ),
      transaction: transaction,
    );
  }

  Future<void> _performSoftSwitch(
    Future<void> Function(int generation) startPlayback, {
    TrackSwitchTransaction? transaction,
  }) async {
    // 源头纪元捕获：必须在任何 await 之前读取。当前事务已在
    // _prepareTrackSwitchTransaction 中 begin()，此处的 _playGeneration
    // 即本次装载的目标纪元；引擎据此将装载期事件与旧歌隔离。
    final generation = _playGeneration;
    _updateSessionPhase(PlaybackPhase.arming);

    // 绑定当前软切换关联的切歌事务，避免快速切歌时旧事务晚完成污染新事务的统计对象
    final targetTx = (transaction != null && transaction.token == generation)
        ? transaction
        : (_currentSwitchTx?.token == generation ? _currentSwitchTx : null);

    if (!_canStartPlayback(generation)) return;
    final engineSw = Stopwatch()..start();
    await startPlayback(generation);
    if (_canStartPlayback(generation)) {
      if (_state == PBState.loading && _engine.isPlaying) {
        _onEngineStateChanged(EngineState.playing);
      }
      final timing = targetTx?.timing;
      if (timing != null) {
        timing.engineStartupMs = engineSw.elapsedMilliseconds;
        final engineTiming = _engine.lastStartupTiming;
        if (engineTiming != null) {
          timing.engineEnsurePlayerMs = engineTiming.ensurePlayerMs;
          timing.engineMuteMs = engineTiming.muteMs;
          timing.softFadeOutMs = engineTiming.muteMs;
          timing.engineStopMs = engineTiming.stopMs;
          timing.engineSetSourceMs = engineTiming.setSourceMs;
          timing.enginePlayToReadyMs = engineTiming.playToReadyMs;
        }
      }
    }
  }

  void _schedulePreloadNextTrack() {
    if (_state != PBState.playing) return;
    final current = currentTrack;
    if (current == null) return;

    final scheduledEntryId = _activeQueueEntryId;
    if (scheduledEntryId == null) return;
    final scheduledOp = _preloadOp;
    _cancelScheduledPreload();
    _preloadTriggerTimer = Timer(_preloadTriggerDelay, () {
      _preloadTriggerTimer = null;
      final playingTrack = currentTrack;
      if (scheduledOp != _preloadOp ||
          _state != PBState.playing ||
          playingTrack == null ||
          _activeQueueEntryId != scheduledEntryId) {
        return;
      }
      unawaited(_preloadAdjacentTracks());
    });
  }

  Future<void> _preloadAdjacentTracks() async {
    if (_preloadingNext) return;
    final current = currentTrack;
    if (current == null) return;

    final mode = PlaybackModeService().currentMode;
    final currentEntryId = _activeQueueEntryId;
    if (currentEntryId == null) return;
    final currentQueueIndex = _queueController.indexOfEntryId(currentEntryId);
    if (currentQueueIndex < 0 || currentQueueIndex != _currentIndex) return;
    final nextIndex = _queueController.peekNextIndex(mode);
    final nextTrack = nextIndex == null ? null : _queue[nextIndex];
    final nextEntryId = nextIndex == null
        ? null
        : _queueController.entryIdAt(nextIndex);
    final selectedQuality = AudioQualityService().currentQuality;
    final currentIdentity = _buildTrackIdentity(current);
    final queueRevision = _queueController.structureRevision;

    _preloadingNext = true;
    final op = ++_preloadOp;
    try {
      // 1. 优先预加载下一首 (Next)
      if (nextTrack != null) {
        final nextKey = _buildPrefetchCacheKey(nextTrack, selectedQuality);
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

        if (nextEntryId != currentEntryId &&
            nextKey != _lastPreloadedTargetKey &&
            (nextTrack.source == MusicSource.local ||
                AudioSourceService().isConfigured)) {
          await _preloadTrackSource(nextTrack, selectedQuality, op);
          if (op == _preloadOp) {
            _lastPreloadedTargetKey = nextKey;
          }
        }
      }

      if (op != _preloadOp) return;

      // URL plan ready is only the first half of preloading. The native
      // rolling window is prepared below and owns the actual source switch.
      if (nextTrack != null &&
          queueRevision == _queueController.structureRevision &&
          _matchesTrackIdentity(currentTrack, currentIdentity)) {
        StructuredLogService.event(
          'playback.preload_plan_ready',
          fields: {
            'track': _buildTrackIdentity(nextTrack),
            'queue_revision': queueRevision,
            'has_next_plan': _prefetchedPlayablePlans.containsKey(
              _buildPrefetchCacheKey(nextTrack, selectedQuality),
            ),
            'native_playlist_preload': true,
          },
        );
      }

      if (op != _preloadOp ||
          queueRevision != _queueController.structureRevision) {
        return;
      }

      if (op != _preloadOp ||
          queueRevision != _queueController.structureRevision ||
          _activeQueueEntryId != currentEntryId) {
        return;
      }
      await _prepareNativePlaybackWindow(
        next: nextTrack,
        currentEntryId: currentEntryId,
        nextEntryId: nextEntryId,
        quality: selectedQuality,
        queueRevision: queueRevision,
      );
    } catch (e) {
      StructuredLogService.log('[PlaybackService] 预加载邻近曲目失败: $e');
    } finally {
      _preloadingNext = false;
    }
  }

  Future<void> _prepareNativePlaybackWindow({
    required Track? next,
    required int currentEntryId,
    required int? nextEntryId,
    required AudioQuality quality,
    required int queueRevision,
  }) async {
    final activeSource = _activePlayableSource;
    if (activeSource == null) return;

    PreparedPlaybackSlot slotFor(int entryId, _TrackSwitchPlaybackPlan plan) {
      return PreparedPlaybackSlot(
        key: _nativeSourceKeyForEntry(entryId),
        source: plan.source,
        expiresAt: DateTime.now().add(_prefetchedSongDetailTtl),
        queueRevision: queueRevision,
      );
    }

    final currentSlot = PreparedPlaybackSlot(
      key: _nativeSourceKeyForEntry(currentEntryId),
      source: activeSource,
      expiresAt: DateTime.now().add(_prefetchedSongDetailTtl),
      queueRevision: queueRevision,
    );
    final nextPlan = next == null
        ? null
        : _peekPrefetchedPlayablePlan(next, quality);
    if (nextPlan != null &&
        nextEntryId != null &&
        nextEntryId != currentEntryId) {
      _nativePreparedPlans[_nativeSourceKeyForEntry(nextEntryId)] = nextPlan;
    }

    await _engine.bindCurrentPreparedSlot(currentSlot);
    await _engine.preparePlaybackWindow(
      PreparedPlaybackWindow(
        current: currentSlot,
        next:
            nextPlan == null ||
                next == null ||
                nextEntryId == null ||
                nextEntryId == currentEntryId
            ? null
            : slotFor(nextEntryId, nextPlan),
      ),
    );
  }

  Future<bool> _replayCurrentSourceForRepeatOne() async {
    final track = currentTrack;
    final song = _activeSong;
    if (track == null || song == null || song.url.isEmpty) return false;

    final cachedFileInfo = _currentCachedFileInfo;
    if (cachedFileInfo != null) {
      final replayedFromCache = await _playCachedFileSource(cachedFileInfo);
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
      StructuredLogService.log(
        '[PlaybackService] repeatOne 复用当前音源失败，回退重新拉流: $e',
      );
      return false;
    }
  }

  Future<bool> _playCachedFileSource(
    CachedAudioFileInfo cacheInfo, {
    bool autoPlay = true,
    Duration? initialPosition,
    bool preload = true,
    TrackSwitchTransaction? transaction,
  }) async {
    CacheService().pinCachedFile(cacheInfo);
    try {
      final track = _pendingTrack ?? currentTrack;
      final sw = Stopwatch()..start();
      final source = LocalFilePlayableSource(
        cacheInfo.filePath,
        originalUrl: cacheInfo.metadata.originalUrl,
      );

      await _playPlayableSourceWithSoftSwitch(
        source,
        autoPlay: autoPlay,
        initialPosition: initialPosition,
        preload: preload,
        transaction: transaction,
      );
      StructuredLogService.log(
        '[PlaybackService] 本地缓存播放已提交 ${sw.elapsedMilliseconds}ms '
        'source=${_describePlayableSource(source)}',
      );

      _setCurrentCachedFileInfo(cacheInfo);
      if (track != null) {
        _cacheBypassKeys.remove(
          _cachePlaybackKey(track, cacheInfo.metadata.quality),
        );
      }
      await _replaceCurrentTempFilePath(null);
      return true;
    } catch (e) {
      StructuredLogService.log('[PlaybackService] 本地缓存播放失败，回退网络链路: $e');
      _markCachePlaybackBypassed(
        _pendingTrack ?? currentTrack,
        cacheInfo.metadata.quality,
        reason: 'file-start-failed',
      );
      if (_currentCachedFileInfo?.cacheKey != cacheInfo.cacheKey) {
        CacheService().unpinCachedFile(cacheInfo);
      }
      _setCurrentCachedFileInfo(null);
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
        : await CacheService().getCachedAudioFileInfo(
            track,
            quality: qualityStr,
          );

    if (cacheInfo != null && cacheInfo.metadata.quality == qualityStr) {
      final cachedSong = buildCachedSongDetail(
        track,
        cacheInfo.metadata,
        playbackUrl: cacheInfo.metadata.originalUrl.isNotEmpty
            ? cacheInfo.metadata.originalUrl
            : cacheInfo.filePath,
      );
      final cachedSource = LocalFilePlayableSource(
        cacheInfo.filePath,
        originalUrl: cacheInfo.metadata.originalUrl,
      );
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
        usesCachedFile: true,
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
      sourceIds: track.sourceIds,
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
        usesCachedFile: false,
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
          usesCachedFile: false,
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
        usesCachedFile: false,
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
      usesCachedFile: false,
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

  Future<_TrackSwitchPlaybackPlan?> _preloadTrackSource(
    Track track,
    AudioQuality selectedQuality,
    int op,
  ) async {
    final plan = await _buildPrefetchedPlayablePlan(track, selectedQuality);
    if (op != _preloadOp || plan == null) return null;
    _savePrefetchedPlayablePlan(track, selectedQuality, plan);
    return plan;
  }

  Map<String, String> _buildPlaybackHeaders(MusicSource source) {
    return buildAudioRequestHeaders(source);
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
    _setCurrentCachedFileInfo(null);
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
    _desiredPlaying = false;
    await _engine.stop();
    _state = PBState.idle;
    _activeTrack = null;
    _activeQueueEntryId = null;
    _activeSong = null;
    _queueController.clear();
    _preloadedTrack = null;
    _clearPendingTrack();
    _position = Duration.zero;
    _duration = Duration.zero;
    _bufferedPosition = Duration.zero;
    _presentationDuration = Duration.zero;
    _presentationBufferedPosition = Duration.zero;
    _errorMessage = null;
    _setCurrentCachedFileInfo(null);
    _cacheBypassKeys.clear();
    _trackResolver.clear();
    LyricService().clearAll(notify: false);
    positionNotifier.value = Duration.zero;
    presentationPositionNotifier.value = Duration.zero;
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
      _desiredPlaying = false;
      _activeTrack = null;
      _activeQueueEntryId = null;
      _activeSong = null;
      _preloadedTrack = null;
      _clearPendingTrack();
      _position = Duration.zero;
      _duration = Duration.zero;
      _bufferedPosition = Duration.zero;
      _presentationDuration = Duration.zero;
      _presentationBufferedPosition = Duration.zero;
      presentationPositionNotifier.value = Duration.zero;
      _setCurrentCachedFileInfo(null);
      _cacheBypassKeys.clear();
      _trackResolver.clear();
      LyricService().clearAll(notify: false);
      coverManager.setCoverImmediate(null, notify: false);
      _sessionManager.dispose();
      _historyRecorder.dispose();
      await _engine.dispose();
    } catch (e) {
      StructuredLogService.log('[PlaybackService] 释放资源失败: $e');
    }
  }

  @override
  void dispose() {
    _resetPreloadState();
    _unbindPreloadDependencyListeners();
    _stabilityTracker.dispose();
    AudioSourceService().removeListener(_onAudioSourceConfigChanged);
    for (final sub in _engineSubs) {
      sub.cancel();
    }
    _engineSubs.clear();
    PlaybackModeService().removeListener(_handlePlaybackModeChanged);
    _pauseListeningTimeTracking();
    _stopStateSaveTimer();
    _sessionManager.dispose();
    _historyRecorder.dispose();
    _cleanupCurrentTempFile();
    _engine.dispose();
    ProxyService().stop();
    coverManager.dispose();
    positionNotifier.dispose();
    presentationPositionNotifier.dispose();
    bufferedPositionNotifier.dispose();
    problemNotifier.dispose();
    sourceHealthNotifier.dispose();
    super.dispose();
  }
}
