import 'structured_log_service.dart';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';

/// 权限管理服务
class PermissionService {
  static final PermissionService _instance = PermissionService._internal();
  factory PermissionService() => _instance;
  PermissionService._internal();

  /// 请求通知权限（Android 13+）
  Future<bool> requestNotificationPermission() async {
    // 只在 Android 平台请求
    if (!Platform.isAndroid) {
      return true; // 其他平台默认有权限
    }

    try {
      final status = await Permission.notification.status;

      if (status.isGranted) {
        StructuredLogService.log('✅ [PermissionService] 通知权限已授予');
        return true;
      }

      if (status.isDenied) {
        StructuredLogService.log('🔔 [PermissionService] 请求通知权限...');
        final result = await Permission.notification.request();

        if (result.isGranted) {
          StructuredLogService.log('✅ [PermissionService] 用户授予了通知权限');
          return true;
        } else if (result.isPermanentlyDenied) {
          StructuredLogService.log('❌ [PermissionService] 用户永久拒绝了通知权限');
          return false;
        } else {
          StructuredLogService.log('⚠️ [PermissionService] 用户拒绝了通知权限');
          return false;
        }
      }

      if (status.isPermanentlyDenied) {
        StructuredLogService.log('❌ [PermissionService] 通知权限被永久拒绝，需要打开设置');
        return false;
      }

      return false;
    } catch (e) {
      StructuredLogService.log('❌ [PermissionService] 请求通知权限失败: $e');
      return false;
    }
  }

  /// 请求忽略电池优化 (Android 专用)
  /// 这有助于防止后台播放因 CPU 被挂起而卡顿
  Future<bool> requestIgnoreBatteryOptimizations() async {
    if (!Platform.isAndroid) return true;

    try {
      final status = await Permission.ignoreBatteryOptimizations.status;
      if (status.isGranted) {
        StructuredLogService.log('✅ [PermissionService] 电池优化已忽略');
        return true;
      }

      StructuredLogService.log('🔋 [PermissionService] 尝试请求忽略电池优化...');
      // 弹出请求对话框
      final result = await Permission.ignoreBatteryOptimizations.request();

      if (result.isGranted) {
        StructuredLogService.log('✅ [PermissionService] 用户授予了忽略电池优化权限');
        return true;
      } else {
        StructuredLogService.log('⚠️ [PermissionService] 用户未授予忽略电池优化权限');
        return false;
      }
    } catch (e) {
      StructuredLogService.log('❌ [PermissionService] 请求电池优化异常: $e');
      return false;
    }
  }

  /// 显示权限说明对话框并跳转到设置
  Future<void> showPermissionDialog(BuildContext context) async {
    return showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('需要通知权限'),
        content: const Text(
          'Cyrene Music 需要通知权限来显示播放控制器。\n\n'
          '请在设置中允许通知权限，以便：\n'
          '• 在通知栏显示播放控制器\n'
          '• 在锁屏界面控制播放\n'
          '• 接收媒体按钮事件',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(context);
              await openAppSettings();
            },
            child: const Text('打开设置'),
          ),
        ],
      ),
    );
  }

  /// 检查并请求所有必要的权限
  Future<bool> checkAndRequestPermissions(BuildContext context) async {
    if (!Platform.isAndroid) {
      return true; // 非 Android 平台不需要
    }

    final hasNotificationPermission = await requestNotificationPermission();

    if (!hasNotificationPermission) {
      // 显示说明对话框
      if (context.mounted) {
        await showPermissionDialog(context);
      }
    }

    // 🍎 额外请求忽略电池优化（非强制，不阻断面流程）
    await requestIgnoreBatteryOptimizations();

    return hasNotificationPermission;
  }
}

