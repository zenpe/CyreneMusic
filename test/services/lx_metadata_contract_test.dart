import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:cyrene_music/models/playlist.dart';
import 'package:cyrene_music/models/song_detail.dart';
import 'package:cyrene_music/models/track.dart';
import 'package:cyrene_music/services/favorite_service.dart';
import 'package:cyrene_music/services/lx_music_info.dart';
import 'package:cyrene_music/services/play_history_service.dart';
import 'package:cyrene_music/services/playback/track_resolver.dart';
import 'package:cyrene_music/services/track_metadata_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final fixture = jsonDecode(
    File('test/fixtures/lx_music_metadata_contract.json').readAsStringSync(),
  ) as Map;

  test('script fields match actual LX official toOldMusicInfo output', () {
    for (final row in fixture['rows'] as List) {
      final actual = buildLxMusicInfo(
        source: row['source'],
        songId: row['id'],
        title: 'Song',
        artist: 'Artist',
        album: 'Album',
        durationMs: row['durationMs'],
        lxMetadata: LxMusicMetadata.fromJson(row['lxMetadata']),
      );
      for (final entry in (row['expected'] as Map).entries) {
        expect(
          actual[entry.key],
          entry.value,
          reason: '${row['source']}.${entry.key}',
        );
      }
    }
  });

  test(
    'script metadata survives queue JSON, playlists, favorites and history',
    () {
      final metadata = LxMusicMetadata.fromJson(
        fixture['rows'][0]['lxMetadata'],
      );
      final track = Track(
        id: 'MID1',
        name: 'Song',
        artists: 'Artist',
        album: 'Album',
        picUrl: '',
        source: MusicSource.qq,
        lxMetadata: metadata,
      );
      for (final restored in [
        Track.fromJson(jsonDecode(jsonEncode(track.toJson()))),
        PlaylistTrack.fromJson(
          jsonDecode(jsonEncode(PlaylistTrack.fromTrack(track).toJson())),
        ).toTrack(),
        FavoriteTrack.fromJson(
          jsonDecode(
            jsonEncode({
              ...FavoriteTrack.fromTrack(track).toJson(),
              'addedAt': DateTime.utc(2026).toIso8601String(),
            }),
          ),
        ).toTrack(),
        PlayHistoryItem.fromJson(
          jsonDecode(jsonEncode(PlayHistoryItem.fromTrack(track).toJson())),
        ).toTrack(),
      ]) {
        expect(restored.id, 'MID1');
        expect(restored.lxMetadata.toJson(), metadata.toJson());
      }
    },
  );

  test(
    'optional completion merges original IDs without overwriting known IDs',
    () async {
      SharedPreferences.setMockInitialValues({});
      final service = TrackMetadataService.forTesting(
        origin: () => 'https://example.test',
        fetch: (_) async => {
          'mid': 'MID1',
          'lxMetadata': {
            'songId': '12345',
            'strMediaMid': 'MEDIA1',
            'albumMid': 'NEW',
          },
        },
      );
      final track = Track(
        id: 'MID1',
        name: 'Song',
        artists: 'Artist',
        album: 'Album',
        picUrl: 'https://example.test/cover.jpg',
        source: MusicSource.qq,
        durationMs: 212000,
        lxMetadata: const LxMusicMetadata(albumMid: 'KNOWN'),
      );
      final result = await service.complete(track, includeDuration: true);
      expect(result.lxMetadata.songId, '12345');
      expect(result.lxMetadata.strMediaMid, 'MEDIA1');
      expect(result.lxMetadata.albumMid, 'KNOWN');
      expect(result.id, track.id);
    },
  );

  for (final pending in [false, true]) {
    test(
      'new script metadata replaces ${pending ? 'pending request' : 'URL cache'} without changing song identity',
      () async {
        final old = Completer<SongDetail?>();
        final inputs = <LxMusicMetadata>[];
        final resolver = TrackResolver(
          fetcher:
              ({
                required songId,
                required quality,
                required source,
                required title,
                required artist,
                String album = '',
                int? durationMs,
                LxMusicMetadata lxMetadata = const LxMusicMetadata(),
                required sourceIds,
                required fetchLyrics,
                onLxFailure,
                requestTimeout,
              }) async {
                inputs.add(lxMetadata);
                if (pending && inputs.length == 1) return old.future;
                return _detail(inputs.length);
              },
        );
        Future<TrackResolutionResult> resolve(LxMusicMetadata metadata) =>
            resolver.resolve(
              songId: 'MID1',
              quality: AudioQuality.exhigh,
              source: MusicSource.qq,
              title: 'Song',
              artist: 'Artist',
              lxMetadata: metadata,
              timeout: const Duration(seconds: 2),
              fetchLyrics: false,
            );
        final first = resolve(const LxMusicMetadata());
        await Future<void>.delayed(Duration.zero);
        if (!pending) await first;
        final second = await resolve(
          const LxMusicMetadata(songId: '12345', strMediaMid: 'MEDIA1'),
        );
        if (pending) {
          old.complete(_detail(1));
          await first;
        }
        final cached = await resolve(
          const LxMusicMetadata(songId: '12345', strMediaMid: 'MEDIA1'),
        );
        expect(inputs, hasLength(2));
        expect(inputs.last.strMediaMid, 'MEDIA1');
        expect(cached.detail?.url, second.detail?.url);
        expect(cached.isL1CacheHit, isTrue);
      },
    );
  }
}

SongDetail _detail(int n) => SongDetail(
  id: 'MID1',
  name: 'Song',
  pic: '',
  arName: 'Artist',
  alName: 'Album',
  level: '128k',
  size: '0',
  url: 'https://example.test/$n.mp3',
  lyric: '',
  tlyric: '',
  source: MusicSource.qq,
);
