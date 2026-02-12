import 'package:flutter/foundation.dart';
import '../models/track.dart';
import 'auth_service.dart';
import 'api/api_client.dart';

/// 收藏歌曲模型
class FavoriteTrack {
  final String id;
  final String name;
  final String artists;
  final String album;
  final String picUrl;
  final MusicSource source;
  final DateTime addedAt;

  FavoriteTrack({
    required this.id,
    required this.name,
    required this.artists,
    required this.album,
    required this.picUrl,
    required this.source,
    required this.addedAt,
  });

  /// 从 Track 创建
  factory FavoriteTrack.fromTrack(Track track) {
    return FavoriteTrack(
      id: track.id.toString(),
      name: track.name,
      artists: track.artists,
      album: track.album,
      picUrl: track.picUrl,
      source: track.source,
      addedAt: DateTime.now(),
    );
  }

  /// 从 JSON 创建
  factory FavoriteTrack.fromJson(Map<String, dynamic> json) {
    return FavoriteTrack(
      id: json['trackId'] as String,
      name: json['name'] as String,
      artists: json['artists'] as String,
      album: json['album'] as String,
      picUrl: json['picUrl'] as String,
      source: MusicSource.values.firstWhere(
        (e) => e.toString().split('.').last == json['source'],
        orElse: () => MusicSource.netease,
      ),
      addedAt: DateTime.parse(json['addedAt'] as String),
    );
  }

  /// 转换为 Track
  Track toTrack() {
    return Track(
      id: id,
      name: name,
      artists: artists,
      album: album,
      picUrl: picUrl,
      source: source,
    );
  }

  /// 转换为 JSON（用于发送到后端）
  Map<String, dynamic> toJson() {
    return {
      'trackId': id,
      'name': name,
      'artists': artists,
      'album': album,
      'picUrl': picUrl,
      'source': source.toString().split('.').last,
    };
  }
}

/// 收藏服务
class FavoriteService extends ChangeNotifier {
  static final FavoriteService _instance = FavoriteService._internal();
  factory FavoriteService() => _instance;
  FavoriteService._internal() {
    // 监听登录状态变化
    AuthService().addListener(_onAuthChanged);
  }

  List<FavoriteTrack> _favorites = [];
  List<FavoriteTrack> get favorites => _favorites;

  bool _isLoading = false;
  bool get isLoading => _isLoading;

  Set<String> _favoriteIds = {}; // 用于快速查找

  /// 监听认证状态变化
  void _onAuthChanged() {
    if (!AuthService().isLoggedIn) {
      // 用户登出时清空收藏列表
      clear();
    }
  }

  /// 检查歌曲是否已收藏
  bool isFavorite(Track track) {
    final key = '${track.source}_${track.id}';
    return _favoriteIds.contains(key);
  }

  /// 加载收藏列表
  Future<void> loadFavorites() async {
    if (!AuthService().isLoggedIn) {
      print('[FavoriteService] not logged in');
      return;
    }

    try {
      _isLoading = true;
      notifyListeners();

      final result = await ApiClient().getJson('/favorites');

      if (result.ok) {
        final data = result.data as Map<String, dynamic>?;

        if (data != null && data['status'] == 200) {
          final List<dynamic> favoritesJson = data['favorites'] ?? [];
          _favorites = favoritesJson
              .map((item) => FavoriteTrack.fromJson(item as Map<String, dynamic>))
              .toList();

          // 更新快速查找集合
          _favoriteIds = _favorites
              .map((f) => '${f.source}_${f.id}')
              .toSet();

          print('[FavoriteService] loaded ${_favorites.length} favorites');
        } else {
          throw Exception(data?['message'] ?? '加载失败');
        }
      } else {
        throw Exception('HTTP ${result.statusCode}');
      }
    } catch (e) {
      print('[FavoriteService] loadFavorites failed: $e');
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// 添加收藏
  Future<bool> addFavorite(Track track) async {
    if (!AuthService().isLoggedIn) {
      print('[FavoriteService] not logged in');
      return false;
    }

    try {
      final favoriteTrack = FavoriteTrack.fromTrack(track);

      final result = await ApiClient().postJson(
        '/favorites',
        data: favoriteTrack.toJson(),
      );

      if (result.ok) {
        final data = result.data as Map<String, dynamic>?;

        if (data != null && data['status'] == 200) {
          // 添加到本地列表
          _favorites.insert(0, favoriteTrack);
          _favoriteIds.add('${track.source}_${track.id}');

          print('[FavoriteService] added: ${track.name}');
          notifyListeners();
          return true;
        } else {
          throw Exception(data?['message'] ?? '添加失败');
        }
      } else {
        throw Exception('HTTP ${result.statusCode}');
      }
    } catch (e) {
      print('[FavoriteService] addFavorite failed: $e');
      return false;
    }
  }

  /// 删除收藏
  Future<bool> removeFavorite(Track track) async {
    if (!AuthService().isLoggedIn) {
      print('[FavoriteService] not logged in');
      return false;
    }

    try {
      final trackId = track.id.toString();
      final source = track.source.toString().split('.').last;

      final result = await ApiClient().deleteJson('/favorites/$trackId/$source');

      if (result.ok) {
        final data = result.data as Map<String, dynamic>?;

        if (data != null && data['status'] == 200) {
          // 从本地列表删除
          _favorites.removeWhere((f) => f.id == trackId && f.source == track.source);
          _favoriteIds.remove('${track.source}_${track.id}');

          print('[FavoriteService] removed: ${track.name}');
          notifyListeners();
          return true;
        } else {
          throw Exception(data?['message'] ?? '删除失败');
        }
      } else {
        throw Exception('HTTP ${result.statusCode}');
      }
    } catch (e) {
      print('[FavoriteService] removeFavorite failed: $e');
      return false;
    }
  }

  /// 切换收藏状态
  Future<bool> toggleFavorite(Track track) async {
    if (isFavorite(track)) {
      return await removeFavorite(track);
    } else {
      return await addFavorite(track);
    }
  }

  /// 清空收藏列表（登出时调用）
  void clear() {
    _favorites.clear();
    _favoriteIds.clear();
    notifyListeners();
  }
}
