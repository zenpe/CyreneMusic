import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:fluent_ui/fluent_ui.dart' as fluent_ui;
import '../../utils/theme_manager.dart';
import '../../services/auth_service.dart';
import '../../widgets/material/material_settings_widgets.dart';

import '../../services/lab_functions_service.dart';

/// 实验室功能内容组件
class LabFunctionsContent extends StatefulWidget {
  final VoidCallback onBack;
  final bool embed;

  const LabFunctionsContent({
    super.key,
    required this.onBack,
    this.embed = false,
  });

  @override
  State<LabFunctionsContent> createState() => _LabFunctionsContentState();
}

class _LabFunctionsContentState extends State<LabFunctionsContent> {
  final LabFunctionsService _labService = LabFunctionsService();

  @override
  void initState() {
    super.initState();
    _labService.addListener(_update);
  }

  @override
  void dispose() {
    _labService.removeListener(_update);
    super.dispose();
  }

  void _update() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    if (ThemeManager().isCupertinoFramework) {
      return _buildCupertinoUI(context);
    }
    if (Platform.isWindows && ThemeManager().isFluentFramework) {
      return _buildFluentUI(context);
    }
    return _buildMaterialUI(context);
  }

  /// 构建 Material UI 版本
  Widget _buildMaterialUI(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final isSponsor = AuthService().currentUser?.isSponsor ?? false;

    return ListView(
      padding: const EdgeInsets.symmetric(vertical: 8),
      children: [
        _buildMaterialHeader(context, colorScheme),
        const SizedBox(height: 16),
        if (!isSponsor)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Card(
              elevation: 0,
              color: colorScheme.secondaryContainer.withOpacity(0.3),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
                side: BorderSide(color: colorScheme.secondary.withOpacity(0.1)),
              ),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    Icon(Icons.stars, color: colorScheme.primary),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Text(
                        '实验室功能仅对赞助用户开放。您的支持是我们持续创新的动力。',
                        style: TextStyle(
                          color: colorScheme.onSecondaryContainer,
                          fontSize: 14,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        MD3SettingsSection(
          title: '实验性功能',
          children: [
            if (Platform.isAndroid)
              MD3SettingsTile(
                leading: const Icon(Icons.widgets_outlined),
                title: '安卓桌面小部件',
                subtitle: isSponsor ? '开启安卓主屏幕音乐控制小部件' : '🎁 赞助用户独享功能',
                enabled: isSponsor,
                trailing: Switch(
                  value: _labService.enableAndroidWidget,
                  onChanged: isSponsor ? (value) => _labService.setEnableAndroidWidget(value) : null,
                ),
              )
            else
              const MD3SettingsTile(
                leading: Icon(Icons.science_outlined),
                title: '暂无实验性功能',
                subtitle: '敬请期待更多功能的加入',
                enabled: false,
              ),
          ],
        ),
      ],
    );
  }

  Widget _buildMaterialHeader(BuildContext context, ColorScheme colorScheme) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            colorScheme.primary.withOpacity(0.1),
            colorScheme.primary.withOpacity(0.05),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(24),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.auto_awesome, color: colorScheme.primary, size: 20),
              const SizedBox(width: 8),
              Text(
                '实验室',
                style: TextStyle(
                  color: colorScheme.primary,
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            '在这里可以抢先体验还没有正式上线的功能，仅赞助用户可用。',
            style: TextStyle(
              color: colorScheme.onSurfaceVariant,
              fontSize: 14,
              height: 1.5,
            ),
          ),
        ],
      ),
    );
  }

  /// 构建 Cupertino UI 版本
  Widget _buildCupertinoUI(BuildContext context) {
    final isSponsor = AuthService().currentUser?.isSponsor ?? false;

    return ListView(
      children: [
        const SizedBox(height: 20),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Text(
            '在这里可以抢先体验还没有正式上线的功能，仅赞助用户可用。',
            style: TextStyle(
              fontSize: 13,
              color: CupertinoColors.systemGrey.resolveFrom(context),
            ),
          ),
        ),
        const SizedBox(height: 20),
        CupertinoListSection.insetGrouped(
          header: const Text('实验性功能'),
          children: [
            if (Platform.isAndroid)
              CupertinoListTile(
                leading: const Icon(CupertinoIcons.square_grid_2x2, color: CupertinoColors.systemBlue),
                title: const Text('安卓桌面小部件'),
                subtitle: Text(isSponsor ? '开启安卓主屏幕音乐控制小部件' : '🎁 赞助用户独享功能'),
                trailing: CupertinoSwitch(
                  value: _labService.enableAndroidWidget,
                  onChanged: isSponsor ? (value) => _labService.setEnableAndroidWidget(value) : null,
                ),
              )
            else
              const CupertinoListTile(
                leading: Icon(CupertinoIcons.lab_flask, color: CupertinoColors.systemPurple),
                title: Text('暂无实验性功能'),
                subtitle: Text('敬请期待更多功能的加入'),
              ),
          ],
        ),
        if (!isSponsor)
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Text(
              '注：实验室功能仅对赞助用户开放。',
              style: TextStyle(
                fontSize: 12,
                color: CupertinoColors.systemRed.resolveFrom(context).withOpacity(0.8),
              ),
            ),
          ),
      ],
    );
  }

  /// 构建 Fluent UI 版本
  Widget _buildFluentUI(BuildContext context) {
    final theme = fluent_ui.FluentTheme.of(context);
    final isSponsor = AuthService().currentUser?.isSponsor ?? false;

    return fluent_ui.ScaffoldPage.scrollable(
      header: fluent_ui.PageHeader(
        title: Row(
          children: [
            fluent_ui.Tooltip(
              message: '返回',
              child: fluent_ui.IconButton(
                icon: const Icon(fluent_ui.FluentIcons.back),
                onPressed: widget.onBack,
              ),
            ),
            const SizedBox(width: 8),
            MouseRegion(
              cursor: SystemMouseCursors.click,
              child: GestureDetector(
                onTap: widget.onBack,
                child: Text(
                  '设置',
                  style: theme.typography.title?.copyWith(
                    color: theme.resources.textFillColorSecondary,
                    fontSize: 20,
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Icon(
                fluent_ui.FluentIcons.chevron_right,
                size: 12,
                color: theme.resources.textFillColorSecondary,
              ),
            ),
            const Text(
              '实验室功能',
              style: TextStyle(fontSize: 20),
            ),
          ],
        ),
      ),
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const fluent_ui.InfoBar(
                title: Text('欢迎来到实验室'),
                content: Text('在这里可以抢先体验还没有正式上线的功能，仅赞助用户可用。'),
                severity: fluent_ui.InfoBarSeverity.info,
                isIconVisible: true,
              ),
              const SizedBox(height: 24),
              if (!isSponsor) ...[
                const fluent_ui.InfoBar(
                  title: Text('权限受限'),
                  content: Text('实验室功能仅对赞助用户开放。'),
                  severity: fluent_ui.InfoBarSeverity.warning,
                ),
                const SizedBox(height: 24),
              ],
              Text('实验性功能', style: theme.typography.subtitle),
              const SizedBox(height: 12),
              if (Platform.isAndroid)
                fluent_ui.Card(
                  child: Row(
                    children: [
                      const Icon(fluent_ui.FluentIcons.all_apps),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('安卓桌面小部件', style: theme.typography.bodyLarge),
                            Text(isSponsor ? '开启安卓主屏幕音乐控制小部件' : '🎁 赞助用户独享功能', style: theme.typography.body),
                          ],
                        ),
                      ),
                      fluent_ui.ToggleSwitch(
                        checked: _labService.enableAndroidWidget,
                        onChanged: isSponsor ? (value) => _labService.setEnableAndroidWidget(value) : null,
                      ),
                    ],
                  ),
                )
              else
                fluent_ui.Card(
                  child: Row(
                    children: [
                      const Icon(fluent_ui.FluentIcons.test_beaker),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('暂无实验性功能', style: theme.typography.bodyLarge),
                            Text('敬请期待更多功能的加入', style: theme.typography.body),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}
