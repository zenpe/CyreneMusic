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
  omniparse,   // OmniParse 音源（兼容现有后端格式）
  lxmusic,     // 洛雪音乐音源
  tunehub,     // TuneHub 音源（公开 API）
  navidrome,   // Navidrome
}

/// 音源服务 - 管理音源配置（获取歌曲播放 URL）
/// 
/// 支持多音源管理，用户可以添加多个音源并选择其中一个作为当前活动音源。
class AudioSourceService extends ChangeNotifier {
  static final AudioSourceService _instance = AudioSourceService._internal();
  factory AudioSourceService() => _instance;
  AudioSourceService._internal();

  /// 所有已配置的音源列表
  List<AudioSourceConfig> _sources = [];

  /// 当前活动音源 ID
  String _activeSourceId = '';

  /// 是否已初始化
  bool _isInitialized = false;

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

  // ==================== TuneHub 音源来源代码映射 ====================
  static const Map<MusicSource, String> _tuneHubSourceCodeMap = {
    MusicSource.netease: 'netease',
    MusicSource.qq: 'qq',
    MusicSource.kuwo: 'kuwo',
  };

  static const List<String> tuneHubQualityOptions = ['128k', '320k', 'flac', 'flac24bit'];

  /// 各音源类型默认支持的搜索平台
  static const Map<AudioSourceType, List<String>> defaultSupportedPlatforms = {
    AudioSourceType.omniparse: ['netease', 'qq', 'kugou', 'kuwo', 'apple', 'spotify'],
    AudioSourceType.tunehub: ['netease', 'qq', 'kuwo'],
    AudioSourceType.lxmusic: [], // 动态从脚本获取
    AudioSourceType.navidrome: [], // Navidrome 使用独立 API
  };

  /// 初始化服务
  Future<void> initialize() async {
    if (_isInitialized) return;

    await _loadSettings();

    // 如果当前有活动音源且是洛雪音源，初始化运行时
    if (activeSource?.type == AudioSourceType.lxmusic) {
      initializeLxRuntime();
    }

    _isInitialized = true;
    print('✅ [AudioSourceService] 初始化完成');
  }

  /// 初始化洛雪运行时环境
  Future<void> initializeLxRuntime() async {
    final source = activeSource;
    if (source == null || source.type != AudioSourceType.lxmusic) return;
    
    try {
      print('🚀 [AudioSourceService] 正在初始化洛雪运行时...');
      // 优先使用 config 中的 scriptContent，如果没有则尝试从文件加载（旧版兼容）
      String? scriptContent = source.scriptContent;
      if (scriptContent.isEmpty) {
        scriptContent = await _loadLxScriptContent();
      }
      
      if (scriptContent != null && scriptContent.isNotEmpty) {
        final runtime = LxMusicRuntimeService();
        if (!runtime.isInitialized) {
          await runtime.initialize();
        }
        await runtime.loadScript(scriptContent);
        print('✅ [AudioSourceService] 洛雪运行时初始化成功');
      } else {
        print('⚠️ [AudioSourceService] 未找到洛雪脚本内容，无法初始化运行时');
      }
    } catch (e) {
      print('❌ [AudioSourceService] 初始化洛雪运行时失败: $e');
    }
  }

  /// 生成唯一 ID
  String _generateId() {
    return '${DateTime.now().millisecondsSinceEpoch}_${Random().nextInt(10000)}';
  }

  /// 从本地存储加载设置
  Future<void> _loadSettings() async {
    try {
      final prefs = await SharedPreferences.getInstance();

      // 1. 加载音源列表
      final sourcesJson = prefs.getString(_keySources);
      if (sourcesJson != null) {
        final List<dynamic> list = jsonDecode(sourcesJson);
        _sources = list.map((e) => AudioSourceConfig.fromJson(e)).toList();
      }

      // 2. 加载活动音源 ID
      _activeSourceId = prefs.getString(_keyActiveSourceId) ?? '';

      // 3. 迁移旧版配置 (如果列表为空但有旧配置)
      if (_sources.isEmpty && prefs.containsKey(_keyOldSourceUrl)) {
        await _migrateOldSettings(prefs);
      }

      print('🔊 [AudioSourceService] 加载配置完成: ${_sources.length} 个音源');
      if (activeSource != null) {
        print('   当前活动音源: ${activeSource!.name} (${activeSource!.type.name})');
      } else {
        print('   当前无活动音源');
      }
      
      notifyListeners();
    } catch (e) {
      print('❌ [AudioSourceService] 加载配置失败: $e');
    }
  }

  /// 迁移旧版配置
  Future<void> _migrateOldSettings(SharedPreferences prefs) async {
    print('🔄 [AudioSourceService] 检测到旧版配置，开始迁移...');
    try {
      final typeIndex = prefs.getInt(_keyOldSourceType) ?? 0;
      final type = AudioSourceType.values[typeIndex];
      final url = prefs.getString(_keyOldSourceUrl) ?? '';
      
      if (url.isEmpty) return;

      final config = AudioSourceConfig(
        id: _generateId(),
        type: type,
        name: type == AudioSourceType.lxmusic 
            ? (prefs.getString(_keyOldLxSourceName) ?? '洛雪音源') 
            : (type == AudioSourceType.tunehub ? 'TuneHub 音源' : 'OmniParse 音源'),
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
      
      // 清理旧配置 (可选，这里暂时保留以防万一)
      print('✅ [AudioSourceService] 迁移完成');
    } catch (e) {
      print('❌ [AudioSourceService] 迁移失败: $e');
    }
  }

  /// 保存音源列表
  Future<void> _saveSources() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final jsonList = _sources.map((e) => e.toJson()).toList();
      await prefs.setString(_keySources, jsonEncode(jsonList));
    } catch (e) {
      print('❌ [AudioSourceService] 保存音源列表失败: $e');
    }
  }

  /// 保存活动音源 ID
  Future<void> _saveActiveSourceId() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_keyActiveSourceId, _activeSourceId);
    } catch (e) {
      print('❌ [AudioSourceService] 保存活动音源 ID 失败: $e');
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
  Future<void> addSource(AudioSourceConfig config) async {
    _sources.add(config);
    await _saveSources();
    
    // 如果是第一个音源，自动设为活动
    if (_sources.length == 1) {
      await setActiveSource(config.id);
    }
    
    notifyListeners();
  }

  /// 更新音源
  Future<void> updateSource(AudioSourceConfig config) async {
    final index = _sources.indexWhere((s) => s.id == config.id);
    if (index != -1) {
      _sources[index] = config;
      await _saveSources();
      
      // 如果更新的是当前活动音源，可能需要重新初始化运行时
      if (config.id == _activeSourceId && config.type == AudioSourceType.lxmusic) {
        initializeLxRuntime();
      }
      
      notifyListeners();
    }
  }

  /// 删除音源
  Future<void> removeSource(String id) async {
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
          initializeLxRuntime();
        }
      } else {
        await _saveActiveSourceId();
      }
    }
    
    notifyListeners();
  }

  /// 设置当前活动音源
  Future<void> setActiveSource(String id) async {
    if (_activeSourceId != id) {
      _activeSourceId = id;
      await _saveActiveSourceId();
      
      // 切换音源后，如果是洛雪，初始化运行时
      if (activeSource?.type == AudioSourceType.lxmusic) {
        initializeLxRuntime();
      }
      
      notifyListeners();
      print('🔊 [AudioSourceService] 切换音源至: ${activeSource?.name}');
    }
  }

  // ==================== Compatibility Getters ====================
  // 保持现有 API 兼容，但基于 activeSource 返回数据

  AudioSourceType get sourceType => activeSource?.type ?? AudioSourceType.omniparse;
  
  String get sourceUrl => activeSource?.url ?? '';
  
  String get lxApiKey => activeSource?.apiKey ?? '';
  
  String get lxSourceName => activeSource?.name ?? '';
  
  String get lxSourceVersion => activeSource?.version ?? '';
  
  String get lxSourceAuthor => activeSource?.author ?? '';
  
  String get lxSourceDescription => activeSource?.description ?? '';
  
  String get lxScriptSource => activeSource?.scriptSource ?? '';
  
  bool get isConfigured {
    if (isNavidromeActive) {
      return NavidromeSessionService().isConfigured;
    }
    return activeSource != null;
  }

  /// 获取当前活动音源支持的搜索平台列表
  List<String> get currentSupportedPlatforms {
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

  String get baseUrl {
    final url = activeSource?.url ?? '';
    if (url.isEmpty) return '';
    return _cleanUrl(url);
  }

  // ==================== Helper Methods ====================

  String _cleanUrl(String url) {
    String result = url.trim();
    while (result.startsWith("'") || result.startsWith('"')) {
      result = result.substring(1);
    }
    while (result.endsWith("'") || result.endsWith('"')) {
      result = result.substring(0, result.length - 1);
    }
    if (result.endsWith('/')) {
      result = result.substring(0, result.length - 1);
    }
    return result;
  }

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
      case AudioSourceType.omniparse:
        return 'OmniParse';
      case AudioSourceType.lxmusic:
        return '洛雪音乐';
      case AudioSourceType.tunehub:
        return 'TuneHub';
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
    if (config.type == AudioSourceType.lxmusic) {
      return '${config.name} (v${config.version})';
    } else if (config.type == AudioSourceType.omniparse) {
      return '${config.name} (URL 已隐藏)';
    }    return config.url;
  }

  /// [Deprecated] Use addSource instead
  @Deprecated('Use addSource for creating new sources or updateSource for existing ones')
  void configure(AudioSourceType type, String url, {String? lxApiKey}) {
     // Compatibility implementation: Update active source or create new if none
     if (activeSource != null) {
       updateSource(activeSource!.copyWith(
         type: type.index != activeSource!.type.index ? null : activeSource!.type, 
         url: url,
         apiKey: lxApiKey
       ));
     } else {
       addSource(AudioSourceConfig(
         id: _generateId(),
         type: type,
         name: type == AudioSourceType.tunehub ? 'TuneHub' : 'OmniParse',
         url: url,
         apiKey: lxApiKey ?? '',
       ));
     }
  }

  /// [Deprecated] Use addSource instead
  @Deprecated('Use addSource instead')
  void configureLxMusicSource({
    required String name,
    required String version,
    required String apiUrl,
    required String apiKey,
    required String scriptSource,
    required String scriptContent,
    String? urlPathTemplate,
    String author = '',
    String description = '',
  }) {
    // Creating a new source for LxMusic import
    addSource(AudioSourceConfig(
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
      print('❌ [AudioSourceService] 读取脚本内容失败: $e');
    }
    return null;
  }
  
  /// 清除当前配置 
  void clear() {
     _activeSourceId = '';
     _saveActiveSourceId();
     notifyListeners();
  }

  // ==================== Source Logic (Proxies to Active Source) ====================

  bool isLxSourceSupported(MusicSource source) {
    if (sourceType != AudioSourceType.lxmusic) return false;
    return _lxSourceCodeMap.containsKey(source);
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

  String buildLxMusicUrl(MusicSource source, dynamic songId, AudioQuality quality) {
    final config = activeSource;
    if (config == null) return '';
    
    final sourceCode = getLxSourceCode(source);
    if (sourceCode == null) throw UnsupportedError('洛雪音源不支持 ${source.name}');
    
    final lxQuality = getLxQuality(quality);
    
    if (config.urlPathTemplate.isNotEmpty) {
      final path = config.urlPathTemplate
          .replaceAll('{source}', sourceCode)
          .replaceAll('{songId}', songId.toString())
          .replaceAll('{quality}', lxQuality);
      return '${baseUrl}$path';
    }
    
    return '${baseUrl}/url/$sourceCode/$songId/$lxQuality';
  }

  Map<String, String> getLxRequestHeaders() {
    return {
      'Content-Type': 'application/json',
      'User-Agent': 'lx-music-request/1.0.0',
      if (lxApiKey.isNotEmpty) 'X-Request-Key': lxApiKey,
    };
  }

  // ==================== API Endpoints ====================

  String get neteaseSongUrl => isConfigured ? '$baseUrl/song' : '';
  String get qqSongUrl => isConfigured ? '$baseUrl/qq/song' : '';
  String get kugouSongUrl => isConfigured ? '$baseUrl/kugou/song' : '';
  String get kuwoSongUrl => isConfigured ? '$baseUrl/kuwo/song' : '';
  String get appleSongUrl => isConfigured ? '$baseUrl/apple/song' : '';
  String get appleStreamUrl => isConfigured ? '$baseUrl/apple/stream' : '';
  String get audioProxyUrl => isConfigured ? '$baseUrl/audio/proxy' : '';

  // ==================== TuneHub Logic ====================

  bool isTuneHubSourceSupported(MusicSource source) {
    if (sourceType != AudioSourceType.tunehub) return false;
    return _tuneHubSourceCodeMap.containsKey(source);
  }

  String? getTuneHubSourceCode(MusicSource source) => _tuneHubSourceCodeMap[source];

  String getTuneHubQuality(AudioQuality quality) {
    switch (quality) {
      case AudioQuality.standard: return '128k';
      case AudioQuality.exhigh: return '320k';
      case AudioQuality.lossless: return 'flac';
      case AudioQuality.hires:
      case AudioQuality.jymaster: return 'flac24bit';
      default: return '320k';
    }
  }

  String buildTuneHubInfoUrl(MusicSource source, dynamic songId) {
    final sourceCode = getTuneHubSourceCode(source);
    if (sourceCode == null) throw UnsupportedError('TuneHub 音源不支持 ${source.name}');
    return '$baseUrl/api/?type=info&source=$sourceCode&id=$songId';
  }

  String buildTuneHubMusicUrl(MusicSource source, dynamic songId, AudioQuality quality) {
    final sourceCode = getTuneHubSourceCode(source);
    if (sourceCode == null) throw UnsupportedError('TuneHub 音源不支持 ${source.name}');
    final tuneHubQuality = getTuneHubQuality(quality);
    return '$baseUrl/api/?type=url&source=$sourceCode&id=$songId&br=$tuneHubQuality';
  }

  String buildTuneHubLyricUrl(MusicSource source, dynamic songId) {
    final sourceCode = getTuneHubSourceCode(source);
    if (sourceCode == null) throw UnsupportedError('TuneHub 音源不支持 ${source.name}');
    return '$baseUrl/api/?type=lrc&source=$sourceCode&id=$songId';
  }

  // ==================== TuneHub v3 API ====================

  /// TuneHub v3 解析端点 URL
  String get tuneHubV3ParseUrl => '$baseUrl/v1/parse';

  /// 获取 TuneHub v3 请求头（包含 API Key 认证）
  Map<String, String> getTuneHubV3Headers() {
    final config = activeSource;
    return {
      'Content-Type': 'application/json',
      if (config?.apiKey.isNotEmpty == true) 
        'X-API-Key': config!.apiKey,
    };
  }

  /// 构建 TuneHub v3 解析请求参数
  Map<String, dynamic> buildTuneHubV3ParseBody(
    MusicSource source, 
    dynamic songId, 
    AudioQuality quality,
  ) {
    final platform = getTuneHubSourceCode(source);
    if (platform == null) throw UnsupportedError('TuneHub 音源不支持 ${source.name}');
    
    return {
      'platform': platform,
      'ids': songId.toString(),
      'quality': getTuneHubQuality(quality),
    };
  }
}

