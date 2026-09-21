import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_js/flutter_js.dart';
import 'lx_http_bridge.dart';
import 'lx_runtime_interface.dart';
import 'lx_sandbox_js.dart';

class _LxRuntimeContext {
  _LxRuntimeContext(this.generation, this.runtime);

  final int generation;
  final JavascriptRuntime runtime;
  bool disposed = false;
}

class _PendingLxRequest {
  _PendingLxRequest(this.context, this.completer);

  final _LxRuntimeContext context;
  final Completer<String> completer;
}

class LxQuickJsRuntime implements LxRuntime {
  JavascriptRuntime? _runtime;
  _LxRuntimeContext? _context;
  int _runtimeGeneration = 0;
  bool _isInitialized = false;
  bool _isScriptReady = false;
  bool _isDisabled = false;
  LxScriptInfo? _currentScript;
  LxRuntimeFailure? _lastFailure;

  final Map<String, _PendingLxRequest> _pendingRequests = {};
  int _requestCounter = 0;
  List<String> _pendingSupportedSources = [];
  List<String> _pendingSupportedQualities = [];
  Map<String, List<String>> _pendingPlatformQualities = {};

  Future<void> _evalQueue = Future.value();
  Future<void> _operationQueue = Future.value();

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
  LxRuntimeFailure? get lastFailure => _lastFailure;

  @override
  Future<void> initialize() async {
    if (_isInitialized) {
      _debug('⚠️ [LxQuickJsRuntime] 已经初始化');
      return;
    }

    _debug('🚀 [LxQuickJsRuntime] 初始化 QuickJS 运行时...');
    try {
      final runtime = getJavascriptRuntime(xhr: true);
      final context = _LxRuntimeContext(++_runtimeGeneration, runtime);
      _runtime = runtime;
      _context = context;
      runtime.enableHandlePromises();
      runtime.onMessage('lx_bridge', (args) {
        _handleBridgeMessage(context, args);
      });

      await _evaluate('''
        globalThis.__lx_native_send__ = function(handlerName, data) {
          try {
            sendMessage('lx_bridge', JSON.stringify({handlerName: handlerName, data: data}));
          } catch (e) {
            sendMessage('lx_bridge', JSON.stringify({handlerName: 'lxOnError', data: String(e)}));
          }
        };
      ''', context: context);

      await _evaluate(lxSandboxJs, context: context);

      _isInitialized = true;
      _debug('✅ [LxQuickJsRuntime] 初始化完成');
    } catch (e) {
      _context?.disposed = true;
      _runtime?.dispose();
      _runtime = null;
      _context = null;
      _isDisabled = true;
      _isInitialized = false;
      _error('❌ [LxQuickJsRuntime] 初始化失败: $e');
      rethrow;
    }
  }

  @override
  Future<LxScriptInfo?> loadScript(String scriptContent) {
    return _enqueueOperation(() => _loadScriptInternal(scriptContent));
  }

  Future<LxScriptInfo?> _loadScriptInternal(String scriptContent) async {
    // A script may leave unresolved promises, timers, or HTTP callbacks in
    // the JS global scope. __lx_reset__ cannot cancel those tasks, so a source
    // switch must get a fresh JS context instead of reusing the old one.
    if (_isInitialized) {
      await _resetRuntimeContext();
    }
    if (!_isInitialized) {
      await initialize();
    }
    if (!_isInitialized || _runtime == null) {
      _error('❌ [LxQuickJsRuntime] 运行时未初始化');
      return null;
    }

    _debug('📜 [LxQuickJsRuntime] 加载脚本...');
    _isScriptReady = false;
    final context = _context;
    if (context == null || context.disposed) return null;

    try {
      final scriptInfo = LxScriptParser.parse(scriptContent);
      _debug('📋 [LxQuickJsRuntime] 脚本信息:');
      _debug('   名称: ${scriptInfo.name}');
      _debug('   版本: ${scriptInfo.version}');
      _debug('   作者: ${scriptInfo.author}');

      await _evaluate('globalThis.__lx_reset__();', context: context);

      final scriptBase64 = base64Encode(utf8.encode(scriptContent));
      final scriptInfoJson = jsonEncode({
        'name': scriptInfo.name,
        'version': scriptInfo.version,
        'author': scriptInfo.author,
        'description': scriptInfo.description,
        'homepage': scriptInfo.homepage,
        'scriptBase64': scriptBase64,
      });

      await _evaluate(
        'globalThis.__lx_setScriptInfo__($scriptInfoJson);',
        context: context,
      );

      final wrappedScript =
          '''
        (function() {
          try {
            $scriptContent
          } catch (e) {
            globalThis.__lx_onError__(e.message || String(e));
          }
        })();
      ''';

      await _evaluate(wrappedScript, context: context);

      final startTime = DateTime.now();
      while (!_isScriptReady) {
        if (!identical(context, _context) || context.disposed) return null;
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
  }) {
    return _enqueueOperation(
      () => _getMusicUrlInternal(
        source: source,
        songId: songId,
        quality: quality,
        musicInfo: musicInfo,
      ),
    );
  }

  Future<String?> _getMusicUrlInternal({
    required String source,
    required dynamic songId,
    required String quality,
    Map<String, dynamic>? musicInfo,
  }) async {
    _lastFailure = null;
    if (!_isInitialized || !_isScriptReady) {
      _lastFailure = const LxRuntimeFailure(
        kind: LxRuntimeFailureKind.notReady,
        message: '洛雪音源脚本未就绪',
      );
      _error('❌ [LxQuickJsRuntime] 服务未就绪');
      return null;
    }

    final requestKey =
        'req_${++_requestCounter}_${DateTime.now().millisecondsSinceEpoch}';
    final context = _context;
    if (context == null || context.disposed) {
      _lastFailure = const LxRuntimeFailure(
        kind: LxRuntimeFailureKind.notReady,
        message: '洛雪音源运行时已被替换',
      );
      return null;
    }
    final completer = Completer<String>();
    _pendingRequests[requestKey] = _PendingLxRequest(context, completer);

    try {
      final info =
          musicInfo ??
          {
            'songmid': songId.toString(),
            'copyrightId': songId.toString(),
            'hash': songId.toString(),
          };

      final requestData = jsonEncode({
        'requestKey': requestKey,
        'source': source,
        'action': 'musicUrl',
        'info': {'musicInfo': info, 'type': quality},
      });

      _debug('🎵 [LxQuickJsRuntime] 请求音乐 URL:');
      _debug('   source: $source, songId: $songId, quality: $quality');

      await _evaluate(
        'globalThis.__lx_sendRequest__($requestData);',
        context: context,
      );

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
      _lastFailure = classifyLxRuntimeFailure(e);
      _error('❌ [LxQuickJsRuntime] 获取 URL 失败: $e');
      _pendingRequests.remove(requestKey);
      return null;
    }
  }

  /// QuickJS scripts are not required to be re-entrant. Serialize the whole
  /// script operation, including its asynchronous HTTP round trip, so a
  /// second request cannot overwrite script-level state used by the first.
  Future<T> _enqueueOperation<T>(Future<T> Function() operation) {
    final result = _operationQueue.then<T>((_) => operation());
    _operationQueue = result.then<void>((_) {}, onError: (_, __) {});
    return result;
  }

  Future<void> _resetRuntimeContext() async {
    final oldContext = _context;
    final oldRuntime = oldContext?.runtime ?? _runtime;
    if (oldContext != null) oldContext.disposed = true;
    _runtime = null;
    _context = null;
    _runtimeGeneration++;
    _isInitialized = false;
    _isScriptReady = false;
    _currentScript = null;
    for (final entry in _pendingRequests.entries) {
      if (!entry.value.completer.isCompleted) {
        entry.value.completer.completeError(
          StateError('LxRuntime script replaced'),
        );
      }
    }
    _pendingRequests.clear();
    oldRuntime?.dispose();
  }

  @override
  Future<void> dispose() async {
    final context = _context;
    if (context != null) context.disposed = true;
    _runtime?.dispose();
    _runtime = null;
    _context = null;
    _runtimeGeneration++;
    _isInitialized = false;
    _isScriptReady = false;
    _currentScript = null;
    for (final entry in _pendingRequests.entries) {
      final completer = entry.value.completer;
      if (!completer.isCompleted) {
        completer.completeError(StateError('LxQuickJsRuntime disposed'));
      }
    }
    _pendingRequests.clear();
  }

  Future<void> _evaluate(
    String code, {
    required _LxRuntimeContext context,
  }) async {
    if (context.disposed || !identical(context, _context)) {
      throw StateError('LxRuntime operation belongs to an obsolete context');
    }
    final runtime = context.runtime;
    if (_runtime == null || !identical(runtime, _runtime)) {
      throw Exception('QuickJS runtime not initialized');
    }
    final completer = Completer<void>();
    _evalQueue = _evalQueue
        .then((_) {
          try {
            if (context.disposed || !identical(context, _context)) {
              throw StateError(
                'LxRuntime operation belongs to an obsolete context',
              );
            }
            final result = runtime.evaluate(code);
            if (result.isError) {
              throw Exception(result.stringResult);
            }
            // 执行 Promise microtask 队列
            for (var i = 0; i < 3; i++) {
              runtime.executePendingJob();
            }
            completer.complete();
          } catch (e, st) {
            if (!completer.isCompleted) {
              completer.completeError(e, st);
            }
          }
        })
        .catchError((e, st) {
          if (!completer.isCompleted) {
            completer.completeError(e, st);
          }
        });
    return completer.future;
  }

  void _handleBridgeMessage(_LxRuntimeContext context, dynamic args) {
    if (context.disposed || !identical(context, _context)) return;
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
        _handleRequest(context, data);
        break;
      case 'lxOnResponse':
        _handleResponse(context, data);
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
        _pendingSupportedSources = sources.keys
            .map((k) => k.toString())
            .toList();
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
        _pendingSupportedQualities = qualityOrder
            .where((q) => allQualities.contains(q))
            .toList();

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

  void _handleRequest(_LxRuntimeContext context, dynamic data) {
    if (data is! Map) return;
    final requestId = data['requestId']?.toString();
    final url = data['url']?.toString();
    final Map<String, dynamic> options = data['options'] is Map
        ? Map<String, dynamic>.from(data['options'])
        : <String, dynamic>{};

    if (requestId == null || url == null) return;
    _debug('🌐 [LxQuickJsRuntime] HTTP 请求: $url');
    _executeHttpRequest(context, requestId, url, options);
  }

  void _handleResponse(_LxRuntimeContext context, dynamic data) {
    if (context.disposed || !identical(context, _context)) return;
    if (data is! Map) return;
    final requestKey = data['requestKey']?.toString();
    if (requestKey == null || !_pendingRequests.containsKey(requestKey)) {
      return;
    }
    final success = data['success'] as bool? ?? false;
    final url = data['url']?.toString();
    final error = data['error']?.toString();

    final pending = _pendingRequests[requestKey]!;
    if (!identical(pending.context, context)) return;
    final completer = pending.completer;
    if (success && url != null) {
      completer.complete(url);
    } else {
      completer.completeError(error ?? '未知错误');
    }
  }

  void _executeHttpRequest(
    _LxRuntimeContext context,
    String requestId,
    String url,
    Map<String, dynamic> options,
  ) async {
    if (context.disposed || !identical(context, _context)) return;
    try {
      final result = await LxHttpBridge.performHttpRequest(url, options);
      _debug('✅ [LxQuickJsRuntime] HTTP 请求成功，准备回调 JS');
      _debug('   requestId: $requestId');
      final bodyPreview = result['body']?.toString() ?? '';
      final preview = bodyPreview.length > 100
          ? bodyPreview.substring(0, 100)
          : bodyPreview;
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
      if (context.disposed || !identical(context, _context)) return;
      await _evaluate(
        'globalThis.__lx_handleHttpResponse__($responseData);',
        context: context,
      );
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
        if (context.disposed || !identical(context, _context)) return;
        await _evaluate(
          'globalThis.__lx_handleHttpResponse__($errorData);',
          context: context,
        );
      } catch (e2) {
        _error('❌ [LxQuickJsRuntime] 错误回调也失败: $e2');
      }
    }
  }
}
