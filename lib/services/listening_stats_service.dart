import 'structured_log_service.dart';
import 'dart:async';
import 'package:flutter/foundation.dart';
import '../models/track.dart';
import 'auth_service.dart';
import 'api/api_client.dart';

/// 听歌统计数据模型
class ListeningStatsData {
  final int totalListeningTime; // 总听歌时长（秒）
  final int totalPlayCount; // 总播放次数
  final List<PlayCountItem> playCounts; // 播放次数列表

  ListeningStatsData({
    required this.totalListeningTime,
    required this.totalPlayCount,
    required this.playCounts,
  });

  factory ListeningStatsData.fromJson(Map<String, dynamic> json) {
    return ListeningStatsData(
      totalListeningTime: json['totalListeningTime'] as int? ?? 0,
      totalPlayCount: json['totalPlayCount'] as int? ?? 0,
      playCounts: (json['playCounts'] as List<dynamic>?)
              ?.map((item) => PlayCountItem.fromJson(item as Map<String, dynamic>))
              .toList() ??
          [],
    );
  }
}

/// 播放次数数据项
class PlayCountItem {
  final String trackId;
  final String trackName;
  final String artists;
  final String album;
  final String picUrl;
  final String source;
  final int playCount;
  final DateTime lastPlayedAt;

  PlayCountItem({
    required this.trackId,
    required this.trackName,
    required this.artists,
    required this.album,
    required this.picUrl,
    required this.source,
    required this.playCount,
    required this.lastPlayedAt,
  });

  factory PlayCountItem.fromJson(Map<String, dynamic> json) {
    return PlayCountItem(
      trackId: json['track_id'] as String,
      trackName: json['track_name'] as String,
      artists: json['artists'] as String? ?? '',
      album: json['album'] as String? ?? '',
      picUrl: json['pic_url'] as String? ?? '',
      source: json['source'] as String,
      playCount: json['play_count'] as int,
      lastPlayedAt: DateTime.parse(json['last_played_at'] as String),
    );
  }

  /// 转换为 Track 对象
  Track toTrack() {
    return Track(
      id: trackId,
      name: trackName,
      artists: artists,
      album: album,
      picUrl: picUrl,
      source: _parseSource(source),
    );
  }

  /// 解析音乐来源
  MusicSource _parseSource(String source) {
    switch (source.toLowerCase()) {
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
        return MusicSource.netease;
    }
  }
}

/// 听歌统计服务
class ListeningStatsService extends ChangeNotifier {
  static final ListeningStatsService _instance = ListeningStatsService._internal();
  factory ListeningStatsService() => _instance;
  ListeningStatsService._internal();

  final ApiClient _api = ApiClient();

  Timer? _syncTimer;
  int _pendingSeconds = 0; // 待同步的秒数
  ListeningStatsData? _statsData;

  ListeningStatsData? get statsData => _statsData;

  /// 初始化服务
  void initialize() {
    // 每30秒同步一次听歌时长
    _syncTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      _syncListeningTime();
    });
    StructuredLogService.log('📊 [ListeningStatsService] 服务已初始化');
  }

  /// 累积听歌时长
  void accumulateListeningTime(int seconds) {
    _pendingSeconds += seconds;
  }

  /// 同步听歌时长到服务器
  Future<void> _syncListeningTime() async {
    if (_pendingSeconds <= 0) {
      StructuredLogService.log('📊 [ListeningStatsService] 无待同步数据（待同步: ${_pendingSeconds}秒）');
      return;
    }

    if (!AuthService().isLoggedIn) {
      StructuredLogService.log('⚠️ [ListeningStatsService] 用户未登录，无法同步');
      return;
    }

    final seconds = _pendingSeconds;
    _pendingSeconds = 0; // 重置待同步秒数

    StructuredLogService.log('📤 [ListeningStatsService] 准备同步听歌时长: ${seconds}秒');

    try {
      final result = await _api.postJson(
        '/stats/listening-time',
        data: {'seconds': seconds},
      );

      StructuredLogService.log('📥 [ListeningStatsService] 同步响应状态: ${result.statusCode}');

      if (result.ok) {
        final data = result.data as Map<String, dynamic>?;
        StructuredLogService.log('✅ [ListeningStatsService] 听歌时长已同步: +${seconds}秒, 总计: ${data?['data']?['totalListeningTime']}秒');
      } else {
        StructuredLogService.log('❌ [ListeningStatsService] 同步听歌时长失败: ${result.statusCode}');
        // 同步失败，将秒数加回待同步队列
        _pendingSeconds += seconds;
      }
    } catch (e) {
      StructuredLogService.log('❌ [ListeningStatsService] 同步听歌时长异常: $e');
      // 异常时将秒数加回待同步队列
      _pendingSeconds += seconds;
    }
  }

  /// 立即同步听歌时长（用于调试）
  Future<void> syncNow() async {
    StructuredLogService.log('🔄 [ListeningStatsService] 手动触发同步，待同步: ${_pendingSeconds}秒');
    await _syncListeningTime();
  }

  /// 记录播放次数
  Future<void> recordPlayCount(Track track) async {
    if (!AuthService().isLoggedIn) return;

    try {
      final result = await _api.postJson(
        '/stats/play-count',
        data: {
          'trackId': track.id.toString(),
          'trackName': track.name,
          'artists': track.artists,
          'album': track.album,
          'picUrl': track.picUrl,
          'source': track.source.name,
        },
      );

      if (result.ok) {
        StructuredLogService.log('✅ [ListeningStatsService] 播放次数已记录: ${track.name}');
      } else {
        StructuredLogService.log('❌ [ListeningStatsService] 记录播放次数失败: ${result.statusCode}');
      }
    } catch (e) {
      StructuredLogService.log('❌ [ListeningStatsService] 记录播放次数异常: $e');
    }
  }

  /// 获取统计数据
  Future<ListeningStatsData?> fetchStats() async {
    if (!AuthService().isLoggedIn) {
      StructuredLogService.log('⚠️ [ListeningStatsService] 用户未登录');
      return null;
    }

    try {
      final result = await _api.getJson('/stats');

      if (result.ok) {
        _statsData = ListeningStatsData.fromJson(result.bodyData as Map<String, dynamic>);
        notifyListeners();
        StructuredLogService.log('✅ [ListeningStatsService] 统计数据已获取');
        return _statsData;
      } else {
        StructuredLogService.log('❌ [ListeningStatsService] 获取统计数据失败: ${result.statusCode}');
        return null;
      }
    } catch (e) {
      StructuredLogService.log('❌ [ListeningStatsService] 获取统计数据异常: $e');
      return null;
    }
  }

  /// 格式化时长（秒转为时分秒）
  static String formatDuration(int seconds) {
    if (seconds < 60) {
      return '${seconds}秒';
    } else if (seconds < 3600) {
      final minutes = seconds ~/ 60;
      final secs = seconds % 60;
      return '${minutes}分${secs}秒';
    } else {
      final hours = seconds ~/ 3600;
      final minutes = (seconds % 3600) ~/ 60;
      return '${hours}小时${minutes}分';
    }
  }

  /// 在退出前同步数据
  Future<void> syncBeforeExit() async {
    StructuredLogService.log('🔄 [ListeningStatsService] 退出前同步数据...');
    _syncTimer?.cancel();
    await _syncListeningTime();
    StructuredLogService.log('✅ [ListeningStatsService] 退出前同步完成');
  }

  /// 清理资源
  @override
  void dispose() {
    _syncTimer?.cancel();
    StructuredLogService.log('🗑️ [ListeningStatsService] 服务已释放');
    super.dispose();
  }
}
