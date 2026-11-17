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
import '../resolution_request.dart';
import '../structured_log_service.dart';
import '../audio_source_service.dart';
import '../automatic_recommendation_router.dart';

class TrackResolutionResult {
  final SongDetail? detail;
  final LxRuntimeFailure? lxFailure;
  final bool timedOut;
  final bool isL1CacheHit;
  final bool cancelled;

  const TrackResolutionResult({
    required this.detail,
    this.lxFailure,
    this.timedOut = false,
    this.isL1CacheHit = false,
    this.cancelled = false,
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
    cancelled: cancelled,
  );
}

class _ResolvedCacheEntry {
  final TrackResolutionResult result;
  final DateTime expiresAt;
  final int? durationMs;
  final LxMusicMetadata lxMetadata;

  _ResolvedCacheEntry({
    required this.result,
    required this.expiresAt,
    this.durationMs,
    this.lxMetadata = const LxMusicMetadata(),
  });

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
  final DateTime requestDeadline;
  final Future<TrackResolutionResult> future;
  final ResolutionRequest request;
  final int? durationMs;
  final LxMusicMetadata lxMetadata;
  int waiters = 0;
  _RequestState state = _RequestState.running;

  _RequestEntry({
    required this.hardDeadline,
    required this.requestDeadline,
    required this.future,
    required this.request,
    this.durationMs,
    this.lxMetadata = const LxMusicMetadata(),
  });

  bool isReusableFor(
    Duration callerTimeout, {
    int? durationMs,
    LxMusicMetadata lxMetadata = const LxMusicMetadata(),
  }) {
    final now = DateTime.now();
    return (durationMs == null || this.durationMs == durationMs) &&
        (lxMetadata.isEmpty ||
            this.lxMetadata.fingerprint == lxMetadata.fingerprint) &&
        state == _RequestState.running &&
        now.isBefore(hardDeadline) &&
        now.isBefore(requestDeadline) &&
        !request.isCancelled;
  }
}

typedef SongDetailFetcher = Future<SongDetail?> Function({
  required dynamic songId,
  required AudioQuality quality,
  required MusicSource source,
  required String title,
  required String artist,
  String album,
  int? durationMs,
  LxMusicMetadata lxMetadata,
  required TrackSourceIds sourceIds,
  required bool fetchLyrics,
  void Function(LxRuntimeFailure? failure)? onLxFailure,
  Duration? requestTimeout,
});

class TrackResolver {
  TrackResolver({
    SongDetailFetcher? fetcher,
    AutomaticRoute? Function(MusicSource)? automaticRouteFor,
    this.hardTimeout = const Duration(seconds: 18),
    this.maxResolvedCacheEntries = defaultMaxResolvedCacheEntries,
    this.resolvedCacheTtl = defaultResolvedCacheTtl,
  }) : _fetcher = fetcher ?? MusicService().fetchSongDetail,
       _automaticRouteFor =
           automaticRouteFor ?? AudioSourceService().automaticRouteFor;

  static const int defaultMaxResolvedCacheEntries = 30;
  static const Duration defaultResolvedCacheTtl = Duration(minutes: 5);

  final SongDetailFetcher _fetcher;
  final AutomaticRoute? Function(MusicSource) _automaticRouteFor;
  final Duration hardTimeout;
  final int maxResolvedCacheEntries;
  final Duration resolvedCacheTtl;
  final Map<String, _RequestEntry> _pending = {};
  int _cacheEpoch = 0;
  final LinkedHashMap<String, _ResolvedCacheEntry> _resolvedCache =
      LinkedHashMap<String, _ResolvedCacheEntry>();

  int get resolvedCacheSize => _resolvedCache.length;

  TrackResolutionResult? _getResolvedCache(
    String key, {
    int? durationMs,
    LxMusicMetadata lxMetadata = const LxMusicMetadata(),
  }) {
    final entry = _resolvedCache.remove(key);
    if (entry == null) return null;
    if (entry.isExpired ||
        (durationMs != null && entry.durationMs != durationMs) ||
        (!lxMetadata.isEmpty &&
            entry.lxMetadata.fingerprint != lxMetadata.fingerprint)) {
      return null;
    }
    _resolvedCache[key] = entry;
    return entry.result.copyWith(isL1CacheHit: true);
  }

  void _putResolvedCache(
    String key,
    TrackResolutionResult result, {
    int? durationMs,
    LxMusicMetadata lxMetadata = const LxMusicMetadata(),
  }) {
    if (!result.isPlayable) return;
    if (maxResolvedCacheEntries <= 0) return;
    _resolvedCache.remove(key);
    while (_resolvedCache.length >= maxResolvedCacheEntries) {
      _resolvedCache.remove(_resolvedCache.keys.first);
    }
    _resolvedCache[key] = _ResolvedCacheEntry(
      result: result.copyWith(isL1CacheHit: false),
      durationMs: durationMs,
      lxMetadata: lxMetadata,
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

  /// Lookup only: never joins a pending task or starts a network request.
  TrackResolutionResult? peekResolved({
    required dynamic songId,
    required AudioQuality quality,
    required MusicSource source,
    bool fetchLyrics = false,
    int? durationMs,
    LxMusicMetadata lxMetadata = const LxMusicMetadata(),
    String? resolverFingerprint,
  }) {
    final cached = _getResolvedCache(
      _requestKey(
        songId,
        source,
        quality,
        fetchLyrics,
        resolverFingerprint: resolverFingerprint,
      ),
      durationMs: durationMs,
      lxMetadata: lxMetadata,
    );
    if (cached != null || fetchLyrics) return cached;
    return _getResolvedCache(
      _requestKey(
        songId,
        source,
        quality,
        true,
        resolverFingerprint: resolverFingerprint,
      ),
      durationMs: durationMs,
      lxMetadata: lxMetadata,
    );
  }

  Future<TrackResolutionResult> resolve({
    required dynamic songId,
    required AudioQuality quality,
    required MusicSource source,
    required String title,
    required String artist,
    String album = '',
    int? durationMs,
    LxMusicMetadata lxMetadata = const LxMusicMetadata(),
    TrackSourceIds sourceIds = const TrackSourceIds(),
    required Duration timeout,
    bool fetchLyrics = true,
    String? resolverFingerprint,
    bool skipMemoryCache = false,
    bool retryExpiredSharedRequest = true,
    bool Function()? acceptResult,
  }) async {
    final automaticRoute = _automaticRouteFor(source);
    if (automaticRoute != null) {
      resolverFingerprint = automaticRoute.fingerprint;
      quality = AudioQuality.standard;
    }
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
      final cached = peekResolved(
        songId: songId,
        quality: quality,
        source: source,
        fetchLyrics: fetchLyrics,
        durationMs: durationMs,
        lxMetadata: lxMetadata,
        resolverFingerprint: resolverFingerprint,
      );
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
    final clock = Stopwatch()..start();
    final adopted =
        _pending[key]?.isReusableFor(
          timeout,
          durationMs: durationMs,
          lxMetadata: lxMetadata,
        ) ??
        false;
    final request = _acquire(
      key: key,
      songId: songId,
      quality: quality,
      source: source,
      title: title,
      artist: artist,
      album: album,
      durationMs: durationMs,
      lxMetadata: lxMetadata,
      sourceIds: sourceIds,
      fetchLyrics: fetchLyrics,
      forceNew: skipMemoryCache,
      requestTimeout: timeout,
      automaticRoute: automaticRoute,
    );
    final entry = _pending[key];
    if (entry != null) entry.waiters++;
    try {
      var result = await request.timeout(
        timeout,
        onTimeout: () {
          final entry = _pending[key];
          if (entry != null &&
              identical(entry.future, request) &&
              entry.waiters <= 1) {
            entry.request.failure = const LxRuntimeFailure(
              kind: LxRuntimeFailureKind.timeout,
              message: '获取歌曲详情超时',
            );
            entry.request.cancel();
          }
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
      // A foreground adopter may outlive the preload's transport deadline.
      // Retry once using only its remaining original budget.
      final remaining = timeout - clock.elapsed;
      if (retryExpiredSharedRequest &&
          adopted &&
          (result.timedOut ||
              result.lxFailure?.kind == LxRuntimeFailureKind.timeout) &&
          remaining > Duration.zero &&
          (acceptResult?.call() ?? true) &&
          cacheEpoch == _cacheEpoch) {
        result = await resolve(
          songId: songId,
          quality: quality,
          source: source,
          title: title,
          artist: artist,
          album: album,
          durationMs: durationMs,
          lxMetadata: lxMetadata,
          sourceIds: sourceIds,
          timeout: remaining,
          fetchLyrics: fetchLyrics,
          resolverFingerprint: resolverFingerprint,
          acceptResult: acceptResult,
          retryExpiredSharedRequest: false,
        );
      }
      trace.mark(
        result.cancelled
            ? 'cancelled'
            : result.isPlayable
            ? 'success'
            : 'unplayable',
        level: result.cancelled || result.isPlayable
            ? LogLevel.info
            : LogLevel.warning,
        fields: {
          'timed_out': result.timedOut,
          'failure_kind': result.lxFailure?.kind.name,
        },
      );
      if (result.isPlayable && (acceptResult?.call() ?? true)) {
        if (cacheEpoch == _cacheEpoch && entry?.request.isCancelled != true) {
          _putResolvedCache(
            key,
            result,
            durationMs: durationMs,
            lxMetadata: lxMetadata,
          );
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
    } finally {
      if (entry != null) entry.waiters--;
    }
  }

  Future<TrackResolutionResult> _acquire({
    AutomaticRoute? automaticRoute,
    required String key,
    required dynamic songId,
    required AudioQuality quality,
    required MusicSource source,
    required String title,
    required String artist,
    String album = '',
    int? durationMs,
    LxMusicMetadata lxMetadata = const LxMusicMetadata(),
    required TrackSourceIds sourceIds,
    required bool fetchLyrics,
    bool forceNew = false,
    required Duration requestTimeout,
  }) {
    final effectiveRequestTimeout = requestTimeout < hardTimeout
        ? requestTimeout
        : hardTimeout;
    final existing = _pending[key];
    if (!forceNew &&
        (existing?.isReusableFor(
              effectiveRequestTimeout,
              durationMs: durationMs,
              lxMetadata: lxMetadata,
            ) ??
            false)) {
      return existing!.future;
    }
    if (existing != null) {
      existing.request.cancel();
      existing.state = _RequestState.expired;
      _pending.remove(key);
    }

    final completer = Completer<TrackResolutionResult>();
    late final _RequestEntry entry;
    final requestStartedAt = DateTime.now();
    final ownership = ResolutionRequest(track: '${source.name}_$songId');
    final automaticLease = automaticRoute?.acquire();
    entry = _RequestEntry(
      hardDeadline: requestStartedAt.add(hardTimeout),
      requestDeadline: requestStartedAt.add(effectiveRequestTimeout),
      future: completer.future,
      request: ownership,
      durationMs: durationMs,
      lxMetadata: lxMetadata,
    );
    _pending[key] = entry;

    unawaited(() async {
      LxRuntimeFailure? requestFailure;
      var hardTimedOut = false;
      try {
        final detail = await ownership
            .bind(
              Future<SongDetail?>.value(
                ownership.run(() {
                  Future<SongDetail?> fetch() => _fetcher(
                    songId: songId,
                    quality: quality,
                    source: source,
                    title: title,
                    artist: artist,
                    album: album,
                    durationMs: durationMs,
                    lxMetadata: lxMetadata,
                    sourceIds: sourceIds,
                    fetchLyrics: fetchLyrics,
                    onLxFailure: (failure) => requestFailure = failure,
                    requestTimeout: effectiveRequestTimeout,
                  );
                  final work = Future<SongDetail?>.sync(
                    () => automaticLease == null
                        ? fetch()
                        : automaticLease.run(fetch),
                  );
                  // The transport may finish after its waiter times out. Keep
                  // the context until the actual resolver work has settled.
                  return work.whenComplete(() => automaticLease?.release());
                }),
              ),
            )
            .timeout(
              effectiveRequestTimeout,
              onTimeout: () {
                hardTimedOut = true;
                ownership.failure = const LxRuntimeFailure(
                  kind: LxRuntimeFailureKind.timeout,
                  message: '歌曲详情请求超时',
                );
                ownership.cancel();
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
      } on ResolutionCancelled {
        entry.state = _RequestState.expired;
        if (!completer.isCompleted) {
          completer.complete(
            TrackResolutionResult(
              detail: null,
              cancelled:
                  ownership.failure?.kind != LxRuntimeFailureKind.timeout,
              timedOut: ownership.failure?.kind == LxRuntimeFailureKind.timeout,
              lxFailure: ownership.failure,
            ),
          );
        }
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
    cancelPending();
    _pending.clear();
    _resolvedCache.clear();
  }

  void cancelPending({String? exceptKey}) {
    for (final entry in _pending.entries.toList()) {
      if (entry.key == exceptKey) continue;
      entry.value.request.cancel();
      if (identical(_pending[entry.key], entry.value)) {
        _pending.remove(entry.key);
      }
    }
  }

  void prioritize({
    required dynamic songId,
    required MusicSource source,
    required AudioQuality quality,
    String? resolverFingerprint,
  }) {
    cancelPending(
      exceptKey: _requestKey(
        songId,
        source,
        quality,
        false,
        resolverFingerprint: resolverFingerprint,
      ),
    );
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
  durationMs: track.durationMs,
  sourceIds: track.sourceIds,
  lxMetadata: track.lxMetadata,
);

bool needsCachedMetadataRefresh(CacheMetadata metadata) =>
    metadata.songName.isEmpty ||
    metadata.artists.isEmpty ||
    metadata.album.isEmpty ||
    metadata.picUrl.isEmpty ||
    metadata.originalUrl.isEmpty;
