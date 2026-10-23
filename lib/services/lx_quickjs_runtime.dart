import 'structured_log_service.dart';
import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_js/flutter_js.dart';
import 'lx_http_bridge.dart';
import 'lx_runtime_interface.dart';
import 'lx_sandbox_js.dart';
import 'resolution_request.dart';

class _LxRuntimeContext {
  _LxRuntimeContext(this.generation, this.runtime);

  final int generation;
  final JavascriptRuntime runtime;
  final Map<int, Timer> timers = {};
  bool disposed = false;

  void cancelTimers() {
    for (final timer in timers.values) {
      timer.cancel();
    }
    timers.clear();
  }
}

class _PendingLxRequest {
  _PendingLxRequest(this.context, this.completer);

  final _LxRuntimeContext context;
  final Completer<String> completer;
}

class LxQuickJsRuntime implements LxRuntime {
  static const Duration _defaultMusicUrlTimeout = Duration(seconds: 6);
  static const int _maxActiveResolutions = 4;
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
  final Map<String, ResolutionRequest> _owners = {};
  final Map<String, DateTime> _deadlines = {};
  final Map<String, ResolutionRequest> _httpRequests = {};

  void _debug(String message) {
    if (kDebugMode) {
      StructuredLogService.log(message);
    }
  }

  void _error(String message) {
    StructuredLogService.log(message);
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
    for (final owner in _owners.values.toList()) {
      owner.cancel();
    }
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
    Duration? timeout,
  }) {
    final effectiveTimeout = timeout ?? _defaultMusicUrlTimeout;
    final deadline = DateTime.now().add(effectiveTimeout);
    final owner = ResolutionRequest();
    final parent = ResolutionRequest.current;
    final unlink = parent?.onCancel(() {
      // Preserve an outer deadline's reason for transport diagnostics. A
      // deadline abort must not be logged as an ordinary user cancellation.
      owner.failure ??= parent.failure;
      owner.cancel();
    });
    final queueClock = Stopwatch()..start();
    Future<String?>? response;
    return _enqueueOperation(() async {
          owner.check();
          final remaining = deadline.difference(DateTime.now());
          StructuredLogService.event(
            'lx.resolution_dequeued',
            fields: {
              'source': source,
              'quality': quality,
              'queue_wait_ms': queueClock.elapsedMilliseconds,
              'remaining_ms': remaining.inMilliseconds,
              'queue_expired': remaining <= Duration.zero,
            },
          );
          if (remaining <= Duration.zero) {
            owner.failure = _lastFailure = const LxRuntimeFailure(
              kind: LxRuntimeFailureKind.timeout,
              message: '获取播放地址前请求已过期',
            );
            parent?.failure = _lastFailure;
            return;
          }
          if (_owners.values.where((request) => !request.isCancelled).length >=
              _maxActiveResolutions) {
            const failure = LxRuntimeFailure(
              kind: LxRuntimeFailureKind.notReady,
              message: '音源解析通道繁忙，请重试',
            );
            owner.failure = failure;
            parent?.failure = failure;
            _lastFailure = failure;
            return;
          }
          // Serialize admission/context changes, not the HTTP round trip.
          // Every JS turn still runs exclusively through _evalQueue.
          response = _getMusicUrlInternal(
            source: source,
            songId: songId,
            quality: quality,
            musicInfo: musicInfo,
            deadline: deadline,
            owner: owner,
          );
        })
        .then((_) async {
          final result = await response;
          parent?.check();
          parent?.failure = owner.failure;
          return result;
        })
        .whenComplete(() => unlink?.call());
  }

  Future<String?> _getMusicUrlInternal({
    required String source,
    required dynamic songId,
    required String quality,
    Map<String, dynamic>? musicInfo,
    required DateTime deadline,
    required ResolutionRequest owner,
  }) async {
    _lastFailure = null;
    if (!_isInitialized || !_isScriptReady) {
      owner.failure = _lastFailure = const LxRuntimeFailure(
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
      owner.failure = _lastFailure = const LxRuntimeFailure(
        kind: LxRuntimeFailureKind.notReady,
        message: '洛雪音源运行时已被替换',
      );
      return null;
    }
    final completer = Completer<String>();
    _pendingRequests[requestKey] = _PendingLxRequest(context, completer);
    _owners[requestKey] = owner;
    _deadlines[requestKey] = deadline;
    final requestClock = Stopwatch()..start();
    StructuredLogService.event(
      'lx.music_url_started',
      fields: {
        'request_id': requestKey,
        'source': source,
        'quality': quality,
        'budget_ms': deadline.difference(DateTime.now()).inMilliseconds,
      },
    );

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
        operationDeadline: deadline,
      );

      final responseTimeout = deadline.difference(DateTime.now());
      if (responseTimeout <= Duration.zero) {
        throw TimeoutException('请求超时');
      }
      final result = await owner
          .bind(completer.future)
          .timeout(
            responseTimeout,
            onTimeout: () {
              throw TimeoutException('请求超时');
            },
          );

      StructuredLogService.event(
        'lx.music_url_completed',
        fields: {
          'request_id': requestKey,
          'elapsed_ms': requestClock.elapsedMilliseconds,
        },
      );
      return result;
    } catch (e) {
      if (e is ResolutionCancelled || owner.isCancelled) {
        throw const ResolutionCancelled();
      }
      final failure = classifyLxRuntimeFailure(e);
      owner.failure = failure;
      _lastFailure = failure;
      StructuredLogService.event(
        'lx.music_url_failed',
        level: LogLevel.warning,
        fields: {
          'request_id': requestKey,
          'source': source,
          'quality': quality,
          'failure_kind': failure.kind.name,
          'last_http_status': owner.lastHttpResponse?.status,
          'last_body_type': owner.lastHttpResponse?.bodyType,
          'last_business_code': owner.lastHttpResponse?.businessCode,
          'elapsed_ms': requestClock.elapsedMilliseconds,
          'deadline_exceeded': !DateTime.now().isBefore(deadline),
        },
        error: e,
      );
      _error('❌ [LxQuickJsRuntime] 获取 URL 失败: $e');
      return null;
    } finally {
      owner.cancel();
      _owners.remove(requestKey);
      _deadlines.remove(requestKey);
      if (!context.disposed && identical(context, _context)) {
        try {
          await _evaluate(
            'globalThis.__lx_cancelRequest__(${jsonEncode(requestKey)});',
            context: context,
          );
        } catch (error) {
          // Source replacement can dispose this context after cleanup queued.
          // Cleanup must not replace the original cancellation/result.
          if (!context.disposed && identical(context, _context)) {
            _error('❌ [LxQuickJsRuntime] 请求清理失败: $error');
          }
        }
        // Abandoned promises lose their request-scoped HTTP/timer callbacks.
        // Do not reset the shared context underneath another live resolution.
      }
      _pendingRequests.remove(requestKey);
    }
  }

  /// Serialize context replacement and request admission. Network responses
  /// remain independent; _evaluate serializes each synchronous JavaScript turn.
  Future<T> _enqueueOperation<T>(Future<T> Function() operation) {
    final result = _operationQueue.then<T>((_) => operation());
    _operationQueue = result.then<void>((_) {}, onError: (_, _) {});
    return result;
  }

  Future<void> _resetRuntimeContext() async {
    for (final request in _httpRequests.values.toList()) {
      request.cancel();
    }
    final oldContext = _context;
    final oldRuntime = oldContext?.runtime ?? _runtime;
    if (oldContext != null) {
      oldContext.disposed = true;
      oldContext.cancelTimers();
    }
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
    for (final request in _httpRequests.values.toList()) {
      request.cancel();
    }
    for (final owner in _owners.values.toList()) {
      owner.cancel();
    }
    final context = _context;
    if (context != null) {
      context.disposed = true;
      context.cancelTimers();
    }
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
    DateTime? operationDeadline,
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
            if (operationDeadline != null &&
                !DateTime.now().isBefore(operationDeadline)) {
              throw TimeoutException('LxRuntime operation expired');
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
      case 'lxCancelHttp':
        if (data is Map) _httpRequests[data['requestId']]?.cancel();
        break;
      case 'lxSetTimeout':
        _handleTimer(context, data);
        break;
      case 'lxClearTimeout':
        if (data is Map) context.timers.remove(data['timerId'])?.cancel();
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

  void _handleTimer(_LxRuntimeContext context, dynamic data) {
    if (data is! Map || data['timerId'] is! int) return;
    final timerId = data['timerId'] as int;
    final ownerKey = data['ownerKey']?.toString();
    final owner = ownerKey == null ? null : _owners[ownerKey];
    if (ownerKey != null && (owner == null || owner.isCancelled)) return;
    final delay = data['delay'];
    final milliseconds = delay is num ? delay.toInt().clamp(0, 2147483647) : 0;
    context.timers[timerId] = Timer(
      Duration(milliseconds: milliseconds),
      () async {
        context.timers.remove(timerId);
        if (context.disposed ||
            !identical(context, _context) ||
            owner?.isCancelled == true) {
          return;
        }
        try {
          await _evaluate(
            'globalThis.__lx_fireTimer__($timerId);',
            context: context,
          );
        } catch (error) {
          if (!context.disposed && owner?.isCancelled != true) {
            _error('❌ [LxQuickJsRuntime] 脚本定时器失败: $error');
          }
        }
      },
    );
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
    final ownerKey = data['ownerKey']?.toString();
    final owner = ownerKey == null ? null : _owners[ownerKey];
    if (ownerKey != null && (owner == null || owner.isCancelled)) return;
    _debug('🌐 [LxQuickJsRuntime] HTTP 请求: $url');
    final httpOwner = ResolutionRequest();
    final unlink = owner?.onCancel(() {
      httpOwner.failure ??= owner.failure;
      httpOwner.cancel();
    });
    _httpRequests[requestId] = httpOwner;
    unawaited(
      _executeHttpRequest(
        context,
        requestId,
        url,
        options,
        ownerKey == null ? null : _deadlines[ownerKey],
        httpOwner,
        ownerKey,
      ).whenComplete(() {
        unlink?.call();
        if (identical(_httpRequests[requestId], httpOwner)) {
          _httpRequests.remove(requestId);
        }
      }),
    );
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
    if (completer.isCompleted) return;
    if (success && url != null) {
      completer.complete(url);
    } else {
      completer.completeError(error ?? '未知错误');
    }
  }

  Future<void> _executeHttpRequest(
    _LxRuntimeContext context,
    String requestId,
    String url,
    Map<String, dynamic> options,
    DateTime? deadline,
    ResolutionRequest? owner,
    String? ownerKey,
  ) async {
    if (context.disposed || !identical(context, _context)) return;
    final httpClock = Stopwatch()..start();
    StructuredLogService.event(
      'lx.http_started',
      fields: {
        'request_id': requestId,
        'resolution_id': ownerKey,
        'budget_ms': deadline?.difference(DateTime.now()).inMilliseconds,
      },
    );
    try {
      final remaining = deadline?.difference(DateTime.now());
      if (remaining != null && remaining <= Duration.zero) {
        throw TimeoutException('Lx HTTP request expired before execution');
      }
      final result = await LxHttpBridge.performHttpRequest(
        url,
        options,
        timeout: remaining ?? const Duration(seconds: 30),
        request: owner,
        requestId: requestId,
        resolutionId: ownerKey,
      );
      final responseBody = result['body'];
      final bodyType = switch (responseBody) {
        null => 'null',
        Map() => 'object',
        List() => 'array',
        String() => 'string',
        bool() => 'boolean',
        num() => 'number',
        _ => 'unknown',
      };
      final resolutionOwner = _owners[ownerKey];
      if (resolutionOwner != null && !resolutionOwner.isCancelled) {
        resolutionOwner.lastHttpResponse = (
          status: result['statusCode'] as int,
          bodyType: bodyType,
          businessCode: responseBody is Map && responseBody['code'] is int
              ? responseBody['code'] as int
              : null,
        );
      }
      final endpoint = Uri.tryParse(url);
      StructuredLogService.event(
        'lx.http_response',
        level: (result['statusCode'] as int) >= 400
            ? LogLevel.warning
            : LogLevel.info,
        fields: {
          'request_id': requestId,
          'resolution_id': ownerKey,
          'host': endpoint?.host,
          'status': result['statusCode'],
          'body_type': bodyType,
          'business_code': responseBody is Map ? responseBody['code'] : null,
          'elapsed_ms': httpClock.elapsedMilliseconds,
        },
      );
      _debug('✅ [LxQuickJsRuntime] HTTP 请求成功，准备回调 JS');
      _debug('   requestId: $requestId');
      _debug('   body type: $bodyType');

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
      if (context.disposed ||
          owner?.isCancelled == true ||
          !identical(context, _context) ||
          (deadline != null && !DateTime.now().isBefore(deadline))) {
        return;
      }
      await _evaluate(
        'globalThis.__lx_handleHttpResponse__($responseData);',
        context: context,
        operationDeadline: deadline,
      );
      _debug('✅ [LxQuickJsRuntime] __lx_handleHttpResponse__ 调用完成');
    } catch (e, st) {
      if (owner?.isCancelled == true) {
        StructuredLogService.event(
          'lx.http_cancelled',
          fields: {
            'request_id': requestId,
            'resolution_id': ownerKey,
            'elapsed_ms': httpClock.elapsedMilliseconds,
          },
        );
        return;
      }
      StructuredLogService.event(
        'lx.http_failed',
        level: LogLevel.warning,
        fields: {
          'request_id': requestId,
          'resolution_id': ownerKey,
          'elapsed_ms': httpClock.elapsedMilliseconds,
          'deadline_exceeded':
              deadline != null && !DateTime.now().isBefore(deadline),
        },
        error: e,
      );
      _error('❌ [LxQuickJsRuntime] HTTP 请求/回调失败: $e');
      _error('   Stack: $st');

      final errorData = jsonEncode({
        'requestId': requestId,
        'success': false,
        'error': e.toString(),
      });

      try {
        if (context.disposed ||
            !identical(context, _context) ||
            (deadline != null && !DateTime.now().isBefore(deadline))) {
          return;
        }
        await _evaluate(
          'globalThis.__lx_handleHttpResponse__($errorData);',
          context: context,
          operationDeadline: deadline,
        );
      } catch (e2) {
        _error('❌ [LxQuickJsRuntime] 错误回调也失败: $e2');
      }
    }
  }
}
