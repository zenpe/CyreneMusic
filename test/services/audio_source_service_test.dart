import 'dart:convert';

import 'package:cyrene_music/models/audio_source_config.dart';
import 'package:cyrene_music/services/audio_source_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final service = AudioSourceService();

  Future<void> resetServiceState() async {
    for (final source in List<AudioSourceConfig>.from(service.sources)) {
      await service.removeSource(source.id);
    }
    await service.clear();
  }

  AudioSourceConfig buildSource(String id, String name) {
    return AudioSourceConfig(
      id: id,
      type: AudioSourceType.lxmusic,
      name: name,
      url: 'https://example.com/$id',
    );
  }

  setUp(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    await resetServiceState();
  });

  test('rewrites supported legacy source indexes using stable names', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'audio_source_list': jsonEncode(<Map<String, Object>>[
        <String, Object>{
          'id': 'legacy-navidrome',
          'type': 3,
          'name': 'Navidrome',
          'url': 'https://example.com',
        },
      ]),
    });

    await service.initialize();

    expect(service.sources.single.type, AudioSourceType.navidrome);
    final prefs = await SharedPreferences.getInstance();
    final stored =
        jsonDecode(prefs.getString('audio_source_list')!) as List<dynamic>;
    expect((stored.single as Map<String, dynamic>)['type'], 'navidrome');
  });

  group('AudioSourceService mutation queue', () {
    test('serializes concurrent addSource calls', () async {
      final sourceA = buildSource('a', 'Source A');
      final sourceB = buildSource('b', 'Source B');

      await Future.wait<void>([
        service.addSource(sourceA),
        service.addSource(sourceB),
      ]);

      expect(service.sources.map((e) => e.id), containsAll(<String>['a', 'b']));
      expect(service.sources.length, 2);
      expect(service.activeSource?.id, 'a');
    });

    test('keeps state consistent for setActive + remove race', () async {
      final sourceA = buildSource('a', 'Source A');
      final sourceB = buildSource('b', 'Source B');

      await service.addSource(sourceA);
      await service.addSource(sourceB);

      await Future.wait<void>([
        service.setActiveSource('b'),
        service.removeSource('b'),
      ]);

      expect(service.sources.map((e) => e.id), <String>['a']);
      expect(service.activeSource?.id, 'a');
    });
  });
}
