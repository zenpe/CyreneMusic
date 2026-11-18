import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:flutter/widgets.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'api/api_client.dart';
import 'lx_quickjs_runtime.dart';
import 'lx_runtime_interface.dart';
import 'source_recommendation_service.dart';

class AutomaticTarget {
  const AutomaticTarget(this.path, this.hash, this.name);
  final String path, hash, name;
  factory AutomaticTarget.fromJson(dynamic value) {
    if (value is! Map ||
        value['path'] is! String ||
        !(value['path'] as String).endsWith('.js') ||
        (value['path'] as String).length > 1024 ||
        value['sha256'] is! String ||
        !RegExp(r'^[a-f0-9]{64}$').hasMatch(value['sha256'] as String) ||
        value['name'] is! String ||
        (value['name'] as String).isEmpty ||
        (value['name'] as String).length > 1024) {
      throw const FormatException('自动推荐目标无效');
    }
    return AutomaticTarget(value['path'], value['sha256'], value['name']);
  }
  Map<String, dynamic> toJson() => {'path': path, 'sha256': hash, 'name': name};
}

class AutomaticPlan {
  AutomaticPlan(this.id, Map<String, AutomaticTarget> targets)
    : targets = Map.unmodifiable(targets);
  final String id;
  final Map<String, AutomaticTarget> targets;
  factory AutomaticPlan.fromJson(dynamic value) {
    if (value is! Map ||
        value['format'] != 1 ||
        value['quality'] != '128k' ||
        value['planId'] is! String ||
        !RegExp(r'^p-[a-f0-9]{32}$').hasMatch(value['planId']) ||
        value['targets'] is! Map) {
      throw const FormatException('自动推荐清单无效或版本不受支持');
    }
    final targets = <String, AutomaticTarget>{};
    for (final entry in (value['targets'] as Map).entries) {
      if (!const ['qq', 'netease'].contains(entry.key)) {
        throw const FormatException('自动推荐平台不受支持');
      }
      targets[entry.key] = AutomaticTarget.fromJson(entry.value);
    }
    if (targets.isEmpty) throw const FormatException('自动推荐清单为空');
    return AutomaticPlan(value['planId'], targets);
  }
  Map<String, dynamic> toJson() => {
    'format': 1,
    'planId': id,
    'quality': '128k',
    'targets': targets.map((k, v) => MapEntry(k, v.toJson())),
  };
}

class AutomaticHttpResponse {
  const AutomaticHttpResponse(this.status, this.bytes);
  final int status;
  final List<int> bytes;
}

typedef AutomaticFetch = Future<AutomaticHttpResponse> Function(
  String url,
  Map<String, String> headers,
  int limit,
);

class _Context {
  _Context(this.hash, this.runtime);
  final String hash;
  final LxRuntime runtime;
  int leases = 0;
  bool retiring = false;
  bool disposing = false;

  bool supports(String platform) {
    final code = platform == 'qq' ? 'tx' : 'wy';
    final info = runtime.currentScript;
    return !disposing &&
        runtime.isScriptReady &&
        info != null &&
        info.supportedSources.contains(code) &&
        info.getQualitiesForPlatform(code).contains('128k');
  }
}

/// Pins one platform's immutable resolver for the lifetime of the actual work.
class AutomaticRoute {
  AutomaticRoute._(
    this.origin,
    this.platform,
    this.target,
    this.planId,
    this._context,
    this._release,
  );
  final String origin, platform, planId;
  final AutomaticTarget target;
  final _Context _context;
  final void Function(_Context) _release;
  String get fingerprint => sha256
      .convert(utf8.encode(jsonEncode([origin, platform, '128k', target.hash])))
      .toString();
  AutomaticLease acquire() {
    if (_context.disposing) throw StateError('自动推荐目标已过期，请重试');
    _context.leases++;
    return AutomaticLease._(this);
  }
}

class AutomaticLease {
  AutomaticLease._(this.route);
  static final Object _key = Object();
  static AutomaticLease? get current => Zone.current[_key] as AutomaticLease?;
  final AutomaticRoute route;
  bool _released = false;
  LxRuntime get runtime => route._context.runtime;
  T run<T>(T Function() work) => runZoned(work, zoneValues: {_key: this});
  void release() {
    if (_released) return;
    _released = true;
    route._context.leases--;
    route._release(route._context);
  }
}

/// Automatic mode owns its contexts. It never commits the ordinary singleton.
class AutomaticRecommendationRouter extends ChangeNotifier
    with WidgetsBindingObserver {
  AutomaticRecommendationRouter({
    AutomaticFetch? fetch,
    LxRuntime Function()? runtimeFactory,
    Future<Directory> Function()? directory,
    Future<void> Function(Future<void> Function())? commit,
    bool Function()? isCurrent,
    int Function()? selectionEpoch,
  }) : _fetch = fetch ?? _http,
       _factory = runtimeFactory ?? LxQuickJsRuntime.new,
       _directory = directory ?? getApplicationSupportDirectory,
       _commit = commit ?? ((work) => work()),
       _isCurrent = isCurrent ?? (() => true),
       _selectionEpoch = selectionEpoch ?? (() => 0);

  final AutomaticFetch _fetch;
  final LxRuntime Function() _factory;
  final Future<Directory> Function() _directory;
  final Future<void> Function(Future<void> Function()) _commit;
  final bool Function() _isCurrent;
  final int Function() _selectionEpoch;
  final Map<String, _Context> _contexts = {};
  final Map<String, AutomaticRoute> _routes = {};
  final Map<String, int> _failures = {};
  final Map<String, DateTime> _retryAt = {};
  Map<String, dynamic> _applied = {};
  Map<String, dynamic> health = {};
  AutomaticPlan? desired;
  String origin = '';
  String? updateError;
  final Map<String, String> platformErrors = {};
  Future<void>? _checking;
  Future<void>? _restoring;
  Timer? _timer;
  bool _active = false, _observing = false;
  int _generation = 0;
  DateTime? _lastCheck;
  Directory? _root;
  String get _storageKey =>
      'automatic_recommendation_v1_${sha256.convert(utf8.encode(origin))}';
  bool get isReady => _routes.keys.any((p) => routeFor(p) != null);
  List<String> get platforms =>
      _routes.keys.where((p) => routeFor(p) != null).toList();
  AutomaticRoute? routeFor(String platform) {
    final route = _routes[platform];
    return _active && route != null && route._context.supports(platform)
        ? route
        : null;
  }
  Map<String, AutomaticRoute> get routes =>
      Map.unmodifiable({for (final p in platforms) p: _routes[p]!});

  bool _waitingToRetry(String platform, DateTime now) {
    final deadline = _retryAt[platform];
    return deadline != null && now.isBefore(deadline);
  }

  static Future<AutomaticHttpResponse> _http(
    String url,
    Map<String, String> headers,
    int limit,
  ) async {
    final cancel = CancelToken();
    final timer = Timer(const Duration(seconds: 10), () => cancel.cancel());
    try {
      final response = await ApiClient().requestStream(
        url,
        auth: false,
        headers: headers,
        timeout: const Duration(seconds: 10),
        cancelToken: cancel,
      );
      final status = response.statusCode ?? 0;
      if (status != 200) {
        cancel.cancel();
        return AutomaticHttpResponse(status, const []);
      }
      final builder = BytesBuilder(copy: false);
      var count = 0;
      await for (final chunk in response.data!.stream) {
        count += chunk.length;
        if (count > limit) throw const FormatException('自动推荐响应超过大小限制');
        builder.add(chunk);
      }
      return AutomaticHttpResponse(status, builder.takeBytes());
    } finally {
      timer.cancel();
      cancel.cancel();
    }
  }

  Future<void> start(String backendOrigin, {bool remote = true}) async {
    origin = SourceRecommendationService.normalizeOrigin(backendOrigin);
    _active = true;
    final generation = ++_generation;
    await (_restoring = _restore(generation));
    if (remote && _valid(generation)) await check(force: true);
  }

  void follow() {
    if (!_active) return;
    if (!_observing) {
      WidgetsBinding.instance.addObserver(this);
      _observing = true;
    }
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(minutes: 1), (_) {
      if (WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed ||
          WidgetsBinding.instance.lifecycleState == null) {
        unawaited(check());
      }
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) unawaited(check());
  }

  bool _valid(int generation) =>
      _active && generation == _generation && _isCurrent();
  void _checkCurrent(
    int generation,
    int epoch, {
    String? platform,
    String? hash,
  }) {
    if (!_valid(generation) ||
        epoch != _selectionEpoch() ||
        (platform != null && desired?.targets[platform]?.hash != hash)) {
      throw StateError('自动推荐更新已失效');
    }
  }

  Future<Directory> _ensureRoot() async {
    if (_root != null) return _root!;
    final base = await _directory();
    final root = Directory(
      '${base.path}/automatic_recommendations/${sha256.convert(utf8.encode(origin))}',
    );
    await root.create(recursive: true);
    return _root = root;
  }

  Future<void> _persist(Map<String, dynamic> applied) async {
    final prefs = await SharedPreferences.getInstance();
    if (!await prefs.setString(
      _storageKey,
      jsonEncode({
        'format': 1,
        'origin': origin,
        'desired': desired?.toJson(),
        'applied': applied,
      }),
    )) {
      throw StateError('自动推荐配置保存失败');
    }
  }

  Future<void> _restore(int generation) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_storageKey);
      if (raw == null) return;
      final state = jsonDecode(raw);
      if (state is! Map ||
          state['format'] != 1 ||
          state['origin'] != origin ||
          state['applied'] is! Map) {
        throw const FormatException('本地自动推荐记录无效');
      }
      if (state['desired'] != null) {
        try {
          desired = AutomaticPlan.fromJson(state['desired']);
        } catch (_) {
          // A corrupt desired record cannot suppress valid local targets or
          // cause us to send a conditional request for an unknown plan.
          desired = null;
        }
      }
      final root = await _ensureRoot();
      for (final entry in (state['applied'] as Map).entries) {
        try {
          final platform = entry.key as String;
          if (!const ['qq', 'netease'].contains(platform)) continue;
          if (desired != null && !desired!.targets.containsKey(platform)) {
            continue;
          }
          final target = AutomaticTarget.fromJson(entry.value['target']);
          final planId = entry.value['planId'] as String;
          if (!RegExp(r'^p-[a-f0-9]{32}$').hasMatch(planId)) {
            throw const FormatException('本机计划版本无效');
          }
          final bytes = await _readScript(
            File('${root.path}/${target.hash}.js'),
          );
          final context = await _prepare(target, bytes);
          _validateCapabilities(context, platform);
          if (!_valid(generation)) {
            _collect();
            return;
          }
          _routes[platform] = AutomaticRoute._(
            origin,
            platform,
            target,
            planId,
            context,
            _release,
          );
          _applied[platform] = entry.value;
        } catch (error) {
          platformErrors['${entry.key}'] = '本地版本恢复失败：$error';
        }
      }
    } catch (error) {
      updateError = '$error';
    }
    _collect();
  }

  Future<void> check({bool force = false}) {
    if (!_active || !_isCurrent()) return Future.value();
    if (_checking != null) return _checking!;
    final now = DateTime.now();
    final pending =
        desired?.targets.entries.any(
          (e) =>
              routeFor(e.key)?.target.hash != e.value.hash &&
              !_waitingToRetry(e.key, now),
        ) ??
        false;
    if (!force &&
        !pending &&
        _lastCheck != null &&
        now.difference(_lastCheck!) < const Duration(minutes: 15)) {
      return Future.value();
    }
    late final Future<void> work;
    work = _update(force: force).whenComplete(() {
      if (identical(_checking, work)) _checking = null;
    });
    return _checking = work;
  }

  Future<void> _update({required bool force}) async {
    final generation = _generation, epoch = _selectionEpoch();
    try {
      final response = await _fetch('$origin/lx/recommendation-plan', {
        'Cache-Control': 'no-cache',
        if (desired != null) 'If-None-Match': '"${desired!.id}"',
      }, 64 * 1024);
      _checkCurrent(generation, epoch);
      if (response.status == 200) {
        if (response.bytes.length > 64 * 1024) {
          throw const FormatException('清单超过大小限制');
        }
        final plan = AutomaticPlan.fromJson(
          jsonDecode(utf8.decode(response.bytes)),
        );
        final oldDesired = desired;
        desired = plan;
        try {
          await _commit(() async {
            _checkCurrent(generation, epoch);
            // Commit explicit removals together with the new desired plan.
            // A restart followed by 304 must not resurrect a removed platform.
            final next = Map<String, dynamic>.from(_applied)
              ..removeWhere((p, _) => !plan.targets.containsKey(p));
            await _persist(next);
            _checkCurrent(generation, epoch);
            _applied = next;
            _routes.removeWhere((p, _) => !plan.targets.containsKey(p));
          });
        } catch (_) {
          desired = oldDesired;
          rethrow;
        }
        _checkCurrent(generation, epoch);
      } else if (response.status != 304 || desired == null) {
        throw StateError(
          response.status == 404
              ? '服务器尚未提供自动推荐'
              : '自动推荐更新失败（${response.status}）',
        );
      }
      _lastCheck = DateTime.now();
      updateError = null;
      for (final entry in desired!.targets.entries) {
        final platform = entry.key, target = entry.value;
        if (routeFor(platform)?.target.hash == target.hash) continue;
        if (!force && _waitingToRetry(platform, DateTime.now())) {
          continue;
        }
        try {
          final root = await _ensureRoot();
          final file = File('${root.path}/${target.hash}.js');
          List<int>? bytes;
          if (await file.exists()) {
            try {
              final cached = await _readScript(file);
              SourceRecommendationService.verifiedScript(cached, target.hash);
              bytes = cached;
            } catch (_) {
              /* Download verified replacement. */
            }
          }
          if (bytes == null) {
            final download = await _fetch(
              '$origin/lx/recommendation-scripts/${target.hash}.js',
              const {},
              8 * 1024 * 1024,
            );
            if (download.status != 200) {
              throw StateError('脚本下载失败（${download.status}）');
            }
            bytes = download.bytes;
            SourceRecommendationService.verifiedScript(bytes, target.hash);
            _checkCurrent(
              generation,
              epoch,
              platform: platform,
              hash: target.hash,
            );
            final temp = File(
              '${file.path}.${DateTime.now().microsecondsSinceEpoch}.tmp',
            );
            try {
              await temp.writeAsBytes(bytes, flush: true);
              await temp.rename(file.path);
            } finally {
              if (await temp.exists()) await temp.delete();
            }
          }
          _checkCurrent(
            generation,
            epoch,
            platform: platform,
            hash: target.hash,
          );
          final context = await _prepare(target, bytes);
          _validateCapabilities(context, platform);
          await _commit(() async {
            _checkCurrent(
              generation,
              epoch,
              platform: platform,
              hash: target.hash,
            );
            final planId = desired!.id;
            final next = {
              ..._applied,
              platform: {'target': target.toJson(), 'planId': planId},
            };
            await _persist(next);
            _checkCurrent(
              generation,
              epoch,
              platform: platform,
              hash: target.hash,
            );
            _applied = next;
            _routes[platform] = AutomaticRoute._(
              origin,
              platform,
              target,
              planId,
              context,
              _release,
            );
          });
          platformErrors.remove(platform);
          _retryAt.remove(platform);
          _failures.remove(platform);
        } catch (error) {
          if (!_valid(generation)) return;
          platformErrors[platform] = '$error';
          final failures = (_failures[platform] ?? 0) + 1;
          _failures[platform] = failures;
          _retryAt[platform] = DateTime.now().add(
            Duration(minutes: (1 << (failures - 1).clamp(0, 4)).clamp(1, 15)),
          );
        } finally {
          _collect();
        }
      }
      try {
        final response = await _fetch(
          '$origin/lx/recommendation-status',
          const {},
          64 * 1024,
        );
        _checkCurrent(generation, epoch);
        if (response.status == 200) {
          final body = jsonDecode(utf8.decode(response.bytes));
          if (body is Map && body['format'] == 1 && body['platforms'] is Map) {
            health = Map<String, dynamic>.from(body['platforms']);
          }
        }
      } catch (_) {
        /* Status never prevents applying a valid target. */
      }
    } catch (error) {
      if (_valid(generation)) {
        updateError = '$error';
        _lastCheck = DateTime.now();
      }
    } finally {
      _collect();
      if (_valid(generation)) await _pruneScripts();
      if (_valid(generation)) notifyListeners();
    }
  }

  Future<List<int>> _readScript(File file) async {
    final stat = await file.stat();
    if (stat.type != FileSystemEntityType.file || stat.size > 8 * 1024 * 1024) {
      throw const FormatException('本地脚本无效或超过大小限制');
    }
    return file.readAsBytes();
  }

  Future<void> _pruneScripts() async {
    // Only this origin's immutable script files; persisted targets and leased
    // runtimes remain protected. Cleanup failure must never undo activation.
    final root = _root;
    if (root == null) return;
    try {
      await for (final entry in root.list(followLinks: false)) {
        final name = entry.uri.pathSegments.last;
        if (entry is! File || !RegExp(r'^[a-f0-9]{64}\.js$').hasMatch(name)) {
          continue;
        }
        final hash = name.substring(0, 64);
        if (_contexts.containsKey(hash) ||
            (desired?.targets.values.any((t) => t.hash == hash) ?? false) ||
            _applied.values.any((v) => v['target']['sha256'] == hash)) {
          continue;
        }
        await entry.delete();
      }
    } catch (_) {
      // Retry on the next update.
    }
  }

  Future<_Context> _prepare(AutomaticTarget target, List<int> bytes) async {
    final script = SourceRecommendationService.verifiedScript(
      bytes,
      target.hash,
    );
    final cached = _contexts[target.hash];
    if (cached?.disposing == true) {
      throw StateError('正在等待旧解析上下文释放后更新');
    }
    if (cached != null && cached.runtime.isScriptReady) {
      cached.retiring = false;
      return cached;
    }
    _collect();
    if ((cached == null && _contexts.length >= 4) ||
        (cached != null && cached.leases != 0)) {
      throw StateError('正在等待旧解析完成后更新');
    }
    final context = cached ?? _Context(target.hash, _factory());
    context.retiring = false;
    _contexts[target.hash] = context;
    context.leases++; // Preparation itself also owns a lease.
    try {
      final info = await context.runtime.loadScript(script);
      if (info == null || !context.runtime.isScriptReady) {
        throw StateError('推荐脚本初始化失败');
      }
      return context;
    } catch (_) {
      context.retiring = true;
      rethrow;
    } finally {
      context.leases--;
      _release(context);
    }
  }

  void _validateCapabilities(_Context context, String platform) {
    if (!context.supports(platform)) {
      throw UnsupportedError('推荐脚本未声明支持该平台的标准音质');
    }
  }

  void _collect() {
    final active = _routes.values.map((r) => r._context).toSet();
    for (final context in _contexts.values.toList()) {
      if (!active.contains(context)) {
        context.retiring = true;
        _release(context);
      }
    }
  }

  void _release(_Context context) {
    if (!context.retiring || context.leases != 0 || context.disposing) return;
    context.disposing = true;
    unawaited(
      context.runtime.dispose().catchError((Object _) {}).whenComplete(() {
        if (identical(_contexts[context.hash], context)) {
          _contexts.remove(context.hash);
        }
      }),
    );
  }

  void stop() {
    _active = false;
    _generation++;
    _timer?.cancel();
    if (_observing) {
      WidgetsBinding.instance.removeObserver(this);
      _observing = false;
    }
    _routes.clear();
    _collect();
  }

  Future<void> ready() async {
    await _restoring;
  }

  @override
  void dispose() {
    stop();
    super.dispose();
  }
}
