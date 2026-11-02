import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:fluent_ui/fluent_ui.dart' as fluent_ui;
import '../../services/version_service.dart';
import '../../services/developer_mode_service.dart';
import '../../utils/theme_manager.dart';
import '../../widgets/material/material_settings_widgets.dart';
import '../../widgets/cupertino/cupertino_settings_widgets.dart';
import '../../widgets/client_update_section.dart';
import 'user_agreement_page.dart';

/// 关于设置详情内容（二级页面内容，嵌入在设置页面中）
class AboutSettingsContent extends StatefulWidget {
  final VoidCallback onBack;
  final bool embed;

  const AboutSettingsContent({
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
        // 当前页面：关于（正常颜色）
        Text('关于', style: typography.title),
      ],
    );
  }

  @override
  State<AboutSettingsContent> createState() => _AboutSettingsContentState();
}

class _AboutSettingsContentState extends State<AboutSettingsContent> {
  final VersionService _versionService = VersionService();

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _versionService,
    builder: (context, _) {
      final cupertino = ThemeManager().isCupertinoFramework;
      void terms() => Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const UserAgreementPage()),
      );
      return ListView(
        padding: const EdgeInsets.symmetric(vertical: 8),
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 24),
            child: Column(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(24),
                  child: Image.asset(
                    'assets/icons/new_ico_white.png',
                    width: 96,
                    height: 96,
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  'Cyrene Music',
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                const SizedBox(height: 4),
                GestureDetector(
                  onTap: () => DeveloperModeService().onVersionClicked(),
                  child: Text('v${_versionService.currentVersion}'),
                ),
              ],
            ),
          ),
          const ClientUpdateSection(),
          const SizedBox(height: 16),
          if (cupertino) ...[
            CupertinoSettingsTile(
              icon: CupertinoIcons.doc_text,
              iconColor: CupertinoColors.systemBlue,
              title: '用户协议',
              subtitle: '查看用户协议与隐私政策',
              showChevron: true,
              onTap: terms,
            ),
            CupertinoSettingsTile(
              icon: CupertinoIcons.book,
              iconColor: CupertinoColors.systemGrey,
              title: '开放源代码许可',
              showChevron: true,
              onTap: () => _showLicensePage(context),
            ),
          ] else
            MD3SettingsSection(
              children: [
                MD3SettingsTile(
                  leading: const Icon(Icons.description_outlined),
                  title: '用户协议',
                  subtitle: '查看用户协议与隐私政策',
                  trailing: const Icon(Icons.chevron_right),
                  onTap: terms,
                ),
                MD3SettingsTile(
                  leading: const Icon(Icons.article_outlined),
                  title: '开放源代码许可',
                  subtitle: '查看第三方库许可信息',
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => _showLicensePage(context),
                ),
              ],
            ),
        ],
      );
    },
  );

  void _showLicensePage(BuildContext context) {
    showLicensePage(
      context: context,
      applicationName: 'Cyrene Music',
      applicationVersion: _versionService.currentVersion,
      applicationIcon: Padding(
        padding: const EdgeInsets.all(8.0),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: Image.asset(
            'assets/icons/new_ico_white.png',
            width: 48,
            height: 48,
          ),
        ),
      ),
    );
  }
}
