import 'dart:convert';
import 'dart:io';

import 'package:cyrene_music/models/playlist.dart';
import 'package:cyrene_music/models/song_detail.dart';
import 'package:cyrene_music/models/track.dart';
import 'package:cyrene_music/services/cache_service.dart';
import 'package:cyrene_music/services/favorite_service.dart';
import 'package:cyrene_music/services/lx_music_info.dart';
import 'package:cyrene_music/services/play_history_service.dart';
import 'package:cyrene_music/services/playback/playback_session_snapshot.dart';
import 'package:cyrene_music/services/playback/queue_controller.dart';
import 'package:cyrene_music/services/playback_mode_service.dart';
import 'package:cyrene_music/utils/audio_duration_evidence.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'Go and Dart share duration units, interval and assessment boundaries',
    () {
      final fixture = jsonDecode(
        File('test/fixtures/audio_duration_contract.json').readAsStringSync(),
      ) as Map;
      for (final row in fixture['intervals'] as List) {
        final info = buildLxMusicInfo(
          source: 'tx',
          songId: 'MID',
          durationMs: row['durationMs'] as int?,
        );
        expect(info['interval'], row['interval'], reason: '$row');
        expect(info['songmid'], 'MID');
        expect(info, isNot(contains('duration')));
      }
      const names = {
        AudioDurationAssessment.unknown: 'unknown',
        AudioDurationAssessment.suspectedShort: 'suspected_short_resource',
        AudioDurationAssessment.noShortDetected: 'no_short_duration_detected',
      };
      for (final row in fixture['assessments'] as List) {
        expect(
          names[assessAudioDuration(
            expectedMs: row['expectedMs'] as int?,
            observedMs: row['observedMs'] as int?,
          )],
          row['result'],
          reason: '$row',
        );
      }
      for (final value in ['212', double.nan, double.infinity, 1.5]) {
        expect(validDurationMs(value), isNull);
      }
    },
  );

  test('expected duration survives playlist, history, favorites and session restore', () {
    final track = Track(
      id: 'MID',
      name: 'Song',
      artists: 'Artist',
      album: 'Album',
      picUrl: '',
      source: MusicSource.qq,
      durationMs: 212000,
      sourceIds: const TrackSourceIds(fileHash: 'existing-id'),
    );
    final playlist = PlaylistTrack.fromTrack(track);
    final favorite = FavoriteTrack.fromTrack(track);
    final history = PlayHistoryItem.fromTrack(track);
    final snapshot = PlaybackSessionSnapshot(
      version: 1,
      savedAt: DateTime.utc(2026),
      queue: [track],
      currentIndex: 0,
      source: QueueSource.playlist,
      position: Duration.zero,
      state: PlaybackSessionState.paused,
      playbackMode: PlaybackMode.loopAll,
    );
    final restored = [
      Track.fromJson(track.toJson()),
      PlaylistTrack.fromJson(playlist.toJson()).toTrack(),
      FavoriteTrack.fromJson({
        ...favorite.toJson(),
        'addedAt': DateTime.utc(2026).toIso8601String(),
      }).toTrack(),
      PlayHistoryItem.fromJson(history.toJson()).toTrack(),
      PlaybackSessionSnapshot.fromJson(snapshot.toJson()).queue.single,
    ];
    for (final result in restored) {
      expect(result.durationMs, 212000);
      expect(result.sourceIds.fileHash, 'existing-id');
      expect(
        buildLxMusicInfo(
          source: 'tx',
          songId: result.id,
          durationMs: result.durationMs,
        )['interval'],
        '03:32',
      );
    }
    final old = track.toJson()..remove('durationMs');
    expect(Track.fromJson(old).durationMs, isNull);
    expect(Track.fromJson({...old, 'durationMs': '7'}).durationMs, isNull);
  });

  test(
    'known short resource is declined before cache lookup or any download',
    () async {
      final track = Track(
        id: 'MID',
        name: 'Song',
        artists: 'Artist',
        album: 'Album',
        picUrl: '',
        source: MusicSource.qq,
        durationMs: 212000,
      );
      final detail = SongDetail(
        id: 'MID',
        name: '',
        pic: '',
        arName: '',
        alName: '',
        level: '128k',
        size: '',
        url: 'https://example.invalid/short.mp3',
        lyric: '',
        tlyric: '',
        durationMs: 212000,
        source: MusicSource.qq,
      );
      final roundtrip = SongDetail.fromJson(
        detail.toJson(),
        source: detail.source,
      );
      expect(roundtrip.toTrack().durationMs, 212000);
      expect(
        await CacheService().cacheSong(
          track,
          detail,
          'standard',
          observedDurationMs: 7128,
        ),
        isFalse,
      );
      expect(
        track.durationMs,
        212000,
        reason: 'resource duration never replaces the expected duration',
      );
    },
  );
}
