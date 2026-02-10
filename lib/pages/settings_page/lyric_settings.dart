import 'dart:io';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:fluent_ui/fluent_ui.dart' as fluent_ui;
import '../../utils/theme_manager.dart';
import '../../services/desktop_lyric_service.dart';
import '../../services/android_floating_lyric_service.dart';
import '../../widgets/fluent_settings_card.dart';
import '../../widgets/cupertino/cupertino_settings_widgets.dart';
import '../../widgets/material/material_settings_widgets.dart';


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
    
    final isFluentUI = ThemeManager().isDesktopFluentUI;
    
    if (isFluentUI) {
      return _buildFluentUI(context);
    }
    
    if (ThemeManager().isCupertinoFramework) {
      return _buildCupertinoUI(context);
    }
    
    return _buildMaterialUI(context);
  }

  /// 构建 Material UI 版本 - 入口卡片
  Widget _buildMaterialUI(BuildContext context) {
    return MD3SettingsSection(
      children: [
        MD3SettingsTile(
          leading: const Icon(Icons.lyrics_outlined),
          title: _getTitle(),
          subtitle: _getSubtitle(),
          trailing: const Icon(Icons.chevron_right),
          onTap: onTap,
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

  /// 构建 Cupertino UI 版本 - 入口卡片
  Widget _buildCupertinoUI(BuildContext context) {
    return CupertinoSettingsSection(
      header: '歌词',
      children: [
        CupertinoSettingsTile(
          icon: CupertinoIcons.music_note_2,
          iconColor: CupertinoColors.systemPink,
          title: _getTitle(),
          subtitle: _getSubtitle(),
          showChevron: true,
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
