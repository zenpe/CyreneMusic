import 'structured_log_service.dart';
import 'source_recommendation_service.dart';
import 'automatic_recommendation_router.dart';

import 'package:crypto/crypto.dart';

import 'dart:io';
import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:path_provider/path_provider.dart';

import '../models/track.dart';
import '../models/song_detail.dart';
import '../models/audio_source_config.dart';
import 'lx_music_runtime_service.dart';
import 'lx_runtime_interface.dart';
import 'lx_music_source_parser.dart';
import 'navidrome_session_service.dart';
import 'url_service.dart';
import '../models/lx_source_candidate.dart';

/// 音源类型枚举
enum AudioSourceType {
  lxmusic, // 洛雪音乐音源
  navidrome, // Navidrome
}

enum AudioSourceLoadState { inactive, activating, ready, failed }

typedef AutomaticRouterFactory = AutomaticRecommendationRouter Function({
  required bool Function() isCurrent,
  required int Function() selectionEpoch,
  required Future<void> Function(Future<void> Function()) commit,
});

/// 音源服务 - 管理音源配置（获取歌曲播放 URL）
///
/// 支持多音源管理，用户可以添加多个音源并选择其中一个作为当前活动音源。
class AudioSourceService extends ChangeNotifier {
  static final AudioSourceService _instance = AudioSourceService._internal();
  factory AudioSourceService() => _instance;
  AudioSourceService._internal()
    : _runtime = LxMusicRuntimeService(),
      _parser = LxMusicSourceParser(),
      _automaticFactory = AutomaticRecommendationRouter.new,
      _recommendations = SourceRecommendationService(),
      recommendationStartupBudget = const Duration(seconds: 3);

  @visibleForTesting
  AudioSourceService.withDependencies({
    required this._runtime,
    required this._parser,
    SourceRecommendationService? recommendations,
    AutomaticRouterFactory? automaticFactory,
    this.recommendationStartupBudget = const Duration(seconds: 3),
  }) : _recommendations = recommendations ?? SourceRecommendationService(),
       _automaticFactory =
           automaticFactory ?? AutomaticRecommendationRouter.new;

  final AutomaticRouterFactory _automaticFactory;
  final SourceRecommendationService _recommendations;
  final Duration recommendationStartupBudget;
  Future<void>? _initialization;
  Completer<void>? _startupNetworkInterrupt;
  int _selectionEpoch = 0;
  bool _startupPlaybackRequested = false;
  bool _recommendationJournalCleanupPending = false;
  bool _recommendationRecoveryBlocked = false;
  String? recommendationUpdateError;
  String? recommendationPendingName;
  static const _recommendationJournal =
      'audio_source_recommendation_rollback_v1';
  final LxRuntime _runtime;
  final LxMusicSourceParser _parser;
  Future<void>? _candidateActivation;
  AudioSourceLoadState get loadState => _candidateActivation != null
      ? AudioSourceLoadState.activating
      : activeSource == null
      ? AudioSourceLoadState.inactive
      : loadError != null
      ? AudioSourceLoadState.failed
      : isNavidromeActive ||
            (isAutomaticActive
                ? _automatic?.isReady == true
                : _runtime.isScriptReady)
      ? AudioSourceLoadState.ready
      : AudioSourceLoadState.inactive;
  String? loadError;

  bool get preservesRuntimeDuringActivation =>
      _runtime is LxStagedRuntime &&
      (_runtime as LxStagedRuntime).supportsStaging;

  int _lxSourceRevision = 0;
  int get lxSourceRevision => _lxSourceRevision;
  AutomaticRecommendationRouter? _automatic;
  AutomaticRecommendationRouter? get automaticRouter => _automatic;
  bool get isAutomaticActive => activeSource?.isAutomaticRecommendation == true;
  AutomaticRoute? automaticRouteFor(MusicSource platform) =>
      isAutomaticActive ? _automatic?.routeFor(platform.name) : null;

  /// 外部触发状态刷新（代替直接调用 notifyListeners）
  void refresh() => notifyListeners();

  /// 所有已配置的音源列表
  List<AudioSourceConfig> _sources = [];

  /// 当前活动音源 ID
  String _activeSourceId = '';

  /// 是否已初始化
  bool _isInitialized = false;
  Future<void> _mutationQueue = Future.value();
  Future<void> _lxRuntimeOperation = Future.value();
  int _lxRuntimeGeneration = 0;
  String? _lxRuntimeSourceId;

  // ==================== 存储键名 ====================
  static const String _keySources = 'audio_source_list';
  static const String _keyActiveSourceId = 'audio_source_active_id';
  static const String navidromeSourceId = '__navidrome__';

  // 兼容旧版配置的键名
  static const String _keyOldSourceType = 'audio_source_type';
  static const String _keyOldSourceUrl = 'audio_source_url';
  static const String _keyOldLxApiKey = 'audio_source_lx_api_key';
  static const String _keyOldLxSourceName = 'audio_source_lx_name';
  static const String _keyOldLxSourceVersion = 'audio_source_lx_version';
  static const String _keyOldLxScriptSource = 'audio_source_lx_script_source';
  static const String _keyOldLxSourceAuthor = 'audio_source_lx_author';
  static const String _keyOldLxSourceDescription =
      'audio_source_lx_description';
  static const String _keyOldLxUrlPathTemplate =
      'audio_source_lx_url_path_template';

  // ==================== 洛雪音源来源代码映射 ====================
  static const Map<MusicSource, String> _lxSourceCodeMap = {
    MusicSource.netease: 'wy', // 网易云音乐
    MusicSource.qq: 'tx', // QQ音乐（腾讯）
    MusicSource.kugou: 'kg', // 酷狗音乐
    MusicSource.kuwo: 'kw', // 酷我音乐
  };

  static const List<String> lxQualityOptions = [
    '128k',
    '320k',
    'flac',
    'flac24bit',
  ];

  Future<void> _enqueueMutation(
    Future<void> Function() mutation, {
    bool automatic = false,
  }) {
    if (!automatic) {
      _selectionEpoch++;
      final interrupt = _startupNetworkInterrupt;
      if (interrupt != null && !interrupt.isCompleted) interrupt.complete();
    }
    final task = _mutationQueue.catchError((_) {}).then((_) async {
      if (_recommendationRecoveryBlocked) {
        throw StateError('上次音源更新尚未恢复，本次操作未保存，请重启后重试');
      }
      // Check after prior operations finish: they may have committed a new
      // recommendation but failed to remove its rollback snapshot.
      await _finishRecommendationJournalCleanup();
      await mutation();
    });
    _mutationQueue = task.catchError((_) {});
    return task;
  }

  Future<void> _finishRecommendationJournalCleanup() async {
    if (!_recommendationJournalCleanupPending) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      // remove() can evict the cached key even when the storage write fails.
      // Retry unconditionally until the underlying store confirms success.
      if (!await prefs.remove(_recommendationJournal)) {
        throw StateError('回退记录清理失败');
      }
      _recommendationJournalCleanupPending = false;
    } catch (e) {
      StructuredLogService.log('[AudioSourceService] 推荐回退记录仍待清理: $e');
      throw StateError('上次音源更新的回退记录尚未清理，本次操作未保存，请重试');
    }
  }

  void _invalidateLxRuntime() {
    _stopAutomatic();
    _lxSourceRevision++;
    _lxRuntimeGeneration++;
    _lxRuntimeSourceId = null;
  }

  /// 各音源类型默认支持的搜索平台
  static const Map<AudioSourceType, List<String>> defaultSupportedPlatforms = {
    AudioSourceType.lxmusic: [], // 动态从脚本获取
    AudioSourceType.navidrome: [], // Navidrome 使用独立 API
  };

  /// 初始化服务
  Future<void> initialize() => _initialization ??= _initializeOnce();

  Future<void> _initializeOnce() async {
    if (_isInitialized) return;
    await _loadSettings();
    final source = activeSource;
    if (source?.isRecommendation == true &&
        source!.backendOrigin == SourceRecommendationService.currentOrigin &&
        !_startupPlaybackRequested) {
      final epoch = _selectionEpoch, backend = UrlService().backendRevision;
      final interrupt = Completer<void>();
      _startupNetworkInterrupt = interrupt;
      final clock = Stopwatch()..start();
      DownloadedRecommendation? selected;
      final fetch = _recommendations
          .download(
            source.backendOrigin,
            existingHash:
                source.scriptContentHash ==
                    sha256.convert(utf8.encode(source.scriptContent)).toString()
                ? source.scriptSha256
                : null,
            existingScript: source.scriptContent,
          )
          .then<DownloadedRecommendation?>((download) {
            if (epoch == _selectionEpoch &&
                backend == UrlService().backendRevision &&
                activeSource?.id == source.id &&
                download.descriptor.scriptSha256 != source.scriptSha256) {
              recommendationPendingName = download.descriptor.resolvedName;
              notifyListeners();
            }
            return download;
          })
          .catchError((Object e) {
            if (epoch == _selectionEpoch &&
                backend == UrlService().backendRevision) {
              recommendationUpdateError = e.toString();
            }
            return null;
          });
      try {
        selected = await Future.any<DownloadedRecommendation?>([
          fetch,
          Future<DownloadedRecommendation?>.delayed(
            recommendationStartupBudget,
            () => null,
          ),
          interrupt.future.then((_) => null),
        ]);
      } finally {
        _startupNetworkInterrupt = null;
      }
      if (selected != null &&
          epoch == _selectionEpoch &&
          backend == UrlService().backendRevision &&
          activeSource?.id == source.id) {
        try {
          await _enqueueMutation(() async {
            void validate() {
              if (epoch != _selectionEpoch ||
                  backend != UrlService().backendRevision ||
                  activeSource?.id != source.id) {
                throw StateError('推荐更新已失效');
              }
            }

            validate();
            await _applyRecommendation(selected!, validate: validate);
          }, automatic: true);
        } catch (e) {
          recommendationUpdateError = e.toString();
          StructuredLogService.log('[AudioSourceService] 推荐启动更新失败，使用本地版本: $e');
        }
      }
      StructuredLogService.log(
        '[AudioSourceService] 推荐启动选择及准备 elapsedMs=${clock.elapsedMilliseconds} release=${activeSource?.releaseId} sha256=${activeSource?.scriptSha256}',
      );
    }
    if (activeSource?.type == AudioSourceType.lxmusic) {
      try {
        await _initializeLxRuntime();
      } catch (_) {
        /* Settings remain accessible for repair. */
      }
    }
    _isInitialized = true;
    StructuredLogService.log('✅ [AudioSourceService] 初始化完成');
  }

  bool _automaticBackendListening = false;
  AutomaticRecommendationRouter _newAutomaticRouter({
    required bool Function() isCurrent,
    required Future<void> Function(Future<void> Function()) commit,
  }) {
    if (!_automaticBackendListening) {
      UrlService().addListener(_onAutomaticBackendChanged);
      _automaticBackendListening = true;
    }
    return _automaticFactory(
      isCurrent: isCurrent,
      selectionEpoch: () => _selectionEpoch,
      commit: commit,
    );
  }

  void _onAutomaticBackendChanged() {
    if (_automatic != null &&
        _automatic!.origin != SourceRecommendationService.currentOrigin) {
      _automatic!.stop();
      notifyListeners();
    }
  }

  void _stopAutomatic() {
    final router = _automatic;
    _automatic = null;
    router?.removeListener(notifyListeners);
    router?.dispose();
  }

  /// Preparation runs outside the source mutation queue; only publication is serialized.
  Future<void> useAutomaticSource() async {
    final origin = SourceRecommendationService.currentOrigin;
    if (isAutomaticActive &&
        _automatic?.origin == origin &&
        _automatic!.isReady) {
      await _automatic!.check(force: true);
      return;
    }
    final epoch = ++_selectionEpoch, backend = UrlService().backendRevision;
    var adopted = false;
    late final AutomaticRecommendationRouter router;
    router = _newAutomaticRouter(
      isCurrent: () =>
          backend == UrlService().backendRevision &&
          (adopted
              ? identical(_automatic, router) && isAutomaticActive
              : epoch == _selectionEpoch),
      commit: (work) =>
          adopted ? _enqueueMutation(work, automatic: true) : work(),
    );
    try {
      await router.start(origin);
      if (!router.isReady) {
        throw StateError(router.updateError ?? '当前服务器尚无可用的自动推荐目标');
      }
      await _enqueueMutation(() async {
        if (epoch != _selectionEpoch ||
            backend != UrlService().backendRevision) {
          throw StateError('音源选择已改变，本次自动推荐未启用');
        }
        final existing = _sources
            .where(
              (s) => s.isAutomaticRecommendation && s.backendOrigin == origin,
            )
            .firstOrNull;
        final config = AudioSourceConfig(
          id:
              existing?.id ??
              'automatic_${sha256.convert(utf8.encode(origin)).toString().substring(0, 24)}',
          type: AudioSourceType.lxmusic,
          name: '自动推荐（标准音质）',
          url: '',
          catalogKind: 'automatic_recommendation',
          backendOrigin: origin,
          supportedPlatforms: const ['qq', 'netease'],
        );
        final next = [..._sources.where((s) => s.id != config.id), config];
        final prefs = await SharedPreferences.getInstance();
        final oldList = prefs.getString(_keySources),
            oldId = prefs.getString(_keyActiveSourceId);
        if (!await prefs.setString(
          _recommendationJournal,
          jsonEncode({'sources': oldList, 'activeId': oldId}),
        )) {
          throw StateError('无法保存选源回退记录');
        }
        try {
          if (!await prefs.setString(
                _keySources,
                jsonEncode(next.map((s) => s.toJson()).toList()),
              ) ||
              !await prefs.setString(_keyActiveSourceId, config.id)) {
            throw StateError('无法保存自动推荐选择');
          }
          if (epoch != _selectionEpoch ||
              backend != UrlService().backendRevision) {
            throw StateError('音源选择已改变');
          }
        } catch (_) {
          final listOk = oldList == null
              ? await prefs.remove(_keySources)
              : await prefs.setString(_keySources, oldList);
          final idOk = oldId == null
              ? await prefs.remove(_keyActiveSourceId)
              : await prefs.setString(_keyActiveSourceId, oldId);
          _recommendationRecoveryBlocked = !listOk || !idOk;
          if (!_recommendationRecoveryBlocked) {
            _recommendationJournalCleanupPending = true;
            await _finishRecommendationJournalCleanup();
          }
          rethrow;
        }
        _stopAutomatic();
        _automatic = router;
        adopted = true;
        _sources = next;
        _activeSourceId = config.id;
        _lxSourceRevision++;
        _lxRuntimeGeneration++;
        _lxRuntimeSourceId = null;
        loadError = null;
        router.addListener(notifyListeners);
        router.follow();
        await _lxRuntimeOperation.catchError((Object _) {});
        await _runtime.dispose().catchError((Object _) {});
        _recommendationJournalCleanupPending = true;
        try {
          await _finishRecommendationJournalCleanup();
        } catch (_) {
          /* Retry before next mutation. */
        }
        notifyListeners();
      }, automatic: true);
    } finally {
      if (!adopted) router.dispose();
    }
  }

  Future<void> _restoreAutomatic(AudioSourceConfig config) async {
    if (_automatic != null) {
      await _automatic!.ready();
      return;
    }
    if (config.backendOrigin != SourceRecommendationService.currentOrigin) {
      throw StateError('自动推荐来自原服务器，请选择当前服务器的自动推荐');
    }
    late final AutomaticRecommendationRouter router;
    router = _newAutomaticRouter(
      isCurrent: () =>
          identical(_automatic, router) &&
          isAutomaticActive &&
          config.backendOrigin == SourceRecommendationService.currentOrigin,
      commit: (work) => _enqueueMutation(work, automatic: true),
    );
    _automatic = router;
    router.addListener(notifyListeners);
    await router.start(config.backendOrigin, remote: false);
    router.follow();
    unawaited(router.check(force: true));
  }

  Future<void> useRecommendedSource() {
    final origin = SourceRecommendationService.currentOrigin,
        revision = UrlService().backendRevision;
    return _enqueueMutation(() async {
      final old = _sources
          .where((s) => s.isRecommendation && s.backendOrigin == origin)
          .firstOrNull;
      void validate() {
        if (revision != UrlService().backendRevision) {
          throw StateError('服务器已更换，请重新选择推荐音源');
        }
      }

      try {
        final downloaded = await _recommendations.download(
          origin,
          existingHash:
              old?.scriptContentHash ==
                  sha256
                      .convert(utf8.encode(old?.scriptContent ?? ''))
                      .toString()
              ? old?.scriptSha256
              : null,
          existingScript: old?.scriptContent,
        );
        validate();
        await _applyRecommendation(downloaded, validate: validate);
      } catch (e) {
        recommendationUpdateError = e.toString();
        notifyListeners();
        rethrow;
      }
    });
  }

  Future<void> cacheRecommendedUpdate() async {
    final source = activeSource,
        epoch = _selectionEpoch,
        backend = UrlService().backendRevision;
    if (source?.isRecommendation != true ||
        source!.backendOrigin != SourceRecommendationService.currentOrigin) {
      return;
    }
    try {
      final pending = await _recommendations.download(
        source.backendOrigin,
        existingHash: source.scriptSha256,
        existingScript: source.scriptContent,
      );
      if (epoch != _selectionEpoch ||
          backend != UrlService().backendRevision ||
          activeSource?.id != source.id) {
        return;
      }
      recommendationPendingName =
          pending.descriptor.scriptSha256 == source.scriptSha256
          ? null
          : pending.descriptor.resolvedName;
      recommendationUpdateError = null;
    } catch (e) {
      if (epoch == _selectionEpoch && backend == UrlService().backendRevision) {
        recommendationUpdateError = e.toString();
      }
    }
    notifyListeners();
  }

  Future<void> _applyRecommendation(
    DownloadedRecommendation downloaded, {
    required void Function() validate,
  }) async {
    final old = _sources
        .where(
          (s) => s.isRecommendation && s.backendOrigin == downloaded.origin,
        )
        .firstOrNull;
    final next = downloaded.config(old?.id ?? createSourceId());
    // A release/note-only change does not restart an already active identical runtime.
    if (old != null &&
        activeSource?.id == old.id &&
        old.scriptSha256 == next.scriptSha256 &&
        old.scriptContentHash == next.scriptContentHash &&
        _runtime.isScriptReady) {
      validate();
      final prefs = await SharedPreferences.getInstance();
      final updated = _sources
          .map(
            (s) => s.id == old.id
                ? next.copyWith(supportedPlatforms: s.supportedPlatforms)
                : s,
          )
          .toList();
      final before = prefs.getString(_keySources);
      try {
        if (!await prefs.setString(
          _keySources,
          jsonEncode(updated.map((s) => s.toJson()).toList()),
        )) {
          throw StateError('无法保存推荐版本');
        }
        validate();
      } catch (_) {
        final restored = before == null
            ? await prefs.remove(_keySources)
            : await prefs.setString(_keySources, before);
        if (!restored) throw StateError('推荐信息保存及恢复失败，请重新加载音源');
        rethrow;
      }
      _sources = updated;
      notifyListeners();
    } else {
      await _activateConfig(next, validate: validate);
    }
    recommendationUpdateError = null;
    recommendationPendingName = null;
    notifyListeners();
    StructuredLogService.log(
      '[AudioSourceService] 推荐已应用 backend=${downloaded.origin} release=${next.releaseId} sha256=${next.scriptSha256}',
    );
  }

  /// 初始化洛雪运行时环境
  Future<void> initializeLxRuntime() async {
    // A playback request closes only the startup network window. Preparation and
    // persistence rollback must finish before a resolver can observe the choice.
    if (!_isInitialized) _startupPlaybackRequested = true;
    if (!_isInitialized && _initialization != null) {
      final interrupt = _startupNetworkInterrupt;
      if (interrupt != null && !interrupt.isCompleted) interrupt.complete();
      await _initialization;
    }
    await _initializeLxRuntime();
  }

  Future<void> _initializeLxRuntime() async {
    final automaticConfig = activeSource;
    if (automaticConfig?.isAutomaticRecommendation == true) {
      await _restoreAutomatic(automaticConfig!);
      return;
    }
    // A candidate has its own context; existing playback can keep resolving.
    if (_runtime is LxStagedRuntime &&
        (_runtime as LxStagedRuntime).supportsStaging &&
        _lxRuntimeSourceId == activeSource?.id &&
        _runtime.isScriptReady) {
      return;
    }
    while (true) {
      final activation = _candidateActivation;
      if (activation == null) break;
      await activation;
    }
    final source = activeSource;
    final generation = _lxRuntimeGeneration;
    if (source == null || source.type != AudioSourceType.lxmusic) {
      _lxRuntimeSourceId = null;
      return;
    }

    final sourceId = source.id;
    final operation = _lxRuntimeOperation.catchError((_) {}).then((_) async {
      // Source changes are latest-wins. An older queued initialization must
      // never load its script after a newer source has become active.
      if (generation != _lxRuntimeGeneration || activeSource?.id != sourceId) {
        return;
      }
      if (_lxRuntimeSourceId == sourceId && _runtime.isScriptReady) {
        return;
      }

      try {
        StructuredLogService.log(
          '🚀 [AudioSourceService] 正在初始化洛雪运行时: $sourceId',
        );
        if (source.isRecommendation &&
            (source.scriptContentHash.isEmpty ||
                source.scriptContentHash !=
                    sha256
                        .convert(utf8.encode(source.scriptContent))
                        .toString())) {
          throw StateError('本地推荐脚本完整性验证失败，请检查更新');
        }
        String? scriptContent = source.scriptContent;
        if (scriptContent.isEmpty) {
          scriptContent = await _loadLxScriptContent();
        }
        if (scriptContent == null || scriptContent.isEmpty) {
          StructuredLogService.log(
            '⚠️ [AudioSourceService] 未找到洛雪脚本内容，无法初始化运行时',
          );
          throw StateError('未找到音源脚本，请更新脚本');
        }

        final runtime = _runtime;
        final loaded = await runtime.loadScript(scriptContent);
        if (loaded == null ||
            !runtime.isScriptReady ||
            loaded.supportedSources.isEmpty) {
          StructuredLogService.log(
            '⚠️ [AudioSourceService] 洛雪脚本加载失败: $sourceId',
          );
          throw StateError(runtime.lastFailure?.message ?? '脚本初始化失败');
        }
        if (generation == _lxRuntimeGeneration &&
            activeSource?.id == sourceId) {
          _lxRuntimeSourceId = sourceId;
          loadError = null;
          StructuredLogService.log(
            '✅ [AudioSourceService] 洛雪运行时初始化成功: $sourceId',
          );
        }
      } catch (e) {
        if (generation == _lxRuntimeGeneration &&
            activeSource?.id == sourceId) {
          loadError = e.toString();
        }
        StructuredLogService.log('❌ [AudioSourceService] 初始化洛雪运行时失败: $e');
        rethrow;
      } finally {
        if (generation == _lxRuntimeGeneration &&
            activeSource?.id == sourceId) {
          notifyListeners();
        }
      }
    });
    _lxRuntimeOperation = operation;
    await operation;
  }

  /// 生成唯一 ID
  String _generateId() {
    return '${DateTime.now().millisecondsSinceEpoch}_${Random().nextInt(10000)}';
  }

  /// 提供给 UI 层统一生成音源 ID，避免各处重复规则
  String createSourceId() => _generateId();

  /// 从本地存储加载设置
  Future<void> _loadSettings() async {
    try {
      final prefs = await SharedPreferences.getInstance();

      final journal = prefs.getString(_recommendationJournal);
      if (journal != null) {
        _recommendationRecoveryBlocked = true;
        final backup = jsonDecode(journal) as Map<String, dynamic>;
        final list = backup['sources'] as String?,
            id = backup['activeId'] as String?;
        if (!(list == null
                ? await prefs.remove(_keySources)
                : await prefs.setString(_keySources, list)) ||
            !(id == null
                ? await prefs.remove(_keyActiveSourceId)
                : await prefs.setString(_keyActiveSourceId, id))) {
          throw StateError('无法恢复上次中断的推荐更新');
        }
        _recommendationRecoveryBlocked = false;
        _recommendationJournalCleanupPending = true;
        try {
          await _finishRecommendationJournalCleanup();
        } catch (_) {
          // The old configuration has been restored. Load it even if cleanup
          // must be retried before a later mutation can persist.
          StructuredLogService.log('[AudioSourceService] 配置已恢复，回退记录待清理');
        }
        StructuredLogService.log('[AudioSourceService] 已恢复中断前的音源配置');
      }
      // 1. 加载音源列表
      final sourcesJson = prefs.getString(_keySources);
      if (sourcesJson != null) {
        final List<dynamic> list = jsonDecode(sourcesJson);
        final needsRewrite = list.any(
          (item) => item is! Map || item['type'] is! String,
        );
        _sources = list
            .whereType<Map>()
            .map(
              (item) => AudioSourceConfig.tryFromJson(
                Map<String, dynamic>.from(item),
              ),
            )
            .whereType<AudioSourceConfig>()
            .toList();
        if (needsRewrite || _sources.length != list.length) {
          await prefs.setString(
            _keySources,
            jsonEncode(_sources.map((source) => source.toJson()).toList()),
          );
        }
      }

      // 2. 加载活动音源 ID
      _activeSourceId = prefs.getString(_keyActiveSourceId) ?? '';
      if (_activeSourceId != navidromeSourceId &&
          !_sources.any((source) => source.id == _activeSourceId)) {
        _activeSourceId = '';
        await prefs.setString(_keyActiveSourceId, '');
      }

      // 3. 迁移旧版配置 (如果列表为空但有旧配置)
      if (_sources.isEmpty && prefs.containsKey(_keyOldSourceUrl)) {
        await _migrateOldSettings(prefs);
      }

      StructuredLogService.log(
        '🔊 [AudioSourceService] 加载配置完成: ${_sources.length} 个音源',
      );
      if (activeSource != null) {
        StructuredLogService.log(
          '   当前活动音源: ${activeSource!.name} (${activeSource!.type.name})',
        );
      } else {
        StructuredLogService.log('   当前无活动音源');
      }

      notifyListeners();
    } catch (e) {
      if (_recommendationRecoveryBlocked) {
        loadError = '上次音源更新恢复失败，请重启后重试';
      }
      StructuredLogService.log('❌ [AudioSourceService] 加载配置失败: $e');
    }
  }

  /// 迁移旧版配置
  Future<void> _migrateOldSettings(SharedPreferences prefs) async {
    StructuredLogService.log('🔄 [AudioSourceService] 检测到旧版配置，开始迁移...');
    try {
      final typeIndex = prefs.getInt(_keyOldSourceType);
      final url = prefs.getString(_keyOldSourceUrl) ?? '';

      if (typeIndex != 1 || url.isEmpty) {
        StructuredLogService.log('ℹ️ [AudioSourceService] 忽略已废弃的旧版音源配置');
        await _clearOldSettings(prefs);
        return;
      }

      final config = AudioSourceConfig(
        id: _generateId(),
        type: AudioSourceType.lxmusic,
        name: prefs.getString(_keyOldLxSourceName) ?? '洛雪音源',
        url: url,
        apiKey: prefs.getString(_keyOldLxApiKey) ?? '',
        version: prefs.getString(_keyOldLxSourceVersion) ?? '',
        author: prefs.getString(_keyOldLxSourceAuthor) ?? '',
        description: prefs.getString(_keyOldLxSourceDescription) ?? '',
        scriptSource: prefs.getString(_keyOldLxScriptSource) ?? '',
        // 尝试加载脚本内容
        scriptContent: (await _loadLxScriptContent()) ?? '',
        urlPathTemplate: prefs.getString(_keyOldLxUrlPathTemplate) ?? '',
      );

      _sources.add(config);
      _activeSourceId = config.id;

      await _saveSources();
      await _saveActiveSourceId();

      await _clearOldSettings(prefs);
      StructuredLogService.log('✅ [AudioSourceService] 迁移完成');
    } catch (e) {
      StructuredLogService.log('❌ [AudioSourceService] 迁移失败: $e');
    }
  }

  Future<void> _clearOldSettings(SharedPreferences prefs) async {
    for (final key in [
      _keyOldSourceType,
      _keyOldSourceUrl,
      _keyOldLxApiKey,
      _keyOldLxSourceName,
      _keyOldLxSourceVersion,
      _keyOldLxScriptSource,
      _keyOldLxSourceAuthor,
      _keyOldLxSourceDescription,
      _keyOldLxUrlPathTemplate,
    ]) {
      await prefs.remove(key);
    }
  }

  /// 保存音源列表
  Future<void> _saveSources() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final jsonList = _sources.map((e) => e.toJson()).toList();
      await prefs.setString(_keySources, jsonEncode(jsonList));
    } catch (e) {
      StructuredLogService.log('❌ [AudioSourceService] 保存音源列表失败: $e');
    }
  }

  /// 保存活动音源 ID
  Future<void> _saveActiveSourceId() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_keyActiveSourceId, _activeSourceId);
    } catch (e) {
      StructuredLogService.log('❌ [AudioSourceService] 保存活动音源 ID 失败: $e');
    }
  }

  // ==================== Public Methods ====================

  /// 获取音源列表
  List<AudioSourceConfig> get sources => List.unmodifiable(_sources);

  /// 获取当前活动音源配置
  AudioSourceConfig? get activeSource {
    if (_activeSourceId == navidromeSourceId) {
      final session = NavidromeSessionService();
      return AudioSourceConfig(
        id: navidromeSourceId,
        type: AudioSourceType.navidrome,
        name: 'Navidrome',
        url: session.baseUrl,
      );
    }
    try {
      return _sources.firstWhere((s) => s.id == _activeSourceId);
    } catch (e) {
      return null;
    }
  }

  bool get isNavidromeActive => _activeSourceId == navidromeSourceId;

  /// Download and activate as one serialized operation. Until initialization
  /// succeeds, neither the saved selection nor the source list is changed.
  Future<void> useLxSource(String scriptUrl, {String? catalogPath}) {
    if (catalogPath == SourceRecommendation.catalogPath) {
      return useRecommendedSource();
    }
    final backendRevision = UrlService().backendRevision;
    void checkBackend() {
      if (catalogPath != null &&
          backendRevision != UrlService().backendRevision) {
        throw Exception('服务器已更换，请在当前服务器重新选择音源');
      }
    }

    return _enqueueMutation(() async {
      checkBackend();
      if (catalogPath != null
          ? !LxSourceCandidate.isScriptPath(catalogPath)
          : !isValidUrl(scriptUrl)) {
        throw Exception('无效的音源路径或链接');
      }
      final parsed = catalogPath != null
          ? await _parser.parseFromCatalogPath(catalogPath)
          : await _parser.parseFromUrl(scriptUrl);
      checkBackend();
      if (parsed == null || parsed.scriptContent.isEmpty) {
        throw Exception('无法下载或读取音源脚本，请刷新列表后重试');
      }

      final index = _sources.indexWhere(
        (source) =>
            source.type == AudioSourceType.lxmusic &&
            (catalogPath != null
                ? source.catalogPath == catalogPath
                : source.catalogPath.isEmpty &&
                      source.scriptSource == scriptUrl),
      );
      final config = AudioSourceConfig(
        id: index < 0 ? createSourceId() : _sources[index].id,
        type: AudioSourceType.lxmusic,
        name: parsed.name,
        version: parsed.version,
        url: parsed.apiUrl,
        apiKey: parsed.apiKey,
        scriptSource: catalogPath == null ? scriptUrl : '',
        catalogPath: catalogPath ?? '',
        scriptContent: parsed.scriptContent,
        author: parsed.author,
        description: parsed.description,
        urlPathTemplate: parsed.urlPathTemplate,
      );
      await _activateConfig(config, validate: checkBackend);
    });
  }

  Future<void> _activateConfig(
    AudioSourceConfig config, {
    void Function()? validate,
  }) async {
    void checkBackend() => validate?.call();
    if (config.isRecommendation &&
        (config.scriptContentHash.isEmpty ||
            config.scriptContentHash !=
                sha256.convert(utf8.encode(config.scriptContent)).toString())) {
      throw StateError('推荐脚本已改变，请通过检查更新重新下载');
    }
    final previousSources = List<AudioSourceConfig>.from(_sources);
    final previousId = _activeSourceId;
    final previous = activeSource;
    final previousRuntimeId = _lxRuntimeSourceId;
    final staged =
        _runtime is LxStagedRuntime &&
        (_runtime as LxStagedRuntime).supportsStaging;
    LxRuntimeCandidate? candidate;
    final index = _sources.indexWhere((source) => source.id == config.id);
    final barrier = Completer<void>();
    _candidateActivation = barrier.future;
    _lxRuntimeGeneration++;
    if (!staged) _lxRuntimeSourceId = null;
    notifyListeners();
    SharedPreferences? prefs;
    String? storedSources;
    String? storedId;
    var persistenceStarted = false;
    var journalStarted = false;
    try {
      await _lxRuntimeOperation.catchError((_) {});
      checkBackend();
      final LxScriptInfo? info;
      if (staged) {
        candidate = await (_runtime as LxStagedRuntime).prepareScript(
          config.scriptContent,
        );
        info = candidate.script;
      } else {
        info = await _runtime.loadScript(config.scriptContent);
      }
      checkBackend();
      if (info == null ||
          (!staged && !_runtime.isScriptReady) ||
          info.supportedSources.isEmpty) {
        throw Exception(_runtime.lastFailure?.message ?? '脚本加载失败或初始化超时');
      }
      config = config.copyWith(supportedPlatforms: info.supportedPlatforms);
      final nextSources = List<AudioSourceConfig>.from(_sources);
      if (index < 0) {
        nextSources.add(config);
      } else {
        nextSources[index] = config;
      }
      prefs = await SharedPreferences.getInstance();
      storedSources = prefs.getString(_keySources);
      storedId = prefs.getString(_keyActiveSourceId);
      if (config.isRecommendation) {
        journalStarted = true;
        _recommendationRecoveryBlocked = true;
        if (!await prefs.setString(
          _recommendationJournal,
          jsonEncode({'sources': storedSources, 'activeId': storedId}),
        )) {
          throw StateError('无法保存推荐回退记录');
        }
      }
      persistenceStarted = true;
      if (!await prefs.setString(
            _keySources,
            jsonEncode(nextSources.map((source) => source.toJson()).toList()),
          ) ||
          !await prefs.setString(_keyActiveSourceId, config.id)) {
        throw Exception('无法保存音源配置');
      }
      checkBackend();
      candidate?.commit();
      _stopAutomatic();
      _sources = nextSources;
      _activeSourceId = config.id;
      _lxRuntimeSourceId = config.id;
      _lxSourceRevision++;
      loadError = null;
      if (config.isRecommendation) {
        _recommendationRecoveryBlocked = false;
        _recommendationJournalCleanupPending = true;
        try {
          await _finishRecommendationJournalCleanup();
        } catch (_) {
          StructuredLogService.log(
            '[AudioSourceService] 推荐已应用，回退记录待清理；后续保存前将重试',
          );
        }
      }
    } catch (error) {
      _sources = previousSources;
      _activeSourceId = previousId;
      _lxRuntimeSourceId = staged ? previousRuntimeId : null;
      var restored = true;
      if ((persistenceStarted || journalStarted) && prefs != null) {
        try {
          if (persistenceStarted) {
            final restoredSources = storedSources == null
                ? await prefs.remove(_keySources)
                : await prefs.setString(_keySources, storedSources);
            final restoredId = storedId == null
                ? await prefs.remove(_keyActiveSourceId)
                : await prefs.setString(_keyActiveSourceId, storedId);
            restored = restoredSources && restoredId;
          }
          if (restored && journalStarted) {
            _recommendationRecoveryBlocked = false;
            _recommendationJournalCleanupPending = true;
            await _finishRecommendationJournalCleanup();
          }
        } catch (_) {
          restored = false;
        }
      }
      try {
        if (staged) {
          await candidate?.dispose();
        } else if (previous?.isAutomaticRecommendation == true) {
          // The independent automatic contexts were never replaced.
          await _runtime.dispose();
        } else if (previous?.type == AudioSourceType.lxmusic) {
          final content = previous!.scriptContent.isNotEmpty
              ? previous.scriptContent
              : await _loadLxScriptContent();
          final info = content == null || content.isEmpty
              ? null
              : await _runtime.loadScript(content);
          if (info == null || !_runtime.isScriptReady) {
            restored = false;
          } else {
            _lxRuntimeSourceId = previous.id;
            loadError = null;
          }
        } else {
          await _runtime.dispose();
        }
      } catch (_) {
        restored = false;
      }
      if (!restored) {
        loadError = '原音源恢复失败，请重新加载';
        throw Exception('加载音源失败，原配置已保留但恢复未完成，请重新选择音源');
      }
      rethrow;
    } finally {
      try {
        await candidate?.dispose();
      } finally {
        _candidateActivation = null;
        barrier.complete();
        notifyListeners();
      }
    }
  }

  Future<void> addSource(AudioSourceConfig config) =>
      _enqueueMutation(() async {
        if (config.isAutomaticRecommendation) {
          throw StateError('请通过自动推荐入口启用此配置');
        }
        if (_sources.any((s) => s.id == config.id)) throw StateError('音源已存在');
        if (_sources.isEmpty && config.type == AudioSourceType.lxmusic) {
          await _activateConfig(config);
        } else {
          _sources = [..._sources, config];
          await _saveSources();
          notifyListeners();
        }
      });

  Future<void> updateSource(AudioSourceConfig config) =>
      _enqueueMutation(() async {
        final index = _sources.indexWhere((s) => s.id == config.id);
        if (index < 0) throw StateError('音源不存在');
        if (config.isAutomaticRecommendation ||
            _sources[index].isAutomaticRecommendation) {
          throw StateError('自动推荐由服务器维护，请使用检查更新');
        }
        if (config.id == _activeSourceId &&
            config.type == AudioSourceType.lxmusic) {
          await _activateConfig(config);
        } else {
          _sources[index] = config;
          await _saveSources();
          notifyListeners();
        }
      });

  Future<void> removeSource(String id) => _enqueueMutation(() async {
    if (id == navidromeSourceId) return;
    // Deleting the selection does not silently activate another source.
    if (_activeSourceId == id) {
      _activeSourceId = '';
      _invalidateLxRuntime();
      await _runtime.dispose();
      await _saveActiveSourceId();
    }
    _sources.removeWhere((s) => s.id == id);
    await _saveSources();
    notifyListeners();
  });

  Future<void> setActiveSource(String id) {
    final automatic = _sources
        .where((s) => s.id == id && s.isAutomaticRecommendation)
        .firstOrNull;
    if (automatic != null) {
      if (automatic.backendOrigin !=
          SourceRecommendationService.currentOrigin) {
        return Future.error(StateError('该自动推荐来自原服务器，请选择当前服务器的自动推荐'));
      }
      return useAutomaticSource();
    }
    return _enqueueMutation(() async {
      if (id == navidromeSourceId) {
        _activeSourceId = id;
        _invalidateLxRuntime();
        await _runtime.dispose();
        loadError = null;
        await _saveActiveSourceId();
        notifyListeners();
        return;
      }
      final config = _sources.where((s) => s.id == id).firstOrNull;
      if (config == null) throw StateError('音源不存在');
      await _activateConfig(config);
    });
  }

  /// Reload the saved script without downloading or restarting playback.
  Future<void> reloadActiveSource() => setActiveSource(_activeSourceId);

  AudioSourceType get sourceType =>
      activeSource?.type ?? AudioSourceType.lxmusic;

  bool get isConfigured {
    if (isNavidromeActive) {
      return NavidromeSessionService().isConfigured;
    }
    return activeSource != null;
  }

  /// 获取当前活动解析器支持的播放平台列表。
  ///
  /// This is deliberately not used by SearchService. Search capabilities are
  /// owned by SearchProviderCatalog.
  List<String> get currentSupportedPlaybackPlatforms {
    if (isAutomaticActive) return _automatic?.platforms ?? const [];
    if (isNavidromeActive) {
      return const [];
    }
    final source = activeSource;
    if (source == null) {
      // 无活动音源时返回所有平台
      return ['netease', 'apple', 'qq', 'kugou', 'kuwo'];
    }

    // 优先使用音源配置中存储的支持平台
    if (source.supportedPlatforms.isNotEmpty) {
      return source.supportedPlatforms;
    }

    // 如果是洛雪音源且运行时已加载脚本，从运行时获取
    if (source.type == AudioSourceType.lxmusic) {
      final runtime = _runtime;
      if (runtime.isScriptReady && runtime.currentScript != null) {
        final platforms = runtime.currentScript!.supportedPlatforms;
        if (platforms.isNotEmpty) {
          return platforms;
        }
      }
    }

    // 回退到默认配置
    return defaultSupportedPlatforms[source.type] ??
        ['netease', 'apple', 'qq', 'kugou', 'kuwo'];
  }

  /// @deprecated Use [currentSupportedPlaybackPlatforms].
  List<String> get currentSupportedPlatforms =>
      currentSupportedPlaybackPlatforms;

  // ==================== Helper Methods ====================

  /// 验证 URL 格式
  static bool isValidUrl(String url) {
    if (url.isEmpty) return false;
    try {
      final uri = Uri.parse(url);
      return uri.hasScheme && (uri.scheme == 'http' || uri.scheme == 'https');
    } catch (e) {
      return false;
    }
  }

  /// 获取音源类型显示名称
  String getSourceTypeName() {
    switch (sourceType) {
      case AudioSourceType.lxmusic:
        return '洛雪音乐';
      case AudioSourceType.navidrome:
        return 'Navidrome';
    }
  }

  /// 获取音源描述 (兼容旧版 API)
  String getSourceDescription() {
    if (!isConfigured) return '未配置';
    final config = activeSource!;
    if (isNavidromeActive) {
      final baseUrl = NavidromeSessionService().baseUrl;
      return baseUrl.isEmpty ? 'Navidrome (未配置)' : baseUrl;
    }
    return '${config.name} (v${config.version})';
  }

  /// [Deprecated] Use addSource instead
  @Deprecated('Use addSource instead')
  Future<void> configureLxMusicSource({
    required String name,
    required String version,
    required String apiUrl,
    required String apiKey,
    required String scriptSource,
    required String scriptContent,
    String? urlPathTemplate,
    String author = '',
    String description = '',
  }) async {
    // Creating a new source for LxMusic import
    await addSource(
      AudioSourceConfig(
        id: _generateId(),
        type: AudioSourceType.lxmusic,
        name: name,
        version: version,
        url: apiUrl,
        apiKey: apiKey,
        scriptSource: scriptSource,
        scriptContent: scriptContent,
        urlPathTemplate: urlPathTemplate ?? '',
        author: author,
        description: description,
      ),
    );
  }

  // ==================== Legacy File Support ====================

  /// 从文件读取洛雪脚本内容 (Legacy support)
  Future<String?> _loadLxScriptContent() async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      final file = File('${dir.path}/lx_source_script.js');
      if (await file.exists()) {
        return await file.readAsString();
      }
    } catch (e) {
      StructuredLogService.log('❌ [AudioSourceService] 读取脚本内容失败: $e');
    }
    return null;
  }

  /// 清除当前配置
  Future<void> clear() {
    return _enqueueMutation(() async {
      _activeSourceId = '';
      _invalidateLxRuntime();
      await _runtime.dispose();
      await _saveActiveSourceId();
      notifyListeners();
    });
  }

  // ==================== Source Logic (Proxies to Active Source) ====================

  bool isLxSourceSupported(MusicSource source) {
    if (isAutomaticActive) return automaticRouteFor(source) != null;
    if (sourceType != AudioSourceType.lxmusic) return false;
    final sourceCode = _lxSourceCodeMap[source];
    if (sourceCode == null) return false;

    final runtime = _runtime;
    final declaredSources = runtime.currentScript?.supportedSources ?? const [];
    if (runtime.isScriptReady && declaredSources.isNotEmpty) {
      return declaredSources.contains(sourceCode);
    }
    return true;
  }

  String? getLxSourceCode(MusicSource source) => _lxSourceCodeMap[source];

  String getLxQuality(AudioQuality quality) {
    switch (quality) {
      case AudioQuality.standard:
        return '128k';
      case AudioQuality.exhigh:
        return '320k';
      case AudioQuality.lossless:
        return 'flac';
      case AudioQuality.hires:
      case AudioQuality.jymaster:
        return 'flac24bit';
      default:
        return '320k';
    }
  }

  @override
  void dispose() {
    _selectionEpoch++;
    _stopAutomatic();
    if (_automaticBackendListening) {
      UrlService().removeListener(_onAutomaticBackendChanged);
      _automaticBackendListening = false;
    }
    super.dispose();
  }
}
