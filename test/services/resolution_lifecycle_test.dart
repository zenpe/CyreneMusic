import 'dart:async';
import 'dart:io';

import 'package:cyrene_music/models/song_detail.dart';
import 'package:cyrene_music/models/track.dart';
import 'package:cyrene_music/services/lx_http_bridge.dart';
import 'package:cyrene_music/services/playback/track_resolver.dart';
import 'package:cyrene_music/services/resolution_request.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'foreground cancels obsolete HTTP and adopts matching preload',
    () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final seen = Completer<void>();
      final responses = <HttpResponse>[];
      final subscription = server.listen((request) {
        responses.add(request.response);
        if (!seen.isCompleted) seen.complete();
      });
      addTearDown(() async {
        await subscription.cancel();
        await server.close(force: true);
      });
      var calls = 0;
      final resolver = TrackResolver(
        fetcher:
            ({
              required songId,
              required quality,
              required source,
              required title,
              required artist,
              required sourceIds,
              required fetchLyrics,
              onLxFailure,
              requestTimeout,
            }) async {
              calls++;
              await LxHttpBridge.performHttpRequest(
                'http://127.0.0.1:${server.port}/$songId',
                {},
                timeout: const Duration(seconds: 5),
              );
              return detail(songId);
            },
      );
      Future<TrackResolutionResult> resolve(int id) => resolver.resolve(
        songId: id,
        quality: AudioQuality.standard,
        source: MusicSource.qq,
        title: 'song',
        artist: 'artist',
        timeout: const Duration(seconds: 5),
        fetchLyrics: false,
      );
      final old = resolve(1);
      await seen.future;
      resolver.prioritize(
        songId: 2,
        source: MusicSource.qq,
        quality: AudioQuality.standard,
      );
      expect((await old.timeout(const Duration(seconds: 1))).cancelled, isTrue);
      final preload = resolve(2);
      resolver.prioritize(
        songId: 2,
        source: MusicSource.qq,
        quality: AudioQuality.standard,
      );
      final adopted = resolve(2);
      while (responses.length < 2) {
        await Future<void>.delayed(const Duration(milliseconds: 5));
      }
      responses[1].write('{}');
      await responses[1].close();
      expect((await adopted).isPlayable, isTrue);
      expect((await preload).isPlayable, isTrue);
      expect(calls, 2);
    },
  );

  test(
    'clearing cancels promptly and late success cannot fill cache',
    () async {
      final response = Completer<SongDetail?>();
      ResolutionRequest? owner;
      final resolver = TrackResolver(
        fetcher:
            ({
              required songId,
              required quality,
              required source,
              required title,
              required artist,
              required sourceIds,
              required fetchLyrics,
              onLxFailure,
              requestTimeout,
            }) {
              owner = ResolutionRequest.current;
              return response.future;
            },
      );
      final pending = resolver.resolve(
        songId: 1,
        quality: AudioQuality.standard,
        source: MusicSource.qq,
        title: '',
        artist: '',
        timeout: const Duration(seconds: 5),
      );
      resolver.clear();
      expect((await pending).cancelled, isTrue);
      expect(owner!.isCancelled, isTrue);
      response.complete(detail(1));
      await Future<void>.delayed(Duration.zero);
      expect(resolver.resolvedCacheSize, 0);
    },
  );

  test(
    'caller timeout cancels its request and reports timeout to an adopter',
    () async {
      final owners = <ResolutionRequest>[];
      final resolver = TrackResolver(
        fetcher:
            ({
              required songId,
              required quality,
              required source,
              required title,
              required artist,
              required sourceIds,
              required fetchLyrics,
              onLxFailure,
              requestTimeout,
            }) {
              owners.add(ResolutionRequest.current!);
              return Completer<SongDetail?>().future;
            },
      );
      final pending = resolver.resolve(
        songId: 1,
        quality: AudioQuality.standard,
        source: MusicSource.qq,
        title: '',
        artist: '',
        timeout: const Duration(milliseconds: 30),
      );
      final adopted = resolver.resolve(
        songId: 1,
        quality: AudioQuality.standard,
        source: MusicSource.qq,
        title: '',
        artist: '',
        timeout: const Duration(seconds: 1),
      );
      final result = await pending;
      expect(result.timedOut, isTrue);
      final adoptedResult = await adopted;
      expect(adoptedResult.timedOut, isTrue);
      expect(adoptedResult.cancelled, isFalse);
      expect(owners.single.isCancelled, isTrue);
    },
  );
}

SongDetail detail(dynamic id) => SongDetail(
  id: id,
  name: 'song',
  pic: '',
  arName: '',
  alName: '',
  level: '128k',
  size: '',
  url: 'https://example.com/audio',
  lyric: '',
  tlyric: '',
  source: MusicSource.qq,
);
