import 'structured_log_service.dart';

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

/// 音源服务 - 管理音源配置（获取歌曲播放 URL）
///
/// 支持多音源管理，用户可以添加多个音源并选择其中一个作为当前活动音源。
class AudioSourceService extends ChangeNotifier {
  static final AudioSourceService _instance = AudioSourceService._internal();
  factory AudioSourceService() => _instance;
  AudioSourceService._internal()
    : _runtime = LxMusicRuntimeService(),
      _parser = LxMusicSourceParser();

  @visibleForTesting
  AudioSourceService.withDependencies({
    required this._runtime,
    required this._parser,
  });

  final LxRuntime _runtime;
  final LxMusicSourceParser _parser;
  Future<void>? _candidateActivation;
  AudioSourceLoadState get loadState => _candidateActivation != null
      ? AudioSourceLoadState.activating
      : activeSource == null
      ? AudioSourceLoadState.inactive
      : loadError != null
      ? AudioSourceLoadState.failed
      : isNavidromeActive || _runtime.isScriptReady
      ? AudioSourceLoadState.ready
      : AudioSourceLoadState.inactive;
  String? loadError;

  bool get preservesRuntimeDuringActivation =>
      _runtime is LxStagedRuntime &&
      (_runtime as LxStagedRuntime).supportsStaging;

  int _lxSourceRevision = 0;
  int get lxSourceRevision => _lxSourceRevision;

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

  Future<void> _enqueueMutation(Future<void> Function() mutation) {
    final task = _mutationQueue.catchError((_) {}).then((_) => mutation());
    _mutationQueue = task.catchError((_) {});
    return task;
  }

  void _invalidateLxRuntime() {
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
  Future<void> initialize() async {
    if (_isInitialized) return;

    await _loadSettings();

    // 如果当前有活动音源且是洛雪音源，初始化运行时
    if (activeSource?.type == AudioSourceType.lxmusic) {
      try {
        await initializeLxRuntime();
      } catch (_) {
        /* Settings remain accessible for repair. */
      }
    }

    _isInitialized = true;
    StructuredLogService.log('✅ [AudioSourceService] 初始化完成');
  }

  /// 初始化洛雪运行时环境
  Future<void> initializeLxRuntime() async {
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
      _sources = nextSources;
      _activeSourceId = config.id;
      _lxRuntimeSourceId = config.id;
      _lxSourceRevision++;
      loadError = null;
    } catch (error) {
      _sources = previousSources;
      _activeSourceId = previousId;
      _lxRuntimeSourceId = staged ? previousRuntimeId : null;
      var restored = true;
      if (persistenceStarted && prefs != null) {
        try {
          final restoredSources = storedSources == null
              ? await prefs.remove(_keySources)
              : await prefs.setString(_keySources, storedSources);
          final restoredId = storedId == null
              ? await prefs.remove(_keyActiveSourceId)
              : await prefs.setString(_keyActiveSourceId, storedId);
          restored = restoredSources && restoredId;
        } catch (_) {
          restored = false;
        }
      }
      try {
        if (staged) {
          await candidate?.dispose();
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

  Future<void> setActiveSource(String id) => _enqueueMutation(() async {
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
}
