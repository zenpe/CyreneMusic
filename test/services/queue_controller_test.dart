import 'dart:math';

import 'package:cyrene_music/models/track.dart';
import 'package:cyrene_music/services/playback/queue_controller.dart';
import 'package:cyrene_music/services/playback_mode_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Track track(int id) => Track(
    id: id,
    name: 'Track $id',
    artists: 'Artist',
    album: 'Album',
    picUrl: '',
    source: MusicSource.netease,
  );

  test('replace clamps index and exposes current track', () {
    final queue = QueueController();
    queue.replace([track(1), track(2)], 9, QueueSource.playlist);

    expect(queue.currentIndex, 1);
    expect(queue.currentTrack?.id, 2);
    expect(queue.source, QueueSource.playlist);
  });

  test('removing current track keeps pointer valid', () {
    final queue = QueueController();
    queue.replace([track(1), track(2), track(3)], 1, QueueSource.album);

    final result = queue.removeAt(1);

    expect(result.removedCurrent, isTrue);
    expect(result.becameEmpty, isFalse);
    expect(queue.currentTrack?.id, 3);
  });

  test('reorder preserves the selected track', () {
    final queue = QueueController();
    queue.replace([track(1), track(2), track(3)], 1, QueueSource.playlist);

    expect(queue.reorder(1, 3), isTrue);
    expect(queue.currentTrack?.id, 2);
    expect(queue.currentIndex, 2);
  });

  test('single item shuffle never requests an invalid random range', () {
    final queue = QueueController(random: Random(1));
    queue.replace([track(1)], 0, QueueSource.playlist);

    expect(queue.advanceRandom()?.id, 1);
    expect(queue.peekNext(PlaybackMode.shuffle)?.id, 1);
  });

  test('sequential mode does not wrap the preload lookahead at the end', () {
    final queue = QueueController();
    queue.replace([track(1), track(2)], 1, QueueSource.playlist);

    expect(queue.peekNext(PlaybackMode.sequential), isNull);
  });

  test('clear resets source and pointer', () {
    final queue = QueueController();
    queue.replace([track(1)], 0, QueueSource.history);

    queue.clear();

    expect(queue.tracks, isEmpty);
    expect(queue.currentIndex, -1);
    expect(queue.source, QueueSource.none);
  });

  test('structure revision changes only for structural mutations', () {
    final queue = QueueController();
    final initialRevision = queue.structureRevision;

    queue.replace([track(1), track(2)], 0, QueueSource.playlist);
    final replacedRevision = queue.structureRevision;
    expect(replacedRevision, greaterThan(initialRevision));

    queue.jumpTo(1);
    queue.advanceNext(shuffle: false);
    queue.advancePrevious(shuffle: false);
    expect(queue.structureRevision, replacedRevision);

    queue.append(track(3));
    expect(queue.structureRevision, greaterThan(replacedRevision));
  });

  test('duplicate tracks receive distinct stable queue entry ids', () {
    final queue = QueueController();
    queue.replace([track(1), track(1), track(2)], 0, QueueSource.playlist);

    final first = queue.entryIdAt(0);
    final duplicate = queue.entryIdAt(1);
    expect(first, isNotNull);
    expect(duplicate, isNotNull);
    expect(duplicate, isNot(first));

    queue.jumpTo(1);
    expect(queue.currentEntryId, duplicate);
    expect(queue.indexOfEntryId(duplicate!), 1);
  });

  test('queue entry id follows its track through reorder and removal', () {
    final queue = QueueController();
    queue.replace([track(1), track(2), track(3)], 1, QueueSource.playlist);
    final selectedId = queue.currentEntryId;

    expect(queue.reorder(1, 3), isTrue);
    expect(queue.currentEntryId, selectedId);
    expect(queue.indexOfEntryId(selectedId!), 2);

    queue.removeAt(0);
    expect(queue.currentEntryId, selectedId);
    expect(queue.indexOfEntryId(selectedId), 1);
  });
}
