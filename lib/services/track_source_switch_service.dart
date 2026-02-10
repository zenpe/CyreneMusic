import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../models/track.dart';
import '../models/playlist.dart';
import 'url_service.dart';

/// 换源搜索结果
class SourceSwitchResult {
  final PlaylistTrack originalTrack;
  final List<Track> searchResults;
  final Track? selectedTrack;
  final bool isProcessing;
  final String? error;

  SourceSwitchResult({
    required this.originalTrack,
    this.searchResults = const [],
    this.selectedTrack,
    this.isProcessing = false,
    this.error,
  });

  SourceSwitchResult copyWith({
    PlaylistTrack? originalTrack,
    List<Track>? searchResults,
    Track? selectedTrack,
    bool? isProcessing,
    String? error,
  }) {
    return SourceSwitchResult(
      originalTrack: originalTrack ?? this.originalTrack,
      searchResults: searchResults ?? this.searchResults,
      selectedTrack: selectedTrack,
      isProcessing: isProcessing ?? this.isProcessing,
      error: error,
    );
  }
}

/// 换源进度
class SourceSwitchProgress {
  final int current;
  final int total;
  final String currentTrackName;

  SourceSwitchProgress({
    required this.current,
    required this.total,
    required this.currentTrackName,
  });

  double get percentage => total > 0 ? current / total : 0;
}

/// 歌单换源服务
class TrackSourceSwitchService extends ChangeNotifier {
  static final TrackSourceSwitchService _instance = TrackSourceSwitchService._internal();
  factory TrackSourceSwitchService() => _instance;
  TrackSourceSwitchService._internal();

  // 换源结果列表
  List<SourceSwitchResult> _results = [];
  List<SourceSwitchResult> get results => _results;

  // 处理进度
  SourceSwitchProgress? _progress;
  SourceSwitchProgress? get progress => _progress;

  // 是否正在处理
  bool _isProcessing = false;
  bool get isProcessing => _isProcessing;

  // 是否已取消
  bool _isCancelled = false;

  /// 开始换源处理
  /// [tracks] 需要换源的歌曲列表
  /// [targetSource] 目标平台
  Future<void> startSourceSwitch(
    List<PlaylistTrack> tracks,
    MusicSource targetSource,
  ) async {
    if (_isProcessing) return;

    _isProcessing = true;
    _isCancelled = false;
    _results = tracks.map((t) => SourceSwitchResult(
      originalTrack: t,
      isProcessing: true,
    )).toList();
    notifyListeners();

    for (int i = 0; i < tracks.length; i++) {
      if (_isCancelled) break;

      final track = tracks[i];
      _progress = SourceSwitchProgress(
        current: i + 1,
        total: tracks.length,
        currentTrackName: track.name,
      );
      notifyListeners();

      try {
        final searchResults = await _searchTrack(track, targetSource);
        
        _results[i] = SourceSwitchResult(
          originalTrack: track,
          searchResults: searchResults,
          selectedTrack: searchResults.isNotEmpty ? searchResults.first : null,
          isProcessing: false,
        );
      } catch (e) {
        _results[i] = SourceSwitchResult(
          originalTrack: track,
          searchResults: [],
          isProcessing: false,
          error: e.toString(),
        );
      }
      notifyListeners();
    }

    _isProcessing = false;
    _progress = null;
    notifyListeners();
  }

  /// 取消处理
  void cancel() {
    _isCancelled = true;
  }

  /// 清空结果
  void clear() {
    _results = [];
    _progress = null;
    _isProcessing = false;
    _isCancelled = false;
    notifyListeners();
  }

  /// 更新选中的歌曲
  void updateSelectedTrack(int index, Track? track) {
    if (index < 0 || index >= _results.length) return;
    
    _results[index] = _results[index].copyWith(
      selectedTrack: track,
    );
    notifyListeners();
  }

  /// 获取所有选中的换源结果
  List<MapEntry<PlaylistTrack, Track>> getSelectedResults() {
    return _results
        .where((r) => r.selectedTrack != null)
        .map((r) => MapEntry(r.originalTrack, r.selectedTrack!))
        .toList();
  }

  /// 搜索单首歌曲
  Future<List<Track>> _searchTrack(PlaylistTrack track, MusicSource targetSource) async {
    final keyword = '${track.name} ${track.artists}';
    final baseUrl = UrlService().baseUrl;
    
    try {
      switch (targetSource) {
        case MusicSource.netease:
          return await _searchNetease(keyword, baseUrl);
        case MusicSource.apple:
          return await _searchApple(keyword, baseUrl);
        case MusicSource.qq:
          return await _searchQQ(keyword, baseUrl);
        case MusicSource.kugou:
          return await _searchKugou(keyword, baseUrl);
        case MusicSource.kuwo:
          return await _searchKuwo(keyword, baseUrl);
        case MusicSource.navidrome:
          return [];
        case MusicSource.spotify:
          return await _searchSpotify(keyword, baseUrl);
        case MusicSource.local:
          return [];
      }
    } catch (e) {
      print('❌ [TrackSourceSwitchService] 搜索失败: $e');
      rethrow;
    }
  }

  /// 搜索 Apple Music
  Future<List<Track>> _searchApple(String keyword, String baseUrl) async {
    final url =
        '$baseUrl/apple/search?keywords=${Uri.encodeComponent(keyword)}&limit=1';
    final response = await http.get(
      Uri.parse(url),
      headers: {'Content-Type': 'application/json'},
    ).timeout(const Duration(seconds: 10));

    if (response.statusCode == 200) {
      final data =
          json.decode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
      if (data['status'] == 200) {
        return (data['result'] as List<dynamic>)
            .take(1)
            .map((item) => Track(
                  id: item['id'],
                  name: item['name'] as String,
                  artists: item['artists'] as String,
                  album: item['album'] as String,
                  picUrl: item['picUrl'] as String,
                  source: MusicSource.apple,
                ))
            .toList();
      }
    }
    throw Exception('Apple Music 搜索失败');
  }

  /// 搜索网易云音乐
  Future<List<Track>> _searchNetease(String keyword, String baseUrl) async {
    final url = '$baseUrl/search';
    final response = await http.post(
      Uri.parse(url),
      headers: {'Content-Type': 'application/x-www-form-urlencoded'},
      body: {'keywords': keyword, 'limit': '1'},
    ).timeout(const Duration(seconds: 10));

    if (response.statusCode == 200) {
      final data = json.decode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
      if (data['status'] == 200) {
        return (data['result'] as List<dynamic>)
            .map((item) => Track(
                  id: item['id'] as int,
                  name: item['name'] as String,
                  artists: item['artists'] as String,
                  album: item['album'] as String,
                  picUrl: item['picUrl'] as String,
                  source: MusicSource.netease,
                ))
            .toList();
      }
    }
    throw Exception('网易云搜索失败');
  }

  /// 搜索QQ音乐
  Future<List<Track>> _searchQQ(String keyword, String baseUrl) async {
    final url = '$baseUrl/qq/search?keywords=${Uri.encodeComponent(keyword)}&limit=1';
    final response = await http.get(
      Uri.parse(url),
      headers: {'Content-Type': 'application/json'},
    ).timeout(const Duration(seconds: 10));

    if (response.statusCode == 200) {
      final data = json.decode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
      if (data['status'] == 200) {
        return (data['result'] as List<dynamic>)
            .map((item) => Track(
                  id: item['mid'] as String,
                  name: item['name'] as String,
                  artists: item['singer'] as String,
                  album: item['album'] as String,
                  picUrl: item['pic'] as String,
                  source: MusicSource.qq,
                ))
            .toList();
      }
    }
    throw Exception('QQ音乐搜索失败');
  }

  /// 搜索酷狗音乐
  Future<List<Track>> _searchKugou(String keyword, String baseUrl) async {
    final url = '$baseUrl/kugou/search?keywords=${Uri.encodeComponent(keyword)}';
    final response = await http.get(
      Uri.parse(url),
      headers: {'Content-Type': 'application/json'},
    ).timeout(const Duration(seconds: 10));

    if (response.statusCode == 200) {
      final data = json.decode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
      if (data['status'] == 200) {
        return (data['result'] as List<dynamic>)
            .take(1)
            .map((item) => Track(
                  id: item['emixsongid'] as String,
                  name: item['name'] as String,
                  artists: item['singer'] as String,
                  album: item['album'] as String,
                  picUrl: item['pic'] as String,
                  source: MusicSource.kugou,
                ))
            .toList();
      }
    }
    throw Exception('酷狗音乐搜索失败');
  }

  /// 搜索酷我音乐
  Future<List<Track>> _searchKuwo(String keyword, String baseUrl) async {
    final url = '$baseUrl/kuwo/search?keywords=${Uri.encodeComponent(keyword)}';
    final response = await http.get(
      Uri.parse(url),
      headers: {'Content-Type': 'application/json'},
    ).timeout(const Duration(seconds: 10));

    if (response.statusCode == 200) {
      final data = json.decode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
      if (data['status'] == 200) {
        final songsData = data['data']?['songs'] as List<dynamic>? ?? [];
        return songsData
            .take(1)
            .map((item) => Track(
                  id: item['rid'] as int,
                  name: item['name'] as String,
                  artists: item['artist'] as String,
                  album: item['album'] as String? ?? '',
                  picUrl: item['pic'] as String? ?? '',
                  source: MusicSource.kuwo,
                ))
            .toList();
      }
    }
    throw Exception('酷我音乐搜索失败');
  }

  /// 搜索 Spotify
  Future<List<Track>> _searchSpotify(String keyword, String baseUrl) async {
    final url = '$baseUrl/spotify/search?keywords=${Uri.encodeComponent(keyword)}&limit=1&type=track';
    
    final response = await http.get(
      Uri.parse(url),
      headers: {'Content-Type': 'application/json'},
    ).timeout(const Duration(seconds: 10));

    if (response.statusCode == 200) {
      final data = json.decode(utf8.decode(response.bodyBytes));
      // 兼容直接返回或 {status, data} 包装
      dynamic tracksData;
      if (data['tracks'] != null) {
        tracksData = data['tracks'];
      } else if (data['data'] != null && data['data']['tracks'] != null) {
        tracksData = data['data']['tracks'];
      }

      if (tracksData != null && tracksData['items'] != null) {
        final items = tracksData['items'] as List<dynamic>;
        return items.take(1).map((item) {
          final album = item['album'];
          final artists = (item['artists'] as List<dynamic>)
              .map((a) => a['name'] as String)
              .join(',');
          final images = album['images'] as List<dynamic>;
          final picUrl = images.isNotEmpty ? images[0]['url'] as String : '';
          
          return Track(
            id: item['id'],
            name: item['name'] as String,
            artists: artists,
            album: album['name'] as String,
            picUrl: picUrl,
            source: MusicSource.spotify,
          );
        }).toList();
      }
    }
    throw Exception('Spotify 搜索失败');
  }
}
