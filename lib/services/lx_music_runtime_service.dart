import 'package:flutter/foundation.dart';
import 'dart:async';
import 'lx_quickjs_runtime.dart';
import 'lx_runtime_interface.dart';

class LxMusicRuntimeService implements LxRuntime, LxStagedRuntime {
  static final LxMusicRuntimeService _instance =
      LxMusicRuntimeService._internal();
  factory LxMusicRuntimeService() => _instance;
  LxMusicRuntimeService._internal();

  @visibleForTesting
  LxMusicRuntimeService.withFactory(LxRuntime Function() factory)
    : _factory = factory,
      _runtime = factory();

  LxRuntime _runtime = LxQuickJsRuntime();
  LxRuntime Function()? _factory = LxQuickJsRuntime.new;
  final Set<_RuntimeCandidate> _candidates = {};
  int _generation = 0;

  @visibleForTesting
  void useRuntimeForTesting(LxRuntime runtime) {
    _runtime = runtime;
    _factory = null;
    _generation++;
  }

  @override
  bool get supportsStaging => _factory != null;

  @override
  Future<LxRuntimeCandidate> prepareScript(String content) async {
    final generation = _generation;
    final candidate = _RuntimeCandidate(this, _factory!(), generation);
    _candidates.add(candidate);
    try {
      final info = await candidate.runtime.loadScript(content);
      if (candidate.closed || generation != _generation) {
        throw StateError('音源验证已取消');
      }
      if (info == null ||
          !candidate.runtime.isScriptReady ||
          info.supportedSources.isEmpty) {
        throw StateError(candidate.runtime.lastFailure?.message ?? '脚本加载失败');
      }
      candidate.info = info;
      return candidate;
    } catch (_) {
      // A queued native load may finish after disposal; clean that late result
      // too, rather than trusting the candidate's already-closed flag.
      if (candidate.closed) {
        await candidate.runtime.dispose();
      } else {
        await candidate.dispose();
      }
      rethrow;
    }
  }

  @override
  bool get isInitialized => _runtime.isInitialized;
  @override
  bool get isAvailable => _runtime.isAvailable;
  @override
  bool get isScriptReady => _runtime.isScriptReady;
  @override
  LxScriptInfo? get currentScript => _runtime.currentScript;
  @override
  LxRuntimeFailure? get lastFailure => _runtime.lastFailure;

  @override
  Future<void> initialize() => _runtime.initialize();

  @override
  Future<void> dispose() async {
    _generation++;
    await Future.wait([
      _runtime.dispose(),
      ..._candidates.toList().map((candidate) => candidate.dispose()),
    ]);
  }

  @override
  Future<LxScriptInfo?> loadScript(String scriptContent) {
    _generation++;
    return _runtime.loadScript(scriptContent);
  }

  @override
  Future<String?> getMusicUrl({
    required String source,
    required dynamic songId,
    required String quality,
    Map<String, dynamic>? musicInfo,
    Duration? timeout,
  }) {
    return _runtime.getMusicUrl(
      source: source,
      songId: songId,
      quality: quality,
      musicInfo: musicInfo,
      timeout: timeout,
    );
  }
}

class _RuntimeCandidate implements LxRuntimeCandidate {
  _RuntimeCandidate(this.host, this.runtime, this.generation);
  final LxMusicRuntimeService host;
  final LxRuntime runtime;
  final int generation;
  LxScriptInfo? info;
  bool closed = false;
  @override
  LxScriptInfo get script => info!;

  @override
  void commit() {
    if (closed || generation != host._generation || !runtime.isScriptReady) {
      throw StateError('音源验证结果已过期');
    }
    final old = host._runtime;
    host._runtime = runtime;
    host._generation++;
    closed = true;
    host._candidates.remove(this);
    // Publication is synchronous. Cleanup cannot roll back a committed source.
    unawaited(
      Future<void>.sync(old.dispose).catchError((Object error) {
        debugPrint('LX old context cleanup failed: $error');
      }),
    );
  }

  @override
  Future<void> dispose() async {
    if (closed) return;
    closed = true;
    host._candidates.remove(this);
    await runtime.dispose();
  }
}
