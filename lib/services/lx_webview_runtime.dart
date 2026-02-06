import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'lx_http_bridge.dart';
import 'lx_runtime_interface.dart';
import 'lx_sandbox_js.dart';

class LxWebViewRuntime implements LxRuntime {
  HeadlessInAppWebView? _headlessWebView;
  InAppWebViewController? _webViewController;

  bool _isInitialized = false;
  bool _isScriptReady = false;
  bool _isDisabled = false;
  LxScriptInfo? _currentScript;
  Completer<bool>? _initCompleter;

  final Map<String, Completer<String>> _pendingRequests = {};
  int _requestCounter = 0;

  List<String> _pendingSupportedSources = [];
  List<String> _pendingSupportedQualities = [];
  Map<String, List<String>> _pendingPlatformQualities = {};

  @override
  bool get isInitialized => _isInitialized;

  @override
  bool get isScriptReady => _isScriptReady;

  @override
  bool get isAvailable => !_isDisabled && !kIsWeb;

  @override
  LxScriptInfo? get currentScript => _currentScript;

  @override
  Future<void> initialize() async {
    if (_isInitialized) {
      print('⚠️ [LxWebViewRuntime] 已经初始化');
      return;
    }

    print('🚀 [LxWebViewRuntime] 开始初始化 WebView 沙箱...');
    _initCompleter = Completer<bool>();

    try {
      _headlessWebView = HeadlessInAppWebView(
        initialData: InAppWebViewInitialData(
          data: _buildSandboxHtml(),
          mimeType: 'text/html',
          encoding: 'utf-8',
        ),
        initialSettings: InAppWebViewSettings(
          javaScriptEnabled: true,
          domStorageEnabled: true,
          databaseEnabled: true,
          cacheEnabled: true,
          allowBackgroundAudioPlaying: true,
          allowsInlineMediaPlayback: true,
          mediaPlaybackRequiresUserGesture: false,
          allowFileAccess: false,
          allowContentAccess: false,
          javaScriptCanOpenWindowsAutomatically: false,
        ),
        onWebViewCreated: (controller) {
          _webViewController = controller;
          print('✅ [LxWebViewRuntime] WebView 创建成功');
          _registerJavaScriptHandlers(controller);
        },
        onLoadStop: (controller, url) async {
          print('✅ [LxWebViewRuntime] WebView 加载完成');
          _isInitialized = true;
          _initCompleter?.complete(true);
        },
        onConsoleMessage: (controller, message) {
          print('🌐 [WebView Console] ${message.message}');
        },
        onLoadError: (controller, url, code, message) {
          print('❌ [LxWebViewRuntime] 加载错误: $code - $message');
          _initCompleter?.complete(false);
        },
      );

      await _headlessWebView!.run();
      final success = await _initCompleter!.future;
      if (!success) {
        _isDisabled = true;
        throw Exception('WebView 初始化失败');
      }

      _isDisabled = false;
      print('✅ [LxWebViewRuntime] 初始化完成');
    } catch (e) {
      _isDisabled = true;
      rethrow;
    }
  }

  @override
  Future<void> dispose() async {
    print('🗑️ [LxWebViewRuntime] 销毁 WebView...');
    _isInitialized = false;
    _isScriptReady = false;
    _currentScript = null;
    for (final entry in _pendingRequests.entries) {
      final completer = entry.value;
      if (!completer.isCompleted) {
        completer.completeError(StateError('LxWebViewRuntime disposed'));
      }
    }
    _pendingRequests.clear();

    await _headlessWebView?.dispose();
    _headlessWebView = null;
    _webViewController = null;
  }

  @override
  Future<LxScriptInfo?> loadScript(String scriptContent) async {
    if (!_isInitialized) {
      print('❌ [LxWebViewRuntime] WebView 未初始化');
      return null;
    }

    print('📜 [LxWebViewRuntime] 加载脚本...');
    _isScriptReady = false;

    try {
      final scriptInfo = LxScriptParser.parse(scriptContent);
      print('📋 [LxWebViewRuntime] 脚本信息:');
      print('   名称: ${scriptInfo.name}');
      print('   版本: ${scriptInfo.version}');
      print('   作者: ${scriptInfo.author}');

      await _webViewController?.evaluateJavascript(source: '''
        window.__lx_reset__();
      ''');

      final scriptBase64 = base64Encode(utf8.encode(scriptContent));
      final scriptInfoJson = jsonEncode({
        'name': scriptInfo.name,
        'version': scriptInfo.version,
        'author': scriptInfo.author,
        'description': scriptInfo.description,
        'homepage': scriptInfo.homepage,
        'scriptBase64': scriptBase64,
      });

      await _webViewController?.evaluateJavascript(source: '''
        window.__lx_setScriptInfo__($scriptInfoJson);
      ''');

      final wrappedScript = '''
        (function() {
          try {
            $scriptContent
          } catch (e) {
            window.__lx_onError__(e.message || String(e));
          }
        })();
      ''';

      await _webViewController?.evaluateJavascript(source: wrappedScript);

      final startTime = DateTime.now();
      while (!_isScriptReady) {
        await Future.delayed(const Duration(milliseconds: 100));
        if (DateTime.now().difference(startTime).inSeconds > 10) {
          print('⚠️ [LxWebViewRuntime] 脚本初始化超时');
          return null;
        }
      }

      final updatedScriptInfo = LxScriptInfo(
        name: scriptInfo.name,
        version: scriptInfo.version,
        author: scriptInfo.author,
        description: scriptInfo.description,
        homepage: scriptInfo.homepage,
        script: scriptInfo.script,
        supportedSources: _pendingSupportedSources,
        supportedQualities: _pendingSupportedQualities,
        platformQualities: _pendingPlatformQualities,
      );

      _currentScript = updatedScriptInfo;
      print('✅ [LxWebViewRuntime] 脚本加载成功');
      print('   支持的平台: ${updatedScriptInfo.supportedPlatforms}');
      print('   支持的音质: ${updatedScriptInfo.supportedQualities}');
      return updatedScriptInfo;
    } catch (e) {
      print('❌ [LxWebViewRuntime] 脚本加载失败: $e');
      return null;
    }
  }

  @override
  Future<String?> getMusicUrl({
    required String source,
    required dynamic songId,
    required String quality,
    Map<String, dynamic>? musicInfo,
  }) async {
    if (!_isInitialized || !_isScriptReady) {
      print('❌ [LxWebViewRuntime] 服务未就绪');
      return null;
    }

    final requestKey =
        'req_${++_requestCounter}_${DateTime.now().millisecondsSinceEpoch}';
    final completer = Completer<String>();
    _pendingRequests[requestKey] = completer;

    try {
      final info = musicInfo ?? {
        'songmid': songId.toString(),
        'copyrightId': songId.toString(),
        'hash': songId.toString(),
      };

      final requestData = jsonEncode({
        'requestKey': requestKey,
        'source': source,
        'action': 'musicUrl',
        'info': {
          'musicInfo': info,
          'type': quality,
        },
      });

      print('🎵 [LxWebViewRuntime] 请求音乐 URL:');
      print('   source: $source, songId: $songId, quality: $quality');

      await _webViewController?.evaluateJavascript(source: '''
        window.__lx_sendRequest__($requestData);
      ''');

      final result = await completer.future.timeout(
        const Duration(seconds: 30),
        onTimeout: () {
          _pendingRequests.remove(requestKey);
          throw TimeoutException('请求超时');
        },
      );

      _pendingRequests.remove(requestKey);
      return result;
    } catch (e) {
      print('❌ [LxWebViewRuntime] 获取 URL 失败: $e');
      _pendingRequests.remove(requestKey);
      return null;
    }
  }

  void _registerJavaScriptHandlers(InAppWebViewController controller) {
    controller.addJavaScriptHandler(
      handlerName: 'lxOnInited',
      callback: (args) {
        print('✅ [LxWebViewRuntime] 脚本初始化完成');
        if (args.isNotEmpty) {
          final data = args[0];
          final sources = data['sources'];
          if (sources != null && sources is Map) {
            _pendingSupportedSources =
                sources.keys.map((k) => k.toString()).toList();
            print('   支持的音源: $_pendingSupportedSources');

            final allQualities = <String>{};
            _pendingPlatformQualities = {};

            sources.forEach((key, value) {
              if (value is Map) {
                final qualitys = value['qualitys'];
                if (qualitys is List && qualitys.isNotEmpty) {
                  final qualityList = qualitys.map((t) => t.toString()).toList();
                  _pendingPlatformQualities[key.toString()] = qualityList;
                  allQualities.addAll(qualityList);
                }
              } else if (value is List) {
                final qualityList = value.map((t) => t.toString()).toList();
                _pendingPlatformQualities[key.toString()] = qualityList;
                allQualities.addAll(qualityList);
              }
            });

            final qualityOrder = ['128k', '320k', 'flac', 'flac24bit'];
            _pendingSupportedQualities = qualityOrder
                .where((q) => allQualities.contains(q))
                .toList();

            print('   支持的音质: $_pendingSupportedQualities');
            print('   各平台音质: $_pendingPlatformQualities');
          } else {
            _pendingSupportedSources = [];
            _pendingSupportedQualities = [];
            _pendingPlatformQualities = {};
          }
        }
        _isScriptReady = true;
        return null;
      },
    );

    controller.addJavaScriptHandler(
      handlerName: 'lxRequest',
      callback: (args) async {
        if (args.isEmpty) return null;

        final data = args[0] as Map<String, dynamic>;
        final requestId = data['requestId'] as String;
        final url = data['url'] as String;
        final options = data['options'] as Map<String, dynamic>? ?? {};

        print('🌐 [LxWebViewRuntime] HTTP 请求: $url');
        _executeHttpRequest(requestId, url, options);
        return null;
      },
    );

    controller.addJavaScriptHandler(
      handlerName: 'lxOnResponse',
      callback: (args) {
        if (args.isEmpty) return;

        final data = args[0] as Map<String, dynamic>;
        final requestKey = data['requestKey'] as String?;
        final success = data['success'] as bool? ?? false;
        final url = data['url'] as String?;
        final error = data['error'] as String?;

        print('📥 [LxWebViewRuntime] 响应: requestKey=$requestKey, success=$success');

        if (requestKey != null && _pendingRequests.containsKey(requestKey)) {
          final completer = _pendingRequests[requestKey]!;
          if (success && url != null) {
            completer.complete(url);
          } else {
            completer.completeError(error ?? '未知错误');
          }
        }
        return null;
      },
    );

    controller.addJavaScriptHandler(
      handlerName: 'lxOnError',
      callback: (args) {
        final error = args.isNotEmpty ? args[0] : '未知错误';
        print('❌ [LxWebViewRuntime] 脚本错误: $error');
        return null;
      },
    );

    controller.addJavaScriptHandler(
      handlerName: 'LxLyricInfo',
      callback: (args) {
        print('ℹ️ [LxWebViewRuntime] 歌词请求已忽略（使用后端 API 获取歌词）');
        return null;
      },
    );

    controller.addJavaScriptHandler(
      handlerName: 'lxOnLyric',
      callback: (args) {
        print('ℹ️ [LxWebViewRuntime] lxOnLyric 请求已忽略');
        return null;
      },
    );
  }

  void _executeHttpRequest(
    String requestId,
    String url,
    Map<String, dynamic> options,
  ) async {
    try {
      final result = await LxHttpBridge.performHttpRequest(url, options);

      final responseData = jsonEncode({
        'requestId': requestId,
        'success': true,
        'response': {
          'statusCode': result['statusCode'],
          'statusMessage': result['statusMessage'],
          'headers': result['headers'],
          'body': result['body'],
          'bytes': result['bytes'],
        },
        'body': result['body'],
      });

      await _webViewController?.evaluateJavascript(source: '''
        window.__lx_handleHttpResponse__($responseData);
      ''');
    } catch (e) {
      print('❌ [LxWebViewRuntime] HTTP 请求失败: $e');

      final errorData = jsonEncode({
        'requestId': requestId,
        'success': false,
        'error': e.toString(),
      });

      await _webViewController?.evaluateJavascript(source: '''
        window.__lx_handleHttpResponse__($errorData);
      ''');
    }
  }

  String _buildSandboxHtml() {
    return '''
<!DOCTYPE html>
<html>
<head>
  <meta charset="UTF-8">
  <meta http-equiv="Content-Security-Policy" content="default-src 'unsafe-inline' 'unsafe-eval'">
  <title>LxMusic Sandbox</title>
</head>
<body>
<script>
$lxSandboxJs
</script>
</body>
</html>
''';
  }
}
