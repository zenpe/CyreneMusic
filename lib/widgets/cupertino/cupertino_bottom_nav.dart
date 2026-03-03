import 'dart:ui' as ui;
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import '../../utils/theme_manager.dart';

/// Cupertino 风格的底部导航栏
class CupertinoBottomNavBar extends StatelessWidget {
  final int currentIndex;
  final ValueChanged<int> onTap;
  final List<BottomNavigationBarItem> items;
  
  const CupertinoBottomNavBar({
    super.key,
    required this.currentIndex,
    required this.onTap,
    required this.items,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    
    return Container(
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(
            color: isDark 
                ? CupertinoColors.systemGrey.withOpacity(0.3)
                : CupertinoColors.systemGrey.withOpacity(0.2),
            width: 0.5,
          ),
        ),
      ),
      child: ClipRect(
        child: BackdropFilter(
          filter: ui.ImageFilter.blur(sigmaX: 20, sigmaY: 20),
          child: CupertinoTabBar(
            currentIndex: currentIndex,
            onTap: onTap,
            items: items,
            activeColor: ThemeManager.iosBlue,
            inactiveColor: CupertinoColors.systemGrey,
            backgroundColor: isDark 
                ? CupertinoColors.black.withOpacity(0.7)
                : CupertinoColors.white.withOpacity(0.7),
          ),
        ),
      ),
    );
  }
}

/// 显示 Cupertino 风格的更多菜单
Future<void> showCupertinoMoreSheet({
  required BuildContext context,
  required VoidCallback onHistoryTap,
  required VoidCallback onLocalTap,
  required VoidCallback onSettingsTap,
  VoidCallback? onDevTap,
  bool showDev = false,
}) async {
  await showCupertinoModalPopup<void>(
    context: context,
    builder: (context) => CupertinoActionSheet(
      title: const Text('更多'),
      actions: [
        CupertinoActionSheetAction(
          onPressed: () {
            Navigator.pop(context);
            onHistoryTap();
          },
          child: const Text('历史'),
        ),
        CupertinoActionSheetAction(
          onPressed: () {
            Navigator.pop(context);
            onLocalTap();
          },
          child: const Text('本地'),
        ),
        CupertinoActionSheetAction(
          onPressed: () {
            Navigator.pop(context);
            onSettingsTap();
          },
          child: const Text('设置'),
        ),
        if (showDev && onDevTap != null)
          CupertinoActionSheetAction(
            onPressed: () {
              Navigator.pop(context);
              onDevTap();
            },
            child: const Text('开发者工具'),
          ),
      ],
      cancelButton: CupertinoActionSheetAction(
        isDestructiveAction: true,
        onPressed: () => Navigator.pop(context),
        child: const Text('取消'),
      ),
    ),
  );
}

