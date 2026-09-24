import 'structured_log_service.dart';
import 'package:flutter/foundation.dart';
import 'package:dio/dio.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/track.dart';
import '../models/merged_track.dart';
import 'api/api_client.dart';
import 'search_provider_catalog.dart';

/// 搜索结果模型
class SearchResult {
  final List<Track> neteaseResults;
  final List<Track> appleResults;
  final List<Track> qqResults;
  final List<Track> kugouResults;
  final List<Track> kuwoResults;
  final List<Track> spotifyResults;
  final bool neteaseLoading;
  final bool appleLoading;
  final bool qqLoading;
  final bool kugouLoading;
  final bool kuwoLoading;
  final bool spotifyLoading;
  final String? neteaseError;
  final String? appleError;
  final String? qqError;
  final String? kugouError;
  final String? kuwoError;
  final String? spotifyError;

  SearchResult({
    this.neteaseResults = const [],
    this.appleResults = const [],
    this.qqResults = const [],
    this.kugouResults = const [],
    this.kuwoResults = const [],
    this.spotifyResults = const [],
    this.neteaseLoading = false,
    this.appleLoading = false,
    this.qqLoading = false,
    this.kugouLoading = false,
    this.kuwoLoading = false,
    this.spotifyLoading = false,
    this.neteaseError,
    this.appleError,
    this.qqError,
    this.kugouError,
    this.kuwoError,
    this.spotifyError,
  });

  /// 获取所有结果的总数
  int get totalCount => neteaseResults.length + appleResults.length + qqResults.length + kugouResults.length + kuwoResults.length + spotifyResults.length;

  /// 是否所有平加载完成
  bool get allCompleted => !neteaseLoading && !appleLoading && !qqLoading && !kugouLoading && !kuwoLoading && !spotifyLoading;

  /// 是否有任何错误
  bool get hasError => neteaseError != null || appleError != null || qqError != null || kugouError != null || kuwoError != null || spotifyError != null;

  /// 复制并修改部分字段
  SearchResult copyWith({
    List<Track>? neteaseResults,
    List<Track>? appleResults,
    List<Track>? qqResults,
    List<Track>? kugouResults,
    List<Track>? kuwoResults,
    List<Track>? spotifyResults,
    bool? neteaseLoading,
    bool? appleLoading,
    bool? qqLoading,
    bool? kugouLoading,
    bool? kuwoLoading,
    bool? spotifyLoading,
    String? neteaseError,
    String? appleError,
    String? qqError,
    String? kugouError,
    String? kuwoError,
    String? spotifyError,
  }) {
    return SearchResult(
      neteaseResults: neteaseResults ?? this.neteaseResults,
      appleResults: appleResults ?? this.appleResults,
      qqResults: qqResults ?? this.qqResults,
      kugouResults: kugouResults ?? this.kugouResults,
      kuwoResults: kuwoResults ?? this.kuwoResults,
      spotifyResults: spotifyResults ?? this.spotifyResults,
      neteaseLoading: neteaseLoading ?? this.neteaseLoading,
      appleLoading: appleLoading ?? this.appleLoading,
      qqLoading: qqLoading ?? this.qqLoading,
      kugouLoading: kugouLoading ?? this.kugouLoading,
      kuwoLoading: kuwoLoading ?? this.kuwoLoading,
      spotifyLoading: spotifyLoading ?? this.spotifyLoading,
      neteaseError: neteaseError,
      appleError: appleError,
      qqError: qqError,
      kugouError: kugouError,
      kuwoError: kuwoError,
      spotifyError: spotifyError,
    );
  }
}

/// 搜索服务
class SearchService extends ChangeNotifier {
  static final SearchService _instance = SearchService._internal();
  factory SearchService() => _instance;
  SearchService._internal() {
    _loadSearchHistory();
  }

  SearchResult _searchResult = SearchResult();
  SearchResult get searchResult => _searchResult;

  String _currentKeyword = '';
  String get currentKeyword => _currentKeyword;
  int _activeSearchSession = 0;
  CancelToken? _activeSearchCancelToken;

  // 搜索历史记录
  List<String> _searchHistory = [];
  List<String> get searchHistory => _searchHistory;

  static const String _historyKey = 'search_history';
  static const int _maxHistoryCount = 20; // 最多保存20条历史记录
  static const SearchProviderCatalog _providerCatalog =
      SearchProviderCatalog();

  /// 搜索歌曲（根据后端搜索目录的平台并行搜索）。
  Future<void> search(String keyword, {bool saveHistory = true}) async {
    final normalizedKeyword = keyword.trim();
    if (normalizedKeyword.isEmpty) {
      return;
    }

    final sessionId = ++_activeSearchSession;
    _cancelActiveSearchRequests('新的搜索请求');
    final cancelToken = CancelToken();
    _activeSearchCancelToken = cancelToken;
    _currentKeyword = normalizedKeyword;

    // 保存到搜索历史
    if (saveHistory) {
      await _addToSearchHistory(normalizedKeyword);
      if (!_isSessionActive(sessionId, normalizedKeyword)) {
        StructuredLogService.log('⏭️ [SearchService] 忽略过期搜索（历史保存后）: $normalizedKeyword');
        return;
      }
    }

    // 搜索平台由后端搜索目录决定，与当前播放解析器解耦。
    final supportedPlatforms = _providerCatalog.platformKeys;
    StructuredLogService.log('🔍 [SearchService] 搜索平台: $supportedPlatforms');

    // 根据支持的平台设置加载状态
    _searchResult = SearchResult(
      neteaseLoading: supportedPlatforms.contains('netease'),
      appleLoading: supportedPlatforms.contains('apple'),
      qqLoading: supportedPlatforms.contains('qq'),
      kugouLoading: supportedPlatforms.contains('kugou'),
      kuwoLoading: supportedPlatforms.contains('kuwo'),
      spotifyLoading: supportedPlatforms.contains('spotify'),
    );
    notifyListeners();

    StructuredLogService.log('🔍 [SearchService] 开始搜索: $normalizedKeyword');

    // 只向支持的平台发送搜索请求
    final futures = <Future<void>>[];
    if (supportedPlatforms.contains('netease')) futures.add(_searchNetease(normalizedKeyword, sessionId, cancelToken));
    if (supportedPlatforms.contains('apple')) futures.add(_searchApple(normalizedKeyword, sessionId, cancelToken));
    if (supportedPlatforms.contains('qq')) futures.add(_searchQQ(normalizedKeyword, sessionId, cancelToken));
    if (supportedPlatforms.contains('kugou')) futures.add(_searchKugou(normalizedKeyword, sessionId, cancelToken));
    if (supportedPlatforms.contains('kuwo')) futures.add(_searchKuwo(normalizedKeyword, sessionId, cancelToken));
    if (supportedPlatforms.contains('spotify')) futures.add(_searchSpotify(normalizedKeyword, sessionId, cancelToken));

    await Future.wait(futures);

    if (!_isSessionActive(sessionId, normalizedKeyword)) {
      StructuredLogService.log('⏭️ [SearchService] 忽略过期搜索（全部返回后）: $normalizedKeyword');
      return;
    }

    if (identical(_activeSearchCancelToken, cancelToken)) {
      _activeSearchCancelToken = null;
    }

    StructuredLogService.log('✅ [SearchService] 搜索完成，共 ${_searchResult.totalCount} 条结果');
  }

  /// 获取后端搜索目录支持的平台列表。
  List<String> get currentSupportedPlatforms => _providerCatalog.platformKeys;

  /// 搜索网易云音乐
  Future<void> _searchNetease(String keyword, int sessionId, CancelToken cancelToken) async {
    try {
      StructuredLogService.log('🎵 [SearchService] 网易云搜索: $keyword');

      final result = await ApiClient().postJson(
        '/search',
        data: {'keywords': keyword, 'limit': '20'},
        contentType: 'application/x-www-form-urlencoded',
        timeout: const Duration(seconds: 10),
        cancelToken: cancelToken,
      );

      if (result.ok) {
        final data = result.data as Map<String, dynamic>;

        if (data['status'] == 200) {
          final results = (data['result'] as List<dynamic>)
              .map((item) => Track(
                    id: item['id'] as int,
                    name: item['name'] as String,
                    artists: item['artists'] as String,
                    album: item['album'] as String,
                    picUrl: item['picUrl'] as String,
                    source: MusicSource.netease,
                  ))
              .toList();

          if (!_isSessionActive(sessionId, keyword)) {
            StructuredLogService.log('⏭️ [SearchService] 丢弃过期网易云结果: $keyword');
            return;
          }

          _searchResult = _searchResult.copyWith(
            neteaseResults: results,
            neteaseLoading: false,
          );

          StructuredLogService.log('✅ [SearchService] 网易云搜索完成: ${results.length} 条结果');
        } else {
          throw Exception('服务器返回状态 ${data['status']}');
        }
      } else {
        throw Exception('HTTP ${result.statusCode}');
      }
    } catch (e) {
      StructuredLogService.log('❌ [SearchService] 网易云搜索失败: $e');
      if (!_isSessionActive(sessionId, keyword)) {
        StructuredLogService.log('⏭️ [SearchService] 丢弃过期网易云错误: $keyword');
        return;
      }
      _searchResult = _searchResult.copyWith(
        neteaseLoading: false,
        neteaseError: e.toString(),
      );
    }
    if (!_isSessionActive(sessionId, keyword)) {
      StructuredLogService.log('⏭️ [SearchService] 跳过过期网易云刷新: $keyword');
      return;
    }
    notifyListeners();
  }

  /// 搜索 Apple Music
  Future<void> _searchApple(String keyword, int sessionId, CancelToken cancelToken) async {
    try {
      StructuredLogService.log('🍎 [SearchService] Apple Music 搜索: $keyword');

      final result = await ApiClient().getJson(
        '/apple/search',
        queryParameters: {'keywords': keyword, 'limit': 20},
        timeout: const Duration(seconds: 10),
        cancelToken: cancelToken,
      );

      if (result.ok) {
        final data = result.data as Map<String, dynamic>;

        if (data['status'] == 200) {
          final results = (data['result'] as List<dynamic>)
              .map((item) => Track(
                    id: item['id'],
                    name: item['name'] as String,
                    artists: item['artists'] as String,
                    album: item['album'] as String,
                    picUrl: item['picUrl'] as String,
                    source: MusicSource.apple,
                  ))
              .toList();

          if (!_isSessionActive(sessionId, keyword)) {
            StructuredLogService.log('⏭️ [SearchService] 丢弃过期 Apple 结果: $keyword');
            return;
          }

          _searchResult = _searchResult.copyWith(
            appleResults: results,
            appleLoading: false,
          );

          StructuredLogService.log('✅ [SearchService] Apple Music 搜索完成: ${results.length} 条结果');
        } else {
          throw Exception('服务器返回状态 ${data['status']}');
        }
      } else {
        throw Exception('HTTP ${result.statusCode}');
      }
    } catch (e) {
      StructuredLogService.log('❌ [SearchService] Apple Music 搜索失败: $e');
      if (!_isSessionActive(sessionId, keyword)) {
        StructuredLogService.log('⏭️ [SearchService] 丢弃过期 Apple 错误: $keyword');
        return;
      }
      _searchResult = _searchResult.copyWith(
        appleLoading: false,
        appleError: e.toString(),
      );
    }
    if (!_isSessionActive(sessionId, keyword)) {
      StructuredLogService.log('⏭️ [SearchService] 跳过过期 Apple 刷新: $keyword');
      return;
    }
    notifyListeners();
  }

  /// 搜索QQ音乐
  Future<void> _searchQQ(String keyword, int sessionId, CancelToken cancelToken) async {
    try {
      StructuredLogService.log('🎶 [SearchService] QQ音乐搜索: $keyword');

      final result = await ApiClient().getJson(
        '/qq/search',
        queryParameters: {'keywords': keyword, 'limit': 10},
        timeout: const Duration(seconds: 10),
        cancelToken: cancelToken,
      );

      if (result.ok) {
        final data = result.data as Map<String, dynamic>;

        if (data['status'] == 200) {
          final results = (data['result'] as List<dynamic>)
              .map((item) => Track(
                    id: item['mid'] as String,  // QQ音乐使用 mid
                    name: item['name'] as String,
                    artists: item['singer'] as String,
                    album: item['album'] as String,
                    picUrl: item['pic'] as String,
                    source: MusicSource.qq,
                  ))
              .toList();

          if (!_isSessionActive(sessionId, keyword)) {
            StructuredLogService.log('⏭️ [SearchService] 丢弃过期 QQ 结果: $keyword');
            return;
          }

          _searchResult = _searchResult.copyWith(
            qqResults: results,
            qqLoading: false,
          );

          StructuredLogService.log('✅ [SearchService] QQ音乐搜索完成: ${results.length} 条结果');
        } else {
          throw Exception('服务器返回状态 ${data['status']}');
        }
      } else {
        throw Exception('HTTP ${result.statusCode}');
      }
    } catch (e) {
      StructuredLogService.log('❌ [SearchService] QQ音乐搜索失败: $e');
      if (!_isSessionActive(sessionId, keyword)) {
        StructuredLogService.log('⏭️ [SearchService] 丢弃过期 QQ 错误: $keyword');
        return;
      }
      _searchResult = _searchResult.copyWith(
        qqLoading: false,
        qqError: e.toString(),
      );
    }
    if (!_isSessionActive(sessionId, keyword)) {
      StructuredLogService.log('⏭️ [SearchService] 跳过过期 QQ 刷新: $keyword');
      return;
    }
    notifyListeners();
  }

  /// 搜索酷狗音乐
  Future<void> _searchKugou(String keyword, int sessionId, CancelToken cancelToken) async {
    try {
      StructuredLogService.log('🎼 [SearchService] 酷狗音乐搜索: $keyword');

      final result = await ApiClient().getJson(
        '/kugou/search',
        queryParameters: {'keywords': keyword},
        timeout: const Duration(seconds: 10),
        cancelToken: cancelToken,
      );

      if (result.ok) {
        final data = result.data as Map<String, dynamic>;

        if (data['status'] == 200) {
          final results = (data['result'] as List<dynamic>)
              .whereType<Map>()
              .map((item) => Map<String, dynamic>.from(item))
              .where((item) => _nonEmptyString(item['hash']) != null)
              .map((item) {
                final emixSongId = _nonEmptyString(item['emixsongid']);
                final fileHash = _nonEmptyString(item['hash'])!;
                return Track(
                  id: emixSongId ?? fileHash,
                  name: item['name']?.toString() ?? '',
                  artists: item['singer']?.toString() ?? '',
                  album: item['album']?.toString() ?? '',
                  picUrl: item['pic']?.toString() ?? '',
                  source: MusicSource.kugou,
                  sourceIds: TrackSourceIds(
                    fileHash: fileHash,
                    emixSongId: emixSongId,
                    albumAudioId: _nonEmptyString(item['album_audio_id']),
                  ),
                );
              })
              .toList();

          if (!_isSessionActive(sessionId, keyword)) {
            StructuredLogService.log('⏭️ [SearchService] 丢弃过期酷狗结果: $keyword');
            return;
          }

          _searchResult = _searchResult.copyWith(
            kugouResults: results,
            kugouLoading: false,
          );

          StructuredLogService.log('✅ [SearchService] 酷狗音乐搜索完成: ${results.length} 条结果');
        } else {
          throw Exception('服务器返回状态 ${data['status']}');
        }
      } else {
        throw Exception('HTTP ${result.statusCode}');
      }
    } catch (e) {
      StructuredLogService.log('❌ [SearchService] 酷狗音乐搜索失败: $e');
      if (!_isSessionActive(sessionId, keyword)) {
        StructuredLogService.log('⏭️ [SearchService] 丢弃过期酷狗错误: $keyword');
        return;
      }
      _searchResult = _searchResult.copyWith(
        kugouLoading: false,
        kugouError: e.toString(),
      );
    }
    if (!_isSessionActive(sessionId, keyword)) {
      StructuredLogService.log('⏭️ [SearchService] 跳过过期酷狗刷新: $keyword');
      return;
    }
    notifyListeners();
  }

  static String? _nonEmptyString(dynamic value) {
    final text = value?.toString().trim();
    return text == null || text.isEmpty ? null : text;
  }

  /// 搜索酷我音乐
  Future<void> _searchKuwo(String keyword, int sessionId, CancelToken cancelToken) async {
    try {
      StructuredLogService.log('🎸 [SearchService] 酷我音乐搜索: $keyword');

      final result = await ApiClient().getJson(
        '/kuwo/search',
        queryParameters: {'keywords': keyword},
        timeout: const Duration(seconds: 10),
        cancelToken: cancelToken,
      );

      if (result.ok) {
        final data = result.data as Map<String, dynamic>;

        if (data['status'] == 200) {
          final songsData = data['data']?['songs'] as List<dynamic>? ?? [];
          final results = songsData
              .map((item) => Track(
                    id: item['rid'] as int,  // 酷我使用 rid
                    name: item['name'] as String,
                    artists: item['artist'] as String,
                    album: item['album'] as String? ?? '',
                    picUrl: item['pic'] as String? ?? '',
                    source: MusicSource.kuwo,
                  ))
              .toList();

          if (!_isSessionActive(sessionId, keyword)) {
            StructuredLogService.log('⏭️ [SearchService] 丢弃过期酷我结果: $keyword');
            return;
          }

          _searchResult = _searchResult.copyWith(
            kuwoResults: results,
            kuwoLoading: false,
          );

          StructuredLogService.log('✅ [SearchService] 酷我音乐搜索完成: ${results.length} 条结果');
        } else {
          throw Exception('服务器返回状态 ${data['status']}');
        }
      } else {
        throw Exception('HTTP ${result.statusCode}');
      }
    } catch (e) {
      StructuredLogService.log('❌ [SearchService] 酷我音乐搜索失败: $e');
      if (!_isSessionActive(sessionId, keyword)) {
        StructuredLogService.log('⏭️ [SearchService] 丢弃过期酷我错误: $keyword');
        return;
      }
      _searchResult = _searchResult.copyWith(
        kuwoLoading: false,
        kuwoError: e.toString(),
      );
    }
    if (!_isSessionActive(sessionId, keyword)) {
      StructuredLogService.log('⏭️ [SearchService] 跳过过期酷我刷新: $keyword');
      return;
    }
    notifyListeners();
  }

  /// 搜索 Spotify
  Future<void> _searchSpotify(String keyword, int sessionId, CancelToken cancelToken) async {
    try {
      StructuredLogService.log('🟢 [SearchService] Spotify 搜索: $keyword');

      final result = await ApiClient().getJson(
        '/spotify/search',
        queryParameters: {'keywords': keyword},
        timeout: const Duration(seconds: 10),
        cancelToken: cancelToken,
      );

      if (result.ok) {
        final data = result.data as Map<String, dynamic>;

        if (data['status'] == 200) {
          final tracksData = data['result']?['tracks'] as List<dynamic>? ?? [];
          final results = tracksData.map((item) {
            final artistsList = item['artists'] as List<dynamic>? ?? [];
            final artistsNames = artistsList.map((a) => a['name'] as String).join(', ');
            final albumData = item['album'] as Map<String, dynamic>? ?? {};

            return Track(
              id: item['id'] as String,
              name: item['name'] as String,
              artists: artistsNames,
              album: albumData['name'] as String? ?? '',
              picUrl: albumData['coverArt'] as String? ?? '',
              source: MusicSource.spotify,
            );
          }).toList();

          if (!_isSessionActive(sessionId, keyword)) {
            StructuredLogService.log('⏭️ [SearchService] 丢弃过期 Spotify 结果: $keyword');
            return;
          }

          _searchResult = _searchResult.copyWith(
            spotifyResults: results,
            spotifyLoading: false,
          );

          StructuredLogService.log('✅ [SearchService] Spotify 搜索完成: ${results.length} 条结果');
        } else {
          throw Exception('服务器返回状态 ${data['status']}');
        }
      } else {
        throw Exception('HTTP ${result.statusCode}');
      }
    } catch (e) {
      StructuredLogService.log('❌ [SearchService] Spotify 搜索失败: $e');
      if (!_isSessionActive(sessionId, keyword)) {
        StructuredLogService.log('⏭️ [SearchService] 丢弃过期 Spotify 错误: $keyword');
        return;
      }
      _searchResult = _searchResult.copyWith(
        spotifyLoading: false,
        spotifyError: e.toString(),
      );
    }
    if (!_isSessionActive(sessionId, keyword)) {
      StructuredLogService.log('⏭️ [SearchService] 跳过过期 Spotify 刷新: $keyword');
      return;
    }
    notifyListeners();
  }

  /// 获取合并后的搜索结果（跨平台去重）
  List<MergedTrack> getMergedResults() {
    // 收集所有平台的歌曲
    // 注意：Apple Music 放在最后，因为其 DRM 加密流目前无法直接播放
    final allTracks = <Track>[
      ...(_searchResult.neteaseResults),
      ...(_searchResult.qqResults),
      ...(_searchResult.kugouResults),
      ...(_searchResult.kuwoResults),
      ...(_searchResult.spotifyResults),
      ...(_searchResult.appleResults), // Apple Music 优先级最低
    ];

    if (allTracks.isEmpty) {
      return [];
    }

    // 合并相同的歌曲
    final mergedMap = <String, List<Track>>{};

    for (final track in allTracks) {
      // 生成唯一键（标准化后的歌曲名+歌手名）
      final key = _generateKey(track.name, track.artists);

      if (mergedMap.containsKey(key)) {
        mergedMap[key]!.add(track);
      } else {
        mergedMap[key] = [track];
      }
    }

    // 转换为 MergedTrack 列表
    final mergedTracks = mergedMap.values
        .map((tracks) => MergedTrack.fromTracks(tracks))
        .toList();

    StructuredLogService.log('🔍 [SearchService] 合并结果: ${allTracks.length} 首 → ${mergedTracks.length} 首');

    if (_currentKeyword.trim().isNotEmpty) {
      final keyword = _currentKeyword;
      mergedTracks.sort((a, b) {
        final scoreB = _calculateTrackRelevance(b, keyword);
        final scoreA = _calculateTrackRelevance(a, keyword);
        if (scoreB.compareTo(scoreA) != 0) {
          return scoreB.compareTo(scoreA);
        }
        // 如果相关度相同，则按名称字典序排序（保持稳定性）
        return a.name.toLowerCase().compareTo(b.name.toLowerCase());
      });
    }

    return mergedTracks;
  }

  /// 生成歌曲的唯一键（用于合并判断）
  String _generateKey(String name, String artists) {
    return '${_normalize(name)}|${_normalize(artists)}';
  }

  /// 标准化字符串
  String _normalize(String str) {
    return str
        .trim()
        .toLowerCase()
        .replaceAll(' ', '')
        .replaceAll('、', ',')
        .replaceAll('/', ',')
        .replaceAll('&', ',')
        .replaceAll('，', ',');
  }

  double _calculateTrackRelevance(MergedTrack track, String keyword) {
    final normalizedKeyword = _normalizeForScoring(keyword);
    if (normalizedKeyword.isEmpty) {
      return 0;
    }

    final keywordTokens = _tokenizeForScoring(keyword);
    final strippedKeyword = _stripForLcs(keyword);

    double bestScore = 0;
    for (final candidate in track.tracks) {
      final score = _calculateNameScore(
        candidate.name,
        normalizedKeyword: normalizedKeyword,
        keywordTokens: keywordTokens,
        strippedKeyword: strippedKeyword,
      );
      if (score > bestScore) {
        bestScore = score;
      }
    }

    return bestScore;
  }

  double _calculateNameScore(
    String name, {
    required String normalizedKeyword,
    required List<String> keywordTokens,
    required String strippedKeyword,
  }) {
    final normalizedName = _normalizeForScoring(name);
    if (normalizedName.isEmpty) {
      return 0;
    }

    if (normalizedName == normalizedKeyword) {
      return 1.0;
    }

    if (normalizedName.startsWith(normalizedKeyword)) {
      final ratio = normalizedKeyword.length / normalizedName.length;
      return (0.9 + ratio * 0.1).clamp(0.0, 1.0);
    }

    if (normalizedName.contains(normalizedKeyword)) {
      final ratio = normalizedKeyword.length / normalizedName.length;
      return (0.75 + ratio * 0.15).clamp(0.0, 1.0);
    }

    final nameTokens = _tokenizeForScoring(name);
    double tokenScore = 0;
    if (keywordTokens.isNotEmpty && nameTokens.isNotEmpty) {
      final keywordSet = keywordTokens.toSet();
      final nameSet = nameTokens.toSet();
      final intersectionCount =
          keywordSet.where((token) => nameSet.contains(token)).length;
      tokenScore = intersectionCount / keywordSet.length;
    }

    double lcsScore = 0;
    if (strippedKeyword.isNotEmpty) {
      final strippedName = _stripForLcs(name);
      if (strippedName.isNotEmpty) {
        final lcsLength =
            _longestCommonSubsequenceLength(strippedName, strippedKeyword);
        lcsScore = lcsLength / strippedKeyword.length;
      }
    }

    return (tokenScore * 0.6 + lcsScore * 0.4).clamp(0.0, 1.0);
  }

  String _normalizeForScoring(String input) {
    return input
        .toLowerCase()
        .replaceAll(RegExp(r'[^\w\u4e00-\u9fa5]+'), ' ')
        .trim()
        .replaceAll(RegExp(r'\s+'), ' ');
  }

  List<String> _tokenizeForScoring(String input) {
    final normalized = _normalizeForScoring(input);
    if (normalized.isEmpty) {
      return const [];
    }
    return normalized.split(' ').where((token) => token.isNotEmpty).toList();
  }

  String _stripForLcs(String input) {
    return input
        .toLowerCase()
        .replaceAll(RegExp(r'[^\w\u4e00-\u9fa5]+'), '');
  }

  int _longestCommonSubsequenceLength(String a, String b) {
    final m = a.length;
    final n = b.length;
    if (m == 0 || n == 0) {
      return 0;
    }

    final dp = List.generate(
      m + 1,
      (_) => List<int>.filled(n + 1, 0),
    );

    for (var i = 1; i <= m; i++) {
      for (var j = 1; j <= n; j++) {
        if (a[i - 1] == b[j - 1]) {
          dp[i][j] = dp[i - 1][j - 1] + 1;
        } else {
          dp[i][j] = dp[i - 1][j] > dp[i][j - 1] ? dp[i - 1][j] : dp[i][j - 1];
        }
      }
    }

    return dp[m][n];
  }

  /// 清空搜索结果
  void clear() {
    _activeSearchSession++;
    _cancelActiveSearchRequests('搜索已清空');
    _activeSearchCancelToken = null;
    _searchResult = SearchResult();
    _currentKeyword = '';
    notifyListeners();
  }

  bool _isSessionActive(int sessionId, String keyword) {
    return sessionId == _activeSearchSession && keyword == _currentKeyword;
  }

  void _cancelActiveSearchRequests(String reason) {
    final token = _activeSearchCancelToken;
    if (token == null || token.isCancelled) {
      return;
    }
    token.cancel(reason);
  }

  @override
  void dispose() {
    _activeSearchSession++;
    _cancelActiveSearchRequests('SearchService disposed');
    _activeSearchCancelToken = null;
    super.dispose();
  }

  /// 加载搜索历史
  Future<void> _loadSearchHistory() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final history = prefs.getStringList(_historyKey) ?? [];
      _searchHistory = history;
      StructuredLogService.log('📚 [SearchService] 加载搜索历史: ${_searchHistory.length} 条');
    } catch (e) {
      StructuredLogService.log('❌ [SearchService] 加载搜索历史失败: $e');
      _searchHistory = [];
    }
  }

  /// 添加到搜索历史
  Future<void> _addToSearchHistory(String keyword) async {
    try {
      final trimmedKeyword = keyword.trim();
      if (trimmedKeyword.isEmpty) return;

      // 如果已存在，先移除（避免重复）
      _searchHistory.remove(trimmedKeyword);

      // 添加到列表开头
      _searchHistory.insert(0, trimmedKeyword);

      // 限制历史记录数量
      if (_searchHistory.length > _maxHistoryCount) {
        _searchHistory = _searchHistory.sublist(0, _maxHistoryCount);
      }

      // 保存到本地
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList(_historyKey, _searchHistory);

      StructuredLogService.log('💾 [SearchService] 保存搜索历史: $trimmedKeyword');
      notifyListeners();
    } catch (e) {
      StructuredLogService.log('❌ [SearchService] 保存搜索历史失败: $e');
    }
  }

  /// 删除单条搜索历史
  Future<void> removeSearchHistory(String keyword) async {
    try {
      _searchHistory.remove(keyword);

      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList(_historyKey, _searchHistory);

      StructuredLogService.log('🗑️ [SearchService] 删除搜索历史: $keyword');
      notifyListeners();
    } catch (e) {
      StructuredLogService.log('❌ [SearchService] 删除搜索历史失败: $e');
    }
  }

  /// 清空所有搜索历史
  Future<void> clearSearchHistory() async {
    try {
      _searchHistory.clear();

      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_historyKey);

      StructuredLogService.log('🗑️ [SearchService] 清空所有搜索历史');
      notifyListeners();
    } catch (e) {
      StructuredLogService.log('❌ [SearchService] 清空搜索历史失败: $e');
    }
  }
}
