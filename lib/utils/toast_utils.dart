import 'package:flutter/material.dart';
import '../main.dart';
import 'app_feedback.dart';

/// Compatibility facade for global service feedback; never queues stale messages.
class ToastUtils {
  static AppFeedback? get _feedback {
    final global = GlobalContextHolder.context;
    final context = global?.mounted == true
        ? global
        : MyApp.navigatorKey.currentState?.overlay?.context;
    return context == null ? null : AppFeedback.maybeOf(context);
  }

  static void show(String message) => _feedback?.info(message);
  static void success(String message) => _feedback?.success(message);
  static void error(String message) => _feedback?.error(message);
  static void infoWithIcon(
    String message, {
    required IconData icon,
    Color? color,
  }) => _feedback?.info(message, icon: icon, operationKey: 'playback-mode');
}
