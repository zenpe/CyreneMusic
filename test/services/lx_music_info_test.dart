import 'package:flutter_test/flutter_test.dart';
import 'package:cyrene_music/models/audio_source_config.dart';
import 'package:cyrene_music/models/track.dart';
import 'package:cyrene_music/services/audio_source_service.dart';
import 'package:cyrene_music/services/lx_music_info.dart';

void main() {
  test('passes real metadata without fabricating platform identifiers', () {
    final qq = buildLxMusicInfo(
      source: 'tx',
      songId: 'song-mid',
      title: '歌名',
      artist: '歌手',
      album: '专辑',
    );
    expect(qq['songmid'], 'song-mid');
    expect(qq['name'], '歌名');
    expect(qq['singer'], '歌手');
    expect(qq['albumName'], '专辑');
    expect(qq.containsKey('strMediaMid'), isFalse);
    expect(qq.containsKey('hash'), isFalse);
    expect(qq.containsKey('copyrightId'), isFalse);
    final kg = buildLxMusicInfo(
      source: 'kg',
      songId: 'HASH',
      sourceIds: const TrackSourceIds(albumAudioId: 'audio-id'),
    );
    expect(kg['hash'], 'HASH');
    expect(kg['albumAudioId'], 'audio-id');
    expect(kg.containsKey('albumId'), isFalse);
    expect(buildLxMusicInfo(source: 'mg', songId: 123)['copyrightId'], '123');
    expect(buildLxMusicInfo(source: 'wy', songId: 123)['id'], 123);
  });

  test('resolver digest is bounded and changes with credentials or code', () {
    final config = AudioSourceConfig(
      id: 'source',
      type: AudioSourceType.lxmusic,
      name: 'Display name',
      url: '',
      apiKey: 'secret',
      scriptContent: 'private script',
    );
    final digest = config.resolverContentHash;
    expect(digest, matches(RegExp(r'^[a-f0-9]{64}$')));
    expect(config.copyWith(name: 'Renamed').resolverContentHash, digest);
    expect(
      config.copyWith(apiKey: 'changed').resolverContentHash,
      isNot(digest),
    );
    expect(
      config.copyWith(scriptContent: 'changed').resolverContentHash,
      isNot(digest),
    );
    expect(config.copyWith().resolverContentHash, digest);
  });
}
