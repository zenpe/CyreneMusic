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
