import 'playback_state_service.dart';
import 'notification_service.dart';
import 'player_service.dart';
import 'app_settings_service.dart';

/// 播放恢复管理服务
/// 负责在应用启动时检查上次播放状态并询问用户是否继续播放
class PlaybackResumeService {
  static final PlaybackResumeService _instance = PlaybackResumeService._internal();
  factory PlaybackResumeService() => _instance;
  PlaybackResumeService._internal();

  bool _hasCheckedOnStartup = false;
  PlaybackState? _pendingState;

  /// 在应用启动时检查并显示恢复通知
  Future<void> checkAndShowResumeNotification() async {
    print('🔍 [PlaybackResumeService] 开始检查启动状态...');
    
    // 避免重复检查
    if (_hasCheckedOnStartup) {
      print('ℹ️ [PlaybackResumeService] 已检查过启动状态，跳过');
      return;
    }

    _hasCheckedOnStartup = true;

    try {
      final appSettings = AppSettingsService();
      await appSettings.ensureInitialized();
      if (!appSettings.showResumePromptOnStartup) {
        print('ℹ️ [PlaybackResumeService] 启动恢复提示已关闭，跳过');
        return;
      }

      print('📱 [PlaybackResumeService] 正在获取上次播放状态...');
      
      // 获取上次播放状态
      final state = await PlaybackStateService().getLastPlaybackState();

      if (state == null) {
        print('ℹ️ [PlaybackResumeService] 没有待恢复的播放状态');
        return;
      }

      print('✅ [PlaybackResumeService] 找到播放状态: ${state.track.name} - ${state.track.artists}');
      print('   播放位置: ${state.position.inSeconds}秒');
      print('   最后播放时间: ${state.lastPlayTime}');
      print('   上次平台: ${state.lastPlatform}');
      print('   当前平台: ${state.currentPlatform}');
      print('   是否跨平台: ${state.isCrossPlatform}');

      _pendingState = state;

      // 设置通知操作回调
      NotificationService().setActionCallback((action, payload) {
        print('🔔 [PlaybackResumeService] 通知操作: $action');
        _handleNotificationAction(action);
      });

      print('🔔 [PlaybackResumeService] 准备显示恢复播放通知...');

      // 显示恢复播放通知
      await NotificationService().showResumePlaybackNotification(
        trackName: state.track.name,
        artist: state.track.artists,
        coverUrl: state.coverUrl,
        platformInfo: state.isCrossPlatform ? state.platformDisplayText : null,
        payload: 'resume_playback',
      );

      print('✅ [PlaybackResumeService] 已显示恢复播放通知');
    } catch (e) {
      print('❌ [PlaybackResumeService] 检查播放状态失败: $e');
    }
  }

  /// 处理通知操作
  void _handleNotificationAction(String action) {
    switch (action) {
      case 'resume':
      case 'tap': // 点击通知本身也视为继续播放
        print('▶️ [PlaybackResumeService] 用户选择继续播放');
        manualResume();
        break;
      case 'dismiss':
        print('🚫 [PlaybackResumeService] 用户选择忽略');
        _clearPendingState();
        break;
    }

    // 取消通知
    NotificationService().cancelNotification(100);
  }

  /// 恢复播放
  Future<void> _resumePlayback() async {
    if (_pendingState == null) return;

    try {
      await PlayerService().resumeFromSavedState(_pendingState!);
      print('✅ [PlaybackResumeService] 播放已恢复');
    } catch (e) {
      print('❌ [PlaybackResumeService] 恢复播放失败: $e');
    } finally {
      _pendingState = null;
    }
  }

  /// 清除待处理状态
  Future<void> _clearPendingState() async {
    _pendingState = null;
    await PlaybackStateService().clearPlaybackState();
  }

  /// 手动触发恢复播放（用于UI按钮）
  Future<void> manualResume() async {
    final state = _pendingState ?? await PlaybackStateService().getLastPlaybackState();
    if (state == null) {
      print('ℹ️ [PlaybackResumeService] 没有可恢复的播放状态');
      return;
    }

    _pendingState = state;
    await _resumePlayback();
  }
}

