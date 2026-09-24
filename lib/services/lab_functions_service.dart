import 'dart:io';
import 'package:flutter/foundation.dart';
import 'persistent_storage_service.dart';
import 'system_media_service.dart';
import 'android_media_notification_service.dart';

/// 实验室功能服务 - 管理实验性功能的开启状态
class LabFunctionsService extends ChangeNotifier {
  static final LabFunctionsService _instance = LabFunctionsService._internal();
  factory LabFunctionsService() => _instance;
  LabFunctionsService._internal() {
    _loadSettings();
  }

  bool _enableAndroidWidget = false;
  bool _enableCustomNotification = true;

  bool get enableAndroidWidget => _enableAndroidWidget;
  bool get enableCustomNotification => _enableCustomNotification;

  /// 加载设置
  void _loadSettings() {
    final storage = PersistentStorageService();
    if (!storage.isInitialized) {
      // 如果还未初始化，监听初始化完成
      storage.addListener(_onStorageInitialized);
      return;
    }
    _enableAndroidWidget = storage.getBool('enable_android_widget') ?? false;
    _enableCustomNotification =
        storage.getBool('enable_custom_media_notification') ?? true;
  }

  void _onStorageInitialized() {
    final storage = PersistentStorageService();
    if (storage.isInitialized) {
      _enableAndroidWidget = storage.getBool('enable_android_widget') ?? false;
      _enableCustomNotification =
          storage.getBool('enable_custom_media_notification') ?? true;
      storage.removeListener(_onStorageInitialized);
      notifyListeners();
    }
  }

  /// 设置安卓桌面小部件开启状态
  Future<void> setEnableAndroidWidget(bool enable) async {
    if (_enableAndroidWidget != enable) {
      _enableAndroidWidget = enable;
      final storage = PersistentStorageService();
      await storage.setBool('enable_android_widget', enable);

      // 无论开启还是关闭，立即触发一次更新同步，以便刷新小部件显示内容
      await SystemMediaService().updateWidget();

      notifyListeners();
    }
  }

  /// 设置增强媒体通知栏卡片开启状态
  Future<void> setEnableCustomNotification(bool enable) async {
    if (_enableCustomNotification != enable) {
      _enableCustomNotification = enable;
      final storage = PersistentStorageService();
      await storage.setBool('enable_custom_media_notification', enable);

      if (Platform.isAndroid) {
        if (enable) {
          await AndroidMediaNotificationService().start();
        } else {
          await AndroidMediaNotificationService().stop();
        }
      }

      notifyListeners();
    }
  }
}
