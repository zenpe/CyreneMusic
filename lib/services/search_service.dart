import 'structured_log_service.dart';
import 'package:flutter/foundation.dart';
import 'package:dio/dio.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/track.dart';
import '../models/search_page_state.dart';
import 'api/api_client.dart';
import 'search_provider_catalog.dart';
import 'search_request.dart';

/// 搜索结果模型
class SearchResult {
  static const Object _unchanged = Object();

  List<Track> resultsFor(MusicSource source) => switch (source) {
    MusicSource.netease => neteaseResults,
    MusicSource.qq => qqResults,
    MusicSource.kugou => kugouResults,
    MusicSource.kuwo => kuwoResults,
    MusicSource.apple => appleResults,
    MusicSource.spotify => spotifyResults,
    _ => const [],
  };

  bool loadingFor(MusicSource source) => switch (source) {
    MusicSource.netease => neteaseLoading,
    MusicSource.qq => qqLoading,
    MusicSource.kugou => kugouLoading,
    MusicSource.kuwo => kuwoLoading,
    MusicSource.apple => appleLoading,
    MusicSource.spotify => spotifyLoading,
    _ => false,
  };

  String? errorFor(MusicSource source) => switch (source) {
    MusicSource.netease => neteaseError,
    MusicSource.qq => qqError,
    MusicSource.kugou => kugouError,
    MusicSource.kuwo => kuwoError,
    MusicSource.apple => appleError,
    MusicSource.spotify => spotifyError,
    _ => null,
  };
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
  final bool qqSuggestions;

  String? noticeFor(MusicSource source) =>
      source == MusicSource.qq && qqSuggestions ? 'QQ音乐当前显示联想结果，结果可能不完整' : null;

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
    this.qqSuggestions = false,
  });

  /// 获取所有结果的总数
  int get totalCount =>
      neteaseResults.length +
      appleResults.length +
      qqResults.length +
      kugouResults.length +
      kuwoResults.length +
      spotifyResults.length;

  /// 是否所有平加载完成
  bool get allCompleted =>
      !neteaseLoading &&
      !appleLoading &&
      !qqLoading &&
      !kugouLoading &&
      !kuwoLoading &&
      !spotifyLoading;

  /// 是否有任何错误
  bool get hasError =>
      neteaseError != null ||
      appleError != null ||
      qqError != null ||
      kugouError != null ||
      kuwoError != null ||
      spotifyError != null;

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
    bool? qqSuggestions,
    Object? neteaseError = _unchanged,
    Object? appleError = _unchanged,
    Object? qqError = _unchanged,
    Object? kugouError = _unchanged,
    Object? kuwoError = _unchanged,
    Object? spotifyError = _unchanged,
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
      qqSuggestions: qqSuggestions ?? this.qqSuggestions,
      neteaseError: identical(neteaseError, _unchanged)
          ? this.neteaseError
          : neteaseError as String?,
      appleError: identical(appleError, _unchanged)
          ? this.appleError
          : appleError as String?,
      qqError: identical(qqError, _unchanged)
          ? this.qqError
          : qqError as String?,
      kugouError: identical(kugouError, _unchanged)
          ? this.kugouError
          : kugouError as String?,
      kuwoError: identical(kuwoError, _unchanged)
          ? this.kuwoError
          : kuwoError as String?,
      spotifyError: identical(spotifyError, _unchanged)
          ? this.spotifyError
          : spotifyError as String?,
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
  final Map<MusicSource, CancelToken> _requests = {};
  final Map<MusicSource, SearchPageState> _pages = {};
  int get sessionId => _activeSearchSession;
  SearchPageState pageFor(MusicSource platform) =>
      _pages[platform] ?? const SearchPageState();

  // 搜索历史记录
  List<String> _searchHistory = [];
  List<String> get searchHistory => _searchHistory;

  static const String _historyKey = 'search_history';
  static const int _maxHistoryCount = 20; // 最多保存20条历史记录
  static const SearchProviderCatalog _providerCatalog = SearchProviderCatalog();

  /// First pages remain independent and concurrent.
  Future<void> search(String keyword, {bool saveHistory = true}) async {
    final normalized = keyword.trim();
    if (normalized.isEmpty) return;
    final session = ++_activeSearchSession;
    _cancelActiveSearchRequests('新的搜索请求');
    _currentKeyword = normalized;
    _pages.clear();
    _searchResult = SearchResult();
    for (final platform in SearchProviderCatalog.defaultPlatforms) {
      _updatePlatform(platform, loading: true, error: null);
    }
    notifyListeners();
    if (saveHistory) {
      await _addToSearchHistory(normalized);
      if (!_isSessionActive(session, normalized)) return;
    }
    await Future.wait(
      SearchProviderCatalog.defaultPlatforms.map(
        (platform) => _fetchPlatformPage(platform, 1, session, normalized),
      ),
    );
  }

  List<String> get currentSupportedPlatforms => _providerCatalog.platformKeys;

  Future<void> retryPlatform(MusicSource platform) async {
    if (!_providerCatalog.supports(platform) ||
        _currentKeyword.isEmpty ||
        _requests.containsKey(platform)) {
      return;
    }
    if (pageFor(platform).page > 0) {
      await loadMore(platform);
    } else {
      await _fetchPlatformPage(
        platform,
        1,
        _activeSearchSession,
        _currentKeyword,
      );
    }
  }

  Future<void> loadMore(MusicSource platform) async {
    final state = pageFor(platform);
    if (!_providerCatalog.supports(platform) ||
        _currentKeyword.isEmpty ||
        state.page < 1 ||
        !state.hasMore ||
        state.blocked ||
        _requests.containsKey(platform)) {
      return;
    }
    await _fetchPlatformPage(
      platform,
      state.page + 1,
      _activeSearchSession,
      _currentKeyword,
    );
  }

  Future<void> _fetchPlatformPage(
    MusicSource platform,
    int page,
    int session,
    String keyword,
  ) async {
    if (!_isSessionActive(session, keyword) ||
        _requests.containsKey(platform)) {
      return;
    }
    final token = CancelToken();
    _requests[platform] = token;
    final previous = pageFor(platform);
    final append = page > 1;
    _pages[platform] = SearchPageState(
      page: previous.page,
      hasMore: previous.hasMore,
      loadingMore: append,
      fingerprint: previous.fingerprint,
    );
    if (!append) _updatePlatform(platform, loading: true, error: null);
    notifyListeners();
    bool current() =>
        _isSessionActive(session, keyword) &&
        identical(_requests[platform], token) &&
        !token.isCancelled;
    try {
      final params = <String, dynamic>{
        'keywords': keyword,
        'limit': 20,
        'page': page,
      };
      final response = await runSearchRequest(
        token,
        (child) => platform == MusicSource.netease
            ? ApiClient().postJson(
                '/search',
                data: params,
                contentType: 'application/x-www-form-urlencoded',
                timeout: const Duration(seconds: 15),
                cancelToken: child,
              )
            : ApiClient().getJson(
                platform == MusicSource.qq ? '/qq/search' : '/kugou/search',
                queryParameters: params,
                timeout: const Duration(seconds: 15),
                cancelToken: child,
              ),
      );
      if (!current()) return;
      if (!response.ok) {
        throw Exception(response.statusCode == 504 ? '搜索超时，请重试' : '搜索失败，请稍后重试');
      }
      final data = response.data;
      if (data is! Map || data['status'] != 200 || data['result'] is! List) {
        throw const FormatException('搜索结果格式异常');
      }
      if ((append && data['page'] != page) ||
          (data['page'] != null && data['page'] != page)) {
        throw const FormatException('搜索页码异常，请重试');
      }
      final suggestions = data['resultKind'] == 'suggestions';
      if (append && suggestions) {
        throw const FormatException('暂时无法获取完整搜索结果，请重试');
      }
      final fingerprint = data['pageFingerprint'] as String?;
      if (append &&
          fingerprint != null &&
          fingerprint == previous.fingerprint) {
        _pages[platform] = SearchPageState(
          page: previous.page,
          hasMore: false,
          blocked: true,
          error: '暂时无法加载更多，请重新搜索',
          fingerprint: fingerprint,
        );
        return;
      }
      final tracks = (data['result'] as List)
          .whereType<Map>()
          .map((item) => _mapSearchTrack(platform, item))
          .whereType<Track>();
      final existing = append ? _searchResult.resultsFor(platform) : <Track>[];
      final seen = existing.map((track) => track.id.toString()).toSet();
      final combined = [
        ...existing,
        ...tracks.where((track) => seen.add(track.id.toString())),
      ];
      _pages[platform] = SearchPageState(
        page: page,
        hasMore:
            !suggestions && data['page'] == page && data['hasMore'] == true,
        fingerprint: fingerprint,
      );
      _updatePlatform(platform, tracks: combined, loading: false, error: null);
      if (platform == MusicSource.qq) {
        _searchResult = _searchResult.copyWith(qqSuggestions: suggestions);
      }
    } catch (error) {
      if (!current()) return;
      StructuredLogService.log(
        '[SearchService] ${platform.name} page=$page failed: $error',
      );
      _pages[platform] = SearchPageState(
        page: previous.page,
        hasMore: previous.hasMore,
        fingerprint: previous.fingerprint,
        error: append ? '加载失败，请重试' : null,
      );
      if (!append) {
        _updatePlatform(platform, loading: false, error: error.toString());
      }
    } finally {
      if (identical(_requests[platform], token)) {
        _requests.remove(platform);
        if (_isSessionActive(session, keyword)) notifyListeners();
      }
    }
  }

  Track? _mapSearchTrack(MusicSource platform, Map item) {
    if (platform == MusicSource.kugou) {
      final hash = _nonEmptyString(item['hash']);
      if (hash == null) return null;
      final emix = _nonEmptyString(item['emixsongid']);
      return Track(
        id: emix ?? hash,
        name: item['name']?.toString() ?? '',
        artists: item['singer']?.toString() ?? '',
        album: item['album']?.toString() ?? '',
        picUrl: item['pic']?.toString() ?? '',
        source: platform,
        sourceIds: TrackSourceIds(
          fileHash: hash,
          emixSongId: emix,
          albumAudioId: _nonEmptyString(item['album_audio_id']),
        ),
      );
    }
    final id = platform == MusicSource.qq ? item['mid'] : item['id'];
    if (id == null || id.toString().isEmpty) return null;
    return Track(
      id: id,
      name: item['name']?.toString() ?? '',
      artists:
          (platform == MusicSource.qq ? item['singer'] : item['artists'])
              ?.toString() ??
          '',
      album: item['album']?.toString() ?? '',
      picUrl:
          (platform == MusicSource.qq ? item['pic'] : item['picUrl'])
              ?.toString() ??
          '',
      source: platform,
    );
  }

  void _updatePlatform(
    MusicSource platform, {
    List<Track>? tracks,
    bool? loading,
    String? error,
  }) {
    _searchResult = switch (platform) {
      MusicSource.netease => _searchResult.copyWith(
        neteaseResults: tracks,
        neteaseLoading: loading,
        neteaseError: error,
      ),
      MusicSource.qq => _searchResult.copyWith(
        qqResults: tracks,
        qqLoading: loading,
        qqError: error,
      ),
      MusicSource.kugou => _searchResult.copyWith(
        kugouResults: tracks,
        kugouLoading: loading,
        kugouError: error,
      ),
      _ => _searchResult,
    };
  }

  static String? _nonEmptyString(dynamic value) {
    final text = value?.toString().trim();
    return text == null || text.isEmpty ? null : text;
  }

  /// Cancels IO when the UI closes, retaining completed pages.
  void cancelPendingRequests() {
    _activeSearchSession++;
    final pending = {
      ..._requests.keys,
      ...SearchProviderCatalog.defaultPlatforms.where(_searchResult.loadingFor),
    };
    _cancelActiveSearchRequests('搜索页面已关闭');
    for (final platform in pending) {
      _pages[platform] = pageFor(platform).stopLoading();
      if (_searchResult.loadingFor(platform)) {
        _updatePlatform(platform, loading: false, error: '搜索已取消，请重试');
      }
    }
    if (pending.isNotEmpty) notifyListeners();
  }

  /// 清空搜索结果
  void clear() {
    _activeSearchSession++;
    _cancelActiveSearchRequests('搜索已清空');
    _pages.clear();
    _searchResult = SearchResult();
    _currentKeyword = '';
    notifyListeners();
  }

  bool _isSessionActive(int sessionId, String keyword) {
    return sessionId == _activeSearchSession && keyword == _currentKeyword;
  }

  void _cancelActiveSearchRequests(String reason) {
    final tokens = _requests.values.toList();
    _requests.clear();
    for (final token in tokens) {
      token.cancel(reason);
    }
  }

  @override
  void dispose() {
    _activeSearchSession++;
    _cancelActiveSearchRequests('SearchService disposed');
    _pages.clear();
    super.dispose();
  }

  /// 加载搜索历史
  Future<void> _loadSearchHistory() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final history = prefs.getStringList(_historyKey) ?? [];
      _searchHistory = history;
      StructuredLogService.log(
        '📚 [SearchService] 加载搜索历史: ${_searchHistory.length} 条',
      );
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
