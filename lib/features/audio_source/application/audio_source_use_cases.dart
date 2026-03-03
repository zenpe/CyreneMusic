import '../../../models/audio_source_config.dart';
import '../domain/audio_source_repository.dart';

/// 音源应用层用例。
class AudioSourceUseCases {
  AudioSourceUseCases(this._repository);

  final AudioSourceRepository _repository;

  String createSourceId() => _repository.createSourceId();

  Future<void> saveSource(
    AudioSourceConfig config, {
    required bool isEditing,
  }) async {
    if (isEditing) {
      await _repository.updateSource(config);
      return;
    }
    await _repository.addSource(config);
  }

  Future<void> setActiveSource(String id) => _repository.setActiveSource(id);

  Future<void> removeSource(String id) => _repository.removeSource(id);

  Future<void> clearSelection() => _repository.clear();
}

