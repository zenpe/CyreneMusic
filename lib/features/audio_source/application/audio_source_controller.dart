import '../../../models/audio_source_config.dart';
import '../data/audio_source_repository_impl.dart';
import 'audio_source_action_result.dart';
import 'audio_source_use_cases.dart';

/// 音源写操作控制器。
///
/// 作为 UI 与用例层之间的唯一写入口，统一错误收敛格式。
class AudioSourceController {
  static final AudioSourceController _instance = AudioSourceController._internal();

  factory AudioSourceController() => _instance;

  AudioSourceController.withUseCases(AudioSourceUseCases useCases)
      : _useCases = useCases;

  AudioSourceController._internal({AudioSourceUseCases? useCases})
      : _useCases = useCases ?? AudioSourceUseCases(AudioSourceRepositoryImpl());

  final AudioSourceUseCases _useCases;

  String createSourceId() => _useCases.createSourceId();

  Future<AudioSourceActionResult> saveSource(
    AudioSourceConfig config, {
    required bool isEditing,
  }) {
    return _run(
      () => _useCases.saveSource(config, isEditing: isEditing),
      fallbackMessage: isEditing ? '保存音源失败' : '添加音源失败',
    );
  }

  Future<AudioSourceActionResult> setActiveSource(String id) {
    return _run(
      () => _useCases.setActiveSource(id),
      fallbackMessage: '切换音源失败',
    );
  }

  Future<AudioSourceActionResult> removeSource(String id) {
    return _run(
      () => _useCases.removeSource(id),
      fallbackMessage: '删除音源失败',
    );
  }

  Future<AudioSourceActionResult> clearSelection() {
    return _run(
      () => _useCases.clearSelection(),
      fallbackMessage: '重置音源状态失败',
    );
  }

  Future<AudioSourceActionResult> _run(
    Future<void> Function() action, {
    required String fallbackMessage,
  }) async {
    try {
      await action();
      return AudioSourceActionResult.success();
    } catch (error) {
      final detail = _normalizeError(error);
      if (detail == null) {
        return AudioSourceActionResult.failure(fallbackMessage);
      }
      return AudioSourceActionResult.failure('$fallbackMessage：$detail');
    }
  }

  String? _normalizeError(Object error) {
    final raw = error.toString().trim();
    if (raw.isEmpty) return null;
    if (raw.startsWith('Exception:')) {
      final cleaned = raw.substring('Exception:'.length).trim();
      return cleaned.isEmpty ? null : cleaned;
    }
    return raw;
  }
}
