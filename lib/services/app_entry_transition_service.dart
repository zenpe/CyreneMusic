import '../features/audio_source/audio_source_feature.dart';

/// 统一处理引导流程结束后的入口状态切换。
///
/// 将“协议确认 + 本地模式开关 + 状态刷新”收敛到一个服务中，
/// 避免页面层重复实现同一业务流程。
class AppEntryTransitionService {
  static final AppEntryTransitionService _instance =
      AppEntryTransitionService._internal();
  factory AppEntryTransitionService() => _instance;
  AppEntryTransitionService._internal();

  final AudioSourceFacade _audioSourceFacade = AudioSourceFacade();

  /// 用户确认协议并进入主界面（非本地模式）。
  Future<void> acceptTermsAndEnterMain() =>
      _audioSourceFacade.acceptTermsAndEnterMain();

  /// 跳过配置后直接进入主界面（行为同协议确认进入）。
  Future<void> skipSetupAndEnterMain() =>
      _audioSourceFacade.skipSetupAndEnterMain();

  /// 启用本地模式并进入主界面。
  Future<void> enterLocalModeAndEnterMain() =>
      _audioSourceFacade.enterLocalModeAndEnterMain();

  /// 重置为“待配置音源”状态并返回引导流程。
  ///
  /// 保留协议确认状态，仅确保不再处于本地模式，
  /// 同时清空当前活动音源选择。
  Future<void> resetToInitialSourceSetup() =>
      _audioSourceFacade.resetToInitialSourceSetup();
}
