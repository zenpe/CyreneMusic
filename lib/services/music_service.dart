import 'structured_log_service.dart';
import 'dart:convert';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../models/toplist.dart';
import '../models/track.dart';
import '../models/song_detail.dart';
import 'api/api_client.dart';
import 'audio_source_service.dart';
import 'developer_mode_service.dart';
import 'audio_quality_service.dart';
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
    if (_isCached && !forceRefresh) {
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
        '/toplists',
        timeout: const Duration(seconds: 20),
      );

      StructuredLogService.log('🎵 [MusicService] 响应状态码: ${result.statusCode}');

      if (result.ok) {
        final data = result.data as Map<String, dynamic>;

        if (data['status'] == 200) {
          final toplistsData = data['toplists'] as List<dynamic>;
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

      // 🎵 洛雪音源：使用专门的 API 格式
      if (audioSourceService.sourceType == AudioSourceType.lxmusic) {
        return await _fetchSongDetailFromLxMusic(
          songId: songId,
          quality: quality,
          source: source,
          audioSourceService: audioSourceService,
          fetchLyrics: fetchLyrics,
          onFailure: onLxFailure,
        );
      }

      // 🎵 TuneHub 音源：使用 TuneHub API 格式
      if (audioSourceService.sourceType == AudioSourceType.tunehub) {
        return await _fetchSongDetailFromTuneHub(
          songId: songId,
          quality: quality,
          source: source,
          audioSourceService: audioSourceService,
          fetchLyrics: fetchLyrics,
        );
      }

      // OmniParse 格式（原有逻辑）
      final baseUrl = audioSourceService.baseUrl;
      // 获取 OmniParse API Key
      final omniParseApiKey = audioSourceService.activeSource?.apiKey ?? '';

      // 🔧 OmniParse 音质降级处理：hires 和 jyeffect 只支持网易云平台
      final qualityService = AudioQualityService();
      final platformQualities = qualityService.getOmniParseQualitiesForPlatform(
        source,
      );
      final effectiveQuality = qualityService.getEffectiveQuality(
        quality,
        platformQualities,
      );
      if (effectiveQuality != quality) {
        StructuredLogService.log(
          '🔄 [MusicService] OmniParse 音质降级: ${quality.displayName} -> ${effectiveQuality.displayName} (平台: ${source.name})',
        );
        DeveloperModeService().addLog(
          '🔄 [MusicService] 音质降级到 ${effectiveQuality.displayName}',
        );
      }

      String url;
      http.Response response;

      switch (source) {
        case MusicSource.netease:
          // 网易云音乐
          url = '$baseUrl/song';
          final requestBody = {
            'ids': songId.toString(),
            'level': effectiveQuality.value,
            'type': 'json',
          };

          DeveloperModeService().addLog('🌐 [Network] POST $url');
          DeveloperModeService().addLog(
            '📤 [Network] 请求体: ${requestBody.toString()}',
          );

          response = await http
              .post(
                Uri.parse(url),
                headers: {
                  'Content-Type': 'application/x-www-form-urlencoded',
                  if (omniParseApiKey.isNotEmpty) 'X-API-Key': omniParseApiKey,
                },
                body: requestBody,
              )
              .timeout(
                const Duration(seconds: 15),
                onTimeout: () {
                  DeveloperModeService().addLog('⏱️ [Network] 请求超时 (15s)');
                  throw Exception('请求超时');
                },
              );
          break;

        case MusicSource.apple:
          // Apple Music
          // 后端对齐网易云 song 接口返回结构：{status,id,name,pic,ar_name,al_name,level,size,url,lyric,tlyric}
          // 注意：后端返回的 url 是加密的 HLS 流，需要使用 /apple/stream 端点获取解密后的音频
          url = '$baseUrl/apple/song?salableAdamId=$songId&storefront=cn';
          DeveloperModeService().addLog('🌐 [Network] GET $url');

          response = await http
              .get(
                Uri.parse(url),
                headers: {'Content-Type': 'application/json'},
              )
              .timeout(
                const Duration(seconds: 15),
                onTimeout: () {
                  DeveloperModeService().addLog('⏱️ [Network] 请求超时 (15s)');
                  throw Exception('请求超时');
                },
              );
          break;

        case MusicSource.qq:
          // QQ音乐
          url = '$baseUrl/qq/song?ids=$songId';
          DeveloperModeService().addLog('🌐 [Network] GET $url');

          response = await http
              .get(
                Uri.parse(url),
                headers: {
                  'Content-Type': 'application/json',
                  if (omniParseApiKey.isNotEmpty) 'X-API-Key': omniParseApiKey,
                },
              )
              .timeout(
                const Duration(seconds: 15),
                onTimeout: () {
                  DeveloperModeService().addLog('⏱️ [Network] 请求超时 (15s)');
                  throw Exception('请求超时');
                },
              );
          break;

        case MusicSource.kugou:
          // 酷狗音乐 - 需要传递用户 token 以使用绑定的酷狗账号
          // 支持两种 ID 格式：
          // 1. "emixsongid" - 来自搜索结果（优先使用，更稳定）
          // 2. "hash" 或 "hash:album_audio_id" - 来自歌单导入（备用）
          final songIdStr = songId.toString();
          if (songIdStr.contains(':')) {
            // 格式: "hash:album_audio_id" - 使用hash值
            final parts = songIdStr.split(':');
            final hash = parts[0].toUpperCase(); // 确保hash为大写
            if (hash.isEmpty) {
              throw Exception('酷狗歌曲hash值不能为空');
            }
            url = '$baseUrl/kugou/song?hash=$hash';
          } else {
            // 判断是hash还是emixsongid
            // hash通常是32位十六进制字符串，emixsongid通常是其他格式
            final idStr = songIdStr.toUpperCase();
            final isHash =
                idStr.length == 32 && RegExp(r'^[0-9A-F]+$').hasMatch(idStr);

            if (isHash) {
              // 32位十六进制字符串，是hash
              url = '$baseUrl/kugou/song?hash=$idStr';
            } else {
              // 否则是emixsongid（优先使用，更稳定）
              url = '$baseUrl/kugou/song?emixsongid=$songId';
            }
          }
          DeveloperModeService().addLog('🌐 [Network] GET $url');

          final authToken = AuthService().token;
          response = await http
              .get(
                Uri.parse(url),
                headers: {
                  'Content-Type': 'application/json',
                  if (authToken != null) 'Authorization': 'Bearer $authToken',
                  if (omniParseApiKey.isNotEmpty) 'X-API-Key': omniParseApiKey,
                },
              )
              .timeout(
                const Duration(seconds: 15),
                onTimeout: () {
                  DeveloperModeService().addLog('⏱️ [Network] 请求超时 (15s)');
                  throw Exception('请求超时');
                },
              );
          break;

        case MusicSource.kuwo:
          // 酷我音乐 - 使用 rid 获取歌曲详情
          url = '$baseUrl/kuwo/song?mid=$songId';
          DeveloperModeService().addLog('🌐 [Network] GET $url');

          response = await http
              .get(
                Uri.parse(url),
                headers: {
                  'Content-Type': 'application/json',
                  if (omniParseApiKey.isNotEmpty) 'X-API-Key': omniParseApiKey,
                },
              )
              .timeout(
                const Duration(seconds: 15),
                onTimeout: () {
                  DeveloperModeService().addLog('⏱️ [Network] 请求超时 (15s)');
                  throw Exception('请求超时');
                },
              );
          break;

        case MusicSource.navidrome:
          return null;
        case MusicSource.spotify:
          // Spotify 歌曲详情处理
          return await _fetchSongDetailFromSpotify(
            songId: songId,
            quality: effectiveQuality,
          );

        case MusicSource.local:
          // 本地音乐已在方法开头处理，不会到达这里
          // 保留 case 以满足 switch 完整性
          return null;
      }

      StructuredLogService.log(
        '🎵 [MusicService] 歌曲详情响应状态码: ${response.statusCode}',
      );
      DeveloperModeService().addLog('📥 [Network] 状态码: ${response.statusCode}');

      if (response.statusCode == 200) {
        final responseBody = utf8.decode(response.bodyBytes);
        final truncatedBody = responseBody.length > 500
            ? '${responseBody.substring(0, 500)}...'
            : responseBody;
        DeveloperModeService().addLog('📄 [Network] 响应体: $truncatedBody');

        final data = json.decode(responseBody) as Map<String, dynamic>;

        // 🔍 调试：打印后端返回的完整数据（根据音乐源不同处理）
        StructuredLogService.log('🔍 [MusicService] 后端返回的数据 (${source.name}):');
        StructuredLogService.log('   status: ${data['status']}');

        if (source == MusicSource.qq) {
          // QQ音乐格式
          StructuredLogService.log('   song 字段存在: ${data.containsKey('song')}');
          if (data.containsKey('song')) {
            final song = data['song'] as Map<String, dynamic>?;
            StructuredLogService.log('   name: ${song?['name']}');
          }
          StructuredLogService.log(
            '   lyric 字段存在: ${data.containsKey('lyric')}',
          );
          if (data.containsKey('lyric')) {
            final lyricData = data['lyric'];
            StructuredLogService.log('   lyric 类型: ${lyricData.runtimeType}');
            if (lyricData is Map) {
              final lyricText = lyricData['lyric'];
              StructuredLogService.log(
                '   lyric.lyric 类型: ${lyricText.runtimeType}',
              );
              if (lyricText is String) {
                StructuredLogService.log(
                  '   lyric.lyric 长度: ${lyricText.length}',
                );
              }
            }
          }
          StructuredLogService.log(
            '   music_urls 字段存在: ${data.containsKey('music_urls')}',
          );
        } else {
          // 网易云/Apple/酷狗/酷我格式
          StructuredLogService.log('   name: ${data['name']}');
          StructuredLogService.log('   url: ${data['url']}');
          StructuredLogService.log(
            '   lyric 字段存在: ${data.containsKey('lyric')}',
          );
          StructuredLogService.log(
            '   tlyric 字段存在: ${data.containsKey('tlyric')}',
          );
          if (data.containsKey('lyric')) {
            final lyricContent = data['lyric'];
            StructuredLogService.log(
              '   ✅ lyric 类型: ${lyricContent.runtimeType}',
            );
            if (lyricContent is String) {
              StructuredLogService.log('   ✅ lyric 长度: ${lyricContent.length}');
              if (lyricContent.isNotEmpty && lyricContent.length > 100) {
                final preview = lyricContent.substring(0, 100);
                StructuredLogService.log('   ✅ lyric 前100字符: $preview');
              }
            }
          }
        }

        if (data['status'] == 200) {
          SongDetail songDetail;

          if (source == MusicSource.qq) {
            // QQ音乐返回格式特殊处理
            final song = data['song'] as Map<String, dynamic>;
            final lyricData = data['lyric'] as Map<String, dynamic>?;
            final musicUrls = data['music_urls'] as Map<String, dynamic>?;

            // 根据用户选择的音质选择播放URL
            String playUrl = '';
            String bitrate = '';
            if (musicUrls != null) {
              // 使用 AudioQualityService 选择最佳音质
              playUrl =
                  AudioQualityService().selectBestQQMusicUrl(musicUrls) ?? '';

              // 获取对应的 bitrate 信息
              final qualityKey = AudioQualityService().getQQMusicQualityKey();
              if (musicUrls[qualityKey] != null) {
                bitrate = musicUrls[qualityKey]['bitrate'] ?? qualityKey;
              } else {
                // 降级时获取实际使用的音质
                if (musicUrls['flac'] != null &&
                    playUrl == musicUrls['flac']['url']) {
                  bitrate = musicUrls['flac']['bitrate'] ?? 'FLAC';
                } else if (musicUrls['320'] != null &&
                    playUrl == musicUrls['320']['url']) {
                  bitrate = musicUrls['320']['bitrate'] ?? '320kbps';
                } else if (musicUrls['128'] != null &&
                    playUrl == musicUrls['128']['url']) {
                  bitrate = musicUrls['128']['bitrate'] ?? '128kbps';
                }
              }
            }

            // 安全获取歌词（后端返回的是 {lyric: string, tylyric: string, qrc: string, qrcTrans: string}）
            String lyricText = '';
            String tlyricText = '';
            String qrcText = '';
            String qrcTransText = '';
            if (lyricData != null) {
              // 确保类型安全：检查是否为String
              final lyricValue = lyricData['lyric'];
              final tlyricValue = lyricData['tylyric'];
              final qrcValue = lyricData['qrc'];
              final qrcTransValue = lyricData['qrcTrans'];

              lyricText = lyricValue is String ? lyricValue : '';
              tlyricText = tlyricValue is String ? tlyricValue : '';
              qrcText = qrcValue is String ? qrcValue : '';
              qrcTransText = qrcTransValue is String ? qrcTransValue : '';

              StructuredLogService.log('🎵 [MusicService] OmniParse QQ音乐歌词获取:');
              StructuredLogService.log(
                '   原文歌词: ${lyricText.isNotEmpty ? "${lyricText.length}字符" : "无"}',
              );
              StructuredLogService.log(
                '   翻译歌词: ${tlyricText.isNotEmpty ? "${tlyricText.length}字符" : "无"}',
              );
              StructuredLogService.log(
                '   逐字歌词(QRC): ${qrcText.isNotEmpty ? "${qrcText.length}字符" : "无"}',
              );
              StructuredLogService.log(
                '   📋 lyricData 原始字段: ${lyricData.keys.toList()}',
              );
            }

            songDetail = SongDetail(
              id: song['mid'] ?? song['id'] ?? songId,
              name: song['name'] ?? '',
              pic: song['pic'] ?? '',
              arName: song['singer'] ?? '',
              alName: song['album'] ?? '',
              level: bitrate,
              size: '0', // QQ音乐不返回文件大小
              url: playUrl,
              lyric: lyricText,
              tlyric: tlyricText,
              qrc: qrcText,
              qrcTrans: qrcTransText,
              source: source,
            );
          } else if (source == MusicSource.kugou) {
            // 酷狗音乐返回格式
            final song = data['song'] as Map<String, dynamic>?;
            if (song == null) {
              StructuredLogService.log('❌ [MusicService] 酷狗音乐返回数据格式错误');
              return null;
            }

            // 调试：打印酷狗音乐返回的 song 对象
            StructuredLogService.log('🔍 [MusicService] 酷狗音乐 song 对象:');
            StructuredLogService.log('   name: ${song['name']}');
            StructuredLogService.log('   singer: ${song['singer']}');
            StructuredLogService.log('   album: ${song['album']}');
            StructuredLogService.log('   pic: ${song['pic']}');
            StructuredLogService.log(
              '   url: ${song['url'] != null ? '已获取' : '无'}',
            );

            // 处理 bitrate（可能是 int 或 String）
            final bitrateValue = song['bitrate'];
            final bitrate = bitrateValue != null ? '${bitrateValue}kbps' : '未知';

            songDetail = SongDetail(
              id: songId, // 使用传入的 emixsongid
              name: song['name'] ?? '',
              pic: song['pic'] ?? '',
              arName: song['singer'] ?? '',
              alName: song['album'] ?? '',
              level: bitrate,
              size: song['duration']?.toString() ?? '0', // 使用 duration 字段
              url: song['url'] ?? '',
              lyric: song['lyric'] ?? '',
              tlyric: '', // 酷狗音乐没有翻译歌词
              source: source,
            );
          } else if (source == MusicSource.kuwo) {
            // 酷我音乐返回格式
            final song = data['song'] as Map<String, dynamic>?;
            if (song == null) {
              StructuredLogService.log('❌ [MusicService] 酷我音乐返回数据格式错误');
              return null;
            }

            // 调试：打印酷我音乐返回的 song 对象
            StructuredLogService.log('🔍 [MusicService] 酷我音乐 song 对象:');
            StructuredLogService.log('   name: ${song['name']}');
            StructuredLogService.log('   artist: ${song['artist']}');
            StructuredLogService.log('   album: ${song['album']}');
            StructuredLogService.log('   pic: ${song['pic']}');
            StructuredLogService.log(
              '   url: ${song['url'] != null ? '已获取' : '无'}',
            );
            StructuredLogService.log('   duration: ${song['duration']}');

            // 获取歌词
            final lyricText = song['lyric'] is String
                ? song['lyric'] as String
                : '';

            StructuredLogService.log('🎵 [MusicService] 酷我歌词获取结果:');
            StructuredLogService.log(
              '   lyricText类型: ${song['lyric'].runtimeType}',
            );
            StructuredLogService.log('   lyricText长度: ${lyricText.length}');
            if (lyricText.isNotEmpty) {
              StructuredLogService.log(
                '   lyricText前50字符: ${lyricText.substring(0, min(50, lyricText.length))}',
              );
              StructuredLogService.log(
                '   lyricText包含换行符: ${lyricText.contains('\n')}',
              );
            } else {
              StructuredLogService.log('   ❌ 歌词为空！');
              StructuredLogService.log(
                '   完整 song 对象 keys: ${song.keys.toList()}',
              );
            }

            songDetail = SongDetail(
              id: songId, // 使用传入的 rid
              name: song['name'] ?? '',
              pic: song['pic'] ?? '',
              arName: song['artist'] ?? '',
              alName: song['album'] ?? '',
              level: '未知', // 酷我音乐API未返回音质信息
              size: song['duration']?.toString() ?? '0', // 使用 duration 字段
              url: song['url'] ?? '',
              lyric: lyricText,
              tlyric: '', // 酷我音乐没有翻译歌词
              source: source,
            );
          } else if (source == MusicSource.apple) {
            // Apple Music - 需要特殊处理 URL
            // 后端返回的 url 是加密的 HLS 流，需要替换为解密流端点
            StructuredLogService.log(
              '🔧 [MusicService] 开始解析 Apple Music 数据...',
            );

            final originalUrl = data['url'] as String? ?? '';
            final isEncrypted =
                data['isEncrypted'] as bool? ??
                (originalUrl.contains('.m3u8') ||
                    originalUrl.contains('aod-ssl.itunes.apple.com'));

            // 如果是加密流，使用后端的解密流端点
            String playUrl = originalUrl;
            if (isEncrypted && originalUrl.isNotEmpty) {
              // 构建解密流端点 URL
              playUrl = '$baseUrl/apple/stream?salableAdamId=$songId';
              StructuredLogService.log(
                '🔐 [MusicService] Apple Music 流已加密，使用解密端点: $playUrl',
              );
              DeveloperModeService().addLog('🔐 [MusicService] 使用解密流端点');
            }

            songDetail = SongDetail(
              id: data['id'] ?? songId,
              name: data['name'] ?? '',
              pic: data['pic'] ?? '',
              arName: data['ar_name'] ?? '',
              alName: data['al_name'] ?? '',
              level: data['level'] ?? '',
              size: data['size'] ?? '0',
              url: playUrl,
              lyric: data['lyric'] ?? '',
              tlyric: data['tlyric'] ?? '',
              source: source,
            );

            StructuredLogService.log(
              '🔧 [MusicService] 解析完成，检查 SongDetail 对象:',
            );
            StructuredLogService.log(
              '   songDetail.lyric 长度: ${songDetail.lyric.length}',
            );
            StructuredLogService.log(
              '   songDetail.tlyric 长度: ${songDetail.tlyric.length}',
            );
            StructuredLogService.log('   songDetail.url: ${songDetail.url}');
          } else {
            // 网易云音乐（同结构）
            StructuredLogService.log(
              '🔧 [MusicService] 开始解析 ${source.name} 数据...',
            );
            songDetail = SongDetail.fromJson(data, source: source);
            StructuredLogService.log(
              '🔧 [MusicService] 解析完成，检查 SongDetail 对象:',
            );
            StructuredLogService.log(
              '   songDetail.lyric 长度: ${songDetail.lyric.length}',
            );
            StructuredLogService.log(
              '   songDetail.tlyric 长度: ${songDetail.tlyric.length}',
            );
          }

          StructuredLogService.log(
            '✅ [MusicService] 成功获取歌曲详情: ${songDetail.name}',
          );
          StructuredLogService.log(
            '   🆔 ID: ${songDetail.id} (类型: ${songDetail.id.runtimeType})',
          );
          StructuredLogService.log('   🎵 艺术家: ${songDetail.arName}');
          StructuredLogService.log('   💿 专辑: ${songDetail.alName}');
          StructuredLogService.log(
            '   🖼️ 封面: ${songDetail.pic.isNotEmpty ? songDetail.pic : "无"}',
          );
          StructuredLogService.log('   🎼 音质: ${songDetail.level}');
          StructuredLogService.log('   📦 大小: ${songDetail.size}');
          StructuredLogService.log(
            '   🔗 URL: ${songDetail.url.isNotEmpty ? "已获取" : "无"}',
          );
          StructuredLogService.log(
            '   📝 歌词: ${songDetail.lyric.isNotEmpty ? "${songDetail.lyric.length} 字符" : "无"}',
          );
          StructuredLogService.log(
            '   🌏 翻译: ${songDetail.tlyric.isNotEmpty ? "${songDetail.tlyric.length} 字符" : "无"}',
          );

          DeveloperModeService().addLog(
            '✅ [MusicService] 成功获取歌曲: ${songDetail.name}',
          );

          return songDetail;
        } else {
          StructuredLogService.log(
            '❌ [MusicService] 获取歌曲详情失败: 服务器返回状态 ${data['status']}',
          );
          DeveloperModeService().addLog(
            '❌ [MusicService] 服务器状态 ${data['status']}',
          );
          return null;
        }
      } else {
        StructuredLogService.log(
          '❌ [MusicService] 获取歌曲详情失败: HTTP ${response.statusCode}',
        );
        DeveloperModeService().addLog(
          '❌ [Network] HTTP ${response.statusCode}',
        );
        return null;
      }
    } on AudioSourceNotConfiguredException {
      // 音源未配置异常需要向上传递，由 PlayerService 处理并显示弹窗
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

      final lyricData = await _fetchLyricFromBackend(source, songId);
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
    final String lxSongId = _extractLxSongId(songId, source);
    final sourceCode = audioSourceService.getLxSourceCode(source);
    final lxQuality = audioSourceService.getLxQuality(quality);
    final sourceId = audioSourceService.activeSource?.id;

    try {
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
          final lyricData = await _fetchLyricFromBackend(source, songId);
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
    dynamic songId,
  ) async {
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
        // 酷狗可能使用 hash 或 emixsongid
        final idStr = songId.toString();
        path = '/lyrics/kugou';
        if (idStr.length == 32 && RegExp(r'^[0-9A-Fa-f]+$').hasMatch(idStr)) {
          queryParameters = {'hash': idStr};
        } else {
          queryParameters = {'emixsongid': songId.toString()};
        }
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

  /// 从 songId 中提取洛雪音源所需的 ID
  String _extractLxSongId(dynamic songId, MusicSource source) {
    final idStr = songId.toString();

    // 酷狗音乐可能使用 "hash:album_audio_id" 格式，提取 hash
    if (source == MusicSource.kugou && idStr.contains(':')) {
      return idStr.split(':')[0].toUpperCase();
    }

    return idStr;
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

  /// 🎵 TuneHub 音源：获取歌曲详情
  ///
  /// TuneHub v3 API 格式: POST ${baseUrl}/v1/parse
  /// 请求头: X-API-Key: {apiKey}
  /// 请求体: { platform, ids, quality }
  /// 响应格式: { code: 200, data: { id, name, artist, album, pic, url, lrc } }
  Future<SongDetail?> _fetchSongDetailFromTuneHub({
    required dynamic songId,
    required AudioQuality quality,
    required MusicSource source,
    required AudioSourceService audioSourceService,
    required bool fetchLyrics,
  }) async {
    StructuredLogService.log('🎵 [MusicService] 使用 TuneHub v3 音源获取歌曲: $songId');
    DeveloperModeService().addLog('🎵 [MusicService] 使用 TuneHub v3 音源');

    // 检查来源是否被 TuneHub 音源支持
    if (!audioSourceService.isTuneHubSourceSupported(source)) {
      StructuredLogService.log(
        '⚠️ [MusicService] TuneHub 音源不支持 ${source.name}',
      );
      DeveloperModeService().addLog(
        '⚠️ [MusicService] TuneHub 音源不支持 ${source.name}',
      );
      throw UnsupportedError('TuneHub 音源不支持 ${source.name}，请切换到其他音源');
    }

    try {
      // 构建 TuneHub v3 API 请求
      final parseUrl = audioSourceService.tuneHubV3ParseUrl;
      final headers = audioSourceService.getTuneHubV3Headers();
      final body = audioSourceService.buildTuneHubV3ParseBody(
        source,
        songId,
        quality,
      );

      StructuredLogService.log(
        '🌐 [MusicService] TuneHub v3 音源请求: POST $parseUrl',
      );
      StructuredLogService.log('   📦 Body: $body');
      DeveloperModeService().addLog('🌐 [Network] POST $parseUrl');

      final response = await http
          .post(Uri.parse(parseUrl), headers: headers, body: json.encode(body))
          .timeout(
            const Duration(seconds: 15),
            onTimeout: () {
              DeveloperModeService().addLog('⏱️ [Network] 请求超时 (15s)');
              throw Exception('请求超时');
            },
          );

      StructuredLogService.log(
        '🎵 [MusicService] TuneHub v3 音源响应状态码: ${response.statusCode}',
      );
      DeveloperModeService().addLog('📥 [Network] 状态码: ${response.statusCode}');

      if (response.statusCode == 200) {
        final responseBody = utf8.decode(response.bodyBytes);
        final truncatedBody = responseBody.length > 300
            ? '${responseBody.substring(0, 300)}...'
            : responseBody;
        DeveloperModeService().addLog('📄 [Network] 响应体: $truncatedBody');

        final data = json.decode(responseBody) as Map<String, dynamic>;
        final code = data['code'];
        final success = data['success'] as bool? ?? false;

        // TuneHub v3 响应码处理：code == 0 或 success == true 表示成功
        if (code == 0 || success) {
          // v3 格式：data.data 是数组
          final outerData = data['data'] as Map<String, dynamic>?;
          final dataList = outerData?['data'] as List<dynamic>?;

          if (dataList == null || dataList.isEmpty) {
            StructuredLogService.log('❌ [MusicService] TuneHub v3 音源返回空数据');
            DeveloperModeService().addLog('❌ [MusicService] 返回空数据');
            return null;
          }

          // 获取第一个结果
          final songData = dataList[0] as Map<String, dynamic>;

          // 检查单曲是否成功
          final itemSuccess = songData['success'] as bool? ?? false;
          if (!itemSuccess) {
            final errorMsg = songData['error'] as String? ?? '获取失败';
            StructuredLogService.log(
              '❌ [MusicService] TuneHub v3 单曲获取失败: $errorMsg',
            );
            DeveloperModeService().addLog('❌ [MusicService] 错误: $errorMsg');
            throw Exception(errorMsg);
          }

          // 获取播放 URL（v3 直接返回完整 URL）
          String audioUrl = songData['url'] as String? ?? '';

          // 获取歌曲信息（v3 格式在 info 对象中）
          final info = songData['info'] as Map<String, dynamic>? ?? {};
          final songName = info['name'] as String? ?? '';
          final artistName = info['artist'] as String? ?? '';
          final albumName = info['album'] as String? ?? '';

          // 封面图片（v3 使用 cover 字段）
          final coverUrl = songData['cover'] as String? ?? '';

          // 🎵 使用后端歌词 API 获取歌词（与洛雪音源保持一致）
          String lyricText = '';
          String tlyricText = '';
          String yrcText = '';
          String ytlrcText = '';
          String qrcText = '';
          String qrcTransText = '';
          if (fetchLyrics) {
            try {
              final lyricData = await _fetchLyricFromBackend(source, songId);
              if (lyricData != null) {
                lyricText = lyricData['lyric'] ?? '';
                tlyricText = lyricData['tlyric'] ?? '';
                yrcText = lyricData['yrc'] ?? '';
                ytlrcText = lyricData['ytlrc'] ?? '';
                qrcText = lyricData['qrc'] ?? '';
                qrcTransText = lyricData['qrcTrans'] ?? '';
                StructuredLogService.log(
                  '📝 [MusicService] TuneHub v3 成功从后端获取歌词: ${lyricText.length} 字符',
                );
                if (qrcText.isNotEmpty) {
                  StructuredLogService.log(
                    '   逐字歌词(QRC): ${qrcText.length} 字符',
                  );
                }
              }
            } catch (e) {
              StructuredLogService.log(
                '⚠️ [MusicService] TuneHub v3 获取歌词失败（不影响播放）: $e',
              );
            }
          } else {
            StructuredLogService.log(
              'ℹ️ [MusicService] TuneHub v3 跳过同步歌词拉取，优先返回可播放链接',
            );
          }

          // 获取实际音质信息
          final actualQuality =
              songData['actualQuality'] as String? ??
              audioSourceService.getTuneHubQuality(quality);

          StructuredLogService.log('✅ [MusicService] TuneHub v3 音源获取成功');
          StructuredLogService.log('   🎵 歌曲: $songName');
          StructuredLogService.log('   🎤 艺术家: $artistName');
          StructuredLogService.log('   💿 专辑: $albumName');
          StructuredLogService.log(
            '   🔗 URL: ${audioUrl.length > 50 ? "${audioUrl.substring(0, 50)}..." : audioUrl}',
          );
          DeveloperModeService().addLog('✅ [MusicService] TuneHub v3 获取成功');

          return SongDetail(
            id: songId,
            name: songName,
            pic: coverUrl,
            arName: artistName,
            alName: albumName,
            level: actualQuality,
            size: '0',
            url: audioUrl,
            lyric: lyricText,
            tlyric: tlyricText,
            yrc: yrcText,
            ytlrc: ytlrcText,
            qrc: qrcText,
            qrcTrans: qrcTransText,
            source: source,
          );
        } else {
          // 处理 TuneHub 音源错误码
          final errorMsg = data['message'] as String? ?? '未知错误 (code: $code)';
          StructuredLogService.log(
            '❌ [MusicService] TuneHub v3 音源错误: $errorMsg',
          );
          DeveloperModeService().addLog('❌ [MusicService] 错误: $errorMsg');
          throw Exception(errorMsg);
        }
      } else {
        StructuredLogService.log(
          '❌ [MusicService] TuneHub v3 音源请求失败: HTTP ${response.statusCode}',
        );
        DeveloperModeService().addLog(
          '❌ [Network] HTTP ${response.statusCode}',
        );
        return null;
      }
    } catch (e) {
      if (e is UnsupportedError) rethrow;
      StructuredLogService.log('❌ [MusicService] TuneHub v3 音源异常: $e');
      DeveloperModeService().addLog('❌ [MusicService] 异常: $e');
      return null;
    }
  }

  /// 🎵 Spotify 音源：获取歌曲详情 (通过流媒体服务)
  Future<SongDetail?> _fetchSongDetailFromSpotify({
    required dynamic songId,
    required AudioQuality quality,
  }) async {
    try {
      final result = await ApiClient().getJson(
        '/spotify/stream/$songId',
        timeout: const Duration(seconds: 30),
      );

      if (result.ok) {
        final data = result.data as Map<String, dynamic>;
        if (data['status'] == 200 && data['data'] != null) {
          final streamData = data['data'];
          final metadata = streamData['metadata'];

          return SongDetail(
            id: songId,
            name: metadata['name'] ?? '',
            pic: metadata['coverArt'] ?? '',
            arName: metadata['artists'] ?? '',
            alName: metadata['album'] ?? '',
            level: streamData['bitrate'] ?? 'High',
            size: '0',
            url: streamData['url'] ?? streamData['proxyUrl'] ?? '',
            lyric: streamData['lyric'] ?? '',
            tlyric: '', // Spotify 通常无翻译
            source: MusicSource.spotify,
          );
        }
      }
      return null;
    } catch (e) {
      StructuredLogService.log('❌ [MusicService] Spotify fetch failed: $e');
      return null;
    }
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
