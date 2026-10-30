import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:fluent_ui/fluent_ui.dart' as fluent;
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:path_provider/path_provider.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../services/auth_service.dart';
import '../../services/url_service.dart';
import '../../services/netease_login_service.dart';
import '../../utils/theme_manager.dart';
import 'netease_qr_dialog.dart';

Future<bool?> showNeteaseLogin(BuildContext context, int userId) {
  final themes = InheritedTheme.capture(
    from: context,
    to: Navigator.of(context).context,
  );
  return Navigator.of(context).push<bool>(
    MaterialPageRoute(
      builder: (_) => themes.wrap(NeteaseLoginPage(userId: userId)),
    ),
  );
}

class NeteaseLoginPage extends StatefulWidget {
  const NeteaseLoginPage({super.key, required this.userId});
  final int userId;
  @override
  State<NeteaseLoginPage> createState() => _NeteaseLoginPageState();
}

class _NeteaseLoginPageState extends State<NeteaseLoginPage>
    with WidgetsBindingObserver {
  final service = NeteaseLoginService();
  late final String identity;
  WebViewEnvironment? environment;
  CookieManager? cookies;
  InAppWebViewController? controller;
  String? session;
  String? error;
  Directory? profile;
  Timer? timer;
  bool qrActive = false;
  bool initializing = false;
  bool ready = false;
  bool busy = false;
  bool active = true;
  bool complete = false;
  bool closing = false;
  @override
  void initState() {
    super.initState();
    identity = service.scope;
    WidgetsBinding.instance.addObserver(this);
    AuthService().addListener(_checkIdentity);
    UrlService().addListener(_checkIdentity);
    unawaited(_initialize());
  }

  void _checkIdentity() {
    if (service.scope != identity && mounted && !closing) {
      closing = true;
      Navigator.of(context).pop(false);
    }
  }

  bool get current => mounted && !closing && identity == service.scope;
  Future<void> _initialize() async {
    if (initializing || !current) return;
    initializing = true;
    try {
      if (!isNeteaseCredentialTransportAllowed(UrlService().baseUrl)) {
        throw const NeteaseAccountException(
          'HTTPS_REQUIRED',
          '请使用 HTTPS 服务器地址完成网页登录，或选择扫码绑定',
        );
      }
      if (Platform.isWindows) {
        if (await WebViewEnvironment.getAvailableVersion() == null) {
          throw const NeteaseAccountException(
            'WEBVIEW_MISSING',
            '未安装 Microsoft Edge WebView2，请安装后重试，或使用扫码绑定',
          );
        }
        final root = await getApplicationSupportDirectory();
        final parent = await Directory(
          '${root.path}/netease-login',
        ).create(recursive: true);
        profile = await parent.createTemp('session-');
        environment = await WebViewEnvironment.create(
          settings: WebViewEnvironmentSettings(userDataFolder: profile!.path),
        );
      } else if (!(Platform.isAndroid || Platform.isIOS || Platform.isMacOS)) {
        throw const NeteaseAccountException('UNSUPPORTED', '当前平台请使用扫码绑定');
      }
      if (!current) {
        await _cleanup();
        return;
      }
      cookies = CookieManager.instance(webViewEnvironment: environment);
      await _clearCookies();
      if (!context.mounted || !current) return;
      final result = await service.startBinding('web');
      session = result['id'] as String;
      if (!current) {
        await _cleanup();
        return;
      }
      setState(() => ready = true);
      timer = Timer.periodic(const Duration(seconds: 3), (_) {
        if (active) unawaited(_checkCookies());
      });
    } catch (e) {
      if (current) {
        setState(
          () => error = e is NeteaseAccountException
              ? e.message
              : '官方登录页初始化失败，请重试或使用扫码绑定',
        );
      }
    } finally {
      initializing = false;
    }
  }

  Future<void> _clearCookies() async {
    if (Platform.isWindows) {
      await cookies?.deleteAllCookies();
      return;
    }
    for (final host in ['music.163.com', '.music.163.com']) {
      await cookies?.deleteCookies(
        url: WebUri('https://music.163.com/'),
        domain: host,
      );
    }
  }

  Future<void> _checkCookies() async {
    if (!current ||
        qrActive ||
        busy ||
        complete ||
        session == null ||
        cookies == null) {
      return;
    }
    busy = true;
    try {
      final list = await cookies!.getCookies(
        url: WebUri('https://music.163.com/'),
        webViewController: controller,
      );
      final selected = list
          .where((c) => ['MUSIC_U', '__csrf', 'NMTID'].contains(c.name))
          .toList();
      if (!selected.any(
            (c) => c.name == 'MUSIC_U' && c.value.toString().isNotEmpty,
          ) ||
          !current) {
        return;
      }
      await service.completeBinding(
        session!,
        selected.map((c) => '${c.name}=${c.value}').join('; '),
      );
      if (!mounted) return;
      if (!current) return;
      complete = true;
      Navigator.of(context).pop(true);
    } catch (e) {
      if (current) {
        setState(
          () =>
              error = e is NeteaseAccountException ? e.message : '验证登录失败，请稍后重试',
        );
        if (e is NeteaseAccountException && e.code == 'BIND_SESSION_EXPIRED') {
          try {
            final next = await service.startBinding('web');
            session = next['id'] as String;
            if (!current) await _cleanup();
          } catch (_) {
            timer?.cancel();
          }
        }
      }
    } finally {
      busy = false;
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    active = state == AppLifecycleState.resumed;
    if (active) unawaited(_checkCookies());
  }

  Future<NavigationActionPolicy> _navigate(NavigationAction action) async {
    final uri = action.request.url;
    if (uri == null) return NavigationActionPolicy.CANCEL;
    if (uri.toString() == 'about:blank') return NavigationActionPolicy.ALLOW;
    final host = uri.host.toLowerCase();
    if (uri.scheme == 'https' &&
        [
          '163.com',
          'netease.com',
          'qq.com',
        ].any((d) => host == d || host.endsWith('.$d'))) {
      return NavigationActionPolicy.ALLOW;
    }
    if (uri.scheme == 'orpheus' && action.isForMainFrame) {
      try {
        await launchUrl(
          Uri.parse(uri.toString()),
          mode: LaunchMode.externalApplication,
        );
      } catch (_) {
        if (current) setState(() => error = '未能打开网易云 App，请继续使用官方网页登录');
      }
    }
    return NavigationActionPolicy.CANCEL;
  }

  Future<void> _cleanup() async {
    final id = session;
    if (!complete && id != null && identity == service.scope) {
      try {
        await service.cancelBinding(id);
      } catch (_) {}
    }
    try {
      await _clearCookies();
    } catch (_) {}
    try {
      await environment?.dispose();
    } catch (_) {}
    // WebView2 can retain file handles briefly; delete only our checked profile.
    final dir = profile;
    if (dir != null) {
      try {
        await dir.delete(recursive: true);
      } catch (_) {}
    }
  }

  @override
  void dispose() {
    closing = true;
    timer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    AuthService().removeListener(_checkIdentity);
    UrlService().removeListener(_checkIdentity);
    unawaited(_cleanup());
    super.dispose();
  }

  Widget _button(String text, VoidCallback? onPressed) {
    final theme = ThemeManager();
    if (theme.isDesktopFluentUI) {
      return fluent.Button(onPressed: onPressed, child: Text(text));
    }
    if (theme.isCupertinoFramework) {
      return CupertinoButton(onPressed: onPressed, child: Text(text));
    }
    return TextButton(onPressed: onPressed, child: Text(text));
  }

  @override
  Widget build(BuildContext context) {
    final content = Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            children: [
              const Expanded(child: Text('在网易云官方页面登录，完成后自动绑定当前账号。')),
              _button(
                '扫码绑定',
                qrActive
                    ? null
                    : () async {
                        if (qrActive) return;
                        setState(() => qrActive = true);
                        active = false;
                        timer?.cancel();
                        final id = session;
                        if (id != null) {
                          try {
                            await service.cancelBinding(id);
                          } catch (_) {}
                        }
                        if (!context.mounted || !current) return;
                        final result = await showNeteaseQrDialog(
                          context,
                          widget.userId,
                        );
                        if (!context.mounted || !current) return;
                        if (result == true) {
                          complete = true;
                          Navigator.of(context).pop(true);
                        } else {
                          Navigator.of(context).pop(false);
                        }
                      },
              ),
            ],
          ),
        ),
        if (error != null)
          Padding(padding: const EdgeInsets.all(12), child: Text(error!)),
        if (ready)
          Expanded(
            child: InAppWebView(
              webViewEnvironment: environment,
              initialUrlRequest: URLRequest(
                url: WebUri('https://music.163.com/m/login'),
              ),
              initialSettings: InAppWebViewSettings(
                useShouldOverrideUrlLoading: true,
                javaScriptCanOpenWindowsAutomatically: false,
                supportMultipleWindows: false,
                sharedCookiesEnabled: false,
                cacheEnabled: false,
              ),
              onWebViewCreated: (c) => controller = c,
              shouldOverrideUrlLoading: (_, action) => _navigate(action),
              onLoadStop: (_, _) => _checkCookies(),
              onReceivedError: (_, request, _) {
                if (request.isForMainFrame == true && current) {
                  setState(() => error = '官方登录页加载失败，请重试或扫码绑定');
                }
              },
            ),
          )
        else
          const Expanded(child: Center(child: Text('等待打开网易云登录页'))),
        SafeArea(
          top: false,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _button('重新加载', () {
                if (controller != null) {
                  unawaited(controller!.reload());
                } else if (!ready) {
                  setState(() => error = null);
                  unawaited(_initialize());
                }
              }),
              if (Platform.isWindows && !ready)
                _button(
                  '安装 WebView2',
                  () => unawaited(
                    launchUrl(
                      Uri.parse(
                        'https://developer.microsoft.com/microsoft-edge/webview2/',
                      ),
                      mode: LaunchMode.externalApplication,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
    if (ThemeManager().isDesktopFluentUI) {
      return fluent.ScaffoldPage(
        header: fluent.PageHeader(
          title: const Text('绑定网易云'),
          leading: fluent.IconButton(
            icon: const Icon(fluent.FluentIcons.back),
            onPressed: () => Navigator.of(context).pop(false),
          ),
        ),
        content: content,
      );
    }
    if (ThemeManager().isCupertinoFramework) {
      return CupertinoPageScaffold(
        navigationBar: const CupertinoNavigationBar(middle: Text('绑定网易云')),
        child: SafeArea(child: content),
      );
    }
    return Scaffold(
      appBar: AppBar(title: const Text('绑定网易云')),
      body: content,
    );
  }
}
