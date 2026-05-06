import 'package:flutter/foundation.dart';
import '../models/playlist.dart';
import '../models/track.dart';
import 'auth_service.dart';
import 'api/api_client.dart';

class PlaylistSyncResult {
  final int insertedCount;
  final List<PlaylistTrack> newTracks;
  final String message;

  const PlaylistSyncResult({
    required this.insertedCount,
    required this.newTracks,
    this.message = '',
  });

  factory PlaylistSyncResult.empty({String message = ''}) {
    return PlaylistSyncResult(
      insertedCount: 0,
      newTracks: const <PlaylistTrack>[],
      message: message,
    );
  }

  bool get hasUpdates => insertedCount > 0;
}

/// 歌单服务
class PlaylistService extends ChangeNotifier {
  static final PlaylistService _instance = PlaylistService._internal();
  factory PlaylistService() => _instance;
  PlaylistService._internal() {
    // 监听登录状态变化
    AuthService().addListener(_onAuthChanged);
  }

  /// 更新歌单导入配置
  Future<bool> updateImportConfig(int playlistId, {
    required String source,
    required String sourcePlaylistId,
  }) async {
    if (!AuthService().isLoggedIn) return false;
    try {
      final result = await ApiClient().putJson(
        '/playlists/$playlistId/import-config',
        data: {
          'source': source,
          'sourcePlaylistId': sourcePlaylistId,
        },
        timeout: const Duration(seconds: 15),
      );
      if (result.ok) {
        final idx = _playlists.indexWhere((p) => p.id == playlistId);
        if (idx != -1) {
          final p = _playlists[idx];
          _playlists[idx] = Playlist(
            id: p.id,
            name: p.name,
            isDefault: p.isDefault,
            trackCount: p.trackCount,
            createdAt: p.createdAt,
            updatedAt: DateTime.now(),
            source: source,
            sourcePlaylistId: sourcePlaylistId,
          );
          notifyListeners();
        }
        return true;
      }
    } catch (_) {}
    return false;
  }

  /// 触发服务端同步
  Future<PlaylistSyncResult> syncPlaylist(int playlistId) async {
    if (!AuthService().isLoggedIn) return PlaylistSyncResult.empty();
    try {
      print('🚀 [PlaylistService] 同步开始: /playlists/$playlistId/sync (playlistId=$playlistId)');
      final result = await ApiClient().postJson(
        '/playlists/$playlistId/sync',
        timeout: const Duration(minutes: 2),
      );
      print('📥 [PlaylistService] 同步响应: status=${result.statusCode}');
      if (result.text != null && result.text!.isNotEmpty) {
        print('📄 [PlaylistService] 响应内容: ${result.text}');
      }
      if (result.ok) {
        final data = result.data as Map<String, dynamic>;
        if ((data['status'] as int?) != 200) {
          final failureMessage = data['message'] as String? ?? '同步失败';
          print('⚠️ [PlaylistService] 同步失败: $failureMessage');
          return PlaylistSyncResult.empty(message: failureMessage);
        }
        final inserted = data['insertedCount'] as int? ?? 0;
        final newTracks = (data['newTracks'] as List<dynamic>? ?? [])
            .map((item) => PlaylistTrack.fromJson(item as Map<String, dynamic>))
            .toList();
        final message = data['message'] as String? ?? '同步完成';
        print('✅ [PlaylistService] 同步完成，新增 $inserted 首');
        if (inserted > 0) {
          _applySyncUpdates(playlistId, inserted, newTracks);
        }
        return PlaylistSyncResult(
          insertedCount: inserted,
          newTracks: newTracks,
          message: message,
        );
      }
      print('⚠️ [PlaylistService] 同步失败: HTTP ${result.statusCode}');
    } catch (e) {
      print('❌ [PlaylistService] 同步异常: $e');
      return PlaylistSyncResult.empty(message: '同步失败: $e');
    }
    return PlaylistSyncResult.empty(message: '同步失败');
  }

  void _applySyncUpdates(int playlistId, int inserted, List<PlaylistTrack> newTracks) {
    final idx = _playlists.indexWhere((p) => p.id == playlistId);
    if (idx != -1) {
      final playlist = _playlists[idx];
      _playlists[idx] = Playlist(
        id: playlist.id,
        name: playlist.name,
        isDefault: playlist.isDefault,
        trackCount: playlist.trackCount + inserted,
        createdAt: playlist.createdAt,
        updatedAt: DateTime.now(),
        source: playlist.source,
        sourcePlaylistId: playlist.sourcePlaylistId,
      );
    }

    if (_currentPlaylistId == playlistId && newTracks.isNotEmpty) {
      _currentTracks = [...newTracks, ..._currentTracks];
    }

    notifyListeners();
  }

  List<Playlist> _playlists = [];
  List<Playlist> get playlists => _playlists;

  // 当前选中的歌单 ID
  int? _currentPlaylistId;
  int? get currentPlaylistId => _currentPlaylistId;

  // 当前歌单的歌曲列表
  List<PlaylistTrack> _currentTracks = [];
  List<PlaylistTrack> get currentTracks => _currentTracks;

  bool _isLoading = false;
  bool get isLoading => _isLoading;

  bool _isLoadingTracks = false;
  bool get isLoadingTracks => _isLoadingTracks;

  /// 监听认证状态变化
  void _onAuthChanged() {
    if (!AuthService().isLoggedIn) {
      // 用户登出时清空数据
      clear();
    }
  }

  /// 清空所有数据
  void clear() {
    _playlists = [];
    _currentPlaylistId = null;
    _currentTracks = [];
    notifyListeners();
  }

  /// 获取默认歌单（我的收藏）
  Playlist? get defaultPlaylist {
    return _playlists.firstWhere(
      (p) => p.isDefault,
      orElse: () => _playlists.isNotEmpty ? _playlists.first : Playlist(
        id: 0,
        name: '我的收藏',
        isDefault: true,
        trackCount: 0,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      ),
    );
  }

  /// 加载歌单列表
  Future<void> loadPlaylists() async {
    if (!AuthService().isLoggedIn) {
      print('⚠️ [PlaylistService] 未登录，无法加载歌单');
      return;
    }

    try {
      _isLoading = true;
      notifyListeners();

      final result = await ApiClient().getJson(
        '/playlists',
        timeout: const Duration(seconds: 10),
      );

      if (result.ok) {
        final data = result.data as Map<String, dynamic>;

        if (data['status'] == 200) {
          final List<dynamic> playlistsJson = data['playlists'] ?? [];
          _playlists = playlistsJson
              .map((item) => Playlist.fromJson(item as Map<String, dynamic>))
              .toList();

          print('✅ [PlaylistService] 加载歌单列表: ${_playlists.length} 个');
        } else {
          throw Exception(data['message'] ?? '加载失败');
        }
      } else {
        throw Exception('HTTP ${result.statusCode}');
      }
    } catch (e) {
      print('❌ [PlaylistService] 加载歌单列表失败: $e');
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// 创建新歌单
  /// 返回新创建的 Playlist 对象，失败时返回 null
  Future<Playlist?> createPlaylist(String name) async {
    if (!AuthService().isLoggedIn) {
      print('⚠️ [PlaylistService] 未登录，无法创建歌单');
      return null;
    }

    if (name.trim().isEmpty) {
      print('⚠️ [PlaylistService] 歌单名称不能为空');
      return null;
    }

    try {
      final result = await ApiClient().postJson(
        '/playlists',
        data: {'name': name.trim()},
        timeout: const Duration(seconds: 10),
      );

      if (result.ok) {
        final data = result.data as Map<String, dynamic>;

        if (data['status'] == 200) {
          // 添加到本地列表
          final newPlaylist = Playlist.fromJson(data['playlist'] as Map<String, dynamic>);
          _playlists.add(newPlaylist);

          print('✅ [PlaylistService] 创建歌单成功: $name (id=${newPlaylist.id})');
          notifyListeners();
          return newPlaylist;
        } else {
          throw Exception(data['message'] ?? '创建失败');
        }
      } else {
        throw Exception('HTTP ${result.statusCode}');
      }
    } catch (e) {
      print('❌ [PlaylistService] 创建歌单失败: $e');
      return null;
    }
  }

  /// 更新歌单（重命名）
  Future<bool> updatePlaylist(int playlistId, String name) async {
    if (!AuthService().isLoggedIn) {
      print('⚠️ [PlaylistService] 未登录，无法更新歌单');
      return false;
    }

    if (name.trim().isEmpty) {
      print('⚠️ [PlaylistService] 歌单名称不能为空');
      return false;
    }

    try {
      final result = await ApiClient().putJson(
        '/playlists/$playlistId',
        data: {'name': name.trim()},
        timeout: const Duration(seconds: 10),
      );

      if (result.ok) {
        final data = result.data as Map<String, dynamic>;

        if (data['status'] == 200) {
          // 更新本地列表
          final index = _playlists.indexWhere((p) => p.id == playlistId);
          if (index != -1) {
            _playlists[index] = Playlist(
              id: _playlists[index].id,
              name: name.trim(),
              isDefault: _playlists[index].isDefault,
              trackCount: _playlists[index].trackCount,
              createdAt: _playlists[index].createdAt,
              updatedAt: DateTime.now(),
              source: _playlists[index].source,
              sourcePlaylistId: _playlists[index].sourcePlaylistId,
            );
          }

          print('✅ [PlaylistService] 更新歌单成功: $name');
          notifyListeners();
          return true;
        } else {
          throw Exception(data['message'] ?? '更新失败');
        }
      } else {
        throw Exception('HTTP ${result.statusCode}');
      }
    } catch (e) {
      print('❌ [PlaylistService] 更新歌单失败: $e');
      return false;
    }
  }

  /// 删除歌单
  Future<bool> deletePlaylist(int playlistId) async {
    if (!AuthService().isLoggedIn) {
      print('⚠️ [PlaylistService] 未登录，无法删除歌单');
      return false;
    }

    try {
      final result = await ApiClient().postJson(
        '/playlists/$playlistId/delete',
        data: {},
        timeout: const Duration(seconds: 10),
      );

      if (result.ok) {
        final data = result.data as Map<String, dynamic>;

        if (data['status'] == 200) {
          // 从本地列表删除
          _playlists.removeWhere((p) => p.id == playlistId);

          // 如果删除的是当前选中的歌单，清空当前歌曲列表
          if (_currentPlaylistId == playlistId) {
            _currentPlaylistId = null;
            _currentTracks = [];
          }

          print('✅ [PlaylistService] 删除歌单成功');
          notifyListeners();
          return true;
        } else {
          throw Exception(data['message'] ?? '删除失败');
        }
      } else {
        throw Exception('HTTP ${result.statusCode}');
      }
    } catch (e) {
      print('❌ [PlaylistService] 删除歌单失败: $e');
      return false;
    }
  }

  /// 添加歌曲到歌单
  Future<bool> addTrackToPlaylist(int playlistId, Track track) async {
    if (!AuthService().isLoggedIn) {
      print('⚠️ [PlaylistService] 未登录，无法添加歌曲');
      return false;
    }

    try {
      final playlistTrack = PlaylistTrack.fromTrack(track);

      final result = await ApiClient().postJson(
        '/playlists/$playlistId/tracks',
        data: playlistTrack.toJson(),
        timeout: const Duration(seconds: 10),
      );

      if (result.ok) {
        final data = result.data as Map<String, dynamic>;

        if (data['status'] == 200) {
          // 更新歌单的歌曲数量
          final index = _playlists.indexWhere((p) => p.id == playlistId);
          if (index != -1) {
            _playlists[index] = Playlist(
              id: _playlists[index].id,
              name: _playlists[index].name,
              isDefault: _playlists[index].isDefault,
              trackCount: _playlists[index].trackCount + 1,
              createdAt: _playlists[index].createdAt,
              updatedAt: DateTime.now(),
              source: _playlists[index].source,
              sourcePlaylistId: _playlists[index].sourcePlaylistId,
            );
          }

          // 如果是当前选中的歌单，添加到当前列表
          if (_currentPlaylistId == playlistId) {
            _currentTracks.insert(0, playlistTrack);
          }

          print('✅ [PlaylistService] 添加歌曲成功: ${track.name}');
          notifyListeners();
          return true;
        } else {
          throw Exception(data['message'] ?? '添加失败');
        }
      } else {
        throw Exception('HTTP ${result.statusCode}');
      }
    } catch (e) {
      print('❌ [PlaylistService] 添加歌曲失败: $e');
      return false;
    }
  }

  /// 批量添加歌曲到歌单（高性能版本，一次网络请求）
  /// [mode]
  ///   - 'append'（默认）：追加到歌单末尾，position 在当前最大值后递增
  ///   - 'replace'：先清空目标歌单再写入，用于"同步刷新"等场景
  /// 传入的 [tracks] 顺序即写入顺序，后端会按数组下标分配 position
  /// 返回 {successCount, skipCount, failCount}
  Future<Map<String, int>> addTracksToPlaylist(
    int playlistId,
    List<Track> tracks, {
    String mode = 'append',
  }) async {
    if (!AuthService().isLoggedIn) {
      print('⚠️ [PlaylistService] 未登录，无法批量添加歌曲');
      return {'successCount': 0, 'skipCount': 0, 'failCount': tracks.length};
    }

    if (tracks.isEmpty) {
      return {'successCount': 0, 'skipCount': 0, 'failCount': 0};
    }

    try {
      // 转换为 API 需要的格式（保持原始顺序）
      final tracksData = tracks.map((track) {
        final playlistTrack = PlaylistTrack.fromTrack(track);
        return playlistTrack.toJson();
      }).toList();

      final result = await ApiClient().postJson(
        '/playlists/$playlistId/tracks/batch',
        data: {
          'tracks': tracksData,
          'mode': mode,
        },
        timeout: const Duration(seconds: 60),
      );

      if (result.ok) {
        final data = result.data as Map<String, dynamic>;

        if (data['status'] == 200) {
          final successCount = data['successCount'] as int? ?? 0;
          final skipCount = data['skipCount'] as int? ?? 0;
          final failCount = data['failCount'] as int? ?? 0;

          // 更新歌单的歌曲数量
          final index = _playlists.indexWhere((p) => p.id == playlistId);
          if (index != -1) {
            _playlists[index] = Playlist(
              id: _playlists[index].id,
              name: _playlists[index].name,
              isDefault: _playlists[index].isDefault,
              trackCount: _playlists[index].trackCount + successCount,
              createdAt: _playlists[index].createdAt,
              updatedAt: DateTime.now(),
              source: _playlists[index].source,
              sourcePlaylistId: _playlists[index].sourcePlaylistId,
            );
          }

          print('✅ [PlaylistService] 批量添加完成: 成功=$successCount, 跳过=$skipCount, 失败=$failCount');
          notifyListeners();
          return {'successCount': successCount, 'skipCount': skipCount, 'failCount': failCount};
        } else {
          throw Exception(data['message'] ?? '批量添加失败');
        }
      } else {
        throw Exception('HTTP ${result.statusCode}');
      }
    } catch (e) {
      print('❌ [PlaylistService] 批量添加歌曲失败: $e');
      return {'successCount': 0, 'skipCount': 0, 'failCount': tracks.length};
    }
  }

  /// 加载歌单中的歌曲
  Future<void> loadPlaylistTracks(int playlistId) async {
    if (!AuthService().isLoggedIn) {
      print('⚠️ [PlaylistService] 未登录，无法加载歌曲');
      return;
    }

    try {
      _isLoadingTracks = true;
      _currentPlaylistId = playlistId;
      notifyListeners();

      final result = await ApiClient().getJson(
        '/playlists/$playlistId/tracks',
        timeout: const Duration(seconds: 10),
      );

      if (result.ok) {
        final data = result.data as Map<String, dynamic>;

        if (data['status'] == 200) {
          final List<dynamic> tracksJson = data['tracks'] ?? [];
          _currentTracks = tracksJson
              .map((item) => PlaylistTrack.fromJson(item as Map<String, dynamic>))
              .toList();

          print('✅ [PlaylistService] 加载歌曲列表: ${_currentTracks.length} 首');
        } else {
          throw Exception(data['message'] ?? '加载失败');
        }
      } else {
        throw Exception('HTTP ${result.statusCode}');
      }
    } catch (e) {
      print('❌ [PlaylistService] 加载歌曲列表失败: $e');
    } finally {
      _isLoadingTracks = false;
      notifyListeners();
    }
  }

  /// 从歌单删除歌曲（通过 trackId 和 source 字符串）
  Future<bool> removeTrackFromPlaylist(int playlistId, String trackId, String source) async {
    if (!AuthService().isLoggedIn) {
      print('⚠️ [PlaylistService] 未登录，无法删除歌曲');
      return false;
    }

    try {
      // 诊断日志
      print('🗑️ [PlaylistService] 准备删除歌曲:');
      print('   PlaylistId: $playlistId');
      print('   TrackId: $trackId');
      print('   Source: $source');
      print('   URL: /playlists/$playlistId/tracks/remove');

      // 使用 POST 请求代替 DELETE（避免某些框架的解析问题）
      final result = await ApiClient().postJson(
        '/playlists/$playlistId/tracks/remove',
        data: {
          'trackId': trackId,
          'source': source,
        },
        timeout: const Duration(seconds: 10),
      );

      print('📥 [PlaylistService] 删除请求响应状态码: ${result.statusCode}');
      if (!result.ok) {
        print('📄 [PlaylistService] 响应内容: ${result.text}');
      }

      if (result.ok) {
        final data = result.data as Map<String, dynamic>;

        if (data['status'] == 200) {
          // 更新歌单的歌曲数量
          final index = _playlists.indexWhere((p) => p.id == playlistId);
          if (index != -1) {
            _playlists[index] = Playlist(
              id: _playlists[index].id,
              name: _playlists[index].name,
              isDefault: _playlists[index].isDefault,
              trackCount: _playlists[index].trackCount - 1,
              createdAt: _playlists[index].createdAt,
              updatedAt: DateTime.now(),
              source: _playlists[index].source,
              sourcePlaylistId: _playlists[index].sourcePlaylistId,
            );
          }

          // 从当前列表删除
          if (_currentPlaylistId == playlistId) {
            _currentTracks.removeWhere((t) =>
              t.trackId == trackId && t.source.name == source
            );
          }

          print('✅ [PlaylistService] 删除歌曲成功');
          notifyListeners();
          return true;
        } else {
          throw Exception(data['message'] ?? '删除失败');
        }
      } else {
        throw Exception('HTTP ${result.statusCode}');
      }
    } catch (e) {
      print('❌ [PlaylistService] 删除歌曲失败: $e');
      return false;
    }
  }

  /// 从歌单删除歌曲（通过 PlaylistTrack 对象）
  Future<bool> removePlaylistTrack(int playlistId, PlaylistTrack track) async {
    final source = track.source.toString().split('.').last;
    return removeTrackFromPlaylist(playlistId, track.trackId, source);
  }

  /// 批量删除歌曲
  Future<int> removeTracksFromPlaylist(int playlistId, List<PlaylistTrack> tracks) async {
    if (!AuthService().isLoggedIn) {
      print('⚠️ [PlaylistService] 未登录，无法批量删除歌曲');
      return 0;
    }

    if (tracks.isEmpty) {
      print('⚠️ [PlaylistService] 歌曲列表为空');
      return 0;
    }

    try {
      // 构建删除列表
      final tracksToDelete = tracks.map((track) => {
        'trackId': track.trackId,
        'source': track.source.toString().split('.').last,
      }).toList();

      print('🗑️ [PlaylistService] 准备批量删除 ${tracks.length} 首歌曲');

      final result = await ApiClient().postJson(
        '/playlists/$playlistId/tracks/batch-remove',
        data: {
          'tracks': tracksToDelete,
        },
        timeout: const Duration(seconds: 30),
      );

      print('📥 [PlaylistService] 批量删除响应状态码: ${result.statusCode}');

      if (result.ok) {
        final data = result.data as Map<String, dynamic>;

        if (data['status'] == 200) {
          final deletedCount = data['deletedCount'] as int? ?? 0;

          // 更新歌单的歌曲数量
          final index = _playlists.indexWhere((p) => p.id == playlistId);
          if (index != -1) {
            _playlists[index] = Playlist(
              id: _playlists[index].id,
              name: _playlists[index].name,
              isDefault: _playlists[index].isDefault,
              trackCount: _playlists[index].trackCount - deletedCount,
              createdAt: _playlists[index].createdAt,
              updatedAt: DateTime.now(),
              source: _playlists[index].source,
              sourcePlaylistId: _playlists[index].sourcePlaylistId,
            );
          }

          // 从当前列表批量删除
          if (_currentPlaylistId == playlistId) {
            for (var track in tracks) {
              _currentTracks.removeWhere((t) =>
                t.trackId == track.trackId && t.source == track.source
              );
            }
          }

          print('✅ [PlaylistService] 批量删除成功: $deletedCount 首');
          notifyListeners();
          return deletedCount;
        } else {
          throw Exception(data['message'] ?? '批量删除失败');
        }
      } else {
        throw Exception('HTTP ${result.statusCode}');
      }
    } catch (e) {
      print('❌ [PlaylistService] 批量删除失败: $e');
      return 0;
    }
  }

  /// 检查歌曲是否在指定歌单中
  bool isTrackInPlaylist(int playlistId, Track track) {
    if (_currentPlaylistId != playlistId) {
      return false;
    }
    return _currentTracks.any((t) =>
      t.trackId == track.id.toString() && t.source == track.source
    );
  }

  /// 检查歌曲是否在用户的任一歌单中（调用后端 API）
  Future<TrackInPlaylistResult> isTrackInAnyPlaylist(Track track) async {
    if (!AuthService().isLoggedIn) {
      return TrackInPlaylistResult(inPlaylist: false, playlistIds: [], playlistNames: []);
    }

    try {
      final trackId = track.id.toString();
      final source = track.source.name;

      final result = await ApiClient().getJson(
        '/playlists/check-track',
        queryParameters: {'trackId': trackId, 'source': source},
        timeout: const Duration(seconds: 10),
      );

      if (result.ok) {
        final data = result.data as Map<String, dynamic>;
        return TrackInPlaylistResult(
          inPlaylist: data['inPlaylist'] as bool? ?? false,
          playlistIds: (data['playlistIds'] as List<dynamic>?)?.map((e) => e as int).toList() ?? [],
          playlistNames: (data['playlistNames'] as List<dynamic>?)?.map((e) => e as String).toList() ?? [],
        );
      }
    } catch (e) {
      print('❌ [PlaylistService] 检查歌曲是否在歌单中失败: $e');
    }

    return TrackInPlaylistResult(inPlaylist: false, playlistIds: [], playlistNames: []);
  }

  /// 检查歌曲是否在"我的收藏"中
  bool isFavorite(Track? track) {
    if (track == null) return false;
    final favPlaylist = defaultPlaylist;
    if (favPlaylist == null) return false;

    // 如果当前正在加载收藏歌单，优先从 _currentTracks 查找
    if (_currentPlaylistId == favPlaylist.id) {
      return _currentTracks.any((t) => t.trackId == track.id.toString() && t.source == track.source);
    }

    // 否则只能返回 false 或等待 API 检查（同步调用不支持 Future）
    return false;
  }

  /// 切换收藏状态
  Future<void> toggleFavorite(Track? track) async {
    if (track == null) return;
    final favPlaylist = defaultPlaylist;
    if (favPlaylist == null) return;

    final result = await isTrackInAnyPlaylist(track);
    final isInFav = result.playlistIds.contains(favPlaylist.id);

    if (isInFav) {
      await removeTrackFromPlaylist(favPlaylist.id, track.id.toString(), track.source.name);
    } else {
      await addTrackToPlaylist(favPlaylist.id, track);
    }
  }
}

/// 歌曲在歌单中的检查结果
class TrackInPlaylistResult {
  final bool inPlaylist;
  final List<int> playlistIds;
  final List<String> playlistNames;

  TrackInPlaylistResult({
    required this.inPlaylist,
    required this.playlistIds,
    required this.playlistNames,
  });
}
