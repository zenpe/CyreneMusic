import 'package:cyrene_music/models/track.dart';
import 'package:cyrene_music/utils/audio_request_headers.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('headers follow the audio host, including cross-platform results', () {
    for (final source in [
      MusicSource.qq,
      MusicSource.netease,
      MusicSource.kugou,
    ]) {
      for (final host in [
        'isure.stream.qqmusic.qq.com',
        'dl.stream.music.tc.qq.com',
      ]) {
        final headers = buildAudioRequestHeaders(
          source,
          uri: Uri.https(host, '/song'),
        );
        expect(headers['Referer'], 'https://y.qq.com/');
        expect(headers['Origin'], 'https://y.qq.com');
      }
      final headers = buildAudioRequestHeaders(
        source,
        uri: Uri.https('fs.kugou.com', '/song'),
      );
      expect(headers['Referer'], 'https://www.kugou.com/');
    }
  });

  test('third-party and misleading hosts never receive platform headers', () {
    for (final host in [
      'cdn-img.gitcode.com',
      '127.0.0.1',
      'qqmusic.qq.com.evil.test',
      'fakeqqmusic.qq.com',
      'y.qq.com',
      'kugou.com.evil.test',
      'notkugou.com',
    ]) {
      final headers = buildAudioRequestHeaders(
        MusicSource.qq,
        uri: Uri.https(host, '/qqmusic.qq.com'),
      );
      expect(headers.keys, ['User-Agent'], reason: host);
    }
    expect(buildAudioRequestHeaders(MusicSource.qq).keys, ['User-Agent']);
  });
}
