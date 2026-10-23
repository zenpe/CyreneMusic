import 'structured_log_service.dart';
import 'dart:io';
import 'package:flutter/services.dart';

/// Android 睡眠定时器原生服务接口
class AndroidSleepTimerService {
  static final AndroidSleepTimerService _instance = AndroidSleepTimerService._internal();
  factory AndroidSleepTimerService() => _instance;
  AndroidSleepTimerService._internal();

  static const MethodChannel _channel = MethodChannel('com.cyrene.music/sleep_timer');

  /// 初始化监听
  void init({required VoidCallback onCancelled}) {
    if (!Platform.isAndroid) return;

    _channel.setMethodCallHandler((call) async {
      if (call.method == 'onTimerCancelled') {
        StructuredLogService.log('📱 [AndroidSleepTimer] 收到原生取消回调');
        onCancelled();
      }
    });
  }

  /// 启动 Android 原生计时器通知
  /// [endTime] 定时结束的时刻
  Future<void> start(DateTime endTime) async {
    if (!Platform.isAndroid) return;
    try {
      await _channel.invokeMethod('start', {
        'endTimeMs': endTime.millisecondsSinceEpoch,
      });
      StructuredLogService.log('✅ [AndroidSleepTimer] 已启动原生计时器通知');
    } catch (e) {
      StructuredLogService.log('❌ [AndroidSleepTimer] 启动失败: $e');
    }
  }

  /// 停止 Android 原生计时器通知
  Future<void> stop() async {
    if (!Platform.isAndroid) return;
    try {
      await _channel.invokeMethod('stop');
      StructuredLogService.log('✅ [AndroidSleepTimer] 已停止原生计时器通知');
    } catch (e) {
      StructuredLogService.log('❌ [AndroidSleepTimer] 停止失败: $e');
    }
  }
}
