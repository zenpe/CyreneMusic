import 'audio_source_service.dart';
import 'auth_service.dart';
import 'persistent_storage_service.dart';

/// 应用入口判定结果（与具体页面解耦）。
enum AppEntryRoute { navidromeMain, navidromeSetup, regularMain, regularSetup }

/// 应用入口判定所需的状态快照。
class AppEntryState {
  final bool isLoggedIn;
  final bool isConfigured;
  final bool isNavidromeActive;
  final bool isTermsAccepted;
  final bool isLocalMode;

  const AppEntryState({
    required this.isLoggedIn,
    required this.isConfigured,
    required this.isNavidromeActive,
    required this.isTermsAccepted,
    required this.isLocalMode,
  });

  factory AppEntryState.fromServices({
    AudioSourceService? audioSourceService,
    PersistentStorageService? storageService,
    AuthService? authService,
  }) {
    final audio = audioSourceService ?? AudioSourceService();
    final storage = storageService ?? PersistentStorageService();
    return AppEntryState(
      isLoggedIn: (authService ?? AuthService()).isLoggedIn,
      isConfigured: audio.isConfigured,
      isNavidromeActive: audio.isNavidromeActive,
      isTermsAccepted: storage.termsAccepted,
      isLocalMode: storage.enableLocalMode,
    );
  }
}

/// 统一的应用入口判定器。
///
/// 仅负责根据状态返回路由类型，不依赖具体 UI 组件。
class AppEntryResolver {
  static AppEntryRoute resolveFromServices({
    AudioSourceService? audioSourceService,
    PersistentStorageService? storageService,
    AuthService? authService,
  }) {
    final state = AppEntryState.fromServices(
      audioSourceService: audioSourceService,
      storageService: storageService,
      authService: authService,
    );
    return resolve(
      isLoggedIn: state.isLoggedIn,
      isConfigured: state.isConfigured,
      isNavidromeActive: state.isNavidromeActive,
      isTermsAccepted: state.isTermsAccepted,
      isLocalMode: state.isLocalMode,
    );
  }

  static AppEntryRoute resolve({
    required bool isLoggedIn,
    required bool isConfigured,
    required bool isNavidromeActive,
    required bool isTermsAccepted,
    required bool isLocalMode,
  }) {
    // Authentication and explicit consent apply to every source and mode.
    if (!isLoggedIn || !isTermsAccepted) {
      return AppEntryRoute.regularSetup;
    }
    if (isNavidromeActive) {
      return (isConfigured && isTermsAccepted)
          ? AppEntryRoute.navidromeMain
          : AppEntryRoute.navidromeSetup;
    }

    if (isConfigured) {
      return AppEntryRoute.regularMain;
    }

    return AppEntryRoute.regularSetup;
  }
}
