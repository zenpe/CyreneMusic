import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/player_service.dart';
import '../models/lyric_line.dart';
import '../utils/lyric_parser.dart';
import 'mobile_player_components/mobile_player_background.dart';
import 'mobile_player_components/mobile_player_control_center.dart';
import 'mobile_player_components/mobile_player_fluid_cloud_layout.dart';
import 'mobile_player_components/mobile_player_classic_layout.dart';
import 'mobile_player_components/mobile_player_dialogs.dart';
import 'mobile_player_components/mobile_player_settings_sheet.dart';
import 'player_components/player_immersive_layout.dart';
import 'player_components/player_fluid_cloud_layout.dart';
import '../../services/lyric_style_service.dart';
import '../services/back_navigation_coordinator.dart';
import '../services/experience_profile_service.dart';
import '../services/structured_log_service.dart';

/// 移动端播放器页面（重构版本）
/// 适用于 Android/iOS，现在使用组件化架构
class MobilePlayerPage extends StatefulWidget {
  const MobilePlayerPage({super.key});

  @override
  State<MobilePlayerPage> createState() => _MobilePlayerPageState();
}

class _MobilePlayerPageState extends State<MobilePlayerPage>
    with TickerProviderStateMixin {
  static const _backCoordinator = BackNavigationCoordinator();
  // 歌词相关
  List<LyricLine> _lyrics = [];
  int _currentLyricIndex = -1;
  LyricLoadState _lyricState = LyricLoadState.idle;
  String? _lastTrackId;
  String? _lastLyricsSignature;

  // 控制中心
  bool _showControlCenter = false;
  bool _showTranslation = true;
  AnimationController? _controlCenterAnimationController;
  Animation<double>? _controlCenterFadeAnimation;

  @override
  void initState() {
    super.initState();
    _initializeAnimations();
    _setupListeners();
    _initializeData();
    // 初始检查：如果当前已经是沉浸模式，强制横屏
    _checkAndForceOrientation();
  }

  /// 根据当前歌词样式检查并强制设置屏幕方向
  void _checkAndForceOrientation() {
    if (!Platform.isAndroid && !Platform.isIOS) return;

    if (LyricStyleService().currentStyle == LyricStyle.immersive) {
      StructuredLogService.event('player_ui.immersive_enter');
      SystemChrome.setPreferredOrientations([
        DeviceOrientation.landscapeLeft,
        DeviceOrientation.landscapeRight,
      ]);
      // 进入全屏沉浸模式，隐藏状态栏和虚拟按键
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    } else {
      // 恢复系统默认（跟随重力感应或恢复到原本的设置，这里设为所有方向以解除锁定）
      SystemChrome.setPreferredOrientations([
        DeviceOrientation.portraitUp,
        DeviceOrientation.portraitDown,
        DeviceOrientation.landscapeLeft,
        DeviceOrientation.landscapeRight,
      ]);
      // 恢复状态栏和虚拟按键显示
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    }
  }

  /// 恢复到默认竖屏（用于关闭播放器时）
  void _resetOrientation() {
    if (!Platform.isAndroid && !Platform.isIOS) return;
    StructuredLogService.event('player_ui.exit');
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    // 确保退出时恢复状态栏
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  }

  /// 是否应该显示译文按钮（与全屏歌词页一致逻辑）
  bool _shouldShowTranslationButton() {
    if (_lyrics.isEmpty) return false;
    final hasTranslation = _lyrics.any(
      (l) => l.translation != null && l.translation!.isNotEmpty,
    );
    if (!hasTranslation) return false;
    final sample = _lyrics
        .where((l) => l.text.trim().isNotEmpty)
        .take(5)
        .map((l) => l.text)
        .join('');
    if (sample.isEmpty) return false;
    final chineseCount = sample.runes
        .where(
          (r) =>
              (r >= 0x4E00 && r <= 0x9FFF) ||
              (r >= 0x3400 && r <= 0x4DBF) ||
              (r >= 0x20000 && r <= 0x2A6DF),
        )
        .length;
    final ratio = chineseCount / sample.length;
    return ratio < 0.3; // 中文占比小于30%判定为外文
  }

  @override
  void dispose() {
    _resetOrientation();
    _disposeAnimations();
    _removeListeners();
    super.dispose();
  }

  /// 初始化动画控制器
  void _initializeAnimations() {
    _controlCenterAnimationController = AnimationController(
      duration: const Duration(milliseconds: 400),
      vsync: this,
    );
    _controlCenterFadeAnimation = CurvedAnimation(
      parent: _controlCenterAnimationController!,
      curve: Curves.easeInOut,
    );
  }

  /// 设置监听器
  void _setupListeners() {
    PlayerService().addListener(_onPlayerStateChanged);
    PlayerService().positionNotifier.addListener(_onPositionChanged);
    LyricStyleService().addListener(_onLyricStyleChanged);
    ExperienceProfileService().addListener(_onExperienceProfileChanged);
  }

  /// 移除监听器
  void _removeListeners() {
    PlayerService().removeListener(_onPlayerStateChanged);
    PlayerService().positionNotifier.removeListener(_onPositionChanged);
    LyricStyleService().removeListener(_onLyricStyleChanged);
    ExperienceProfileService().removeListener(_onExperienceProfileChanged);
  }

  void _onExperienceProfileChanged() {
    if (mounted) setState(() {});
  }

  void _onLyricStyleChanged() {
    if (mounted) {
      _checkAndForceOrientation();
      setState(() {});
    }
  }

  /// 释放动画控制器
  void _disposeAnimations() {
    _controlCenterAnimationController?.dispose();
  }

  /// 初始化数据
  void _initializeData() {
    // 延迟加载歌词，让路由动画先完成 (300ms 动画 + 50ms 缓冲)
    Future.delayed(const Duration(milliseconds: 350), () {
      if (!mounted) return;
      _syncLyricsFromSnapshot(force: true);
    });
  }

  /// 播放器状态变化回调（与桌面端保持一致的逻辑）
  void _onPlayerStateChanged() {
    if (!mounted) return;
    _syncLyricsFromSnapshot();
  }

  /// 进度变化回调（高频，仅由 positionNotifier 触发）
  void _onPositionChanged() {
    if (!mounted) return;
    _updateCurrentLyric();
  }

  void _handleBackPressed() {
    _backCoordinator.handleBack(
      transientPanelVisible: _showControlCenter,
      closeTransientPanel: _toggleControlCenter,
      popRoute: () => Navigator.of(context).pop(),
    );
  }

  void _syncLyricsFromSnapshot({bool force = false}) {
    final player = PlayerService();
    final currentTrack = player.currentTrack;
    final currentTrackId = currentTrack != null
        ? '${currentTrack.source.name}_${currentTrack.id}'
        : null;
    final snapshot = player.lyricSnapshot;
    final nextSignature = snapshot?.signature;
    final nextState = snapshot?.state ?? LyricLoadState.idle;

    if (!force &&
        currentTrackId == _lastTrackId &&
        nextSignature == _lastLyricsSignature &&
        nextState == _lyricState) {
      return;
    }

    if (currentTrackId != _lastTrackId) {
      StructuredLogService.event(
        'player_ui.lyric_track_changed',
        fields: {'previous_track_id': _lastTrackId, 'track_id': currentTrackId},
      );
    }

    _lastTrackId = currentTrackId;
    _lastLyricsSignature = nextSignature;
    _lyricState = nextState;
    _lyrics = snapshot == null ? [] : List<LyricLine>.from(snapshot.lines);
    _currentLyricIndex = -1;
    _updateCurrentLyric(notify: false);
    if (mounted) {
      setState(() {});
    }
  }

  /// 更新当前歌词
  void _updateCurrentLyric({bool notify = true}) {
    if (_lyrics.isEmpty) return;

    final newIndex = LyricParser.findCurrentLineIndex(
      _lyrics,
      PlayerService().position,
    );

    if (newIndex != _currentLyricIndex && newIndex >= 0 && mounted) {
      if (!notify) {
        _currentLyricIndex = newIndex;
        return;
      }
      setState(() {
        _currentLyricIndex = newIndex;
      });
    }
  }

  /// 强制刷新歌词（用于调试）
  void _forceRefreshLyrics() {
    if (PlayerService().currentTrack == null) return;
    StructuredLogService.event('player_ui.lyric_refresh');
    _lastLyricsSignature = null;
    _syncLyricsFromSnapshot(force: true);
  }

  /// 切换控制中心显示状态
  void _toggleControlCenter() {
    setState(() {
      _showControlCenter = !_showControlCenter;
      if (_showControlCenter) {
        _controlCenterAnimationController?.forward();
      } else {
        _controlCenterAnimationController?.reverse();
      }
    });
  }

  /// 构建流体云全屏布局（动态背景模式）
  /// 使用新的 MobilePlayerFluidCloudLayout，不再需要二级歌词页面
  Widget _buildAppleMusicStyleLayout(
    BuildContext context,
    BoxConstraints constraints,
  ) {
    return MobilePlayerFluidCloudLayout(
      lyrics: _lyrics,
      currentLyricIndex: _currentLyricIndex,
      showTranslation: true,
      lyricState: _lyricState,
      onBackPressed: _handleBackPressed,
      onPlaylistPressed: () =>
          MobilePlayerDialogs.showPlaylistBottomSheet(context),
    );
  }

  @override
  Widget build(BuildContext context) {
    final player = PlayerService();
    final song = player.currentSong;
    final track = player.currentTrack;

    // 播放器页面始终使用深色背景，状态栏和导航栏透明，图标为浅色
    const playerOverlayStyle = SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
      statusBarBrightness: Brightness.dark,
      systemNavigationBarColor: Colors.transparent,
      systemNavigationBarIconBrightness: Brightness.light,
      systemNavigationBarDividerColor: Colors.transparent,
    );

    if (song == null && track == null) {
      return AnnotatedRegion<SystemUiOverlayStyle>(
        value: playerOverlayStyle,
        child: Scaffold(
          backgroundColor: Colors.transparent,
          appBar: AppBar(
            backgroundColor: Colors.transparent,
            elevation: 0,
            systemOverlayStyle: playerOverlayStyle,
          ),
          body: const Center(
            child: Text(
              '暂无播放内容',
              style: TextStyle(color: Colors.white70, fontSize: 16),
            ),
          ),
        ),
      );
    }

    // 构建主要内容
    final lyricStyleService = LyricStyleService();
    final lyricState = _lyricState;
    // 流体云布局条件：全屏播放器样式设置为流体云（优先级最高）
    final useFluidCloudLayout =
        lyricStyleService.currentStyle == LyricStyle.fluidCloud;

    // 动态处理状态栏：如果是沉浸模式，或者在流体云样式下的横屏，则隐藏状态栏
    final isImmersive = lyricStyleService.currentStyle == LyricStyle.immersive;
    final isLandscape =
        MediaQuery.of(context).orientation == Orientation.landscape;
    final experiencePolicy = ExperienceProfileService().policy(
      width: MediaQuery.of(context).size.width,
      height: MediaQuery.of(context).size.height,
    );

    if (isImmersive || (useFluidCloudLayout && isLandscape)) {
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    } else {
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    }

    final scaffoldWidget = AnnotatedRegion<SystemUiOverlayStyle>(
      value: playerOverlayStyle,
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: Stack(
          children: [
            // 沉浸模式布局：复用桌面端组件
            if (lyricStyleService.currentStyle == LyricStyle.immersive)
              PlayerImmersiveLayout(
                lyrics: _lyrics,
                currentLyricIndex: _currentLyricIndex,
                showTranslation: _showTranslation,
                lyricState: lyricState,
                isMaximized: true,
                uiScale: experiencePolicy.mobileImmersiveScale,
                carMode: experiencePolicy.profile == ExperienceProfile.car,
                reducedEffects: experiencePolicy.reducedEffects,
                onBackPressed: _handleBackPressed,
                onMorePressed: () => MobilePlayerSettingsSheet.show(context),
                onPlaylistPressed: () =>
                    MobilePlayerDialogs.showPlaylistBottomSheet(context),
                onVolumeControlPressed: _toggleControlCenter,
              )
            // 流体云布局模式：完全接管背景和 Safe Area
            else if (useFluidCloudLayout)
              experiencePolicy.usesWidePlayer
                  ? PlayerFluidCloudLayout(
                      lyrics: _lyrics,
                      currentLyricIndex: _currentLyricIndex,
                      showTranslation: _showTranslation,
                      lyricState: lyricState,
                      isMaximized: true,
                      onBackPressed: _handleBackPressed,
                      onPlaylistPressed: () =>
                          MobilePlayerDialogs.showPlaylistBottomSheet(context),
                      onVolumeControlPressed: () {
                        // 移动端通过系统按键控制音量，内部 Slider 会直接调用 PlayerService().setVolume
                      },
                      onSleepTimerPressed: () =>
                          MobilePlayerDialogs.showSleepTimer(context),
                      onTranslationToggle: () =>
                          setState(() => _showTranslation = !_showTranslation),
                      leftPanelScale: 0.75, // 缩小左侧区域
                    )
                  : _buildAppleMusicStyleLayout(context, const BoxConstraints())
            else ...[
              // 标准布局模式：原有背景 + Safe Area
              const MobilePlayerBackground(),
              SafeArea(
                child: MobilePlayerClassicLayout(
                  lyrics: _lyrics,
                  currentLyricIndex: _currentLyricIndex,
                  lyricState: lyricState,
                  onBackPressed: _handleBackPressed,
                  onPlaylistPressed: () =>
                      MobilePlayerDialogs.showPlaylistBottomSheet(context),
                ),
              ),
            ],

            // 控制中心面板
            MobilePlayerControlCenter(
              isVisible: _showControlCenter,
              fadeAnimation: _controlCenterFadeAnimation,
              onClose: _toggleControlCenter,
            ),
          ],
        ),
      ),
    );

    // Windows 平台：添加圆角边框
    final backAwareWidget = PopScope(
      canPop: !_showControlCenter,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) _handleBackPressed();
      },
      child: scaffoldWidget,
    );

    if (Platform.isWindows) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: backAwareWidget,
      );
    }

    return backAwareWidget;
  }
}
