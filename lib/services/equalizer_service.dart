import 'dart:async' as async_lib;
import 'package:flutter/foundation.dart';
import 'persistent_storage_service.dart';

abstract class EqualizerCapable {
  bool get supportsEqualizer;

  Future<void> applyEqualizer(
    bool enabled,
    List<double> gains,
    List<int> frequencies,
  );
}

/// 均衡器服务 — 从 PlayerService 中提取的独立服务
/// 管理均衡器增益、开关状态，并通过引擎能力接口下发到具体实现
class EqualizerService extends ChangeNotifier {
  static final EqualizerService _instance = EqualizerService._internal();
  factory EqualizerService() => _instance;
  EqualizerService._internal();

  static const List<int> kEqualizerFrequencies = [31, 63, 125, 250, 500, 1000, 2000, 4000, 8000, 16000];

  List<double> _equalizerGains = List.filled(10, 0.0);
  bool _equalizerEnabled = true;
  async_lib.Timer? _saveEqTimer;

  EqualizerCapable? _equalizerBackend;

  List<double> get equalizerGains => List.unmodifiable(_equalizerGains);
  bool get equalizerEnabled => _equalizerEnabled;
  bool get isEqualizerAvailable => _equalizerBackend?.supportsEqualizer ?? false;

  /// 初始化：从持久化存储加载设置
  void loadSettings() {
    final savedEqGains = PersistentStorageService().getStringList('player_eq_gains');
    if (savedEqGains != null && savedEqGains.length == 10) {
      try {
        _equalizerGains = savedEqGains.map((e) => double.tryParse(e) ?? 0.0).toList();
        print('🎚️ [EqualizerService] 已加载均衡器设置');
      } catch (e) {
        print('⚠️ [EqualizerService] 加载均衡器设置失败: $e');
      }
    }
    final savedEqEnabled = PersistentStorageService().getBool('player_eq_enabled');
    if (savedEqEnabled != null) {
      _equalizerEnabled = savedEqEnabled;
    }
  }

  /// 注入当前播放引擎的均衡器能力
  void setBackend(EqualizerCapable? backend) {
    if (identical(_equalizerBackend, backend)) return;
    _equalizerBackend = backend;
    notifyListeners();
  }

  /// 更新均衡器增益
  /// [gains] 10个频段的增益值 (-12.0 到 12.0 dB)
  Future<void> updateEqualizer(List<double> gains) async {
    if (gains.length != 10) return;

    _equalizerGains = List.from(gains);
    notifyListeners();

    await applyEqualizer();
    _saveEqualizerSettingsThrottled();
  }

  /// 开关均衡器
  Future<void> setEqualizerEnabled(bool enabled) async {
    if (_equalizerEnabled == enabled) return;

    _equalizerEnabled = enabled;
    notifyListeners();

    await applyEqualizer();
    PersistentStorageService().setBool('player_eq_enabled', enabled);
  }

  /// 应用均衡器效果 (底层实现)
  Future<void> applyEqualizer() async {
    final backend = _equalizerBackend;
    if (backend == null || !backend.supportsEqualizer) return;

    try {
      await backend.applyEqualizer(
        _equalizerEnabled,
        _equalizerGains,
        kEqualizerFrequencies,
      );
    } catch (e) {
      print('⚠️ [EqualizerService] 应用均衡器失败: $e');
    }
  }

  /// 保存均衡器设置 (节流)
  void _saveEqualizerSettingsThrottled() {
    _saveEqTimer?.cancel();
    _saveEqTimer = async_lib.Timer(const Duration(milliseconds: 1000), () {
      PersistentStorageService().setStringList(
        'player_eq_gains',
        _equalizerGains.map((e) => e.toString()).toList(),
      );
    });
  }
}
