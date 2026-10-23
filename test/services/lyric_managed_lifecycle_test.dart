import 'dart:async';
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:cyrene_music/models/track.dart';
import 'package:cyrene_music/models/song_detail.dart';
import 'package:cyrene_music/services/lyric/lyric_service.dart';
import 'package:cyrene_music/services/lyric/lyric_snapshot.dart';
import 'package:cyrene_music/services/lyric/lyric_fetch_result.dart';
import 'package:cyrene_music/services/lyric/lyric_request_coordinator.dart';
import 'package:cyrene_music/services/lyric/lyric_repository.dart';
import 'package:cyrene_music/services/lyric/lyric_cache_service.dart';

const ready = LyricFetchResult(
  LyricFetchKind.ready,
  payload: LyricPayload(lyric: '[00:00.00]Recovered'),
);
const temporary = LyricFetchResult(LyricFetchKind.unavailable, retryable: true);
void log(String message, {bool toDeveloperPanel = false}) {}
Track track(String id) => Track(
  id: id,
  name: id,
  artists: 'artist',
  album: '',
  picUrl: '',
  source: MusicSource.netease,
);
SongDetail song(
  Track track, {
  String lyric = '',
  String url = 'https://audio.test/song',
}) => SongDetail(
  id: track.id,
  name: track.name,
  pic: '',
  arName: track.artists,
  alName: '',
  level: 'standard',
  size: '0',
  url: url,
  lyric: lyric,
  tlyric: '',
  source: track.source,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory directory;
  late LyricService service;
  late Track selected;
  SongDetail? current;
  setUpAll(() async {
    directory = await Directory.systemTemp.createTemp(
      'cyrene-lyric-lifecycle-',
    );
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (_) async => directory.path,
        );
  });
  tearDownAll(() async {
    await directory.delete(recursive: true);
  });
  setUp(() async {
    service = LyricService.forTesting(
      lookup: LyricRepository().lookup,
      requests: LyricRequestCoordinator(retryDelay: Duration.zero),
    );
    await service.clearCachedLyrics();
    selected = track('a');
    current = song(selected);
    service.bindCurrentTrack(
      track: selected,
      playbackToken: 1,
      song: current,
      state: LyricLoadState.loading,
    );
  });
  tearDown(() async {
    await service.clearCachedLyrics();
    service.dispose();
  });

  LyricRequestAdapter adapter(LyricFetch fetch) => LyricRequestAdapter(
    fetch: LyricRequestFetchAdapter(
      fetchResult: fetch,
      useLyricOnlyFetch: true,
      fetchLyricOnlyDetail: () async => throw StateError('legacy fetch'),
      fetchFullDetail: () async => throw StateError('must not resolve audio'),
      normalizeSongDetail: (detail) => detail,
    ),
    presentation: LyricRequestPresentationAdapter(
      isSamePresentation: (a, b) => identical(a, b),
      currentSong: () => current,
      applyResolvedSongDetail: (value) => current = value,
      refreshFloatingLyrics: () {},
    ),
    cache: LyricRequestCacheAdapter(
      mergeSupplementalSongDetail: (a, b) => a,
      buildCacheRefreshSongDetail: (a, b) => a,
      cacheSongInBackground: (_) async =>
          throw StateError('lyrics must not rewrite audio cache'),
    ),
    hasAnyLyricPayload: (detail) => detail.lyric.isNotEmpty,
    log: log,
  );
  Future<void> request(LyricFetch fetch, {bool force = false}) =>
      service.requestLyrics(
        track: selected,
        playbackToken: 1,
        quality: 'standard',
        refreshKey: selected.id,
        adapter: adapter(fetch),
        force: force,
      );
  LyricPrefetchAdapter prefetchAdapter(LyricFetch fetch) =>
      LyricPrefetchAdapter(
        fetchResult: fetch,
        fetchLyricOnlyDetail: () async => throw StateError('legacy'),
        normalizeSongDetail: (d) => d,
        hasAnyLyricPayload: (_) => true,
        log: log,
      );

  test(
    'lyrics can finish before metadata and survive a later plan bind',
    () async {
      current = null;
      await request((t, d, b) async => ready);
      expect(current!.lyric, contains('Recovered'));
      service.bindCurrentTrack(
        track: selected,
        playbackToken: 1,
        song: song(selected),
        state: LyricLoadState.loading,
      );
      expect(service.currentState, LyricLoadState.ready);
      expect(service.currentSnapshot!.lines.single.text, 'Recovered');
    },
  );

  test('transient failure retries once and keeps the native URL', () async {
    var calls = 0;
    await request((t, d, b) async {
      calls++;
      return calls == 1 ? temporary : ready;
    });
    expect(calls, 2);
    expect(service.currentState, LyricLoadState.ready);
    expect(current!.url, 'https://audio.test/song');
  });

  test(
    'failure settles and manual retry can recover without resolving audio',
    () async {
      var calls = 0;
      await request((t, d, b) async {
        calls++;
        return temporary;
      });
      expect(calls, 2);
      expect(service.currentState, LyricLoadState.failed);
      await request((t, d, bypass) async {
        expect(bypass, isTrue);
        return ready;
      }, force: true);
      expect(service.currentState, LyricLoadState.ready);
    },
  );

  test('pending prefetch is adopted without an additional fetch', () async {
    final response = Completer<LyricFetchResult>();
    final started = Completer<void>();
    var calls = 0;
    Future<LyricFetchResult> fetch(t, d, b) {
      calls++;
      started.complete();
      return response.future;
    }

    final prefetch = service.prefetchLyrics(
      track: selected,
      quality: 'standard',
      refreshKey: selected.id,
      adapter: prefetchAdapter(fetch),
    );
    await started.future;
    final foreground = request(fetch);
    await Future<void>.delayed(Duration.zero);
    response.complete(ready);
    await Future.wait([prefetch, foreground]);
    expect(calls, 1);
    expect(service.currentState, LyricLoadState.ready);
  });

  test('clear while fetching rejects late UI and cache writes', () async {
    final response = Completer<LyricFetchResult>();
    final started = Completer<void>();
    final pending = request((t, d, b) {
      started.complete();
      return response.future;
    });
    await started.future;
    await service.clearCachedLyrics();
    response.complete(ready);
    await pending;
    expect(current!.lyric, isEmpty);
    expect(service.currentState, LyricLoadState.failed);
    expect(
      await LyricRepository().lookup(
        track: selected,
        quality: 'standard',
        currentSong: current,
        log: log,
      ),
      isNull,
    );
    await request((t, d, b) async => ready, force: true);
    expect(service.currentState, LyricLoadState.ready);
  });

  test('old song response cannot overwrite newer selection', () async {
    final response = Completer<LyricFetchResult>();
    final started = Completer<void>();
    final pending = request((t, d, b) {
      started.complete();
      return response.future;
    });
    await started.future;
    final next = track('b');
    current = song(next);
    service.bindCurrentTrack(
      track: next,
      playbackToken: 2,
      song: current,
      state: LyricLoadState.loading,
    );
    response.complete(ready);
    await pending;
    expect(current!.id, 'b');
    expect(current!.lyric, isEmpty);
    expect(service.currentSnapshot!.trackKey, 'netease_b');
  });

  test('existing lyrics and translations survive a failed refresh', () async {
    current = song(selected, lyric: '[00:00.00]Known');
    await request((t, d, b) async => temporary, force: true);
    expect(service.currentState, LyricLoadState.ready);
    expect(current!.lyric, contains('Known'));
    expect(current!.url, 'https://audio.test/song');
  });

  test(
    'expired cached lyrics display while refreshing and retain expiry on failure',
    () async {
      await request((t, d, b) async => ready);
      final entry = await LyricCacheService().readEntry('netease_a');
      final expired = LyricCacheEntry.fromJson({
        ...entry!.toJson(),
        'expiresAt': DateTime.utc(2020).toIso8601String(),
      });
      await LyricCacheService().writeEntry('netease_a', expired);
      LyricRepository().clearMemory();
      service.clearCurrent();
      current = song(selected);
      service.bindCurrentTrack(
        track: selected,
        playbackToken: 1,
        song: current,
        state: LyricLoadState.loading,
      );
      var calls = 0;
      await request((t, d, b) async {
        calls++;
        expect(service.currentState, LyricLoadState.ready);
        expect(current!.lyric, contains('Recovered'));
        return temporary;
      });
      expect(calls, 2);
      expect(service.currentState, LyricLoadState.ready);
      expect(
        (await LyricCacheService().readEntry('netease_a'))!.isExpired,
        isTrue,
      );
    },
  );

  test('obsolete prefetch cannot start after delayed cache lookup', () async {
    final lookup = Completer<LyricLookupResult?>();
    final isolated = LyricService.forTesting(
      lookup:
          ({
            required track,
            required quality,
            required currentSong,
            required log,
          }) => lookup.future,
    );
    isolated.bindCurrentTrack(
      track: selected,
      playbackToken: 1,
      state: LyricLoadState.loading,
    );
    var calls = 0;
    final pending = isolated.prefetchLyrics(
      track: track('b'),
      quality: 'standard',
      refreshKey: 'b',
      adapter: prefetchAdapter((t, d, b) async {
        calls++;
        return ready;
      }),
    );
    isolated.bindCurrentTrack(
      track: track('c'),
      playbackToken: 2,
      state: LyricLoadState.loading,
    );
    lookup.complete(null);
    await pending;
    expect(calls, 0);
    isolated.dispose();
  });

  test('confirmed absence is cached; ambiguous failure is not', () async {
    await request(
      (t, d, b) async => const LyricFetchResult(LyricFetchKind.empty),
    );
    expect(service.currentState, LyricLoadState.empty);
    final cached = await LyricRepository().lookup(
      track: selected,
      quality: 'lossless',
      currentSong: current,
      log: log,
    );
    expect(cached!.state, LyricLoadState.empty);
    expect(cached.skipRemote, isTrue);
  });
}
