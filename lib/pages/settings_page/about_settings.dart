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
import '../../utils/theme_manager.dart';

/// 关于设置组件
class AboutSettings extends StatefulWidget {
  const AboutSettings({super.key});

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
    if (!mounted) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      setState(() {});
    });
  }

  @override
  Widget build(BuildContext context) {
    final isFluent = fluent_ui.FluentTheme.maybeOf(context) != null;
    final isCupertino = ThemeManager().isCupertinoFramework;
    final latestVersion = _versionService.latestVersion;
    final hasUpdate = _versionService.hasUpdate;
    final autoSupported = _autoUpdateService.isPlatformSupported;
    final showStatus = _autoUpdateService.isUpdating ||
        _autoUpdateService.requiresRestart ||
        _autoUpdateService.lastError != null ||
        (_autoUpdateService.statusMessage.isNotEmpty &&
            _autoUpdateService.statusMessage != '未开始');

    if (isFluent) {
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

    if (isCupertino) {
      return _buildCupertinoUI(context, hasUpdate, latestVersion, autoSupported, showStatus);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionTitle(context, '关于'),
        Card(
          child: Column(
            children: [
              ListTile(
                leading: const Icon(Icons.info_outline),
                title: const Text('版本信息'),
                subtitle: Text('v${_versionService.currentVersion}'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => _showAboutDialog(context),
              ),
              const Divider(height: 1),
              ListTile(
                leading: const Icon(Icons.system_update),
                title: const Text('检查更新'),
                subtitle: const Text('查看是否有新版本'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => _checkForUpdate(context),
              ),
              const Divider(height: 1),
              SwitchListTile.adaptive(
                secondary: const Icon(Icons.autorenew),
                value: autoSupported && _autoUpdateService.isEnabled,
                title: const Text('自动更新'),
                subtitle: Text(
                  autoSupported
                      ? '开启后检测到新版本将自动下载并安装'
                      : '当前平台暂不支持自动更新（仅 Windows 和 Android）',
                ),
                onChanged: autoSupported
                    ? (value) => _toggleAutoUpdate(context, value)
                    : null,
              ),
              if (autoSupported) const Divider(height: 1),
              if (autoSupported)
                ListTile(
                  leading: const Icon(Icons.flash_on_outlined),
                  title: const Text('一键更新'),
                  subtitle: Text(
                    hasUpdate && latestVersion != null
                        ? '发现新版本 ${latestVersion.version}，点击立即更新'
                        : '需先检查更新，若有新版本可快速安装',
                  ),
                  trailing: FilledButton.icon(
                    onPressed: () => _triggerQuickUpdate(context),
                    icon: const Icon(Icons.system_update_alt),
                    label: const Text('开始更新'),
                  ),
                  onTap: () => _triggerQuickUpdate(context),
                ),
              if (showStatus)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(
                            _autoUpdateService.lastError != null
                                ? Icons.error_outline
                                : _autoUpdateService.requiresRestart
                                    ? Icons.restart_alt
                                    : Icons.info_outline,
                            color: _autoUpdateService.lastError != null
                                ? Theme.of(context).colorScheme.error
                                : Theme.of(context).colorScheme.primary,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              _autoUpdateService.statusMessage,
                              style: Theme.of(context)
                                  .textTheme
                                  .bodyMedium
                                  ?.copyWith(
                                    color: _autoUpdateService.lastError != null
                                        ? Theme.of(context)
                                            .colorScheme
                                            .error
                                        : null,
                                  ),
                            ),
                          ),
                        ],
                      ),
                      if (_autoUpdateService.isUpdating) ...[
                        const SizedBox(height: 12),
                        LinearProgressIndicator(
                          value: _autoUpdateService.progress > 0 &&
                                  _autoUpdateService.progress < 1
                              ? _autoUpdateService.progress
                              : null,
                        ),
                      ],
                      if (_autoUpdateService.requiresRestart) ...[
                        const SizedBox(height: 12),
                        Text(
                          '更新已完成，请退出并重新启动应用以应用最新版本。',
                          style: Theme.of(context)
                              .textTheme
                              .bodySmall
                              ?.copyWith(fontWeight: FontWeight.bold),
                        ),
                      ],
                      if (_autoUpdateService.lastSuccessAt != null) ...[
                        const SizedBox(height: 8),
                        Text(
                          '最后更新: ${_formatDateTime(_autoUpdateService.lastSuccessAt!)}',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                      if (_autoUpdateService.lastError != null) ...[
                        const SizedBox(height: 8),
                        Text(
                          '错误详情: ${_autoUpdateService.lastError}',
                          style: Theme.of(context)
                              .textTheme
                              .bodySmall
                              ?.copyWith(color: Theme.of(context).colorScheme.error),
                        ),
                      ],
                    ],
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildSectionTitle(BuildContext context, String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12.0, left: 4.0),
      child: Text(
        title,
        style: Theme.of(context).textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.bold,
              color: Theme.of(context).colorScheme.primary,
            ),
      ),
    );
  }

  void _showAboutDialog(BuildContext context) {
    showAboutDialog(
      context: context,
      applicationName: 'Cyrene Music',
      applicationVersion: _versionService.currentVersion,
      applicationIcon: const Icon(Icons.music_note, size: 48),
      children: const [
        Text('一个跨平台的音乐与视频聚合播放器'),
        SizedBox(height: 16),
        Text('支持网易云音乐、QQ音乐、酷狗音乐、Bilibili等平台'),
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

  Future<void> _checkForUpdate(BuildContext context) async {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const Center(child: CircularProgressIndicator()),
    );

    try {
      final versionInfo = await _versionService.checkForUpdate(silent: false);

      if (!mounted) return;

      Navigator.of(context).pop();

      if (versionInfo != null && _versionService.hasUpdate) {
        _showUpdateDialog(context, versionInfo);
      } else {
        final messenger = ScaffoldMessenger.maybeOf(context);
        if (messenger != null) {
          messenger.showSnackBar(
            SnackBar(
              content: Row(
                children: const [
                  Icon(Icons.check_circle, color: Colors.white),
                  SizedBox(width: 12),
                  Expanded(child: Text('当前已是最新版本')),
                ],
              ),
              backgroundColor: Colors.green,
              duration: const Duration(seconds: 2),
            ),
          );
        }
      }
    } catch (e) {
      if (!mounted) return;

      Navigator.of(context).pop();

      final messenger = ScaffoldMessenger.maybeOf(context);
      if (messenger != null) {
        messenger.showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.error_outline, color: Colors.white),
                const SizedBox(width: 12),
                Expanded(child: Text('检查更新失败: $e')),
              ],
            ),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 3),
          ),
        );
      }
    }
  }

  Future<void> _checkForUpdateFluent(BuildContext context) async {
    // 显示 Fluent 进度对话框
    fluent_ui.showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const fluent_ui.ContentDialog(
        content: SizedBox(height: 56, child: Center(child: fluent_ui.ProgressRing())),
      ),
    );

    try {
      final versionInfo = await _versionService.checkForUpdate(silent: false);
      if (!mounted) return;
      Navigator.of(context).pop();

      if (versionInfo != null && _versionService.hasUpdate) {
        _showUpdateDialogFluent(context, versionInfo);
      } else {
        final messenger = ScaffoldMessenger.maybeOf(context);
        if (messenger != null) {
          messenger.showSnackBar(
            const SnackBar(
              content: Text('当前已是最新版本'),
              backgroundColor: Colors.green,
              duration: Duration(seconds: 2),
            ),
          );
        }
      }
    } catch (e) {
      if (!mounted) return;
      Navigator.of(context).pop();
      final messenger = ScaffoldMessenger.maybeOf(context);
      if (messenger != null) {
        messenger.showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.error_outline, color: Colors.white),
                const SizedBox(width: 12),
                Expanded(child: Text('检查更新失败: $e')),
              ],
            ),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 3),
          ),
        );
      }
    }
  }

  Future<void> _toggleAutoUpdate(BuildContext context, bool value) async {
    await _autoUpdateService.setEnabled(value);
    if (!mounted) return;
    final messenger = ScaffoldMessenger.maybeOf(context);
    if (messenger != null) {
      messenger.showSnackBar(
        SnackBar(
          content: Text(value ? '已开启自动更新' : '已关闭自动更新'),
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  Future<void> _triggerQuickUpdate(BuildContext context) async {
    VersionInfo? versionInfo = _versionService.latestVersion;

    if (versionInfo == null || !_versionService.hasUpdate) {
      versionInfo = await _versionService.checkForUpdate(silent: false);
      if (!mounted) return;

      if (versionInfo == null || !_versionService.hasUpdate) {
        final messenger = ScaffoldMessenger.maybeOf(context);
        if (messenger != null) {
          messenger.showSnackBar(
            SnackBar(
              content: Row(
                children: const [
                  Icon(Icons.check_circle, color: Colors.white),
                  SizedBox(width: 12),
                  Expanded(child: Text('当前已是最新版本')),
                ],
              ),
              backgroundColor: Colors.green,
              duration: const Duration(seconds: 2),
            ),
          );
        }
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

    if (!mounted) return;

    final messenger = ScaffoldMessenger.maybeOf(context);
    if (messenger != null) {
      messenger.showSnackBar(
        SnackBar(
          content: Row(
            children: const [
              Icon(Icons.system_update_alt, color: Colors.white),
              SizedBox(width: 12),
              Expanded(child: Text('已开始下载更新，请稍候查看状态')),
            ],
          ),
          duration: const Duration(seconds: 3),
        ),
      );
    }
  }

  Future<void> _triggerQuickUpdateFluent(BuildContext context) async {
    await _triggerQuickUpdate(context);
  }

  void _showUpdateDialog(BuildContext context, VersionInfo versionInfo) {
    final isForceUpdate = versionInfo.forceUpdate;
    final isFixing = versionInfo.fixing;
    final platformSupported = _autoUpdateService.isPlatformSupported;

    showDialog(
      context: context,
      barrierDismissible: !isForceUpdate,
      builder: (context) => PopScope(
        canPop: !isForceUpdate,
        child: AlertDialog(
          title: Row(
            children: [
              Icon(
                isFixing ? Icons.build : Icons.system_update,
                size: 28,
                color: isFixing ? Colors.orange : null,
              ),
              const SizedBox(width: 12),
              Text(isFixing ? '服务器正在维护' : '发现新版本'),
            ],
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.primaryContainer.withOpacity(0.5),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '最新版本',
                            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                                ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            versionInfo.version,
                            style: Theme.of(context).textTheme.titleLarge?.copyWith(
                                  color: Theme.of(context).colorScheme.primary,
                                  fontWeight: FontWeight.bold,
                                ),
                          ),
                        ],
                      ),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(
                            '当前版本',
                            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                                ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            _versionService.currentVersion,
                            style: Theme.of(context).textTheme.titleLarge,
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),
                Text(
                  '更新内容',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                ),
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    versionInfo.changelog,
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                ),
                if (isForceUpdate && !isFixing) ...[
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.errorContainer,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.warning,
                          color: Theme.of(context).colorScheme.error,
                          size: 24,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            '此版本为强制更新\n请尽快完成安装',
                            style: TextStyle(
                              color: Theme.of(context).colorScheme.onErrorContainer,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
                if (isFixing) ...[
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.orange.shade50,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.orange.shade200),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.build,
                          color: Colors.orange.shade700,
                          size: 24,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            '服务器正在维护中，请稍后再试',
                            style: TextStyle(
                              color: Colors.orange.shade900,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
          actions: [
            if (!isForceUpdate)
              TextButton(
                onPressed: () async {
                  await _versionService.ignoreCurrentVersion(versionInfo.version);
                  if (!mounted) return;
                  Navigator.of(context).pop();
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('已忽略版本 ${versionInfo.version}，后续将不再提示'),
                      duration: const Duration(seconds: 2),
                    ),
                  );
                },
                child: const Text('稍后提醒'),
              ),
            if (!isFixing)
              FilledButton.icon(
                onPressed: () async {
                  Navigator.of(context).pop();

                  if (platformSupported) {
                    await _autoUpdateService.startUpdate(
                      versionInfo: versionInfo,
                      autoTriggered: false,
                    );
                    if (!mounted) return;
                    final messenger = ScaffoldMessenger.maybeOf(context);
                    if (messenger != null) {
                      messenger.showSnackBar(
                        SnackBar(
                          content: Row(
                            children: const [
                              Icon(Icons.system_update, color: Colors.white),
                              SizedBox(width: 12),
                              Expanded(child: Text('正在下载并安装更新，请稍候')), 
                            ],
                          ),
                          duration: const Duration(seconds: 3),
                        ),
                      );
                    }
                  } else {
                    await _openDownloadLink(context, versionInfo.downloadUrl);
                  }
                },
                icon: const Icon(Icons.download),
                label: Text(platformSupported ? '一键更新' : '前往下载'),
              ),
          ],
        ),
      ),
    );
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
                if (!mounted) return;
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
                  if (!mounted) return;
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
      if (!mounted) return;
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

  String _formatDateTime(DateTime dateTime) {
    final local = dateTime.toLocal();
    final date = '${local.year.toString().padLeft(4, '0')}-${local.month.toString().padLeft(2, '0')}-${local.day.toString().padLeft(2, '0')}';
    final time = '${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}:${local.second.toString().padLeft(2, '0')}';
    return '$date $time';
  }

  /// 构建 Cupertino UI 版本
  Widget _buildCupertinoUI(
    BuildContext context,
    bool hasUpdate,
    VersionInfo? latestVersion,
    bool autoSupported,
    bool showStatus,
  ) {
    return Column(
      children: [
        // 版本信息
        CupertinoSettingsTile(
          icon: CupertinoIcons.info,
          iconColor: CupertinoColors.systemBlue,
          title: '版本信息',
          subtitle: 'v${_versionService.currentVersion}',
          showChevron: true,
          onTap: () => _showAboutDialogCupertino(context),
        ),
        const SizedBox(height: 1),
        // 检查更新
        CupertinoSettingsTile(
          icon: CupertinoIcons.arrow_down_circle,
          iconColor: CupertinoColors.systemGreen,
          title: '检查更新',
          subtitle: hasUpdate && latestVersion != null
              ? '发现新版本 ${latestVersion.version}'
              : '查看是否有新版本',
          showChevron: true,
          onTap: () => _checkForUpdateCupertino(context),
        ),
        const SizedBox(height: 1),
        // 自动更新开关
        CupertinoSwitchTile(
          icon: CupertinoIcons.arrow_2_circlepath,
          iconColor: CupertinoColors.systemOrange,
          title: '自动更新',
          subtitle: autoSupported
              ? '开启后检测到新版本将自动下载并安装'
              : '当前平台暂不支持自动更新',
          value: autoSupported && _autoUpdateService.isEnabled,
          onChanged: autoSupported
              ? (value) => _toggleAutoUpdate(context, value)
              : null,
        ),
        // 更新状态
        if (showStatus) ...[
          const SizedBox(height: 8),
          _buildCupertinoStatusCard(context),
        ],
      ],
    );
  }

  /// 构建 Cupertino 风格的状态卡片
  Widget _buildCupertinoStatusCard(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.all(12),
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
                _autoUpdateService.lastError != null
                    ? CupertinoIcons.exclamationmark_circle
                    : _autoUpdateService.requiresRestart
                        ? CupertinoIcons.arrow_clockwise
                        : CupertinoIcons.info_circle,
                color: _autoUpdateService.lastError != null
                    ? CupertinoColors.systemRed
                    : CupertinoColors.systemBlue,
                size: 18,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  _autoUpdateService.statusMessage,
                  style: TextStyle(
                    fontSize: 14,
                    color: _autoUpdateService.lastError != null
                        ? CupertinoColors.systemRed
                        : (isDark ? CupertinoColors.white : CupertinoColors.black),
                  ),
                ),
              ),
            ],
          ),
          if (_autoUpdateService.isUpdating) ...[
            const SizedBox(height: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: _autoUpdateService.progress > 0 && _autoUpdateService.progress < 1
                    ? _autoUpdateService.progress
                    : null,
                backgroundColor: CupertinoColors.systemGrey.withOpacity(0.3),
                valueColor: AlwaysStoppedAnimation<Color>(CupertinoColors.systemBlue),
              ),
            ),
          ],
          if (_autoUpdateService.requiresRestart) ...[
            const SizedBox(height: 8),
            Text(
              '更新已完成，请退出并重新启动应用以应用最新版本。',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.bold,
                color: isDark ? CupertinoColors.white : CupertinoColors.black,
              ),
            ),
          ],
        ],
      ),
    );
  }

  /// 显示 Cupertino 风格的关于对话框
  void _showAboutDialogCupertino(BuildContext context) {
    showCupertinoDialog<void>(
      context: context,
      builder: (context) => CupertinoAlertDialog(
        title: const Text('关于 Cyrene Music'),
        content: Padding(
          padding: const EdgeInsets.only(top: 16),
          child: Column(
            children: [
              Text('版本: ${_versionService.currentVersion}'),
              const SizedBox(height: 8),
              const Text('一个跨平台的音乐与视频聚合播放器'),
              const SizedBox(height: 8),
              const Text('支持网易云音乐、QQ音乐、酷狗音乐、Bilibili等平台'),
            ],
          ),
        ),
        actions: [
          CupertinoDialogAction(
            isDefaultAction: true,
            onPressed: () => Navigator.pop(context),
            child: const Text('关闭'),
          ),
        ],
      ),
    );
  }

  /// Cupertino 风格的检查更新
  Future<void> _checkForUpdateCupertino(BuildContext context) async {
    // 显示加载指示器
    showCupertinoDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (context) => const Center(child: CupertinoActivityIndicator()),
    );

    try {
      final versionInfo = await _versionService.checkForUpdate(silent: false);

      if (!mounted) return;

      Navigator.of(context).pop();

      if (versionInfo != null && _versionService.hasUpdate) {
        _showUpdateDialogCupertino(context, versionInfo);
      } else {
        showCupertinoDialog<void>(
          context: context,
          builder: (context) => CupertinoAlertDialog(
            title: const Text('检查更新'),
            content: const Padding(
              padding: EdgeInsets.only(top: 16),
              child: Text('当前已是最新版本'),
            ),
            actions: [
              CupertinoDialogAction(
                isDefaultAction: true,
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

      showCupertinoDialog<void>(
        context: context,
        builder: (context) => CupertinoAlertDialog(
          title: const Text('检查更新失败'),
          content: Padding(
            padding: const EdgeInsets.only(top: 16),
            child: Text('$e'),
          ),
          actions: [
            CupertinoDialogAction(
              isDefaultAction: true,
              onPressed: () => Navigator.pop(context),
              child: const Text('好的'),
            ),
          ],
        ),
      );
    }
  }

  /// 显示 Cupertino 风格的更新对话框
  void _showUpdateDialogCupertino(BuildContext context, VersionInfo versionInfo) {
    final isForceUpdate = versionInfo.forceUpdate;
    final isFixing = versionInfo.fixing;
    final platformSupported = _autoUpdateService.isPlatformSupported;

    showCupertinoDialog<void>(
      context: context,
      barrierDismissible: !isForceUpdate,
      builder: (context) => PopScope(
        canPop: !isForceUpdate,
        child: CupertinoAlertDialog(
        title: Text(isFixing ? '服务器正在维护' : '发现新版本'),
        content: Padding(
          padding: const EdgeInsets.only(top: 16),
          child: Column(
            children: [
              Text('最新版本: ${versionInfo.version}'),
              const SizedBox(height: 4),
              Text('当前版本: ${_versionService.currentVersion}'),
              const SizedBox(height: 12),
              const Text('更新内容', style: TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 4),
              Text(versionInfo.changelog),
              if (isForceUpdate && !isFixing) ...[
                const SizedBox(height: 12),
                Text(
                  '此版本为强制更新，请尽快完成安装',
                  style: TextStyle(
                    color: CupertinoColors.systemRed,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
              if (isFixing) ...[
                const SizedBox(height: 12),
                Text(
                  '服务器正在维护中，请稍后再试',
                  style: TextStyle(
                    color: CupertinoColors.systemOrange,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ],
          ),
        ),
        actions: [
          if (!isForceUpdate)
            CupertinoDialogAction(
              isDestructiveAction: false,
              onPressed: () async {
                await _versionService.ignoreCurrentVersion(versionInfo.version);
                if (!mounted) return;
                Navigator.of(context).pop();
              },
              child: const Text('稍后提醒'),
            ),
          if (!isFixing)
            CupertinoDialogAction(
              isDefaultAction: true,
              onPressed: () async {
                Navigator.of(context).pop();
                if (platformSupported) {
                  await _autoUpdateService.startUpdate(
                    versionInfo: versionInfo,
                    autoTriggered: false,
                  );
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
}