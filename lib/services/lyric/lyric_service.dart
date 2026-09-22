import 'package:flutter/material.dart';

import '../../models/lyric_line.dart';
import '../../models/song_detail.dart';
import '../../models/track.dart';
import '../../utils/lyric_parser.dart';
import 'lyric_cache_service.dart';
import 'lyric_repository.dart';
import 'lyric_snapshot.dart';

typedef LyricLogFn = void Function(String message, {bool toDeveloperPanel});

class LyricRequestFetchAdapter {
  final bool useLyricOnlyFetch;
  final bool allowFullDetailFallback;
  final bool emptyResultIsAuthoritative;
  final Future<SongDetail?> Function() fetchLyricOnlyDetail;
  final Future<SongDetail?> Function() fetchFullDetail;
  final SongDetail Function(SongDetail detail) normalizeSongDetail;

  const LyricRequestFetchAdapter({
    required this.useLyricOnlyFetch,
    this.allowFullDetailFallback = true,
    this.emptyResultIsAuthoritative = false,
    required this.fetchLyricOnlyDetail,
    required this.fetchFullDetail,
    required this.normalizeSongDetail,
  });
}

class LyricRequestPresentationAdapter {
  final bool Function(SongDetail current, SongDetail next) isSamePresentation;
  final SongDetail? Function() currentSong;
  final void Function(SongDetail detail) applyResolvedSongDetail;
  final void Function() refreshFloatingLyrics;

  const LyricRequestPresentationAdapter({
    required this.isSamePresentation,
    required this.currentSong,
    required this.applyResolvedSongDetail,
    required this.refreshFloatingLyrics,
  });
}

class LyricRequestCacheAdapter {
  final SongDetail Function(SongDetail current, SongDetail supplemental)
  mergeSupplementalSongDetail;
  final SongDetail Function(SongDetail current, SongDetail normalizedDetail)
  buildCacheRefreshSongDetail;
  final Future<bool> Function(SongDetail detail) cacheSongInBackground;

  const LyricRequestCacheAdapter({
    required this.mergeSupplementalSongDetail,
    required this.buildCacheRefreshSongDetail,
    required this.cacheSongInBackground,
  });
}

class LyricRequestAdapter {
  final LyricRequestFetchAdapter fetch;
  final LyricRequestPresentationAdapter presentation;
  final LyricRequestCacheAdapter cache;
  final bool Function(SongDetail song) hasAnyLyricPayload;
  final LyricLogFn log;

  const LyricRequestAdapter({
    required this.fetch,
    required this.presentation,
    required this.cache,
    required this.hasAnyLyricPayload,
    required this.log,
  });
}

class LyricPrefetchAdapter {
  final Future<SongDetail?> Function() fetchLyricOnlyDetail;
  final SongDetail Function(SongDetail detail) normalizeSongDetail;
  final bool Function(SongDetail song) hasAnyLyricPayload;
  final LyricLogFn log;

  const LyricPrefetchAdapter({
    required this.fetchLyricOnlyDetail,
    required this.normalizeSongDetail,
    required this.hasAnyLyricPayload,
    required this.log,
  });
}

class LyricService extends ChangeNotifier {
  static final LyricService _instance = LyricService._internal();
  factory LyricService() => _instance;
  static const Duration _plainTextFallbackLineInterval = Duration(seconds: 3);
  static final RegExp _plainLyricBracketTagPattern = RegExp(r'\[[^\]]+\]');
  static final RegExp _plainLyricParensTriplePattern = RegExp(
    r'\(\d+,\d+,\d+\)',
  );
  static final RegExp _plainLyricParensDoublePattern = RegExp(r'\(\d+,\d+\)');
  static final RegExp _plainLyricAngleTriplePattern = RegExp(r'<\d+,\d+,\d+>');

  LyricService._internal();

  final Set<String> _pendingRefreshKeys = <String>{};

  LyricSnapshot? _currentSnapshot;
  LyricLoadState _currentState = LyricLoadState.idle;
  String? _currentTrackKey;
  int _currentPlaybackToken = 0;
  String? _currentError;
  final LyricRepository _repository = LyricRepository();

  LyricSnapshot? get currentSnapshot => _currentSnapshot;
  LyricLoadState get currentState => _currentState;

  void bindCurrentTrack({
    required Track track,
    required int playbackToken,
    SongDetail? song,
    required LyricLoadState state,
    bool notify = true,
  }) {
    _publish(
      trackKey: _trackKey(track),
      playbackToken: playbackToken,
      song: song,
      state: state,
      error: null,
      notify: notify,
    );
  }

  void syncState({
    required Track track,
    required int playbackToken,
    SongDetail? song,
    required LyricLoadState state,
    String? error,
    bool notify = true,
  }) {
    _publish(
      trackKey: _trackKey(track),
      playbackToken: playbackToken,
      song: song,
      state: state,
      error: error,
      notify: notify,
    );
  }

  void clearCurrent({bool notify = true}) {
    _currentSnapshot = null;
    _currentState = LyricLoadState.idle;
    _currentTrackKey = null;
    _currentPlaybackToken = 0;
    _currentError = null;
    if (notify) {
      notifyListeners();
    }
  }

  void clearAll({bool notify = true}) {
    _pendingRefreshKeys.clear();
    _repository.clearMemory();
    clearCurrent(notify: notify);
  }

  Future<void> clearCachedLyrics() async {
    _pendingRefreshKeys.clear();
    _repository.clearMemory();
    await LyricCacheService().clearAllCache();
  }

  Future<void> evictTrackCache(Track track, {String? quality}) async {
    _repository.evictTrack(track, quality: quality);
    await LyricCacheService().deleteTrackCache(track, quality: quality);
  }

  Future<void> requestLyrics({
    required Track track,
    required int playbackToken,
    required String quality,
    required String refreshKey,
    required LyricRequestAdapter adapter,
  }) async {
    final trackKey = _trackKey(track);
    final presentation = adapter.presentation;
    final fetch = adapter.fetch;
    final cache = adapter.cache;
    final cachedResult = await _repository.lookup(
      track: track,
      quality: quality,
      currentSong: _displayableSongOrNull(presentation.currentSong()),
      log: adapter.log,
    );
    final cached = cachedResult != null && _isUsableLookupResult(cachedResult)
        ? cachedResult
        : null;
    if (cachedResult != null && cached == null) {
      adapter.log(
        '[LyricService] 歌词缓存命中但内容不可展示，继续远端补全: $refreshKey',
        toDeveloperPanel: true,
      );
    }
    if (cached != null) {
      adapter.log(
        '[LyricService] 歌词缓存命中: ${cached.category} key=$refreshKey',
        toDeveloperPanel: true,
      );
      final currentSong = presentation.currentSong();
      if (_isCurrent(trackKey, playbackToken)) {
        if (cached.song != null &&
            (currentSong == null ||
                !presentation.isSamePresentation(currentSong, cached.song!))) {
          presentation.applyResolvedSongDetail(cached.song!);
        }
        _publish(
          trackKey: trackKey,
          playbackToken: playbackToken,
          song: cached.song ?? currentSong,
          state: cached.state,
          error: cached.error,
        );
        if (cached.state == LyricLoadState.ready) {
          presentation.refreshFloatingLyrics();
        }
      }
      if (cached.skipRemote) {
        return;
      }
    }

    if (_pendingRefreshKeys.contains(refreshKey)) {
      adapter.log('[LyricService] 跳过重复歌词补全: $refreshKey');
      return;
    }

    _pendingRefreshKeys.add(refreshKey);
    adapter.log('[LyricService] 歌词补全开始: $refreshKey', toDeveloperPanel: true);

    if (_isCurrent(trackKey, playbackToken)) {
      final currentSong = presentation.currentSong();
      _publish(
        trackKey: trackKey,
        playbackToken: playbackToken,
        song: currentSong,
        state: LyricLoadState.loading,
        error: null,
      );
    }

    var finalized = false;
    void finalize(
      LyricLoadState state, {
      SongDetail? song,
      String? error,
      bool notify = true,
    }) {
      finalized = true;
      if (!_isCurrent(trackKey, playbackToken)) return;
      _publish(
        trackKey: trackKey,
        playbackToken: playbackToken,
        song: song ?? presentation.currentSong(),
        state: state,
        error: error,
        notify: notify,
      );
    }

    try {
      SongDetail? detail;
      if (fetch.useLyricOnlyFetch) {
        detail = await fetch.fetchLyricOnlyDetail();
        if (detail != null) {
          final normalizedLyricOnlyDetail = fetch.normalizeSongDetail(detail);
          if (!_hasDisplayableLyrics(normalizedLyricOnlyDetail)) {
            if (fetch.allowFullDetailFallback) {
              adapter.log(
                '[LyricService] 纯歌词补全未命中可展示歌词，回退完整详情: '
                '$refreshKey',
                toDeveloperPanel: true,
              );
              detail = await fetch.fetchFullDetail();
            } else {
              adapter.log(
                '[LyricService] 纯歌词补全未命中可展示歌词，不回退完整详情: '
                '$refreshKey',
                toDeveloperPanel: true,
              );
              detail = normalizedLyricOnlyDetail;
            }
          } else {
            detail = normalizedLyricOnlyDetail;
          }
        } else {
          if (fetch.allowFullDetailFallback) {
            adapter.log(
              '[LyricService] 纯歌词补全未命中，回退完整详情: $refreshKey',
              toDeveloperPanel: true,
            );
            detail = await fetch.fetchFullDetail();
          } else {
            adapter.log(
              '[LyricService] 纯歌词补全未命中，不回退完整详情: $refreshKey',
              toDeveloperPanel: true,
            );
          }
        }
      } else {
        detail = await fetch.fetchFullDetail();
      }
      if (!_isCurrent(trackKey, playbackToken)) {
        adapter.log(
          '[LyricService] 歌词结果已过期，丢弃: $refreshKey',
          toDeveloperPanel: true,
        );
        return;
      }

      final currentSong = presentation.currentSong();
      if (detail == null || currentSong == null) {
        final currentState = _resolvedLyricState(
          currentSong,
          emptyResultIsAuthoritative: fetch.emptyResultIsAuthoritative,
        );
        adapter.log(
          '[LyricService] 歌词补全未命中任何新增信息: $refreshKey',
          toDeveloperPanel: true,
        );
        await _storeResolvedLyricState(
          track: track,
          quality: quality,
          song: currentSong,
          persistEmpty: fetch.emptyResultIsAuthoritative,
          log: adapter.log,
        );
        finalize(currentState, song: currentSong);
        return;
      }

      final normalizedDetail = fetch.normalizeSongDetail(detail);
      final mergedSong = cache.mergeSupplementalSongDetail(
        currentSong,
        normalizedDetail,
      );
      final cacheRefreshSong = cache.buildCacheRefreshSongDetail(
        currentSong,
        normalizedDetail,
      );

      if (presentation.isSamePresentation(currentSong, mergedSong)) {
        final currentState = _resolvedLyricState(
          currentSong,
          emptyResultIsAuthoritative: fetch.emptyResultIsAuthoritative,
        );
        adapter.log(
          '[LyricService] 歌词补全未命中任何新增信息: $refreshKey',
          toDeveloperPanel: true,
        );
        finalize(currentState, song: currentSong);
        await _storeResolvedLyricState(
          track: track,
          quality: quality,
          song: currentSong,
          persistEmpty: fetch.emptyResultIsAuthoritative,
          log: adapter.log,
        );
        await cache.cacheSongInBackground(cacheRefreshSong);
        return;
      }

      final mergedState = _resolvedLyricState(
        mergedSong,
        emptyResultIsAuthoritative: fetch.emptyResultIsAuthoritative,
      );
      adapter.log(
        mergedState == LyricLoadState.ready
            ? '[LyricService] 歌词补全成功: $refreshKey'
            : '[LyricService] 歌词补全未命中任何新增信息: $refreshKey',
        toDeveloperPanel: true,
      );
      finalize(mergedState, song: mergedSong, notify: true);
      presentation.applyResolvedSongDetail(mergedSong);
      await _storeResolvedLyricState(
        track: track,
        quality: quality,
        song: mergedSong,
        persistEmpty: fetch.emptyResultIsAuthoritative,
        log: adapter.log,
      );
      await cache.cacheSongInBackground(cacheRefreshSong);
      presentation.refreshFloatingLyrics();
    } catch (e) {
      adapter.log(
        '[LyricService] 歌词补全失败: $refreshKey, $e',
        toDeveloperPanel: true,
      );
      finalize(LyricLoadState.failed, error: e.toString());
    } finally {
      _pendingRefreshKeys.remove(refreshKey);
      if (!finalized && _isCurrent(trackKey, playbackToken)) {
        final currentSong = presentation.currentSong();
        final fallbackState = _resolvedLyricState(currentSong);
        adapter.log(
          '[LyricService] 歌词补全完成后触发状态兜底: $refreshKey -> $fallbackState',
          toDeveloperPanel: true,
        );
        _publish(
          trackKey: trackKey,
          playbackToken: playbackToken,
          song: currentSong,
          state: fallbackState,
          error: null,
        );
      }
    }
  }

  Future<void> prefetchLyrics({
    required Track track,
    required String quality,
    required String refreshKey,
    required LyricPrefetchAdapter adapter,
  }) async {
    final prefetchKey = 'prefetch_$refreshKey';
    final cachedResult = await _repository.lookup(
      track: track,
      quality: quality,
      currentSong: null,
      log: adapter.log,
    );
    final cached = cachedResult != null && _isUsableLookupResult(cachedResult)
        ? cachedResult
        : null;
    if (cachedResult != null && cached == null) {
      adapter.log(
        '[LyricService] 歌词缓存命中但内容不可展示，继续预取: $refreshKey',
        toDeveloperPanel: true,
      );
    }
    if (cached != null && cached.skipRemote) {
      adapter.log(
        '[LyricService] 歌词缓存命中: ${cached.category} key=$refreshKey',
        toDeveloperPanel: true,
      );
      return;
    }

    if (_pendingRefreshKeys.contains(prefetchKey)) {
      adapter.log('[LyricService] 跳过重复歌词预取: $refreshKey');
      return;
    }

    _pendingRefreshKeys.add(prefetchKey);
    adapter.log('[LyricService] 歌词预取开始: $refreshKey', toDeveloperPanel: true);

    try {
      final detail = await adapter.fetchLyricOnlyDetail();
      if (detail == null) {
        adapter.log(
          '[LyricService] 歌词预取未命中: $refreshKey',
          toDeveloperPanel: true,
        );
        return;
      }

      final normalizedDetail = adapter.normalizeSongDetail(detail);
      if (_hasDisplayableLyrics(normalizedDetail)) {
        adapter.log(
          '[LyricService] 歌词预取成功: $refreshKey',
          toDeveloperPanel: true,
        );
        await _repository.storeReady(
          track: track,
          quality: quality,
          song: normalizedDetail,
          log: adapter.log,
        );
        return;
      }

      if (adapter.hasAnyLyricPayload(normalizedDetail)) {
        adapter.log(
          '[LyricService] 歌词预取拿到不可展示 payload，忽略缓存: $refreshKey',
          toDeveloperPanel: true,
        );
        return;
      }
      adapter.log(
        '[LyricService] 歌词预取未命中: $refreshKey',
        toDeveloperPanel: true,
      );
    } catch (e) {
      adapter.log(
        '[LyricService] 歌词预取失败: $refreshKey, $e',
        toDeveloperPanel: true,
      );
    } finally {
      _pendingRefreshKeys.remove(prefetchKey);
    }
  }

  SongDetail? _displayableSongOrNull(SongDetail? song) {
    if (song == null) {
      return null;
    }
    return _hasDisplayableLyrics(song) ? song : null;
  }

  bool _isUsableLookupResult(LyricLookupResult result) {
    if (result.state != LyricLoadState.ready) {
      return true;
    }
    final song = result.song;
    return song != null && _hasDisplayableLyrics(song);
  }

  LyricLoadState _resolvedLyricState(
    SongDetail? song, {
    bool emptyResultIsAuthoritative = false,
  }) {
    if (song != null && _hasDisplayableLyrics(song)) {
      return LyricLoadState.ready;
    }
    return emptyResultIsAuthoritative
        ? LyricLoadState.empty
        : LyricLoadState.transientMiss;
  }

  Future<void> _storeResolvedLyricState({
    required Track track,
    required String quality,
    required SongDetail? song,
    required bool persistEmpty,
    required LyricRepositoryLogFn log,
  }) async {
    if (song != null && _hasDisplayableLyrics(song)) {
      await _repository.storeReady(
        track: track,
        quality: quality,
        song: song,
        log: log,
      );
      return;
    }
    if (!persistEmpty) return;
    await _repository.storeConfirmedEmpty(
      track: track,
      quality: quality,
      currentSong: song,
      log: log,
    );
  }

  String _trackKey(Track track) => '${track.source.name}_${track.id}';

  bool _isCurrent(String trackKey, int playbackToken) {
    return _currentTrackKey == trackKey &&
        _currentPlaybackToken == playbackToken;
  }

  void _publish({
    required String trackKey,
    required int playbackToken,
    SongDetail? song,
    required LyricLoadState state,
    String? error,
    bool notify = true,
  }) {
    final lines = song == null ? const <LyricLine>[] : _parseLines(song);
    final normalizedState = _normalizeState(state, song, lines);
    final normalizedError = normalizedState == LyricLoadState.failed
        ? error
        : null;
    final nextSnapshot = LyricSnapshot(
      trackKey: trackKey,
      playbackToken: playbackToken,
      state: normalizedState,
      lines: lines,
      lyric: song?.lyric ?? '',
      tlyric: song?.tlyric ?? '',
      yrc: song?.yrc ?? '',
      ytlrc: song?.ytlrc ?? '',
      qrc: song?.qrc ?? '',
      qrcTrans: song?.qrcTrans ?? '',
      updatedAt: DateTime.now(),
      error: normalizedError,
    );

    final changed =
        _currentTrackKey != trackKey ||
        _currentPlaybackToken != playbackToken ||
        _currentSnapshot?.signature != nextSnapshot.signature ||
        _currentError != normalizedError ||
        _currentState != normalizedState;

    _currentTrackKey = trackKey;
    _currentPlaybackToken = playbackToken;
    _currentState = normalizedState;
    _currentError = normalizedError;
    _currentSnapshot = nextSnapshot;

    if (notify && changed) {
      notifyListeners();
    }
  }

  List<LyricLine> _parseLines(SongDetail song) {
    try {
      List<LyricLine> parsed;
      switch (song.source) {
        case MusicSource.qq:
          parsed = LyricParser.parseQQLyric(
            song.lyric,
            translation: song.tlyric.isNotEmpty ? song.tlyric : null,
            qrcLyric: song.qrc.isNotEmpty ? song.qrc : null,
            qrcTranslation: song.qrcTrans.isNotEmpty ? song.qrcTrans : null,
          );
          break;
        case MusicSource.kugou:
          parsed = LyricParser.parseKugouLyric(
            song.lyric,
            translation: song.tlyric.isNotEmpty ? song.tlyric : null,
          );
          break;
        case MusicSource.netease:
        case MusicSource.local:
        default:
          parsed = LyricParser.parseNeteaseLyric(
            song.lyric,
            translation: song.tlyric.isNotEmpty ? song.tlyric : null,
            yrcLyric: song.yrc.isNotEmpty ? song.yrc : null,
            yrcTranslation: song.ytlrc.isNotEmpty ? song.ytlrc : null,
          );
          break;
      }
      if (parsed.isNotEmpty) {
        return parsed;
      }
      return _parsePlainTextFallback(song);
    } catch (_) {
      return _parsePlainTextFallback(song);
    }
  }

  List<LyricLine> _parsePlainTextFallback(SongDetail song) {
    final primaryPayload = song.lyric.isNotEmpty
        ? song.lyric
        : (song.qrc.isNotEmpty ? song.qrc : song.yrc);
    if (primaryPayload.isEmpty) {
      return const <LyricLine>[];
    }

    final textLines = _extractPlainLines(primaryPayload);
    if (textLines.isEmpty) {
      return const <LyricLine>[];
    }

    final translationPayload = song.tlyric.isNotEmpty
        ? song.tlyric
        : (song.qrcTrans.isNotEmpty ? song.qrcTrans : song.ytlrc);
    final translationLines = _extractPlainLines(translationPayload);

    return List<LyricLine>.generate(textLines.length, (index) {
      final translation = index < translationLines.length
          ? translationLines[index]
          : null;
      return LyricLine(
        startTime: Duration(
          milliseconds: _plainTextFallbackLineInterval.inMilliseconds * index,
        ),
        text: textLines[index],
        translation: translation != null && translation.isNotEmpty
            ? translation
            : null,
      );
    });
  }

  List<String> _extractPlainLines(String payload) {
    if (payload.isEmpty) {
      return const <String>[];
    }
    return payload
        .split('\n')
        .map(
          (line) => line
              .replaceAll(_plainLyricBracketTagPattern, '')
              .replaceAll(_plainLyricParensTriplePattern, '')
              .replaceAll(_plainLyricParensDoublePattern, '')
              .replaceAll(_plainLyricAngleTriplePattern, '')
              .trim(),
        )
        .where((line) => line.isNotEmpty)
        .toList(growable: false);
  }

  LyricLoadState _normalizeState(
    LyricLoadState state,
    SongDetail? song,
    List<LyricLine> lines,
  ) {
    switch (state) {
      case LyricLoadState.loading:
      case LyricLoadState.failed:
      case LyricLoadState.empty:
      case LyricLoadState.transientMiss:
        return state;
      case LyricLoadState.ready:
        if (lines.isNotEmpty) return LyricLoadState.ready;
        return LyricLoadState.transientMiss;
      case LyricLoadState.idle:
        if (song == null) return LyricLoadState.idle;
        if (lines.isNotEmpty) return LyricLoadState.ready;
        return _hasPayload(song)
            ? LyricLoadState.transientMiss
            : LyricLoadState.idle;
    }
  }

  bool _hasDisplayableLyrics(SongDetail song) {
    return _parseLines(song).isNotEmpty;
  }

  bool _hasPayload(SongDetail song) {
    return song.lyric.isNotEmpty ||
        song.tlyric.isNotEmpty ||
        song.yrc.isNotEmpty ||
        song.ytlrc.isNotEmpty ||
        song.qrc.isNotEmpty ||
        song.qrcTrans.isNotEmpty;
  }
}
