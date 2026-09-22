import 'structured_log_service.dart';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:window_manager/window_manager.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 布局模式
enum LayoutMode {
  desktop,  // 桌面模式（侧边栏）
  mobile,   // 移动模式（底部导航栏）
}

/// 布局偏好设置服务
class LayoutPreferenceService extends ChangeNotifier {
  static final LayoutPreferenceService _instance = LayoutPreferenceService._internal();
  factory LayoutPreferenceService() => _instance;
  LayoutPreferenceService._internal() {
    _loadSettings();
  }

  /// 当前布局模式（仅适用于 Windows 平台）
  LayoutMode _layoutMode = LayoutMode.desktop;

  /// 从本地存储加载布局设置
  Future<void> _loadSettings() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final layoutModeIndex = prefs.getInt('layout_mode') ?? 0;
      _layoutMode = LayoutMode.values[layoutModeIndex];

      StructuredLogService.log('🖥️ [LayoutPreference] 从本地加载布局: ${_layoutMode.name}');
      notifyListeners();
    } catch (e) {
      StructuredLogService.log('❌ [LayoutPreference] 加载布局设置失败: $e');
    }
  }

  /// 保存布局模式到本地
  Future<void> _saveLayoutMode() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt('layout_mode', _layoutMode.index);
      StructuredLogService.log('💾 [LayoutPreference] 布局模式已保存: ${_layoutMode.name}');
    } catch (e) {
      StructuredLogService.log('❌ [LayoutPreference] 保存布局模式失败: $e');
    }
  }

  /// 获取当前布局模式
  LayoutMode get layoutMode => _layoutMode;

  /// 是否使用桌面布局
  bool get isDesktopLayout => _layoutMode == LayoutMode.desktop;

  /// 是否使用移动布局
  bool get isMobileLayout => _layoutMode == LayoutMode.mobile;

  /// 设置布局模式
  void setLayoutMode(LayoutMode mode) {
    if (_layoutMode != mode) {
      _layoutMode = mode;
      StructuredLogService.log('🖥️ [LayoutPreference] 布局模式已切换: ${mode == LayoutMode.desktop ? "桌面模式" : "移动模式"}');

      // 保存到本地
      _saveLayoutMode();

      // 先通知监听器更新 UI
      notifyListeners();

      // Windows 平台自动调整窗口大小（延迟执行以确保生效）
      if (Platform.isWindows) {
        // 使用 Future.delayed 确保在 UI 更新后再调整窗口
        Future.delayed(const Duration(milliseconds: 100), () {
          _adjustWindowSize(mode);
        });
      }
    }
  }

  /// 调整窗口大小
  void _adjustWindowSize(LayoutMode mode) {
    try {
      if (mode == LayoutMode.desktop) {
        // 桌面模式：宽屏布局
        final desktopSize = const Size(1320, 880);
        final minSize = const Size(800, 600);

        StructuredLogService.log('🖥️ [LayoutPreference] 调整窗口为桌面尺寸: ${desktopSize.width}x${desktopSize.height}');

        // 先设置最小尺寸，确保新尺寸不会被限制
        // 先设置最小尺寸，确保新尺寸不会被限制
        windowManager.setMinimumSize(minSize);

        // 稍作延迟，确保最小尺寸设置生效
        Future.delayed(const Duration(milliseconds: 50), () {
          windowManager.setSize(desktopSize);
          windowManager.center();
          StructuredLogService.log('✅ [LayoutPreference] 桌面窗口大小设置完成');
        });
      } else {
        // 移动模式：竖屏布局（类似手机）
        final mobileSize = const Size(400, 850);
        final minSize = const Size(360, 640);

        StructuredLogService.log('📱 [LayoutPreference] 调整窗口为移动尺寸: ${mobileSize.width}x${mobileSize.height}');

        // 先设置更小的最小尺寸，允许窄窗口
        windowManager.setMinimumSize(minSize);

        // 稍作延迟，确保最小尺寸设置生效
        Future.delayed(const Duration(milliseconds: 50), () {
          windowManager.setSize(mobileSize);
          windowManager.center();
          StructuredLogService.log('✅ [LayoutPreference] 移动窗口大小设置完成');
        });
      }
    } catch (e) {
      StructuredLogService.log('❌ [LayoutPreference] 调整窗口大小失败: $e');
    }
  }

  /// 切换到桌面布局
  void useDesktopLayout() {
    setLayoutMode(LayoutMode.desktop);
  }

  /// 切换到移动布局
  void useMobileLayout() {
    setLayoutMode(LayoutMode.mobile);
  }

  /// 获取布局模式描述
  String getLayoutDescription() {
    switch (_layoutMode) {
      case LayoutMode.desktop:
        return '桌面模式（侧边导航栏）';
      case LayoutMode.mobile:
        return '移动模式（底部导航栏）';
    }
  }
}

