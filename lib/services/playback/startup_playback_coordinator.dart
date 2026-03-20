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

    final settings = AppSettingsService();
    await settings.ensureInitialized();
    if (!settings.restorePlaybackSessionOnStartup) return;

    final restored = await PlaybackService().restoreSessionOnStartup(
      autoPlay: settings.autoPlayAfterRestoreOnStartup,
    );
    print(
      restored
          ? '[StartupPlaybackCoordinator] 已恢复本地播放会话'
          : '[StartupPlaybackCoordinator] 未找到可恢复的本地播放会话',
    );
  }
}
