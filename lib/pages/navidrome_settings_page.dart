import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'package:fluent_ui/fluent_ui.dart' as fluent_ui;
import '../services/tray_service.dart';
import '../services/player_service.dart';
import '../widgets/navidrome_config_form.dart';

class NavidromeSettingsPage extends StatelessWidget {
  const NavidromeSettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('设置')),
      body: NavidromeConfigForm(
        showClearButton: true,
        onSaved: () {
          if (!context.mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('设置已保存')),
          );
        },
        onCleared: () {
          if (!context.mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('登录信息已清除')),
          );
        },
      ),
      bottomNavigationBar: _buildExitTile(context),
    );
  }

  Widget _buildExitTile(BuildContext context) {
    return SafeArea(
      top: false,
      child: ListTile(
        leading: Icon(
          Icons.power_settings_new,
          color: Theme.of(context).colorScheme.error,
        ),
        title: const Text('退出应用'),
        subtitle: const Text('关闭应用程序'),
        onTap: () => _confirmExit(context),
      ),
    );
  }

  void _confirmExit(BuildContext context) {
    if (Platform.isWindows || Platform.isMacOS || Platform.isLinux) {
      fluent_ui.showDialog(
        context: context,
        builder: (context) => fluent_ui.ContentDialog(
          title: const fluent_ui.Text('退出应用'),
          content: const fluent_ui.Text('确定要退出应用吗？'),
          actions: [
            fluent_ui.Button(
              onPressed: () => Navigator.pop(context),
              child: const fluent_ui.Text('取消'),
            ),
            fluent_ui.FilledButton(
              onPressed: () async {
                Navigator.pop(context);
                await _exitApp();
              },
              child: const fluent_ui.Text('退出'),
            ),
          ],
        ),
      );
      return;
    }

    if (Platform.isIOS) {
      showCupertinoDialog(
        context: context,
        builder: (context) => CupertinoAlertDialog(
          title: const Text('退出应用'),
          content: const Text('确定要退出应用吗？'),
          actions: [
            CupertinoDialogAction(
              isDefaultAction: true,
              onPressed: () => Navigator.pop(context),
              child: const Text('取消'),
            ),
            CupertinoDialogAction(
              isDestructiveAction: true,
              onPressed: () async {
                Navigator.pop(context);
                await _exitApp();
              },
              child: const Text('退出'),
            ),
          ],
        ),
      );
      return;
    }

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('退出应用'),
        content: const Text('确定要退出应用吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () async {
              Navigator.pop(context);
              await _exitApp();
            },
            child: const Text('退出'),
          ),
        ],
      ),
    );
  }

  Future<void> _exitApp() async {
    if (Platform.isWindows || Platform.isMacOS || Platform.isLinux) {
      await TrayService().exitApp();
      return;
    }

    await PlayerService().forceDispose();
    await SystemNavigator.pop();
  }
}
