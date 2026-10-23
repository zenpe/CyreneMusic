import 'package:cyrene_music/models/playlist.dart';
import 'package:cyrene_music/models/track.dart';
import 'package:cyrene_music/services/playlist_service.dart';
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

  test('playlist state merge never regresses independent revisions', () {
    final current = Playlist(
      id: 1,
      name: 'current',
      isDefault: false,
      trackCount: 8,
      createdAt: DateTime.utc(2026, 1, 1),
      updatedAt: DateTime.utc(2026, 1, 2),
      contentRevision: 5,
      orderRevision: 3,
    );
    final incoming = Playlist(
      id: 1,
      name: 'incoming',
      isDefault: false,
      trackCount: 6,
      createdAt: DateTime.utc(2026, 1, 1),
      updatedAt: DateTime.utc(2026, 1, 3),
      contentRevision: 4,
      orderRevision: 6,
    );

    final merged = PlaylistService.mergePlaylistState(current, incoming);

    expect(merged.contentRevision, 5);
    expect(merged.orderRevision, 6);
    expect(merged.trackCount, 8);
    expect(merged.name, 'incoming');
    expect(merged.updatedAt, incoming.updatedAt);
  });
}
