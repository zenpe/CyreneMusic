import 'package:cyrene_music/models/song_detail.dart';
import 'package:cyrene_music/models/track.dart';
import 'package:cyrene_music/models/widget_playback_data.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('restored Track without SongDetail has a valid widget snapshot', () {
    final track = Track(
      id: '1',
      name: 'Song',
      artists: 'Artist',
      album: '',
      picUrl: '',
      source: MusicSource.qq,
    );
    final snapshot = WidgetPlaybackData(
      track: track,
      coverUrl: '',
      playing: false,
    );
    expect(snapshot.title, 'Song');
    expect(snapshot.artist, 'Artist');
    expect(snapshot.mediaKey, 'qq:1');
    expect(snapshot.playing, false);
  });
  test('resolved details and empty playback use explicit fallback fields', () {
    final song = SongDetail(
      id: 1,
      name: 'Resolved',
      pic: '',
      arName: 'Singer',
      alName: '',
      level: '',
      size: '',
      url: '',
      lyric: '',
      tlyric: '',
    );
    final snapshot = WidgetPlaybackData(
      song: song,
      coverUrl: '/art.png',
      playing: true,
    );
    expect(snapshot.artist, 'Singer');
    expect(snapshot.coverUrl, '/art.png');
    final empty = WidgetPlaybackData(coverUrl: '', playing: false);
    expect(empty.title, '未在播放');
    expect(empty.artist, 'Cyrene Music');
  });
}
