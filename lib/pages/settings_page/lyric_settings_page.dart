import 'dart:io';
import 'package:flutter/material.dart';
import 'package:fluent_ui/fluent_ui.dart' as fluent_ui;
import '../../utils/theme_manager.dart';
import '../../widgets/desktop_lyric_settings.dart';
import '../../widgets/android_floating_lyric_settings.dart';

/// 歌词设置详情内容（二级页面内容，嵌入在设置页面中）
class LyricSettingsContent extends StatefulWidget {
  final VoidCallback onBack;
  final bool embed;
  
  const LyricSettingsContent({
    super.key, 
    required this.onBack,
    this.embed = false,
  });

  /// 构建 Fluent UI 面包屑导航（Windows 11 24H2 风格）
  Widget buildFluentBreadcrumb(BuildContext context) {
    final theme = fluent_ui.FluentTheme.of(context);
    final typography = theme.typography;
    
    return Row(
      children: [
        // 父级：设置（颜色较浅，可点击）
        MouseRegion(
          cursor: SystemMouseCursors.click,
          child: GestureDetector(
            onTap: onBack,
            child: Text(
              '设置',
              style: typography.title?.copyWith(
                color: theme.resources.textFillColorSecondary,
              ),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Icon(
            fluent_ui.FluentIcons.chevron_right,
            size: 14,
            color: theme.resources.textFillColorSecondary,
          ),
        ),
        // 当前页面：歌词（正常颜色）
        Text(
          '歌词',
          style: typography.title,
        ),
      ],
    );
  }

  @override
  State<LyricSettingsContent> createState() => _LyricSettingsContentState();
}

class _LyricSettingsContentState extends State<LyricSettingsContent> {
  @override
  Widget build(BuildContext context) {
    final isFluentUI = Platform.isWindows && ThemeManager().isFluentFramework;
    
    if (isFluentUI) {
      return _buildFluentUI(context);
    }
    
    return _buildMaterialUI(context);
  }

  /// 构建 Material UI 版本
  Widget _buildMaterialUI(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // 平台特定的歌词设置
        if (Platform.isWindows) ...[
          _buildMaterialSection(
            context,
            title: '桌面歌词',
            children: const [DesktopLyricSettings()],
          ),
        ] else if (Platform.isAndroid) ...[
          _buildMaterialSection(
            context,
            title: '悬浮歌词',
            children: const [AndroidFloatingLyricSettings()],
          ),
        ],
      ],
    );
  }

  /// 构建 Material UI 分组
  Widget _buildMaterialSection(
    BuildContext context, {
    required String title,
    required List<Widget> children,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 8.0, left: 4.0),
          child: Text(
            title,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.bold,
              color: Theme.of(context).colorScheme.primary,
            ),
          ),
        ),
        ...children,
      ],
    );
  }

  /// 构建 Fluent UI 版本
  Widget _buildFluentUI(BuildContext context) {
    return fluent_ui.ListView(
      padding: const EdgeInsets.all(24),
      children: [
        // 桌面歌词设置（Windows 平台）
        if (Platform.isWindows) const DesktopLyricSettings(),
      ],
    );
  }
}
