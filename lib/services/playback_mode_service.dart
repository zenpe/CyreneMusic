import 'structured_log_service.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 播放模式枚举
enum PlaybackMode {
  /// 顺序播放（播完最后一首停止）
  sequential,

  /// 列表循环（播完最后一首回到第一首）
  loopAll,

  /// 随机播放
  shuffle,

  /// 单曲循环
  repeatOne,
}

/// 播放模式服务
class PlaybackModeService extends ChangeNotifier {
  static final PlaybackModeService _instance = PlaybackModeService._internal();
  factory PlaybackModeService() => _instance;
  PlaybackModeService._internal() {
    _loadMode();
  }

  int _modeRevision = 0;
  int get revision => _modeRevision;

  PlaybackMode _currentMode = PlaybackMode.loopAll;
  PlaybackMode get currentMode => _currentMode;

  static const String _modeKey = 'playback_mode';

  /// 标记是否已完成旧数据迁移
  static const String _migratedKey = 'playback_mode_migrated_v2';

  /// 加载播放模式
  Future<void> _loadMode() async {
    final revision = _modeRevision;
    try {
      final prefs = await SharedPreferences.getInstance();
      if (revision != _modeRevision) return;
      final migrated = prefs.getBool(_migratedKey) ?? false;
      final modeIndex = prefs.getInt(_modeKey);

      if (!migrated && modeIndex != null) {
        // 旧版 3 值枚举: 0=sequential(实际是循环), 1=repeatOne, 2=shuffle
        // 映射到新枚举: 0→loopAll, 1→repeatOne, 2→shuffle
        switch (modeIndex) {
          case 0:
            _currentMode = PlaybackMode.loopAll;
            break;
          case 1:
            _currentMode = PlaybackMode.repeatOne;
            break;
          case 2:
            _currentMode = PlaybackMode.shuffle;
            break;
          default:
            _currentMode = PlaybackMode.loopAll;
        }
        // 保存迁移后的值
        await prefs.setInt(_modeKey, _currentMode.index);
        await prefs.setBool(_migratedKey, true);
        StructuredLogService.log(
          '[PlaybackModeService] 迁移旧播放模式: index=$modeIndex -> ${_currentMode.name}',
        );
      } else if (modeIndex != null &&
          modeIndex >= 0 &&
          modeIndex < PlaybackMode.values.length) {
        _currentMode = PlaybackMode.values[modeIndex];
      } else {
        _currentMode = PlaybackMode.loopAll;
      }
      if (revision == _modeRevision) notifyListeners();
      StructuredLogService.log(
        '[PlaybackModeService] 加载播放模式: ${_currentMode.name}',
      );
    } catch (e) {
      StructuredLogService.log('[PlaybackModeService] 加载播放模式失败: $e');
      if (revision == _modeRevision) {
        _currentMode = PlaybackMode.loopAll;
        notifyListeners();
      }
    }
  }

  /// 切换到下一个播放模式
  /// 顺序: sequential → loopAll → shuffle → repeatOne → sequential
  Future<void> toggleMode() async {
    _modeRevision++;
    final currentIndex = _currentMode.index;
    final nextIndex = (currentIndex + 1) % PlaybackMode.values.length;
    _currentMode = PlaybackMode.values[nextIndex];

    notifyListeners();
    await _saveMode();

    StructuredLogService.log(
      '[PlaybackModeService] 切换播放模式: ${_currentMode.name}',
    );
  }

  /// 设置播放模式
  Future<void> setMode(PlaybackMode mode) async {
    _modeRevision++;
    if (_currentMode == mode) {
      await _saveMode();
      return;
    }

    _currentMode = mode;
    notifyListeners();
    await _saveMode();

    StructuredLogService.log(
      '[PlaybackModeService] 设置播放模式: ${_currentMode.name}',
    );
  }

  /// 保存播放模式
  Future<void> _saveMode() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_migratedKey, true);
      await prefs.setInt(_modeKey, _currentMode.index);
    } catch (e) {
      StructuredLogService.log('[PlaybackModeService] 保存播放模式失败: $e');
    }
  }

  /// 获取播放模式图标
  IconData getModeIcon() {
    switch (_currentMode) {
      case PlaybackMode.sequential:
        return Icons.arrow_forward_rounded;
      case PlaybackMode.loopAll:
        return Icons.repeat_rounded;
      case PlaybackMode.shuffle:
        return Icons.shuffle_rounded;
      case PlaybackMode.repeatOne:
        return Icons.repeat_one_rounded;
    }
  }

  /// 获取播放模式名称
  String getModeName() {
    switch (_currentMode) {
      case PlaybackMode.sequential:
        return '顺序播放';
      case PlaybackMode.loopAll:
        return '列表循环';
      case PlaybackMode.shuffle:
        return '随机播放';
      case PlaybackMode.repeatOne:
        return '单曲循环';
    }
  }

  /// 获取播放模式短标签
  String getShortName() {
    switch (_currentMode) {
      case PlaybackMode.sequential:
        return '顺序';
      case PlaybackMode.loopAll:
        return '循环';
      case PlaybackMode.shuffle:
        return '随机';
      case PlaybackMode.repeatOne:
        return '单曲';
    }
  }
}
