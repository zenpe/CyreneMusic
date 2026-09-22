import 'dart:async';
import 'dart:collection';
import 'dart:io';

import '../../models/song_detail.dart';
import '../../models/track.dart';
import '../../utils/metadata_reader.dart';
import '../cache_service.dart';
import '../local_library_service.dart';
import '../lx_runtime_interface.dart';
import '../music_service.dart';
import '../structured_log_service.dart';

class TrackResolutionResult {
  final SongDetail? detail;
  final LxRuntimeFailure? lxFailure;
  final bool timedOut;
  final bool isL1CacheHit;

  const TrackResolutionResult({
    required this.detail,
    this.lxFailure,
    this.timedOut = false,
    this.isL1CacheHit = false,
  });

  bool get isPlayable => detail != null && detail!.url.isNotEmpty;

  TrackResolutionResult copyWith({
    SongDetail? detail,
    LxRuntimeFailure? lxFailure,
    bool? timedOut,
    bool? isL1CacheHit,
  }) => TrackResolutionResult(
    detail: detail ?? this.detail,
    lxFailure: lxFailure ?? this.lxFailure,
    timedOut: timedOut ?? this.timedOut,
    isL1CacheHit: isL1CacheHit ?? this.isL1CacheHit,
  );
}

class _ResolvedCacheEntry {
  final TrackResolutionResult result;
  final DateTime expiresAt;

  _ResolvedCacheEntry({required this.result, required this.expiresAt});

  bool get isExpired => DateTime.now().isAfter(expiresAt);
}

class TrackLookupResult {
  final SongDetail? resolvedDetail;
  final CachedAudioFileInfo? cacheInfo;
  final bool isCached;
  final bool localFileMissing;
  final bool shouldRefreshCachedMetadata;

  const TrackLookupResult({
    required this.resolvedDetail,
    required this.cacheInfo,
    required this.isCached,
    required this.localFileMissing,
    required this.shouldRefreshCachedMetadata,
  });
}

enum _RequestState { running, completed, failed, expired }

class _RequestEntry {
  final DateTime hardDeadline;
  final Future<TrackResolutionResult> future;
  _RequestState state = _RequestState.running;

  _RequestEntry({required this.hardDeadline, required this.future});

  bool get isReusable =>
      state == _RequestState.running && DateTime.now().isBefore(hardDeadline);
}

typedef SongDetailFetcher =
    Future<SongDetail?> Function({
      required dynamic songId,
      required AudioQuality quality,
      required MusicSource source,
      required String title,
      required String artist,
      required bool fetchLyrics,
      void Function(LxRuntimeFailure? failure)? onLxFailure,
    });

class TrackResolver {
  TrackResolver({
    SongDetailFetcher? fetcher,
    this.hardTimeout = const Duration(seconds: 18),
    this.maxResolvedCacheEntries = defaultMaxResolvedCacheEntries,
    this.resolvedCacheTtl = defaultResolvedCacheTtl,
  }) : _fetcher = fetcher ?? MusicService().fetchSongDetail;

  static const int defaultMaxResolvedCacheEntries = 30;
  static const Duration defaultResolvedCacheTtl = Duration(minutes: 5);

  final SongDetailFetcher _fetcher;
  final Duration hardTimeout;
  final int maxResolvedCacheEntries;
  final Duration resolvedCacheTtl;
  final Map<String, _RequestEntry> _pending = {};
  int _cacheEpoch = 0;
  final LinkedHashMap<String, _ResolvedCacheEntry> _resolvedCache =
      LinkedHashMap<String, _ResolvedCacheEntry>();

  int get resolvedCacheSize => _resolvedCache.length;

  TrackResolutionResult? _getResolvedCache(String key) {
    final entry = _resolvedCache.remove(key);
    if (entry == null) return null;
    if (entry.isExpired) return null;
    _resolvedCache[key] = entry;
    return entry.result.copyWith(isL1CacheHit: true);
  }

  void _putResolvedCache(String key, TrackResolutionResult result) {
    if (!result.isPlayable) return;
    if (maxResolvedCacheEntries <= 0) return;
    _resolvedCache.remove(key);
    while (_resolvedCache.length >= maxResolvedCacheEntries) {
      _resolvedCache.remove(_resolvedCache.keys.first);
    }
    _resolvedCache[key] = _ResolvedCacheEntry(
      result: result.copyWith(isL1CacheHit: false),
      expiresAt: DateTime.now().add(resolvedCacheTtl),
    );
  }

  Future<TrackLookupResult> lookupLocalOrCache({
    required Track track,
    required String quality,
    String? resolverFingerprint,
    bool skipCache = false,
  }) async {
    final cacheInfo = skipCache
        ? null
        : await CacheService().getCachedAudioFileInfo(track, quality: quality);
    final shouldRefresh =
        cacheInfo != null && needsCachedMetadataRefresh(cacheInfo.metadata);

    if (cacheInfo != null && cacheInfo.metadata.quality == quality) {
      return TrackLookupResult(
        resolvedDetail: buildCachedSongDetail(
          track,
          cacheInfo.metadata,
          playbackUrl: cacheInfo.metadata.originalUrl.isNotEmpty
              ? cacheInfo.metadata.originalUrl
              : cacheInfo.filePath,
        ),
        cacheInfo: cacheInfo,
        isCached: true,
        localFileMissing: false,
        shouldRefreshCachedMetadata: shouldRefresh,
      );
    }

    if (track.source == MusicSource.local) {
      final filePath = track.id is String ? track.id as String : '';
      if (filePath.isEmpty || !(await File(filePath).exists())) {
        return TrackLookupResult(
          resolvedDetail: null,
          cacheInfo: cacheInfo,
          isCached: cacheInfo != null,
          localFileMissing: true,
          shouldRefreshCachedMetadata: shouldRefresh,
        );
      }
      var lyric = LocalLibraryService().getLyricByTrackId(filePath);
      if (lyric.isEmpty) {
        final embedded = await MetadataReader.extractLyrics(filePath);
        if (embedded != null && embedded.isNotEmpty) lyric = embedded;
      }
      return TrackLookupResult(
        resolvedDetail: SongDetail(
          id: filePath,
          name: track.name,
          pic: track.picUrl,
          arName: track.artists,
          alName: track.album,
          level: 'local',
          size: '',
          url: filePath,
          lyric: lyric,
          tlyric: '',
          source: MusicSource.local,
        ),
        cacheInfo: null,
        isCached: false,
        localFileMissing: false,
        shouldRefreshCachedMetadata: false,
      );
    }

    return TrackLookupResult(
      resolvedDetail: null,
      cacheInfo: cacheInfo,
      isCached: cacheInfo != null,
      localFileMissing: false,
      shouldRefreshCachedMetadata: shouldRefresh,
    );
  }

  Future<TrackResolutionResult> resolve({
    required dynamic songId,
    required AudioQuality quality,
    required MusicSource source,
    required String title,
    required String artist,
    required Duration timeout,
    bool fetchLyrics = true,
    String? resolverFingerprint,
    bool skipMemoryCache = false,
  }) async {
    if (skipMemoryCache) {
      // A forced refresh must supersede any older in-flight request for the
      // same key, otherwise that request can repopulate the cache later.
      _cacheEpoch++;
    }

    final key = _requestKey(
      songId,
      source,
      quality,
      fetchLyrics,
      resolverFingerprint: resolverFingerprint,
    );

    if (!skipMemoryCache) {
      var cached = _getResolvedCache(key);
      if (cached == null && !fetchLyrics) {
        // 若当前不需要歌词，已缓存的带歌词解析结果同样有效
        final keyWithLyrics = _requestKey(
          songId,
          source,
          quality,
          true,
          resolverFingerprint: resolverFingerprint,
        );
        cached = _getResolvedCache(keyWithLyrics);
      }
      if (cached != null) {
        return cached;
      }
    }

    final trace = OperationTrace(
      'playback.resolve',
      context: {
        'track_id': songId.toString(),
        'source': source.name,
        'quality': quality.value,
        'lyrics': fetchLyrics,
        'resolver_fp': resolverFingerprint,
      },
    );
    final cacheEpoch = _cacheEpoch;
    final request = _acquire(
      key: key,
      songId: songId,
      quality: quality,
      source: source,
      title: title,
      artist: artist,
      fetchLyrics: fetchLyrics,
      forceNew: skipMemoryCache,
    );
    try {
      final result = await request.timeout(
        timeout,
        onTimeout: () {
          trace.mark('timeout', level: LogLevel.warning);
          return const TrackResolutionResult(
            detail: null,
            lxFailure: LxRuntimeFailure(
              kind: LxRuntimeFailureKind.timeout,
              message: '获取歌曲详情超时',
            ),
            timedOut: true,
          );
        },
      );
      trace.mark(
        result.isPlayable ? 'success' : 'unplayable',
        level: result.isPlayable ? LogLevel.info : LogLevel.warning,
        fields: {
          'timed_out': result.timedOut,
          'failure_kind': result.lxFailure?.kind.name,
        },
      );
      if (result.isPlayable) {
        if (cacheEpoch == _cacheEpoch) {
          _putResolvedCache(key, result);
        }
      }
      return result;
    } on AudioSourceNotConfiguredException {
      trace.mark('source_not_configured', level: LogLevel.warning);
      rethrow;
    } catch (error) {
      trace.mark('failed', level: LogLevel.error, error: error);
      return TrackResolutionResult(
        detail: null,
        lxFailure: classifyLxRuntimeFailure(error),
      );
    }
  }

  Future<TrackResolutionResult> _acquire({
    required String key,
    required dynamic songId,
    required AudioQuality quality,
    required MusicSource source,
    required String title,
    required String artist,
    required bool fetchLyrics,
    bool forceNew = false,
  }) {
    final existing = _pending[key];
    if (!forceNew && (existing?.isReusable ?? false)) {
      return existing!.future;
    }
    if (existing != null) {
      existing.state = _RequestState.expired;
      _pending.remove(key);
    }

    final completer = Completer<TrackResolutionResult>();
    late final _RequestEntry entry;
    entry = _RequestEntry(
      hardDeadline: DateTime.now().add(hardTimeout),
      future: completer.future,
    );
    _pending[key] = entry;

    unawaited(() async {
      LxRuntimeFailure? requestFailure;
      var hardTimedOut = false;
      try {
        final detail =
            await Future<SongDetail?>.value(
              _fetcher(
                songId: songId,
                quality: quality,
                source: source,
                title: title,
                artist: artist,
                fetchLyrics: fetchLyrics,
                onLxFailure: (failure) => requestFailure = failure,
              ),
            ).timeout(
              hardTimeout,
              onTimeout: () {
                hardTimedOut = true;
                return null;
              },
            );
        entry.state = hardTimedOut
            ? _RequestState.expired
            : _RequestState.completed;
        if (!completer.isCompleted) {
          completer.complete(
            TrackResolutionResult(
              detail: detail,
              lxFailure: hardTimedOut
                  ? const LxRuntimeFailure(
                      kind: LxRuntimeFailureKind.timeout,
                      message: '歌曲详情请求超时',
                    )
                  : requestFailure,
              timedOut: hardTimedOut,
            ),
          );
        }
      } on AudioSourceNotConfiguredException catch (error, stack) {
        entry.state = _RequestState.failed;
        if (!completer.isCompleted) completer.completeError(error, stack);
      } catch (error) {
        entry.state = _RequestState.failed;
        if (!completer.isCompleted) {
          completer.complete(
            TrackResolutionResult(
              detail: null,
              lxFailure: requestFailure ?? classifyLxRuntimeFailure(error),
            ),
          );
        }
      } finally {
        if (identical(_pending[key], entry)) _pending.remove(key);
      }
    }());

    return entry.future;
  }

  String _requestKey(
    dynamic songId,
    MusicSource source,
    AudioQuality quality,
    bool fetchLyrics, {
    String? resolverFingerprint,
  }) {
    final base = '${source.name}:$songId:${quality.value}:lyrics=$fetchLyrics';
    return resolverFingerprint != null && resolverFingerprint.isNotEmpty
        ? '$base:rf=$resolverFingerprint'
        : base;
  }

  void invalidateSong(
    dynamic songId,
    MusicSource source, {
    AudioQuality? quality,
    String? resolverFingerprint,
  }) {
    _cacheEpoch++;
    if (quality != null) {
      if (resolverFingerprint == null || resolverFingerprint.isEmpty) {
        final qualityPrefix = '${source.name}:$songId:${quality.value}:';
        _resolvedCache.removeWhere((key, _) => key.startsWith(qualityPrefix));
        return;
      }
      for (final fetchLyrics in [false, true]) {
        final key = _requestKey(
          songId,
          source,
          quality,
          fetchLyrics,
          resolverFingerprint: resolverFingerprint,
        );
        _resolvedCache.remove(key);
      }
    } else {
      final prefix = '${source.name}:$songId:';
      _resolvedCache.removeWhere((k, _) => k.startsWith(prefix));
    }
  }

  void invalidateTrack(
    Track track, {
    AudioQuality? quality,
    String? resolverFingerprint,
  }) {
    invalidateSong(
      track.id,
      track.source,
      quality: quality,
      resolverFingerprint: resolverFingerprint,
    );
  }

  void invalidateKey(String key) {
    _cacheEpoch++;
    _resolvedCache.remove(key);
  }

  void clear() {
    _cacheEpoch++;
    _pending.clear();
    _resolvedCache.clear();
  }
}

SongDetail buildCachedSongDetail(
  Track track,
  CacheMetadata metadata, {
  required String playbackUrl,
}) => SongDetail(
  id: track.id,
  name: metadata.songName.isNotEmpty ? metadata.songName : track.name,
  url: playbackUrl,
  pic: metadata.picUrl,
  arName: metadata.artists,
  alName: metadata.album,
  level: metadata.quality,
  size: metadata.fileSize.toString(),
  lyric: '',
  tlyric: '',
  source: track.source,
);

bool needsCachedMetadataRefresh(CacheMetadata metadata) =>
    metadata.songName.isEmpty ||
    metadata.artists.isEmpty ||
    metadata.album.isEmpty ||
    metadata.picUrl.isEmpty ||
    metadata.originalUrl.isEmpty;
