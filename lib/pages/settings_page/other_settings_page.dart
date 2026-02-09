import 'dart:io';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:fluent_ui/fluent_ui.dart' as fluent_ui;
import '../../services/app_settings_service.dart';
import '../../utils/theme_manager.dart';
import '../../widgets/fluent_settings_card.dart';
import '../../widgets/cupertino/cupertino_settings_widgets.dart';
import '../../widgets/material/material_settings_widgets.dart';

/// 其它设置详情内容（二级页面内容，嵌入在设置页面中）
class OtherSettingsContent extends StatefulWidget {
  final VoidCallback onBack;
  final bool embed;

  const OtherSettingsContent({
    super.key,
    required this.onBack,
    this.embed = false,
  });

  @override
  State<OtherSettingsContent> createState() => _OtherSettingsContentState();
}

class _OtherSettingsContentState extends State<OtherSettingsContent> {
  @override
  void initState() {
    super.initState();
    AppSettingsService().ensureInitialized();
  }

  @override
  Widget build(BuildContext context) {
    final isFluentUI = Platform.isWindows && ThemeManager().isFluentFramework;
    final isCupertinoUI =
        (Platform.isIOS || Platform.isAndroid) && ThemeManager().isCupertinoFramework;

    if (isFluentUI) {
      return _buildFluentUI(context);
    }

    if (isCupertinoUI) {
      return _buildCupertinoUI(context);
    }

    return _buildMaterialUI(context);
  }

  Widget _buildMaterialUI(BuildContext context) {
    return AnimatedBuilder(
      animation: AppSettingsService(),
      builder: (context, _) {
        final settings = AppSettingsService();
        return ListView(
          padding: const EdgeInsets.symmetric(vertical: 8),
          children: [
            MD3SettingsSection(
              title: '启动行为',
              children: [
                MD3SwitchTile(
                  leading: const Icon(Icons.restore_outlined),
                  title: '启动时提示恢复播放',
                  subtitle: '开启后启动时会提示从上次位置继续',
                  value: settings.showResumePromptOnStartup,
                  onChanged: (value) {
                    settings.setShowResumePromptOnStartup(value);
                  },
                ),
                MD3SwitchTile(
                  leading: const Icon(Icons.system_update_alt_outlined),
                  title: '启动时弹出更新提示',
                  subtitle: '关闭后不再弹出更新提示页',
                  value: settings.showUpdatePromptOnStartup,
                  onChanged: (value) {
                    settings.setShowUpdatePromptOnStartup(value);
                  },
                ),
              ],
            ),
          ],
        );
      },
    );
  }

  Widget _buildCupertinoUI(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final backgroundColor =
        isDark ? CupertinoColors.black : CupertinoColors.systemGroupedBackground;

    final content = AnimatedBuilder(
      animation: AppSettingsService(),
      builder: (context, _) {
        final settings = AppSettingsService();
        return ListView(
          padding: const EdgeInsets.only(top: 20),
          children: [
            CupertinoSettingsSection(
              header: '启动行为',
              children: [
                CupertinoSwitchTile(
                  icon: CupertinoIcons.arrow_counterclockwise,
                  iconColor: CupertinoColors.systemBlue,
                  title: '启动时提示恢复播放',
                  subtitle: '开启后启动时会提示从上次位置继续',
                  value: settings.showResumePromptOnStartup,
                  onChanged: (value) {
                    settings.setShowResumePromptOnStartup(value);
                  },
                ),
                CupertinoSwitchTile(
                  icon: CupertinoIcons.arrow_down_circle,
                  iconColor: CupertinoColors.systemOrange,
                  title: '启动时弹出更新提示',
                  subtitle: '关闭后不再弹出更新提示页',
                  value: settings.showUpdatePromptOnStartup,
                  onChanged: (value) {
                    settings.setShowUpdatePromptOnStartup(value);
                  },
                ),
              ],
            ),
          ],
        );
      },
    );

    if (widget.embed) {
      return Container(
        color: backgroundColor,
        child: content,
      );
    }

    return CupertinoPageScaffold(
      backgroundColor: backgroundColor,
      navigationBar: CupertinoNavigationBar(
        backgroundColor: backgroundColor.withOpacity(0.8),
        border: null,
        leading: CupertinoButton(
          padding: EdgeInsets.zero,
          onPressed: widget.onBack,
          child: const Icon(CupertinoIcons.back),
        ),
        middle: const Text('其它设置'),
      ),
      child: SafeArea(
        child: content,
      ),
    );
  }

  Widget _buildFluentUI(BuildContext context) {
    return AnimatedBuilder(
      animation: AppSettingsService(),
      builder: (context, _) {
        final settings = AppSettingsService();
        return fluent_ui.ListView(
          padding: const EdgeInsets.all(24),
          children: [
            FluentSettingsGroup(
              title: '启动行为',
              children: [
                FluentSwitchTile(
                  icon: fluent_ui.FluentIcons.history,
                  title: '启动时提示恢复播放',
                  subtitle: '开启后启动时会提示从上次位置继续',
                  value: settings.showResumePromptOnStartup,
                  onChanged: (value) {
                    settings.setShowResumePromptOnStartup(value);
                  },
                ),
                FluentSwitchTile(
                  icon: fluent_ui.FluentIcons.sync,
                  title: '启动时弹出更新提示',
                  subtitle: '关闭后不再弹出更新提示页',
                  value: settings.showUpdatePromptOnStartup,
                  onChanged: (value) {
                    settings.setShowUpdatePromptOnStartup(value);
                  },
                ),
              ],
            ),
          ],
        );
      },
    );
  }
}
