import 'dart:async';

import 'package:cyrene_music/models/track.dart';
import 'package:cyrene_music/services/track_metadata_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

const defaultCover = 'https://y.qq.com/mediastyle/global/img/album_300.png';
Track track(String id, {String album = 'Unknown', String pic = defaultCover}) =>
    Track(
      id: id,
      name: 'Original title',
      artists: 'Original artist',
      album: album,
      picUrl: pic,
      source: MusicSource.qq,
      sourceIds: const TrackSourceIds(fileHash: 'keep-me'),
    );
Map<String, dynamic> info(String id) => {
  'mid': id,
  'album': 'Real album',
  'pic': 'https://y.qq.com/real-$id.jpg',
  'name': 'Do not rename',
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test(
    'fills only missing fields and preserves identity and valid metadata',
    () async {
      final service = TrackMetadataService.forTesting(
        origin: () => 'server-a',
        fetch: (id) async => info(id),
      );
      final original = track('one', album: 'Keep album');
      final result = await service.complete(original);
      expect(result.album, 'Keep album');
      expect(result.picUrl, 'https://y.qq.com/real-one.jpg');
      expect(result.id, original.id);
      expect(result.source, original.source);
      expect(result.sourceIds, same(original.sourceIds));
      expect(result.name, original.name);
      expect(result.artists, original.artists);
      final other = await service.complete(
        track('one', pic: 'https://valid/cover.jpg'),
      );
      expect(other.album, 'Real album');
      expect(other.picUrl, 'https://valid/cover.jpg');
    },
  );

  test(
    'complete tracks, other platforms and ordinary failed URLs are not queried',
    () async {
      var calls = 0;
      final service = TrackMetadataService.forTesting(
        origin: () => 'a',
        fetch: (id) async {
          calls++;
          return info(id);
        },
      );
      final complete = track(
        'one',
        album: 'Album',
        pic: 'https://valid/403.jpg',
      );
      expect(await service.complete(complete), same(complete));
      final netease = Track(
        id: 12,
        name: 'song',
        artists: 'artist',
        album: '',
        picUrl: '',
      );
      expect(await service.complete(netease), same(netease));
      expect(calls, 0);
    },
  );

  test('deduplicates requests and limits concurrency to two', () async {
    var calls = 0, active = 0, peak = 0;
    final release = Completer<void>();
    final twoStarted = Completer<void>();
    final service = TrackMetadataService.forTesting(
      origin: () => 'a',
      fetch: (id) async {
        calls++;
        active++;
        if (active > peak) peak = active;
        if (calls == 2) twoStarted.complete();
        await release.future;
        active--;
        return info(id);
      },
    );
    final requests = [
      for (final id in ['one', 'one', 'two', 'three'])
        service.complete(track(id)),
    ];
    await twoStarted.future;
    expect(calls, 2);
    release.complete();
    final results = await Future.wait(requests);
    expect(calls, 3);
    expect(peak, 2);
    expect(results.every((t) => t.album == 'Real album'), isTrue);
  });

  test(
    'persists successful metadata and isolates different backends',
    () async {
      var origin = 'a', calls = 0;
      Future<Map<String, dynamic>?> fetch(String id) async {
        calls++;
        return info(id);
      }

      final first = TrackMetadataService.forTesting(
        origin: () => origin,
        fetch: fetch,
      );
      await first.complete(track('one'));
      final nextLaunch = TrackMetadataService.forTesting(
        origin: () => origin,
        fetch: fetch,
      );
      expect((await nextLaunch.complete(track('one'))).album, 'Real album');
      expect(calls, 1);
      origin = 'b';
      expect(nextLaunch.cached(track('one')).album, 'Unknown');
      await nextLaunch.complete(track('one'));
      expect(calls, 2);
    },
  );

  test(
    'late responses and queued requests cannot cross server/account changes',
    () async {
      var origin = 'a', session = 'user-a', calls = 0;
      final release = Completer<void>();
      final started = Completer<void>();
      final service = TrackMetadataService.forTesting(
        origin: () => origin,
        session: () => session,
        fetch: (id) async {
          calls++;
          if (calls == 2) started.complete();
          await release.future;
          return info(id);
        },
      );
      final requests = [
        for (final id in ['one', 'two', 'three']) service.complete(track(id)),
      ];
      await started.future;
      origin = 'b';
      session = 'user-b';
      release.complete();
      expect(
        (await Future.wait(requests)).every((t) => t.album == 'Unknown'),
        isTrue,
      );
      expect(calls, 2);
      origin = 'a';
      expect(service.cached(track('one')).album, 'Unknown');
    },
  );

  test(
    'rejects mismatched songs and applies cooldown to optional failures',
    () async {
      var now = DateTime(2026), calls = 0;
      final service = TrackMetadataService.forTesting(
        origin: () => 'a',
        now: () => now,
        fetch: (id) async {
          calls++;
          if (calls == 1) return info('wrong-song');
          if (calls == 2) throw StateError('offline');
          return info(id);
        },
      );
      final original = track('one');
      expect(await service.complete(original), same(original));
      await service.complete(original);
      expect(calls, 1);
      now = now.add(const Duration(minutes: 16));
      expect(await service.complete(original), same(original));
      expect(calls, 2);
      now = now.add(const Duration(minutes: 16));
      expect((await service.complete(original)).album, 'Real album');
    },
  );
}
