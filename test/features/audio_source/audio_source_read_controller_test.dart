import 'package:cyrene_music/features/audio_source/audio_source_feature.dart';
import 'package:cyrene_music/models/audio_source_config.dart';
import 'package:cyrene_music/services/audio_source_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final AudioSourceService service = AudioSourceService();

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

  group('AudioSourceReadController', () {
    test('sourceSummary shows setup prompt when not configured', () {
      final controller = AudioSourceReadController.withService(service);

      expect(controller.isConfigured, isFalse);
      expect(controller.sourceSummary, '未配置（点击配置）');
    });

    test('sourceSummary reuses sourceDescription when configured', () async {
      final controller = AudioSourceReadController.withService(service);
      await service.addSource(buildSource('a', 'Source A'));

      expect(controller.isConfigured, isTrue);
      expect(controller.sourceSummary, controller.sourceDescription);
      expect(controller.sourceSummary, isNot('未配置（点击配置）'));
    });

    test('addListener/removeListener/refresh delegates to service', () {
      final controller = AudioSourceReadController.withService(service);
      var called = 0;

      void listener() {
        called += 1;
      }

      controller.addListener(listener);
      controller.refresh();
      expect(called, 1);

      controller.removeListener(listener);
      controller.refresh();
      expect(called, 1);
    });
  });
}
