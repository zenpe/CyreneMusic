import 'dart:io';
import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';
import 'package:flutter_acrylic/flutter_acrylic.dart';
import '../services/player_service.dart';
import '../services/layout_preference_service.dart';
import '../services/lyric_style_service.dart';
import '../utils/theme_manager.dart';
import '../models/lyric_line.dart';
import '../utils/lyric_parser.dart';
import 'mobile_player_page.dart';
import 'player_components/player_window_controls.dart';
import 'player_components/player_background.dart';
import 'player_components/player_song_info.dart';
import 'player_components/player_karaoke_lyrics_panel.dart';
import 'player_components/player_fluid_cloud_lyrics_panel.dart';
import 'player_components/player_fluid_cloud_layout.dart'; // 导入新布局
import 'player_components/player_immersive_layout.dart'; // 导入沉浸样式布局
import 'player_components/player_controls.dart';
import 'player_components/player_playlist_panel.dart';
import 'player_components/player_control_center.dart';
import 'player_components/player_dialogs.dart';

/// 全屏播放器页面（重构版本）
/// 根据平台自动选择布局，现在使用组件化架构
class PlayerPage extends StatefulWidget {
  const PlayerPage({super.key});

  @override
  State<PlayerPage> createState() => _PlayerPageState();
}

class _PlayerPageState extends State<PlayerPage> with WindowListener, TickerProviderStateMixin {
  // 歌词相关
  List<LyricLine> _lyrics = [];
  int _currentLyricIndex = -1;
  LyricLoadState _lyricState = LyricLoadState.idle;
  String? _lastTrackId;
  String? _lastLyricsSignature;
  
  // UI 状态
  bool _isMaximized = false;
  bool _showPlaylist = false;
  bool _showTranslation = true;
  bool _showControlCenter = false;
  
  // 动画控制器
  AnimationController? _playlistAnimationController;
  Animation<Offset>? _playlistSlideAnimation;
  AnimationController? _controlCenterAnimationController;
  Animation<double>? _controlCenterFadeAnimation;

  @override
  void initState() {
    super.initState();
    _initializeAnimations();
    _setupListeners();
    _initializeData();
  }

  @override
  void dispose() {
    _disposeAnimations();
    _removeListeners();
    super.dispose();
  }

  /// 初始化动画控制器
  void _initializeAnimations() {
    // 播放列表动画
    _playlistAnimationController = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );
    _playlistSlideAnimation = Tween<Offset>(
      begin: const Offset(1.0, 0.0),
      end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: _playlistAnimationController!,
      curve: Curves.easeInOut,
    ));
    
    // 控制中心动画
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
    LyricStyleService().addListener(_onLyricStyleChanged);
    
    if (Platform.isWindows) {
      LayoutPreferenceService().addListener(_onLayoutModeChanged);
      PlayerService().positionNotifier.addListener(_onPositionChanged);
      windowManager.addListener(this);
      _checkMaximizedState();
    }
  }

  /// 移除监听器
  void _removeListeners() {
    PlayerService().removeListener(_onPlayerStateChanged);
    LyricStyleService().removeListener(_onLyricStyleChanged);
    
    if (Platform.isWindows) {
      LayoutPreferenceService().removeListener(_onLayoutModeChanged);
      PlayerService().positionNotifier.removeListener(_onPositionChanged);
      windowManager.removeListener(this);
    }
  }

  /// 释放动画控制器
  void _disposeAnimations() {
    _playlistAnimationController?.dispose();
    _controlCenterAnimationController?.dispose();
  }

  /// 初始化数据
  void _initializeData() {
    LyricStyleService().initialize();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _syncLyricsFromSnapshot(force: true);
    });
  }

  /// 检查窗口是否最大化
  Future<void> _checkMaximizedState() async {
    if (Platform.isWindows) {
      final isMaximized = await windowManager.isMaximized();
      if (mounted) {
        setState(() {
          _isMaximized = isMaximized;
        });
      }
    }
  }

  @override
  void onWindowMaximize() {
    setState(() {
      _isMaximized = true;
    });
  }

  @override
  void onWindowUnmaximize() {
    setState(() {
      _isMaximized = false;
    });
  }

  /// 布局模式变化回调
  void _onLayoutModeChanged() {
    if (mounted) {
      setState(() {
        print('🖥️ [PlayerPage] 布局模式已变化，刷新播放器页面');
      });
    }
  }

  /// 歌词样式变化回调
  void _onLyricStyleChanged() {
    if (mounted) {
      setState(() {
        print('🎤 [PlayerPage] 歌词样式已变化，刷新歌词面板');
      });
    }
  }

  /// 播放进度变化回调
  void _onPositionChanged() {
    if (!mounted) return;
    _updateCurrentLyric();
  }

  /// 播放器状态变化回调
  void _onPlayerStateChanged() {
    if (!mounted) return;
    _syncLyricsFromSnapshot();
  }

  /// 切换播放列表显示状态
  void _togglePlaylist() {
    setState(() {
      _showPlaylist = !_showPlaylist;
      if (_showPlaylist) {
        _playlistAnimationController?.forward();
      } else {
        _playlistAnimationController?.reverse();
      }
    });
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

  /// 切换译文显示
  void _toggleTranslation() {
    setState(() {
      _showTranslation = !_showTranslation;
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(_showTranslation ? '已显示译文' : '已隐藏译文'),
        duration: const Duration(seconds: 1),
      ),
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
      print('🎵 [PlayerPage] 检测到歌曲切换，刷新歌词快照');
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

  /// 根据样式选择构建歌词面板
  Widget _buildLyricPanel() {
    final lyricStyle = LyricStyleService().currentStyle;
    final lyricState = _lyricState;
    
    switch (lyricStyle) {
      case LyricStyle.defaultStyle:
        return PlayerKaraokeLyricsPanel(
          lyrics: _lyrics,
          currentLyricIndex: _currentLyricIndex,
          showTranslation: _showTranslation,
          lyricState: lyricState,
        );
      
      case LyricStyle.fluidCloud:
        return PlayerFluidCloudLyricsPanel(
          lyrics: _lyrics,
          currentLyricIndex: _currentLyricIndex,
          showTranslation: _showTranslation,
          lyricState: lyricState,
        );

      case LyricStyle.immersive:
        // 在沉浸模式下，歌词面板已集成在布局中或由布局单独处理
        // 这里返回空展示，真正的歌词显示逻辑在 PlayerImmersiveLayout 中
        return const SizedBox.shrink();
    }
  }

  @override
  Widget build(BuildContext context) {
    // 移动平台使用专门的移动端播放器布局
    if (Platform.isAndroid || Platform.isIOS) {
      return const MobilePlayerPage();
    }
    
    // Windows 平台：如果启用了移动布局模式，也使用移动端播放器布局
    if (Platform.isWindows && LayoutPreferenceService().isMobileLayout) {
      return const MobilePlayerPage();
    }
    
    // 桌面平台使用组件化的桌面布局
    final player = PlayerService();
    final song = player.currentSong;
    final track = player.currentTrack;
    final lyricState = _lyricState;

    if (song == null && track == null) {
      return Scaffold(
        backgroundColor: Colors.black,
        body: const Center(
          child: Text(
            '暂无播放内容',
            style: TextStyle(color: Colors.white),
          ),
        ),
      );
    }

    // 判断是否需要圆角裁剪（与主窗口逻辑保持一致）
    final effectEnabled = Platform.isWindows && ThemeManager().windowEffect != WindowEffect.disabled;
    final borderRadius = (_isMaximized || effectEnabled) ? BorderRadius.zero : BorderRadius.circular(12);
    
    Widget content = Stack(
          children: [
            // 主要内容区域 (根据样式切换)
            if (LyricStyleService().currentStyle == LyricStyle.fluidCloud)
              PlayerFluidCloudLayout(
                lyrics: _lyrics,
                currentLyricIndex: _currentLyricIndex,
                showTranslation: _showTranslation,
                lyricState: lyricState,
                isMaximized: _isMaximized,
                onBackPressed: () => Navigator.pop(context),
                onPlaylistPressed: _togglePlaylist,
                onVolumeControlPressed: _toggleControlCenter,
                onSleepTimerPressed: () => PlayerDialogs.showSleepTimer(context),
                onTranslationToggle: _toggleTranslation,
              )
            else if (LyricStyleService().currentStyle == LyricStyle.immersive)
              PlayerImmersiveLayout(
                lyrics: _lyrics,
                currentLyricIndex: _currentLyricIndex,
                showTranslation: _showTranslation,
                lyricState: lyricState,
                isMaximized: _isMaximized,
                onBackPressed: () => Navigator.pop(context),
                onPlaylistPressed: _togglePlaylist,
                onVolumeControlPressed: _toggleControlCenter,
                onSleepTimerPressed: () => PlayerDialogs.showSleepTimer(context),
                onTranslationToggle: _toggleTranslation,
              )
            else
              Stack(
                children: [
                  // 背景层
                  const PlayerBackground(),
                  
                  // 主要内容区域
                  SafeArea(
                    child: Column(
                      children: [
                        // 顶部窗口控制
                        PlayerWindowControls(
                          isMaximized: _isMaximized,
                          onBackPressed: () => Navigator.pop(context),
                          onPlaylistPressed: _togglePlaylist,
                        ),
                        
                        // 左右分栏内容区域
                        Expanded(
                          child: Row(
                            children: [
                              // 左侧：歌曲信息
                              Expanded(
                                flex: 5,
                                child: const PlayerSongInfo(),
                              ),
                              
                              // 右侧：歌词
                              Expanded(
                                flex: 4,
                                child: _buildLyricPanel(),
                              ),
                            ],
                          ),
                        ),
                        
                        // 底部控制区域
                        AnimatedBuilder(
                          animation: PlayerService(),
                          builder: (context, child) {
                            return PlayerControls(
                              player: PlayerService(),
                              onVolumeControlPressed: _toggleControlCenter,
                              onPlaylistPressed: _togglePlaylist,
                              onSleepTimerPressed: () => PlayerDialogs.showSleepTimer(context),
                              onAddToPlaylistPressed: (track) => PlayerDialogs.showAddToPlaylist(context, track),
                              lyrics: _lyrics,
                              showTranslation: _showTranslation,
                              onTranslationToggle: _toggleTranslation,
                            );
                          },
                        ),
                      ],
                    ),
                  ),
                ],
              ),

            // 播放列表面板（带遮罩）
            if (_showPlaylist) ...[
              // 背景遮罩
              GestureDetector(
                onTap: _togglePlaylist,
                child: Container(
                  color: Colors.black.withOpacity(0.3),
                ),
              ),
              // 播放列表内容
              PlayerPlaylistPanel(
                isVisible: _showPlaylist,
                slideAnimation: _playlistSlideAnimation,
                onClose: _togglePlaylist,
              ),
            ],
            
            // 控制中心面板
            PlayerControlCenter(
              isVisible: _showControlCenter,
              fadeAnimation: _controlCenterFadeAnimation,
              onClose: _toggleControlCenter,
            ),
          ],
        );
    
    // 仅在禁用窗口效果时应用圆角裁剪（与主窗口逻辑一致）
    if (!effectEnabled) {
      content = ClipRRect(
        borderRadius: borderRadius,
        child: content,
      );
    }
    
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: content,
    );
  }
}
