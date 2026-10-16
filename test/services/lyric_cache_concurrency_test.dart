import 'dart:convert';
import 'dart:io';

import 'package:cyrene_music/services/lyric/lyric_cache_service.dart';
import 'package:flutter_test/flutter_test.dart';

LyricCacheEntry entry(String key, String lyric) => LyricCacheEntry(
  trackKey: key,
  quality: 'standard',
  source: 'netease',
  title: key,
  artist: '',
  lyric: lyric,
  tlyric: '',
  yrc: '',
  ytlrc: '',
  qrc: '',
  qrcTrans: '',
  hasContent: true,
  completeness: 'plain',
  state: LyricCacheState.ready,
  fetchedAt: DateTime.utc(2026),
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory directory;
  late LyricCacheService cache;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('cyrene-lyric-race-');
    cache = LyricCacheService.forTesting(directory);
  });
  tearDown(() async {
    await cache.flushIndex();
    cache.dispose();
    await directory.delete(recursive: true);
  });

  test(
    'concurrent initialization, reads and writes preserve files and index',
    () async {
      await Future.wait(List.generate(10, (_) => cache.initialize()));
      const key = 'netease_same';
      await cache.writeEntry(key, entry(key, 'initial'));
      final work = <Future<void>>[];
      for (var i = 0; i < 25; i++) {
        work.add(cache.writeEntry(key, entry(key, 'version-$i')));
        work.add(
          cache.readEntry(key).then((value) {
            expect(value, isNotNull);
            expect(value!.lyric, startsWith('version-'));
          }),
        );
        final other = 'netease_$i';
        work.add(cache.writeEntry(other, entry(other, 'other-$i')));
      }
      await Future.wait(work);
      await cache.flushIndex();
      expect((await cache.readEntry(key))!.lyric, 'version-24');
      final index =
          jsonDecode(
                await File('${directory.path}/lyric_index.json').readAsString(),
              )
              as Map;
      expect(index.length, 26);
      for (final key in index.keys) {
        expect(await cache.readEntry(key as String), isNotNull);
      }
      expect(
        (await directory.list().toList()).where(
          (f) => f.path.endsWith('.part') || f.path.endsWith('.bak'),
        ),
        isEmpty,
      );
    },
  );

  test('clear and delete cannot remove a newer queued write', () async {
    await cache.initialize();
    const key = 'netease_same';
    await Future.wait([
      cache.writeEntry(key, entry(key, 'old')),
      cache.clearAllCache(),
      cache.writeEntry(key, entry(key, 'after-clear')),
      cache.deleteEntry(key),
      cache.writeEntry(key, entry(key, 'new')),
    ]);
    expect((await cache.readEntry(key))!.lyric, 'new');
    expect((await cache.getCacheStats()).totalFiles, 1);
    final reloaded = LyricCacheService.forTesting(directory);
    await reloaded.initialize();
    expect((await reloaded.readEntry(key))!.lyric, 'new');
    await reloaded.flushIndex();
    reloaded.dispose();
  });

  test('failed operation does not block later cache access', () async {
    await cache.initialize();
    await expectLater(
      cache.writeEntry('missing/track', entry('track', 'bad path')),
      throwsA(isA<FileSystemException>()),
    );
    await cache.writeEntry('good', entry('good', 'recovered'));
    expect((await cache.readEntry('good'))!.lyric, 'recovered');
  });
}
