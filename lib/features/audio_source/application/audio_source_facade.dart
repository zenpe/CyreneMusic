import 'package:flutter/foundation.dart';

import '../../../services/app_entry_resolver.dart';
import '../../../services/auth_service.dart';
import '../../../services/navidrome_api.dart';
import '../../../services/navidrome_session_service.dart';
import '../../../services/persistent_storage_service.dart';
import 'audio_source_controller.dart';
import 'audio_source_read_controller.dart';

/// 应用入口路由（UI 层专用）。
enum AppGateRoute {
  navidromeMain,
  navidromeSetup,
  regularMain,
  regularSetup,
}

/// 音源门面。
///
/// 为页面层提供统一的读写入口，隔离对底层单例服务的散落依赖。
class AudioSourceFacade {
  static final AudioSourceFacade _instance = AudioSourceFacade._internal();

  factory AudioSourceFacade() => _instance;

  AudioSourceFacade.withDependencies({
    required AudioSourceReadController readController,
    required AudioSourceController writeController,
    required PersistentStorageService storageService,
    required AuthService authService,
    required NavidromeSessionService navidromeSessionService,
  })  : _readController = readController,
        _writeController = writeController,
        _storageService = storageService,
        _authService = authService,
        _navidromeSessionService = navidromeSessionService;

  AudioSourceFacade._internal({
    AudioSourceReadController? readController,
    AudioSourceController? writeController,
    PersistentStorageService? storageService,
    AuthService? authService,
    NavidromeSessionService? navidromeSessionService,
  })  : _readController = readController ?? AudioSourceReadController(),
        _writeController = writeController ?? AudioSourceController(),
        _storageService = storageService ?? PersistentStorageService(),
        _authService = authService ?? AuthService(),
        _navidromeSessionService =
            navidromeSessionService ?? NavidromeSessionService();

  final AudioSourceReadController _readController;
  final AudioSourceController _writeController;
  final PersistentStorageService _storageService;
  final AuthService _authService;
  final NavidromeSessionService _navidromeSessionService;

  bool get isAudioConfigured => _readController.isConfigured;
  bool get isNavidromeActive => _readController.isNavidromeActive;
  bool get isLoggedIn => _authService.isLoggedIn;
  bool get termsAccepted => _storageService.termsAccepted;
  bool get isLocalModeEnabled => _storageService.enableLocalMode;
  bool get isThemeConfigured => _storageService.themeConfigured;

  String get navidromeBaseUrl => _navidromeSessionService.baseUrl;
  String get navidromeUsername => _navidromeSessionService.username;

  bool containsStorageKey(String key) => _storageService.containsKey(key);

  Future<void> setThemeConfigured(bool value) =>
      _storageService.setThemeConfigured(value);

  AppGateRoute resolveEntryRoute() {
    final route = AppEntryResolver.resolve(
      isConfigured: isAudioConfigured,
      isNavidromeActive: isNavidromeActive,
      isTermsAccepted: termsAccepted,
      isLocalMode: isLocalModeEnabled,
    );
    return switch (route) {
      AppEntryRoute.navidromeMain => AppGateRoute.navidromeMain,
      AppEntryRoute.navidromeSetup => AppGateRoute.navidromeSetup,
      AppEntryRoute.regularMain => AppGateRoute.regularMain,
      AppEntryRoute.regularSetup => AppGateRoute.regularSetup,
    };
  }

  void addEntryStateListener(VoidCallback listener) {
    _readController.addListener(listener);
    _navidromeSessionService.addListener(listener);
  }

  void removeEntryStateListener(VoidCallback listener) {
    _readController.removeListener(listener);
    _navidromeSessionService.removeListener(listener);
  }

  void addSetupStateListener(VoidCallback listener) {
    _readController.addListener(listener);
    _authService.addListener(listener);
  }

  void removeSetupStateListener(VoidCallback listener) {
    _readController.removeListener(listener);
    _authService.removeListener(listener);
  }

  void addAudioSourceStateListener(VoidCallback listener) {
    _readController.addListener(listener);
  }

  void removeAudioSourceStateListener(VoidCallback listener) {
    _readController.removeListener(listener);
  }

  Future<void> acceptTermsAndEnterMain() async {
    await _storageService.setTermsAccepted(true);
    await _storageService.setEnableLocalMode(false);
    _notifyEntryStateChanged();
  }

  Future<void> skipSetupAndEnterMain() => acceptTermsAndEnterMain();

  Future<void> enterLocalModeAndEnterMain() async {
    await _storageService.setEnableLocalMode(true);
    await _storageService.setTermsAccepted(true);
    _notifyEntryStateChanged();
  }

  Future<void> resetToInitialSourceSetup() async {
    await _storageService.setEnableLocalMode(false);
    final result = await _writeController.clearSelection();
    if (!result.isSuccess) {
      throw Exception(result.errorMessage ?? '重置音源状态失败');
    }
    _authService.refresh();
  }

  Future<bool> testNavidromeConnection({
    required String baseUrl,
    required String username,
    required String password,
  }) async {
    final api = NavidromeApi(
      baseUrl: baseUrl,
      username: username,
      password: password,
    );
    return api.ping();
  }

  Future<void> saveNavidromeConfig({
    required String baseUrl,
    required String username,
    required String password,
  }) {
    return _navidromeSessionService.saveConfig(
      baseUrl: baseUrl,
      username: username,
      password: password,
    );
  }

  Future<void> clearNavidromeConfig() => _navidromeSessionService.clear();

  void _notifyEntryStateChanged() {
    _readController.refresh();
    _authService.refresh();
  }
}
