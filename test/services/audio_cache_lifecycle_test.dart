import 'dart:async';
import 'dart:io';

import 'package:cyrene_music/models/song_detail.dart';
import 'package:cyrene_music/models/track.dart';
import 'package:cyrene_music/services/audio_cache_identity.dart';
import 'package:cyrene_music/services/cache_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _RealHttp extends HttpOverrides {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'refresh, retained readers, quota and clear preserve cache lifecycle',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'cyrene_cache_lifecycle_',
      );
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final slowStarted = Completer<void>();
      final releaseSlow = Completer<void>();
      var requests = 0;
      server.listen((request) async {
        requests++;
        if (request.uri.path == '/slow') {
          slowStarted.complete();
          await releaseSlow.future;
        }
        try {
          if (request.uri.path == '/fail') {
            request.response.statusCode = 503;
          } else {
            request.response.headers.contentType = ContentType('audio', 'mpeg');
            request.response.add([
              0x49,
              0x44,
              0x33,
              ...List.filled(13, request.uri.path == '/new' ? 2 : 1),
            ]);
          }
          await request.response.close();
        } catch (_) {}
      });
      SharedPreferences.setMockInitialValues({
        'cache_enabled': true,
        'custom_cache_dir': directory.path,
      });
      final cache = CacheService();
      final track = Track(
        id: 1,
        name: 'One',
        artists: 'Artist',
        album: 'Album',
        picUrl: '',
      );
      final other = Track(
        id: 2,
        name: 'Two',
        artists: 'Artist',
        album: 'Album',
        picUrl: '',
      );
      SongDetail detail(Track t, String endpoint) => SongDetail(
        id: t.id,
        name: t.name,
        pic: '',
        arName: t.artists,
        alName: t.album,
        level: 'standard',
        size: '',
        url: 'http://${server.address.address}:${server.port}/$endpoint',
        lyric: '',
        tlyric: '',
        source: t.source,
      );
      await HttpOverrides.runZoned(() async {
        try {
          await cache.initialize();
          expect(cache.currentCacheDir, endsWith('v4'));
          expect(
            await cache.cacheSong(track, detail(track, 'old'), '128k'),
            isTrue,
          );
          final original = (await cache.getCachedAudioFileInfo(
            track,
            quality: 'standard',
          ))!;
          final originalBytes = await File(original.filePath).readAsBytes();
          // A different resolver URL still reuses the complete song/quality object.
          expect(
            await cache.cacheSong(track, detail(track, 'new'), 'standard'),
            isTrue,
          );
          expect(requests, 1);

          await cache.beginAudioRefresh(track, 'standard');
          expect(
            await cache.cacheSong(track, detail(track, 'fail'), 'standard'),
            isFalse,
          );
          expect(await File(original.filePath).readAsBytes(), originalBytes);
          expect(cache.isCached(track, quality: 'standard'), isTrue);

          cache.pinCachedFile(original);
          cache.pinCachedFile(original);
          await cache.beginAudioRefresh(track, 'standard');
          expect(
            await cache.cacheSong(track, detail(track, 'new'), 'standard'),
            isTrue,
          );
          final replacement = (await cache.getCachedAudioFileInfo(
            track,
            quality: 'standard',
          ))!;
          expect(replacement.filePath, isNot(original.filePath));
          expect(
            await File(replacement.filePath).readAsBytes(),
            isNot(originalBytes),
          );
          expect(await File(original.filePath).exists(), isTrue);
          cache.unpinCachedFile(original);
          expect(await File(original.filePath).exists(), isTrue);
          cache.unpinCachedFile(original);
          for (
            var i = 0;
            i < 30 && await File(original.filePath).exists();
            i++
          ) {
            await Future<void>.delayed(const Duration(milliseconds: 10));
          }
          expect(await File(original.filePath).exists(), isFalse);

          // Capacity admits a new object by reclaiming an unpinned LRU object.
          await cache.setMaxCacheSizeBytes(16);
          expect(
            await cache.cacheSong(other, detail(other, 'old'), 'standard'),
            isTrue,
          );
          expect(cache.isCached(track, quality: 'standard'), isFalse);
          expect(
            (await cache.getCacheStats()).totalSize,
            lessThanOrEqualTo(16),
          );

          await cache.setMaxCacheSizeBytes(1024);
          await cache.beginAudioRefresh(other, 'standard');
          final staleRefresh = cache.audioRefreshFor(other, 'standard')!;
          await cache.beginAudioRefresh(other, 'standard');
          final currentRefresh = cache.audioRefreshFor(other, 'standard')!;
          cache.releaseAudioRefreshProtection(staleRefresh);
          expect(cache.audioRefreshFor(other, 'standard'), currentRefresh);
          await cache.cancelAudioRefreshByIdentity(
            audioCacheIdentityFor(other, 'standard'),
            staleRefresh.epoch,
          );
          expect(cache.audioRefreshFor(other, 'standard'), currentRefresh);
          expect(
            await cache.cacheSong(
              other,
              detail(other, 'new'),
              'standard',
              refreshRequest: staleRefresh,
            ),
            isFalse,
          );
          expect(cache.audioRefreshFor(other, 'standard'), currentRefresh);
          // Unsupported media is rejected before the download starts, but must
          // still release the refresh reservation belonging to that request.
          expect(
            await cache.cacheSong(
              other,
              detail(other, 'stream.m3u8'),
              'standard',
            ),
            isFalse,
          );
          expect(cache.audioRefreshFor(other, 'standard'), isNull);
          expect(cache.isCached(other), isTrue);
          await cache.beginAudioRefresh(other, 'standard');
          final writing = cache.cacheSong(
            track,
            detail(track, 'slow'),
            'standard',
          );
          await slowStarted.future.timeout(const Duration(seconds: 3));
          expect(
            await cache.cacheSong(other, detail(other, 'new'), 'standard'),
            isFalse,
          );
          expect(
            cache.audioRefreshFor(other, 'standard'),
            isNull,
            reason:
                'a competing download must not leave the skipped refresh protected',
          );
          await cache.clearAllCache().timeout(const Duration(seconds: 3));
          final requestsAfterClear = requests;
          expect(
            await cache.cacheSong(
              other,
              detail(other, 'new'),
              'standard',
              refreshRequest: currentRefresh,
            ),
            isFalse,
          );
          expect(requests, requestsAfterClear);
          releaseSlow.complete();
          expect(await writing, isFalse);
          expect(cache.isCached(track, quality: 'standard'), isFalse);
          expect((await cache.getCacheStats()).totalSize, 0);
          expect(
            await cache.cacheSong(track, detail(track, 'old'), 'standard'),
            isTrue,
          );
        } finally {
          if (!releaseSlow.isCompleted) releaseSlow.complete();
          await cache.clearAllCache();
          await server.close(force: true);
          await directory.delete(recursive: true);
        }
      }, createHttpClient: _RealHttp().createHttpClient);
    },
  );
}
