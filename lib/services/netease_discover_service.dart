import 'package:flutter/foundation.dart';
import 'package:dio/dio.dart';
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
  CancelToken? _playlistsCancelToken;
  CancelToken? _tagsCancelToken;
  int _playlistsRequestId = 0;
  int _tagsRequestId = 0;

  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;
  List<NeteasePlaylistSummary> get playlists => _playlists;
  List<NeteaseTag> get tags => _tags;
  String get currentCat => _currentCat;

  /// 获取"发现-推荐歌单"列表
  Future<void> fetchDiscoverPlaylists({String cat = '全部歌单'}) async {
    final requestId = ++_playlistsRequestId;
    _cancelPlaylistsRequest('新的发现歌单请求');
    final cancelToken = CancelToken();
    _playlistsCancelToken = cancelToken;

    _isLoading = true;
    _errorMessage = null;
    _currentCat = cat;
    notifyListeners();

    try {
      final result = await ApiClient().getJson(
        '/netease/top/playlist',
        queryParameters: {'cat': cat},
        timeout: const Duration(seconds: 15),
        cancelToken: cancelToken,
        cacheTtl: const Duration(seconds: 8),
      );
      if (!_isCurrentPlaylistsRequest(requestId, cancelToken)) {
        return;
      }
      if (!result.ok) {
        throw Exception('HTTP ${result.statusCode}');
      }

      final data = result.data as Map<String, dynamic>;
      if (data['status'] != 200) {
        throw Exception('status ${data['status']}');
      }

      final list = (data['playlists'] as List<dynamic>? ?? []);
      _playlists = list.map((e) => NeteasePlaylistSummary.fromJson(e as Map<String, dynamic>)).toList();
    } catch (e) {
      if (_isRequestCancelled(e, cancelToken) || !_isCurrentPlaylistsRequest(requestId, cancelToken)) {
        return;
      }
      _errorMessage = '获取推荐歌单失败: $e';
    } finally {
      if (_isCurrentPlaylistsRequest(requestId, cancelToken)) {
        _isLoading = false;
        _playlistsCancelToken = null;
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
      final result = await ApiClient().getJson(
        '/netease/playlist/highquality/tags',
        timeout: const Duration(seconds: 15),
        cancelToken: cancelToken,
        cacheTtl: const Duration(seconds: 30),
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
      final list = (data['tags'] as List<dynamic>? ?? []);
      _tags = list.map((e) => NeteaseTag.fromJson(e as Map<String, dynamic>)).toList();
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

  bool _isCurrentPlaylistsRequest(int requestId, CancelToken cancelToken) {
    return requestId == _playlistsRequestId && identical(_playlistsCancelToken, cancelToken);
  }

  bool _isCurrentTagsRequest(int requestId, CancelToken cancelToken) {
    return requestId == _tagsRequestId && identical(_tagsCancelToken, cancelToken);
  }

  void _cancelPlaylistsRequest(String reason) {
    final token = _playlistsCancelToken;
    if (token == null || token.isCancelled) {
      return;
    }
    token.cancel(reason);
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
    _cancelPlaylistsRequest('NeteaseDiscoverService disposed');
    _cancelTagsRequest('NeteaseDiscoverService disposed');
    _playlistsCancelToken = null;
    _tagsCancelToken = null;
    super.dispose();
  }
}
