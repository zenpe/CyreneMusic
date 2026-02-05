import 'dart:io';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:fluent_ui/fluent_ui.dart' as fluent;
import 'package:bitsdojo_window/bitsdojo_window.dart';
import 'package:window_manager/window_manager.dart';
import '../../services/sleep_timer_service.dart';
import '../../services/playback_mode_service.dart';
import '../../services/download_service.dart';
import '../../services/notification_service.dart';
import '../../services/lyric_style_service.dart';
import '../../services/lyric_font_service.dart';
import '../../services/player_background_service.dart';
import '../../services/mini_player_window_service.dart';
import '../../utils/theme_manager.dart';
import '../../models/track.dart';
import '../../models/song_detail.dart';
import '../settings_page/player_background_dialog.dart';

/// 播放器窗口控制组件
/// 包含可拖动顶部栏和窗口控制按钮
class PlayerWindowControls extends StatelessWidget {
  final bool isMaximized;
  final VoidCallback onBackPressed;
  final VoidCallback? onPlaylistPressed;
  final VoidCallback? onSleepTimerPressed;
  final VoidCallback? onPlaybackModePressed;
  // 译文按钮相关
  final bool showTranslationButton;
  final bool showTranslation;
  final VoidCallback? onTranslationToggle;
  // 下载按钮相关
  final Track? currentTrack;
  final SongDetail? currentSong;

  // 顶部切换按钮相关
  final bool isLyricsActive;
  final bool isQueueActive;
  final bool isWikiActive;
  final VoidCallback? onLyricsToggle;
  final VoidCallback? onQueueToggle;
  final VoidCallback? onWikiToggle;
  final bool isTabletMode;
  final VoidCallback? onMorePressed;

  // 胶囊拖动回调
  final void Function(DragUpdateDetails)? onCapsuleDragUpdate;
  final void Function(DragEndDetails)? onCapsuleDragEnd;

  const PlayerWindowControls({
    super.key,
    required this.isMaximized,
    required this.onBackPressed,
    this.onPlaylistPressed,
    this.onSleepTimerPressed,
    this.onPlaybackModePressed,
    this.showTranslationButton = false,
    this.showTranslation = false,
    this.onTranslationToggle,
    this.currentTrack,
    this.currentSong,
    this.isLyricsActive = false,
    this.isQueueActive = false,
    this.isWikiActive = false,
    this.onLyricsToggle,
    this.onQueueToggle,
    this.onWikiToggle,
    this.isTabletMode = false,
    this.onMorePressed,
    this.onCapsuleDragUpdate,
    this.onCapsuleDragEnd,
  });

  @override
  Widget build(BuildContext context) {
    // Windows 平台使用可拖动区域
    if (Platform.isWindows) {
      return SizedBox(
        height: 56,
        child: Stack(
          children: [
            // 可拖动区域（整个顶部）
            Positioned.fill(
              child: MoveWindow(
                child: Container(
                  color: Colors.transparent,
                ),
              ),
            ),
            // 左侧：返回按钮 + 更多按钮
            Positioned(
              left: 8,
              top: 0,
              bottom: 0,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // 返回按钮
                  IconButton(
                    icon: const Icon(Icons.keyboard_arrow_down, size: 32),
                    color: Colors.white,
                    onPressed: onBackPressed,
                    tooltip: '返回',
                  ),
                  const SizedBox(width: 4),
                  // 更多按钮（带悬浮菜单）
                  _MoreMenuButton(
                    onPlaylistPressed: onPlaylistPressed,
                    onSleepTimerPressed: onSleepTimerPressed,
                    onPlaybackModePressed: onPlaybackModePressed,
                  ),
                  // 译文按钮（只在非中文歌词且有翻译时显示）
                  if (showTranslationButton)
                    _TranslationButton(
                      showTranslation: showTranslation,
                      onToggle: onTranslationToggle,
                    ),
                  // 下载按钮
                  if (currentTrack != null && currentSong != null)
                    _DownloadButton(
                      track: currentTrack!,
                      song: currentSong!,
                    ),
                  // 迷你播放器按钮
                  _MiniPlayerButton(),
                  
                  // 布局快捷切换按钮
                  _LayoutToggleButton(),
                  
                  const SizedBox(width: 8),

                  // 歌曲百科按钮 (Apple Music 风格)
                  if (onWikiToggle != null)
                    _TopBarButton(
                      icon: CupertinoIcons.info_circle,
                      isActive: isWikiActive,
                      onPressed: onWikiToggle!,
                      tooltip: '歌曲信息',
                    ),
                  
                  // 待播清单按钮 (Apple Music 风格)
                  if (onQueueToggle != null)
                    _TopBarButton(
                      icon: Icons.format_list_bulleted_rounded,
                      isActive: isQueueActive,
                      onPressed: onQueueToggle!,
                      tooltip: '待播清单',
                    ),
                    
                  // 歌词按钮 (Apple Music 风格)
                  if (onLyricsToggle != null)
                    _TopBarButton(
                      icon: Icons.lyrics_rounded,
                      isActive: isLyricsActive,
                      onPressed: onLyricsToggle!,
                      tooltip: '歌词',
                    ),
                ],
              ),
            ),
            // 右侧：窗口控制按钮
            Positioned(
              right: 0,
              top: 0,
              bottom: 0,
              child: _buildWindowButtons(),
            ),
          ],
        ),
      );
    } else {
      // 其他平台（如移动端）
      return Stack(
        alignment: Alignment.topCenter,
        children: [
          Container(
            height: 56,
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Row(
              children: [
                if (isTabletMode) ...[
                  // 平板模式下：仅显示更多按钮
                  IconButton(
                    icon: const Icon(Icons.more_vert_rounded, size: 28),
                    color: Colors.white,
                    onPressed: onMorePressed,
                    tooltip: '更多设置',
                  ),
                ] else ...[
                  // 返回按钮
                  IconButton(
                    icon: const Icon(Icons.keyboard_arrow_down, size: 32),
                    color: Colors.white,
                    onPressed: onBackPressed,
                    tooltip: '返回',
                  ),
                  const SizedBox(width: 4),
                  // 更多按钮
                  _MoreMenuButton(
                    onPlaylistPressed: onPlaylistPressed,
                    onSleepTimerPressed: onSleepTimerPressed,
                    onPlaybackModePressed: onPlaybackModePressed,
                  ),
                  // 译文按钮
                  if (showTranslationButton)
                    _TranslationButton(
                      showTranslation: showTranslation,
                      onToggle: onTranslationToggle,
                    ),
                  // 下载按钮
                  if (currentTrack != null && currentSong != null)
                    _DownloadButton(
                      track: currentTrack!,
                      song: currentSong!,
                    ),
                ],
                
                const Spacer(),
                
                // 布局快捷切换按钮
                _LayoutToggleButton(),
                
                // 歌曲百科按钮
                if (onWikiToggle != null)
                  _TopBarButton(
                    icon: CupertinoIcons.info_circle,
                    isActive: isWikiActive,
                    onPressed: onWikiToggle!,
                    tooltip: '歌曲信息',
                  ),
                
                // 待播清单按钮
                if (onQueueToggle != null)
                  _TopBarButton(
                    icon: Icons.format_list_bulleted_rounded,
                    isActive: isQueueActive,
                    onPressed: onQueueToggle!,
                    tooltip: '待播清单',
                  ),
                
                // 歌词按钮
                if (onLyricsToggle != null)
                  _TopBarButton(
                    icon: Icons.lyrics_rounded,
                    isActive: isLyricsActive,
                    onPressed: onLyricsToggle!,
                    tooltip: '歌词',
                  ),
              ],
            ),
          ),
          
          // 平板模式顶部拖动胶囊条
          if (isTabletMode)
            Positioned(
              top: 24, // 下移以避免误触状态栏
              child: GestureDetector(
                onVerticalDragUpdate: onCapsuleDragUpdate,
                onVerticalDragEnd: (details) {
                  if (onCapsuleDragEnd != null) {
                    onCapsuleDragEnd!(details);
                  } else {
                     // 兼容旧逻辑：仅支持快速下滑关闭
                    if (details.primaryVelocity != null && details.primaryVelocity! > 300) {
                      onBackPressed();
                    }
                  }
                },
                child: Container(
                  width: 48,
                  height: 5, // 胶囊高度
                  padding: const EdgeInsets.symmetric(vertical: 10), // 增加垂直热区
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.3),
                    borderRadius: BorderRadius.circular(100),
                  ),
                ),
              ),
            ),
        ],
      );
    }
  }

  /// 构建窗口控制按钮（最小化、最大化、关闭）
  Widget _buildWindowButtons() {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _buildWindowButton(
          icon: Icons.remove,
          onPressed: () => appWindow.minimize(),
          tooltip: '最小化',
        ),
        _buildWindowButton(
          icon: isMaximized ? Icons.fullscreen_exit : Icons.crop_square,
          onPressed: () => appWindow.maximizeOrRestore(),
          tooltip: isMaximized ? '还原' : '最大化',
        ),
        _buildWindowButton(
          icon: Icons.close_rounded,
          onPressed: () => windowManager.close(),
          tooltip: '关闭',
          isClose: true,
        ),
      ],
    );
  }

  /// 构建单个窗口按钮
  Widget _buildWindowButton({
    required IconData icon,
    required VoidCallback onPressed,
    required String tooltip,
    bool isClose = false,
  }) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: Tooltip(
        message: tooltip,
        child: InkWell(
          onTap: onPressed,
          hoverColor: isClose ? Colors.red : Colors.white.withOpacity(0.1),
          child: Container(
            width: 48,
            height: 56,
            alignment: Alignment.center,
            child: Icon(
              icon,
              size: 18,
              color: Colors.white,
            ),
          ),
        ),
      ),
    );
  }
}

/// 更多菜单按钮（带悬浮弹出框）
class _MoreMenuButton extends StatefulWidget {
  final VoidCallback? onPlaylistPressed;
  final VoidCallback? onSleepTimerPressed;
  final VoidCallback? onPlaybackModePressed;

  const _MoreMenuButton({
    this.onPlaylistPressed,
    this.onSleepTimerPressed,
    this.onPlaybackModePressed,
  });

  @override
  State<_MoreMenuButton> createState() => _MoreMenuButtonState();
}

class _MoreMenuButtonState extends State<_MoreMenuButton> {
  final LayerLink _layerLink = LayerLink();
  OverlayEntry? _overlayEntry;
  bool _isHovering = false;
  bool _isMenuHovering = false;

  /// 判断菜单是否使用深色背景
  /// 由于菜单使用深色遮罩+白色文字设计，始终返回 true
  bool _isPlayerBackgroundDark() {
    return true;
  }

  void _showMenu() {
    if (_overlayEntry != null) return;
    
    _overlayEntry = OverlayEntry(
      builder: (context) => Positioned(
        width: 260,  // 增加宽度
        child: CompositedTransformFollower(
          link: _layerLink,
          targetAnchor: Alignment.bottomLeft,
          followerAnchor: Alignment.topLeft,
          offset: const Offset(0, 8),  // 增加间距
          child: MouseRegion(
            onEnter: (_) {
              _isMenuHovering = true;
            },
            onExit: (_) {
              _isMenuHovering = false;
              _hideMenuDelayed();
            },
            child: TweenAnimationBuilder<double>(
              tween: Tween(begin: 0.0, end: 1.0),
              duration: const Duration(milliseconds: 200),
              curve: Curves.easeOutCubic,
              builder: (context, value, child) {
                return Transform.scale(
                  scale: 0.95 + (0.05 * value),
                  alignment: Alignment.topLeft,
                  child: Opacity(
                    opacity: value,
                    child: child,
                  ),
                );
              },
              child: Material(
                color: Colors.transparent,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(16),  // 更圆润的边角
                  child: BackdropFilter(
                    filter: ImageFilter.blur(sigmaX: 40, sigmaY: 40),
                    child: Container(
                      // 深灰色半透明遮罩，确保白色文字可读
                      // 无论背景是深色还是浅色，菜单始终使用深色毛玻璃效果 + 白色文字
                      decoration: BoxDecoration(
                        color: Colors.black.withOpacity(0.45),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: Colors.white.withOpacity(0.15),
                          width: 1,
                        ),
                      ),
                      child: _buildMenuContent(),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    
    Overlay.of(context).insert(_overlayEntry!);
  }

  Widget _buildMenuContent() {
    return AnimatedBuilder(
      animation: Listenable.merge([SleepTimerService(), PlaybackModeService(), LyricStyleService(), LyricFontService()]),
      builder: (context, _) {
        final sleepTimer = SleepTimerService();
        final playbackMode = PlaybackModeService();
        final lyricStyle = LyricStyleService();
        final lyricFont = LyricFontService();
        
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ======= 播放列表 =======
              if (widget.onPlaylistPressed != null) ...[
                _buildMenuItem(
                  icon: Icons.queue_music_rounded,
                  label: '播放列表',
                  iconColor: Colors.blue[300],
                  onTap: () {
                    _hideMenu();
                    widget.onPlaylistPressed!();
                  },
                ),
                _buildSectionDivider(),
              ],
              
              // ======= 外观设置分组 =======
              _buildSectionTitle('外观'),
              
              // 播放器主题 (循环切换)
              _buildMenuItem(
                icon: lyricStyle.currentStyle == LyricStyle.immersive 
                    ? Icons.fullscreen_rounded 
                    : Icons.water_drop_rounded,
                label: lyricStyle.currentStyle == LyricStyle.immersive
                    ? '沉浸主题'
                    : '流体云主题',
                subtitle: '切换播放器风格',
                iconColor: lyricStyle.currentStyle == LyricStyle.immersive
                    ? Colors.amber[300]
                    : Colors.cyan[300],
                trailing: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    lyricStyle.currentStyle == LyricStyle.immersive ? '沉浸' : '流体',
                    style: const TextStyle(color: Colors.white, fontSize: 10),
                  ),
                ),
                onTap: () {
                  // 循环切换样式：仅在流体云和沉浸模式间切换 (桌面端隐藏经典模式)
                  LyricStyle nextStyle = lyricStyle.currentStyle == LyricStyle.immersive 
                      ? LyricStyle.fluidCloud 
                      : LyricStyle.immersive;
                  lyricStyle.setStyle(nextStyle);
                  _overlayEntry?.markNeedsBuild();
                },
              ),
              
              // 播放器背景
              _buildMenuItem(
                icon: Icons.photo_rounded,
                label: '播放器背景',
                subtitle: PlayerBackgroundService().getBackgroundTypeName(),
                iconColor: Colors.orange[300],
                trailing: const Icon(
                  Icons.chevron_right_rounded,
                  color: Colors.white38,
                  size: 20,
                ),
                onTap: () {
                  _hideMenu();
                  _showBackgroundDialog(context);
                },
              ),
              
              // 歌词字体
              _buildMenuItem(
                icon: Icons.text_fields_rounded,
                label: '歌词字体',
                subtitle: lyricFont.currentFontName,
                iconColor: Colors.pink[300],
                trailing: const Icon(
                  Icons.chevron_right_rounded,
                  color: Colors.white38,
                  size: 20,
                ),
                onTap: () {
                  _hideMenu();
                  _showFontPicker(context);
                },
              ),

              // 歌词对齐 (新增)
              _buildMenuItem(
                icon: lyricStyle.currentAlignment == LyricAlignment.center 
                    ? Icons.format_align_center_rounded 
                    : Icons.vertical_align_top_rounded,
                label: '歌词对齐',
                subtitle: lyricStyle.currentAlignment == LyricAlignment.center 
                    ? '居中对齐' 
                    : '顶部对齐',
                iconColor: Colors.teal[300],
                trailing: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: Colors.teal.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: Colors.teal.withOpacity(0.3),
                      width: 1,
                    ),
                  ),
                  child: Text(
                    lyricStyle.currentAlignment == LyricAlignment.center ? '居中' : '顶部',
                    style: TextStyle(
                      color: Colors.teal[300],
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      fontFamily: 'Microsoft YaHei',
                    ),
                  ),
                ),
                onTap: () {
                  final newAlignment = lyricStyle.currentAlignment == LyricAlignment.center 
                      ? LyricAlignment.top 
                      : LyricAlignment.center;
                  lyricStyle.setAlignment(newAlignment);
                  _overlayEntry?.markNeedsBuild();
                },
              ),
              
              _buildSectionDivider(),
              
              // ======= 播放控制分组 =======
              _buildSectionTitle('播放'),
              
              // 播放模式
              _buildMenuItem(
                icon: _getPlaybackModeIcon(playbackMode.currentMode),
                label: '播放模式',
                subtitle: playbackMode.getModeName(),
                iconColor: Colors.green[300],
                trailing: _buildModeIndicator(playbackMode.currentMode),
                onTap: () {
                  playbackMode.toggleMode();
                  _overlayEntry?.markNeedsBuild();
                },
              ),
              
              // 睡眠定时器
              _buildMenuItem(
                icon: sleepTimer.isActive ? Icons.bedtime_rounded : Icons.bedtime_outlined,
                label: '睡眠定时器',
                subtitle: sleepTimer.isActive 
                    ? '剩余 ${sleepTimer.remainingTimeString}' 
                    : '设置定时关闭',
                iconColor: sleepTimer.isActive ? Colors.amber[300] : Colors.grey[400],
                trailing: sleepTimer.isActive 
                    ? Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: Colors.amber.withOpacity(0.2),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(
                          '运行中',
                          style: TextStyle(
                            color: Colors.amber[300],
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            fontFamily: 'Microsoft YaHei',
                          ),
                        ),
                      )
                    : null,
                onTap: () {
                  _hideMenu();
                  if (widget.onSleepTimerPressed != null) {
                    widget.onSleepTimerPressed!();
                  }
                },
              ),

              _buildSectionDivider(),

              // ======= 歌词微调分组 =======
              _buildSectionTitle('歌词调节'),

              // 歌词大小
              _buildSliderMenuItem(
                icon: Icons.format_size_rounded,
                label: '歌词大小',
                value: lyricStyle.fontSize,
                min: 24.0,
                max: 48.0,
                divisions: 24,
                iconColor: Colors.indigo[300],
                onChanged: (v) => lyricStyle.setFontSize(v),
              ),

              // 歌词间距 (只在未开启自适应时支持手动调整)
              _buildSliderMenuItem(
                icon: Icons.format_line_spacing_rounded,
                label: '歌词间距',
                value: lyricStyle.lineHeight,
                min: 60.0,
                max: 180.0,
                divisions: 60,
                iconColor: Colors.blueGrey[300],
                enabled: !lyricStyle.autoLineHeight,
                onChanged: (v) => lyricStyle.setLineHeight(v),
                trailing: Tooltip(
                  message: lyricStyle.autoLineHeight ? '已开启自适应' : '手动调整',
                  child: IconButton(
                    icon: Icon(
                      lyricStyle.autoLineHeight ? Icons.auto_awesome_rounded : Icons.edit_note_rounded,
                      size: 16,
                      color: lyricStyle.autoLineHeight ? Colors.cyan[300] : Colors.white38,
                    ),
                    onPressed: () => lyricStyle.setAutoLineHeight(!lyricStyle.autoLineHeight),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                  ),
                ),
              ),

              // 歌词模糊度
              _buildSliderMenuItem(
                icon: Icons.blur_on_rounded,
                label: '渐隐模糊',
                value: lyricStyle.blurSigma,
                min: 0.0,
                max: 10.0,
                divisions: 20,
                iconColor: Colors.cyan[300],
                onChanged: (v) => lyricStyle.setBlurSigma(v),
              ),
            ],
          ),
        );
      },
    );
  }
  
  /// 构建分组标题
  Widget _buildSectionTitle(String title) {
    return Builder(
      builder: (context) {
        final isDark = _isPlayerBackgroundDark();
        final textColor = isDark ? Colors.white : Colors.black;
        
        return Padding(
          padding: const EdgeInsets.only(left: 16, right: 16, top: 4, bottom: 6),
          child: Text(
            title,
            style: TextStyle(
              color: textColor.withOpacity(0.4),
              fontSize: 11,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.5,
              fontFamily: 'Microsoft YaHei',
            ),
          ),
        );
      },
    );
  }
  
  /// 构建分隔线
  /// 构建分隔线
  Widget _buildSectionDivider() {
    return Builder(
      builder: (context) {
        final isDark = _isPlayerBackgroundDark();
        final lineColor = isDark ? Colors.white : Colors.black;
        
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          child: Container(
            height: 1,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  Colors.transparent,
                  lineColor.withOpacity(isDark ? 0.15 : 0.1),
                  lineColor.withOpacity(isDark ? 0.15 : 0.1),
                  Colors.transparent,
                ],
                stops: const [0.0, 0.2, 0.8, 1.0],
              ),
            ),
          ),
        );
      },
    );
  }
  
  /// 构建切换指示器
  /// 构建切换指示器
  Widget _buildSwitchIndicator(bool isOn) {
    return Builder(
      builder: (context) {
        final isDark = _isPlayerBackgroundDark();
        final baseColor = isDark ? Colors.white : Colors.black;
        
        return Container(
          width: 40,
          height: 22,
          decoration: BoxDecoration(
            color: isOn ? Colors.cyan.withOpacity(0.3) : baseColor.withOpacity(0.1),
            borderRadius: BorderRadius.circular(11),
            border: Border.all(
              color: isOn ? Colors.cyan.withOpacity(0.5) : baseColor.withOpacity(0.2),
              width: 1,
            ),
          ),
          child: AnimatedAlign(
            alignment: isOn ? Alignment.centerRight : Alignment.centerLeft,
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeInOut,
            child: Container(
              width: 16,
              height: 16,
              margin: const EdgeInsets.symmetric(horizontal: 2),
              decoration: BoxDecoration(
                color: isOn ? Colors.cyan[300] : baseColor.withOpacity(0.6),
                shape: BoxShape.circle,
                boxShadow: isOn ? [
                  BoxShadow(
                    color: Colors.cyan.withOpacity(0.4),
                    blurRadius: 4,
                  ),
                ] : null,
              ),
            ),
          ),
        );
      },
    );
  }
  
  /// 构建播放模式指示器
  Widget _buildModeIndicator(PlaybackMode mode) {
    final labels = {
      PlaybackMode.sequential: '顺序',
      PlaybackMode.repeatOne: '单曲',
      PlaybackMode.shuffle: '随机',
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: Colors.green.withOpacity(0.15),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: Colors.green.withOpacity(0.3),
          width: 1,
        ),
      ),
      child: Text(
        labels[mode] ?? '',
        style: TextStyle(
          color: Colors.green[300],
          fontSize: 11,
          fontWeight: FontWeight.w600,
          fontFamily: 'Microsoft YaHei',
        ),
      ),
    );
  }
  
  void _showBackgroundDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => PlayerBackgroundDialog(
        onChanged: () {
          // 背景设置变化后刷新
        },
      ),
    );
  }
  
  void _showFontPicker(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => _LyricFontPickerDialog(),
    );
  }

  IconData _getPlaybackModeIcon(PlaybackMode mode) {
    switch (mode) {
      case PlaybackMode.sequential:
        return Icons.repeat_rounded;
      case PlaybackMode.repeatOne:
        return Icons.repeat_one_rounded;
      case PlaybackMode.shuffle:
        return Icons.shuffle_rounded;
    }
  }

  void _hideMenu() {
    _overlayEntry?.remove();
    _overlayEntry = null;
  }

  void _hideMenuDelayed() {
    Future.delayed(const Duration(milliseconds: 100), () {
      if (!_isHovering && !_isMenuHovering) {
        _hideMenu();
      }
    });
  }

  Widget _buildSliderMenuItem({
    required IconData icon,
    required String label,
    required double value,
    required double min,
    required double max,
    required ValueChanged<double> onChanged,
    int? divisions,
    Color? iconColor,
    bool enabled = true,
    Widget? trailing,
  }) {
    return Builder(
      builder: (context) {
        final textColor = Colors.white;
        
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          margin: const EdgeInsets.symmetric(horizontal: 4),
          child: Opacity(
            opacity: enabled ? 1.0 : 0.5,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Container(
                      width: 28,
                      height: 28,
                      decoration: BoxDecoration(
                        color: (iconColor ?? textColor).withOpacity(0.12),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Icon(
                        icon,
                        color: iconColor ?? textColor.withOpacity(0.85),
                        size: 16,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        label,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                          fontFamily: 'Microsoft YaHei',
                        ),
                      ),
                    ),
                    if (trailing != null) ...[
                      trailing,
                      const SizedBox(width: 8),
                    ],
                    Text(
                      value.toStringAsFixed(1),
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.5),
                        fontSize: 11,
                        fontFamily: 'Consolas',
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                SliderTheme(
                  data: SliderThemeData(
                    trackHeight: 2,
                    thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
                    overlayShape: const RoundSliderOverlayShape(overlayRadius: 14),
                    activeTrackColor: (iconColor ?? Colors.white).withOpacity(0.8),
                    inactiveTrackColor: Colors.white.withOpacity(0.1),
                    thumbColor: Colors.white,
                  ),
                  child: SizedBox(
                    height: 24,
                    child: Slider(
                      value: value,
                      min: min,
                      max: max,
                      divisions: divisions,
                      onChanged: enabled ? onChanged : null,
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildMenuItem({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
    String? subtitle,
    Widget? trailing,
    Color? iconColor,
  }) {
    return Builder(
      builder: (context) {
        final isDark = _isPlayerBackgroundDark();
        final textColor = isDark ? Colors.white : Colors.black;
        final hoverColor = textColor.withOpacity(0.08);
        final splashColor = textColor.withOpacity(0.05);
        
        return Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onTap,
            hoverColor: hoverColor,
            splashColor: splashColor,
            borderRadius: BorderRadius.circular(8),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              margin: const EdgeInsets.symmetric(horizontal: 4),
              child: Row(
                children: [
                  // 图标容器（带圆角背景）
                  Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      color: (iconColor ?? textColor).withOpacity(0.12),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(
                      icon,
                      color: iconColor ?? textColor.withOpacity(0.85),
                      size: 18,
                    ),
                  ),
                  const SizedBox(width: 12),
                  // 标题和副标题
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          label,
                          style: TextStyle(
                            color: textColor,
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                            letterSpacing: -0.2,
                            fontFamily: 'Microsoft YaHei',
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                        if (subtitle != null) ...[
                          const SizedBox(height: 2),
                          Text(
                            subtitle,
                            style: TextStyle(
                              color: textColor.withOpacity(0.45),
                              fontSize: 11,
                              fontWeight: FontWeight.w400,
                              fontFamily: 'Microsoft YaHei',
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ],
                    ),
                  ),
                  if (trailing != null) ...[
                    const SizedBox(width: 8),
                    trailing,
                  ],
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  @override
  void dispose() {
    _hideMenu();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return CompositedTransformTarget(
      link: _layerLink,
      child: MouseRegion(
        onEnter: (_) {
          setState(() => _isHovering = true);
          _showMenu();
        },
        onExit: (_) {
          setState(() => _isHovering = false);
          _hideMenuDelayed();
        },
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: _isHovering ? Colors.white.withOpacity(0.1) : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.more_horiz,
                color: Colors.white.withOpacity(0.8),
                size: 24,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 译文按钮组件
class _TranslationButton extends StatelessWidget {
  final bool showTranslation;
  final VoidCallback? onToggle;

  const _TranslationButton({
    required this.showTranslation,
    this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: showTranslation ? '隐藏译文' : '显示译文',
      child: InkWell(
        onTap: onToggle,
        borderRadius: BorderRadius.circular(8),
        hoverColor: Colors.white.withOpacity(0.1),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              color: showTranslation ? Colors.white.withOpacity(0.2) : Colors.transparent,
              borderRadius: BorderRadius.circular(6),
              border: Border.all(
                color: Colors.white.withOpacity(0.3),
                width: 1,
              ),
            ),
            child: const Center(
              child: Text(
                '译',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 下载按钮组件
class _DownloadButton extends StatelessWidget {
  final Track track;
  final SongDetail song;

  const _DownloadButton({
    required this.track,
    required this.song,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: DownloadService(),
      builder: (context, child) {
        final downloadService = DownloadService();
        final isDownloading = downloadService.downloadTasks.containsKey(
          '${track.source.name}_${track.id}'
        );
        
        return Tooltip(
          message: isDownloading ? '下载中...' : '下载',
          child: InkWell(
            onTap: isDownloading ? null : () => _handleDownload(context),
            borderRadius: BorderRadius.circular(8),
            hoverColor: Colors.white.withOpacity(0.1),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Icon(
                isDownloading ? Icons.downloading_rounded : Icons.download_rounded,
                color: isDownloading ? Colors.white54 : Colors.white.withOpacity(0.8),
                size: 24,
              ),
            ),
          ),
        );
      },
    );
  }

  Future<void> _handleDownload(BuildContext context) async {
    try {
      // 检查是否已下载
      final isDownloaded = await DownloadService().isDownloaded(track);
      
      if (isDownloaded) {
        // 已下载，通过通知告知用户
        await NotificationService().showNotification(
          id: DateTime.now().millisecondsSinceEpoch % 100000,
          title: '已下载',
          body: '${track.name} 已存在于下载目录中',
        );
        return;
      }

      // 开始下载（下载完成后会自动发送通知）
      await DownloadService().downloadSong(
        track,
        song,
        onProgress: (progress) {
          // 下载进度会通过 DownloadService 的 notifyListeners 自动更新UI
        },
      );
    } catch (e) {
      // 下载失败，通过通知告知用户
      await NotificationService().showNotification(
        id: DateTime.now().millisecondsSinceEpoch % 100000,
        title: '下载失败',
        body: '${track.name}: $e',
      );
    }
  }
}

/// 歌词字体选择对话框（自适应主题）
class _LyricFontPickerDialog extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final themeManager = ThemeManager();
    
    // 根据主题选择不同的对话框样式
    if (themeManager.isFluentFramework) {
      return _buildFluentDialog(context);
    } else if (themeManager.isCupertinoFramework) {
      return _buildCupertinoDialog(context);
    }
    return _buildMaterialDialog(context);
  }
  
  // ========== Fluent UI 对话框 ==========
  Widget _buildFluentDialog(BuildContext context) {
    final fluentTheme = fluent.FluentTheme.of(context);
    
    return fluent.ContentDialog(
      title: const Row(
        children: [
          Icon(fluent.FluentIcons.font, size: 20),
          SizedBox(width: 8),
          Text('选择歌词字体'),
        ],
      ),
      constraints: const BoxConstraints(maxWidth: 400, maxHeight: 500),
      content: AnimatedBuilder(
        animation: LyricFontService(),
        builder: (context, _) {
          final fontService = LyricFontService();
          return ListView.builder(
            shrinkWrap: true,
            itemCount: LyricFontService.platformFonts.length,
            itemBuilder: (context, index) {
              final font = LyricFontService.platformFonts[index];
              final isSelected = fontService.fontType == 'preset' && 
                  fontService.presetFontId == font.id;
              
              return fluent.ListTile.selectable(
                selected: isSelected,
                onPressed: () async {
                  await fontService.setPresetFont(font.id);
                  if (context.mounted) Navigator.pop(context);
                },
                leading: Text(
                  '字',
                  style: TextStyle(
                    fontFamily: font.fontFamily,
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: fluentTheme.accentColor,
                  ),
                ),
                title: Text(
                  font.name,
                  style: TextStyle(fontFamily: font.fontFamily),
                ),
                subtitle: Text(font.description),
                trailing: isSelected 
                    ? Icon(fluent.FluentIcons.check_mark, 
                        color: fluentTheme.accentColor, size: 16)
                    : null,
              );
            },
          );
        },
      ),
      actions: [
        fluent.Button(
          child: const Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(fluent.FluentIcons.fabric_folder, size: 16),
              SizedBox(width: 8),
              Text('自定义字体...'),
            ],
          ),
          onPressed: () async {
            final success = await LyricFontService().pickAndLoadCustomFont();
            if (success && context.mounted) Navigator.pop(context);
          },
        ),
        fluent.FilledButton(
          child: const Text('关闭'),
          onPressed: () => Navigator.pop(context),
        ),
      ],
    );
  }
  
  // ========== Cupertino 对话框 ==========
  Widget _buildCupertinoDialog(BuildContext context) {
    return Material(
      type: MaterialType.transparency,
      child: CupertinoActionSheet(
        title: const Text('选择歌词字体'),
        message: const Text('选择一个字体来显示歌词'),
        actions: [
          ...LyricFontService.platformFonts.map((font) {
            final fontService = LyricFontService();
            final isSelected = fontService.fontType == 'preset' && 
                fontService.presetFontId == font.id;
            
            return CupertinoActionSheetAction(
              onPressed: () async {
                await fontService.setPresetFont(font.id);
                if (context.mounted) Navigator.pop(context);
              },
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (isSelected)
                    const Padding(
                      padding: EdgeInsets.only(right: 8),
                      child: Icon(CupertinoIcons.checkmark_alt, 
                          color: CupertinoColors.activeBlue, size: 18),
                    ),
                  Text(
                    font.name,
                    style: TextStyle(
                      fontFamily: font.fontFamily,
                      fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                      color: isSelected ? CupertinoColors.activeBlue : null,
                    ),
                  ),
                ],
              ),
            );
          }),
          CupertinoActionSheetAction(
            onPressed: () async {
              final success = await LyricFontService().pickAndLoadCustomFont();
              if (success && context.mounted) Navigator.pop(context);
            },
            child: const Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(CupertinoIcons.folder, size: 18),
                SizedBox(width: 8),
                Text('选择自定义字体...'),
              ],
            ),
          ),
        ],
        cancelButton: CupertinoActionSheetAction(
          isDestructiveAction: true,
          onPressed: () => Navigator.pop(context),
          child: const Text('取消'),
        ),
      ),
    );
  }
  
  // ========== Material 对话框 ==========
  Widget _buildMaterialDialog(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
      child: Container(
        width: 340,
        constraints: const BoxConstraints(maxHeight: 500),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // 标题栏
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 24, 24, 16),
              child: Row(
                children: [
                  Icon(Icons.font_download_rounded, 
                      color: colorScheme.primary, size: 24),
                  const SizedBox(width: 12),
                  Text(
                    '选择歌词字体',
                    style: theme.textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
            
            const Divider(height: 1),
            
            // 字体列表
            Flexible(
              child: AnimatedBuilder(
                animation: LyricFontService(),
                builder: (context, _) {
                  final fontService = LyricFontService();
                  return ListView.builder(
                    shrinkWrap: true,
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    itemCount: LyricFontService.platformFonts.length,
                    itemBuilder: (context, index) {
                      final font = LyricFontService.platformFonts[index];
                      final isSelected = fontService.fontType == 'preset' && 
                          fontService.presetFontId == font.id;
                      
                      return ListTile(
                        selected: isSelected,
                        selectedTileColor: colorScheme.primaryContainer.withOpacity(0.3),
                        leading: CircleAvatar(
                          backgroundColor: isSelected 
                              ? colorScheme.primary 
                              : colorScheme.surfaceContainerHighest,
                          child: Text(
                            '字',
                            style: TextStyle(
                              fontFamily: font.fontFamily,
                              color: isSelected 
                                  ? colorScheme.onPrimary 
                                  : colorScheme.onSurfaceVariant,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        title: Text(
                          font.name,
                          style: TextStyle(
                            fontFamily: font.fontFamily,
                            fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                          ),
                        ),
                        subtitle: Text(font.description),
                        trailing: isSelected 
                            ? Icon(Icons.check_circle, color: colorScheme.primary)
                            : null,
                        onTap: () async {
                          await fontService.setPresetFont(font.id);
                          if (context.mounted) Navigator.pop(context);
                        },
                      );
                    },
                  );
                },
              ),
            ),
            
            const Divider(height: 1),
            
            // 底部按钮
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  TextButton.icon(
                    onPressed: () async {
                      final success = await LyricFontService().pickAndLoadCustomFont();
                      if (success && context.mounted) Navigator.pop(context);
                    },
                    icon: const Icon(Icons.folder_open_rounded, size: 18),
                    label: const Text('自定义字体'),
                  ),
                  const Spacer(),
                  FilledButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('关闭'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 迷你播放器按钮
class _MiniPlayerButton extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: '迷你播放器',
      child: IconButton(
        icon: const Icon(Icons.picture_in_picture_alt_rounded, size: 20),
        color: Colors.white.withOpacity(0.9),
        onPressed: () {
          // 先关闭全屏播放器页面，然后切换到迷你模式
          Navigator.of(context).pop();
          MiniPlayerWindowService().enterMiniMode();
        },
      ),
    );
  }
}

/// 顶部栏专用切换按钮 (Lyrics/Queue)
class _TopBarButton extends StatelessWidget {
  final IconData icon;
  final bool isActive;
  final VoidCallback onPressed;
  final String tooltip;

  const _TopBarButton({
    required this.icon,
    required this.isActive,
    required this.onPressed,
    required this.tooltip,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: IconButton(
        icon: Icon(icon, size: 20),
        color: isActive ? Colors.white : Colors.white24,
        style: IconButton.styleFrom(
          backgroundColor: isActive ? Colors.white.withOpacity(0.15) : Colors.transparent,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
        ),
        onPressed: onPressed,
      ),
    );
  }
}

/// 布局快捷切换按钮
class _LayoutToggleButton extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: LyricStyleService(),
      builder: (context, _) {
        final currentStyle = LyricStyleService().currentStyle;
        return Tooltip(
          message: '快速切换播放器样式',
          child: IconButton(
            icon: Icon(
              currentStyle == LyricStyle.immersive 
                  ? Icons.fullscreen_exit_rounded 
                  : Icons.fullscreen_rounded,
              size: 24,
            ),
            color: Colors.white.withOpacity(0.8),
            onPressed: () {
              LyricStyle nextStyle;
              if (currentStyle == LyricStyle.defaultStyle) {
                nextStyle = LyricStyle.fluidCloud;
              } else if (currentStyle == LyricStyle.fluidCloud) {
                nextStyle = LyricStyle.immersive;
              } else {
                nextStyle = LyricStyle.defaultStyle;
              }
              LyricStyleService().setStyle(nextStyle);
            },
          ),
        );
      },
    );
  }
}
