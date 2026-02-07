import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:fluent_ui/fluent_ui.dart' as fluent_ui;
import '../../utils/theme_manager.dart';
import '../../widgets/material/material_settings_widgets.dart';
import '../../widgets/fluent_settings_card.dart';
import '../../widgets/cupertino/cupertino_settings_widgets.dart';

/// 实验室功能入口组件
class LabFunctions extends StatelessWidget {
  final VoidCallback? onTap;

  const LabFunctions({super.key, this.onTap});

  @override
  Widget build(BuildContext context) {
    final isFluentUI = ThemeManager().isDesktopFluentUI;
    final isCupertinoUI = ThemeManager().isCupertinoFramework;

    if (isFluentUI) {
      return _buildFluentUI(context);
    }
    if (isCupertinoUI) {
      return _buildCupertinoUI(context);
    }
    return _buildMaterialUI(context);
  }

  Widget _buildMaterialUI(BuildContext context) {
    return MD3SettingsSection(
      children: [
        MD3SettingsTile(
          leading: const Icon(Icons.science_outlined),
          title: '实验室功能',
          subtitle: '抢先体验各种实验性新特性',
          trailing: const Icon(Icons.chevron_right),
          onTap: onTap,
        ),
      ],
    );
  }

  Widget _buildCupertinoUI(BuildContext context) {
    return CupertinoSettingsCard(
      icon: CupertinoIcons.lab_flask_solid,
      iconColor: CupertinoColors.systemPurple,
      title: '实验室功能',
      subtitle: '抢先体验实验性功能',
      onTap: onTap,
    );
  }

  Widget _buildFluentUI(BuildContext context) {
    return FluentSettingsGroup(
      title: '实验',
      children: [
        FluentSettingsTile(
          icon: fluent_ui.FluentIcons.test_beaker,
          title: '实验室功能',
          subtitle: '抢先体验还没有正式上线的功能',
          trailing: const Icon(fluent_ui.FluentIcons.chevron_right, size: 12),
          onTap: onTap,
        ),
      ],
    );
  }
}
