import 'package:cyrene_music/models/playlist.dart';
import 'package:cyrene_music/models/track.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('synced playlist parses v2 ownership and revision fields', () {
    final playlist = Playlist.fromJson({
      'id': 7,
      'name': 'Remote order',
      'type': 'synced',
      'isDefault': false,
      'trackCount': 42,
      'contentRevision': 3,
      'orderRevision': 0,
      'source': 'netease',
      'sourcePlaylistId': '123',
      'syncStatus': 'ready',
      'lastSyncedAt': '2026-10-09 08:30:00',
      'createdAt': '2026-10-09 08:00:00',
      'updatedAt': '2026-10-09 08:30:00',
    });

    expect(playlist.isSynced, isTrue);
    expect(playlist.isLocal, isFalse);
    expect(playlist.contentRevision, 3);
    expect(playlist.syncStatus, 'ready');
    expect(playlist.lastSyncedAt, isNotNull);
    expect(playlist.toJson()['type'], 'synced');
  });

  test('local playlist item keeps its stable item id', () {
    final track = PlaylistTrack.fromJson({
      'itemId': 99,
      'trackId': 'song-1',
      'name': 'Song',
      'artists': 'Artist',
      'album': 'Album',
      'picUrl': '',
      'source': 'qq',
      'sourceIds': {'qq': 'song-1'},
      'addedAt': '2026-10-09 08:30:00',
    });

    expect(track.itemId, 99);
    expect(track.source, MusicSource.qq);
    expect(track.toJson()['itemId'], 99);
  });

  test('synced snapshot item may omit a local item id', () {
    final track = PlaylistTrack.fromJson({
      'itemId': null,
      'trackId': '1001',
      'name': 'Read only',
      'artists': 'Artist',
      'album': 'Album',
      'picUrl': '',
      'source': 'netease',
      'addedAt': '2026-10-09 08:30:00',
    });

    expect(track.itemId, isNull);
    expect(track.toJson().containsKey('itemId'), isFalse);
  });
}
