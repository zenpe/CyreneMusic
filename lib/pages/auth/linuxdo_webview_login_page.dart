import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'dart:io';

/// Linux DO WebView 授权登录页面
/// 
/// 使用 InAppWebView 在应用内完成 OAuth 授权流程，
/// 避免调用外部浏览器可能失败的问题。
class LinuxDoWebViewLoginPage extends StatefulWidget {
  const LinuxDoWebViewLoginPage({super.key});

  @override
  State<LinuxDoWebViewLoginPage> createState() => _LinuxDoWebViewLoginPageState();
}

class _LinuxDoWebViewLoginPageState extends State<LinuxDoWebViewLoginPage> {
  // OAuth 配置
  static const String _clientId = '92bIhRkScTeJvJkb3a6w69xX7RoO7wbB';
  static const String _redirectUri = 'http://127.0.0.1:40555/oauth/callback';
  static const String _authUrl = 
      'https://connect.linux.do/oauth2/authorize?response_type=code&client_id=$_clientId&redirect_uri=$_redirectUri&state=login';

  /// WebView 控制器
  InAppWebViewController? _webViewController;
  
  /// 加载进度
  double _progress = 0;
  
  /// 是否正在加载
  bool _isLoading = true;
  
  /// 错误信息
  String? _errorMessage;
  
  /// 是否已经处理过回调（防止重复处理）
  bool _callbackHandled = false;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final colorScheme = Theme.of(context).colorScheme;
    
    return Scaffold(
      appBar: AppBar(
        title: const Text('Linux Do 授权登录'),
        centerTitle: true,
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => Navigator.of(context).pop(null),
        ),
        bottom: _isLoading
            ? PreferredSize(
                preferredSize: const Size.fromHeight(2),
                child: LinearProgressIndicator(
                  value: _progress > 0 ? _progress : null,
                  backgroundColor: Colors.transparent,
                  valueColor: AlwaysStoppedAnimation<Color>(colorScheme.primary),
                ),
              )
            : null,
      ),
      body: _errorMessage != null
          ? _buildErrorView(colorScheme)
          : _buildWebView(isDark),
    );
  }

  /// 构建错误视图
  Widget _buildErrorView(ColorScheme colorScheme) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.hasBoundedHeight && constraints.maxHeight < 260;
        final minHeight = constraints.hasBoundedHeight ? constraints.maxHeight : 0.0;
        return SingleChildScrollView(
          physics: const ClampingScrollPhysics(),
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: minHeight),
            child: Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.error_outline_rounded,
                      size: compact ? 52 : 64,
                      color: colorScheme.error,
                    ),
                    SizedBox(height: compact ? 12 : 16),
                    Text(
                      '加载失败',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: colorScheme.onSurface,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      _errorMessage!,
                      textAlign: TextAlign.center,
                      maxLines: compact ? 3 : 5,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                    SizedBox(height: compact ? 16 : 24),
                    FilledButton.icon(
                      onPressed: _reload,
                      icon: const Icon(Icons.refresh_rounded),
                      label: const Text('重试'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  /// 构建 WebView
  Widget _buildWebView(bool isDark) {
    return InAppWebView(
      initialUrlRequest: URLRequest(url: WebUri(_authUrl)),
      initialSettings: InAppWebViewSettings(
        // 基本设置
        javaScriptEnabled: true,
        domStorageEnabled: true,
        cacheEnabled: true,
        
        // 用户代理 - 模拟桌面浏览器
        userAgent: Platform.isWindows || Platform.isMacOS || Platform.isLinux
            ? 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36'
            : null,
        
        // 允许混合内容（某些 OAuth 可能需要）
        mixedContentMode: MixedContentMode.MIXED_CONTENT_ALWAYS_ALLOW,
        
        // 允许 JavaScript 打开窗口（OAuth 流程可能需要）
        javaScriptCanOpenWindowsAutomatically: true,
        
        // 支持缩放
        supportZoom: true,
        
        // 使用宽视口
        useWideViewPort: true,
        
        // 透明背景
        transparentBackground: false,
        
        // 禁用安全浏览检查（可以帮助避免某些 ORB 问题）
        safeBrowsingEnabled: false,
      ),
      onWebViewCreated: (controller) {
        _webViewController = controller;
        print('🌐 [LinuxDoWebView] WebView 已创建');
      },
      onLoadStart: (controller, url) {
        final urlString = url?.toString() ?? '';
        print('🔄 [LinuxDoWebView] 开始加载: $urlString');
        
        // 检查是否是回调 URL，如果是，立即处理并阻止后续加载
        if (url != null && urlString.startsWith(_redirectUri)) {
          _checkForCallback(urlString);
          // 停止当前加载，避免 WebView 尝试连接 127.0.0.1
          controller.stopLoading();
        }
      },
      onLoadStop: (controller, url) async {
        if (mounted) {
          setState(() {
            _isLoading = false;
            _progress = 1.0;
          });
        }
        print('✅ [LinuxDoWebView] 加载完成: $url');
      },
      onProgressChanged: (controller, progress) {
        if (mounted) {
          setState(() {
            _progress = progress / 100;
            _isLoading = progress < 100;
          });
        }
      },
      onReceivedError: (controller, request, error) {
        final url = request.url.toString();
        final errorDesc = error.description;
        
        // 忽略回调 URL 的错误（因为我们会拦截它）
        if (url.startsWith(_redirectUri)) {
          print('ℹ️ [LinuxDoWebView] 忽略回调 URL 的错误: $errorDesc');
          return;
        }
        
        // 忽略所有非主框架的错误（子资源加载失败不应阻断主流程）
        // isForMainFrame 为 false 表示这是 iframe 或子资源的错误
        if (request.isForMainFrame == false) {
          print('ℹ️ [LinuxDoWebView] 忽略子资源错误: $errorDesc');
          return;
        }
        
        // 忽略常见的非致命网络错误
        final ignoredErrors = [
          'ERR_BLOCKED_BY_ORB',
          'ERR_CONNECTION_REFUSED',
          'ERR_FAILED',  // 通用失败，通常是资源加载问题
          'ERR_ABORTED', // 请求被中止
          'ERR_CACHE_MISS',
          'ERR_INTERNET_DISCONNECTED',
          'ERR_NAME_NOT_RESOLVED',
        ];
        
        for (final ignoredError in ignoredErrors) {
          if (errorDesc.contains(ignoredError)) {
            print('ℹ️ [LinuxDoWebView] 忽略 $ignoredError 错误');
            return;
          }
        }
        
        print('❌ [LinuxDoWebView] 加载错误: $errorDesc');
        // 只有在主文档加载失败且未处理回调时才显示错误
        if (mounted && !_callbackHandled && request.isForMainFrame == true) {
          setState(() {
            _errorMessage = errorDesc;
            _isLoading = false;
          });
        }
      },
      onReceivedHttpError: (controller, request, response) {
        // 忽略回调 URL 的 HTTP 错误
        final url = request.url.toString();
        if (url.startsWith(_redirectUri)) {
          return;
        }
        
        print('⚠️ [LinuxDoWebView] HTTP 错误: ${response.statusCode}');
      },
      shouldOverrideUrlLoading: (controller, navigationAction) async {
        final url = navigationAction.request.url?.toString() ?? '';
        
        // 检查是否是回调 URL
        if (url.startsWith(_redirectUri)) {
          _checkForCallback(url);
          // 阻止 WebView 继续加载回调 URL（因为本地服务器不存在）
          return NavigationActionPolicy.CANCEL;
        }
        
        return NavigationActionPolicy.ALLOW;
      },
    );
  }

  /// 检查 URL 是否是回调 URL，并提取授权码
  void _checkForCallback(String url) {
    if (_callbackHandled) return;
    
    if (url.startsWith(_redirectUri)) {
      print('🎯 [LinuxDoWebView] 检测到回调 URL: $url');
      
      final uri = Uri.tryParse(url);
      if (uri != null) {
        final code = uri.queryParameters['code'];
        final error = uri.queryParameters['error'];
        
        if (code != null && code.isNotEmpty) {
          _callbackHandled = true;
          print('✅ [LinuxDoWebView] 获取授权码成功: ${code.substring(0, 5)}...');
          
          // 返回授权码
          if (mounted) {
            Navigator.of(context).pop(code);
          }
        } else if (error != null) {
          _callbackHandled = true;
          final errorDesc = uri.queryParameters['error_description'] ?? error;
          print('❌ [LinuxDoWebView] 授权失败: $errorDesc');
          
          if (mounted) {
            setState(() {
              _errorMessage = '授权失败: $errorDesc';
            });
          }
        }
      }
    }
  }

  /// 重新加载页面
  void _reload() {
    setState(() {
      _errorMessage = null;
      _isLoading = true;
      _progress = 0;
      _callbackHandled = false;
    });
    _webViewController?.loadUrl(
      urlRequest: URLRequest(url: WebUri(_authUrl)),
    );
  }
}

/// 显示 Linux DO WebView 登录页面
/// 
/// 返回授权码（成功）或 null（取消/失败）
Future<String?> showLinuxDoWebViewLogin(BuildContext context) async {
  return await Navigator.of(context).push<String>(
    MaterialPageRoute(
      builder: (context) => const LinuxDoWebViewLoginPage(),
      fullscreenDialog: true,
    ),
  );
}
