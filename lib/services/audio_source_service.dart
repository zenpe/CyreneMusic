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
import 'navidrome_session_service.dart';

/// 音源类型枚举
enum AudioSourceType {
  lxmusic,     // 洛雪音乐音源
  navidrome,   // Navidrome
}

/// 音源服务 - 管理音源配置（获取歌曲播放 URL）
///
/// 支持多音源管理，用户可以添加多个音源并选择其中一个作为当前活动音源。
class AudioSourceService extends ChangeNotifier {
  static final AudioSourceService _instance = AudioSourceService._internal();
  factory AudioSourceService() => _instance;
  AudioSourceService._internal();

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
  static const String _keyOldLxSourceDescription = 'audio_source_lx_description';
  static const String _keyOldLxUrlPathTemplate = 'audio_source_lx_url_path_template';

  // ==================== 洛雪音源来源代码映射 ====================
  static const Map<MusicSource, String> _lxSourceCodeMap = {
    MusicSource.netease: 'wy',  // 网易云音乐
    MusicSource.qq: 'tx',       // QQ音乐（腾讯）
    MusicSource.kugou: 'kg',    // 酷狗音乐
    MusicSource.kuwo: 'kw',     // 酷我音乐
  };

  static const List<String> lxQualityOptions = ['128k', '320k', 'flac', 'flac24bit'];

  Future<void> _enqueueMutation(Future<void> Function() mutation) {
    final task = _mutationQueue.catchError((_) {}).then((_) => mutation());
    _mutationQueue = task.catchError((_) {});
    return task;
  }

  void _invalidateLxRuntime() {
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
      await initializeLxRuntime();
    }

    _isInitialized = true;
    StructuredLogService.log('✅ [AudioSourceService] 初始化完成');
  }

  /// 初始化洛雪运行时环境
  Future<void> initializeLxRuntime() async {
    final source = activeSource;
    final generation = ++_lxRuntimeGeneration;
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
      if (_lxRuntimeSourceId == sourceId &&
          LxMusicRuntimeService().isScriptReady) {
        return;
      }

      try {
        StructuredLogService.log('🚀 [AudioSourceService] 正在初始化洛雪运行时: $sourceId');
        String? scriptContent = source.scriptContent;
        if (scriptContent.isEmpty) {
          scriptContent = await _loadLxScriptContent();
        }
        if (scriptContent == null || scriptContent.isEmpty) {
          StructuredLogService.log('⚠️ [AudioSourceService] 未找到洛雪脚本内容，无法初始化运行时');
          return;
        }

        final runtime = LxMusicRuntimeService();
        final loaded = await runtime.loadScript(scriptContent);
        if (loaded == null || !runtime.isScriptReady) {
          StructuredLogService.log('⚠️ [AudioSourceService] 洛雪脚本加载失败: $sourceId');
          return;
        }
        if (generation == _lxRuntimeGeneration &&
            activeSource?.id == sourceId) {
          _lxRuntimeSourceId = sourceId;
          StructuredLogService.log('✅ [AudioSourceService] 洛雪运行时初始化成功: $sourceId');
        }
      } catch (e) {
        StructuredLogService.log('❌ [AudioSourceService] 初始化洛雪运行时失败: $e');
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
            .map((item) => AudioSourceConfig.tryFromJson(
                  Map<String, dynamic>.from(item),
                ))
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

      StructuredLogService.log('🔊 [AudioSourceService] 加载配置完成: ${_sources.length} 个音源');
      if (activeSource != null) {
        StructuredLogService.log('   当前活动音源: ${activeSource!.name} (${activeSource!.type.name})');
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

  /// 添加新音源
  Future<void> addSource(AudioSourceConfig config) {
    return _enqueueMutation(() async {
      _sources.add(config);
      await _saveSources();

      // 如果是第一个音源，自动设为活动
      if (_sources.length == 1) {
        await _setActiveSourceInternal(config.id);
      }

      notifyListeners();
    });
  }

  /// 更新音源
  Future<void> updateSource(AudioSourceConfig config) {
    return _enqueueMutation(() async {
      final index = _sources.indexWhere((s) => s.id == config.id);
      if (index != -1) {
        _sources[index] = config;
        await _saveSources();

        // 如果更新的是当前活动音源，可能需要重新初始化运行时
        if (config.id == _activeSourceId && config.type == AudioSourceType.lxmusic) {
          _invalidateLxRuntime();
          await initializeLxRuntime();
        } else if (config.id == _activeSourceId) {
          _invalidateLxRuntime();
        }

        notifyListeners();
      }
    });
  }

  /// 删除音源
  Future<void> removeSource(String id) {
    return _enqueueMutation(() async {
      if (id == navidromeSourceId) return;
      _sources.removeWhere((s) => s.id == id);
      await _saveSources();

      if (_activeSourceId == id) {
        _activeSourceId = '';
        if (_sources.isNotEmpty) {
          _activeSourceId = _sources.first.id;
          await _saveActiveSourceId();

          // 切换到新音源后初始化运行时（如果是洛雪）
          if (activeSource?.type == AudioSourceType.lxmusic) {
            await initializeLxRuntime();
          }
        } else {
          _invalidateLxRuntime();
          await _saveActiveSourceId();
        }
      }

      notifyListeners();
    });
  }

  /// 设置当前活动音源
  Future<void> setActiveSource(String id) {
    return _enqueueMutation(() => _setActiveSourceInternal(id));
  }

  Future<void> _setActiveSourceInternal(String id) async {
    if (_activeSourceId != id) {
      _activeSourceId = id;
      await _saveActiveSourceId();

      // 切换音源后，如果是洛雪，初始化运行时
      if (activeSource?.type == AudioSourceType.lxmusic) {
        await initializeLxRuntime();
      } else {
        _invalidateLxRuntime();
      }

      notifyListeners();
      StructuredLogService.log('🔊 [AudioSourceService] 切换音源至: ${activeSource?.name}');
    }
  }

  AudioSourceType get sourceType => activeSource?.type ?? AudioSourceType.lxmusic;

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
      final runtime = LxMusicRuntimeService();
      if (runtime.isScriptReady && runtime.currentScript != null) {
        final platforms = runtime.currentScript!.supportedPlatforms;
        if (platforms.isNotEmpty) {
          return platforms;
        }
      }
    }

    // 回退到默认配置
    return defaultSupportedPlatforms[source.type] ?? ['netease', 'apple', 'qq', 'kugou', 'kuwo'];
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
    await addSource(AudioSourceConfig(
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
    ));
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
      await _saveActiveSourceId();
      notifyListeners();
    });
  }

  // ==================== Source Logic (Proxies to Active Source) ====================

  bool isLxSourceSupported(MusicSource source) {
    if (sourceType != AudioSourceType.lxmusic) return false;
    final sourceCode = _lxSourceCodeMap[source];
    if (sourceCode == null) return false;

    final runtime = LxMusicRuntimeService();
    final declaredSources = runtime.currentScript?.supportedSources ?? const [];
    if (runtime.isScriptReady && declaredSources.isNotEmpty) {
      return declaredSources.contains(sourceCode);
    }
    return true;
  }

  String? getLxSourceCode(MusicSource source) => _lxSourceCodeMap[source];

  String getLxQuality(AudioQuality quality) {
    switch (quality) {
      case AudioQuality.standard: return '128k';
      case AudioQuality.exhigh: return '320k';
      case AudioQuality.lossless: return 'flac';
      case AudioQuality.hires:
      case AudioQuality.jymaster: return 'flac24bit';
      default: return '320k';
    }
  }

}
