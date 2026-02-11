import 'dart:async' as async_lib;
import 'package:flutter/foundation.dart';
import 'package:media_kit/media_kit.dart' as mk;
import 'persistent_storage_service.dart';

/// 均衡器服务 — 从 PlayerService 中提取的独立服务
/// 管理均衡器增益、开关状态，以及应用到 MediaKit 播放器
class EqualizerService extends ChangeNotifier {
  static final EqualizerService _instance = EqualizerService._internal();
  factory EqualizerService() => _instance;
  EqualizerService._internal();

  static const List<int> kEqualizerFrequencies = [31, 63, 125, 250, 500, 1000, 2000, 4000, 8000, 16000];

  List<double> _equalizerGains = List.filled(10, 0.0);
  bool _equalizerEnabled = true;
  async_lib.Timer? _saveEqTimer;

  /// 当前 MediaKit 播放器引用（由 PlayerService 注入）
  mk.Player? _mediaKitPlayer;
  bool _useMediaKit = false;

  List<double> get equalizerGains => List.unmodifiable(_equalizerGains);
  bool get equalizerEnabled => _equalizerEnabled;

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

  /// 注入 MediaKit 播放器引用（由 PlayerService 在初始化播放器后调用）
  void setPlayer(mk.Player? player, {required bool useMediaKit}) {
    _mediaKitPlayer = player;
    _useMediaKit = useMediaKit;
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
    if (!_useMediaKit || _mediaKitPlayer == null) return;

    try {
      if (!_equalizerEnabled) {
        await (_mediaKitPlayer!.platform as dynamic)?.setProperty('af', '');
        print('🎚️ [EqualizerService] 均衡器已禁用');
        return;
      }

      final filterBuffer = StringBuffer();

      for (int i = 0; i < 10; i++) {
        final freq = kEqualizerFrequencies[i];
        final gain = _equalizerGains[i];

        if (gain.abs() <= 0.1) continue;

        if (filterBuffer.isNotEmpty) filterBuffer.write(',');
        filterBuffer.write('equalizer=f=$freq:width_type=o:width=1:g=${gain.toStringAsFixed(1)}');
      }

      final filterString = filterBuffer.toString();

      if (filterString.isEmpty) {
        await (_mediaKitPlayer!.platform as dynamic)?.setProperty('af', '');
      } else {
        await (_mediaKitPlayer!.platform as dynamic)?.setProperty('af', filterString);
      }
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
