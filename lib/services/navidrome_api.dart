import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../models/navidrome_models.dart';

/// Navidrome/Subsonic API 客户端
///
/// 实现 Subsonic API 规范: http://www.subsonic.org/pages/api.jsp
class NavidromeApi {
  NavidromeApi({
    required this.baseUrl,
    required this.username,
    required this.password,
    http.Client? client,
  }) : _client = client ?? http.Client();

  final String baseUrl;
  final String username;
  final String password;
  final http.Client _client;

  static const String _apiVersion = '1.16.1';
  static const String _clientName = 'CyreneMusic';

  // ==================== 系统 API ====================

  /// 测试连接
  Future<bool> ping() async {
    final response = await _get('ping');
    return (response['status'] as String?) == 'ok';
  }

  // ==================== 专辑 API ====================

  /// 获取专辑列表
  Future<List<NavidromeAlbum>> getAlbumList({
    AlbumListType type = AlbumListType.alphabeticalByName,
    int size = 200,
    int offset = 0,
    int? fromYear,
    int? toYear,
    String? genre,
  }) async {
    final params = <String, String>{
      'type': type.value,
      'size': size.toString(),
      'offset': offset.toString(),
    };
    if (fromYear != null) params['fromYear'] = fromYear.toString();
    if (toYear != null) params['toYear'] = toYear.toString();
    if (genre != null) params['genre'] = genre;

    final response = await _get('getAlbumList2', params);
    final payload = response['albumList2'] as Map<String, dynamic>?;
    final albums = _asList(payload?['album']);
    return albums
        .map((e) => NavidromeAlbum.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// 获取专辑详情（包含歌曲列表）
  Future<List<NavidromeSong>> getAlbumSongs(String albumId) async {
    final response = await _get('getAlbum', {'id': albumId});
    final album = response['album'] as Map<String, dynamic>?;
    final songs = _asList(album?['song']);
    return songs
        .map((e) => NavidromeSong.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  // ==================== 艺术家 API ====================

  /// 获取所有艺术家（按字母索引分组）
  Future<List<NavidromeArtist>> getArtists() async {
    final response = await _get('getArtists');
    final artists = response['artists'] as Map<String, dynamic>?;
    final indexes = _asList(artists?['index']);

    final result = <NavidromeArtist>[];
    for (final index in indexes) {
      final artistList = _asList((index as Map<String, dynamic>)['artist']);
      for (final artist in artistList) {
        result.add(NavidromeArtist.fromJson(artist as Map<String, dynamic>));
      }
    }
    return result;
  }

  /// 获取艺术家详情（包含专辑列表）
  Future<NavidromeArtistInfo> getArtist(String artistId) async {
    final response = await _get('getArtist', {'id': artistId});
    final data = response['artist'] as Map<String, dynamic>?;

    if (data == null) {
      throw Exception('Artist not found');
    }

    final artist = NavidromeArtist.fromJson(data);
    final albumList = _asList(data['album']);
    final albums = albumList
        .map((e) => NavidromeAlbum.fromJson(e as Map<String, dynamic>))
        .toList();

    return NavidromeArtistInfo(
      artist: artist,
      albums: albums,
    );
  }

  // ==================== 歌单 API ====================

  /// 获取所有歌单
  Future<List<NavidromePlaylist>> getPlaylists() async {
    final response = await _get('getPlaylists');
    final payload = response['playlists'] as Map<String, dynamic>?;
    final playlists = _asList(payload?['playlist']);
    return playlists
        .map((e) => NavidromePlaylist.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// 获取歌单详情（包含歌曲列表）
  Future<List<NavidromeSong>> getPlaylistSongs(String playlistId) async {
    final response = await _get('getPlaylist', {'id': playlistId});
    final playlist = response['playlist'] as Map<String, dynamic>?;
    final entries = _asList(playlist?['entry']);
    return entries
        .map((e) => NavidromeSong.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// 创建歌单
  Future<NavidromePlaylist> createPlaylist({
    required String name,
    List<String>? songIds,
  }) async {
    final params = <String, String>{'name': name};
    if (songIds != null && songIds.isNotEmpty) {
      // Subsonic API 使用重复参数来传递多个 songId
      // 这里我们需要特殊处理
    }

    final response = await _get('createPlaylist', params);
    final playlist = response['playlist'] as Map<String, dynamic>?;
    if (playlist == null) {
      throw Exception('Failed to create playlist');
    }
    return NavidromePlaylist.fromJson(playlist);
  }

  /// 更新歌单
  Future<void> updatePlaylist({
    required String playlistId,
    String? name,
    String? comment,
    bool? public,
    List<String>? songIdsToAdd,
    List<int>? songIndexesToRemove,
  }) async {
    final params = <String, String>{'playlistId': playlistId};
    if (name != null) params['name'] = name;
    if (comment != null) params['comment'] = comment;
    if (public != null) params['public'] = public.toString();

    await _get('updatePlaylist', params);
  }

  /// 删除歌单
  Future<void> deletePlaylist(String playlistId) async {
    await _get('deletePlaylist', {'id': playlistId});
  }

  // ==================== 网络电台 API ====================

  /// 获取网络电台列表
  Future<List<NavidromeRadioStation>> getInternetRadioStations() async {
    final response = await _get('getInternetRadioStations');
    final payload = response['internetRadioStations'] as Map<String, dynamic>?;
    final stations = _asList(payload?['internetRadioStation']);
    return stations
        .map((e) => NavidromeRadioStation.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// 创建网络电台
  Future<void> createInternetRadioStation({
    required String name,
    required String streamUrl,
    String? homePageUrl,
  }) async {
    final params = <String, String>{
      'name': name,
      'streamUrl': streamUrl,
    };
    if (homePageUrl != null) params['homePageUrl'] = homePageUrl;

    await _get('createInternetRadioStation', params);
  }

  /// 更新网络电台
  Future<void> updateInternetRadioStation({
    required String id,
    required String name,
    required String streamUrl,
    String? homePageUrl,
  }) async {
    final params = <String, String>{
      'id': id,
      'name': name,
      'streamUrl': streamUrl,
    };
    if (homePageUrl != null) params['homePageUrl'] = homePageUrl;

    await _get('updateInternetRadioStation', params);
  }

  /// 删除网络电台
  Future<void> deleteInternetRadioStation(String id) async {
    await _get('deleteInternetRadioStation', {'id': id});
  }

  // ==================== 搜索 API ====================

  /// 搜索（返回艺术家、专辑、歌曲）
  Future<NavidromeSearchResult> search3(
    String query, {
    int artistCount = 20,
    int artistOffset = 0,
    int albumCount = 20,
    int albumOffset = 0,
    int songCount = 20,
    int songOffset = 0,
  }) async {
    final response = await _get('search3', {
      'query': query,
      'artistCount': artistCount.toString(),
      'artistOffset': artistOffset.toString(),
      'albumCount': albumCount.toString(),
      'albumOffset': albumOffset.toString(),
      'songCount': songCount.toString(),
      'songOffset': songOffset.toString(),
    });

    final result = response['searchResult3'] as Map<String, dynamic>?;

    final artists = _asList(result?['artist'])
        .map((e) => NavidromeArtist.fromJson(e as Map<String, dynamic>))
        .toList();

    final albums = _asList(result?['album'])
        .map((e) => NavidromeAlbum.fromJson(e as Map<String, dynamic>))
        .toList();

    final songs = _asList(result?['song'])
        .map((e) => NavidromeSong.fromJson(e as Map<String, dynamic>))
        .toList();

    return NavidromeSearchResult(
      artists: artists,
      albums: albums,
      songs: songs,
    );
  }

  // ==================== 歌曲 API ====================

  /// 获取热门歌曲
  Future<List<NavidromeSong>> getTopSongs({
    int count = 50,
    int offset = 0,
    String? musicFolderId,
  }) async {
    final params = <String, String>{
      'count': count.toString(),
      'offset': offset.toString(),
    };
    if (musicFolderId != null) params['musicFolderId'] = musicFolderId;

    final response = await _get('getTopSongs', params);
    final payload = response['topSongs'] as Map<String, dynamic>?;
    final songs = _asList(payload?['song']);
    return songs
        .map((e) => NavidromeSong.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  // ==================== 收藏 API ====================

  /// 添加收藏
  Future<void> star({
    String? id,
    String? albumId,
    String? artistId,
  }) async {
    final params = <String, String>{};
    if (id != null) params['id'] = id;
    if (albumId != null) params['albumId'] = albumId;
    if (artistId != null) params['artistId'] = artistId;

    if (params.isEmpty) {
      throw ArgumentError('At least one of id, albumId, or artistId is required');
    }

    await _get('star', params);
  }

  /// 取消收藏
  Future<void> unstar({
    String? id,
    String? albumId,
    String? artistId,
  }) async {
    final params = <String, String>{};
    if (id != null) params['id'] = id;
    if (albumId != null) params['albumId'] = albumId;
    if (artistId != null) params['artistId'] = artistId;

    if (params.isEmpty) {
      throw ArgumentError('At least one of id, albumId, or artistId is required');
    }

    await _get('unstar', params);
  }

  /// 获取收藏列表
  Future<({List<NavidromeArtist> artists, List<NavidromeAlbum> albums, List<NavidromeSong> songs})> getStarred() async {
    final response = await _get('getStarred2');
    final starred = response['starred2'] as Map<String, dynamic>?;

    final artists = _asList(starred?['artist'])
        .map((e) => NavidromeArtist.fromJson(e as Map<String, dynamic>))
        .toList();

    final albums = _asList(starred?['album'])
        .map((e) => NavidromeAlbum.fromJson(e as Map<String, dynamic>))
        .toList();

    final songs = _asList(starred?['song'])
        .map((e) => NavidromeSong.fromJson(e as Map<String, dynamic>))
        .toList();

    return (artists: artists, albums: albums, songs: songs);
  }

  // ==================== 流派 API ====================

  /// 获取所有流派
  Future<List<NavidromeGenre>> getGenres() async {
    final response = await _get('getGenres');
    final genres = response['genres'] as Map<String, dynamic>?;
    final genreList = _asList(genres?['genre']);
    return genreList
        .map((e) => NavidromeGenre.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// 按流派获取歌曲
  Future<List<NavidromeSong>> getSongsByGenre(
    String genre, {
    int count = 100,
    int offset = 0,
  }) async {
    final response = await _get('getSongsByGenre', {
      'genre': genre,
      'count': count.toString(),
      'offset': offset.toString(),
    });
    final songs = _asList(response['songsByGenre']?['song']);
    return songs
        .map((e) => NavidromeSong.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  // ==================== 随机歌曲 API ====================

  /// 获取随机歌曲
  Future<List<NavidromeSong>> getRandomSongs({
    int size = 50,
    String? genre,
    int? fromYear,
    int? toYear,
  }) async {
    final params = <String, String>{'size': size.toString()};
    if (genre != null) params['genre'] = genre;
    if (fromYear != null) params['fromYear'] = fromYear.toString();
    if (toYear != null) params['toYear'] = toYear.toString();

    final response = await _get('getRandomSongs', params);
    final songs = _asList(response['randomSongs']?['song']);
    return songs
        .map((e) => NavidromeSong.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  // ==================== 播放统计 API ====================

  /// 记录播放（scrobble）
  Future<void> scrobble(String id, {bool? submission}) async {
    final params = <String, String>{'id': id};
    if (submission != null) params['submission'] = submission.toString();
    await _get('scrobble', params);
  }

  // ==================== 媒体 URL ====================

  /// 构建流媒体 URL
  String buildStreamUrl(String id, {int? maxBitRate, String? format}) {
    final params = _baseParams();
    params['id'] = id;
    if (maxBitRate != null) {
      params['maxBitRate'] = maxBitRate.toString();
    }
    if (format != null) {
      params['format'] = format;
    }
    return _buildUri('stream', params).toString();
  }

  /// 构建封面图 URL
  String buildCoverUrl(String coverId, {int size = 300}) {
    if (coverId.isEmpty) return '';
    final params = _baseParams();
    params['id'] = coverId;
    params['size'] = size.toString();
    return _buildUri('getCoverArt', params).toString();
  }

  // ==================== 内部方法 ====================

  Future<Map<String, dynamic>> _get(String method,
      [Map<String, String>? extraParams]) async {
    final params = _baseParams();
    if (extraParams != null) {
      params.addAll(extraParams);
    }
    final uri = _buildUri(method, params);

    try {
      final response = await _client.get(uri);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw NavidromeApiException(
          'HTTP ${response.statusCode}',
          statusCode: response.statusCode,
        );
      }

      final jsonBody = jsonDecode(response.body) as Map<String, dynamic>;
      final wrapper = jsonBody['subsonic-response'] as Map<String, dynamic>?;
      if (wrapper == null) {
        throw NavidromeApiException('Invalid response format');
      }

      if ((wrapper['status'] as String?) != 'ok') {
        final error = wrapper['error'] as Map<String, dynamic>?;
        final code = error?['code'] as int?;
        final message = error?['message']?.toString() ?? 'Unknown error';
        throw NavidromeApiException(message, code: code);
      }

      return wrapper;
    } catch (e) {
      if (e is NavidromeApiException) rethrow;
      debugPrint('[NavidromeApi] Request failed: $e');
      throw NavidromeApiException('Network error: $e');
    }
  }

  Map<String, String> _baseParams() {
    return {
      'u': username,
      'p': _encodePassword(password),
      'v': _apiVersion,
      'c': _clientName,
      'f': 'json',
    };
  }

  Uri _buildUri(String method, Map<String, String> params) {
    final base = baseUrl.endsWith('/') ? baseUrl.substring(0, baseUrl.length - 1) : baseUrl;
    return Uri.parse('$base/rest/$method').replace(queryParameters: params);
  }

  String _encodePassword(String raw) {
    final bytes = utf8.encode(raw);
    final buffer = StringBuffer('enc:');
    for (final b in bytes) {
      buffer.write(b.toRadixString(16).padLeft(2, '0'));
    }
    return buffer.toString();
  }

  List<dynamic> _asList(dynamic value) {
    if (value == null) return const [];
    if (value is List) return value;
    return [value];
  }
}

/// Navidrome API 异常
class NavidromeApiException implements Exception {
  final String message;
  final int? code;
  final int? statusCode;

  NavidromeApiException(this.message, {this.code, this.statusCode});

  @override
  String toString() {
    final parts = <String>['NavidromeApiException: $message'];
    if (code != null) parts.add('(code: $code)');
    if (statusCode != null) parts.add('(HTTP $statusCode)');
    return parts.join(' ');
  }
}
