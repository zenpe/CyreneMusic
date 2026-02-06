import 'lx_quickjs_runtime.dart';
import 'lx_runtime_interface.dart';
import 'lx_webview_runtime.dart';

class LxMusicRuntimeService {
  static final LxMusicRuntimeService _instance =
      LxMusicRuntimeService._internal();
  factory LxMusicRuntimeService() => _instance;
  LxMusicRuntimeService._internal();

  final LxRuntime _quickJsRuntime = LxQuickJsRuntime();
  final LxRuntime _webViewRuntime = LxWebViewRuntime();
  LxRuntime? _currentRuntime;

  bool get isInitialized => _currentRuntime?.isInitialized ?? false;
  bool get isScriptReady => _currentRuntime?.isScriptReady ?? false;
  LxScriptInfo? get currentScript => _currentRuntime?.currentScript;

  LxRuntime get _activeRuntime => _currentRuntime ?? _selectPrimaryRuntime();

  LxRuntime _selectPrimaryRuntime() {
    if (_quickJsRuntime.isAvailable) {
      return _quickJsRuntime;
    }
    return _webViewRuntime;
  }

  Future<void> initialize() async {
    final primary = _selectPrimaryRuntime();
    _currentRuntime = primary;
    try {
      await primary.initialize();
    } catch (e) {
      print('⚠️ [LxMusicRuntime] 主运行时初始化失败，尝试回退: $e');
      print('⚠️ [LxMusicRuntime] 当前平台 QuickJS 初始化失败，回退 WebView 运行时');
      await _fallbackToWebView();
    }
  }

  Future<void> dispose() async {
    await _quickJsRuntime.dispose();
    await _webViewRuntime.dispose();
    _currentRuntime = null;
  }

  Future<LxScriptInfo?> loadScript(String scriptContent) async {
    final runtime = _activeRuntime;
    final result = await runtime.loadScript(scriptContent);
    if (result != null && runtime.isScriptReady) {
      return result;
    }

    if (runtime == _webViewRuntime) {
      return result;
    }

    print('⚠️ [LxMusicRuntime] 主运行时脚本加载失败，回退 WebView');
    await _fallbackToWebView();
    return _webViewRuntime.loadScript(scriptContent);
  }

  Future<String?> getMusicUrl({
    required String source,
    required dynamic songId,
    required String quality,
    Map<String, dynamic>? musicInfo,
  }) {
    return _activeRuntime.getMusicUrl(
      source: source,
      songId: songId,
      quality: quality,
      musicInfo: musicInfo,
    );
  }

  Future<void> _fallbackToWebView() async {
    if (!_webViewRuntime.isAvailable) {
      throw Exception('WebView runtime unavailable');
    }
    _currentRuntime = _webViewRuntime;
    if (!_webViewRuntime.isInitialized) {
      await _webViewRuntime.initialize();
    }
  }
}
