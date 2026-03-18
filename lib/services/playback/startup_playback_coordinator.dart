import '../app_settings_service.dart';
import 'playback_service.dart';

class StartupPlaybackCoordinator {
  StartupPlaybackCoordinator._internal();

  static final StartupPlaybackCoordinator _instance =
      StartupPlaybackCoordinator._internal();
  factory StartupPlaybackCoordinator() => _instance;

  bool _hasHandledStartupRestore = false;

  Future<void> restorePlaybackOnStartup() async {
    if (_hasHandledStartupRestore) return;
    _hasHandledStartupRestore = true;

    await AppSettingsService().ensureInitialized();
    if (!AppSettingsService().restorePlaybackSessionOnStartup) return;

    final restored = await PlaybackService().restoreSessionOnStartup();
    print(
      restored
          ? '[StartupPlaybackCoordinator] 已恢复本地播放会话'
          : '[StartupPlaybackCoordinator] 未找到可恢复的本地播放会话',
    );
  }
}
