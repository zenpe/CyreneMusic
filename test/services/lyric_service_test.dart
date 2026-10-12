import 'dart:async';

import 'package:cyrene_music/models/song_detail.dart';
import 'package:cyrene_music/models/track.dart';
import 'package:cyrene_music/services/lyric/lyric_service.dart';
import 'package:cyrene_music/services/lyric/lyric_cache_service.dart';
import 'package:cyrene_music/services/lyric/lyric_snapshot.dart';
import 'package:cyrene_music/utils/lyric_parser.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final service = LyricService();
  var trackSeed = 0;

  setUp(() async {
    await service.clearCachedLyrics();
    service.clearCurrent(notify: false);
  });

  tearDown(() async {
    await service.clearCachedLyrics();
    service.clearCurrent(notify: false);
  });

  Track buildTrack({MusicSource source = MusicSource.netease}) {
    trackSeed += 1;
    return Track(
      id: 'track_$trackSeed',
      name: 'Song $trackSeed',
      artists: 'Artist $trackSeed',
      album: 'Album $trackSeed',
      picUrl: 'https://example.com/$trackSeed.jpg',
      source: source,
    );
  }

  SongDetail buildSongDetail(
    Track track, {
    String lyric = '',
    String tlyric = '',
    String yrc = '',
    String ytlrc = '',
    String qrc = '',
    String qrcTrans = '',
  }) {
    return SongDetail(
      id: track.id,
      name: track.name,
      pic: track.picUrl,
      arName: track.artists,
      alName: track.album,
      level: 'standard',
      size: '0',
      url: 'https://example.com/${track.id}.mp3',
      lyric: lyric,
      tlyric: tlyric,
      yrc: yrc,
      ytlrc: ytlrc,
      qrc: qrc,
      qrcTrans: qrcTrans,
      source: track.source,
    );
  }

  group('LyricService regressions', () {
    for (final outcome in ['ready', 'miss', 'failed']) {
      test('cache read failure settles remote $outcome result', () async {
        final isolated = LyricService.forTesting(
          lookup:
              ({
                required track,
                required quality,
                required currentSong,
                required log,
              }) async => throw StateError('disk unavailable'),
        );
        final track = buildTrack();
        var currentSong = buildSongDetail(track);
        var fetchCount = 0;
        isolated.bindCurrentTrack(
          track: track,
          playbackToken: 1,
          song: currentSong,
          state: LyricLoadState.loading,
          notify: false,
        );
        await isolated.requestLyrics(
          track: track,
          playbackToken: 1,
          quality: 'standard',
          refreshKey: track.id,
          adapter: _buildRequestAdapter(
            currentSong: () => currentSong,
            applyResolvedSongDetail: (detail) => currentSong = detail,
            fetchFullDetail: () async {
              fetchCount++;
              if (outcome == 'failed') throw StateError('network unavailable');
              if (outcome == 'miss') return null;
              return buildSongDetail(track, lyric: '[00:00.00]Remote lyrics');
            },
          ),
        );
        expect(fetchCount, 1);
        expect(isolated.currentState, switch (outcome) {
          'ready' => LyricLoadState.ready,
          'miss' => LyricLoadState.transientMiss,
          _ => LyricLoadState.failed,
        });
        isolated.dispose();
      });
    }

    test(
      'new playback fetches while old request is pending and ignores old result',
      () async {
        final isolated = LyricService.forTesting(
          lookup:
              ({
                required track,
                required quality,
                required currentSong,
                required log,
              }) async => null,
        );
        final track = buildTrack();
        var currentSong = buildSongDetail(track);
        final oldResult = Completer<SongDetail?>();
        final newResult = Completer<SongDetail?>();
        final oldStarted = Completer<void>();
        final newStarted = Completer<void>();
        var fetchCount = 0;
        final adapter = _buildRequestAdapter(
          currentSong: () => currentSong,
          applyResolvedSongDetail: (detail) => currentSong = detail,
          fetchFullDetail: () {
            fetchCount++;
            if (fetchCount == 1) {
              oldStarted.complete();
              return oldResult.future;
            }
            newStarted.complete();
            return newResult.future;
          },
        );
        Future<void> request(int token) => isolated.requestLyrics(
          track: track,
          playbackToken: token,
          quality: 'standard',
          refreshKey: track.id,
          adapter: adapter,
        );
        void bind(int token) => isolated.bindCurrentTrack(
          track: track,
          playbackToken: token,
          song: currentSong,
          state: LyricLoadState.loading,
          notify: false,
        );
        bind(1);
        final oldRequest = request(1);
        await oldStarted.future;
        bind(2);
        final newRequest = request(2);
        await newStarted.future;
        // Same-generation duplicates still share the pending request.
        await request(2);
        expect(fetchCount, 2);
        oldResult.complete(buildSongDetail(track, lyric: '[00:00.00]Old'));
        await oldRequest;
        expect(isolated.currentState, LyricLoadState.loading);
        expect(currentSong.lyric, isEmpty);
        // Completing the old request must not release the new request's lock.
        await request(2);
        expect(fetchCount, 2);
        newResult.complete(buildSongDetail(track, lyric: '[00:00.00]New'));
        await newRequest;
        expect(isolated.currentState, LyricLoadState.ready);
        expect(isolated.currentSnapshot!.playbackToken, 2);
        expect(currentSong.lyric, '[00:00.00]New');
        isolated.dispose();
      },
    );

    test('prefetch continues after cache read failure', () async {
      final isolated = LyricService.forTesting(
        lookup:
            ({
              required track,
              required quality,
              required currentSong,
              required log,
            }) async => throw StateError('disk unavailable'),
      );
      final track = buildTrack();
      var fetchCount = 0;
      await isolated.prefetchLyrics(
        track: track,
        quality: 'standard',
        refreshKey: track.id,
        adapter: LyricPrefetchAdapter(
          fetchLyricOnlyDetail: () async {
            fetchCount++;
            return buildSongDetail(track, lyric: '[00:00.00]Prefetched');
          },
          normalizeSongDetail: (detail) => detail,
          hasAnyLyricPayload: _hasAnyLyricPayload,
          log: _noopLog,
        ),
      );
      expect(fetchCount, 1);
      expect(isolated.currentSnapshot, isNull);
      isolated.dispose();
    });

    test('prefetch null miss does not block foreground lyric fetch', () async {
      final track = buildTrack();
      var currentSong = buildSongDetail(track);
      final resolvedSong = buildSongDetail(
        track,
        lyric: '[00:00.00]Line 1\n[00:03.00]Line 2',
      );
      var fullFetchCount = 0;

      await service.prefetchLyrics(
        track: track,
        quality: 'standard',
        refreshKey: 'prefetch_null_${track.id}',
        adapter: LyricPrefetchAdapter(
          fetchLyricOnlyDetail: () async => null,
          normalizeSongDetail: (detail) => detail,
          hasAnyLyricPayload: _hasAnyLyricPayload,
          log: _noopLog,
        ),
      );

      service.bindCurrentTrack(
        track: track,
        playbackToken: 1,
        song: currentSong,
        state: LyricLoadState.idle,
        notify: false,
      );

      await service.requestLyrics(
        track: track,
        playbackToken: 1,
        quality: 'standard',
        refreshKey: 'request_after_prefetch_null_${track.id}',
        adapter: _buildRequestAdapter(
          currentSong: () => currentSong,
          applyResolvedSongDetail: (detail) {
            currentSong = detail;
          },
          fetchFullDetail: () async {
            fullFetchCount += 1;
            return resolvedSong;
          },
        ),
      );

      expect(fullFetchCount, 1);
      expect(service.currentState, LyricLoadState.ready);
      expect(
        service.currentSnapshot?.lines.map((line) => line.text).toList(),
        <String>['Line 1', 'Line 2'],
      );
    });

    test(
      'prefetch payload-less detail does not block foreground lyric fetch',
      () async {
        final track = buildTrack();
        var currentSong = buildSongDetail(track);
        final resolvedSong = buildSongDetail(
          track,
          lyric: '[00:00.00]Recovered lyric',
        );
        var fullFetchCount = 0;

        await service.prefetchLyrics(
          track: track,
          quality: 'standard',
          refreshKey: 'prefetch_empty_detail_${track.id}',
          adapter: LyricPrefetchAdapter(
            fetchLyricOnlyDetail: () async => buildSongDetail(track),
            normalizeSongDetail: (detail) => detail,
            hasAnyLyricPayload: _hasAnyLyricPayload,
            log: _noopLog,
          ),
        );

        service.bindCurrentTrack(
          track: track,
          playbackToken: 2,
          song: currentSong,
          state: LyricLoadState.idle,
          notify: false,
        );

        await service.requestLyrics(
          track: track,
          playbackToken: 2,
          quality: 'standard',
          refreshKey: 'request_after_prefetch_empty_detail_${track.id}',
          adapter: _buildRequestAdapter(
            currentSong: () => currentSong,
            applyResolvedSongDetail: (detail) {
              currentSong = detail;
            },
            fetchFullDetail: () async {
              fullFetchCount += 1;
              return resolvedSong;
            },
          ),
        );

        expect(fullFetchCount, 1);
        expect(service.currentState, LyricLoadState.ready);
        expect(service.currentSnapshot?.lines.length, 1);
        expect(service.currentSnapshot?.lines.first.text, 'Recovered lyric');
      },
    );

    test('prefetch failure does not block foreground lyric fetch', () async {
      final track = buildTrack();
      var currentSong = buildSongDetail(track);
      final resolvedSong = buildSongDetail(
        track,
        lyric: '[00:00.00]Foreground success',
      );
      var fullFetchCount = 0;

      await service.prefetchLyrics(
        track: track,
        quality: 'standard',
        refreshKey: 'prefetch_failure_${track.id}',
        adapter: LyricPrefetchAdapter(
          fetchLyricOnlyDetail: () async {
            throw StateError('prefetch failed');
          },
          normalizeSongDetail: (detail) => detail,
          hasAnyLyricPayload: _hasAnyLyricPayload,
          log: _noopLog,
        ),
      );

      service.bindCurrentTrack(
        track: track,
        playbackToken: 3,
        song: currentSong,
        state: LyricLoadState.idle,
        notify: false,
      );

      await service.requestLyrics(
        track: track,
        playbackToken: 3,
        quality: 'standard',
        refreshKey: 'request_after_prefetch_failure_${track.id}',
        adapter: _buildRequestAdapter(
          currentSong: () => currentSong,
          applyResolvedSongDetail: (detail) {
            currentSong = detail;
          },
          fetchFullDetail: () async {
            fullFetchCount += 1;
            return resolvedSong;
          },
        ),
      );

      expect(fullFetchCount, 1);
      expect(service.currentState, LyricLoadState.ready);
      expect(service.currentSnapshot?.lines.first.text, 'Foreground success');
    });

    test('transient empty result is retried by the next playback', () async {
      final track = buildTrack();
      var currentSong = buildSongDetail(track);
      var fetchCount = 0;

      Future<void> request(int playbackToken) async {
        service.bindCurrentTrack(
          track: track,
          playbackToken: playbackToken,
          song: currentSong,
          state: LyricLoadState.idle,
          notify: false,
        );
        await service.requestLyrics(
          track: track,
          playbackToken: playbackToken,
          quality: 'standard',
          refreshKey: 'transient_empty_${track.id}',
          adapter: _buildRequestAdapter(
            currentSong: () => currentSong,
            applyResolvedSongDetail: (detail) => currentSong = detail,
            fetchFullDetail: () async {
              fetchCount += 1;
              return buildSongDetail(track);
            },
          ),
        );
      }

      await request(10);
      expect(service.currentState, LyricLoadState.transientMiss);
      expect(service.currentSnapshot?.state.displayText, '暂未获取到歌词');

      await request(11);
      expect(fetchCount, 2);
      expect(service.currentState, LyricLoadState.transientMiss);
    });

    test('failed lyric request is retried by the next playback', () async {
      final track = buildTrack();
      var currentSong = buildSongDetail(track);
      var fetchCount = 0;

      Future<void> request(int playbackToken) async {
        service.bindCurrentTrack(
          track: track,
          playbackToken: playbackToken,
          song: currentSong,
          state: LyricLoadState.idle,
          notify: false,
        );
        await service.requestLyrics(
          track: track,
          playbackToken: playbackToken,
          quality: 'standard',
          refreshKey: 'failed_${track.id}',
          adapter: _buildRequestAdapter(
            currentSong: () => currentSong,
            applyResolvedSongDetail: (detail) => currentSong = detail,
            fetchFullDetail: () async {
              fetchCount += 1;
              throw StateError('temporary failure');
            },
          ),
        );
      }

      await request(20);
      expect(service.currentState, LyricLoadState.failed);
      await request(21);
      expect(fetchCount, 2);
      expect(service.currentState, LyricLoadState.failed);
    });

    test('authoritative empty result is cached', () async {
      final track = buildTrack();
      var currentSong = buildSongDetail(track);
      var fetchCount = 0;

      Future<void> request(int playbackToken) async {
        service.bindCurrentTrack(
          track: track,
          playbackToken: playbackToken,
          song: currentSong,
          state: LyricLoadState.idle,
          notify: false,
        );
        await service.requestLyrics(
          track: track,
          playbackToken: playbackToken,
          quality: 'standard',
          refreshKey: 'authoritative_empty_${track.id}',
          adapter: _buildRequestAdapter(
            currentSong: () => currentSong,
            applyResolvedSongDetail: (detail) => currentSong = detail,
            fetchFullDetail: () async {
              fetchCount += 1;
              return buildSongDetail(track);
            },
            emptyResultIsAuthoritative: true,
          ),
        );
      }

      await request(30);
      expect(service.currentState, LyricLoadState.empty);
      await request(31);
      expect(fetchCount, 1);
      expect(service.currentState, LyricLoadState.empty);
    });

    test('legacy empty cache entry is not authoritative', () {
      final entry = LyricCacheEntry.fromJson(<String, dynamic>{
        'trackKey': 'netease_legacy',
        'state': 'empty',
        'fetchedAt': DateTime.now().toIso8601String(),
      });

      expect(entry.authoritativeEmpty, isFalse);
    });

    test('plain-text fallback lines receive staggered timestamps', () {
      final track = buildTrack(source: MusicSource.qq);
      final song = buildSongDetail(
        track,
        qrc: 'First line\nSecond line\nThird line',
      );

      service.bindCurrentTrack(
        track: track,
        playbackToken: 4,
        song: song,
        state: LyricLoadState.ready,
        notify: false,
      );

      final lines = service.currentSnapshot!.lines;
      expect(lines.map((line) => line.startTime.inSeconds).toList(), <int>[
        0,
        3,
        6,
      ]);
      expect(
        LyricParser.findCurrentLineIndex(lines, const Duration(seconds: 4)),
        1,
      );
      expect(
        LyricParser.findCurrentLineIndex(lines, const Duration(seconds: 7)),
        2,
      );
    });

    test('unparseable payload normalizes ready state to transient miss', () {
      final track = buildTrack(source: MusicSource.qq);
      final song = buildSongDetail(
        track,
        qrc: '[ti:Only metadata]\n[ar:No lines]',
      );

      service.bindCurrentTrack(
        track: track,
        playbackToken: 5,
        song: song,
        state: LyricLoadState.ready,
        notify: false,
      );

      expect(service.currentState, LyricLoadState.transientMiss);
      expect(service.currentSnapshot?.lines, isEmpty);
      expect(service.currentSnapshot?.state.displayText, '暂未获取到歌词');
    });
  });
}

LyricRequestAdapter _buildRequestAdapter({
  required SongDetail? Function() currentSong,
  required void Function(SongDetail detail) applyResolvedSongDetail,
  required Future<SongDetail?> Function() fetchFullDetail,
  bool emptyResultIsAuthoritative = false,
}) {
  return LyricRequestAdapter(
    fetch: LyricRequestFetchAdapter(
      useLyricOnlyFetch: false,
      emptyResultIsAuthoritative: emptyResultIsAuthoritative,
      fetchLyricOnlyDetail: () async => null,
      fetchFullDetail: fetchFullDetail,
      normalizeSongDetail: (detail) => detail,
    ),
    presentation: LyricRequestPresentationAdapter(
      isSamePresentation: _isSamePresentation,
      currentSong: currentSong,
      applyResolvedSongDetail: applyResolvedSongDetail,
      refreshFloatingLyrics: () {},
    ),
    cache: LyricRequestCacheAdapter(
      mergeSupplementalSongDetail: (_, supplemental) => supplemental,
      buildCacheRefreshSongDetail: (_, normalizedDetail) => normalizedDetail,
      cacheSongInBackground: (_) async => false,
    ),
    hasAnyLyricPayload: _hasAnyLyricPayload,
    log: _noopLog,
  );
}

bool _isSamePresentation(SongDetail current, SongDetail next) {
  return current.id == next.id &&
      current.lyric == next.lyric &&
      current.tlyric == next.tlyric &&
      current.yrc == next.yrc &&
      current.ytlrc == next.ytlrc &&
      current.qrc == next.qrc &&
      current.qrcTrans == next.qrcTrans;
}

bool _hasAnyLyricPayload(SongDetail song) {
  return song.lyric.isNotEmpty ||
      song.tlyric.isNotEmpty ||
      song.yrc.isNotEmpty ||
      song.ytlrc.isNotEmpty ||
      song.qrc.isNotEmpty ||
      song.qrcTrans.isNotEmpty;
}

void _noopLog(String _, {bool toDeveloperPanel = false}) {}
