import 'structured_log_service.dart';
import 'dart:io';

import 'package:flutter/services.dart';

/// Android 自定义媒体通知控制服务
///
/// - 只在 Android 平台有效
/// - 通过 MethodChannel 调用原生 `CustomMediaNotificationService`
class AndroidMediaNotificationService {
  static final AndroidMediaNotificationService _instance =
      AndroidMediaNotificationService._internal();
  factory AndroidMediaNotificationService() => _instance;
  AndroidMediaNotificationService._internal();

  static const MethodChannel _channel =
      MethodChannel('android_media_notification');

  bool _started = false;

  /// 启动自定义媒体通知服务
  Future<void> start() async {
    if (!Platform.isAndroid) return;
    if (_started) return;

    try {
      await _channel.invokeMethod('start');
      _started = true;
      // ignore: avoid_print
      StructuredLogService.log('✅ [AndroidMediaNotification] 已请求启动自定义媒体通知服务');
    } catch (e) {
      // ignore: avoid_print
      StructuredLogService.log('❌ [AndroidMediaNotification] 启动失败: $e');
    }
  }

  /// 停止自定义媒体通知服务
  Future<void> stop() async {
    if (!Platform.isAndroid) return;
    if (!_started) return;

    try {
      await _channel.invokeMethod('stop');
      _started = false;
      // ignore: avoid_print
      StructuredLogService.log('✅ [AndroidMediaNotification] 已请求停止自定义媒体通知服务');
    } catch (e) {
      // ignore: avoid_print
      StructuredLogService.log('❌ [AndroidMediaNotification] 停止失败: $e');
    }
  }
}


