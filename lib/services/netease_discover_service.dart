import 'package:flutter/foundation.dart';
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

  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;
  List<NeteasePlaylistSummary> get playlists => _playlists;
  List<NeteaseTag> get tags => _tags;
  String get currentCat => _currentCat;

  /// 获取"发现-推荐歌单"列表
  Future<void> fetchDiscoverPlaylists({String cat = '全部歌单'}) async {
    if (_isLoading) return;
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      _currentCat = cat;
      final result = await ApiClient().getJson(
        '/netease/top/playlist',
        queryParameters: {'cat': cat},
        timeout: const Duration(seconds: 15),
      );
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
      _errorMessage = '获取推荐歌单失败: $e';
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// 获取歌单详情（含曲目）
  Future<NeteasePlaylistDetail?> fetchPlaylistDetail(int id) async {
    try {
      final result = await ApiClient().getJson(
        '/playlist',
        queryParameters: {'id': id},
        timeout: const Duration(seconds: 15),
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
      _errorMessage = '获取歌单详情失败: $e';
      notifyListeners();
      return null;
    }
  }

  /// 获取可选标签
  Future<void> fetchTags() async {
    try {
      final result = await ApiClient().getJson(
        '/netease/playlist/highquality/tags',
        timeout: const Duration(seconds: 15),
      );
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
      _errorMessage = '获取分类失败: $e';
      notifyListeners();
    }
  }
}
