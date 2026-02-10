import 'dart:io';
import 'package:fluent_ui/fluent_ui.dart' as fluent;
import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import '../models/announcement.dart';
import '../services/announcement_service.dart';
import '../utils/theme_manager.dart';

/// 全局公告弹窗 - 根据当前主题自动选择合适的UI风格
class AnnouncementDialog {
  /// 显示公告弹窗
  static Future<void> show(BuildContext context, Announcement announcement) async {
    final themeManager = ThemeManager();

    // 根据平台和主题框架选择合适的弹窗样式
    if (themeManager.isDesktopFluentUI) {
      await _showFluentDialog(context, announcement);
    } else if ((Platform.isIOS || Platform.isAndroid) && themeManager.isCupertinoFramework) {
      await _showCupertinoDialog(context, announcement);
    } else {
      await _showMaterialDialog(context, announcement);
    }
  }

  /// Fluent UI 风格弹窗
  static Future<void> _showFluentDialog(BuildContext context, Announcement announcement) async {
    bool dontShowAgain = false;

    await fluent.showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => fluent.ContentDialog(
          title: Text(announcement.title),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  announcement.content,
                  style: const TextStyle(fontSize: 14, height: 1.6),
                ),
                const SizedBox(height: 16),
                fluent.Checkbox(
                  checked: dontShowAgain,
                  onChanged: (value) {
                    setState(() {
                      dontShowAgain = value ?? false;
                    });
                  },
                  content: const Text('不再显示此公告'),
                ),
              ],
            ),
          ),
          actions: [
            fluent.FilledButton(
              onPressed: () async {
                await AnnouncementService().dismissAnnouncement(
                  dontShowAgain: dontShowAgain,
                );
                if (context.mounted) {
                  Navigator.of(context).pop();
                }
              },
              child: const Text('我知道了'),
            ),
          ],
        ),
      ),
    );
  }

  /// Material UI 风格弹窗
  static Future<void> _showMaterialDialog(BuildContext context, Announcement announcement) async {
    bool dontShowAgain = false;

    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: Text(announcement.title),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  announcement.content,
                  style: const TextStyle(fontSize: 14, height: 1.6),
                ),
                const SizedBox(height: 16),
                CheckboxListTile(
                  value: dontShowAgain,
                  onChanged: (value) {
                    setState(() {
                      dontShowAgain = value ?? false;
                    });
                  },
                  title: const Text('不再显示此公告'),
                  contentPadding: EdgeInsets.zero,
                  controlAffinity: ListTileControlAffinity.leading,
                ),
              ],
            ),
          ),
          actions: [
            FilledButton(
              onPressed: () async {
                await AnnouncementService().dismissAnnouncement(
                  dontShowAgain: dontShowAgain,
                );
                if (context.mounted) {
                  Navigator.of(context).pop();
                }
              },
              child: const Text('我知道了'),
            ),
          ],
        ),
      ),
    );
  }

  /// Cupertino (iOS) 风格弹窗
  static Future<void> _showCupertinoDialog(BuildContext context, Announcement announcement) async {
    bool dontShowAgain = false;

    await showCupertinoDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => CupertinoAlertDialog(
          title: Text(announcement.title),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 8),
                Text(
                  announcement.content,
                  style: const TextStyle(fontSize: 13, height: 1.5),
                  textAlign: TextAlign.left,
                ),
                const SizedBox(height: 16),
                GestureDetector(
                  onTap: () {
                    setState(() {
                      dontShowAgain = !dontShowAgain;
                    });
                  },
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        dontShowAgain
                            ? CupertinoIcons.check_mark_circled_solid
                            : CupertinoIcons.circle,
                        size: 22,
                        color: dontShowAgain
                            ? CupertinoColors.activeBlue
                            : CupertinoColors.systemGrey,
                      ),
                      const SizedBox(width: 8),
                      const Text(
                        '不再显示此公告',
                        style: TextStyle(fontSize: 13),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          actions: [
            CupertinoDialogAction(
              isDefaultAction: true,
              onPressed: () async {
                await AnnouncementService().dismissAnnouncement(
                  dontShowAgain: dontShowAgain,
                );
                if (context.mounted) {
                  Navigator.of(context).pop();
                }
              },
              child: const Text('我知道了'),
            ),
          ],
        ),
      ),
    );
  }
}
