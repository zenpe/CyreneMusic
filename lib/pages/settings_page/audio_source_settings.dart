import 'dart:io';
import 'package:flutter/material.dart';
import 'package:fluent_ui/fluent_ui.dart' as fluent;
import '../../utils/theme_manager.dart';
import 'audio_source_settings_page.dart';

/// 音源设置页面 (Wrapper)
/// 
/// 这是一个包装类，用于在非设置页面的其他地方（如首页、发现页）独立打开音源设置。
/// 它复用了 [AudioSourceSettingsContent] update 的 UI 逻辑。
class AudioSourceSettings extends StatelessWidget {
  final bool openNavidromeSettings;

  const AudioSourceSettings({
    super.key,
    this.openNavidromeSettings = false,
  });

  @override
  Widget build(BuildContext context) {
    final themeManager = ThemeManager();
    final isFluent = themeManager.isFluentFramework && Platform.isWindows;

    if (isFluent) {
      // Fluent UI 需要自己提供 Header，因为 AudioSourceSettingsContent 在 Fluent 下仅提供内容供 SettingsPage 嵌入
      return fluent.ScaffoldPage(
        header: fluent.PageHeader(
          title: const Text('音源设置'),
          leading: fluent.IconButton(
            icon: const Icon(fluent.FluentIcons.back),
            onPressed: () => Navigator.of(context).pop(),
          ),
        ),
        content: AudioSourceSettingsContent(
          embed: false,
          openNavidromeSettings: openNavidromeSettings,
        ),
      );
    }

    // Material 和 Cupertino 风格在 AudioSourceSettingsContent 内部已经包含了 AppBar/NavigationBar
    return AudioSourceSettingsContent(
      onBack: () => Navigator.of(context).pop(),
      embed: false,
      openNavidromeSettings: openNavidromeSettings,
    );
  }
}
