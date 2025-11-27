import 'dart:io';
import 'package:flutter/material.dart';
import 'package:fluent_ui/fluent_ui.dart' as fluent_ui;
import '../../utils/theme_manager.dart';
import '../../services/player_background_service.dart';
import '../../widgets/fluent_settings_card.dart';

/// 外观设置入口组件（显示在主设置页面）
class AppearanceSettings extends StatelessWidget {
  final VoidCallback? onTap;
  
  const AppearanceSettings({super.key, this.onTap});

  @override
  Widget build(BuildContext context) {
    final isFluentUI = Platform.isWindows && ThemeManager().isFluentFramework;
    
    if (isFluentUI) {
      return _buildFluentUI(context);
    }
    
    return _buildMaterialUI(context);
  }

  /// 构建 Material UI 版本 - 入口卡片
  Widget _buildMaterialUI(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 12.0, left: 4.0),
          child: Text(
            '外观',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.bold,
              color: Theme.of(context).colorScheme.primary,
            ),
          ),
        ),
        Card(
          child: ListTile(
            leading: const Icon(Icons.palette_outlined),
            title: const Text('外观设置'),
            subtitle: Text(_getSubtitle()),
            trailing: const Icon(Icons.chevron_right),
            onTap: onTap,
          ),
        ),
      ],
    );
  }

  /// 构建 Fluent UI 版本 - 入口卡片
  Widget _buildFluentUI(BuildContext context) {
    return FluentSettingsGroup(
      title: '外观',
      children: [
        FluentSettingsTile(
          icon: fluent_ui.FluentIcons.color,
          title: '外观设置',
          subtitle: _getSubtitle(),
          trailing: const Icon(fluent_ui.FluentIcons.chevron_right, size: 12),
          onTap: onTap,
        ),
      ],
    );
  }

  String _getSubtitle() {
    final themeMode = ThemeManager().themeMode;
    final themeModeStr = themeMode == ThemeMode.light 
        ? '亮色' 
        : (themeMode == ThemeMode.dark ? '暗色' : '跟随系统');
    final backgroundType = PlayerBackgroundService().getBackgroundTypeName();
    return '$themeModeStr · $backgroundType';
  }
}

