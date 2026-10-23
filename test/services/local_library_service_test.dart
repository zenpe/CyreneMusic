import 'dart:convert';
import 'dart:io';

import 'package:cyrene_music/models/track.dart';
import 'package:cyrene_music/services/local_library_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory root;
  late Directory support;
  late Directory cache;
  setUp(() async {
    root = await Directory.systemTemp.createTemp('cyrene_local_test_');
    support = await Directory(p.join(root.path, 'support')).create();
    cache = await Directory(p.join(root.path, 'cache')).create();
  });
  tearDown(() => root.delete(recursive: true));

  LocalLibraryService library({bool copy = true}) =>
      LocalLibraryService.forTesting(
        directory: support,
        temporaryDirectory: cache,
        copyPickedFiles: copy,
      );
  Future<File> picked(String folder) async {
    final dir = await Directory(
      p.join(cache.path, 'file_picker', folder),
    ).create(recursive: true);
    return File(
      p.join(dir.path, 'Artist - Song.wav'),
    ).writeAsBytes([82, 73, 70, 70, 1, 2, 3]);
  }

  test(
    'imports survive picker cache deletion and deduplicate repeated picks',
    () async {
      final first = await picked('one');
      final second = await picked('two');
      final service = library();
      await service.importFiles([first.path, second.path]);
      expect(service.tracks, hasLength(1));
      final track = service.tracks.single;
      expect(p.isWithin(support.path, track.id as String), true);
      expect(track.name, 'Song');
      expect(track.artists, 'Artist');
      await cache.delete(recursive: true);
      await service.refreshAvailability();
      expect(service.isUnavailable(track), false);
      final reloaded = library();
      await reloaded.init(waitForMaintenance: true);
      expect(reloaded.tracks.single.id, track.id);
      expect(await File(track.id as String).readAsBytes(), [
        82,
        73,
        70,
        70,
        1,
        2,
        3,
      ]);
    },
  );

  test('missing originals remain in the library across restart', () async {
    final file = await picked('desktop');
    final service = library(copy: false);
    await service.importFiles([file.path]);
    await file.delete();
    await service.refreshAvailability();
    expect(service.tracks, hasLength(1));
    expect(service.isUnavailable(service.tracks.single), true);
    final reloaded = library(copy: false);
    await reloaded.init(waitForMaintenance: true);
    expect(reloaded.tracks, hasLength(1));
    expect(reloaded.isUnavailable(reloaded.tracks.single), true);
  });

  test(
    'invalid lyric sidecar does not prevent importing playable audio',
    () async {
      final file = await picked('bad-lyrics');
      await File(p.setExtension(file.path, '.lrc')).writeAsBytes([0xff, 0xff]);
      final service = library();
      await service.importFiles([file.path]);
      expect(service.tracks, hasLength(1));
      expect(service.tracks.single.name, 'Song');
      expect(service.getLyricByTrackId(service.tracks.single.id), isEmpty);
    },
  );

  test('existing picker entries migrate without losing lyrics', () async {
    final file = await picked('legacy');
    final track = Track(
      id: file.path,
      name: 'Legacy',
      artists: 'A',
      album: '',
      picUrl: '',
      source: MusicSource.local,
    );
    await File(p.join(support.path, 'local_library.json')).writeAsString(
      jsonEncode({
        'tracks': [track.toJson()],
        'lyrics': {file.path: '[00:01]hello'},
      }),
    );
    final service = library();
    await service.init(waitForMaintenance: true);
    expect(service.tracks.single.name, 'Legacy');
    expect(service.tracks.single.id, isNot(file.path));
    expect(service.getLyricByTrackId(service.tracks.single.id), '[00:01]hello');
    expect(
      await file.exists(),
      true,
    ); // Migration never deletes a user's original.
  });

  test('clear invalidates imports already queued', () async {
    final file = await picked('queued');
    final service = library();
    await service.init(waitForMaintenance: true);
    final pending = service.importFiles([file.path]);
    await service.clear();
    await pending;
    expect(service.tracks, isEmpty);
    final reloaded = library();
    await reloaded.init(waitForMaintenance: true);
    expect(reloaded.tracks, isEmpty);
  });
}
