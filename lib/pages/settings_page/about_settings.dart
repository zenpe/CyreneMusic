import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:fluent_ui/fluent_ui.dart' as fluent_ui;
import '../../widgets/fluent_settings_card.dart';
import '../../widgets/cupertino/cupertino_settings_widgets.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../models/version_info.dart';
import '../../services/auto_update_service.dart';
import '../../services/url_service.dart';
import '../../services/version_service.dart';
import '../../services/developer_mode_service.dart';
import '../../utils/theme_manager.dart';
import '../../widgets/material/material_settings_widgets.dart';
import '../../utils/toast_utils.dart';


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
  final AutoUpdateService _autoUpdateService = AutoUpdateService();

  @override
  void initState() {
    super.initState();
    _versionService.addListener(_onServiceChanged);
    _autoUpdateService.addListener(_onServiceChanged);
  }

  @override
  void dispose() {
    _versionService.removeListener(_onServiceChanged);
    _autoUpdateService.removeListener(_onServiceChanged);
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
          subtitle: 'v${_versionService.currentVersion}',
          trailing: const Icon(Icons.chevron_right),
          onTap: widget.onTap,
          onLongPress: () => DeveloperModeService().onVersionClicked(), // 额外支持长按触发
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
      subtitle: 'v${_versionService.currentVersion}',
      showChevron: true,
      onTap: widget.onTap,
    );
  }

  /// 构建 Fluent UI 版本（保持原有完整展示）
  Widget _buildFluentUI(BuildContext context) {
    final latestVersion = _versionService.latestVersion;
    final hasUpdate = _versionService.hasUpdate;
    final autoSupported = _autoUpdateService.isPlatformSupported;
    final showStatus = _autoUpdateService.isUpdating ||
        _autoUpdateService.requiresRestart ||
        _autoUpdateService.lastError != null ||
        (_autoUpdateService.statusMessage.isNotEmpty &&
            _autoUpdateService.statusMessage != '未开始');


    return FluentSettingsGroup(
      title: '关于',
        children: [
          FluentSettingsTile(
            icon: Icons.info_outline,
            title: '版本信息',
            subtitle: 'v${_versionService.currentVersion}',
            trailing: const Icon(Icons.chevron_right),
            onTap: () => _showAboutDialogFluent(context),
          ),
          FluentSettingsTile(
            icon: Icons.system_update,
            title: '检查更新',
            subtitle: '查看是否有新版本',
            trailing: const Icon(Icons.chevron_right),
            onTap: () => _checkForUpdateFluent(context),
          ),
          FluentSwitchTile(
            icon: Icons.autorenew,
            title: '自动更新',
            subtitle: autoSupported
                ? '开启后检测到新版本将自动下载并安装'
                : '当前平台暂不支持自动更新（仅 Windows 和 Android）',
            value: autoSupported && _autoUpdateService.isEnabled,
            onChanged: autoSupported
                ? (value) => _toggleAutoUpdate(context, value)
                : null,
          ),
          if (autoSupported)
            FluentSettingsTile(
              icon: Icons.flash_on_outlined,
              title: '一键更新',
              subtitle: hasUpdate && latestVersion != null
                  ? '发现新版本 ${latestVersion.version}，点击立即更新'
                  : '需先检查更新，若有新版本可快速安装',
              trailing: fluent_ui.FilledButton(
                onPressed: () => _triggerQuickUpdateFluent(context),
                child: const Text('开始更新'),
              ),
              onTap: () => _triggerQuickUpdateFluent(context),
            ),
          if (showStatus)
            fluent_ui.Card(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(_autoUpdateService.statusMessage),
                  if (_autoUpdateService.isUpdating) ...[
                    const SizedBox(height: 8),
                    const fluent_ui.ProgressBar(),
                  ],
                  if (_autoUpdateService.requiresRestart) ...[
                    const SizedBox(height: 8),
                    const Text('更新已完成，请退出并重新启动应用以应用最新版本。'),
                  ],
                ],
              ),
            ),
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


  Future<void> _checkForUpdateFluent(BuildContext context) async {
    // 显示 Fluent 进度对话框
    fluent_ui.showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const fluent_ui.ContentDialog(
        title: Text('检查更新'),
        content: SizedBox(height: 56, child: Center(child: fluent_ui.ProgressRing())),
      ),
    );

    try {
      final versionInfo = await _versionService.checkForUpdate(silent: false);
      if (!mounted || !context.mounted) return;
      Navigator.of(context).pop();

      if (versionInfo != null && _versionService.hasUpdate) {
        _showUpdateDialogFluent(context, versionInfo);
      } else {
        // 使用 Fluent UI 对话框显示已是最新版本
        fluent_ui.showDialog(
          context: context,
          builder: (context) => fluent_ui.ContentDialog(
            title: const Text('检查更新'),
            content: const Padding(
              padding: EdgeInsets.symmetric(vertical: 16),
              child: Row(
                children: [
                  Icon(Icons.check_circle, color: Colors.green, size: 24),
                  SizedBox(width: 12),
                  Text('当前已是最新版本'),
                ],
              ),
            ),
            actions: [
              fluent_ui.FilledButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('好的'),
              ),
            ],
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;
      Navigator.of(context).pop();
      // 使用 Fluent UI 对话框显示错误
      fluent_ui.showDialog(
        context: context,
        builder: (context) => fluent_ui.ContentDialog(
          title: const Text('检查更新失败'),
          content: Padding(
            padding: const EdgeInsets.symmetric(vertical: 16),
            child: Row(
              children: [
                const Icon(Icons.error_outline, color: Colors.red, size: 24),
                const SizedBox(width: 12),
                Expanded(child: Text('$e')),
              ],
            ),
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

  Future<void> _toggleAutoUpdate(BuildContext context, bool value) async {
    await _autoUpdateService.setEnabled(value);
    if (!mounted || !context.mounted) return;
    ToastUtils.show(value ? '已开启自动更新' : '已关闭自动更新');
  }

  Future<void> _triggerQuickUpdate(BuildContext context) async {
    VersionInfo? versionInfo = _versionService.latestVersion;

    if (versionInfo == null || !_versionService.hasUpdate) {
      versionInfo = await _versionService.checkForUpdate(silent: false);
      if (!mounted || !context.mounted) return;

      if (versionInfo == null || !_versionService.hasUpdate) {
        ToastUtils.show('当前已是最新版本');
        return;
      }
    }

    if (!_autoUpdateService.isPlatformSupported) {
      await _openDownloadLink(context, versionInfo.downloadUrl);
      return;
    }

    await _autoUpdateService.startUpdate(
      versionInfo: versionInfo,
      autoTriggered: false,
    );

    if (!mounted || !context.mounted) return;

    ToastUtils.show('已开始下载更新，请稍候查看状态');
  }

  Future<void> _triggerQuickUpdateFluent(BuildContext context) async {
    await _triggerQuickUpdate(context);
  }


  void _showUpdateDialogFluent(BuildContext context, VersionInfo versionInfo) {
    final isForceUpdate = versionInfo.forceUpdate;
    final isFixing = versionInfo.fixing;
    final platformSupported = _autoUpdateService.isPlatformSupported;
    fluent_ui.showDialog(
      context: context,
      barrierDismissible: !isForceUpdate,
      builder: (context) => PopScope(
        canPop: !isForceUpdate,
        child: fluent_ui.ContentDialog(
        title: Text(isFixing ? '服务器正在维护' : '发现新版本'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('最新版本: ${versionInfo.version}'),
            const SizedBox(height: 8),
            Text('当前版本: ${_versionService.currentVersion}'),
            const SizedBox(height: 12),
            const Text('更新内容'),
            const SizedBox(height: 8),
            Text(versionInfo.changelog),
            if (isForceUpdate && !isFixing) ...[
              const SizedBox(height: 12),
              const Text('此版本为强制更新，请尽快完成安装'),
            ],
            if (isFixing) ...[
              const SizedBox(height: 12),
              fluent_ui.InfoBar(
                title: const Text('服务器维护'),
                content: const Text('服务器正在维护中，请稍后再试'),
                severity: fluent_ui.InfoBarSeverity.warning,
              ),
            ],
          ],
        ),
        actions: [
          if (!isForceUpdate)
            fluent_ui.Button(
              onPressed: () async {
                await _versionService.ignoreCurrentVersion(versionInfo.version);
                if (!mounted || !context.mounted) return;
                Navigator.of(context).pop();
                final messenger = ScaffoldMessenger.maybeOf(context);
                if (messenger != null) {
                  messenger.showSnackBar(
                    SnackBar(
                      content: Text('已忽略版本 ${versionInfo.version}，后续将不再提示'),
                      duration: const Duration(seconds: 2),
                    ),
                  );
                }
              },
              child: const Text('稍后提醒'),
            ),
          if (!isFixing)
            fluent_ui.FilledButton(
              onPressed: () async {
                Navigator.of(context).pop();
                if (platformSupported) {
                  await _autoUpdateService.startUpdate(
                    versionInfo: versionInfo,
                    autoTriggered: false,
                  );
                  if (!mounted || !context.mounted) return;
                  final messenger = ScaffoldMessenger.maybeOf(context);
                  if (messenger != null) {
                    messenger.showSnackBar(
                      const SnackBar(
                        content: Text('正在下载并安装更新，请稍候'),
                        duration: Duration(seconds: 3),
                      ),
                    );
                  }
                } else {
                  await _openDownloadLink(context, versionInfo.downloadUrl);
                }
              },
              child: Text(platformSupported ? '一键更新' : '前往下载'),
            ),
        ],
      )),
    );
  }

  Future<void> _openDownloadLink(BuildContext context, String url) async {
    final uri = _resolveDownloadUri(url);

    try {
      if (!await canLaunchUrl(uri)) {
        throw Exception('无法打开链接');
      }
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (e) {
      if (!mounted || !context.mounted) return;
      final messenger = ScaffoldMessenger.maybeOf(context);
      if (messenger != null) {
        messenger.showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.error_outline, color: Colors.white),
                const SizedBox(width: 12),
                Expanded(child: Text('打开下载链接失败: $e')),
              ],
            ),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Uri _resolveDownloadUri(String rawUrl) {
    final uri = Uri.parse(rawUrl);
    if (uri.hasScheme) {
      return uri;
    }

    final base = UrlService().baseUrl;
    final cleanedBase = base.endsWith('/') ? base.substring(0, base.length - 1) : base;
    final formattedPath = rawUrl.startsWith('/') ? rawUrl : '/$rawUrl';
    return Uri.parse('$cleanedBase$formattedPath');
  }


  /// 构建 Cupertino UI 版本

  /// 构建 Cupertino 风格的状态卡片

  /// 显示 Cupertino 风格的关于对话框

  /// Cupertino 风格的检查更新

  /// 显示 Cupertino 风格的更新对话框
}
