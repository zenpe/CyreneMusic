import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:dio/dio.dart';
import 'api/api_client.dart';
import 'search_request.dart';

class ArtistSearchException implements Exception {
  final String message;
  const ArtistSearchException(this.message);

  @override
  String toString() => message;
}

class NeteaseArtistBrief {
  final int id;
  final String name;
  final String picUrl;
  NeteaseArtistBrief({
    required this.id,
    required this.name,
    required this.picUrl,
  });
  factory NeteaseArtistBrief.fromJson(Map<String, dynamic> json) =>
      NeteaseArtistBrief(
        id: (json['id'] as num).toInt(),
        name: (json['name'] ?? '') as String,
        picUrl: (json['picUrl'] ?? '') as String,
      );
}

class NeteaseArtistDetailService extends ChangeNotifier {
  static final NeteaseArtistDetailService _instance =
      NeteaseArtistDetailService._internal();
  factory NeteaseArtistDetailService() => _instance;
  NeteaseArtistDetailService._internal();

  /// 搜索歌手列表
  Future<List<NeteaseArtistBrief>> searchArtists(
    String keywords, {
    int limit = 20,
    CancelToken? cancelToken,
  }) async {
    final keyword = keywords.trim();
    if (keyword.isEmpty) return [];
    final token = cancelToken ?? CancelToken();
    try {
      final result = await runSearchRequest(
        token,
        (child) => ApiClient().postJson(
          '/artist/search',
          data: {'keywords': keyword, 'limit': '$limit'},
          contentType: 'application/x-www-form-urlencoded',
          timeout: const Duration(seconds: 15),
          cancelToken: child,
        ),
      );
      if (token.isCancelled) throw token.cancelError!;
      if (!result.ok) {
        throw ArtistSearchException(
          result.statusCode == 504
              ? '搜索超时，请重试'
              : result.message ?? '歌手搜索失败，请稍后重试',
        );
      }
      final data = result.data;
      if (data is! Map || data['status'] != 200 || data['result'] is! List) {
        throw const ArtistSearchException('歌手搜索结果异常，请重试');
      }
      return (data['result'] as List).map((item) {
        if (item is! Map<String, dynamic> ||
            item['id'] is! int ||
            (item['id'] as int) <= 0 ||
            item['name'] is! String ||
            (item['name'] as String).trim().isEmpty) {
          throw const ArtistSearchException('歌手搜索结果异常，请重试');
        }
        return NeteaseArtistBrief.fromJson(item);
      }).toList();
    } on TimeoutException {
      throw const ArtistSearchException('搜索超时，请重试');
    } on ArtistSearchException {
      rethrow;
    } on DioException {
      rethrow;
    } catch (_) {
      throw const ArtistSearchException('歌手搜索结果异常，请重试');
    } finally {
      if (cancelToken == null) token.cancel('歌手搜索已结束');
    }
  }

  /// 通过歌手名查ID（优先精确匹配）
  Future<int?> resolveArtistIdByName(String name) async {
    try {
      final results = await searchArtists(name, limit: 5);
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
