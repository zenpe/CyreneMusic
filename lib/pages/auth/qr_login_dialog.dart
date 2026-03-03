import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:fluent_ui/fluent_ui.dart' as fluent_ui;
import 'package:qr_flutter/qr_flutter.dart';

import '../../features/auth/auth_feature.dart';
import '../../services/location_service.dart';
import '../../services/qr_login_service.dart';

final AuthFacade _authFacade = AuthFacade();

Future<bool?> showQrLoginDialog(BuildContext context) async {
  final bool isFluent = fluent_ui.FluentTheme.maybeOf(context) != null;

  return isFluent
      ? await fluent_ui.showDialog<bool>(
          context: context,
          barrierDismissible: true,
          builder: (_) => const QrLoginDialog(),
        )
      : await showDialog<bool>(
          context: context,
          barrierDismissible: true,
          builder: (_) => const QrLoginDialog(),
        );
}

class QrLoginDialog extends StatefulWidget {
  const QrLoginDialog({super.key});

  @override
  State<QrLoginDialog> createState() => _QrLoginDialogState();
}

class _QrLoginDialogState extends State<QrLoginDialog> {
  Timer? _pollTimer;
  bool _isCreating = true;
  bool _isCompleting = false;
  String _statusText = '正在生成二维码...';

  QrLoginCreateResult? _created;

  @override
  void initState() {
    super.initState();
    _create();
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    super.dispose();
  }

  Future<void> _create() async {
    setState(() {
      _isCreating = true;
      _isCompleting = false;
      _statusText = '正在生成二维码...';
      _created = null;
    });

    try {
      final deviceName = Platform.isWindows ? 'Windows' : null;

      String? desktopIp;
      String? desktopLocation;
      try {
        final cached = LocationService().currentLocation;
        if (cached != null) {
          desktopIp = cached.ip;
          desktopLocation = cached.shortDescription;
        } else {
          final loc = await LocationService().fetchLocation();
          desktopIp = loc?.ip;
          desktopLocation = loc?.shortDescription;
        }
      } catch (_) {
        desktopIp = null;
        desktopLocation = null;
      }

      final created = await QrLoginService().create(
        desktopDeviceName: deviceName,
        desktopIp: desktopIp,
        desktopLocation: desktopLocation,
        expiresInSeconds: 120,
      );
      if (!mounted) return;

      setState(() {
        _created = created;
        _isCreating = false;
        _statusText = '请使用已登录的手机端扫码';
      });

      _startPolling();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isCreating = false;
        _statusText = '生成失败: $e';
      });
    }
  }

  void _startPolling() {
    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(const Duration(seconds: 2), (_) async {
      final created = _created;
      if (created == null) return;
      if (_isCompleting) return;

      try {
        final r = await QrLoginService().poll(rid: created.rid, code: created.code);
        if (!mounted) return;

        if (r.status == 'confirmed' && r.token != null && r.user != null) {
          setState(() {
            _isCompleting = true;
            _statusText = '登录中...';
          });

          await _authFacade.loginWithToken(token: r.token!, userJson: r.user!);

          if (!mounted) return;
          if (mounted) {
            final nav = Navigator.of(context);
            if (nav.canPop()) {
              nav.pop(true);
            }
          }
          return;
        }

        String next = _statusText;
        switch (r.status) {
          case 'waiting':
            next = '等待扫码...';
            break;
          case 'scanned':
            next = '已扫码，请在手机端确认登录';
            break;
          case 'expired':
            next = '二维码已过期，请刷新';
            break;
          case 'canceled':
            next = '已取消';
            break;
          default:
            next = r.status;
        }

        if (next != _statusText) {
          setState(() {
            _statusText = next;
          });
        }
      } catch (_) {
        return;
      }
    });
  }

  Future<void> _cancel() async {
    final created = _created;
    if (created != null) {
      try {
        await QrLoginService().cancel(rid: created.rid, code: created.code);
      } catch (_) {}
    }
  }

  @override
  Widget build(BuildContext context) {
    final bool isFluent = fluent_ui.FluentTheme.maybeOf(context) != null;

    final body = SizedBox(
      width: 380,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          if (_created != null)
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
              ),
              child: QrImageView(
                data: _created!.qrData,
                version: QrVersions.auto,
                size: 220,
              ),
            )
          else
            SizedBox(
              width: 240,
              height: 240,
              child: Center(
                child: _isCreating
                    ? (isFluent
                        ? const fluent_ui.ProgressRing(strokeWidth: 3)
                        : const CircularProgressIndicator(strokeWidth: 3))
                    : const Icon(Icons.qr_code_2, size: 64),
              ),
            ),
          const SizedBox(height: 12),
          Text(
            _statusText,
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );

    if (isFluent) {
      return fluent_ui.ContentDialog(
        title: Row(
          children: [
            const Icon(Icons.qr_code, size: 18),
            const SizedBox(width: 8),
            Text('扫码登录', style: fluent_ui.FluentTheme.of(context).typography.subtitle),
          ],
        ),
        content: body,
        actions: [
          fluent_ui.Button(
            onPressed: () async {
              await _cancel();
              if (context.mounted) {
                final nav = Navigator.of(context);
                if (nav.canPop()) {
                  nav.pop(false);
                }
              }
            },
            child: const Text('关闭'),
          ),
          fluent_ui.FilledButton(
            onPressed: _isCreating ? null : () => _create(),
            child: const Text('刷新二维码'),
          ),
        ],
      );
    }

    return AlertDialog(
      title: const Row(
        children: [
          Icon(Icons.qr_code),
          SizedBox(width: 8),
          Text('扫码登录'),
        ],
      ),
      content: body,
      actions: [
        TextButton(
          onPressed: () async {
            await _cancel();
            if (context.mounted) {
              final nav = Navigator.of(context);
              if (nav.canPop()) {
                nav.pop(false);
              }
            }
          },
          child: const Text('关闭'),
        ),
        FilledButton(
          onPressed: _isCreating ? null : () => _create(),
          child: const Text('刷新二维码'),
        ),
      ],
    );
  }
}



