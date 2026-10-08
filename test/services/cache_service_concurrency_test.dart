import 'dart:async';
import 'dart:io';

import 'package:cyrene_music/models/song_detail.dart';
import 'package:cyrene_music/models/track.dart';
import 'package:cyrene_music/services/cache_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'background cache shares one track and skips a competing track',
    () async {
      final cacheDir = await Directory.systemTemp.createTemp(
        'cyrene_cache_concurrency_',
      );
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final firstRequestStarted = Completer<void>();
      final releaseFirstRequest = Completer<void>();
      var requestCount = 0;
      server.listen((request) async {
        requestCount++;
        if (request.uri.path == '/first.mp3') {
          if (!firstRequestStarted.isCompleted) {
            firstRequestStarted.complete();
          }
          await releaseFirstRequest.future;
        }
        request.response.headers.contentType = ContentType('audio', 'mpeg');
        request.response.add(<int>[0x49, 0x44, 0x33, 0, 0, 0, 0, 0]);
        await request.response.close();
      });

      SharedPreferences.setMockInitialValues({
        'cache_enabled': true,
        'custom_cache_dir': cacheDir.path,
      });
      final cache = CacheService();
      final realHttp = _RealHttpOverrides();
      await HttpOverrides.runZoned(() async {
        try {
          await cache.initialize();
          expect(cache.isInitialized, isTrue);

          final firstTrack = _track(1, 'First');
          final firstDetail = _detail(
            firstTrack,
            'http://${server.address.address}:${server.port}/first.mp3',
          );
          final competingTrack = _track(2, 'Competing');
          final competingDetail = _detail(
            competingTrack,
            'http://${server.address.address}:${server.port}/second.mp3',
          );

          final firstWrite = cache.cacheSong(
            firstTrack,
            firstDetail,
            'standard',
          );
          await firstRequestStarted.future.timeout(const Duration(seconds: 2));
          final sharedWrite = cache.cacheSong(
            firstTrack,
            firstDetail,
            'standard',
          );

          expect(
            await cache.cacheSong(competingTrack, competingDetail, 'standard'),
            isFalse,
          );
          expect(requestCount, 1);

          releaseFirstRequest.complete();
          expect(await Future.wait([firstWrite, sharedWrite]), [
            isTrue,
            isTrue,
          ]);
          expect(requestCount, 1);
          expect(cache.isCached(firstTrack, quality: 'standard'), isTrue);
          expect(cache.isCached(competingTrack, quality: 'standard'), isFalse);
        } finally {
          if (!releaseFirstRequest.isCompleted) {
            releaseFirstRequest.complete();
          }
          await server.close(force: true);
          await cache.clearAllCache();
          if (await cacheDir.exists()) {
            await cacheDir.delete(recursive: true);
          }
        }
      }, createHttpClient: realHttp.createHttpClient);
    },
  );
}

class _RealHttpOverrides extends HttpOverrides {}

Track _track(int id, String name) =>
    Track(id: id, name: name, artists: 'Artist', album: 'Album', picUrl: '');

SongDetail _detail(Track track, String url) => SongDetail(
  id: track.id,
  name: track.name,
  pic: '',
  arName: track.artists,
  alName: track.album,
  level: 'standard',
  size: '',
  url: url,
  lyric: '',
  tlyric: '',
  source: track.source,
);
