import 'package:cyrene_music/models/track.dart';
import 'package:cyrene_music/services/music_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('LX Kugou playback uses FileHash instead of stable track id', () {
    final id = MusicService.lxPlaybackId(
      'emix-id',
      MusicSource.kugou,
      const TrackSourceIds(fileHash: 'abcdef0123456789', emixSongId: 'emix-id'),
    );

    expect(id, 'ABCDEF0123456789');
  });

  test('LX Kugou playback rejects a missing FileHash', () {
    expect(
      () => MusicService.lxPlaybackId(
        'emix-id',
        MusicSource.kugou,
        const TrackSourceIds(emixSongId: 'emix-id'),
      ),
      throwsA(
        isA<MissingTrackSourceIdentifierException>().having(
          (error) => error.message,
          'message',
          '歌曲标识不完整，请重新搜索或同步',
        ),
      ),
    );
  });

  test('LX non-Kugou playback keeps the stable platform id', () {
    expect(
      MusicService.lxPlaybackId(
        'qq-mid',
        MusicSource.qq,
        const TrackSourceIds(),
      ),
      'qq-mid',
    );
  });
}
