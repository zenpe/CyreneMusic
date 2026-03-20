import 'package:cyrene_music/models/song_detail.dart';
import 'package:cyrene_music/models/track.dart';
import 'package:cyrene_music/services/lyric/lyric_service.dart';
import 'package:cyrene_music/services/lyric/lyric_snapshot.dart';
import 'package:cyrene_music/utils/lyric_parser.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final service = LyricService();
  var trackSeed = 0;

  setUp(() {
    service.clearAll(notify: false);
  });

  tearDown(() {
    service.clearAll(notify: false);
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

    test('prefetch payload-less detail does not block foreground lyric fetch', () async {
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
    });

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
      expect(lines.map((line) => line.startTime.inSeconds).toList(), <int>[0, 3, 6]);
      expect(LyricParser.findCurrentLineIndex(lines, const Duration(seconds: 4)), 1);
      expect(LyricParser.findCurrentLineIndex(lines, const Duration(seconds: 7)), 2);
    });

    test('unparseable payload normalizes ready state to empty', () {
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

      expect(service.currentState, LyricLoadState.empty);
      expect(service.currentSnapshot?.lines, isEmpty);
      expect(service.currentSnapshot?.state.displayText, '暂无歌词');
    });
  });
}

LyricRequestAdapter _buildRequestAdapter({
  required SongDetail? Function() currentSong,
  required void Function(SongDetail detail) applyResolvedSongDetail,
  required Future<SongDetail?> Function() fetchFullDetail,
}) {
  return LyricRequestAdapter(
    fetch: LyricRequestFetchAdapter(
      useLyricOnlyFetch: false,
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
