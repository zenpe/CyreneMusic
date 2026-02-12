import 'package:flutter/foundation.dart';
import 'api/api_client.dart';

class NeteaseArtistBrief {
  final int id;
  final String name;
  final String picUrl;
  NeteaseArtistBrief({required this.id, required this.name, required this.picUrl});
  factory NeteaseArtistBrief.fromJson(Map<String, dynamic> json) => NeteaseArtistBrief(
        id: (json['id'] as num).toInt(),
        name: (json['name'] ?? '') as String,
        picUrl: (json['picUrl'] ?? '') as String,
      );
}

class NeteaseArtistDetailService extends ChangeNotifier {
  static final NeteaseArtistDetailService _instance = NeteaseArtistDetailService._internal();
  factory NeteaseArtistDetailService() => _instance;
  NeteaseArtistDetailService._internal();

  /// 搜索歌手列表
  Future<List<NeteaseArtistBrief>> searchArtists(String keywords, {int limit = 20}) async {
    try {
      if (keywords.trim().isEmpty) return [];
      final result = await ApiClient().postJson(
        '/artist/search',
        data: {'keywords': keywords, 'limit': '$limit'},
        contentType: 'application/x-www-form-urlencoded',
        timeout: const Duration(seconds: 12),
      );
      if (!result.ok) return [];
      final data = result.data as Map<String, dynamic>?;
      if (data == null || data['status'] != 200) return [];
      final resultList = (data['result'] as List<dynamic>? ?? [])
          .map((e) => NeteaseArtistBrief.fromJson(e as Map<String, dynamic>))
          .toList();
      return resultList;
    } catch (_) {
      return [];
    }
  }

  /// 通过歌手名查ID（优先精确匹配）
  Future<int?> resolveArtistIdByName(String name) async {
    try {
      final result = await ApiClient().postJson(
        '/artist/search',
        data: {'keywords': name, 'limit': '5'},
        contentType: 'application/x-www-form-urlencoded',
        timeout: const Duration(seconds: 12),
      );
      if (!result.ok) return null;
      final data = result.data as Map<String, dynamic>?;
      if (data == null || data['status'] != 200) return null;
      final results = (data['result'] as List<dynamic>? ?? [])
          .map((e) => NeteaseArtistBrief.fromJson(e as Map<String, dynamic>))
          .toList();
      if (results.isEmpty) return null;
      // 精确匹配优先
      final exact = results.firstWhere(
        (a) => a.name.toLowerCase() == name.toLowerCase(),
        orElse: () => results.first,
      );
      return exact.id;
    } catch (_) {
      return null;
    }
  }

  /// 获取歌手详情
  Future<Map<String, dynamic>?> fetchArtistDetail(int id) async {
    try {
      final result = await ApiClient().getJson(
        '/artist/detail',
        queryParameters: {'id': id},
        timeout: const Duration(seconds: 15),
      );
      if (!result.ok) return null;
      final data = result.data as Map<String, dynamic>?;
      if (data == null || data['status'] != 200) return null;
      return data['data'] as Map<String, dynamic>;
    } catch (_) {
      return null;
    }
  }

  /// 获取歌手描述
  Future<Map<String, dynamic>?> fetchArtistDesc(int id) async {
    try {
      final result = await ApiClient().getJson(
        '/artist/desc',
        queryParameters: {'id': id},
        timeout: const Duration(seconds: 15),
      );
      if (!result.ok) return null;
      final data = result.data as Map<String, dynamic>?;
      if (data == null || data['status'] != 200) return null;
      return data;
    } catch (_) {
      return null;
    }
  }
}
