import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import '../../utils/theme_manager.dart';
import 'package:fluent_ui/fluent_ui.dart' as fluent_ui;
import 'package:qr_flutter/qr_flutter.dart';
import '../../services/netease_login_service.dart';

/// 显示网易云扫码登录对话框
Future<bool?> showNeteaseQrDialog(BuildContext context, int userId) async {
  NeteaseQrCreateResult? created;
  try {
    created = await NeteaseLoginService().createQrKey();
  } catch (e) {
    if (!context.mounted) return null;
    final message = Text('获取二维码失败：$e');
    if (fluent_ui.FluentTheme.maybeOf(context) != null) {
      await fluent_ui.showDialog<void>(
        context: context,
        builder: (c) => fluent_ui.ContentDialog(
          title: const Text('暂时无法扫码'),
          content: message,
          actions: [
            fluent_ui.Button(
              onPressed: () => Navigator.pop(c),
              child: const Text('关闭'),
            ),
          ],
        ),
      );
    } else if (ThemeManager().isCupertinoFramework) {
      await showCupertinoDialog<void>(
        context: context,
        builder: (c) => CupertinoAlertDialog(
          title: const Text('暂时无法扫码'),
          content: message,
          actions: [
            CupertinoDialogAction(
              onPressed: () => Navigator.pop(c),
              child: const Text('关闭'),
            ),
          ],
        ),
      );
    } else {
      await showDialog<void>(
        context: context,
        builder: (c) => AlertDialog(
          title: const Text('暂时无法扫码'),
          content: message,
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(c),
              child: const Text('关闭'),
            ),
          ],
        ),
      );
    }
    return null;
  }

  if (!context.mounted) {
    try {
      await NeteaseLoginService().cancelBinding(created.key);
    } catch (_) {}
    return null;
  }

  final bool isFluent = fluent_ui.FluentTheme.maybeOf(context) != null;
  final bool? success;
  if (isFluent) {
    success = await fluent_ui.showDialog<bool>(
      context: context,
      barrierDismissible: true,
      builder: (context) => NeteaseQrDialog(
        userId: userId,
        qrUrl: created!.qrUrl,
        qrKey: created.key,
      ),
    );
  } else if (ThemeManager().isCupertinoFramework) {
    success = await showCupertinoDialog<bool>(
      context: context,
      builder: (_) => NeteaseQrDialog(
        userId: userId,
        qrUrl: created!.qrUrl,
        qrKey: created.key,
      ),
    );
  } else {
    success = await showDialog<bool>(
      context: context,
      barrierDismissible: true,
      builder: (context) => NeteaseQrDialog(
        userId: userId,
        qrUrl: created!.qrUrl,
        qrKey: created.key,
      ),
    );
  }

  if (success == true && context.mounted) {
    final messenger = ScaffoldMessenger.maybeOf(context);
    if (messenger != null) {
      messenger.showSnackBar(const SnackBar(content: Text('网易云账号绑定成功')));
    }
  }

  return success;
}

/// 网易云扫码对话框
class NeteaseQrDialog extends StatefulWidget {
  final int userId;
  final String qrUrl;
  final String qrKey;

  const NeteaseQrDialog({
    super.key,
    required this.userId,
    required this.qrUrl,
    required this.qrKey,
  });

  @override
  State<NeteaseQrDialog> createState() => _NeteaseQrDialogState();
}

class _NeteaseQrDialogState extends State<NeteaseQrDialog>
    with WidgetsBindingObserver {
  Timer? _timer;
  final service = NeteaseLoginService();
  late final String identity;
  String _statusText = '请使用网易云音乐 App 扫码登录';
  bool _completed = false;
  bool _busy = false;
  bool _active = true;

  @override
  void initState() {
    super.initState();
    identity = service.scope;
    WidgetsBinding.instance.addObserver(this);
    service.addListener(_identityChanged);
    _timer = Timer.periodic(
      const Duration(seconds: 2),
      (_) => unawaited(_poll()),
    );
  }

  void _identityChanged() {
    if (mounted && identity != service.scope) Navigator.of(context).pop(false);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _active = state == AppLifecycleState.resumed;
    if (_active) unawaited(_poll());
  }

  Future<void> _poll() async {
    if (_completed || _busy || !_active || identity != service.scope) return;
    _busy = true;
    try {
      final r = await service.checkQrStatus(
        key: widget.qrKey,
        userId: widget.userId,
      );
      if (!mounted || identity != service.scope) return;
      if (r.code == 803) {
        _completed = true;
        _timer?.cancel();
        Navigator.of(context).pop(true);
        return;
      }
      if (r.code == 800) _timer?.cancel();
      setState(
        () => _statusText = switch (r.code) {
          800 => '二维码已过期，请关闭后重新获取',
          802 => '已扫码，请在网易云音乐 App 中确认',
          _ => '等待扫码…',
        },
      );
    } catch (e) {
      if (!mounted) return;
      if (e is NeteaseAccountException &&
          ['BIND_SESSION_EXPIRED', 'BINDING_CHANGED'].contains(e.code)) {
        _timer?.cancel();
      }
      setState(() => _statusText = e.toString());
    } finally {
      _busy = false;
    }
  }

  Future<void> _cancel() async {
    if (!_completed && identity == service.scope) {
      try {
        await service.cancelBinding(widget.qrKey);
      } catch (_) {}
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    service.removeListener(_identityChanged);
    unawaited(_cancel());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bool isFluent = fluent_ui.FluentTheme.maybeOf(context) != null;
    if (isFluent) {
      final typo = fluent_ui.FluentTheme.of(context).typography;
      return fluent_ui.ContentDialog(
        title: Row(
          children: [
            const Icon(Icons.qr_code, size: 18),
            const SizedBox(width: 8),
            Text('绑定网易云账号', style: typo.subtitle),
          ],
        ),
        content: SizedBox(
          width: 380,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              fluent_ui.Card(
                padding: const EdgeInsets.all(12),
                child: SizedBox(
                  width: 240,
                  height: 240,
                  child: Center(
                    child: QrImageView(
                      data: widget.qrUrl,
                      version: QrVersions.auto,
                      size: 220,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              SelectableText(widget.qrUrl, style: typo.caption),
              const SizedBox(height: 12),
              Text(_statusText, style: typo.caption),
            ],
          ),
        ),
        actions: [
          fluent_ui.Button(
            onPressed: () => Navigator.pop(context),
            child: const Text('关闭'),
          ),
        ],
      );
    }

    if (ThemeManager().isCupertinoFramework) {
      return CupertinoAlertDialog(
        title: const Text('绑定网易云账号'),
        content: Column(
          children: [
            const SizedBox(height: 16),
            Container(
              color: CupertinoColors.white,
              padding: const EdgeInsets.all(8),
              child: QrImageView(data: widget.qrUrl, size: 200),
            ),
            const SizedBox(height: 12),
            Text(_statusText),
          ],
        ),
        actions: [
          CupertinoDialogAction(
            onPressed: () => Navigator.pop(context),
            child: const Text('关闭'),
          ),
        ],
      );
    }

    return AlertDialog(
      title: const Row(
        children: [Icon(Icons.qr_code), SizedBox(width: 8), Text('绑定网易云账号')],
      ),
      content: SizedBox(
        width: 360,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            SizedBox(
              width: 220,
              height: 220,
              child: Center(
                child: QrImageView(
                  data: widget.qrUrl,
                  version: QrVersions.auto,
                  size: 220,
                ),
              ),
            ),
            const SizedBox(height: 8),
            SelectableText(
              widget.qrUrl,
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 12),
            Text(_statusText, style: Theme.of(context).textTheme.bodySmall),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('关闭'),
        ),
      ],
    );
  }
}
