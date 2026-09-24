import 'dart:async';

import 'package:cyrene_music/models/song_detail.dart';
import 'package:cyrene_music/models/track.dart';
import 'package:cyrene_music/services/lx_runtime_interface.dart';
import 'package:cyrene_music/services/playback/track_resolver.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'reports a missing local file without starting a remote request',
    () async {
      var calls = 0;
      final resolver = TrackResolver(
        fetcher:
            ({
              required songId,
              required quality,
              required source,
              required title,
              required artist,
              required fetchLyrics,
              onLxFailure,
            }) async {
              calls++;
              return null;
            },
      );

      final lookup = await resolver.lookupLocalOrCache(
        track: Track(
          id: 'Z:/missing/cyrene-test.mp3',
          name: 'Missing',
          artists: 'Artist',
          album: 'Album',
          picUrl: '',
          source: MusicSource.local,
        ),
        quality: 'local',
        skipCache: true,
      );

      expect(lookup.localFileMissing, isTrue);
      expect(lookup.resolvedDetail, isNull);
      expect(calls, 0);
    },
  );

  test('deduplicates identical in-flight resolution requests', () async {
    var calls = 0;
    final completer = Completer<SongDetail?>();
    final resolver = TrackResolver(
      fetcher:
          ({
            required songId,
            required quality,
            required source,
            required title,
            required artist,
            required fetchLyrics,
            onLxFailure,
          }) {
            calls++;
            return completer.future;
          },
    );

    final first = resolver.resolve(
      songId: 1,
      quality: AudioQuality.exhigh,
      source: MusicSource.netease,
      title: 'Track',
      artist: 'Artist',
      timeout: const Duration(seconds: 1),
    );
    final second = resolver.resolve(
      songId: 1,
      quality: AudioQuality.exhigh,
      source: MusicSource.netease,
      title: 'Track',
      artist: 'Artist',
      timeout: const Duration(seconds: 1),
    );
    completer.complete(_detail(1));

    expect((await first).detail?.id, 1);
    expect((await second).detail?.id, 1);
    expect(calls, 1);
  });

  test('keeps Lx failures scoped to their own request', () async {
    final completers = <int, Completer<SongDetail?>>{};
    final failureCallbacks = <int, void Function(LxRuntimeFailure?)>{};
    final resolver = TrackResolver(
      fetcher:
          ({
            required songId,
            required quality,
            required source,
            required title,
            required artist,
            required fetchLyrics,
            onLxFailure,
          }) {
            final id = songId as int;
            failureCallbacks[id] = onLxFailure!;
            return (completers[id] = Completer<SongDetail?>()).future;
          },
    );

    final first = resolver.resolve(
      songId: 1,
      quality: AudioQuality.exhigh,
      source: MusicSource.netease,
      title: 'One',
      artist: 'Artist',
      timeout: const Duration(seconds: 1),
    );
    final second = resolver.resolve(
      songId: 2,
      quality: AudioQuality.exhigh,
      source: MusicSource.netease,
      title: 'Two',
      artist: 'Artist',
      timeout: const Duration(seconds: 1),
    );

    failureCallbacks[1]!(
      const LxRuntimeFailure(
        kind: LxRuntimeFailureKind.scriptRejected,
        message: 'rejected',
      ),
    );
    failureCallbacks[2]!(
      const LxRuntimeFailure(
        kind: LxRuntimeFailureKind.timeout,
        message: 'timeout',
      ),
    );
    completers[2]!.complete(null);
    completers[1]!.complete(null);

    expect((await first).lxFailure?.kind, LxRuntimeFailureKind.scriptRejected);
    expect((await second).lxFailure?.kind, LxRuntimeFailureKind.timeout);
  });

  test(
    'caches resolved playable URL and serves subsequent requests from L1 pool',
    () async {
      var calls = 0;
      final resolver = TrackResolver(
        fetcher:
            ({
              required songId,
              required quality,
              required source,
              required title,
              required artist,
              required fetchLyrics,
              onLxFailure,
            }) async {
              calls++;
              return _detail(songId as int);
            },
      );

      final first = await resolver.resolve(
        songId: 101,
        quality: AudioQuality.exhigh,
        source: MusicSource.netease,
        title: 'Track 101',
        artist: 'Artist',
        timeout: const Duration(seconds: 1),
      );

      expect(calls, 1);
      expect(first.isPlayable, isTrue);
      expect(first.isL1CacheHit, isFalse);

      // Second call should hit L1 memory pool without calling fetcher
      final second = await resolver.resolve(
        songId: 101,
        quality: AudioQuality.exhigh,
        source: MusicSource.netease,
        title: 'Track 101',
        artist: 'Artist',
        timeout: const Duration(seconds: 1),
      );

      expect(calls, 1);
      expect(second.isPlayable, isTrue);
      expect(second.isL1CacheHit, isTrue);
      expect(second.detail?.url, first.detail?.url);

      // skipMemoryCache bypasses L1 cache
      final third = await resolver.resolve(
        songId: 101,
        quality: AudioQuality.exhigh,
        source: MusicSource.netease,
        title: 'Track 101',
        artist: 'Artist',
        timeout: const Duration(seconds: 1),
        skipMemoryCache: true,
      );

      expect(calls, 2);
      expect(third.isL1CacheHit, isFalse);
    },
  );

  test('invalidates cached tracks correctly', () async {
    var calls = 0;
    final resolver = TrackResolver(
      fetcher:
          ({
            required songId,
            required quality,
            required source,
            required title,
            required artist,
            required fetchLyrics,
            onLxFailure,
          }) async {
            calls++;
            return _detail(songId as int);
          },
    );

    await resolver.resolve(
      songId: 202,
      quality: AudioQuality.exhigh,
      source: MusicSource.netease,
      title: 'Track 202',
      artist: 'Artist',
      timeout: const Duration(seconds: 1),
    );
    expect(calls, 1);

    // Invalidate the song
    resolver.invalidateSong(202, MusicSource.netease);

    // Next resolve should re-fetch
    await resolver.resolve(
      songId: 202,
      quality: AudioQuality.exhigh,
      source: MusicSource.netease,
      title: 'Track 202',
      artist: 'Artist',
      timeout: const Duration(seconds: 1),
    );
    expect(calls, 2);
  });

  test('isolates cache by resolver fingerprint', () async {
    var calls = 0;
    final resolver = TrackResolver(
      fetcher:
          ({
            required songId,
            required quality,
            required source,
            required title,
            required artist,
            required fetchLyrics,
            onLxFailure,
          }) async {
            calls++;
            return _detail(songId as int);
          },
    );

    await resolver.resolve(
      songId: 303,
      quality: AudioQuality.exhigh,
      source: MusicSource.netease,
      title: 'Track 303',
      artist: 'Artist',
      timeout: const Duration(seconds: 1),
      resolverFingerprint: 'script_v1',
    );
    expect(calls, 1);

    // Same song with different script fingerprint should not hit cache
    await resolver.resolve(
      songId: 303,
      quality: AudioQuality.exhigh,
      source: MusicSource.netease,
      title: 'Track 303',
      artist: 'Artist',
      timeout: const Duration(seconds: 1),
      resolverFingerprint: 'script_v2',
    );
    expect(calls, 2);
  });

  test('LRU eviction respects maxResolvedCacheEntries limit', () async {
    var calls = 0;
    final resolver = TrackResolver(
      maxResolvedCacheEntries: 2,
      fetcher:
          ({
            required songId,
            required quality,
            required source,
            required title,
            required artist,
            required fetchLyrics,
            onLxFailure,
          }) async {
            calls++;
            return _detail(songId as int);
          },
    );

    // Cache song 1
    await resolver.resolve(
      songId: 1,
      quality: AudioQuality.exhigh,
      source: MusicSource.netease,
      title: '1',
      artist: 'A',
      timeout: const Duration(seconds: 1),
    );
    // Cache song 2
    await resolver.resolve(
      songId: 2,
      quality: AudioQuality.exhigh,
      source: MusicSource.netease,
      title: '2',
      artist: 'A',
      timeout: const Duration(seconds: 1),
    );
    expect(calls, 2);
    expect(resolver.resolvedCacheSize, 2);

    // Cache song 3 -> song 1 should be evicted
    await resolver.resolve(
      songId: 3,
      quality: AudioQuality.exhigh,
      source: MusicSource.netease,
      title: '3',
      artist: 'A',
      timeout: const Duration(seconds: 1),
    );
    expect(calls, 3);
    expect(resolver.resolvedCacheSize, 2);

    // Song 2 should hit cache
    final res2 = await resolver.resolve(
      songId: 2,
      quality: AudioQuality.exhigh,
      source: MusicSource.netease,
      title: '2',
      artist: 'A',
      timeout: const Duration(seconds: 1),
    );
    expect(calls, 3);
    expect(res2.isL1CacheHit, isTrue);

    // Song 1 was evicted, should re-fetch
    final res1 = await resolver.resolve(
      songId: 1,
      quality: AudioQuality.exhigh,
      source: MusicSource.netease,
      title: '1',
      artist: 'A',
      timeout: const Duration(seconds: 1),
    );
    expect(calls, 4);
    expect(res1.isL1CacheHit, isFalse);
  });

  test('expires entries after TTL', () async {
    var calls = 0;
    final resolver = TrackResolver(
      resolvedCacheTtl: const Duration(milliseconds: 50),
      fetcher:
          ({
            required songId,
            required quality,
            required source,
            required title,
            required artist,
            required fetchLyrics,
            onLxFailure,
          }) async {
            calls++;
            return _detail(songId as int);
          },
    );

    await resolver.resolve(
      songId: 505,
      quality: AudioQuality.exhigh,
      source: MusicSource.netease,
      title: '505',
      artist: 'A',
      timeout: const Duration(seconds: 1),
    );
    expect(calls, 1);

    // Wait past TTL
    await Future.delayed(const Duration(milliseconds: 60));

    final res = await resolver.resolve(
      songId: 505,
      quality: AudioQuality.exhigh,
      source: MusicSource.netease,
      title: '505',
      artist: 'A',
      timeout: const Duration(seconds: 1),
    );
    expect(calls, 2);
    expect(res.isL1CacheHit, isFalse);
  });

  test('clear() empties resolved cache pool', () async {
    final resolver = TrackResolver(
      fetcher:
          ({
            required songId,
            required quality,
            required source,
            required title,
            required artist,
            required fetchLyrics,
            onLxFailure,
          }) async => _detail(songId as int),
    );

    await resolver.resolve(
      songId: 606,
      quality: AudioQuality.exhigh,
      source: MusicSource.netease,
      title: '606',
      artist: 'A',
      timeout: const Duration(seconds: 1),
    );
    expect(resolver.resolvedCacheSize, 1);

    resolver.clear();
    expect(resolver.resolvedCacheSize, 0);
  });

  test(
    'does not repopulate cache when an in-flight request is cleared',
    () async {
      final completer = Completer<SongDetail?>();
      final resolver = TrackResolver(
        fetcher:
            ({
              required songId,
              required quality,
              required source,
              required title,
              required artist,
              required fetchLyrics,
              onLxFailure,
            }) => completer.future,
      );

      final request = resolver.resolve(
        songId: 707,
        quality: AudioQuality.exhigh,
        source: MusicSource.netease,
        title: '707',
        artist: 'A',
        timeout: const Duration(seconds: 1),
      );
      await Future<void>.delayed(Duration.zero);

      resolver.clear();
      completer.complete(_detail(707));
      await request;

      expect(resolver.resolvedCacheSize, 0);
    },
  );

  test('cancelled caller does not populate the resolved URL cache', () async {
    final completer = Completer<SongDetail?>();
    var acceptResult = true;
    final resolver = TrackResolver(
      fetcher:
          ({
            required songId,
            required quality,
            required source,
            required title,
            required artist,
            required fetchLyrics,
            onLxFailure,
          }) => completer.future,
    );

    final request = resolver.resolve(
      songId: 717,
      quality: AudioQuality.exhigh,
      source: MusicSource.netease,
      title: '717',
      artist: 'A',
      timeout: const Duration(seconds: 1),
      acceptResult: () => acceptResult,
    );
    await Future<void>.delayed(Duration.zero);
    acceptResult = false;
    completer.complete(_detail(717));

    expect((await request).isPlayable, isTrue);
    expect(resolver.resolvedCacheSize, 0);
  });

  test('forced refresh replaces an older in-flight request', () async {
    var calls = 0;
    final oldRequest = Completer<SongDetail?>();
    final resolver = TrackResolver(
      fetcher:
          ({
            required songId,
            required quality,
            required source,
            required title,
            required artist,
            required fetchLyrics,
            onLxFailure,
          }) {
            calls++;
            return calls == 1 ? oldRequest.future : Future.value(_detail(808));
          },
    );

    final first = resolver.resolve(
      songId: 808,
      quality: AudioQuality.exhigh,
      source: MusicSource.netease,
      title: '808',
      artist: 'A',
      timeout: const Duration(seconds: 1),
    );
    await Future<void>.delayed(Duration.zero);

    final refreshed = await resolver.resolve(
      songId: 808,
      quality: AudioQuality.exhigh,
      source: MusicSource.netease,
      title: '808',
      artist: 'A',
      timeout: const Duration(seconds: 1),
      skipMemoryCache: true,
    );
    oldRequest.complete(_detail(808));
    await first;

    expect(calls, 2);
    expect(refreshed.isPlayable, isTrue);
    expect(resolver.resolvedCacheSize, 1);
  });

  test('zero cache capacity disables L1 storage without throwing', () async {
    final resolver = TrackResolver(
      maxResolvedCacheEntries: 0,
      fetcher:
          ({
            required songId,
            required quality,
            required source,
            required title,
            required artist,
            required fetchLyrics,
            onLxFailure,
          }) async => _detail(songId as int),
    );

    await resolver.resolve(
      songId: 909,
      quality: AudioQuality.exhigh,
      source: MusicSource.netease,
      title: '909',
      artist: 'A',
      timeout: const Duration(seconds: 1),
    );

    expect(resolver.resolvedCacheSize, 0);
  });
}

SongDetail _detail(int id) => SongDetail(
  id: id,
  name: 'Track',
  pic: '',
  arName: 'Artist',
  alName: 'Album',
  level: '320k',
  size: '0',
  url: 'https://example.test/$id.mp3',
  lyric: '',
  tlyric: '',
  source: MusicSource.netease,
);
