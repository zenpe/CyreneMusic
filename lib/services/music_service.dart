import 'structured_log_service.dart';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/toplist.dart';
import '../models/track.dart';
import '../models/song_detail.dart';
import 'api/api_client.dart';
import 'audio_source_service.dart';
import 'developer_mode_service.dart';
import 'auth_service.dart';
import 'lx_music_runtime_service.dart';
import 'lx_runtime_interface.dart';
import 'navidrome_session_service.dart';

/// 音乐服务 - 处理与音乐相关的API请求
class MusicService extends ChangeNotifier {
  static final MusicService _instance = MusicService._internal();
  factory MusicService() => _instance;
  MusicService._internal();

  /// 榜单列表
  List<Toplist> _toplists = [];
  List<Toplist> get toplists => _toplists;

  /// 是否正在加载
  bool _isLoading = false;
  bool get isLoading => _isLoading;

  /// 错误信息
  String? _errorMessage;
  String? get errorMessage => _errorMessage;
  LxRuntimeFailure? _lastLxFailure;
  LxRuntimeFailure? get lastLxFailure => _lastLxFailure;

  /// 本地榜单持久化缓存 Key
  static const String _kToplistsCacheKey = 'cached_toplists_data_v1';
  static const String _kToplistsCacheTimeKey = 'cached_toplists_time_v1';

  /// 数据是否已缓存（是否已成功加载过）
  bool _isCached = false;
  bool get isCached => _isCached;
  DateTime? _toplistsCacheSavedAt;
  static const _toplistsFreshness = Duration(minutes: 10);

  /// 初始化服务并从本地磁盘恢复缓存
  Future<void> initialize() async {
    await Future.wait([
      AuthService().ensureInitialized(),
      loadCachedToplists(),
    ]);
  }

  /// 尝试从本地持久化缓存恢复榜单数据（实现秒开，防止离线或冷启动直接报错）
  Future<bool> loadCachedToplists() async {
    if (_toplists.isNotEmpty) return true;
    try {
      final prefs = await SharedPreferences.getInstance();
      final jsonStr = prefs.getString(_kToplistsCacheKey);
      if (jsonStr != null && jsonStr.isNotEmpty) {
        final List<dynamic> decoded = jsonDecode(jsonStr);
        final restored = decoded
            .map((item) => Toplist.fromJson(item as Map<String, dynamic>))
            .toList();
        if (restored.isNotEmpty) {
          _toplists = restored;
          _isCached = true;
          final savedAtMs = prefs.getInt(_kToplistsCacheTimeKey);
          _toplistsCacheSavedAt = savedAtMs == null
              ? null
              : DateTime.fromMillisecondsSinceEpoch(savedAtMs);
          _errorMessage = null;
          StructuredLogService.log(
            '💾 [MusicService] 从本地磁盘恢复了 ${_toplists.length} 个榜单',
          );
          notifyListeners();
          return true;
        }
      }
    } catch (e) {
      StructuredLogService.log('⚠️ [MusicService] 读取本地榜单缓存异常: $e');
    }
    return false;
  }

  /// 保存榜单到本地持久化缓存
  Future<void> _saveToplistsToCache() async {
    try {
      if (_toplists.isEmpty) return;
      final prefs = await SharedPreferences.getInstance();
      final listJson = _toplists.map((t) => t.toJson()).toList();
      await prefs.setString(_kToplistsCacheKey, jsonEncode(listJson));
      await prefs.setInt(
        _kToplistsCacheTimeKey,
        DateTime.now().millisecondsSinceEpoch,
      );
      _toplistsCacheSavedAt = DateTime.now();
      StructuredLogService.log('💾 [MusicService] 榜单数据已持久化到磁盘');
    } catch (e) {
      StructuredLogService.log('⚠️ [MusicService] 持久化榜单数据异常: $e');
    }
  }

  /// 获取榜单列表（带缓存）
  Future<void> fetchToplists({
    MusicSource source = MusicSource.netease,
    bool forceRefresh = false,
  }) async {
    // /toplists requires authentication. Ensure the persisted token has been
    // restored before the first request instead of racing app startup.
    await AuthService().ensureInitialized();

    // 如果内存没有，先尝试从本地磁盘恢复
    if (_toplists.isEmpty) {
      await loadCachedToplists();
    }

    // 如果已有缓存且不是强制刷新，直接返回
    if (_isCached &&
        !forceRefresh &&
        _toplistsCacheSavedAt != null &&
        DateTime.now().difference(_toplistsCacheSavedAt!) < _toplistsFreshness) {
      StructuredLogService.log('💾 [MusicService] 使用缓存数据，跳过加载');
      DeveloperModeService().addLog('💾 [MusicService] 使用缓存数据');
      return;
    }

    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      StructuredLogService.log('🎵 [MusicService] 开始获取榜单列表...');
      StructuredLogService.log('🎵 [MusicService] 音乐源: ${source.name}');

      if (forceRefresh) {
        StructuredLogService.log('🔄 [MusicService] 强制刷新模式');
      }

      final result = await ApiClient().getJson(
        '/v1/home/charts',
        timeout: const Duration(seconds: 8),
      );

      StructuredLogService.log('🎵 [MusicService] 响应状态码: ${result.statusCode}');

      if (result.ok) {
        final data = result.data as Map<String, dynamic>;

        if (data['status'] == 200) {
          final toplistsData = data['sections'] as List<dynamic>? ?? const [];
          _toplists = toplistsData
              .map(
                (item) => Toplist.fromJson(
                  item as Map<String, dynamic>,
                  source: source,
                ),
              )
              .toList();

          StructuredLogService.log(
            '✅ [MusicService] 成功获取 ${_toplists.length} 个榜单',
          );

          // 打印每个榜单的歌曲数量
          for (var toplist in _toplists) {
            StructuredLogService.log(
              '   📊 ${toplist.name}: ${toplist.tracks.length} 首歌曲',
            );
          }

          _errorMessage = null;
          _isCached = true; // 标记数据已缓存
          StructuredLogService.log('💾 [MusicService] 数据已缓存');
          await _saveToplistsToCache();
        } else {
          final errMsg = '获取榜单失败: 服务器返回状态 ${data['status']}';
          StructuredLogService.log('❌ [MusicService] $errMsg');
          if (_toplists.isEmpty) {
            _errorMessage = errMsg;
          } else {
            StructuredLogService.log('⚠️ [MusicService] 保持使用旧缓存数据展示');
          }
        }
      } else {
        final errMsg = _describeToplistsFailure(
          statusCode: result.statusCode,
          isNetworkError: result.isNetworkError,
          detail: result.text,
        );
        StructuredLogService.event(
          'music.toplists_request_failed',
          level: LogLevel.warning,
          fields: {
            'status_code': result.statusCode,
            'network_error': result.isNetworkError,
          },
          error: result.text,
        );
        // 关键：如果本地已有缓存榜单，不要将全屏遮蔽为错误状态，继续展示缓存内容！
        if (_toplists.isEmpty) {
          _errorMessage = errMsg;
        } else {
          StructuredLogService.log('⚠️ [MusicService] 网络不可达，继续使用本地离线缓存数据展示');
        }
      }
    } catch (e) {
      final errMsg = '获取榜单失败: $e';
      StructuredLogService.log('❌ [MusicService] $errMsg');
      if (_toplists.isEmpty) {
        _errorMessage = errMsg;
      } else {
        StructuredLogService.log('⚠️ [MusicService] 发生异常，继续使用本地离线缓存数据展示');
      }
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  String _describeToplistsFailure({
    required int statusCode,
    required bool isNetworkError,
    String? detail,
  }) {
    if (statusCode == 401) {
      return '获取榜单失败：登录状态已失效，请重新登录';
    }
    if (isNetworkError || statusCode == 0) {
      final normalized = detail?.toLowerCase() ?? '';
      if (normalized.contains('timeout')) {
        return '获取榜单失败：服务器响应超时，请稍后重试';
      }
      return '获取榜单失败：网络连接异常，请检查网络后重试';
    }
    return '获取榜单失败：HTTP $statusCode';
  }

  /// 刷新榜单（强制重新加载）
  Future<void> refreshToplists({
    MusicSource source = MusicSource.netease,
  }) async {
    StructuredLogService.log('🔄 [MusicService] 手动刷新榜单');
    await fetchToplists(source: source, forceRefresh: true);
  }

  /// 根据英文名称获取榜单
  Toplist? getToplistByNameEn(String nameEn) {
    try {
      return _toplists.firstWhere((toplist) => toplist.nameEn == nameEn);
    } catch (e) {
      return null;
    }
  }

  /// 根据ID获取榜单
  Toplist? getToplistById(int id) {
    try {
      return _toplists.firstWhere((toplist) => toplist.id == id);
    } catch (e) {
      return null;
    }
  }

  /// 获取推荐榜单（前4个）
  List<Toplist> getRecommendedToplists() {
    return _toplists.take(4).toList();
  }

  /// 从所有榜单中随机获取指定数量的歌曲
  List<Track> getRandomTracks(int count) {
    // 收集所有榜单的所有歌曲
    final allTracks = <Track>[];
    for (var toplist in _toplists) {
      allTracks.addAll(toplist.tracks);
    }

    if (allTracks.isEmpty) {
      return [];
    }

    // 去重（基于歌曲ID）
    final uniqueTracks = <int, Track>{};
    for (var track in allTracks) {
      uniqueTracks[track.id] = track;
    }

    final trackList = uniqueTracks.values.toList();

    // 如果歌曲数量不足，返回所有歌曲
    if (trackList.length <= count) {
      return trackList;
    }

    // 随机打乱并返回指定数量
    trackList.shuffle();
    return trackList.take(count).toList();
  }

  /// 获取歌曲详情
  ///
  /// 如果音源未配置，会抛出 [AudioSourceNotConfiguredException] 异常
  Future<SongDetail?> fetchSongDetail({
    required dynamic songId, // 支持 int 和 String
    AudioQuality quality = AudioQuality.exhigh,
    MusicSource source = MusicSource.netease,
    String? title,
    String? artist,
    TrackSourceIds sourceIds = const TrackSourceIds(),
    bool fetchLyrics = true,
    void Function(LxRuntimeFailure? failure)? onLxFailure,
  }) async {
    try {
      StructuredLogService.log(
        '🎵 [MusicService] 获取歌曲详情: $songId (${source.name}), 音质: ${quality.displayName}',
      );
      StructuredLogService.log('   Song ID 类型: ${songId.runtimeType}');
      DeveloperModeService().addLog(
        '🎵 [MusicService] 获取歌曲详情: $songId (${source.name})',
      );

      // 本地音乐不需要音源配置
      if (source == MusicSource.local) {
        DeveloperModeService().addLog('ℹ️ [MusicService] 本地歌曲无需请求');
        return null;
      }

      // Navidrome 使用独立 API
      if (source == MusicSource.navidrome) {
        final session = NavidromeSessionService();
        if (!session.isConfigured) {
          throw AudioSourceNotConfiguredException(
            'Navidrome 未配置，请在设置中配置 Navidrome',
          );
        }
        final api = session.api!;
        final streamUrl = api.buildStreamUrl(songId.toString());
        String lyricText = '';
        String tlyricText = '';
        if (fetchLyrics) {
          try {
            StructuredLogService.log(
              '📝 [MusicService] Navidrome 获取歌词: getLyricsBySongId(songId="$songId")',
            );
            final fetched = await api
                .getLyricsBySongId(songId.toString())
                .timeout(const Duration(seconds: 4));
            if (fetched != null && !fetched.isEmpty) {
              lyricText = fetched.lyric;
              tlyricText = fetched.tlyric;
              StructuredLogService.log(
                '✅ [MusicService] Navidrome 歌词获取成功: getLyricsBySongId',
              );
            } else {
              StructuredLogService.log(
                '⚠️ [MusicService] Navidrome 歌词为空: getLyricsBySongId',
              );
            }
          } catch (e) {
            StructuredLogService.log(
              '⚠️ [MusicService] Navidrome 获取歌词失败（不影响播放）: '
              'getLyricsBySongId: $e',
            );
          }
        }
        return SongDetail(
          id: songId,
          name: '',
          pic: '',
          arName: '',
          alName: '',
          level: quality.displayName,
          size: '0',
          url: streamUrl,
          lyric: lyricText,
          tlyric: tlyricText,
          source: source,
        );
      }

      // 检查音源是否已配置
      final audioSourceService = AudioSourceService();
      if (!audioSourceService.isConfigured) {
        StructuredLogService.log('⚠️ [MusicService] 音源未配置，无法获取歌曲 URL');
        DeveloperModeService().addLog('⚠️ [MusicService] 音源未配置');
        throw AudioSourceNotConfiguredException();
      }

      if (audioSourceService.sourceType != AudioSourceType.lxmusic) {
        throw AudioSourceNotConfiguredException('当前播放音源已废弃，请重新导入洛雪音源');
      }

      return await _fetchSongDetailFromLxMusic(
        songId: songId,
        quality: quality,
        source: source,
        sourceIds: sourceIds,
        audioSourceService: audioSourceService,
        fetchLyrics: fetchLyrics,
        onFailure: onLxFailure,
      );
    } on AudioSourceNotConfiguredException {
      rethrow;
    } catch (e) {
      StructuredLogService.log('❌ [MusicService] 获取歌曲详情异常: $e');
      DeveloperModeService().addLog('❌ [MusicService] 异常: $e');
      return null;
    }
  }

  Future<SongDetail?> fetchLyricOnlySongDetail({
    required dynamic songId,
    required MusicSource source,
    TrackSourceIds sourceIds = const TrackSourceIds(),
    String? title,
    String? artist,
  }) async {
    try {
      DeveloperModeService().addLog(
        '📝 [MusicService] 获取歌词补全: $songId (${source.name})',
      );

      if (source == MusicSource.local) {
        DeveloperModeService().addLog('⚠️ [MusicService] 跳过歌词补全: 本地歌曲 $songId');
        return null;
      }

      if (source == MusicSource.navidrome) {
        final session = NavidromeSessionService();
        if (!session.isConfigured) {
          DeveloperModeService().addLog(
            '⚠️ [MusicService] Navidrome 未配置，无法补全歌词: $songId',
          );
          return null;
        }
        try {
          final fetched = await session.api!
              .getLyricsBySongId(songId.toString())
              .timeout(const Duration(seconds: 4));
          if (fetched == null || fetched.isEmpty) {
            DeveloperModeService().addLog(
              '⚠️ [MusicService] Navidrome 歌词补全无结果(getLyricsBySongId): '
              '$songId',
            );
            return null;
          }
          DeveloperModeService().addLog(
            '✅ [MusicService] Navidrome 歌词补全成功(getLyricsBySongId): '
            '$songId',
          );
          return SongDetail(
            id: songId,
            name: title ?? '',
            pic: '',
            arName: artist ?? '',
            alName: '',
            level: '',
            size: '0',
            url: '',
            lyric: fetched.lyric,
            tlyric: fetched.tlyric,
            source: source,
          );
        } catch (e) {
          StructuredLogService.log('⚠️ [MusicService] Navidrome 歌词补全失败: $e');
          DeveloperModeService().addLog(
            '❌ [MusicService] Navidrome 歌词补全失败(getLyricsBySongId): $e',
          );
          return null;
        }
      }

      final lyricData = await _fetchLyricFromBackend(
        source,
        songId,
        sourceIds: sourceIds,
      );
      if (lyricData == null) {
        DeveloperModeService().addLog(
          '⚠️ [MusicService] 歌词补全无结果: $songId (${source.name})',
        );
        return null;
      }

      DeveloperModeService().addLog(
        '✅ [MusicService] 歌词补全成功: $songId (${source.name})',
      );

      return SongDetail(
        id: songId,
        name: title ?? '',
        pic: '',
        arName: artist ?? '',
        alName: '',
        level: '',
        size: '0',
        url: '',
        lyric: lyricData['lyric'] ?? '',
        tlyric: lyricData['tlyric'] ?? '',
        yrc: lyricData['yrc'] ?? '',
        ytlrc: lyricData['ytlrc'] ?? '',
        qrc: lyricData['qrc'] ?? '',
        qrcTrans: lyricData['qrcTrans'] ?? '',
        source: source,
      );
    } catch (e) {
      StructuredLogService.log('❌ [MusicService] 歌词补全异常: $e');
      DeveloperModeService().addLog('❌ [MusicService] 歌词补全异常: $e');
      return null;
    }
  }

  /// 🎵 洛雪音源：获取歌曲详情
  ///
  /// 洛雪音源 API 格式: GET ${baseUrl}/url/${source}/${songId}/${quality}
  /// 响应格式: { code: 0, url: "音频URL" }
  Future<SongDetail?> _fetchSongDetailFromLxMusic({
    required dynamic songId,
    required AudioQuality quality,
    required MusicSource source,
    required TrackSourceIds sourceIds,
    required AudioSourceService audioSourceService,
    required bool fetchLyrics,
    void Function(LxRuntimeFailure? failure)? onFailure,
  }) async {
    _lastLxFailure = null;
    onFailure?.call(null);
    StructuredLogService.log('🎵 [MusicService] 使用洛雪音源获取歌曲: $songId');
    DeveloperModeService().addLog('🎵 [MusicService] 使用洛雪音源');

    // 获取正确的 songId
    // 不同平台的 ID 字段不同：
    // - 网易云：id (int)
    // - QQ音乐：songmid (String)
    // - 酷狗：hash (String)
    // - 酷我：rid/mid (int)
    final sourceCode = audioSourceService.getLxSourceCode(source);
    final lxQuality = audioSourceService.getLxQuality(quality);
    final sourceId = audioSourceService.activeSource?.id;

    try {
      final String lxSongId = lxPlaybackId(songId, source, sourceIds);
      final runtime = LxMusicRuntimeService();

      // Runtime is a singleton, so readiness must be tied to the active
      // source rather than only to the runtime's initialized flag.
      await audioSourceService.initializeLxRuntime();
      if (audioSourceService.activeSource?.id != sourceId ||
          !runtime.isInitialized ||
          !runtime.isScriptReady) {
        throw Exception('洛雪音源已切换或脚本尚未就绪，请重试');
      }

      if (!audioSourceService.isLxSourceSupported(source)) {
        StructuredLogService.log('⚠️ [MusicService] 当前洛雪脚本不支持 ${source.name}');
        DeveloperModeService().addLog(
          '⚠️ [MusicService] 当前洛雪脚本不支持 ${source.name}',
        );
        throw UnsupportedError('当前洛雪音源不支持 ${source.name}，请切换支持该平台的音源');
      }

      StructuredLogService.log(
        '🌐 [MusicService] 调用洛雪运行时获取 URL: $sourceCode / $lxSongId / $lxQuality',
      );
      DeveloperModeService().addLog('🌐 [Runtime] Get Music URL');

      final audioUrl = await runtime.getMusicUrl(
        source: sourceCode!,
        songId: lxSongId,
        quality: lxQuality,
      );

      if (audioUrl == null || audioUrl.isEmpty) {
        _lastLxFailure = runtime.lastFailure;
        onFailure?.call(_lastLxFailure);
        // Playback resolution errors belong to PlaybackService. Do not write
        // them into the toplist error state, otherwise returning to the home
        // page incorrectly renders the charts section as failed.
        StructuredLogService.log('❌ [MusicService] 洛雪音源返回空 URL');
        DeveloperModeService().addLog('❌ [MusicService] 返回空 URL');
        return null;
      }

      StructuredLogService.log('✅ [MusicService] 洛雪音源获取成功');
      _lastLxFailure = null;
      onFailure?.call(null);
      StructuredLogService.log(
        '   🔗 URL: ${audioUrl.length > 50 ? "${audioUrl.substring(0, 50)}..." : audioUrl}',
      );
      DeveloperModeService().addLog('✅ [MusicService] 获取成功');

      // 🎵 尝试从后端歌词 API 获取歌词
      String lyric = '';
      String tlyric = '';
      String yrc = '';
      String ytlrc = '';
      String qrc = '';
      String qrcTrans = '';
      if (fetchLyrics) {
        try {
          final lyricData = await _fetchLyricFromBackend(
            source,
            songId,
            sourceIds: sourceIds,
          );
          if (lyricData != null) {
            lyric = lyricData['lyric'] ?? '';
            tlyric = lyricData['tlyric'] ?? '';
            yrc = lyricData['yrc'] ?? '';
            ytlrc = lyricData['ytlrc'] ?? '';
            qrc = lyricData['qrc'] ?? '';
            qrcTrans = lyricData['qrcTrans'] ?? '';
            StructuredLogService.log(
              '📝 [MusicService] 成功从后端获取歌词: ${lyric.length} 字符',
            );
            if (qrc.isNotEmpty) {
              StructuredLogService.log('   逐字歌词(QRC): ${qrc.length} 字符');
            }
          }
        } catch (e) {
          StructuredLogService.log('⚠️ [MusicService] 获取歌词失败（不影响播放）: $e');
        }
      } else {
        StructuredLogService.log('ℹ️ [MusicService] 跳过同步歌词拉取，优先返回可播放链接');
      }

      // 洛雪音源只返回 URL，创建一个简化的 SongDetail
      // 注意：歌曲元数据（名称、艺术家、封面等）需要从其他地方获取
      return SongDetail(
        id: songId,
        name: '', // 需要从 Track 信息获取
        pic: '', // 需要从 Track 信息获取
        arName: '', // 需要从 Track 信息获取
        alName: '', // 需要从 Track 信息获取
        level: lxQuality,
        size: '0',
        url: audioUrl,
        lyric: lyric,
        tlyric: tlyric,
        yrc: yrc,
        ytlrc: ytlrc,
        qrc: qrc,
        qrcTrans: qrcTrans,
        source: source,
      );
    } catch (e) {
      if (e is UnsupportedError) rethrow;
      _lastLxFailure =
          LxMusicRuntimeService().lastFailure ?? classifyLxRuntimeFailure(e);
      onFailure?.call(_lastLxFailure);
      StructuredLogService.log('❌ [MusicService] 洛雪音源异常: $e');
      DeveloperModeService().addLog('❌ [MusicService] 异常: $e');
      return null;
    }
  }

  /// 从后端歌词 API 获取歌词（供洛雪音源使用）
  Future<Map<String, String>?> _fetchLyricFromBackend(
    MusicSource source,
    dynamic songId, {
    TrackSourceIds sourceIds = const TrackSourceIds(),
  }) async {
    String path;
    Map<String, dynamic> queryParameters;

    switch (source) {
      case MusicSource.netease:
        path = '/lyrics/netease';
        queryParameters = {'id': songId.toString()};
        break;
      case MusicSource.qq:
        path = '/lyrics/qq';
        queryParameters = {'id': songId.toString()};
        break;
      case MusicSource.kugou:
        path = '/lyrics/kugou';
        final emixSongId = sourceIds.emixSongId;
        if (emixSongId == null) return null;
        queryParameters = {'emixsongid': emixSongId};
        break;
      case MusicSource.kuwo:
        path = '/lyrics/kuwo';
        queryParameters = {'mid': songId.toString()};
        break;
      case MusicSource.navidrome:
        return null;
      default:
        StructuredLogService.log(
          '⚠️ [MusicService] 后端歌词 API 不支持 ${source.name}',
        );
        return null;
    }

    StructuredLogService.log('📝 [MusicService] 获取歌词: $path $queryParameters');

    try {
      final result = await ApiClient().getJson(
        path,
        queryParameters: queryParameters,
        timeout: const Duration(seconds: 10),
      );

      if (result.ok) {
        final data = result.data as Map<String, dynamic>;
        if (data['status'] == 200 && data['data'] != null) {
          final lyricData = data['data'] as Map<String, dynamic>;
          return {
            'lyric': (lyricData['lyric'] ?? '') as String,
            'tlyric': (lyricData['tlyric'] ?? '') as String,
            'yrc': (lyricData['yrc'] ?? '') as String,
            'ytlrc': (lyricData['ytlrc'] ?? '') as String,
            'qrc': (lyricData['qrc'] ?? '') as String,
            'qrcTrans': (lyricData['qrcTrans'] ?? '') as String,
          };
        }
      }
      StructuredLogService.log(
        '⚠️ [MusicService] 歌词 API 返回异常: ${result.statusCode}',
      );
    } catch (e) {
      StructuredLogService.log('❌ [MusicService] 歌词请求失败: $e');
    }
    return null;
  }

  /// 返回 LX Music 协议需要的播放标识，不对平台标识做格式猜测。
  static String lxPlaybackId(
    dynamic songId,
    MusicSource source,
    TrackSourceIds sourceIds,
  ) {
    if (source != MusicSource.kugou) return songId.toString();
    final fileHash = sourceIds.fileHash;
    if (fileHash == null || fileHash.isEmpty) {
      throw const MissingTrackSourceIdentifierException(
        '歌曲标识不完整，请重新搜索或同步',
      );
    }
    return fileHash.toUpperCase();
  }

  /// 获取洛雪音源错误消息

  /// 清除数据和缓存
  void clear() {
    _toplists = [];
    _errorMessage = null;
    _isLoading = false;
    _isCached = false; // 清除缓存标志
    StructuredLogService.log('🗑️ [MusicService] 已清除数据和缓存');
    notifyListeners();
  }

}

/// 音源未配置异常
///
/// 当用户尝试播放歌曲但尚未配置音源时抛出此异常
class AudioSourceNotConfiguredException implements Exception {
  final String message;

  AudioSourceNotConfiguredException([this.message = '音源未配置，请在设置中配置音源']);

  @override
  String toString() => 'AudioSourceNotConfiguredException: $message';
}
