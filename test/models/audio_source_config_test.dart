import 'package:cyrene_music/models/audio_source_config.dart';
import 'package:cyrene_music/models/lx_source_candidate.dart';
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

  test(
    'catalog matching keeps saved recommendations bound to their server',
    () {
      const candidates = [
        LxSourceCandidate(
          path: '推荐/recommended.js',
          name: '推荐音源',
          directory: '推荐',
          kind: 'recommendation',
        ),
        LxSourceCandidate(path: 'ordinary.js', name: 'Ordinary', directory: ''),
      ];
      final recommendation = AudioSourceConfig(
        id: 'recommended-a',
        type: AudioSourceType.lxmusic,
        name: 'Recommended',
        url: '',
        catalogKind: 'recommendation',
        catalogPath: '推荐/recommended.js',
        backendOrigin: 'https://server.example:8443/api',
      );
      expect(
        recommendation.matchesCatalog(
          candidates,
          backendOrigin: recommendation.backendOrigin,
        ),
        isTrue,
      );
      for (final other in [
        'http://server.example:8443/api',
        'https://server.example/api',
        'https://server.example:8443/other',
        'https://other.example:8443/api',
      ]) {
        expect(
          recommendation.matchesCatalog(candidates, backendOrigin: other),
          isFalse,
        );
      }
      expect(
        recommendation
            .copyWith(catalogKind: '')
            .matchesCatalog(
              candidates,
              backendOrigin: recommendation.backendOrigin,
            ),
        isFalse,
        reason:
            'Legacy entries without recommendation identity stay accessible',
      );
      expect(
        recommendation
            .copyWith(catalogKind: '', catalogPath: 'ordinary.js')
            .matchesCatalog(candidates, backendOrigin: 'https://other.example'),
        isTrue,
        reason: 'Ordinary catalog source matching is unchanged',
      );
      expect(
        recommendation.matchesCatalog(
          [],
          backendOrigin: recommendation.backendOrigin,
        ),
        isFalse,
      );
    },
  );
}
