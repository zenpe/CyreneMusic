import 'structured_log_service.dart';
import 'package:flutter/foundation.dart';
import 'package:dio/dio.dart';
import '../models/track.dart';
import 'auth_service.dart';
import 'api/api_client.dart';
import 'url_service.dart';

/// 收藏歌曲模型
class FavoriteTrack {
  final String id;
  final String name;
  final String artists;
  final String album;
  final String picUrl;
  final MusicSource source;
  final TrackSourceIds sourceIds;
  final DateTime addedAt;

  FavoriteTrack({
    required this.id,
    required this.name,
    required this.artists,
    required this.album,
    required this.picUrl,
    required this.source,
    this.sourceIds = const TrackSourceIds(),
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
      sourceIds: track.sourceIds,
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
      sourceIds: TrackSourceIds.fromJson(json['sourceIds']),
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
      sourceIds: sourceIds,
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
      if (!sourceIds.isEmpty) 'sourceIds': sourceIds.toJson(),
    };
  }
}

/// 收藏服务
class FavoriteService extends ChangeNotifier {
  static final FavoriteService _instance = FavoriteService._internal();
  factory FavoriteService() => _instance;
  FavoriteService._internal() {
    _observedSession = AuthService().sessionIdentity;
    _observedBackendRevision = UrlService().backendRevision;
    // 监听登录状态变化
    AuthService().addListener(_onAuthChanged);
    UrlService().addListener(_onAuthChanged);
  }

  List<FavoriteTrack> _favorites = [];
  List<FavoriteTrack> get favorites => _favorites;

  bool _isLoading = false;
  String? _observedSession;
  int _observedBackendRevision = 0;
  int _loadGeneration = 0;
  Future<void>? _loadInFlight;
  CancelToken? _loadRequest;
  // Only successful mutations overlapping the current read need to be retained.
  final Map<String, FavoriteTrack?> _changesDuringLoad = {};
  bool get isLoading => _isLoading;

  Set<String> _favoriteIds = {}; // 用于快速查找

  /// 监听认证状态变化
  void _onAuthChanged() {
    final session = AuthService().sessionIdentity;
    final backendRevision = UrlService().backendRevision;
    if (_observedSession != session ||
        _observedBackendRevision != backendRevision) {
      _observedSession = session;
      _observedBackendRevision = backendRevision;
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
    _onAuthChanged();
    final session = AuthService().sessionIdentity;
    if (session == null) {
      StructuredLogService.log('[FavoriteService] not logged in');
      return;
    }

    final pending = _loadInFlight;
    if (pending != null) return pending;
    final generation = ++_loadGeneration;
    final request = _loadFavorites(session, generation);
    _loadInFlight = request;
    try {
      await request;
    } finally {
      if (identical(_loadInFlight, request)) _loadInFlight = null;
    }
  }

  Future<void> _loadFavorites(String session, int generation) async {
    final backendRevision = UrlService().backendRevision;
    final token = CancelToken();
    _loadRequest = token;
    _changesDuringLoad.clear();
    try {
      _isLoading = true;
      notifyListeners();

      final result = await ApiClient().getJson(
        '/favorites',
        cancelToken: token,
      );
      if (session != AuthService().sessionIdentity ||
          backendRevision != UrlService().backendRevision ||
          generation != _loadGeneration) {
        return;
      }

      if (result.ok) {
        final data = result.data as Map<String, dynamic>?;

        if (data != null && data['status'] == 200) {
          final List<dynamic> favoritesJson = data['favorites'] ?? [];
          final loaded = favoritesJson
              .map(
                (item) => FavoriteTrack.fromJson(item as Map<String, dynamic>),
              )
              .toList();
          for (final change in _changesDuringLoad.entries) {
            loaded.removeWhere((f) => '${f.source}_${f.id}' == change.key);
            if (change.value != null) loaded.insert(0, change.value!);
          }
          _favorites = loaded;

          // 更新快速查找集合
          _favoriteIds = _favorites.map((f) => '${f.source}_${f.id}').toSet();

          StructuredLogService.log(
            '[FavoriteService] loaded ${_favorites.length} favorites',
          );
        } else {
          throw Exception(data?['message'] ?? '加载失败');
        }
      } else {
        throw Exception('HTTP ${result.statusCode}');
      }
    } catch (e) {
      StructuredLogService.log('[FavoriteService] loadFavorites failed: $e');
    } finally {
      if (session == AuthService().sessionIdentity &&
          backendRevision == UrlService().backendRevision &&
          generation == _loadGeneration) {
        _changesDuringLoad.clear();
        _loadRequest = null;
        _isLoading = false;
        notifyListeners();
      }
    }
  }

  /// 添加收藏
  Future<bool> addFavorite(Track track) async {
    _onAuthChanged();
    final session = AuthService().sessionIdentity;
    final backendRevision = UrlService().backendRevision;
    if (session == null) {
      StructuredLogService.log('[FavoriteService] not logged in');
      return false;
    }

    try {
      final favoriteTrack = FavoriteTrack.fromTrack(track);

      final result = await ApiClient().postJson(
        '/favorites',
        data: favoriteTrack.toJson(),
      );
      if (session != AuthService().sessionIdentity ||
          backendRevision != UrlService().backendRevision) {
        return false;
      }

      if (result.ok) {
        final data = result.data as Map<String, dynamic>?;

        if (data != null && data['status'] == 200) {
          // 添加到本地列表
          final key = '${track.source}_${track.id}';
          _favorites.removeWhere((f) => '${f.source}_${f.id}' == key);
          _favorites.insert(0, favoriteTrack);
          _favoriteIds.add(key);
          if (_isLoading) _changesDuringLoad[key] = favoriteTrack;

          StructuredLogService.log('[FavoriteService] added: ${track.name}');
          notifyListeners();
          return true;
        } else {
          throw Exception(data?['message'] ?? '添加失败');
        }
      } else {
        throw Exception('HTTP ${result.statusCode}');
      }
    } catch (e) {
      StructuredLogService.log('[FavoriteService] addFavorite failed: $e');
      return false;
    }
  }

  /// 删除收藏
  Future<bool> removeFavorite(Track track) async {
    _onAuthChanged();
    final session = AuthService().sessionIdentity;
    final backendRevision = UrlService().backendRevision;
    if (session == null) {
      StructuredLogService.log('[FavoriteService] not logged in');
      return false;
    }

    try {
      final trackId = track.id.toString();
      final source = track.source.toString().split('.').last;

      final result = await ApiClient().deleteJson(
        '/favorites/$trackId/$source',
      );
      if (session != AuthService().sessionIdentity ||
          backendRevision != UrlService().backendRevision) {
        return false;
      }

      if (result.ok) {
        final data = result.data as Map<String, dynamic>?;

        if (data != null && data['status'] == 200) {
          // 从本地列表删除
          _favorites.removeWhere(
            (f) => f.id == trackId && f.source == track.source,
          );
          _favoriteIds.remove('${track.source}_${track.id}');
          if (_isLoading) {
            _changesDuringLoad['${track.source}_${track.id}'] = null;
          }

          StructuredLogService.log('[FavoriteService] removed: ${track.name}');
          notifyListeners();
          return true;
        } else {
          throw Exception(data?['message'] ?? '删除失败');
        }
      } else {
        throw Exception('HTTP ${result.statusCode}');
      }
    } catch (e) {
      StructuredLogService.log('[FavoriteService] removeFavorite failed: $e');
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
    _loadGeneration++;
    _loadRequest?.cancel('收藏列表上下文已失效');
    _loadRequest = null;
    _loadInFlight = null;
    _changesDuringLoad.clear();
    _isLoading = false;
    _favorites.clear();
    _favoriteIds.clear();
    notifyListeners();
  }

  @override
  void dispose() {
    AuthService().removeListener(_onAuthChanged);
    UrlService().removeListener(_onAuthChanged);
    _loadRequest?.cancel('收藏服务已释放');
    super.dispose();
  }
}
