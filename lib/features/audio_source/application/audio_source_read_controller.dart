import 'package:flutter/foundation.dart';

import '../../../models/audio_source_config.dart';
import '../../../services/audio_source_service.dart';

/// 音源读控制器。
///
/// 统一暴露读取状态与监听能力，减少页面直接依赖 AudioSourceService。
class AudioSourceReadController {
  static final AudioSourceReadController _instance =
      AudioSourceReadController._internal();

  factory AudioSourceReadController() => _instance;

  AudioSourceReadController.withService(AudioSourceService service)
      : _service = service;

  AudioSourceReadController._internal({AudioSourceService? service})
      : _service = service ?? AudioSourceService();

  final AudioSourceService _service;

  List<AudioSourceConfig> get sources => _service.sources;

  AudioSourceConfig? get activeSource => _service.activeSource;

  bool get isNavidromeActive => _service.isNavidromeActive;

  bool get isConfigured => _service.isConfigured;

  String get sourceDescription => _service.getSourceDescription();

  String get sourceSummary =>
      isConfigured ? sourceDescription : '未配置（点击配置）';

  void addListener(VoidCallback listener) => _service.addListener(listener);

  void removeListener(VoidCallback listener) => _service.removeListener(listener);

  void refresh() => _service.refresh();
}
