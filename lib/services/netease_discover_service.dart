import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:dio/dio.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/netease_discover.dart';
import 'api/api_client.dart';

/// 发现页 - 网易云歌单服务
class NeteaseDiscoverService extends ChangeNotifier {
  static final NeteaseDiscoverService _instance = NeteaseDiscoverService._internal();
  factory NeteaseDiscoverService() => _instance;
  NeteaseDiscoverService._internal();

  bool _isLoading = false;
  String? _errorMessage;
  List<NeteasePlaylistSummary> _playlists = [];
  List<NeteaseTag> _tags = [];
  String _currentCat = '全部歌单';
  CancelToken? _tagsCancelToken;
  int _playlistsRequestId = 0;
  int _tagsRequestId = 0;

  static const _playlistCachePrefix = 'content.discover.playlists.v2.';
  static const _tagsCacheKey = 'content.discover.tags.v2';
  static const _cacheFreshness = Duration(minutes: 10);

  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;
  List<NeteasePlaylistSummary> get playlists => _playlists;
  List<NeteaseTag> get tags => _tags;
  String get currentCat => _currentCat;

  /// 获取"发现-推荐歌单"列表
  Future<void> fetchDiscoverPlaylists({
    String cat = '全部歌单',
    bool forceRefresh = false,
  }) async {
    final requestId = ++_playlistsRequestId;
    final previousCat = _currentCat;
    _isLoading = _playlists.isEmpty;
    _errorMessage = null;
    _currentCat = cat;
    if (previousCat != cat) {
      _playlists = [];
    }
    notifyListeners();

    try {
      final cached = await _readPlaylistCache(cat);
      if (requestId != _playlistsRequestId) return;
      if (cached != null) {
        _playlists = cached.items;
        _isLoading = false;
        notifyListeners();
        if (!forceRefresh && DateTime.now().difference(cached.savedAt) < _cacheFreshness) {
          return;
        }
      }

      final result = await ApiClient().getJson(
        '/v1/discover/playlists',
        queryParameters: {
          'category': cat,
        },
        timeout: const Duration(seconds: 15),
      );
      if (requestId != _playlistsRequestId) {
        return;
      }
      if (!result.ok) {
        throw Exception('HTTP ${result.statusCode}');
      }

      final data = result.data as Map<String, dynamic>;
      if (data['status'] != 200) {
        throw Exception(data['message'] ?? 'status ${data['status']}');
      }

      final list = (data['items'] as List<dynamic>? ?? []);
      _playlists = list.map((e) => NeteasePlaylistSummary.fromJson(e as Map<String, dynamic>)).toList();
      await _writePlaylistCache(cat, _playlists);
    } catch (e) {
      if (requestId != _playlistsRequestId) {
        return;
      }
      _errorMessage = '获取推荐歌单失败: $e';
    } finally {
      if (requestId == _playlistsRequestId) {
        _isLoading = false;
        notifyListeners();
      }
    }
  }

  /// 获取歌单详情（含曲目）
  Future<NeteasePlaylistDetail?> fetchPlaylistDetail(int id, {CancelToken? cancelToken}) async {
    try {
      final result = await ApiClient().getJson(
        '/playlist',
        queryParameters: {'id': id},
        timeout: const Duration(seconds: 15),
        cancelToken: cancelToken,
        cacheTtl: const Duration(seconds: 10),
      );
      if (!result.ok) {
        throw Exception('HTTP ${result.statusCode}');
      }
      final data = result.data as Map<String, dynamic>;
      if (data['status'] != 200) {
        throw Exception('status ${data['status']}');
      }
      return NeteasePlaylistDetail.fromJson(data['data'] as Map<String, dynamic>);
    } catch (e) {
      if (_isRequestCancelled(e, cancelToken)) {
        return null;
      }
      _errorMessage = '获取歌单详情失败: $e';
      notifyListeners();
      return null;
    }
  }

  /// 获取可选标签
  Future<void> fetchTags() async {
    final requestId = ++_tagsRequestId;
    _cancelTagsRequest('新的发现分类请求');
    final cancelToken = CancelToken();
    _tagsCancelToken = cancelToken;

    try {
      final cached = await _readTagsCache();
      if (_isCurrentTagsRequest(requestId, cancelToken) && cached != null) {
        _tags = cached.items;
        notifyListeners();
        if (DateTime.now().difference(cached.savedAt) < _cacheFreshness) {
          _tagsCancelToken = null;
          return;
        }
      }

      final result = await ApiClient().getJson(
        '/v1/discover/tags',
        timeout: const Duration(seconds: 15),
        cancelToken: cancelToken,
      );
      if (!_isCurrentTagsRequest(requestId, cancelToken)) {
        return;
      }
      if (!result.ok) {
        throw Exception('HTTP ${result.statusCode}');
      }
      final data = result.data as Map<String, dynamic>;
      if (data['status'] != 200) {
        throw Exception('status ${data['status']}');
      }
      final list = (data['items'] as List<dynamic>? ?? []);
      _tags = list.map((e) => NeteaseTag.fromJson(e as Map<String, dynamic>)).toList();
      await _writeTagsCache(_tags);
      notifyListeners();
    } catch (e) {
      if (_isRequestCancelled(e, cancelToken) || !_isCurrentTagsRequest(requestId, cancelToken)) {
        return;
      }
      _errorMessage = '获取分类失败: $e';
      notifyListeners();
    } finally {
      if (_isCurrentTagsRequest(requestId, cancelToken)) {
        _tagsCancelToken = null;
      }
    }
  }

  bool _isCurrentTagsRequest(int requestId, CancelToken cancelToken) {
    return requestId == _tagsRequestId && identical(_tagsCancelToken, cancelToken);
  }

  void _cancelTagsRequest(String reason) {
    final token = _tagsCancelToken;
    if (token == null || token.isCancelled) {
      return;
    }
    token.cancel(reason);
  }

  bool _isRequestCancelled(Object error, CancelToken? cancelToken) {
    if (cancelToken != null && cancelToken.isCancelled) {
      return true;
    }
    if (error is DioException && CancelToken.isCancel(error)) {
      return true;
    }
    return error is DioException && error.type == DioExceptionType.cancel;
  }

  @override
  void dispose() {
    _cancelTagsRequest('NeteaseDiscoverService disposed');
    _tagsCancelToken = null;
    super.dispose();
  }

  String _playlistCacheKey(String cat) {
    return '$_playlistCachePrefix${Uri.encodeComponent(cat)}';
  }

  Future<_CachedPlaylistList?> _readPlaylistCache(String cat) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_playlistCacheKey(cat));
      if (raw == null) return null;
      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      final items = (decoded['items'] as List<dynamic>? ?? [])
          .map((item) => NeteasePlaylistSummary.fromJson(item as Map<String, dynamic>))
          .toList();
      final savedAt = DateTime.fromMillisecondsSinceEpoch((decoded['savedAt'] as num).toInt());
      return _CachedPlaylistList(items: items, savedAt: savedAt);
    } catch (_) {
      return null;
    }
  }

  Future<void> _writePlaylistCache(String cat, List<NeteasePlaylistSummary> items) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        _playlistCacheKey(cat),
        jsonEncode({
          'savedAt': DateTime.now().millisecondsSinceEpoch,
          'items': items
              .map((item) => {
                    'id': item.id,
                    'name': item.name,
                    'coverImgUrl': item.coverImgUrl,
                    'creator': {'nickname': item.creatorNickname},
                    'trackCount': item.trackCount,
                    'playCount': item.playCount,
                  })
              .toList(),
        }),
      );
    } catch (_) {}
  }

  Future<_CachedTagList?> _readTagsCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_tagsCacheKey);
      if (raw == null) return null;
      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      final items = (decoded['items'] as List<dynamic>? ?? [])
          .map((item) => NeteaseTag.fromJson(item as Map<String, dynamic>))
          .toList();
      return _CachedTagList(
        items: items,
        savedAt: DateTime.fromMillisecondsSinceEpoch((decoded['savedAt'] as num).toInt()),
      );
    } catch (_) {
      return null;
    }
  }

  Future<void> _writeTagsCache(List<NeteaseTag> items) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        _tagsCacheKey,
        jsonEncode({
          'savedAt': DateTime.now().millisecondsSinceEpoch,
          'items': items
              .map((item) => {
                    'id': item.id,
                    'name': item.name,
                    'type': item.type,
                    'category': item.category,
                    'hot': item.hot,
                  })
              .toList(),
        }),
      );
    } catch (_) {}
  }
}

class _CachedPlaylistList {
  final List<NeteasePlaylistSummary> items;
  final DateTime savedAt;

  const _CachedPlaylistList({required this.items, required this.savedAt});
}

class _CachedTagList {
  final List<NeteaseTag> items;
  final DateTime savedAt;

  const _CachedTagList({required this.items, required this.savedAt});
}
