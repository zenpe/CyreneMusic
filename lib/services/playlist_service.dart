import 'dart:math';

import 'package:flutter/foundation.dart';

import '../models/playlist.dart';
import '../models/track.dart';
import 'api/api_client.dart';
import 'auth_service.dart';
import 'structured_log_service.dart';

class PlaylistSyncResult {
  final bool succeeded;
  final int trackCount;
  final String message;

  const PlaylistSyncResult({
    required this.succeeded,
    required this.trackCount,
    this.message = '',
  });

  factory PlaylistSyncResult.empty({String message = ''}) =>
      PlaylistSyncResult(succeeded: false, trackCount: 0, message: message);

  factory PlaylistSyncResult.success(Playlist playlist) => PlaylistSyncResult(
    succeeded: true,
    trackCount: playlist.trackCount,
    message: '同步完成',
  );
}

class PlaylistTrackMatch {
  final int playlistId;
  final String playlistName;
  final int itemId;

  const PlaylistTrackMatch({
    required this.playlistId,
    required this.playlistName,
    required this.itemId,
  });

  factory PlaylistTrackMatch.fromJson(Map<String, dynamic> json) =>
      PlaylistTrackMatch(
        playlistId: (json['playlistId'] as num).toInt(),
        playlistName: json['playlistName'] as String,
        itemId: (json['itemId'] as num).toInt(),
      );
}

class TrackInPlaylistResult {
  final bool known;
  final List<PlaylistTrackMatch> matches;

  const TrackInPlaylistResult({required this.known, required this.matches});

  bool get inPlaylist => matches.isNotEmpty;
  List<int> get playlistIds =>
      matches.map((match) => match.playlistId).toList();
  List<String> get playlistNames =>
      matches.map((match) => match.playlistName).toList();

  int? itemIdFor(int playlistId) {
    for (final match in matches) {
      if (match.playlistId == playlistId) return match.itemId;
    }
    return null;
  }
}

class PlaylistService extends ChangeNotifier {
  static final PlaylistService _instance = PlaylistService._internal();
  factory PlaylistService() => _instance;

  PlaylistService._internal() {
    final auth = AuthService();
    _observedSessionIdentity = _sessionIdentity();
    auth.addListener(_onAuthChanged);
  }

  final Random _secureRandom = Random.secure();
  final Map<int, List<PlaylistTrack>> _tracksByPlaylist = {};
  final Map<int, int> _trackLoadGenerations = {};
  int _playlistLoadGeneration = 0;
  String? _observedSessionIdentity;
  List<Playlist> _playlists = [];
  int? _currentPlaylistId;
  bool _isLoading = false;
  bool _isLoadingTracks = false;

  List<Playlist> get playlists => List.unmodifiable(_playlists);
  int? get currentPlaylistId => _currentPlaylistId;
  List<PlaylistTrack> get currentTracks => List.unmodifiable(
    _currentPlaylistId == null
        ? const <PlaylistTrack>[]
        : (_tracksByPlaylist[_currentPlaylistId] ?? const <PlaylistTrack>[]),
  );
  bool get isLoading => _isLoading;
  bool get isLoadingTracks => _isLoadingTracks;

  Playlist? get defaultPlaylist {
    for (final playlist in _playlists) {
      if (playlist.isDefault) return playlist;
    }
    return null;
  }

  String? _sessionIdentity() {
    final auth = AuthService();
    final token = auth.token;
    final userId = auth.currentUser?.id;
    if (!auth.isLoggedIn || token == null || token.isEmpty || userId == null) {
      return null;
    }
    return '$userId:$token';
  }

  bool _isCurrentSession(String session) => _sessionIdentity() == session;

  String _operationId() {
    final bytes = List<int>.generate(16, (_) => _secureRandom.nextInt(256));
    bytes[6] = (bytes[6] & 0x0f) | 0x40;
    bytes[8] = (bytes[8] & 0x3f) | 0x80;
    String hex(int value) => value.toRadixString(16).padLeft(2, '0');
    final value = bytes.map(hex).join();
    return '${value.substring(0, 8)}-${value.substring(8, 12)}-'
        '${value.substring(12, 16)}-${value.substring(16, 20)}-'
        '${value.substring(20)}';
  }

  void _onAuthChanged() {
    final current = _sessionIdentity();
    if (current == _observedSessionIdentity) return;
    _observedSessionIdentity = current;
    clear();
  }

  void clear() {
    _playlistLoadGeneration++;
    _playlists = [];
    _currentPlaylistId = null;
    _tracksByPlaylist.clear();
    _trackLoadGenerations.clear();
    _isLoading = false;
    _isLoadingTracks = false;
    notifyListeners();
  }

  Playlist? _playlist(int playlistId) {
    for (final playlist in _playlists) {
      if (playlist.id == playlistId) return playlist;
    }
    return null;
  }

  bool _isWritable(int playlistId) => _playlist(playlistId)?.isLocal == true;

  void _invalidateLoadsForMutation([int? playlistId]) {
    _playlistLoadGeneration++;
    var shouldNotify = _isLoading;
    _isLoading = false;
    if (playlistId != null) {
      _trackLoadGenerations[playlistId] =
          (_trackLoadGenerations[playlistId] ?? 0) + 1;
      if (_currentPlaylistId == playlistId && _isLoadingTracks) {
        _isLoadingTracks = false;
        shouldNotify = true;
      }
    }
    if (shouldNotify) notifyListeners();
  }

  @visibleForTesting
  static Playlist mergePlaylistState(Playlist current, Playlist incoming) {
    final keepCurrentMetadata = current.updatedAt.isAfter(incoming.updatedAt);
    final keepCurrentContent =
        current.contentRevision > incoming.contentRevision;
    return Playlist(
      id: incoming.id,
      name: keepCurrentMetadata ? current.name : incoming.name,
      isDefault: incoming.isDefault,
      trackCount: keepCurrentContent ? current.trackCount : incoming.trackCount,
      coverUrl: keepCurrentContent ? current.coverUrl : incoming.coverUrl,
      createdAt: incoming.createdAt,
      updatedAt: keepCurrentMetadata ? current.updatedAt : incoming.updatedAt,
      source: incoming.source,
      sourcePlaylistId: incoming.sourcePlaylistId,
      type: incoming.type,
      contentRevision: max(current.contentRevision, incoming.contentRevision),
      orderRevision: max(current.orderRevision, incoming.orderRevision),
      syncStatus: keepCurrentMetadata
          ? current.syncStatus
          : incoming.syncStatus,
      lastSyncedAt: keepCurrentMetadata
          ? current.lastSyncedAt
          : incoming.lastSyncedAt,
    );
  }

  Playlist _upsertPlaylist(Playlist playlist) {
    final index = _playlists.indexWhere((item) => item.id == playlist.id);
    if (index < 0) {
      _playlists.add(playlist);
      return playlist;
    }
    final merged = mergePlaylistState(_playlists[index], playlist);
    _playlists[index] = merged;
    return merged;
  }

  Playlist? _playlistFromResponse(dynamic data) {
    if (data is! Map<String, dynamic>) return null;
    final json = data['playlist'];
    if (json is! Map<String, dynamic>) return null;
    final playlist = Playlist.fromJson(json);
    return _upsertPlaylist(playlist);
  }

  Future<void> _refreshCurrentTracks(int playlistId) async {
    if (_currentPlaylistId == playlistId) await loadPlaylistTracks(playlistId);
  }

  Future<void> loadPlaylists() async {
    final session = _sessionIdentity();
    if (session == null) return;
    final generation = ++_playlistLoadGeneration;
    _isLoading = true;
    notifyListeners();
    try {
      final result = await ApiClient().getJson(
        '/playlists',
        timeout: const Duration(seconds: 10),
      );
      final data = result.data;
      if (!result.ok ||
          data is! Map<String, dynamic> ||
          data['status'] != 200) {
        throw Exception(
          data is Map ? data['message'] : 'HTTP ${result.statusCode}',
        );
      }
      if (!_isCurrentSession(session) ||
          generation != _playlistLoadGeneration) {
        return;
      }
      final currentById = {for (final item in _playlists) item.id: item};
      _playlists = (data['playlists'] as List<dynamic>? ?? const []).map((
        item,
      ) {
        final incoming = Playlist.fromJson(item as Map<String, dynamic>);
        final current = currentById[incoming.id];
        return current == null
            ? incoming
            : mergePlaylistState(current, incoming);
      }).toList();
    } catch (error) {
      StructuredLogService.log('[PlaylistService] 加载歌单失败: $error');
    } finally {
      if (_isCurrentSession(session) && generation == _playlistLoadGeneration) {
        _isLoading = false;
        notifyListeners();
      }
    }
  }

  Future<Playlist?> createPlaylist(String name) async {
    final session = _sessionIdentity();
    if (session == null || name.trim().isEmpty) return null;
    _invalidateLoadsForMutation();
    try {
      final result = await ApiClient().postJson(
        '/playlists',
        data: {'name': name.trim(), 'operationId': _operationId()},
        timeout: const Duration(seconds: 10),
      );
      if (!result.ok || !_isCurrentSession(session)) return null;
      _invalidateLoadsForMutation();
      final playlist = _playlistFromResponse(result.data);
      notifyListeners();
      return playlist;
    } catch (error) {
      StructuredLogService.log('[PlaylistService] 创建歌单失败: $error');
      return null;
    }
  }

  Future<Playlist?> followPlaylist({
    required String source,
    required String sourcePlaylistId,
    String? name,
  }) async {
    final session = _sessionIdentity();
    if (session == null) return null;
    _invalidateLoadsForMutation();
    try {
      final result = await ApiClient().postJson(
        '/playlists/follow',
        data: {
          'source': source,
          'sourcePlaylistId': sourcePlaylistId,
          if (name?.trim().isNotEmpty == true) 'name': name!.trim(),
          'operationId': _operationId(),
        },
        timeout: const Duration(seconds: 60),
      );
      if (!result.ok || !_isCurrentSession(session)) return null;
      _invalidateLoadsForMutation();
      final playlist = _playlistFromResponse(result.data);
      notifyListeners();
      return playlist;
    } catch (error) {
      StructuredLogService.log('[PlaylistService] 关注来源歌单失败: $error');
      return null;
    }
  }

  Future<Playlist?> copyPlaylist(int playlistId, {String? name}) async {
    final session = _sessionIdentity();
    if (session == null) return null;
    _invalidateLoadsForMutation();
    try {
      final result = await ApiClient().postJson(
        '/playlists/$playlistId/copy',
        data: {
          'operationId': _operationId(),
          if (name?.trim().isNotEmpty == true) 'name': name!.trim(),
        },
        timeout: const Duration(seconds: 30),
      );
      if (!result.ok || !_isCurrentSession(session)) return null;
      _invalidateLoadsForMutation();
      final playlist = _playlistFromResponse(result.data);
      notifyListeners();
      return playlist;
    } catch (error) {
      StructuredLogService.log('[PlaylistService] 复制歌单失败: $error');
      return null;
    }
  }

  Future<bool> updatePlaylist(int playlistId, String name) async {
    final session = _sessionIdentity();
    if (session == null || name.trim().isEmpty) return false;
    _invalidateLoadsForMutation(playlistId);
    try {
      final result = await ApiClient().putJson(
        '/playlists/$playlistId',
        data: {'name': name.trim(), 'operationId': _operationId()},
        timeout: const Duration(seconds: 10),
      );
      if (!result.ok || !_isCurrentSession(session)) return false;
      _invalidateLoadsForMutation(playlistId);
      if (_playlistFromResponse(result.data) == null) return false;
      notifyListeners();
      return true;
    } catch (error) {
      StructuredLogService.log('[PlaylistService] 重命名歌单失败: $error');
      return false;
    }
  }

  Future<bool> deletePlaylist(int playlistId) async {
    final session = _sessionIdentity();
    if (session == null) return false;
    _invalidateLoadsForMutation(playlistId);
    try {
      final result = await ApiClient().postJson(
        '/playlists/$playlistId/delete',
        data: {'operationId': _operationId()},
        timeout: const Duration(seconds: 10),
      );
      if (!result.ok || !_isCurrentSession(session)) return false;
      _invalidateLoadsForMutation(playlistId);
      _playlists.removeWhere((item) => item.id == playlistId);
      _tracksByPlaylist.remove(playlistId);
      if (_currentPlaylistId == playlistId) _currentPlaylistId = null;
      notifyListeners();
      return true;
    } catch (error) {
      StructuredLogService.log('[PlaylistService] 删除歌单失败: $error');
      return false;
    }
  }

  Future<bool> addTrackToPlaylist(int playlistId, Track track) async {
    final session = _sessionIdentity();
    if (session == null || !_isWritable(playlistId)) return false;
    _invalidateLoadsForMutation(playlistId);
    try {
      final result = await ApiClient().postJson(
        '/playlists/$playlistId/tracks',
        data: {
          'operationId': _operationId(),
          'track': PlaylistTrack.fromTrack(track).toJson(),
        },
        timeout: const Duration(seconds: 10),
      );
      if (!result.ok || !_isCurrentSession(session)) return false;
      _invalidateLoadsForMutation(playlistId);
      _playlistFromResponse(result.data);
      await _refreshCurrentTracks(playlistId);
      if (!_isCurrentSession(session)) return false;
      notifyListeners();
      return true;
    } catch (error) {
      StructuredLogService.log('[PlaylistService] 添加歌曲失败: $error');
      return false;
    }
  }

  Future<Map<String, int>> addTracksToPlaylist(
    int playlistId,
    List<Track> tracks,
  ) async {
    final session = _sessionIdentity();
    if (session == null || !_isWritable(playlistId) || tracks.isEmpty) {
      return {'successCount': 0, 'skipCount': 0, 'failCount': tracks.length};
    }
    _invalidateLoadsForMutation(playlistId);
    try {
      final result = await ApiClient().postJson(
        '/playlists/$playlistId/tracks/batch',
        data: {
          'operationId': _operationId(),
          'tracks': tracks
              .map((track) => PlaylistTrack.fromTrack(track).toJson())
              .toList(),
        },
        timeout: const Duration(seconds: 60),
      );
      final data = result.data;
      if (!result.ok ||
          data is! Map<String, dynamic> ||
          !_isCurrentSession(session)) {
        throw Exception('HTTP ${result.statusCode}');
      }
      _invalidateLoadsForMutation(playlistId);
      final added = (data['addedCount'] as num?)?.toInt() ?? 0;
      _playlistFromResponse(data);
      await _refreshCurrentTracks(playlistId);
      if (!_isCurrentSession(session)) {
        return {'successCount': 0, 'skipCount': 0, 'failCount': tracks.length};
      }
      notifyListeners();
      return {
        'successCount': added,
        'skipCount': tracks.length - added,
        'failCount': 0,
      };
    } catch (error) {
      StructuredLogService.log('[PlaylistService] 批量添加失败: $error');
      return {'successCount': 0, 'skipCount': 0, 'failCount': tracks.length};
    }
  }

  Future<void> loadPlaylistTracks(int playlistId) async {
    final session = _sessionIdentity();
    if (session == null) return;
    final generation = (_trackLoadGenerations[playlistId] ?? 0) + 1;
    _trackLoadGenerations[playlistId] = generation;
    _currentPlaylistId = playlistId;
    _isLoadingTracks = true;
    notifyListeners();
    try {
      final result = await ApiClient().getJson(
        '/playlists/$playlistId/tracks',
        timeout: const Duration(seconds: 10),
      );
      final data = result.data;
      if (!result.ok ||
          data is! Map<String, dynamic> ||
          data['status'] != 200) {
        throw Exception(
          data is Map ? data['message'] : 'HTTP ${result.statusCode}',
        );
      }
      if (!_isCurrentSession(session) ||
          _trackLoadGenerations[playlistId] != generation) {
        return;
      }
      final tracks = (data['tracks'] as List<dynamic>? ?? const [])
          .map((item) => PlaylistTrack.fromJson(item as Map<String, dynamic>))
          .toList();
      _tracksByPlaylist[playlistId] = tracks;
      final current = _playlist(playlistId);
      if (current != null) {
        _upsertPlaylist(
          current.copyWith(
            trackCount: tracks.length,
            contentRevision:
                (data['contentRevision'] as num?)?.toInt() ??
                current.contentRevision,
            orderRevision:
                (data['orderRevision'] as num?)?.toInt() ??
                current.orderRevision,
          ),
        );
      }
    } catch (error) {
      StructuredLogService.log('[PlaylistService] 加载歌曲失败: $error');
    } finally {
      if (_isCurrentSession(session) &&
          _trackLoadGenerations[playlistId] == generation &&
          _currentPlaylistId == playlistId) {
        _isLoadingTracks = false;
        notifyListeners();
      }
    }
  }

  Future<bool> removePlaylistTrack(int playlistId, PlaylistTrack track) async {
    final session = _sessionIdentity();
    final itemId = track.itemId;
    if (session == null || !_isWritable(playlistId) || itemId == null) {
      return false;
    }
    _invalidateLoadsForMutation(playlistId);
    try {
      final result = await ApiClient().deleteJson(
        '/playlists/$playlistId/items/$itemId',
        data: {'operationId': _operationId()},
        timeout: const Duration(seconds: 10),
      );
      if (!result.ok || !_isCurrentSession(session)) return false;
      _invalidateLoadsForMutation(playlistId);
      _playlistFromResponse(result.data);
      _tracksByPlaylist[playlistId]?.removeWhere(
        (item) => item.itemId == itemId,
      );
      notifyListeners();
      return true;
    } catch (error) {
      StructuredLogService.log('[PlaylistService] 移除歌曲失败: $error');
      return false;
    }
  }

  Future<bool> removeTrackMatch(PlaylistTrackMatch match, Track track) {
    final value = PlaylistTrack.fromTrack(track);
    return removePlaylistTrack(
      match.playlistId,
      PlaylistTrack(
        itemId: match.itemId,
        trackId: value.trackId,
        name: value.name,
        artists: value.artists,
        album: value.album,
        picUrl: value.picUrl,
        source: value.source,
        sourceIds: value.sourceIds,
        addedAt: value.addedAt,
      ),
    );
  }

  Future<int> removeTracksFromPlaylist(
    int playlistId,
    List<PlaylistTrack> tracks,
  ) async {
    final session = _sessionIdentity();
    final itemIds = tracks
        .map((track) => track.itemId)
        .whereType<int>()
        .toSet()
        .toList();
    if (session == null || !_isWritable(playlistId) || itemIds.isEmpty) {
      return 0;
    }
    _invalidateLoadsForMutation(playlistId);
    try {
      final result = await ApiClient().postJson(
        '/playlists/$playlistId/items/batch-remove',
        data: {'operationId': _operationId(), 'itemIds': itemIds},
        timeout: const Duration(seconds: 30),
      );
      final data = result.data;
      if (!result.ok ||
          data is! Map<String, dynamic> ||
          !_isCurrentSession(session)) {
        return 0;
      }
      _invalidateLoadsForMutation(playlistId);
      final removed = (data['removedCount'] as num?)?.toInt() ?? 0;
      _playlistFromResponse(data);
      _tracksByPlaylist[playlistId]?.removeWhere(
        (track) => itemIds.contains(track.itemId),
      );
      notifyListeners();
      return removed;
    } catch (error) {
      StructuredLogService.log('[PlaylistService] 批量移除失败: $error');
      return 0;
    }
  }

  Future<bool> replacePlaylistTrack(
    int playlistId,
    PlaylistTrack current,
    Track replacement,
  ) async {
    final session = _sessionIdentity();
    if (session == null || !_isWritable(playlistId) || current.itemId == null) {
      return false;
    }
    _invalidateLoadsForMutation(playlistId);
    try {
      final result = await ApiClient().postJson(
        '/playlists/$playlistId/items/${current.itemId}/replace',
        data: {
          'operationId': _operationId(),
          'track': PlaylistTrack.fromTrack(replacement).toJson(),
        },
        timeout: const Duration(seconds: 15),
      );
      if (!result.ok || !_isCurrentSession(session)) return false;
      _invalidateLoadsForMutation(playlistId);
      _playlistFromResponse(result.data);
      await _refreshCurrentTracks(playlistId);
      if (!_isCurrentSession(session)) return false;
      notifyListeners();
      return true;
    } catch (error) {
      StructuredLogService.log('[PlaylistService] 原子换源失败: $error');
      return false;
    }
  }

  Future<bool> reorderPlaylist(
    int playlistId,
    List<PlaylistTrack> orderedTracks,
  ) async {
    final session = _sessionIdentity();
    final playlist = _playlist(playlistId);
    final itemIds = orderedTracks
        .map((track) => track.itemId)
        .whereType<int>()
        .toList();
    if (session == null ||
        playlist == null ||
        !playlist.isLocal ||
        itemIds.length != orderedTracks.length) {
      return false;
    }
    _invalidateLoadsForMutation(playlistId);
    try {
      final result = await ApiClient().postJson(
        '/playlists/$playlistId/items/reorder',
        data: {
          'operationId': _operationId(),
          'expectedOrderRevision': playlist.orderRevision,
          'itemIds': itemIds,
        },
        timeout: const Duration(seconds: 15),
      );
      if (!result.ok || !_isCurrentSession(session)) return false;
      _invalidateLoadsForMutation(playlistId);
      _playlistFromResponse(result.data);
      _tracksByPlaylist[playlistId] = List.of(orderedTracks);
      notifyListeners();
      return true;
    } catch (error) {
      StructuredLogService.log('[PlaylistService] 歌单排序失败: $error');
      return false;
    }
  }

  Future<PlaylistSyncResult> syncPlaylist(int playlistId) async {
    final session = _sessionIdentity();
    final playlist = _playlist(playlistId);
    if (session == null || playlist?.isSynced != true) {
      return PlaylistSyncResult.empty(message: '仅来源订阅可以同步');
    }
    _invalidateLoadsForMutation(playlistId);
    try {
      final result = await ApiClient().postJson(
        '/playlists/$playlistId/sync',
        data: {'operationId': _operationId()},
        timeout: const Duration(seconds: 60),
      );
      if (!_isCurrentSession(session)) {
        return PlaylistSyncResult.empty(message: '账号状态已变化');
      }
      if (!result.ok) {
        final data = result.data;
        return PlaylistSyncResult.empty(
          message: data is Map
              ? (data['message']?.toString() ?? '同步失败')
              : '同步失败',
        );
      }
      _invalidateLoadsForMutation(playlistId);
      final updated = _playlistFromResponse(result.data);
      if (updated == null) return PlaylistSyncResult.empty(message: '同步响应无效');
      await _refreshCurrentTracks(playlistId);
      if (!_isCurrentSession(session)) {
        return PlaylistSyncResult.empty(message: '账号状态已变化');
      }
      notifyListeners();
      return PlaylistSyncResult.success(updated);
    } catch (error) {
      StructuredLogService.log('[PlaylistService] 同步失败: $error');
      return PlaylistSyncResult.empty(message: '同步失败，请稍后重试');
    }
  }

  bool isTrackInPlaylist(int playlistId, Track track) {
    return (_tracksByPlaylist[playlistId] ?? const <PlaylistTrack>[]).any(
      (item) =>
          item.trackId == track.id.toString() && item.source == track.source,
    );
  }

  Future<TrackInPlaylistResult> isTrackInAnyPlaylist(Track track) async {
    final session = _sessionIdentity();
    if (session == null) {
      return const TrackInPlaylistResult(known: true, matches: []);
    }
    try {
      final result = await ApiClient().getJson(
        '/playlists/check-track',
        queryParameters: {
          'trackId': track.id.toString(),
          'source': track.source.name,
        },
        timeout: const Duration(seconds: 10),
      );
      final data = result.data;
      if (!result.ok ||
          data is! Map<String, dynamic> ||
          !_isCurrentSession(session)) {
        return const TrackInPlaylistResult(known: false, matches: []);
      }
      final matches = (data['matches'] as List<dynamic>? ?? const [])
          .map(
            (item) => PlaylistTrackMatch.fromJson(item as Map<String, dynamic>),
          )
          .toList();
      return TrackInPlaylistResult(known: true, matches: matches);
    } catch (error) {
      StructuredLogService.log('[PlaylistService] 查询收藏状态失败: $error');
      return const TrackInPlaylistResult(known: false, matches: []);
    }
  }

  bool isFavorite(Track? track) {
    if (track == null || defaultPlaylist == null) return false;
    return isTrackInPlaylist(defaultPlaylist!.id, track);
  }

  Future<void> toggleFavorite(Track? track) async {
    final favorite = defaultPlaylist;
    if (track == null || favorite == null) return;
    final result = await isTrackInAnyPlaylist(track);
    if (!result.known) return;
    final itemId = result.itemIdFor(favorite.id);
    if (itemId == null) {
      await addTrackToPlaylist(favorite.id, track);
      return;
    }
    final current = PlaylistTrack.fromTrack(track);
    await removePlaylistTrack(
      favorite.id,
      PlaylistTrack(
        itemId: itemId,
        trackId: current.trackId,
        name: current.name,
        artists: current.artists,
        album: current.album,
        picUrl: current.picUrl,
        source: current.source,
        sourceIds: current.sourceIds,
        addedAt: current.addedAt,
      ),
    );
  }
}
