import 'dart:io';
import 'package:flutter/material.dart';
import 'package:fluent_ui/fluent_ui.dart' as fluent_ui;
import '../../utils/theme_manager.dart';
import '../../services/desktop_lyric_service.dart';
import '../../services/android_floating_lyric_service.dart';
import '../../widgets/fluent_settings_card.dart';

/// 歌词设置入口组件（显示在主设置页面）
class LyricSettings extends StatelessWidget {
  final VoidCallback? onTap;
  
  const LyricSettings({super.key, this.onTap});

  @override
  Widget build(BuildContext context) {
    // 仅在 Windows 和 Android 平台显示
    if (!Platform.isWindows && !Platform.isAndroid) {
      return const SizedBox.shrink();
    }
    
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
            '歌词',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.bold,
              color: Theme.of(context).colorScheme.primary,
            ),
          ),
        ),
        Card(
          child: ListTile(
            leading: const Icon(Icons.lyrics_outlined),
            title: Text(_getTitle()),
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
      title: '歌词',
      children: [
        FluentSettingsTile(
          icon: fluent_ui.FluentIcons.text_paragraph_option,
          title: _getTitle(),
          subtitle: _getSubtitle(),
          trailing: const Icon(fluent_ui.FluentIcons.chevron_right, size: 12),
          onTap: onTap,
        ),
      ],
    );
  }

  String _getTitle() {
    if (Platform.isWindows) {
      return '桌面歌词';
    } else if (Platform.isAndroid) {
      return '悬浮歌词';
    }
    return '歌词设置';
  }

  String _getSubtitle() {
    if (Platform.isWindows) {
      final isVisible = DesktopLyricService().isVisible;
      return isVisible ? '已启用' : '未启用';
    } else if (Platform.isAndroid) {
      final isVisible = AndroidFloatingLyricService().isVisible;
      return isVisible ? '已启用' : '未启用';
    }
    return '';
  }
}
