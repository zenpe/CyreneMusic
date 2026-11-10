import 'dart:async';
import 'dart:collection';

import 'structured_log_service.dart';

import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../utils/toast_utils.dart';

/// 开发者模式服务
class DeveloperModeService extends ChangeNotifier {
  static final DeveloperModeService _instance =
      DeveloperModeService._internal();
  factory DeveloperModeService() => _instance;

  DeveloperModeService._internal();

  @visibleForTesting
  DeveloperModeService.forTesting();

  bool _disposed = false;

  bool _isDeveloperMode = false;
  bool get isDeveloperMode => _isDeveloperMode;

  bool _showPerformanceOverlay = false;
  bool get showPerformanceOverlay => _showPerformanceOverlay;

  int _settingsClickCount = 0;
  DateTime? _lastClickTime;

  /// 初始化完成的 Future，用于等待加载完成
  Future<void>? _initFuture;
  bool _isInitialized = false;
  bool get isInitialized => _isInitialized;

  /// 初始化服务（必须在 WidgetsFlutterBinding.ensureInitialized() 之后调用）
  Future<void> initialize() {
    _initFuture ??= _loadDeveloperMode();
    return _initFuture!;
  }

  /// 等待初始化完成（如果尚未初始化则先初始化）
  Future<void> ensureInitialized() => initialize();

  /// This service notifies settings listeners only. Log views subscribe here.
  final ChangeNotifier _logChanges = ChangeNotifier();
  Listenable get logChanges => _logChanges;
  final ListQueue<String> _logs = ListQueue<String>();
  Timer? _logNotifyTimer;
  List<String> get logs => List.unmodifiable(_logs);

  void _scheduleLogNotification() {
    if (_disposed || !_logChanges.hasListeners || _logNotifyTimer != null) {
      return;
    }
    // Timer callbacks run outside the synchronous build phase. Batch bursts
    // without scheduling work when no log view is listening.
    _logNotifyTimer = Timer(const Duration(milliseconds: 100), () {
      _logNotifyTimer = null;
      if (!_disposed && _logChanges.hasListeners) {
        _logChanges.notifyListeners();
      }
    });
  }

  void _notifyListenersSafely() {
    if (_disposed) return;
    SchedulerPhase phase;
    try {
      phase = SchedulerBinding.instance.schedulerPhase;
    } catch (_) {
      // Binding not ready yet; safe to notify synchronously.
      notifyListeners();
      return;
    }
    if (phase != SchedulerPhase.idle) {
      SchedulerBinding.instance.addPostFrameCallback((_) {
        if (!_disposed && hasListeners) {
          notifyListeners();
        }
      });
      return;
    }
    notifyListeners();
  }

  /// 处理设置按钮点击
  void onSettingsClicked() {
    _handleTrigger();
  }

  /// 处理版本信息点击
  void onVersionClicked() {
    _handleTrigger();
  }

  /// 统一处理触发逻辑
  void _handleTrigger() {
    final now = DateTime.now();

    // 如果距离上次点击超过2秒，重置计数
    if (_lastClickTime != null &&
        now.difference(_lastClickTime!).inSeconds > 2) {
      _settingsClickCount = 0;
    }

    _lastClickTime = now;
    _settingsClickCount++;

    StructuredLogService.log(
      '🔧 [DeveloperMode] 触发按钮点击次数: $_settingsClickCount',
    );

    if (_isDeveloperMode) {
      // 如果已经开启，点击5次提示（类似于 Android 逻辑）
      if (_settingsClickCount >= 5) {
        ToastUtils.show('您已处于开发者模式');
        _settingsClickCount = 0;
      }
      return;
    }

    // 连续点击5次进入开发者模式
    if (_settingsClickCount >= 5) {
      _enableDeveloperMode();
      _settingsClickCount = 0;
    } else if (_settingsClickCount >= 2) {
      // 从第2次点击开始提示进度
      ToastUtils.show('再点击 ${5 - _settingsClickCount} 次即可开启开发者模式');
    }
  }

  /// 启用开发者模式
  Future<void> _enableDeveloperMode() async {
    _isDeveloperMode = true;
    await _saveDeveloperMode();
    addLog('🚀 开发者模式已启用');
    ToastUtils.success('开发者模式已启用');
    _notifyListenersSafely();
    StructuredLogService.log('🚀 [DeveloperMode] 开发者模式已启用');
  }

  /// 禁用开发者模式
  Future<void> disableDeveloperMode() async {
    _isDeveloperMode = false;
    _logs.clear();
    _logNotifyTimer?.cancel();
    _logNotifyTimer = null;
    _scheduleLogNotification();
    await _saveDeveloperMode();
    _notifyListenersSafely();
    StructuredLogService.log('🔒 [DeveloperMode] 开发者模式已禁用');
  }

  /// 切换性能叠加层开关
  Future<void> togglePerformanceOverlay(bool value) async {
    _showPerformanceOverlay = value;
    await _saveDeveloperMode();
    addLog(value ? '📈 已启用性能叠加层' : '📈 已禁用性能叠加层');
    _notifyListenersSafely();
  }

  /// 添加日志
  void addLog(String message) {
    if (_disposed || !_isDeveloperMode) return;
    final timestamp = DateTime.now().toString().substring(11, 19);
    final logEntry = '[$timestamp] $message';
    _logs.addLast(logEntry);

    // 限制日志数量，最多保留1000条
    if (_logs.length > 1000) {
      _logs.removeFirst();
    }

    _scheduleLogNotification();
  }

  /// Avoid preparing detailed diagnostics when collection is disabled.
  void addLogLazy(String Function() message) {
    if (_disposed || !_isDeveloperMode) return;
    addLog(message());
  }

  /// 清除所有日志
  void clearLogs() {
    _logs.clear();
    addLog('🗑️ 日志已清除');
    _scheduleLogNotification();
  }

  /// 加载开发者模式状态
  Future<void> _loadDeveloperMode() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _isDeveloperMode = prefs.getBool('developer_mode') ?? false;
      _showPerformanceOverlay =
          prefs.getBool('show_performance_overlay') ?? false;
      _isInitialized = true;
      if (_isDeveloperMode) {
        StructuredLogService.log('🔧 [DeveloperMode] 从本地加载: 已启用');
        addLog('🔄 开发者模式状态已恢复');
      }
      _notifyListenersSafely();
    } catch (e) {
      StructuredLogService.log('❌ [DeveloperMode] 加载失败: $e');
      _isInitialized = true; // 即使加载失败也标记为已初始化，使用默认值
      _notifyListenersSafely();
    }
  }

  /// 保存开发者模式状态
  Future<void> _saveDeveloperMode() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('developer_mode', _isDeveloperMode);
      await prefs.setBool('show_performance_overlay', _showPerformanceOverlay);
      StructuredLogService.log(
        '💾 [DeveloperMode] 状态已保存: 开发者模式=$_isDeveloperMode',
      );
    } catch (e) {
      StructuredLogService.log('❌ [DeveloperMode] 保存失败: $e');
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _logNotifyTimer?.cancel();
    _logChanges.dispose();
    _logs.clear();
    super.dispose();
  }
}
