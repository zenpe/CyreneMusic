import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:fluent_ui/fluent_ui.dart' as fluent_ui;
import '../../utils/theme_manager.dart';
import '../../widgets/fluent_settings_card.dart';
import '../../widgets/cupertino/cupertino_settings_widgets.dart';
import '../../widgets/material/material_settings_widgets.dart';

/// 其它设置入口组件（显示在主设置页面）
class OtherSettings extends StatelessWidget {
  final VoidCallback? onTap;

  const OtherSettings({super.key, this.onTap});

  @override
  Widget build(BuildContext context) {
    final isFluentUI = ThemeManager().isFluentFramework;

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
          leading: const Icon(Icons.tune_outlined),
          title: '其它设置',
          subtitle: '启动行为、更新提示',
          trailing: const Icon(Icons.chevron_right),
          onTap: onTap,
        ),
      ],
    );
  }

  /// 构建 Fluent UI 版本 - 入口卡片
  Widget _buildFluentUI(BuildContext context) {
    return FluentSettingsGroup(
      title: '其它',
      children: [
        FluentSettingsTile(
          icon: fluent_ui.FluentIcons.settings,
          title: '其它设置',
          subtitle: '启动行为、更新提示',
          trailing: const Icon(fluent_ui.FluentIcons.chevron_right, size: 12),
          onTap: onTap,
        ),
      ],
    );
  }

  /// 构建 Cupertino UI 版本 - 入口卡片
  Widget _buildCupertinoUI(BuildContext context) {
    return CupertinoSettingsSection(
      header: '其它',
      children: [
        CupertinoSettingsTile(
          icon: CupertinoIcons.ellipsis,
          iconColor: CupertinoColors.systemGrey,
          title: '其它设置',
          subtitle: '启动行为、更新提示',
          showChevron: true,
          onTap: onTap,
        ),
      ],
    );
  }
}
