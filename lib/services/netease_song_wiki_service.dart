import 'package:flutter/foundation.dart';
import 'api/api_client.dart';

/// 网易云歌曲百科及元数据服务
class NeteaseSongWikiService extends ChangeNotifier {
  static final NeteaseSongWikiService _instance = NeteaseSongWikiService._internal();
  factory NeteaseSongWikiService() => _instance;
  NeteaseSongWikiService._internal();

  /// 获取歌曲百科摘要 (Wiki Summary)
  /// 包含：曲风、语种、发行时间、简介等
  Future<Map<String, dynamic>?> fetchSongWiki(dynamic id) async {
    try {
      final result = await ApiClient().getJson(
        '/song/wiki/summary',
        queryParameters: {'id': id},
        timeout: const Duration(seconds: 15),
      );
      if (!result.ok) return null;
      final data = result.data as Map<String, dynamic>?;
      if (data == null || data['status'] != 200) return null;
      return data['data'] as Map<String, dynamic>;
    } catch (e) {
      debugPrint('[SongWikiService] fetchSongWiki failed: $e');
      return null;
    }
  }

  /// 获取歌曲音轨详细信息 (Music Detail)
  /// 包含：BPM、能量值、情感倾向等
  Future<Map<String, dynamic>?> fetchSongMusicDetail(dynamic id) async {
    try {
      final result = await ApiClient().getJson(
        '/song/music/detail/get',
        queryParameters: {'id': id},
        timeout: const Duration(seconds: 15),
      );
      if (!result.ok) return null;
      final data = result.data as Map<String, dynamic>?;
      if (data == null || data['status'] != 200) return null;
      return data['data'] as Map<String, dynamic>;
    } catch (e) {
      debugPrint('[SongWikiService] fetchSongMusicDetail failed: $e');
      return null;
    }
  }
}
