import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import '../models/playlist.dart';
import 'playlist_service.dart';
import 'api/api_client.dart';

enum MusicTasteMode {
  professional,
  tieba,
}

extension MusicTasteModeApiValue on MusicTasteMode {
  String get apiValue {
    switch (this) {
      case MusicTasteMode.professional:
        return 'professional';
      case MusicTasteMode.tieba:
        return 'tieba';
    }
  }

  String get displayName {
    switch (this) {
      case MusicTasteMode.professional:
        return '专业分析';
      case MusicTasteMode.tieba:
        return '业余分析';
    }
  }
}

/// 听歌品味总结服务
/// 获取用户歌单中的歌曲，通过后端 API 调用大模型生成品味总结
class MusicTasteService extends ChangeNotifier {
  static final MusicTasteService _instance = MusicTasteService._internal();
  factory MusicTasteService() => _instance;
  MusicTasteService._internal();

  // 状态
  bool _isLoading = false;
  bool get isLoading => _isLoading;

  String _result = '';
  String get result => _result;

  String _error = '';
  String get error => _error;

  bool _isStreaming = false;
  bool get isStreaming => _isStreaming;

  /// 重置状态
  void reset() {
    _isLoading = false;
    _result = '';
    _error = '';
    _isStreaming = false;
    notifyListeners();
  }

  /// 从选中的歌单获取歌曲列表
  Future<List<PlaylistTrack>> getTracksFromPlaylists(List<Playlist> playlists) async {
    final List<PlaylistTrack> allTracks = [];
    final playlistService = PlaylistService();

    for (final playlist in playlists) {
      await playlistService.loadPlaylistTracks(playlist.id);
      final tracks = playlistService.currentTracks;
      allTracks.addAll(tracks);
    }

    return allTracks;
  }

  /// 将歌曲列表转换为后端 API 需要的格式
  List<Map<String, String>> _tracksToApiFormat(List<PlaylistTrack> tracks) {
    return tracks.map((track) => {
      'name': track.name,
      'artists': track.artists,
      'album': track.album,
    }).toList();
  }

  /// 生成品味总结（流式输出）
  Future<void> generateTasteSummary(
    List<Playlist> playlists, {
    MusicTasteMode mode = MusicTasteMode.professional,
  }) async {
    if (playlists.isEmpty) {
      _error = '请至少选择一个歌单';
      notifyListeners();
      return;
    }

    _isLoading = true;
    _result = '';
    _error = '';
    _isStreaming = true;
    notifyListeners();

    try {
      // 获取所有歌曲
      final tracks = await getTracksFromPlaylists(playlists);

      if (tracks.isEmpty) {
        _error = '选中的歌单中没有歌曲';
        _isLoading = false;
        _isStreaming = false;
        notifyListeners();
        return;
      }

      // 调用后端 API（流式）
      await _callStreamingApi(tracks, mode: mode);

    } catch (e) {
      _error = '生成失败: $e';
      _isLoading = false;
      _isStreaming = false;
      notifyListeners();
    }
  }

  /// 调用后端流式 API
  Future<void> _callStreamingApi(
    List<PlaylistTrack> tracks, {
    required MusicTasteMode mode,
  }) async {
    try {
      final response = await ApiClient().requestStream(
        '/music-taste/generate',
        method: 'POST',
        data: {
          'tracks': _tracksToApiFormat(tracks),
          'mode': mode.apiValue,
        },
        contentType: 'application/json',
      );

      if (response.statusCode != 200) {
        throw Exception('API 请求失败: ${response.statusCode}');
      }

      // 处理流式响应
      await for (final chunk in utf8.decoder.bind(response.data!.stream)) {
        // SSE 格式：每行以 "data: " 开头
        final lines = chunk.split('\n');
        for (final line in lines) {
          if (line.startsWith('data: ')) {
            final data = line.substring(6).trim();
            if (data == '[DONE]') {
              _isStreaming = false;
              _isLoading = false;
              notifyListeners();
              break;
            }

            try {
              final jsonData = json.decode(data) as Map<String, dynamic>;
              final choices = jsonData['choices'] as List<dynamic>?;
              if (choices != null && choices.isNotEmpty) {
                final delta = choices[0]['delta'] as Map<String, dynamic>?;
                if (delta != null) {
                  final content = delta['content'] as String?;
                  if (content != null) {
                    _result += content;
                    notifyListeners();
                  }
                }
              }
            } catch (e) {
              // 忽略解析错误，继续处理下一行
            }
          }
        }
      }

      _isStreaming = false;
      _isLoading = false;
      notifyListeners();

    } catch (e) {
      _error = '请求失败: $e';
      _isLoading = false;
      _isStreaming = false;
      notifyListeners();
      rethrow;
    }
  }

  /// 生成品味总结（非流式，备用）
  Future<String> generateTasteSummarySync(
    List<Playlist> playlists, {
    MusicTasteMode mode = MusicTasteMode.professional,
  }) async {
    if (playlists.isEmpty) {
      throw Exception('请至少选择一个歌单');
    }

    // 获取所有歌曲
    final tracks = await getTracksFromPlaylists(playlists);

    if (tracks.isEmpty) {
      throw Exception('选中的歌单中没有歌曲');
    }

    // 调用后端 API
    final result = await ApiClient().postJson(
      '/music-taste/generate-sync',
      data: {
        'tracks': _tracksToApiFormat(tracks),
        'mode': mode.apiValue,
      },
      timeout: const Duration(minutes: 2),
    );

    if (!result.ok) {
      throw Exception('API 请求失败: ${result.statusCode}');
    }

    final data = result.data as Map<String, dynamic>?;

    if (data == null || data['code'] != 200) {
      throw Exception(data?['message'] ?? 'API 请求失败');
    }

    final content = data['data']?['content'] as String?;

    if (content == null) {
      throw Exception('API 返回内容为空');
    }

    return content;
  }
}
