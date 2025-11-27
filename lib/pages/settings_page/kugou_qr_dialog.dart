import 'dart:async';
import 'package:flutter/material.dart';
import 'package:fluent_ui/fluent_ui.dart' as fluent_ui;
import 'package:qr_flutter/qr_flutter.dart';
import '../../services/kugou_login_service.dart';

/// 显示酷狗扫码登录对话框
Future<bool?> showKugouQrDialog(BuildContext context, int userId) async {
  KugouQrCreateResult? created;
  try {
    created = await KugouLoginService().createQrKey();
  } catch (e) {
    if (!context.mounted) return null;
    final messenger = ScaffoldMessenger.maybeOf(context);
    if (messenger != null) {
      messenger.showSnackBar(
        SnackBar(content: Text('获取二维码失败: $e')),
      );
    }
    return null;
  }

  if (!context.mounted) return null;

  final bool isFluent = fluent_ui.FluentTheme.maybeOf(context) != null;
  final success = isFluent
      ? await fluent_ui.showDialog<bool>(
          context: context,
          barrierDismissible: true,
          builder: (context) => KugouQrDialog(
            userId: userId,
            qrUrl: created!.qrUrl,
            qrcode: created.qrcode,
          ),
        )
      : await showDialog<bool>(
          context: context,
          barrierDismissible: true,
          builder: (context) => KugouQrDialog(
            userId: userId,
            qrUrl: created!.qrUrl,
            qrcode: created.qrcode,
          ),
        );

  if (success == true && context.mounted) {
    final messenger = ScaffoldMessenger.maybeOf(context);
    if (messenger != null) {
      messenger.showSnackBar(
        const SnackBar(content: Text('酷狗音乐账号绑定成功')),
      );
    }
  }

  return success;
}

/// 酷狗扫码对话框
class KugouQrDialog extends StatefulWidget {
  final int userId;
  final String qrUrl;
  final String qrcode;
  
  const KugouQrDialog({
    super.key,
    required this.userId,
    required this.qrUrl,
    required this.qrcode,
  });

  @override
  State<KugouQrDialog> createState() => _KugouQrDialogState();
}

class _KugouQrDialogState extends State<KugouQrDialog> {
  Timer? _timer;
  String _statusText = '请使用酷狗音乐 App 扫码登录';
  bool _completed = false;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 2), (t) async {
      if (_completed) return;
      try {
        final r = await KugouLoginService().checkQrStatus(
          qrcode: widget.qrcode,
          userId: widget.userId,
        );
        String nextStatus = _statusText;
        bool success = false;
        switch (r.status) {
          case 0:
            nextStatus = '二维码已过期，请关闭重试';
            break;
          case 1:
            nextStatus = '等待扫码...';
            break;
          case 2:
            nextStatus = '待确认，请在手机上确认登录';
            break;
          case 4:
            success = true;
            _completed = true;
            break;
          default:
            nextStatus = r.message ?? '状态未知';
        }
        if (!mounted) return;
        if (success) {
          Navigator.of(context).pop(true);
        } else if (nextStatus != _statusText) {
          setState(() {
            _statusText = nextStatus;
          });
        }
      } catch (_) {}
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
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
            Text('绑定酷狗音乐账号', style: typo.subtitle),
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
              SelectableText(
                widget.qrUrl,
                style: typo.caption,
              ),
              const SizedBox(height: 12),
              Text(
                _statusText,
                style: typo.caption,
              ),
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

    return AlertDialog(
      title: const Row(
        children: [
          Icon(Icons.qr_code),
          SizedBox(width: 8),
          Text('绑定酷狗音乐账号')
        ],
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
            Text(
              _statusText,
              style: Theme.of(context).textTheme.bodySmall,
            ),
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

