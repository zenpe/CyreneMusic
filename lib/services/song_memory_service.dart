import 'package:flutter/foundation.dart';
import 'api/api_client.dart';

/// 用户歌曲回忆坐标服务
/// 获取用户对特定歌曲的首次播放时间和累计播放次数
class SongMemoryService extends ChangeNotifier {
  static final SongMemoryService _instance = SongMemoryService._internal();
  factory SongMemoryService() => _instance;
  SongMemoryService._internal();

  /// 获取用户对特定歌曲的回忆坐标
  /// 返回 { firstPlayedAt, playCount, lastPlayedAt }
  Future<Map<String, dynamic>?> fetchSongMemory(dynamic trackId, String source) async {
    try {
      final result = await ApiClient().getJson(
        '/stats/song-memory',
        queryParameters: {'trackId': trackId.toString(), 'source': source},
      );

      if (!result.ok) return null;
      final data = result.data as Map<String, dynamic>?;
      if (data == null || data['code'] != 200) return null;
      return data['data'] as Map<String, dynamic>?;
    } catch (e) {
      debugPrint('[SongMemoryService] fetchSongMemory failed: $e');
      return null;
    }
  }
}
