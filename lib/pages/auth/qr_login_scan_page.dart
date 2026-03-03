import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../features/auth/auth_feature.dart';
import '../../services/qr_login_service.dart';
import '../../utils/theme_manager.dart';
import 'qr_login_result_page.dart';

final AuthFacade _authFacade = AuthFacade();

Future<void> openQrLoginScanPage(BuildContext context) async {
  if (!_authFacade.isLoggedIn) {
    return;
  }

  final bool isCupertino = ThemeManager().isCupertinoFramework;
  await Navigator.of(context).push(
    isCupertino
        ? CupertinoPageRoute(builder: (_) => const QrLoginScanPage())
        : MaterialPageRoute(builder: (_) => const QrLoginScanPage()),
  );
}

class QrLoginScanPage extends StatefulWidget {
  const QrLoginScanPage({super.key});

  @override
  State<QrLoginScanPage> createState() => _QrLoginScanPageState();
}

class _QrLoginScanPageState extends State<QrLoginScanPage> {
  bool _hasPermission = false;
  bool _isRequesting = true;
  bool _handled = false;
  String? _error;

  final MobileScannerController _controller = MobileScannerController(
    detectionSpeed: DetectionSpeed.normal,
    facing: CameraFacing.back,
  );

  @override
  void initState() {
    super.initState();
    _ensureCameraPermission();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _ensureCameraPermission() async {
    setState(() {
      _isRequesting = true;
      _error = null;
    });

    try {
      final status = await Permission.camera.request();
      if (!mounted) return;

      if (status.isGranted) {
        setState(() {
          _hasPermission = true;
          _isRequesting = false;
        });
        return;
      }

      if (status.isPermanentlyDenied) {
        setState(() {
          _hasPermission = false;
          _isRequesting = false;
          _error = '相机权限被永久拒绝，请在系统设置中开启。';
        });
        return;
      }

      setState(() {
        _hasPermission = false;
        _isRequesting = false;
        _error = '未获得相机权限。';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _hasPermission = false;
        _isRequesting = false;
        _error = '请求相机权限失败: $e';
      });
    }
  }

  Future<void> _handleCode(String raw) async {
    if (_handled) return;
    _handled = true;

    Uri? uri;
    try {
      uri = Uri.parse(raw);
    } catch (_) {}

    final rid = uri?.queryParameters['rid'];
    final code = uri?.queryParameters['code'];

    if (rid == null || rid.isEmpty || code == null || code.isEmpty) {
      setState(() {
        _error = '二维码内容无效';
      });
      _handled = false;
      return;
    }

    try {
      final scanned = await QrLoginService().scan(rid: rid, code: code);

      if (!mounted) return;

      await _controller.stop();

      if (!mounted) return;

      final bool isCupertino = ThemeManager().isCupertinoFramework;
      final ok = await Navigator.of(context).push<bool>(
        isCupertino
            ? CupertinoPageRoute(
                builder: (_) => QrLoginResultPage(
                  args: QrLoginResultArgs(
                    rid: rid,
                    code: code,
                    desktopDeviceName: scanned.desktopDeviceName,
                    desktopIp: scanned.desktopIp,
                    desktopLocation: scanned.desktopLocation,
                  ),
                ),
              )
            : MaterialPageRoute(
                builder: (_) => QrLoginResultPage(
                  args: QrLoginResultArgs(
                    rid: rid,
                    code: code,
                    desktopDeviceName: scanned.desktopDeviceName,
                    desktopIp: scanned.desktopIp,
                    desktopLocation: scanned.desktopLocation,
                  ),
                ),
              ),
      );

      if (!mounted) return;

      if (ok == true) {
        if (mounted) {
          final nav = Navigator.of(context);
          if (nav.canPop()) {
            nav.pop(true);
          }
        }
      } else {
        _handled = false;
        await _controller.start();
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
      });
      _handled = false;
      await _controller.start();
    }
  }

  @override
  Widget build(BuildContext context) {
    final title = const Text('扫码登录桌面端');

    final body = _isRequesting
        ? const Center(child: CircularProgressIndicator())
        : !_hasPermission
            ? Center(
                child: Padding(
                  padding: const EdgeInsets.all(24.0),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.camera_alt_outlined, size: 48),
                      const SizedBox(height: 12),
                      Text(_error ?? '无法使用相机'),
                      const SizedBox(height: 12),
                      FilledButton(
                        onPressed: () async {
                          await openAppSettings();
                        },
                        child: const Text('打开系统设置'),
                      ),
                      const SizedBox(height: 8),
                      TextButton(
                        onPressed: _ensureCameraPermission,
                        child: const Text('重试'),
                      ),
                    ],
                  ),
                ),
              )
            : Stack(
                children: [
                  MobileScanner(
                    controller: _controller,
                    onDetect: (capture) {
                      final barcodes = capture.barcodes;
                      for (final b in barcodes) {
                        final raw = b.rawValue;
                        if (raw != null && raw.isNotEmpty) {
                          _handleCode(raw);
                          break;
                        }
                      }
                    },
                  ),
                  if (_error != null)
                    Positioned(
                      left: 12,
                      right: 12,
                      bottom: 12,
                      child: Card(
                        color: Theme.of(context).colorScheme.errorContainer,
                        child: Padding(
                          padding: const EdgeInsets.all(12.0),
                          child: Text(
                            _error!,
                            style: TextStyle(color: Theme.of(context).colorScheme.onErrorContainer),
                          ),
                        ),
                      ),
                    ),
                ],
              );

    final bool isCupertino = ThemeManager().isCupertinoFramework;
    if (isCupertino) {
      return CupertinoPageScaffold(
        navigationBar: const CupertinoNavigationBar(
          middle: Text('扫码登录桌面端'),
        ),
        child: SafeArea(child: body),
      );
    }

    return Scaffold(
      appBar: AppBar(title: title),
      body: body,
    );
  }
}



