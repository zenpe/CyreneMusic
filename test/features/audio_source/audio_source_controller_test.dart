import 'package:cyrene_music/features/audio_source/application/audio_source_controller.dart';
import 'package:cyrene_music/features/audio_source/application/audio_source_use_cases.dart';
import 'package:cyrene_music/features/audio_source/domain/audio_source_repository.dart';
import 'package:cyrene_music/models/audio_source_config.dart';
import 'package:cyrene_music/services/audio_source_service.dart';
import 'package:flutter_test/flutter_test.dart';

class _InMemoryAudioSourceRepository implements AudioSourceRepository {
  final List<AudioSourceConfig> sources = <AudioSourceConfig>[];
  String activeId = '';
  bool throwOnAdd = false;
  bool throwOnUpdate = false;
  bool throwOnRemove = false;
  bool throwOnSetActive = false;
  bool throwOnClear = false;
  int _id = 0;

  @override
  Future<void> addSource(AudioSourceConfig config) async {
    if (throwOnAdd) throw Exception('add failed');
    sources.add(config);
  }

  @override
  Future<void> clear() async {
    if (throwOnClear) throw Exception('clear failed');
    activeId = '';
  }

  @override
  String createSourceId() => 'id_${_id++}';

  @override
  Future<void> removeSource(String id) async {
    if (throwOnRemove) throw Exception('remove failed');
    sources.removeWhere((item) => item.id == id);
    if (activeId == id) {
      activeId = sources.isEmpty ? '' : sources.first.id;
    }
  }

  @override
  Future<void> setActiveSource(String id) async {
    if (throwOnSetActive) throw Exception('set active failed');
    activeId = id;
  }

  @override
  Future<void> updateSource(AudioSourceConfig config) async {
    if (throwOnUpdate) throw Exception('update failed');
    final index = sources.indexWhere((item) => item.id == config.id);
    if (index == -1) throw Exception('source not found');
    sources[index] = config;
  }
}

AudioSourceConfig _buildConfig(String id, String name) {
  return AudioSourceConfig(
    id: id,
    type: AudioSourceType.lxmusic,
    name: name,
    url: 'https://example.com/$id',
  );
}

void main() {
  group('AudioSourceController', () {
    late _InMemoryAudioSourceRepository repository;
    late AudioSourceController controller;

    setUp(() {
      repository = _InMemoryAudioSourceRepository();
      controller = AudioSourceController.withUseCases(
        AudioSourceUseCases(repository),
      );
    });

    test('saveSource adds when creating', () async {
      final config = _buildConfig('1', 'One');
      final result = await controller.saveSource(config, isEditing: false);

      expect(result.isSuccess, isTrue);
      expect(repository.sources.length, 1);
      expect(repository.sources.first.name, 'One');
    });

    test('saveSource updates when editing', () async {
      repository.sources.add(_buildConfig('1', 'Old'));
      final updated = _buildConfig('1', 'New');

      final result = await controller.saveSource(updated, isEditing: true);

      expect(result.isSuccess, isTrue);
      expect(repository.sources.length, 1);
      expect(repository.sources.first.name, 'New');
    });

    test('setActiveSource returns normalized failure', () async {
      repository.throwOnSetActive = true;

      final result = await controller.setActiveSource('1');

      expect(result.isSuccess, isFalse);
      expect(result.errorMessage, '切换音源失败：set active failed');
    });

    test('removeSource returns fallback when error text is empty', () async {
      repository.throwOnRemove = true;

      final result = await controller.removeSource('1');

      expect(result.isSuccess, isFalse);
      expect(result.errorMessage, '删除音源失败：remove failed');
    });

    test('clearSelection delegates to repository', () async {
      repository.activeId = 'active';

      final result = await controller.clearSelection();

      expect(result.isSuccess, isTrue);
      expect(repository.activeId, isEmpty);
    });
  });
}
