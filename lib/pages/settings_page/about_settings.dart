import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:fluent_ui/fluent_ui.dart' as fluent_ui;
import '../../widgets/fluent_settings_card.dart';
import '../../widgets/cupertino/cupertino_settings_widgets.dart';

import '../../services/version_service.dart';
import '../../widgets/client_update_section.dart';
import '../../services/developer_mode_service.dart';
import '../../utils/theme_manager.dart';
import '../../widgets/material/material_settings_widgets.dart';

/// 关于设置组件（设置页面入口）
class AboutSettings extends StatefulWidget {
  /// 点击关于入口时的回调（用于打开二级页面）
  final VoidCallback? onTap;

  const AboutSettings({super.key, this.onTap});

  @override
  State<AboutSettings> createState() => _AboutSettingsState();
}

class _AboutSettingsState extends State<AboutSettings> {
  final VersionService _versionService = VersionService();

  @override
  void initState() {
    super.initState();
    _versionService.addListener(_onServiceChanged);
  }

  @override
  void dispose() {
    _versionService.removeListener(_onServiceChanged);
    super.dispose();
  }

  void _onServiceChanged() {
    if (!mounted || !context.mounted) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !context.mounted) return;
      setState(() {});
    });
  }

  @override
  Widget build(BuildContext context) {
    final isFluent = fluent_ui.FluentTheme.maybeOf(context) != null;
    final isCupertino = ThemeManager().isCupertinoFramework;

    // Fluent UI 保持原有完整展示
    if (isFluent) {
      return _buildFluentUI(context);
    }

    // Material/Cupertino 显示简化入口
    if (isCupertino) {
      return _buildCupertinoEntry(context);
    }

    return _buildMaterialEntry(context);
  }

  /// 构建 Material UI 简化入口
  Widget _buildMaterialEntry(BuildContext context) {
    return MD3SettingsSection(
      children: [
        MD3SettingsTile(
          leading: const Icon(Icons.info_outline),
          title: '关于',
          subtitle: _versionService.hasVisibleUpdate
              ? 'v${_versionService.currentVersion} · 有新版本'
              : 'v${_versionService.currentVersion}',
          trailing: const Icon(Icons.chevron_right),
          onTap: widget.onTap,
          onLongPress: () =>
              DeveloperModeService().onVersionClicked(), // 额外支持长按触发
        ),
      ],
    );
  }

  /// 构建 Cupertino 简化入口
  Widget _buildCupertinoEntry(BuildContext context) {
    return CupertinoSettingsTile(
      icon: CupertinoIcons.info,
      iconColor: CupertinoColors.systemBlue,
      title: '关于',
      subtitle: _versionService.hasVisibleUpdate
          ? 'v${_versionService.currentVersion} · 有新版本'
          : 'v${_versionService.currentVersion}',
      showChevron: true,
      onTap: widget.onTap,
    );
  }

  /// 构建 Fluent UI 版本（保持原有完整展示）
  Widget _buildFluentUI(BuildContext context) {
    return FluentSettingsGroup(
      title: '关于',
      children: [
        FluentSettingsTile(
          icon: Icons.info_outline,
          title: '版本信息',
          subtitle: _versionService.hasVisibleUpdate
              ? 'v${_versionService.currentVersion} · 有新版本'
              : 'v${_versionService.currentVersion}',
          onTap: () => _showAboutDialogFluent(context),
        ),
        const ClientUpdateSection(),
      ],
    );
  }

  void _showAboutDialogFluent(BuildContext context) {
    fluent_ui.showDialog(
      context: context,
      builder: (context) => fluent_ui.ContentDialog(
        title: const Text('关于 Cyrene Music'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('版本: ${_versionService.currentVersion}'),
            const SizedBox(height: 8),
            const Text('一个跨平台的音乐与视频聚合播放器'),
            const SizedBox(height: 8),
            const Text('支持网易云音乐、QQ音乐、酷狗音乐、Bilibili等平台'),
          ],
        ),
        actions: [
          fluent_ui.Button(
            onPressed: () => Navigator.pop(context),
            child: const Text('关闭'),
          ),
        ],
      ),
    );
  }
}
