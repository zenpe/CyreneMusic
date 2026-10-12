import 'lx_quickjs_runtime.dart';
import 'lx_runtime_interface.dart';

class LxMusicRuntimeService implements LxRuntime {
  static final LxMusicRuntimeService _instance =
      LxMusicRuntimeService._internal();
  factory LxMusicRuntimeService() => _instance;
  LxMusicRuntimeService._internal();

  final LxRuntime _runtime = LxQuickJsRuntime();

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
  Future<void> dispose() => _runtime.dispose();

  @override
  Future<LxScriptInfo?> loadScript(String scriptContent) =>
      _runtime.loadScript(scriptContent);

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
