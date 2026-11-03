import 'dart:async';
import 'package:cyrene_music/services/lx_runtime_interface.dart';

class FakeLxRuntime implements LxRuntime {
  LxScriptInfo? script;
  Completer<void>? loadGate;
  @override
  bool get isInitialized => script != null;
  @override
  bool get isScriptReady => script != null;
  @override
  bool get isAvailable => true;
  @override
  LxScriptInfo? get currentScript => script;
  @override
  LxRuntimeFailure? get lastFailure => null;
  @override
  Future<void> initialize() async {}
  @override
  Future<void> dispose() async {
    script = null;
  }

  @override
  Future<LxScriptInfo?> loadScript(String content) async {
    final gate = loadGate;
    loadGate = null;
    if (gate != null) await gate.future;
    if (content.isEmpty) return null;
    return script = LxScriptInfo(
      name: 'Test',
      version: '1',
      script: content,
      supportedSources: ['wy', 'tx', 'kg', 'kw'],
      supportedQualities: ['128k', '320k', 'flac'],
    );
  }

  @override
  Future<String?> getMusicUrl({
    required String source,
    required dynamic songId,
    required String quality,
    Map<String, dynamic>? musicInfo,
    Duration? timeout,
  }) async => null;
}
