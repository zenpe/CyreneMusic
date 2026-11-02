import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:fluent_ui/fluent_ui.dart' as fluent;
import 'package:url_launcher/url_launcher.dart';
import '../models/version_info.dart';
import '../services/version_service.dart';
import '../utils/theme_manager.dart';
import 'fluent_settings_card.dart';
import 'cupertino/cupertino_settings_widgets.dart';
import 'material/material_settings_widgets.dart';

/// Shared update controls; uses each theme's existing settings components.
class ClientUpdateSection extends StatelessWidget {
  final VersionService? service;
  const ClientUpdateSection({super.key, this.service});

  @override
  Widget build(BuildContext context) {
    final updates = service ?? VersionService();
    return AnimatedBuilder(
      animation: updates,
      builder: (context, _) {
        final subtitle = updates.hasVisibleUpdate
            ? '发现新版本 ${updates.latestVersion!.version} · 查看更新内容'
            : '从 GitHub 检查官方稳定版本';
        const automaticSubtitle = '每天检查一次，仅提示，不自动下载或安装';
        void check() => showClientUpdateDialog(context, service: updates);
        if (fluent.FluentTheme.maybeOf(context) != null) {
          return FluentSettingsGroup(
            title: '软件更新',
            children: [
              FluentSettingsTile(
                icon: Icons.system_update_outlined,
                title: '检查更新',
                subtitle: subtitle,
                onTap: check,
              ),
              FluentSwitchTile(
                icon: Icons.autorenew,
                title: '自动检查更新',
                subtitle: automaticSubtitle,
                value: updates.isEnabled,
                onChanged: updates.setEnabled,
              ),
            ],
          );
        }
        if (ThemeManager().isCupertinoFramework) {
          return Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CupertinoSettingsTile(
                icon: CupertinoIcons.arrow_down_circle,
                iconColor: CupertinoColors.systemBlue,
                title: '检查更新',
                subtitle: subtitle,
                showChevron: true,
                onTap: check,
              ),
              CupertinoSwitchTile(
                icon: CupertinoIcons.arrow_clockwise,
                iconColor: CupertinoColors.systemBlue,
                title: '自动检查更新',
                subtitle: automaticSubtitle,
                value: updates.isEnabled,
                onChanged: updates.setEnabled,
              ),
            ],
          );
        }
        return MD3SettingsSection(
          children: [
            MD3SettingsTile(
              leading: const Icon(Icons.system_update_outlined),
              title: '检查更新',
              subtitle: subtitle,
              trailing: const Icon(Icons.chevron_right),
              onTap: check,
            ),
            MD3SwitchTile(
              leading: const Icon(Icons.autorenew_outlined),
              title: '自动检查更新',
              subtitle: automaticSubtitle,
              value: updates.isEnabled,
              onChanged: updates.setEnabled,
            ),
          ],
        );
      },
    );
  }
}

Future<void> showClientUpdateDialog(
  BuildContext context, {
  VersionService? service,
  VersionInfo? release,
  Future<bool> Function(Uri)? openBrowser,
}) async {
  final child = ClientUpdateDialog(
    service: service ?? VersionService(),
    release: release,
    openBrowser: openBrowser,
  );
  if (fluent.FluentTheme.maybeOf(context) != null) {
    await fluent.showDialog<void>(context: context, builder: (_) => child);
  } else if (ThemeManager().isCupertinoFramework) {
    await showCupertinoDialog<void>(
      context: context,
      barrierDismissible: true,
      builder: (_) => child,
    );
  } else {
    await showDialog<void>(context: context, builder: (_) => child);
  }
}

/// The dialog owns its check, so closing it cannot pop an unrelated route later.
class ClientUpdateDialog extends StatefulWidget {
  final VersionService service;
  final VersionInfo? release;
  final Future<bool> Function(Uri)? openBrowser;
  const ClientUpdateDialog({
    super.key,
    required this.service,
    this.release,
    this.openBrowser,
  });
  @override
  State<ClientUpdateDialog> createState() => _ClientUpdateDialogState();
}

class _ClientUpdateDialogState extends State<ClientUpdateDialog> {
  VersionInfo? _release;
  bool _checking = false;
  bool _opening = false;
  String? _error;
  String? _browserError;

  @override
  void initState() {
    super.initState();
    _release = widget.release;
    if (_release == null) _check();
  }

  Future<void> _check() async {
    setState(() {
      _checking = true;
      _error = null;
    });
    final release = await widget.service.checkForUpdate();
    if (!mounted) return;
    setState(() {
      _checking = false;
      _release = release;
      _error = widget.service.lastError;
    });
  }

  Future<void> _open(String url) async {
    if (_opening) return;
    setState(() {
      _opening = true;
      _browserError = null;
    });
    var opened = false;
    try {
      final uri = Uri.parse(url);
      opened =
          await (widget.openBrowser?.call(uri) ??
              launchUrl(uri, mode: LaunchMode.externalApplication));
    } catch (_) {
      /* Display a selectable fallback below. */
    }
    if (!mounted) return;
    setState(() {
      _opening = false;
      if (!opened) {
        _browserError =
            '无法打开浏览器，请复制发行页地址后访问：\n'
            '${_release?.releasePage ?? VersionInfo.latestReleasePage}';
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final isFluent = fluent.FluentTheme.maybeOf(context) != null;
    final isCupertino = !isFluent && ThemeManager().isCupertinoFramework;
    final update =
        _release != null &&
        VersionInfo.compare(_release!.version, widget.service.currentVersion) >
            0;
    final download = _release?.platformDownloadUrl(widget.service.platformKey);
    final title = _checking
        ? '正在检查更新'
        : _error != null
        ? '检查失败'
        : update
        ? '发现新版本 ${_release!.version}'
        : '当前已是最新版本';
    final content = ConstrainedBox(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * .5,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('当前版本 ${widget.service.currentVersion}'),
            const SizedBox(height: 12),
            if (_checking) const Text('正在连接 GitHub…'),
            if (_error != null) Text(_error!),
            if (!_checking && _error == null && update) ...[
              Text(
                _release!.changelog.isEmpty
                    ? '此版本未提供更新说明。'
                    : _release!.changelog,
              ),
              const SizedBox(height: 16),
              Text(
                download == null
                    ? '此版本没有适合当前设备的安装包，请前往发行页查看。'
                    : widget.service.platformKey == 'windows-x64'
                    ? '浏览器下载 ZIP 后，退出应用，将压缩包全部内容解压到原程序目录并覆盖。请勿只替换 EXE。'
                    : '浏览器下载 APK 后直接覆盖安装，保留应用数据，无需卸载。',
              ),
            ],
            if (_browserError != null) ...[
              const SizedBox(height: 12),
              SelectableText(_browserError!),
            ],
          ],
        ),
      ),
    );
    Widget button(
      String label,
      VoidCallback? onPressed, {
      bool primary = false,
    }) {
      if (isFluent) {
        return primary
            ? fluent.FilledButton(onPressed: onPressed, child: Text(label))
            : fluent.Button(onPressed: onPressed, child: Text(label));
      }
      if (isCupertino) {
        return CupertinoDialogAction(
          onPressed: onPressed,
          isDefaultAction: primary,
          child: Text(label),
        );
      }
      return primary
          ? FilledButton(onPressed: onPressed, child: Text(label))
          : TextButton(onPressed: onPressed, child: Text(label));
    }

    final actions = <Widget>[
      if (!_checking && _error != null) button('重试', _check),
      if (!_checking && update && _error == null)
        button('忽略此版本', () async {
          await widget.service.ignoreCurrentVersion(_release!.version);
          if (context.mounted) Navigator.of(context).pop();
        }),
      button(update ? '稍后' : '关闭', () {
        if (_release != null) {
          widget.service.markVersionReminded(_release!.version);
        }
        Navigator.of(context).pop();
      }),
      if (!_checking)
        button(
          '发行页',
          _opening
              ? null
              : () => _open(
                  _release?.releasePage ?? VersionInfo.latestReleasePage,
                ),
        ),
      if (!_checking && _error == null && update && download != null)
        button('浏览器下载', _opening ? null : () => _open(download), primary: true),
    ];
    if (isFluent) {
      return fluent.ContentDialog(
        title: Text(title),
        content: content,
        actions: [
          Wrap(
            spacing: 8,
            runSpacing: 8,
            alignment: WrapAlignment.end,
            children: actions,
          ),
        ],
      );
    }
    if (isCupertino) {
      return CupertinoAlertDialog(
        title: Text(title),
        content: content,
        actions: actions,
      );
    }
    return AlertDialog(
      title: Text(title),
      content: SizedBox(width: 480, child: content),
      actions: actions,
      scrollable: true,
    );
  }
}
