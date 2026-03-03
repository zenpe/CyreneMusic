import '../../../models/audio_source_config.dart';
import '../../../services/audio_source_service.dart';
import '../domain/audio_source_repository.dart';

/// 音源仓储默认实现（基于现有 AudioSourceService）。
class AudioSourceRepositoryImpl implements AudioSourceRepository {
  AudioSourceRepositoryImpl({AudioSourceService? service})
      : _service = service ?? AudioSourceService();

  final AudioSourceService _service;

  @override
  String createSourceId() => _service.createSourceId();

  @override
  Future<void> addSource(AudioSourceConfig config) {
    return _service.addSource(config);
  }

  @override
  Future<void> updateSource(AudioSourceConfig config) {
    return _service.updateSource(config);
  }

  @override
  Future<void> removeSource(String id) {
    return _service.removeSource(id);
  }

  @override
  Future<void> setActiveSource(String id) {
    return _service.setActiveSource(id);
  }

  @override
  Future<void> clear() {
    return _service.clear();
  }
}

