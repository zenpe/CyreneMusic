import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_js/flutter_js.dart';
import 'lx_http_bridge.dart';
import 'lx_runtime_interface.dart';
import 'lx_sandbox_js.dart';

class LxQuickJsRuntime implements LxRuntime {
  JavascriptRuntime? _runtime;
  bool _isInitialized = false;
  bool _isScriptReady = false;
  bool _isDisabled = false;
  LxScriptInfo? _currentScript;

  final Map<String, Completer<String>> _pendingRequests = {};
  int _requestCounter = 0;
  List<String> _pendingSupportedSources = [];
  List<String> _pendingSupportedQualities = [];
  Map<String, List<String>> _pendingPlatformQualities = {};

  Future<void> _evalQueue = Future.value();

  void _debug(String message) {
    if (kDebugMode) {
      print(message);
    }
  }

  void _error(String message) {
    print(message);
  }

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
      _debug('⚠️ [LxQuickJsRuntime] 已经初始化');
      return;
    }

    _debug('🚀 [LxQuickJsRuntime] 初始化 QuickJS 运行时...');
    try {
      _runtime = getJavascriptRuntime(xhr: true);
      _runtime!.enableHandlePromises();
      _runtime!.onMessage('lx_bridge', _handleBridgeMessage);

      await _evaluate('''
        globalThis.__lx_native_send__ = function(handlerName, data) {
          try {
            sendMessage('lx_bridge', JSON.stringify({handlerName: handlerName, data: data}));
          } catch (e) {
            sendMessage('lx_bridge', JSON.stringify({handlerName: 'lxOnError', data: String(e)}));
          }
        };
      ''');

      await _evaluate(lxSandboxJs);

      _isInitialized = true;
      _debug('✅ [LxQuickJsRuntime] 初始化完成');
    } catch (e) {
      _runtime?.dispose();
      _runtime = null;
      _isDisabled = true;
      _isInitialized = false;
      _error('❌ [LxQuickJsRuntime] 初始化失败: $e');
      rethrow;
    }
  }

  @override
  Future<LxScriptInfo?> loadScript(String scriptContent) async {
    if (!_isInitialized || _runtime == null) {
      _error('❌ [LxQuickJsRuntime] 运行时未初始化');
      return null;
    }

    _debug('📜 [LxQuickJsRuntime] 加载脚本...');
    _isScriptReady = false;

    try {
      final scriptInfo = LxScriptParser.parse(scriptContent);
      _debug('📋 [LxQuickJsRuntime] 脚本信息:');
      _debug('   名称: ${scriptInfo.name}');
      _debug('   版本: ${scriptInfo.version}');
      _debug('   作者: ${scriptInfo.author}');

      await _evaluate('globalThis.__lx_reset__();');

      final scriptBase64 = base64Encode(utf8.encode(scriptContent));
      final scriptInfoJson = jsonEncode({
        'name': scriptInfo.name,
        'version': scriptInfo.version,
        'author': scriptInfo.author,
        'description': scriptInfo.description,
        'homepage': scriptInfo.homepage,
        'scriptBase64': scriptBase64,
      });

      await _evaluate('globalThis.__lx_setScriptInfo__($scriptInfoJson);');

      final wrappedScript = '''
        (function() {
          try {
            $scriptContent
          } catch (e) {
            globalThis.__lx_onError__(e.message || String(e));
          }
        })();
      ''';

      await _evaluate(wrappedScript);

      final startTime = DateTime.now();
      while (!_isScriptReady) {
        await Future.delayed(const Duration(milliseconds: 100));
        if (DateTime.now().difference(startTime).inSeconds > 10) {
          _debug('⚠️ [LxQuickJsRuntime] 脚本初始化超时');
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
      _debug('✅ [LxQuickJsRuntime] 脚本加载成功');
      _debug('   支持的平台: ${updatedScriptInfo.supportedPlatforms}');
      _debug('   支持的音质: ${updatedScriptInfo.supportedQualities}');
      return updatedScriptInfo;
    } catch (e) {
      _error('❌ [LxQuickJsRuntime] 脚本加载失败: $e');
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
      _error('❌ [LxQuickJsRuntime] 服务未就绪');
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

      _debug('🎵 [LxQuickJsRuntime] 请求音乐 URL:');
      _debug('   source: $source, songId: $songId, quality: $quality');

      await _evaluate('globalThis.__lx_sendRequest__($requestData);');

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
      _error('❌ [LxQuickJsRuntime] 获取 URL 失败: $e');
      _pendingRequests.remove(requestKey);
      return null;
    }
  }

  @override
  Future<void> dispose() async {
    _runtime?.dispose();
    _runtime = null;
    _isInitialized = false;
    _isScriptReady = false;
    _currentScript = null;
    for (final entry in _pendingRequests.entries) {
      final completer = entry.value;
      if (!completer.isCompleted) {
        completer.completeError(StateError('LxQuickJsRuntime disposed'));
      }
    }
    _pendingRequests.clear();
  }

  Future<void> _evaluate(String code) async {
    if (_runtime == null) {
      throw Exception('QuickJS runtime not initialized');
    }
    final completer = Completer<void>();
    _evalQueue = _evalQueue.then((_) {
      try {
        final result = _runtime!.evaluate(code);
        if (result.isError) {
          throw Exception(result.stringResult);
        }
        // 执行 Promise microtask 队列
        for (var i = 0; i < 3; i++) {
          _runtime!.executePendingJob();
        }
        completer.complete();
      } catch (e, st) {
        if (!completer.isCompleted) {
          completer.completeError(e, st);
        }
      }
    }).catchError((e, st) {
      if (!completer.isCompleted) {
        completer.completeError(e, st);
      }
    });
    return completer.future;
  }

  void _handleBridgeMessage(dynamic args) {
    final payload = _normalizePayload(args);
    if (payload == null) return;

    final handlerName = payload['handlerName']?.toString();
    var data = payload['data'];
    if (data is String) {
      try {
        data = jsonDecode(data);
      } catch (_) {
        // keep string
      }
    }

    switch (handlerName) {
      case 'lxOnInited':
        _handleInited(data);
        break;
      case 'lxRequest':
        _handleRequest(data);
        break;
      case 'lxOnResponse':
        _handleResponse(data);
        break;
      case 'lxOnError':
        _error('❌ [LxQuickJsRuntime] 脚本错误: $data');
        break;
      default:
        break;
    }
  }

  Map<String, dynamic>? _normalizePayload(dynamic args) {
    dynamic payload = args;
    if (payload is List && payload.isNotEmpty) {
      payload = payload.first;
    }
    if (payload is String) {
      try {
        final decoded = jsonDecode(payload);
        if (decoded is Map) {
          return Map<String, dynamic>.from(decoded);
        }
      } catch (_) {
        return null;
      }
    }
    if (payload is Map) {
      return Map<String, dynamic>.from(payload);
    }
    return null;
  }

  void _handleInited(dynamic data) {
    if (data is Map) {
      final sources = data['sources'];
      if (sources != null && sources is Map) {
        _pendingSupportedSources =
            sources.keys.map((k) => k.toString()).toList();
        _debug('   支持的音源: $_pendingSupportedSources');

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
        _pendingSupportedQualities =
            qualityOrder.where((q) => allQualities.contains(q)).toList();

        _debug('   支持的音质: $_pendingSupportedQualities');
        _debug('   各平台音质: $_pendingPlatformQualities');
      } else {
        _pendingSupportedSources = [];
        _pendingSupportedQualities = [];
        _pendingPlatformQualities = {};
      }
    }

    _isScriptReady = true;
  }

  void _handleRequest(dynamic data) {
    if (data is! Map) return;
    final requestId = data['requestId']?.toString();
    final url = data['url']?.toString();
    final Map<String, dynamic> options = data['options'] is Map
        ? Map<String, dynamic>.from(data['options'])
        : <String, dynamic>{};

    if (requestId == null || url == null) return;
    _debug('🌐 [LxQuickJsRuntime] HTTP 请求: $url');
    _executeHttpRequest(requestId, url, options);
  }

  void _handleResponse(dynamic data) {
    if (data is! Map) return;
    final requestKey = data['requestKey']?.toString();
    if (requestKey == null || !_pendingRequests.containsKey(requestKey)) {
      return;
    }
    final success = data['success'] as bool? ?? false;
    final url = data['url']?.toString();
    final error = data['error']?.toString();

    final completer = _pendingRequests[requestKey]!;
    if (success && url != null) {
      completer.complete(url);
    } else {
      completer.completeError(error ?? '未知错误');
    }
  }

  void _executeHttpRequest(
    String requestId,
    String url,
    Map<String, dynamic> options,
  ) async {
    try {
      final result = await LxHttpBridge.performHttpRequest(url, options);
      _debug('✅ [LxQuickJsRuntime] HTTP 请求成功，准备回调 JS');
      _debug('   requestId: $requestId');
      final bodyPreview = result['body']?.toString() ?? '';
      final preview =
          bodyPreview.length > 100 ? bodyPreview.substring(0, 100) : bodyPreview;
      _debug('   body: $preview...');

      final responseData = jsonEncode({
        'requestId': requestId,
        'success': true,
        'response': {
          'statusCode': result['statusCode'],
          'statusMessage': result['statusMessage'],
          'headers': result['headers'],
          'body': result['body'],
        },
        'body': result['body'],
      });

      _debug('📤 [LxQuickJsRuntime] 调用 __lx_handleHttpResponse__');
      _debug('   responseData length: ${responseData.length}');
      await _evaluate('globalThis.__lx_handleHttpResponse__($responseData);');
      _debug('✅ [LxQuickJsRuntime] __lx_handleHttpResponse__ 调用完成');
    } catch (e, st) {
      _error('❌ [LxQuickJsRuntime] HTTP 请求/回调失败: $e');
      _error('   Stack: $st');

      final errorData = jsonEncode({
        'requestId': requestId,
        'success': false,
        'error': e.toString(),
      });

      try {
        await _evaluate('globalThis.__lx_handleHttpResponse__($errorData);');
      } catch (e2) {
        _error('❌ [LxQuickJsRuntime] 错误回调也失败: $e2');
      }
    }
  }
}
