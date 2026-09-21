import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:fluttertoast/fluttertoast.dart';
import '../main.dart';

class ToastUtils {
  static FToast? _fToast;

  static void _ensureInitialized() {
    if (_fToast != null) return;
    
    // 优先使用 GlobalContextHolder 提供的 context
    final context = GlobalContextHolder.context ?? MyApp.navigatorKey.currentContext;
    if (context != null) {
      _fToast = FToast();
      _fToast!.init(context);
      debugPrint('🔧 [ToastUtils] FToast 已使用 ${GlobalContextHolder.context != null ? "GlobalContext" : "navigatorKey"} 初始化');
    }
  }

  /// 显示普通消息
  static void show(String message) {
    _ensureInitialized();
    if (_fToast == null) {
      // 回退方案
      Fluttertoast.showToast(msg: message);
      return;
    }

    _fToast!.showToast(
      child: _ToastWidget(
        message: message,
        icon: Icons.info_outline,
        color: Colors.blueAccent,
      ),
      gravity: ToastGravity.BOTTOM,
      toastDuration: const Duration(seconds: 2),
    );
  }

  /// 显示带自定义图标和颜色的居中提示（如播放模式切换）
  static void infoWithIcon(String message, {required IconData icon, Color? color}) {
    _ensureInitialized();
    if (_fToast == null) {
      Fluttertoast.showToast(msg: message);
      return;
    }

    _fToast!.removeCustomToast();
    _fToast!.showToast(
      child: _ToastWidget(
        message: message,
        icon: icon,
        color: color ?? Colors.white,
      ),
      gravity: ToastGravity.CENTER,
      toastDuration: const Duration(milliseconds: 1400),
    );
  }

  /// 显示成功消息
  static void success(String message) {
    _ensureInitialized();
    if (_fToast == null) {
      Fluttertoast.showToast(
        msg: message,
        backgroundColor: Colors.green,
      );
      return;
    }

    _fToast!.showToast(
      child: _ToastWidget(
        message: message,
        icon: Icons.check_circle_outline,
        color: Colors.greenAccent,
      ),
      gravity: ToastGravity.BOTTOM,
      toastDuration: const Duration(seconds: 2),
    );
  }

  /// 显示错误消息
  static void error(String message) {
    _ensureInitialized();
    if (_fToast == null) {
      Fluttertoast.showToast(
        msg: message,
        backgroundColor: Colors.red,
      );
      return;
    }

    _fToast!.showToast(
      child: _ToastWidget(
        message: message,
        icon: Icons.error_outline,
        color: Colors.redAccent,
        showBorder: false, // 失败时不显示边框
      ),
      gravity: ToastGravity.BOTTOM,
      toastDuration: const Duration(seconds: 3),
    );
  }
}

class _ToastWidget extends StatelessWidget {
  final String message;
  final IconData icon;
  final Color color;
  final bool showBorder;

  const _ToastWidget({
    required this.message,
    required this.icon,
    required this.color,
    this.showBorder = true,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 12.0),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12.0),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.1),
            blurRadius: 10,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12.0),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 12.0, sigmaY: 12.0), // 增加模糊强度
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
            decoration: BoxDecoration(
              // 进一步调低 alpha 以显示更通透的模糊背景
              color: isDark 
                  ? Colors.black.withValues(alpha: 0.55) 
                  : Colors.white.withValues(alpha: 0.45),
              border: showBorder ? Border.all(
                color: color.withValues(alpha: 0.1),
                width: 0.5,
              ) : null,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, color: color, size: 22),
                const SizedBox(width: 10.0),
                Flexible(
                  child: Text(
                    message,
                    style: TextStyle(
                      color: isDark ? Colors.white : Colors.black87,
                      fontSize: 14.0,
                      fontWeight: FontWeight.w400,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
