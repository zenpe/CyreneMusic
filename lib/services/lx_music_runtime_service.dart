import 'lx_quickjs_runtime.dart';
import 'lx_runtime_interface.dart';

class LxMusicRuntimeService {
  static final LxMusicRuntimeService _instance =
      LxMusicRuntimeService._internal();
  factory LxMusicRuntimeService() => _instance;
  LxMusicRuntimeService._internal();

  final LxRuntime _runtime = LxQuickJsRuntime();

  bool get isInitialized => _runtime.isInitialized;
  bool get isScriptReady => _runtime.isScriptReady;
  LxScriptInfo? get currentScript => _runtime.currentScript;
  LxRuntimeFailure? get lastFailure => _runtime.lastFailure;

  Future<void> initialize() => _runtime.initialize();

  Future<void> dispose() => _runtime.dispose();

  Future<LxScriptInfo?> loadScript(String scriptContent) =>
      _runtime.loadScript(scriptContent);

  Future<String?> getMusicUrl({
    required String source,
    required dynamic songId,
    required String quality,
    Map<String, dynamic>? musicInfo,
  }) {
    return _runtime.getMusicUrl(
      source: source,
      songId: songId,
      quality: quality,
      musicInfo: musicInfo,
    );
  }
}
