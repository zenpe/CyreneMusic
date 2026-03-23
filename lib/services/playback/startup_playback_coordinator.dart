import '../app_settings_service.dart';
import '../system_media_service.dart';
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

    final autoPlay = settings.autoPlayAfterRestoreOnStartup;

    final restored = await PlaybackService().restoreSessionOnStartup(
      autoPlay: autoPlay,
      beforeDeferredAutoPlay: autoPlay
          ? () async {
              try {
                print(
                  '[StartupPlaybackCoordinator] 启动自动恢复播放前预初始化 audio_service...',
                );
                await SystemMediaService().ensureMobileInitialized();
                print(
                  '[StartupPlaybackCoordinator] audio_service 预初始化完成，开始恢复播放',
                );
              } catch (e) {
                print(
                  '[StartupPlaybackCoordinator] audio_service 预初始化失败，继续恢复播放: $e',
                );
              }
            }
          : null,
    );
    print(
      restored
          ? '[StartupPlaybackCoordinator] 已恢复本地播放会话'
          : '[StartupPlaybackCoordinator] 未找到可恢复的本地播放会话',
    );
  }
}
