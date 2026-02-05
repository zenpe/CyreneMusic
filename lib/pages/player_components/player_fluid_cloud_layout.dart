import 'dart:io';
import 'dart:ui';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:fluent_ui/fluent_ui.dart' as fluent;
import '../../services/player_service.dart';
import '../../services/playlist_service.dart';
import '../../services/netease_artist_service.dart';
import '../../utils/theme_manager.dart';
import '../../models/lyric_line.dart';
import '../../models/track.dart';
import '../../models/song_detail.dart';
import '../../widgets/search_widget.dart';
import '../artist_detail_page.dart';
import 'player_fluid_cloud_background.dart';
import 'player_window_controls.dart';
import 'player_fluid_cloud_lyrics_panel.dart';
import 'player_fluid_cloud_queue_panel.dart';
import 'player_fluid_cloud_queue_panel.dart';
import 'player_fluid_cloud_song_wiki_panel.dart';
import '../mobile_player_components/mobile_player_settings_sheet.dart';
import 'player_dialogs.dart';

/// 流体云全屏布局
/// 模仿 Apple Music 的左右分栏设计
/// 左侧：封面、信息、控制
/// 右侧：沉浸式歌词
class PlayerFluidCloudLayout extends StatefulWidget {
  final List<LyricLine> lyrics;
  final int currentLyricIndex;
  final bool showTranslation;
  final bool isMaximized;
  final VoidCallback onBackPressed;
  final VoidCallback onPlaylistPressed;
  final VoidCallback onVolumeControlPressed;
  final VoidCallback? onSleepTimerPressed;
  final VoidCallback? onTranslationToggle;
  final double leftPanelScale;

  const PlayerFluidCloudLayout({
    super.key,
    required this.lyrics,
    required this.currentLyricIndex,
    required this.showTranslation,
    required this.isMaximized,
    required this.onBackPressed,
    required this.onPlaylistPressed,
    required this.onVolumeControlPressed,
    this.onSleepTimerPressed,
    this.onTranslationToggle,
    this.leftPanelScale = 0.9,
  });

  @override
  State<PlayerFluidCloudLayout> createState() => _PlayerFluidCloudLayoutState();
}

class _PlayerFluidCloudLayoutState extends State<PlayerFluidCloudLayout>
    with TickerProviderStateMixin {
  // 缓存当前歌曲的封面 URL，用于检测歌曲变化
  String? _currentImageUrl;

  Future<void>? _pendingCoverPrecache;
  
  // 歌词折叠状态
  bool _isLyricsCollapsed = false;
  
  // 折叠按钮显示状态（鼠标悬停时显示）
  bool _showCollapseButton = false;

  // 是否显示待播播放队列 (代替歌词显示)
  bool _showQueue = false;


  // 是否显示歌曲百科 (代替歌词显示)
  bool _showWiki = false;
  
  // 折叠动画控制器
  AnimationController? _collapseController;
  Animation<double>? _collapseAnimation;
  
  // 获取动画值，未初始化时返回 0
  double get _collapseAnimationValue => _collapseAnimation?.value ?? 0.0;
  
  // 下滑关闭相关 (平板模式胶囊拖动)
  double _dragOffset = 0;
  late AnimationController _snapController;
  late Animation<double> _snapAnimation;
  
  @override
  void initState() {
    super.initState();
    
    // 先初始化折叠动画控制器（在其他操作之前）
    _collapseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    );
    _collapseAnimation = CurvedAnimation(
      parent: _collapseController!,
      curve: Curves.easeInOutCubic,
    );
    
    PlayerService().addListener(_onPlayerChanged);
    _updateCurrentImageUrl();

    // 初始化下滑回弹动画
    _snapController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
    _snapController.addListener(() {
      setState(() {
        _dragOffset = _snapAnimation.value;
      });
    });
  }
  
  @override
  void dispose() {
    _collapseController?.dispose();
    _snapController.dispose();
    PlayerService().removeListener(_onPlayerChanged);
    super.dispose();
  }
  
  /// 切换歌词折叠状态
  void _toggleLyricsCollapse() {
    setState(() {
      _isLyricsCollapsed = !_isLyricsCollapsed;
    });
    if (_isLyricsCollapsed) {
      _collapseController?.forward();
    } else {
      _collapseController?.reverse();
    }
  }
  
  void _onPlayerChanged() {
    // 检查封面 URL 是否变化
    final player = PlayerService();
    final newImageUrl = player.currentCoverUrl ?? '';
    
    if (_currentImageUrl != newImageUrl) {
      setState(() {
        _currentImageUrl = newImageUrl;
      });

      final provider = player.currentCoverImageProvider;
      if (provider != null) {
        _pendingCoverPrecache = precacheImage(
          provider,
          context,
          size: const Size(512, 512),
        );
      }
    }
  }
  
  void _updateCurrentImageUrl() {
    _currentImageUrl = PlayerService().currentCoverUrl ?? '';
  }

  /// 处理胶囊拖动更新
  void _handleCapsuleDragUpdate(DragUpdateDetails details) {
    setState(() {
      _dragOffset += details.delta.dy;
      if (_dragOffset < 0) _dragOffset = 0; // 不允许向上拖动
    });
  }

  /// 处理胶囊拖动结束
  void _handleCapsuleDragEnd(DragEndDetails details) {
    if (_dragOffset > 150 || (details.primaryVelocity ?? 0) > 800) {
      // 下滑超过阈值或速度足够快，关闭播放器
      widget.onBackPressed();
    } else {
      // 回弹
      _snapAnimation = Tween<double>(
        begin: _dragOffset,
        end: 0,
      ).animate(CurvedAnimation(
        parent: _snapController,
        curve: Curves.easeOutCubic,
      ));
      _snapController.forward(from: 0);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Transform.translate(
      offset: Offset(0, _dragOffset),
      child: Stack(
      children: [
        // 1. 全局背景（流体云专用背景：自适应模式下始终显示专辑封面 100% 填充）
        Positioned.fill(child: const PlayerFluidCloudBackground()),
        
        // 2. 玻璃拟态遮罩 (整个容器)
        Positioned.fill(
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 40, sigmaY: 40),
            child: Container(
              color: Colors.black.withOpacity(0.2), // 降低亮度以突出内容
            ),
          ),
        ),

        // 3. 主要内容区域
        SafeArea(
          child: Column(
            children: [
              // 顶部窗口控制
              Builder(
                builder: (context) {
                  final player = PlayerService();
                  return PlayerWindowControls(
                    isMaximized: widget.isMaximized,
                    onBackPressed: widget.onBackPressed,
                    onSleepTimerPressed: widget.onSleepTimerPressed,
                    // 译文按钮相关
                    showTranslationButton: _shouldShowTranslationButton(),
                    showTranslation: widget.showTranslation,
                    onTranslationToggle: widget.onTranslationToggle,
                    // 下载按钮相关
                    currentTrack: player.currentTrack,
                    currentSong: player.currentSong,
                    isLyricsActive: !_isLyricsCollapsed && !_showQueue && !_showWiki,
                    isQueueActive: !_isLyricsCollapsed && _showQueue,
                    isWikiActive: !_isLyricsCollapsed && _showWiki,
                    onLyricsToggle: () {
                      setState(() {
                        if (!_isLyricsCollapsed && !_showQueue && !_showWiki) {
                          // 如果当前已经是歌词，点击则折叠
                          _toggleLyricsCollapse();
                        } else if (_isLyricsCollapsed) {
                          // 如果目前处于折叠状态，则展开并显示歌词
                          _showQueue = false;
                          _showWiki = false;
                          _toggleLyricsCollapse();
                        } else {
                          // 如果目前在显示其他，则切换到歌词
                          _showQueue = false;
                          _showWiki = false;
                        }
                      });
                    },
                    onQueueToggle: () {
                      setState(() {
                        if (!_isLyricsCollapsed && _showQueue) {
                          // 如果当前已经是队列，点击则折叠
                          _toggleLyricsCollapse();
                        } else if (_isLyricsCollapsed) {
                          // 如果目前处于折叠状态，则展开并显示队列
                          _showQueue = true;
                          _showWiki = false;
                          _toggleLyricsCollapse();
                        } else {
                          // 如果目前在显示其他，则切换到队列
                          _showQueue = true;
                          _showWiki = false;
                        }
                      });
                    },
                    onWikiToggle: () {
                      setState(() {
                        if (!_isLyricsCollapsed && _showWiki) {
                          // 如果当前已经是百科，点击则折叠
                          _toggleLyricsCollapse();
                        } else if (_isLyricsCollapsed) {
                          // 如果目前处于折叠状态，则展开并显示百科
                          _showWiki = true;
                          _showQueue = false;
                          _toggleLyricsCollapse();
                        } else {
                          // 如果目前在显示其他，则切换到百科
                          _showWiki = true;
                          _showQueue = false;
                        }
                      });
                    },
                    isTabletMode: ThemeManager().isTablet,
                    onMorePressed: () => MobilePlayerSettingsSheet.show(
                      context, 
                      currentTrack: player.currentTrack
                    ),

                    // 传递拖动回调
                    onCapsuleDragUpdate: _handleCapsuleDragUpdate,
                    onCapsuleDragEnd: _handleCapsuleDragEnd,
                  );
                },
              ),
              
              // 主体布局 - 支持歌词折叠
              Expanded(
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    return Padding(
                      padding: const EdgeInsets.only(left: 60, right: 40, top: 20, bottom: 20),
                      child: AnimatedBuilder(
                        animation: _collapseController ?? const AlwaysStoppedAnimation(0.0),
                        builder: (context, child) {
                          // 计算动态布局比例
                          // 展开时: 左侧 42%, 右侧 58%
                          // 折叠时: 左侧占据全部空间居中
                          final animValue = _collapseAnimationValue;
                          final leftFlex = (42 + (58 * animValue)).round();
                          final rightFlex = (58 * (1 - animValue)).round();
                          final rightOpacity = 1.0 - animValue;
                          
                          return Stack(
                            children: [
                              // 主要内容 Row
                              Row(
                                crossAxisAlignment: CrossAxisAlignment.center,
                                children: [
                                  // 左侧：控制面板 (动态宽度)
                                  Expanded(
                                    flex: leftFlex,
                                    child: Padding(
                                      // 折叠时减少右侧 padding
                                      padding: EdgeInsets.only(
                                        right: 60 * (1 - animValue) + 20 * animValue,
                                      ),
                                      child: _buildLeftPanel(context),
                                    ),
                                  ),
                                  
                                  // 折叠按钮占位（实际按钮在 Stack 中）
                                  const SizedBox(width: 48),
                                  
                                  // 右侧：歌词面板 (动态宽度，折叠时隐藏)
                                  if (rightFlex > 0)
                                    Expanded(
                                      flex: rightFlex,
                                      child: MouseRegion(
                                        onEnter: (_) => setState(() => _showCollapseButton = true),
                                        onExit: (_) => setState(() => _showCollapseButton = false),
                                        child: Opacity(
                                          opacity: rightOpacity,
                                          child: Padding(
                                            padding: const EdgeInsets.only(left: 40),
                                            child: _buildRightPanel(),
                                          ),
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                              
                              // 折叠按钮（浮动在 Stack 中）
                              // 未折叠时：在歌词区域左侧
                              // 折叠时：在窗口右侧
                              Positioned(
                                right: _isLyricsCollapsed 
                                    ? 0  // 折叠时靠右
                                    : constraints.maxWidth * 0.58 - 16, // 未折叠时在歌词区域左边
                                top: 0,
                                bottom: 0,
                                child: _isLyricsCollapsed
                                    // 折叠时：右侧热区
                                    ? MouseRegion(
                                        onEnter: (_) => setState(() => _showCollapseButton = true),
                                        onExit: (_) => setState(() => _showCollapseButton = false),
                                        child: SizedBox(
                                          width: 60,
                                          child: Center(
                                            child: _buildCollapseButton(),
                                          ),
                                        ),
                                      )
                                    // 未折叠时：按钮直接显示（由歌词区域的 MouseRegion 控制）
                                    : Center(
                                        child: _buildCollapseButton(),
                                      ),
                              ),
                            ],
                          );
                        },
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ],
    ),
    );
  }

  /// 构建折叠按钮
  Widget _buildCollapseButton() {
    return MouseRegion(
      // 鼠标在按钮上时也保持显示
      onEnter: (_) => setState(() => _showCollapseButton = true),
      onExit: (_) => setState(() => _showCollapseButton = false),
      child: AnimatedOpacity(
        opacity: _showCollapseButton ? 1.0 : 0.0,
        duration: const Duration(milliseconds: 200),
        child: GestureDetector(
          onTap: _showCollapseButton ? _toggleLyricsCollapse : null,
          child: Container(
            width: 32,
            height: 80,
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.15),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: Colors.white.withOpacity(0.25),
                width: 1,
              ),
            ),
            child: Center(
              child: AnimatedRotation(
                duration: const Duration(milliseconds: 300),
                turns: _isLyricsCollapsed ? 0.5 : 0,
                child: Icon(
                  CupertinoIcons.chevron_right,
                  color: Colors.white.withOpacity(0.8),
                  size: 20,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// 构建左侧面板
  Widget _buildLeftPanel(BuildContext context) {
    final player = PlayerService();
    final song = player.currentSong;
    final track = player.currentTrack;
    // ✅ 关键修复：使用 PlayerService 的封面 URL 和 Provider，避免详情加载导致重新请求
    final imageUrl = player.currentCoverUrl ?? track?.picUrl ?? '';
    final coverProvider = player.currentCoverImageProvider;
    
    // 获取折叠动画值
    final animValue = _collapseAnimationValue;
    // 是否处于折叠状态（动画进行中或已折叠）
    final isCollapsing = animValue > 0;

    // 构建封面 widget（带渐变切换效果）
    Widget cover = AspectRatio(
      aspectRatio: 1.0,
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.4),
              blurRadius: 40,
              offset: const Offset(0, 20),
            ),
          ],
        ),
        clipBehavior: Clip.antiAlias,
        // ✨ Apple Music 风格：使用 AnimatedSwitcher 实现封面渐变切换
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 600),
          switchInCurve: Curves.easeOut,
          switchOutCurve: Curves.easeIn,
          transitionBuilder: (Widget child, Animation<double> animation) {
            return FadeTransition(
              opacity: animation,
              child: child,
            );
          },
          child: imageUrl.isNotEmpty
              ? RepaintBoundary(
                  key: ValueKey(imageUrl),
                  child: _buildCoverImage(imageUrl, preferProvider: coverProvider),
                )
              : Container(
                  key: const ValueKey('placeholder'),
                  color: Colors.grey[900],
                  child: const Icon(
                    Icons.music_note,
                    size: 80,
                    color: Colors.white54,
                  ),
                ),
        ),
      ),
    );

    // 根据折叠状态决定布局
    // 未折叠时：使用原有的 90% 缩放布局
    // 折叠时：居中显示，限制最大宽度
    if (isCollapsing) {
      return Center(
        child: Transform.scale(
          scale: 0.9,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 450),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                // 封面
                cover,
                const SizedBox(height: 40),
                
                // 歌曲信息
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Flexible(
                      child: Text(
                        track?.name ?? '未知歌曲',
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontSize: 28,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                          letterSpacing: -0.5,
                          fontFamily: 'Microsoft YaHei',
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (track != null) ...[
                      const SizedBox(width: 8),
                      _FavoriteButton(track: track),
                    ],
                  ],
                ),
                const SizedBox(height: 8),
                _buildArtistsRow(context, track?.artists ?? '未知歌手', player.currentSong),
                
                const SizedBox(height: 30),
                
                // 进度条
                AnimatedBuilder(
                  animation: player.positionNotifier,
                  builder: (context, _) {
                    final position = player.positionNotifier.value.inMilliseconds.toDouble();
                    final duration = player.duration.inMilliseconds.toDouble();
                    final value = (duration > 0) ? (position / duration).clamp(0.0, 1.0) : 0.0;
                    
                    return Column(
                      children: [
                        SizedBox(
                          height: 24,
                          child: _AppleMusicSlider(
                            value: value,
                            onChanged: (v) {
                              final pos = Duration(milliseconds: (v * duration).round());
                              player.seek(pos);
                            },
                          ),
                        ),
                        const SizedBox(height: 4),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              _formatDuration(player.positionNotifier.value),
                              style: TextStyle(
                                color: Colors.white.withOpacity(0.6),
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                                fontFamily: 'Consolas',
                              ),
                            ),
                            Text(
                              _formatDuration(player.duration),
                              style: TextStyle(
                                color: Colors.white.withOpacity(0.6),
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                                fontFamily: 'Consolas',
                              ),
                            ),
                          ],
                        ),
                      ],
                    );
                  },
                ),
                
                const SizedBox(height: 16),
                
                // 控制按钮
                Row(
                  mainAxisSize: MainAxisSize.min,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    IconButton(
                      icon: const Icon(CupertinoIcons.backward_fill),
                      color: Colors.white.withOpacity(0.9),
                      iconSize: 36,
                      onPressed: player.hasPrevious ? player.playPrevious : null,
                    ),
                    const SizedBox(width: 24),
                    AnimatedBuilder(
                      animation: player,
                      builder: (context, _) {
                        return IconButton(
                          icon: Icon(
                            player.isPlaying ? CupertinoIcons.pause_fill : CupertinoIcons.play_fill,
                            color: Colors.white,
                          ),
                          iconSize: 56,
                          padding: EdgeInsets.zero,
                          onPressed: player.togglePlayPause,
                        );
                      },
                    ),
                    const SizedBox(width: 24),
                    IconButton(
                      icon: const Icon(CupertinoIcons.forward_fill),
                      color: Colors.white.withOpacity(0.9),
                      iconSize: 36,
                      onPressed: player.hasNext ? player.playNext : null,
                    ),
                  ],
                ),
                
                const SizedBox(height: 20),
                
                // 音量控制
                _buildVolumeSlider(player),
              ],
            ),
          ),
        ),
      );
    }
    
    // 未折叠时：原有布局
    return Transform.scale(
      scale: widget.leftPanelScale,
      child: Center(
        child: SingleChildScrollView(
          physics: const ClampingScrollPhysics(),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // 1. 专辑封面
              cover,
              
              const SizedBox(height: 30), // 缩小间距 (40 -> 30)
              
              // 2. 歌曲信息（歌曲名 + 收藏按钮）
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Flexible(
                    child: Text(
                      track?.name ?? '未知歌曲',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                        letterSpacing: -0.5,
                        fontFamily: 'Microsoft YaHei',
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (track != null) ...[
                    const SizedBox(width: 8),
                    _FavoriteButton(track: track),
                  ],
                ],
              ),
              const SizedBox(height: 8),
              // 歌手名（可点击）
              _buildArtistsRow(context, track?.artists ?? '未知歌手', player.currentSong),
              
              const SizedBox(height: 24), // 缩小间距 (30 -> 24)
              
              // 3. 进度条 - Apple Music 风格 (Hover 显现滑块)
              AnimatedBuilder(
                animation: player.positionNotifier,
                builder: (context, _) {
                  final position = player.positionNotifier.value.inMilliseconds.toDouble();
                  final duration = player.duration.inMilliseconds.toDouble();
                  final value = (duration > 0) ? (position / duration).clamp(0.0, 1.0) : 0.0;
                  
                  return Column(
                    children: [
                      _AppleMusicSlider(
                        value: value,
                        onChanged: (v) {
                          final pos = Duration(milliseconds: (v * duration).round());
                          player.seek(pos);
                        },
                      ),
                      const SizedBox(height: 4),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 0),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              _formatDuration(player.positionNotifier.value),
                              style: TextStyle(
                                color: Colors.white.withOpacity(0.6), 
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                                fontFamily: 'Consolas',
                              ),
                            ),
                            Text(
                              _formatDuration(player.duration),
                              style: TextStyle(
                                color: Colors.white.withOpacity(0.6), 
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                                fontFamily: 'Consolas',
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  );
                }
              ),
              
              const SizedBox(height: 12), // 缩小间距 (16 -> 12)
              
              // 4. 控制按钮 (居中，作为一个整体) - iOS/Cupertino 风格图标，与移动端一致
              Center(
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    // 上一首 - iOS 风格粗图标
                    IconButton(
                      icon: const Icon(CupertinoIcons.backward_fill),
                      color: Colors.white.withOpacity(0.9),
                      iconSize: 36,
                      onPressed: player.hasPrevious ? player.playPrevious : null,
                    ),
                    const SizedBox(width: 24),
                    
                    // 播放/暂停 - iOS 风格粗图标
                    AnimatedBuilder(
                      animation: player,
                      builder: (context, _) {
                        return IconButton(
                          icon: Icon(
                            player.isPlaying ? CupertinoIcons.pause_fill : CupertinoIcons.play_fill,
                            color: Colors.white,
                          ),
                          iconSize: 56,
                          padding: EdgeInsets.zero,
                          onPressed: player.togglePlayPause,
                        );
                      }
                    ),
                    const SizedBox(width: 24),
                    
                    // 下一首 - iOS 风格粗图标
                    IconButton(
                      icon: const Icon(CupertinoIcons.forward_fill),
                      color: Colors.white.withOpacity(0.9),
                      iconSize: 36,
                      onPressed: player.hasNext ? player.playNext : null,
                    ),
                  ],
                ),
              ),
              
              const SizedBox(height: 16), // 缩小间距 (20 -> 16)
              
              // 5. 音量控制 (与进度条样式一致)
              _buildVolumeSlider(player),
              
            ],
          ),
        ),
      ),
    );
  }
  
  /// 构建音量滑条 - MD3 风格 (竖线滑块 + 分离式轨道，与移动端一致)
  Widget _buildVolumeSlider(PlayerService player) {
    return AnimatedBuilder(
      animation: player,
      builder: (context, _) {
        return Row(
          children: [
            // 静音图标
            Icon(
              CupertinoIcons.speaker_fill,
              color: Colors.white.withOpacity(0.5),
              size: 16,
            ),
            const SizedBox(width: 8),
            
            // 音量滑条 - Apple Music 风格
            Expanded(
              child: _AppleMusicSlider(
                value: player.volume,
                min: 0.0,
                max: 1.0,
                onChanged: (v) {
                  player.setVolume(v);
                },
              ),
            ),
            
            const SizedBox(width: 8),
            // 最大音量图标
            Icon(
              CupertinoIcons.speaker_3_fill,
              color: Colors.white.withOpacity(0.5),
              size: 16,
            ),
          ],
        );
      },
    );
  }

  Widget _buildRightPanel() {
    return ShaderMask(
      shaderCallback: (Rect bounds) {
        return const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Colors.transparent,
            Colors.black,
            Colors.black,
            Colors.transparent,
          ],
          stops: [0.0, 0.1, 0.9, 1.0], // 列表建议淡出略窄一点，保持可视区域
        ).createShader(bounds);
      },
      blendMode: BlendMode.dstIn,
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 500),
        transitionBuilder: (Widget child, Animation<double> animation) {
          return FadeTransition(
            opacity: animation,
            child: child,
          );
        },
        child: _showWiki
            ? const PlayerFluidCloudSongWikiPanel(key: ValueKey('wiki'))
            : _showQueue 
                ? const PlayerFluidCloudQueuePanel(key: ValueKey('queue'))
                : _buildLyricsContent(),
      ),
    );
  }

  Widget _buildLyricsContent() {
    return PlayerFluidCloudLyricsPanel(
      key: const ValueKey('lyrics'),
      lyrics: widget.lyrics,
      currentLyricIndex: widget.currentLyricIndex,
      showTranslation: widget.showTranslation,
    );
  }

  /// 构建封面图片（支持网络 URL 和本地文件路径）
  /// [preferProvider] 优先使用的预缓存 ImageProvider，避免重复请求
  Widget _buildCoverImage(String imageUrl, {ImageProvider? preferProvider}) {
    // 判断是网络 URL 还是本地文件路径
    final isNetwork = imageUrl.startsWith('http://') || imageUrl.startsWith('https://');
    
    if (isNetwork) {
      // ✅ 优先使用预缓存的 provider，避免歌曲详情加载时因 URL 轻微变化导致重新请求
      if (preferProvider != null) {
        return Image(
          key: ValueKey(imageUrl),
          image: preferProvider,
          fit: BoxFit.cover,
          filterQuality: FilterQuality.medium,
          errorBuilder: (context, error, stackTrace) => Container(
            color: Colors.grey[900],
          ),
        );
      }
      // 降级：无 provider 时使用 CachedNetworkImage
      return CachedNetworkImage(
        key: ValueKey(imageUrl),
        imageUrl: imageUrl,
        fit: BoxFit.cover,
        memCacheWidth: 1024,
        memCacheHeight: 1024,
        filterQuality: FilterQuality.medium,
        placeholder: (context, url) => Container(
          color: Colors.grey[900],
        ),
        errorWidget: (context, url, error) => Container(
          color: Colors.grey[900],
        ),
      );
    } else {
      // 本地文件
      return Image.file(
        File(imageUrl),
        key: ValueKey(imageUrl),
        fit: BoxFit.cover,
        filterQuality: FilterQuality.medium,
        errorBuilder: (context, error, stackTrace) => Container(
          color: Colors.grey[900],
          child: const Icon(
            Icons.music_note,
            size: 80,
            color: Colors.white54,
          ),
        ),
      );
    }
  }

  String _formatDuration(Duration duration) {
    final minutes = duration.inMinutes;
    final seconds = duration.inSeconds % 60;
    return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }

  /// 判断是否应该显示译文按钮
  /// 只有当歌词非中文且存在翻译时才显示
  bool _shouldShowTranslationButton() {
    if (widget.lyrics.isEmpty) return false;
    
    // 检查是否有翻译
    final hasTranslation = widget.lyrics.any((lyric) => 
      lyric.translation != null && lyric.translation!.isNotEmpty
    );
    
    if (!hasTranslation) return false;
    
    // 检查原文是否为中文（检查前几行非空歌词）
    final sampleLyrics = widget.lyrics
        .where((lyric) => lyric.text.trim().isNotEmpty)
        .take(5)
        .map((lyric) => lyric.text)
        .join('');
    
    if (sampleLyrics.isEmpty) return false;
    
    // 判断是否主要为中文（中文字符占比）
    final chineseCount = sampleLyrics.runes.where((rune) {
      return (rune >= 0x4E00 && rune <= 0x9FFF) || // 基本汉字
             (rune >= 0x3400 && rune <= 0x4DBF) || // 扩展A
             (rune >= 0x20000 && rune <= 0x2A6DF); // 扩展B
    }).length;
    
    final totalCount = sampleLyrics.runes.length;
    final chineseRatio = totalCount > 0 ? chineseCount / totalCount : 0;
    
    // 如果中文字符占比小于30%，认为是非中文歌词
    return chineseRatio < 0.3;
  }

  /// 构建歌手行（支持多歌手点击）
  Widget _buildArtistsRow(BuildContext context, String artistsStr, SongDetail? song) {
    final artists = _splitArtists(artistsStr);
    
    return Wrap(
      alignment: WrapAlignment.center,
      children: artists.asMap().entries.map((entry) {
        final index = entry.key;
        final artist = entry.value;
        
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            GestureDetector(
              onTap: () => _onArtistTap(context, artist, song),
              child: MouseRegion(
                cursor: SystemMouseCursors.click,
                child: Text(
                  artist,
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w400,
                    color: Colors.white.withOpacity(0.6),
                    fontFamily: 'Microsoft YaHei',
                    decoration: TextDecoration.underline,
                    decorationColor: Colors.white.withOpacity(0.3),
                  ),
                ),
              ),
            ),
            if (index < artists.length - 1)
              Text(
                ' / ',
                style: TextStyle(
                  fontSize: 18,
                  color: Colors.white.withOpacity(0.6),
                  fontFamily: 'Microsoft YaHei',
                ),
              ),
          ],
        );
      }).toList(),
    );
  }

  /// 分割歌手字符串（支持多种分隔符）
  List<String> _splitArtists(String artistsStr) {
    final separators = ['/', ',', '、'];
    
    for (final separator in separators) {
      if (artistsStr.contains(separator)) {
        return artistsStr
            .split(separator)
            .map((a) => a.trim())
            .where((a) => a.isNotEmpty)
            .toList();
      }
    }
    
    return [artistsStr];
  }

  /// 歌手点击处理
  Future<void> _onArtistTap(BuildContext context, String artistName, SongDetail? song) async {
    // 仅在网易云音乐来源时跳转歌手详情，否则沿用搜索
    if (song?.source != MusicSource.netease) {
      _searchInDialog(context, artistName);
      return;
    }
    // 解析歌手ID（后端无返回ID时，通过搜索解析）
    final id = await NeteaseArtistDetailService().resolveArtistIdByName(artistName);
    if (id == null) {
      _searchInDialog(context, artistName);
      return;
    }
    if (!context.mounted) return;
    
    final isFluent = ThemeManager().isFluentFramework;
    
    if (isFluent) {
      // Fluent UI 样式对话框
      final fluentTheme = fluent.FluentTheme.of(context);
      final backgroundColor = fluentTheme.micaBackgroundColor ?? 
          fluentTheme.scaffoldBackgroundColor;
      
      fluent.showDialog(
        context: context,
        barrierDismissible: true,
        barrierColor: Colors.black87,
        builder: (context) => fluent.ContentDialog(
          constraints: const BoxConstraints(maxWidth: 800, maxHeight: 700),
          style: fluent.ContentDialogThemeData(
            padding: EdgeInsets.zero,
            bodyPadding: EdgeInsets.zero,
            decoration: BoxDecoration(
              color: backgroundColor,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: fluentTheme.resources.surfaceStrokeColorDefault,
                width: 1,
              ),
            ),
          ),
          content: ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: SizedBox(
              width: 800,
              height: 700,
              child: ArtistDetailContent(artistId: id),
            ),
          ),
        ),
      );
    } else {
      // Material 样式对话框
      showDialog(
        context: context,
        barrierDismissible: true,
        barrierColor: Colors.black87,
        builder: (context) => Dialog(
          backgroundColor: Colors.transparent,
          insetPadding: const EdgeInsets.all(16),
          child: Container(
            constraints: const BoxConstraints(maxWidth: 800, maxHeight: 700),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surface,
              borderRadius: BorderRadius.circular(28),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(28),
              child: ArtistDetailContent(artistId: id),
            ),
          ),
        ),
      );
    }
  }

  /// 在对话框中打开搜索
  void _searchInDialog(BuildContext context, String keyword) {
    final isFluent = ThemeManager().isFluentFramework;
    
    if (isFluent) {
      // Fluent UI 样式对话框
      final fluentTheme = fluent.FluentTheme.of(context);
      final backgroundColor = fluentTheme.micaBackgroundColor ?? 
          fluentTheme.scaffoldBackgroundColor;
      
      fluent.showDialog(
        context: context,
        barrierDismissible: true,
        barrierColor: Colors.black87,
        builder: (context) => fluent.ContentDialog(
          constraints: const BoxConstraints(maxWidth: 800, maxHeight: 700),
          style: fluent.ContentDialogThemeData(
            padding: EdgeInsets.zero,
            bodyPadding: EdgeInsets.zero,
            decoration: BoxDecoration(
              color: backgroundColor,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: fluentTheme.resources.surfaceStrokeColorDefault,
                width: 1,
              ),
            ),
          ),
          content: ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: SizedBox(
              width: 800,
              height: 700,
              child: SearchWidget(
                onClose: () => Navigator.pop(context),
                initialKeyword: keyword,
              ),
            ),
          ),
        ),
      );
    } else {
      // Material 样式对话框
      showDialog(
        context: context,
        barrierDismissible: true,
        barrierColor: Colors.black87,
        builder: (context) => Dialog(
          backgroundColor: Colors.transparent,
          insetPadding: const EdgeInsets.all(16),
          child: Container(
            constraints: const BoxConstraints(
              maxWidth: 800,
              maxHeight: 700,
            ),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surface,
              borderRadius: BorderRadius.circular(28),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(28),
              child: SearchWidget(
                onClose: () => Navigator.pop(context),
                initialKeyword: keyword,
              ),
            ),
          ),
        ),
      );
    }
  }
}

/// 收藏按钮组件
/// 检测歌曲是否在用户歌单中，显示实心或空心爱心
class _FavoriteButton extends StatefulWidget {
  final Track track;

  const _FavoriteButton({required this.track});

  @override
  State<_FavoriteButton> createState() => _FavoriteButtonState();
}

class _FavoriteButtonState extends State<_FavoriteButton> {
  bool _isInPlaylist = false;
  bool _isLoading = true;
  List<String> _playlistNames = [];
  List<int> _playlistIds = [];

  @override
  void initState() {
    super.initState();
    _checkIfInPlaylist();
  }

  @override
  void didUpdateWidget(_FavoriteButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 当歌曲变化时重新检查
    if (oldWidget.track.id != widget.track.id || 
        oldWidget.track.source != widget.track.source) {
      _checkIfInPlaylist();
    }
  }

  Future<void> _checkIfInPlaylist() async {
    setState(() => _isLoading = true);
    
    final playlistService = PlaylistService();
    
    // 调用后端 API 检查歌曲是否在任何歌单中
    final result = await playlistService.isTrackInAnyPlaylist(widget.track);
    
    if (mounted) {
      setState(() {
        _isInPlaylist = result.inPlaylist;
        _playlistNames = result.playlistNames;
        _playlistIds = result.playlistIds;
        _isLoading = false;
      });
    }
  }

  Future<void> _removeFromPlaylists() async {
    if (_playlistIds.isEmpty) return;
    
    final playlistService = PlaylistService();
    
    for (final playlistId in _playlistIds) {
      await playlistService.removeTrackFromPlaylist(
        playlistId,
        widget.track.id.toString(),
        widget.track.source.name,
      );
    }
    
    // 刷新状态
    _checkIfInPlaylist();
  }

  void _showManageMenu(BuildContext context, Offset position) {
    final RenderBox overlay = Overlay.of(context).context.findRenderObject() as RenderBox;
    
    showMenu<String>(
      context: context,
      position: RelativeRect.fromRect(
        Rect.fromCenter(center: position, width: 0, height: 0),
        Offset.zero & overlay.size,
      ),
      color: Colors.grey[850],
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      items: [
        PopupMenuItem<String>(
          value: 'info',
          enabled: false,
          child: Text(
            '已收藏到: ${_playlistNames.join(", ")}',
            style: TextStyle(color: Colors.white.withOpacity(0.6), fontSize: 12),
          ),
        ),
        const PopupMenuDivider(),
        PopupMenuItem<String>(
          value: 'remove',
          child: Row(
            children: [
              Icon(Icons.remove_circle_outline, color: Colors.redAccent, size: 18),
              const SizedBox(width: 8),
              const Text('从所有歌单移除', style: TextStyle(color: Colors.white)),
            ],
          ),
        ),
        PopupMenuItem<String>(
          value: 'add',
          child: Row(
            children: [
              Icon(Icons.playlist_add, color: Colors.white70, size: 18),
              const SizedBox(width: 8),
              const Text('添加到其他歌单', style: TextStyle(color: Colors.white)),
            ],
          ),
        ),
      ],
    ).then((value) {
      if (value == 'remove') {
        _removeFromPlaylists();
      } else if (value == 'add') {
        PlayerDialogs.showAddToPlaylist(context, widget.track);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const SizedBox(
        width: 32,
        height: 32,
        child: Padding(
          padding: EdgeInsets.all(8.0),
          child: CircularProgressIndicator(
            strokeWidth: 2,
            color: Colors.white54,
          ),
        ),
      );
    }

    final tooltip = _isInPlaylist 
        ? '已收藏到: ${_playlistNames.join(", ")}' 
        : '添加到歌单';

    return GestureDetector(
      onTapDown: (details) {
        if (_isInPlaylist) {
          _showManageMenu(context, details.globalPosition);
        } else {
          PlayerDialogs.showAddToPlaylist(context, widget.track);
        }
      },
      child: Tooltip(
        message: tooltip,
        child: Container(
          width: 32,
          height: 32,
          alignment: Alignment.center,
          child: Icon(
            _isInPlaylist ? Icons.favorite : Icons.favorite_border,
            color: _isInPlaylist ? Colors.redAccent : Colors.white.withOpacity(0.7),
            size: 26,
          ),
        ),
      ),
    );
  }
}

/// Apple Music 风格的 Slider 组件
/// 1. 默认隐藏滑块，鼠标悬停时显示
/// 2. 悬停时激活轨道变亮
/// 3. 使用圆形滑块，略微放大动画
class _AppleMusicSlider extends StatefulWidget {
  final double value;
  final ValueChanged<double>? onChanged;
  final double min;
  final double max;
  final Color activeColor;
  final Color inactiveColor;

  const _AppleMusicSlider({
    required this.value,
    required this.onChanged,
    this.min = 0.0,
    this.max = 1.0,
    this.activeColor = Colors.white,
    this.inactiveColor = const Color(0x1FFFFFFF), // 约 12% 不透明度
  });

  @override
  State<_AppleMusicSlider> createState() => _AppleMusicSliderState();
}

class _AppleMusicSliderState extends State<_AppleMusicSlider> with SingleTickerProviderStateMixin {
  bool _isHovering = false;
  late AnimationController _controller;
  late Animation<double> _thumbScaleAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 200),
    );
    _thumbScaleAnimation = CurvedAnimation(
      parent: _controller,
      curve: Curves.easeOutCubic,
    );
  }
  
  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) {
         setState(() => _isHovering = true);
         _controller.forward();
      },
      onExit: (_) {
         setState(() => _isHovering = false);
         _controller.reverse();
      },
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, child) {
          // 非悬停时，active track 颜色变得非常淡 (约 45%)，背景轨道则保持极致透明
          final currentActiveColor = _isHovering 
              ? widget.activeColor.withOpacity(0.8) 
              : widget.activeColor.withOpacity(0.45);
              
          final currentInactiveColor = _isHovering
              ? Colors.white.withOpacity(0.3)
              : widget.inactiveColor; // 默认即为 12%

          return SliderTheme(
            data: SliderThemeData(
              trackHeight: 6, 
              trackShape: const RoundedRectSliderTrackShape(),
              thumbShape: _AppleMusicThumbShape(scale: _thumbScaleAnimation.value),
              overlayShape: SliderComponentShape.noOverlay,
              activeTrackColor: currentActiveColor,
              inactiveTrackColor: currentInactiveColor,
            ),
            child: SizedBox(
               height: 20, // 增加热区高度方便点击
               child: Slider(
                 value: widget.value,
                 onChanged: widget.onChanged,
                 min: widget.min,
                 max: widget.max,
               ),
            ),
          );
        }
      ),
    );
  }
}

/// 自定义圆形滑块，支持缩放动画
class _AppleMusicThumbShape extends SliderComponentShape {
  final double scale;
  final double maxRadius;

  const _AppleMusicThumbShape({
    required this.scale,
    this.maxRadius = 6.0,
  });

  @override
  Size getPreferredSize(bool isEnabled, bool isDiscrete) {
    return Size.fromRadius(maxRadius * scale);
  }

  @override
  void paint(
    PaintingContext context,
    Offset center, {
    required Animation<double> activationAnimation,
    required Animation<double> enableAnimation,
    required bool isDiscrete,
    required TextPainter labelPainter,
    required RenderBox parentBox,
    required SliderThemeData sliderTheme,
    required TextDirection textDirection,
    required double value,
    required double textScaleFactor,
    required Size sizeWithOverflow,
  }) {
    if (scale <= 0.1) return; // 几乎隐藏时不绘制

    final Canvas canvas = context.canvas;
    
    // 绘制阴影 (可选，Apple Music 通常比较扁平，但微弱阴影增加立体感)
    final path = Path()
      ..addOval(Rect.fromCircle(center: center, radius: maxRadius * scale));
    
    canvas.drawShadow(path, Colors.black.withOpacity(0.3), 3.0, true);

    // 绘制白色圆点
    final Paint paint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.fill;
    
    canvas.drawCircle(center, maxRadius * scale, paint);
  }
}

