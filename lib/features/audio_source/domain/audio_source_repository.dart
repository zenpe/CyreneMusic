import '../../../models/audio_source_config.dart';

/// 音源领域仓储接口。
///
/// 负责抽象音源写操作，隔离上层用例与底层存储实现。
abstract class AudioSourceRepository {
  String createSourceId();

  Future<void> addSource(AudioSourceConfig config);

  Future<void> updateSource(AudioSourceConfig config);

  Future<void> removeSource(String id);

  Future<void> setActiveSource(String id);

  Future<void> clear();
}

