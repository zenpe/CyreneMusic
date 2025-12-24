import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:fluent_ui/fluent_ui.dart' as fluent_ui;
import 'package:url_launcher/url_launcher.dart';

import 'settings_page/donate_settings.dart';
import 'settings_page/sponsor_wall.dart';
import '../utils/theme_manager.dart';
import '../services/app_config_service.dart';
import '../services/auth_service.dart';
import '../widgets/fluent_settings_card.dart';

class SupportPage extends StatefulWidget {
  const SupportPage({super.key});

  @override
  State<SupportPage> createState() => _SupportPageState();
}

class _SupportPageState extends State<SupportPage> {
  AppPublicConfig? _config;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadConfig();
  }

  Future<void> _loadConfig() async {
    try {
      final config = await AppConfigService().fetchPublicConfig();
      if (mounted) {
        setState(() {
          _config = config;
          _loading = false;
        });
      }
    } catch (e) {
      print('[SupportPage] 加载配置失败: $e');
      if (mounted) {
        setState(() {
          _loading = false;
        });
      }
    }
  }

  Future<void> _openQQGroup() async {
    final url = _config?.qqGroup.url;
    if (url == null || url.isEmpty) return;

    try {
      final uri = Uri.parse(url);
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      } else {
        print('[SupportPage] 无法打开链接: $url');
      }
    } catch (e) {
      print('[SupportPage] 打开QQ群链接失败: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final isFluentUI = Platform.isWindows && ThemeManager().isFluentFramework;
    final isCupertino = (Platform.isIOS || Platform.isAndroid) && ThemeManager().isCupertinoFramework;

    if (isFluentUI) {
      return _buildFluentPage();
    }

    if (isCupertino) {
      return _buildCupertinoPage(context);
    }

    return _buildMaterialPage(context);
  }

  /// Fluent UI 页面
  Widget _buildFluentPage() {
    final isLoggedIn = AuthService().isLoggedIn;
    
    return fluent_ui.ScaffoldPage.scrollable(
      padding: const EdgeInsets.all(24.0),
      header: const fluent_ui.PageHeader(
        title: Text('支持'),
      ),
      children: [
        // 只有登录后才显示赞助项目
        if (isLoggedIn) ...[
          const DonateSettings(),
          const SizedBox(height: 16),
        ],
        // QQ群入口
        if (!_loading && _config?.qqGroup.enabled == true)
          _buildFluentQQGroupSection(),
        if (!_loading && _config?.qqGroup.enabled == true)
          const SizedBox(height: 16),
        const SponsorWall(),
        const SizedBox(height: 40),
      ],
    );
  }

  /// iOS Cupertino 页面
  Widget _buildCupertinoPage(BuildContext context) {
    final isDark = CupertinoTheme.of(context).brightness == Brightness.dark;
    final backgroundColor = isDark
        ? CupertinoColors.black
        : CupertinoColors.systemGroupedBackground;

    return Material(
      type: MaterialType.transparency,
      child: CupertinoPageScaffold(
        backgroundColor: backgroundColor,
        child: CustomScrollView(
          slivers: [
            CupertinoSliverNavigationBar(
              largeTitle: const Text('支持'),
              backgroundColor: isDark
                  ? const Color(0xFF1C1C1E)
                  : CupertinoColors.systemBackground,
              border: null,
            ),
            SliverPadding(
              padding: const EdgeInsets.all(16.0),
              sliver: SliverList(
                delegate: SliverChildListDelegate([
                  // 只有登录后才显示赞助项目
                  if (AuthService().isLoggedIn) ...[
                    _buildCupertinoSettingsSection(
                      context,
                      title: '支持与赞助',
                      isDark: isDark,
                      children: [
                        _buildCupertinoSettingsTile(
                          context,
                          icon: CupertinoIcons.heart_fill,
                          iconColor: CupertinoColors.systemRed,
                          title: '赞助项目',
                          subtitle: '您的支持是我们持续维护与改进的动力',
                          isDark: isDark,
                          onTap: () {
                            // 打开赞助对话框
                            Navigator.of(context).push(
                              CupertinoPageRoute(
                                builder: (context) => const _CupertinoDonatePage(),
                              ),
                            );
                          },
                        ),
                      ],
                    ),
                    const SizedBox(height: 24),
                  ],
                  // QQ群入口
                  if (!_loading && _config?.qqGroup.enabled == true)
                    _buildCupertinoSettingsSection(
                      context,
                      title: '加入社区',
                      isDark: isDark,
                      children: [
                        _buildCupertinoSettingsTile(
                          context,
                          icon: CupertinoIcons.group_solid,
                          iconColor: ThemeManager.iosBlue,
                          title: '加入QQ群',
                          subtitle: _config?.qqGroup.name ?? 'QQ群',
                          isDark: isDark,
                          onTap: _openQQGroup,
                        ),
                      ],
                    ),
                  if (!_loading && _config?.qqGroup.enabled == true)
                    const SizedBox(height: 24),
                  // 赞助墙
                  const SponsorWall(),
                  // 底部安全区域
                  SizedBox(height: MediaQuery.of(context).padding.bottom + 40),
                ]),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 构建 iOS 风格的设置区域
  Widget _buildCupertinoSettingsSection(
    BuildContext context, {
    required String title,
    required bool isDark,
    required List<Widget> children,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 16.0, bottom: 8.0),
          child: Text(
            title,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w500,
              color: isDark
                  ? CupertinoColors.systemGrey
                  : CupertinoColors.systemGrey,
            ),
          ),
        ),
        Container(
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF1C1C1E) : CupertinoColors.white,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Column(children: children),
        ),
      ],
    );
  }

  /// 构建 iOS 风格的设置项
  Widget _buildCupertinoSettingsTile(
    BuildContext context, {
    required IconData icon,
    required Color iconColor,
    required String title,
    String? subtitle,
    required bool isDark,
    VoidCallback? onTap,
  }) {
    return CupertinoButton(
      padding: EdgeInsets.zero,
      onPressed: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            Container(
              width: 30,
              height: 30,
              decoration: BoxDecoration(
                color: iconColor,
                borderRadius: BorderRadius.circular(6),
              ),
              child: Icon(
                icon,
                color: CupertinoColors.white,
                size: 18,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: 16,
                      color: isDark
                          ? CupertinoColors.white
                          : CupertinoColors.black,
                    ),
                  ),
                  if (subtitle != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(
                        subtitle,
                        style: TextStyle(
                          fontSize: 13,
                          color: CupertinoColors.systemGrey,
                        ),
                      ),
                    ),
                ],
              ),
            ),
            Icon(
              CupertinoIcons.chevron_right,
              size: 16,
              color: CupertinoColors.systemGrey3,
            ),
          ],
        ),
      ),
    );
  }

  /// Material Design 页面
  Widget _buildMaterialPage(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final isLoggedIn = AuthService().isLoggedIn;
    
    return Scaffold(
      backgroundColor: colorScheme.surface,
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            floating: true,
            snap: true,
            backgroundColor: colorScheme.surface,
            title: Text(
              '支持',
              style: TextStyle(
                color: colorScheme.onSurface,
                fontSize: 24,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.all(24.0),
            sliver: SliverList(
              delegate: SliverChildListDelegate([
                // 只有登录后才显示赞助项目
                if (isLoggedIn) ...[
                  const DonateSettings(),
                  const SizedBox(height: 24),
                ],
                // QQ群入口
                if (!_loading && _config?.qqGroup.enabled == true)
                  _buildMaterialQQGroupSection(context),
                if (!_loading && _config?.qqGroup.enabled == true)
                  const SizedBox(height: 24),
                const SponsorWall(),
                const SizedBox(height: 40),
              ]),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFluentQQGroupSection() {
    final groupName = _config?.qqGroup.name ?? 'QQ群';
    return FluentSettingsGroup(
      title: '加入社区',
      children: [
        FluentSettingsTile(
          icon: fluent_ui.FluentIcons.people,
          title: '加入QQ群',
          subtitle: groupName,
          trailing: const Icon(Icons.chevron_right),
          onTap: _openQQGroup,
        ),
      ],
    );
  }

  Widget _buildMaterialQQGroupSection(BuildContext context) {
    final groupName = _config?.qqGroup.name ?? 'QQ群';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 12.0, left: 4.0),
          child: Text(
            '加入社区',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: Theme.of(context).colorScheme.primary,
                ),
          ),
        ),
        Card(
          child: ListTile(
            leading: const Icon(Icons.people_outline),
            title: const Text('加入QQ群'),
            subtitle: Text(groupName),
            trailing: const Icon(Icons.chevron_right),
            onTap: _openQQGroup,
          ),
        ),
      ],
    );
  }
}

/// iOS 风格的赞助页面（用于展示赞助相关内容）
class _CupertinoDonatePage extends StatelessWidget {
  const _CupertinoDonatePage();

  @override
  Widget build(BuildContext context) {
    final isDark = CupertinoTheme.of(context).brightness == Brightness.dark;
    final backgroundColor = isDark
        ? CupertinoColors.black
        : CupertinoColors.systemGroupedBackground;

    return Material(
      type: MaterialType.transparency,
      child: CupertinoPageScaffold(
        backgroundColor: backgroundColor,
        navigationBar: CupertinoNavigationBar(
          middle: const Text('赞助支持'),
          backgroundColor: isDark
              ? const Color(0xFF1C1C1E)
              : CupertinoColors.systemBackground,
          border: null,
        ),
        child: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 说明文字
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: isDark ? const Color(0xFF1C1C1E) : CupertinoColors.white,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(
                            CupertinoIcons.heart_fill,
                            color: CupertinoColors.systemRed,
                            size: 24,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            '感谢您的支持',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: isDark
                                  ? CupertinoColors.white
                                  : CupertinoColors.black,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Text(
                        '赞助后您可以获得独特的用户标识',
                        style: TextStyle(
                          fontSize: 15,
                          color: isDark
                              ? CupertinoColors.white
                              : CupertinoColors.black,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '是否赞助不影响任何功能',
                        style: TextStyle(
                          fontSize: 14,
                          color: CupertinoColors.systemGrey,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        '赞助任意金额您的名字将被永久保留在赞助墙上。',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                          color: ThemeManager.iosBlue,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),
                // 赞助设置组件
                const DonateSettings(),
                const SizedBox(height: 40),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

