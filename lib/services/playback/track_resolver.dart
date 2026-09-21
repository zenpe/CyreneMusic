import 'dart:async';
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

  const TrackResolutionResult({
    required this.detail,
    this.lxFailure,
    this.timedOut = false,
  });

  bool get isPlayable => detail != null && detail!.url.isNotEmpty;
}

class TrackLookupResult {
  final SongDetail? resolvedDetail;
  final CyreneFileInfo? cacheInfo;
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
  }) : _fetcher = fetcher ?? MusicService().fetchSongDetail;

  final SongDetailFetcher _fetcher;
  final Duration hardTimeout;
  final Map<String, _RequestEntry> _pending = {};

  Future<TrackLookupResult> lookupLocalOrCache({
    required Track track,
    required String quality,
    String? resolverFingerprint,
    bool skipCache = false,
  }) async {
    final cacheInfo = skipCache
        ? null
        : await CacheService().getCyreneFileInfo(
            track,
            quality: quality,
            resolverFingerprint: resolverFingerprint,
          );
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
  }) async {
    final trace = OperationTrace(
      'playback.resolve',
      context: {
        'track_id': songId.toString(),
        'source': source.name,
        'quality': quality.value,
        'lyrics': fetchLyrics,
      },
    );
    final key = _requestKey(songId, source, quality, fetchLyrics);
    final request = _acquire(
      key: key,
      songId: songId,
      quality: quality,
      source: source,
      title: title,
      artist: artist,
      fetchLyrics: fetchLyrics,
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
  }) {
    final existing = _pending[key];
    if (existing?.isReusable ?? false) return existing!.future;
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
            await _fetcher(
              songId: songId,
              quality: quality,
              source: source,
              title: title,
              artist: artist,
              fetchLyrics: fetchLyrics,
              onLxFailure: (failure) => requestFailure = failure,
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
    bool fetchLyrics,
  ) => '${source.name}:$songId:${quality.value}:lyrics=$fetchLyrics';

  void clear() => _pending.clear();
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
  lyric: metadata.lyric,
  tlyric: metadata.tlyric,
  yrc: metadata.yrc,
  ytlrc: metadata.ytlrc,
  qrc: metadata.qrc,
  qrcTrans: metadata.qrcTrans,
  source: track.source,
);

bool needsCachedMetadataRefresh(CacheMetadata metadata) =>
    metadata.songName.isEmpty ||
    metadata.artists.isEmpty ||
    metadata.album.isEmpty ||
    metadata.picUrl.isEmpty ||
    metadata.originalUrl.isEmpty ||
    (metadata.lyric.isEmpty && metadata.yrc.isEmpty && metadata.qrc.isEmpty);
