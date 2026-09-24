import 'package:cyrene_music/models/playlist.dart';
import 'package:cyrene_music/models/track.dart';
import 'package:cyrene_music/services/favorite_service.dart';
import 'package:cyrene_music/services/play_history_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const sourceIds = TrackSourceIds(
    fileHash: 'ABCDEF0123456789',
    emixSongId: 'emix-1',
    albumAudioId: 'audio-1',
  );

  final track = Track(
    id: 'emix-1',
    name: 'Song',
    artists: 'Artist',
    album: 'Album',
    picUrl: 'https://example.test/cover.jpg',
    source: MusicSource.kugou,
    sourceIds: sourceIds,
  );

  test('Track source identifiers survive JSON round-trip', () {
    final restored = Track.fromJson(track.toJson());

    expect(restored.source, MusicSource.kugou);
    expect(restored.sourceIds.fileHash, sourceIds.fileHash);
    expect(restored.sourceIds.emixSongId, sourceIds.emixSongId);
    expect(restored.sourceIds.albumAudioId, sourceIds.albumAudioId);
  });

  test('old Track JSON remains readable without guessing identifiers', () {
    final restored = Track.fromJson({
      'id': 'legacy-id',
      'name': 'Legacy',
      'artists': 'Artist',
      'album': 'Album',
      'picUrl': '',
      'source': 'kugou',
    });

    expect(restored.source, MusicSource.kugou);
    expect(restored.sourceIds.isEmpty, isTrue);
  });

  test('history, favorite and playlist models preserve source identifiers', () {
    final history = PlayHistoryItem.fromJson(
      PlayHistoryItem.fromTrack(track).toJson(),
    ).toTrack();
    final favoriteJson = FavoriteTrack.fromTrack(track).toJson()
      ..['addedAt'] = DateTime.utc(2026).toIso8601String();
    final favorite = FavoriteTrack.fromJson(favoriteJson).toTrack();
    final playlist = PlaylistTrack.fromJson(
      PlaylistTrack.fromTrack(track).toJson(),
    ).toTrack();

    for (final restored in [history, favorite, playlist]) {
      expect(restored.sourceIds.fileHash, sourceIds.fileHash);
      expect(restored.sourceIds.emixSongId, sourceIds.emixSongId);
      expect(restored.sourceIds.albumAudioId, sourceIds.albumAudioId);
    }
  });
}
