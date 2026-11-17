import 'dart:async';

import 'package:cyrene_music/models/song_detail.dart';
import 'package:cyrene_music/models/track.dart';
import 'package:cyrene_music/services/audio_source_service.dart';
import 'package:cyrene_music/services/playback/engine_host.dart';
import 'package:cyrene_music/services/playback/playable_source.dart';
import 'package:cyrene_music/services/playback/playback_service.dart';
import 'package:cyrene_music/services/playback/track_resolver.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _PreparedHost extends EngineHost {
  PreparedPlaybackSlot? current;
  PreparedPlaybackSlot? next;
  Completer<void>? prepareGate;
  final preparing = Completer<void>();
  int invalidations = 0;

  @override
  Future<void> bindCurrentPreparedSlot(PreparedPlaybackSlot slot) async {
    current = slot;
  }

  @override
  Future<void> preparePlaybackWindow(PreparedPlaybackWindow window) async {
    if (!preparing.isCompleted) preparing.complete();
    await prepareGate?.future;
    next = window.next;
  }

  @override
  Future<void> invalidatePreparedSlots() async {
    invalidations++;
    next = null;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const quality = AudioQuality.standard;
  Track track(MusicSource platform) => Track(
    id: 'song',
    name: 'Song',
    artists: 'Artist',
    album: '',
    picUrl: '',
    source: platform,
  );
  final wy = track(MusicSource.netease), kw = track(MusicSource.kuwo);
  late Map<MusicSource, String> targets;
  late PlaybackService playback;
  late _PreparedHost engine;
  Completer<void>? fetchGate;
  late Completer<void> fetching;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    targets = {MusicSource.netease: 'wy-a', MusicSource.kuwo: 'kw-a'};
    fetchGate = null;
    fetching = Completer<void>();
    engine = _PreparedHost();
    playback = PlaybackService.forTesting(
      engine: engine,
      resolverFingerprintFor: (platform) => targets[platform],
      resolver: TrackResolver(
        automaticRouteFor: (_) => null,
        fetcher:
            ({
              required songId,
              required quality,
              required source,
              required title,
              required artist,
              String album = '',
              int? durationMs,
              LxMusicMetadata lxMetadata = const LxMusicMetadata(),
              required sourceIds,
              required fetchLyrics,
              onLxFailure,
              requestTimeout,
            }) async {
              final target = targets[source];
              if (!fetching.isCompleted) fetching.complete();
              await fetchGate?.future;
              return SongDetail(
                id: songId,
                name: title,
                pic: '',
                arName: artist,
                alName: album,
                level: '128k',
                size: '0',
                url: 'https://example.test/$target.mp3',
                lyric: '',
                tlyric: '',
                source: source,
              );
            },
      ),
    );
  });
  tearDown(() => playback.dispose());

  test(
    'lookup and take reject old target URLs even before change notification',
    () async {
      expect(await playback.prefetchForTesting(wy, quality), isTrue);
      expect(await playback.prefetchForTesting(kw, quality), isTrue);
      targets[MusicSource.netease] = 'wy-b';
      expect(playback.prefetchedSourceForTesting(wy, quality), isNull);
      expect(
        playback.prefetchedSourceForTesting(wy, quality, consume: true),
        isNull,
      );
      expect(
        playback.prefetchedSourceForTesting(kw, quality)!.sourceUrl,
        contains('kw-a'),
      );
      expect(await playback.prefetchForTesting(wy, quality), isTrue);
      expect(
        playback
            .prefetchedSourceForTesting(wy, quality, consume: true)!
            .sourceUrl,
        contains('wy-b'),
      );
    },
  );

  test('late prefetch cannot be relabeled with the new target', () async {
    fetchGate = Completer<void>();
    final pending = playback.prefetchForTesting(wy, quality);
    await fetching.future;
    targets[MusicSource.netease] = 'wy-b';
    AudioSourceService().refresh();
    fetchGate!.complete();
    expect(await pending, isFalse);
    expect(playback.prefetchedSourceForTesting(wy, quality), isNull);
    expect(await playback.prefetchForTesting(wy, quality), isTrue);
    expect(
      playback.prefetchedSourceForTesting(wy, quality)!.sourceUrl,
      contains('wy-b'),
    );
  });

  test('only an affected native next slot is removed; current playback is retained', () async {
    await playback.prefetchForTesting(wy, quality);
    await playback.prepareWindowForTesting(kw, wy, quality);
    final current = engine.current;
    final next = engine.next;
    expect(next, isNotNull);
    AudioSourceService().refresh();
    expect(engine.invalidations, 0, reason: 'health-only refresh');
    targets[MusicSource.kuwo] = 'kw-b';
    AudioSourceService().refresh();
    expect(engine.next, same(next), reason: 'unrelated platform update');
    targets[MusicSource.netease] = 'wy-b';
    AudioSourceService().refresh();
    expect(engine.next, isNull);
    expect(engine.current, same(current));
    expect(playback.currentTrack, same(kw));
  });

  test(
    'target change during native preparation cannot reinstall stale next slot',
    () async {
      await playback.prefetchForTesting(wy, quality);
      engine.prepareGate = Completer<void>();
      final pending = playback.prepareWindowForTesting(kw, wy, quality);
      await engine.preparing.future;
      final current = engine.current;
      expect(current, isNotNull);
      targets[MusicSource.netease] = 'wy-b';
      AudioSourceService().refresh();
      engine.prepareGate!.complete();
      await pending;
      expect(engine.next, isNull);
      expect(engine.current, same(current));
    },
  );
}
