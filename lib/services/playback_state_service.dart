import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import '../models/track.dart';
import 'auth_service.dart';
import 'url_service.dart';

/// 播放状态持久化服务
/// 用于记录用户上次播放的歌曲信息，以便下次启动时恢复
/// 完全基于云端同步，需要登录后使用
class PlaybackStateService {
  static final PlaybackStateService _instance = PlaybackStateService._internal();
  factory PlaybackStateService() => _instance;
  PlaybackStateService._internal();

  /// 获取当前平台名称
  String _getCurrentPlatform() {
    if (Platform.isAndroid) return 'Android';
    if (Platform.isWindows) return 'Windows';
    if (Platform.isIOS) return 'iOS';
    if (Platform.isMacOS) return 'macOS';
    if (Platform.isLinux) return 'Linux';
    return 'Unknown';
  }

  /// 保存当前播放状态（仅保存到云端，登录后才生效）
  Future<void> savePlaybackState({
    required Track track,
    required Duration position,
    bool isFromPlaylist = false,
  }) async {
    try {
      final currentPlatform = _getCurrentPlatform();
      
      // 直接保存到云端（如果已登录）
      await _saveToCloud(track, position, isFromPlaylist, currentPlatform);
      
      print('💾 [PlaybackStateService] 播放状态已保存: ${track.name}, 位置: ${position.inSeconds}秒, 平台: $currentPlatform');
    } catch (e) {
      print('❌ [PlaybackStateService] 保存播放状态失败: $e');
    }
  }

  /// 保存到云端
  Future<void> _saveToCloud(Track track, Duration position, bool isFromPlaylist, String platform) async {
    try {
      // 检查是否已登录
      if (!AuthService().isLoggedIn) {
        print('⚠️ [PlaybackStateService] 未登录，无法保存到云端');
        return;
      }

      final token = AuthService().token;
      final baseUrl = UrlService().baseUrl;
      
      final response = await http.post(
        Uri.parse('$baseUrl/playback/save'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: json.encode({
          'trackId': track.id.toString(),
          'trackName': track.name,
          'artists': track.artists,
          'album': track.album,
          'picUrl': track.picUrl,
          'source': track.source.toString().split('.').last,
          'position': position.inSeconds,
          'isFromPlaylist': isFromPlaylist,
          'platform': platform,
        }),
      ).timeout(const Duration(seconds: 5));

      if (response.statusCode == 200) {
        print('☁️ [PlaybackStateService] 播放状态已保存到云端');
      } else {
        print('⚠️ [PlaybackStateService] 云端保存失败: ${response.statusCode}');
      }
    } catch (e) {
      print('❌ [PlaybackStateService] 云端保存失败: $e');
    }
  }

  /// 获取上次播放状态（仅从云端获取）
  Future<PlaybackState?> getLastPlaybackState() async {
    print('🔍 [PlaybackStateService] 开始读取播放状态...');
    
    // 检查是否已登录
    if (!AuthService().isLoggedIn) {
      print('ℹ️ [PlaybackStateService] 未登录，无法获取播放状态');
      return null;
    }
    
    // 从云端获取
    print('☁️ [PlaybackStateService] 从云端获取播放状态...');
    return await _getFromCloud();
  }

  /// 从云端获取
  Future<PlaybackState?> _getFromCloud() async {
    try {
      final token = AuthService().token;
      final baseUrl = UrlService().baseUrl;
      
      final response = await http.get(
        Uri.parse('$baseUrl/playback/last'),
        headers: {
          'Authorization': 'Bearer $token',
        },
      ).timeout(const Duration(seconds: 5));

      if (response.statusCode == 200) {
        final data = json.decode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
        
        if (data['status'] == 200 && data['data'] != null) {
          final playbackData = data['data'] as Map<String, dynamic>;
          
          // 检查是否过期（24小时）
          final timestamp = playbackData['updatedAt'] as int;
          final lastPlayTime = DateTime.fromMillisecondsSinceEpoch(timestamp);
          final timeDiff = DateTime.now().difference(lastPlayTime);
          
          if (timeDiff.inHours > 24) {
            print('⏰ [PlaybackStateService] 云端播放记录已过期（${timeDiff.inHours}小时前）');
            return null;
          }
          
          // 解析数据
          final track = Track(
            id: _parseTrackId(playbackData['trackId']),
            name: playbackData['trackName'] as String,
            artists: playbackData['artists'] as String,
            album: playbackData['album'] as String,
            picUrl: playbackData['picUrl'] as String,
            source: _parseSource(playbackData['source'] as String),
          );
          
          return PlaybackState(
            track: track,
            position: Duration(seconds: playbackData['position'] as int),
            lastPlayTime: lastPlayTime,
            isFromPlaylist: playbackData['isFromPlaylist'] as bool,
            lastPlatform: playbackData['platform'] as String? ?? 'Unknown',
            currentPlatform: _getCurrentPlatform(),
          );
        }
      }
      
      return null;
    } catch (e) {
      print('⚠️ [PlaybackStateService] 云端获取失败: $e');
      return null;
    }
  }

  /// 解析 Track ID（可能是字符串或数字）
  dynamic _parseTrackId(dynamic id) {
    if (id is String) {
      // 尝试转换为数字
      final intId = int.tryParse(id);
      return intId ?? id;
    }
    return id;
  }

  /// 清除播放状态（从云端清除）
  Future<void> clearPlaybackState() async {
    try {
      if (!AuthService().isLoggedIn) {
        print('ℹ️ [PlaybackStateService] 未登录，无需清除');
        return;
      }

      final token = AuthService().token;
      final baseUrl = UrlService().baseUrl;

      final response = await http.delete(
        Uri.parse('$baseUrl/playback/clear'),
        headers: {
          'Authorization': 'Bearer $token',
        },
      ).timeout(const Duration(seconds: 5));

      if (response.statusCode == 200) {
        print('🗑️ [PlaybackStateService] 云端播放状态已清除');
      }
    } catch (e) {
      print('❌ [PlaybackStateService] 清除播放状态失败: $e');
    }
  }

  /// 解析音乐源
  /// 支持两种格式：
  /// - 简短格式: "netease", "qq", "kugou", "kuwo", "local"
  /// - 完整格式: "MusicSource.netease", "MusicSource.qq" 等
  MusicSource _parseSource(String source) {
    // 统一处理：移除可能的前缀
    final normalizedSource = source.replaceFirst('MusicSource.', '').toLowerCase();
    
    switch (normalizedSource) {
      case 'netease':
        return MusicSource.netease;
      case 'apple':
        return MusicSource.apple;
      case 'qq':
        return MusicSource.qq;
      case 'kugou':
        return MusicSource.kugou;
      case 'kuwo':
        return MusicSource.kuwo;
      case 'navidrome':
        return MusicSource.navidrome;
      case 'local':
        return MusicSource.local;
      default:
        print('⚠️ [PlaybackStateService] 未知音乐源: $source, 默认使用网易云');
        return MusicSource.netease;
    }
  }
}

/// 播放状态数据类
class PlaybackState {
  final Track track;
  final Duration position;
  final DateTime lastPlayTime;
  final bool isFromPlaylist;
  final String lastPlatform;      // 上次播放的平台
  final String currentPlatform;   // 当前运行的平台

  PlaybackState({
    required this.track,
    required this.position,
    required this.lastPlayTime,
    required this.isFromPlaylist,
    required this.lastPlatform,
    required this.currentPlatform,
  });
  
  /// 获取封面URL
  String get coverUrl => track.picUrl;
  
  /// 是否是跨平台播放（不同设备）
  bool get isCrossPlatform => lastPlatform != currentPlatform;
  
  /// 获取平台显示文本
  String get platformDisplayText {
    if (!isCrossPlatform) return '';
    return '来自你的 $lastPlatform';
  }
}
