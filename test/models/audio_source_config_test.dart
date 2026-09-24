import 'package:cyrene_music/models/audio_source_config.dart';
import 'package:cyrene_music/services/audio_source_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Map<String, dynamic> jsonWithType(dynamic type) => {
    'id': 'source-1',
    'type': type,
    'name': 'Source',
    'url': 'https://example.test',
  };

  test('serializes audio source type using a stable string', () {
    final config = AudioSourceConfig(
      id: 'source-1',
      type: AudioSourceType.lxmusic,
      name: 'LX',
      url: '',
    );

    expect(config.toJson()['type'], 'lxmusic');
    expect(
      AudioSourceConfig.fromJson(config.toJson()).type,
      AudioSourceType.lxmusic,
    );
  });

  test('migrates supported legacy enum indexes', () {
    expect(
      AudioSourceConfig.tryFromJson(jsonWithType(1))?.type,
      AudioSourceType.lxmusic,
    );
    expect(
      AudioSourceConfig.tryFromJson(jsonWithType(3))?.type,
      AudioSourceType.navidrome,
    );
  });

  test('rejects removed legacy source types', () {
    expect(AudioSourceConfig.tryFromJson(jsonWithType(0)), isNull);
    expect(AudioSourceConfig.tryFromJson(jsonWithType(2)), isNull);
  });
}
