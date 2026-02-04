import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/navidrome_models.dart';

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

  Future<bool> ping() async {
    final response = await _get('ping');
    return (response['status'] as String?) == 'ok';
  }

  Future<List<NavidromeAlbum>> getAlbumList({int size = 200}) async {
    final response = await _get('getAlbumList2', {
      'type': 'alphabeticalByName',
      'size': size.toString(),
    });
    final payload = response['albumList2'] as Map<String, dynamic>?;
    final albums = _asList(payload?['album']);
    return albums
        .map((e) => NavidromeAlbum.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<List<NavidromeSong>> getAlbumSongs(String albumId) async {
    final response = await _get('getAlbum', {'id': albumId});
    final album = response['album'] as Map<String, dynamic>?;
    final songs = _asList(album?['song']);
    return songs
        .map((e) => NavidromeSong.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<List<NavidromePlaylist>> getPlaylists() async {
    final response = await _get('getPlaylists');
    final payload = response['playlists'] as Map<String, dynamic>?;
    final playlists = _asList(payload?['playlist']);
    return playlists
        .map((e) => NavidromePlaylist.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<List<NavidromeSong>> getPlaylistSongs(String playlistId) async {
    final response = await _get('getPlaylist', {'id': playlistId});
    final playlist = response['playlist'] as Map<String, dynamic>?;
    final entries = _asList(playlist?['entry']);
    return entries
        .map((e) => NavidromeSong.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<NavidromeSearchResult> search3(String query) async {
    final response = await _get('search3', {'query': query});
    final result = response['searchResult3'] as Map<String, dynamic>?;
    final songs = _asList(result?['song'])
        .map((e) => NavidromeSong.fromJson(e as Map<String, dynamic>))
        .toList();
    return NavidromeSearchResult(songs: songs);
  }

  String buildStreamUrl(String id, {int? maxBitRate}) {
    final params = _baseParams();
    params['id'] = id;
    if (maxBitRate != null) {
      params['maxBitRate'] = maxBitRate.toString();
    }
    return _buildUri('getStream', params).toString();
  }

  String buildCoverUrl(String coverId, {int size = 300}) {
    if (coverId.isEmpty) return '';
    final params = _baseParams();
    params['id'] = coverId;
    params['size'] = size.toString();
    return _buildUri('getCoverArt', params).toString();
  }

  Future<Map<String, dynamic>> _get(String method,
      [Map<String, String>? extraParams]) async {
    final params = _baseParams();
    if (extraParams != null) {
      params.addAll(extraParams);
    }
    final uri = _buildUri(method, params);
    final response = await _client.get(uri);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception('HTTP ${response.statusCode}');
    }
    final jsonBody = jsonDecode(response.body) as Map<String, dynamic>;
    final wrapper = jsonBody['subsonic-response'] as Map<String, dynamic>?;
    if (wrapper == null) {
      throw Exception('Invalid response');
    }
    if ((wrapper['status'] as String?) != 'ok') {
      final message = wrapper['error']?['message']?.toString() ?? 'Unknown error';
      throw Exception(message);
    }
    return wrapper;
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
