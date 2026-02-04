import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'package:fluent_ui/fluent_ui.dart' as fluent_ui;
import '../services/tray_service.dart';
import '../services/player_service.dart';
import '../widgets/navidrome_config_form.dart';
import '../widgets/navidrome_ui.dart';
import '../services/audio_source_service.dart';
import 'settings_page/audio_source_settings.dart';

class NavidromeSettingsPage extends StatelessWidget {
  const NavidromeSettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Scaffold(
      body: SafeArea(
        child: NavidromeConfigForm(
          showClearButton: true,
          header: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '设置',
                style: theme.textTheme.headlineMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Navidrome',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: colorScheme.outline,
                ),
              ),
              const SizedBox(height: 16),
              NavidromeSectionHeader(
                title: '账户与连接',
                padding: EdgeInsets.zero,
              ),
            ],
          ),
          footer: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              NavidromeSectionHeader(
                title: '音源',
                padding: EdgeInsets.zero,
              ),
              NavidromeCard(
                onTap: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => const AudioSourceSettings(),
                    ),
                  );
                },
                padding: const EdgeInsets.all(12),
                borderColor: colorScheme.outlineVariant,
                child: Row(
                  children: [
                    _IconBadge(
                      icon: Icons.swap_horiz,
                      background: colorScheme.primaryContainer,
                      foreground: colorScheme.onPrimaryContainer,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '切换音源',
                            style: theme.textTheme.bodyLarge?.copyWith(
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '进入音源配置与选择',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: colorScheme.outline,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Icon(Icons.chevron_right, color: colorScheme.outline),
                  ],
                ),
              ),
              const SizedBox(height: 10),
              NavidromeCard(
                onTap: () => _confirmResetAudioSource(context),
                padding: const EdgeInsets.all(12),
                borderColor: colorScheme.error.withOpacity(0.35),
                backgroundColor: colorScheme.errorContainer.withOpacity(0.18),
                child: Row(
                  children: [
                    _IconBadge(
                      icon: Icons.refresh,
                      background: colorScheme.errorContainer,
                      foreground: colorScheme.error,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '回到初始音源配置',
                            style: theme.textTheme.bodyLarge?.copyWith(
                              color: colorScheme.error,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '清除当前音源选择并回到引导页',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: colorScheme.outline,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Icon(Icons.chevron_right, color: colorScheme.error),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              NavidromeSectionHeader(
                title: '应用',
                padding: EdgeInsets.zero,
              ),
              NavidromeCard(
                onTap: () => _confirmExit(context),
                padding: const EdgeInsets.all(12),
                backgroundColor: colorScheme.errorContainer.withOpacity(0.25),
                borderColor: colorScheme.error.withOpacity(0.4),
                child: Row(
                  children: [
                    _IconBadge(
                      icon: Icons.power_settings_new,
                      background: colorScheme.errorContainer,
                      foreground: colorScheme.error,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        '退出应用',
                        style: theme.textTheme.bodyLarge?.copyWith(
                          color: colorScheme.error,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    Icon(Icons.chevron_right, color: colorScheme.error),
                  ],
                ),
              ),
            ],
          ),
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

  void _confirmResetAudioSource(BuildContext context) {
    if (Platform.isWindows || Platform.isMacOS || Platform.isLinux) {
      fluent_ui.showDialog(
        context: context,
        builder: (context) => fluent_ui.ContentDialog(
          title: const fluent_ui.Text('回到初始配置'),
          content: const fluent_ui.Text('确定要清除当前音源选择吗？'),
          actions: [
            fluent_ui.Button(
              onPressed: () => Navigator.pop(context),
              child: const fluent_ui.Text('取消'),
            ),
            fluent_ui.FilledButton(
              onPressed: () async {
                Navigator.pop(context);
                AudioSourceService().clear();
              },
              child: const fluent_ui.Text('确认'),
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
          title: const Text('回到初始配置'),
          content: const Text('确定要清除当前音源选择吗？'),
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
                AudioSourceService().clear();
              },
              child: const Text('确认'),
            ),
          ],
        ),
      );
      return;
    }

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('回到初始配置'),
        content: const Text('确定要清除当前音源选择吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () async {
              Navigator.pop(context);
              AudioSourceService().clear();
            },
            child: const Text('确认'),
          ),
        ],
      ),
    );
  }
}

class _IconBadge extends StatelessWidget {
  final IconData icon;
  final Color background;
  final Color foreground;

  const _IconBadge({
    required this.icon,
    required this.background,
    required this.foreground,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 36,
      height: 36,
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Icon(icon, size: 18, color: foreground),
    );
  }
}
