import 'dart:io';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../../features/auth/auth_feature.dart';
import '../../services/qr_login_service.dart';
import '../../utils/theme_manager.dart';

final AuthFacade _authFacade = AuthFacade();

class QrLoginResultArgs {
  final String rid;
  final String code;
  final String? desktopDeviceName;
  final String? desktopIp;
  final String? desktopLocation;

  QrLoginResultArgs({
    required this.rid,
    required this.code,
    required this.desktopDeviceName,
    required this.desktopIp,
    required this.desktopLocation,
  });
}

class QrLoginResultPage extends StatefulWidget {
  final QrLoginResultArgs args;

  const QrLoginResultPage({super.key, required this.args});

  @override
  State<QrLoginResultPage> createState() => _QrLoginResultPageState();
}

class _QrLoginResultPageState extends State<QrLoginResultPage> {
  bool _submitting = false;
  String? _error;

  Future<void> _confirm() async {
    if (_submitting) return;

    setState(() {
      _submitting = true;
      _error = null;
    });

    try {
      await QrLoginService().confirm(rid: widget.args.rid, code: widget.args.code);
      if (!mounted) return;

      if (ThemeManager().isCupertinoFramework || Platform.isIOS) {
        await showCupertinoDialog<void>(
          context: context,
          builder: (_) => CupertinoAlertDialog(
            title: const Text('已确认'),
            content: const Text('桌面端将自动完成登录。'),
            actions: [
              CupertinoDialogAction(
                isDefaultAction: true,
                onPressed: () {
                  final nav = Navigator.of(context);
                  if (nav.canPop()) {
                    nav.pop();
                  }
                },
                child: const Text('好'),
              ),
            ],
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('已确认，桌面端将自动登录')),
        );
      }

      if (mounted) {
        final nav = Navigator.of(context);
        if (nav.canPop()) {
          nav.pop(true);
        }
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
      });
    } finally {
      if (mounted) {
        setState(() {
          _submitting = false;
        });
      }
    }
  }

  Widget _buildCupertinoInfoTile({required IconData icon, required String title, required String value}) {
    final bg = CupertinoDynamicColor.resolve(
      CupertinoColors.secondarySystemGroupedBackground,
      context,
    );
    final titleColor = CupertinoDynamicColor.resolve(CupertinoColors.secondaryLabel, context);
    final valueColor = CupertinoDynamicColor.resolve(CupertinoColors.label, context);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: titleColor, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(fontSize: 12, color: titleColor),
                ),
                const SizedBox(height: 3),
                Text(
                  value,
                  style: TextStyle(fontSize: 15, color: valueColor),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoTile({required IconData icon, required String title, required String value}) {
    return ListTile(
      leading: Icon(icon),
      title: Text(title),
      subtitle: Text(value),
      dense: true,
    );
  }

  @override
  Widget build(BuildContext context) {
    final user = _authFacade.currentUser;
    final now = DateTime.now();

    final deviceName = widget.args.desktopDeviceName?.trim().isNotEmpty == true
        ? widget.args.desktopDeviceName!.trim()
        : '未知设备';

    final desktopLoc = widget.args.desktopLocation?.trim();
    final desktopIp = widget.args.desktopIp?.trim();
    final desktopLocText = (desktopLoc != null && desktopLoc.isNotEmpty) ? desktopLoc : '未知';
    final desktopIpText = (desktopIp != null && desktopIp.isNotEmpty) ? desktopIp : '';

    final bool isCupertino = ThemeManager().isCupertinoFramework;
    if (isCupertino) {
      final pageBg = CupertinoDynamicColor.resolve(CupertinoColors.systemGroupedBackground, context);
      final secondaryText = CupertinoDynamicColor.resolve(CupertinoColors.secondaryLabel, context);

      return CupertinoPageScaffold(
        navigationBar: const CupertinoNavigationBar(
          middle: Text('扫码结果'),
        ),
        backgroundColor: pageBg,
        child: SafeArea(
          child: Material(
            type: MaterialType.transparency,
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: CupertinoDynamicColor.resolve(CupertinoColors.secondarySystemGroupedBackground, context),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('扫码结果', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
                      const SizedBox(height: 8),
                      Text(
                        '请确认你正在授权的设备属于你本人。确认后，桌面端将自动完成登录。',
                        style: TextStyle(color: secondaryText),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                _buildCupertinoInfoTile(
                  icon: CupertinoIcons.person_crop_circle,
                  title: '当前账号',
                  value: user == null ? '未获取到用户信息' : '${user.username}（${user.email}）',
                ),
                const SizedBox(height: 8),
                _buildCupertinoInfoTile(
                  icon: CupertinoIcons.desktopcomputer,
                  title: '登录设备',
                  value: deviceName,
                ),
                const SizedBox(height: 8),
                _buildCupertinoInfoTile(
                  icon: CupertinoIcons.time,
                  title: '授权时间',
                  value: now.toString(),
                ),
                const SizedBox(height: 8),
                _buildCupertinoInfoTile(
                  icon: CupertinoIcons.location,
                  title: '登录地',
                  value: desktopIpText.isNotEmpty ? '$desktopLocText（IP: $desktopIpText）' : desktopLocText,
                ),
                const SizedBox(height: 12),
                if (_error != null)
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: CupertinoDynamicColor.resolve(CupertinoColors.systemRed, context).withOpacity(0.12),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      _error!,
                      style: TextStyle(
                        color: CupertinoDynamicColor.resolve(CupertinoColors.systemRed, context),
                      ),
                    ),
                  ),
                const SizedBox(height: 12),
                CupertinoButton.filled(
                  onPressed: _submitting ? null : _confirm,
                  child: _submitting
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CupertinoActivityIndicator(),
                        )
                      : const Text('确认登录'),
                ),
                const SizedBox(height: 8),
                CupertinoButton(
                  onPressed: _submitting ? null : () {
                    final nav = Navigator.of(context);
                    if (nav.canPop()) {
                      nav.pop(false);
                    }
                  },
                  child: const Text('取消'),
                ),
              ],
            ),
          ),
        ),
      );
    }

    final content = ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(12.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('扫码结果', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
                const SizedBox(height: 8),
                Text(
                  '请确认你正在授权的设备属于你本人。确认后，桌面端将自动完成登录。',
                  style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        Card(
          child: Column(
            children: [
              _buildInfoTile(
                icon: Icons.account_circle,
                title: '当前账号',
                value: user == null ? '未获取到用户信息' : '${user.username}（${user.email}）',
              ),
              _buildInfoTile(
                icon: Icons.desktop_windows,
                title: '登录设备',
                value: deviceName,
              ),
              _buildInfoTile(
                icon: Icons.schedule,
                title: '授权时间',
                value: now.toString(),
              ),
              _buildInfoTile(
                icon: Icons.location_on,
                title: '登录地',
                value: desktopIpText.isNotEmpty ? '$desktopLocText（IP: $desktopIpText）' : desktopLocText,
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        if (_error != null)
          Card(
            color: Theme.of(context).colorScheme.errorContainer,
            child: Padding(
              padding: const EdgeInsets.all(12.0),
              child: Text(
                _error!,
                style: TextStyle(color: Theme.of(context).colorScheme.onErrorContainer),
              ),
            ),
          ),
        const SizedBox(height: 12),
        FilledButton.icon(
          onPressed: _submitting ? null : _confirm,
          icon: _submitting
              ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
              : const Icon(Icons.check_circle_outline),
          label: const Text('确认登录'),
        ),
        const SizedBox(height: 8),
        OutlinedButton(
          onPressed: _submitting ? null : () {
            final nav = Navigator.of(context);
            if (nav.canPop()) {
              nav.pop(false);
            }
          },
          child: const Text('取消'),
        ),
      ],
    );

    return Scaffold(
      appBar: AppBar(title: const Text('扫码结果')),
      body: content,
    );
  }
}



