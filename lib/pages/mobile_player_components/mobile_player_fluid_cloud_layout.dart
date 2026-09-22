import 'dart:io';
import 'dart:ui';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../services/player_service.dart';
import '../../services/playlist_service.dart';
import '../../services/download_service.dart';
import '../../services/music_service.dart';
import '../../models/lyric_line.dart';
import '../../models/track.dart';
import 'mobile_player_fluid_cloud_lyric_panel.dart';
import 'mobile_player_fluid_cloud_song_wiki_panel.dart';
import 'mobile_player_dialogs.dart';
import 'mobile_player_settings_sheet.dart';
import 'dart:async';
import 'mobile_player_background.dart';
import 'package:flutter/services.dart';
import '../../services/playback_mode_service.dart';
import '../../services/auto_collapse_service.dart';
import '../../services/audio_quality_service.dart';
import '../../services/audio_source_service.dart';
import '../../utils/image_utils.dart';
import '../../utils/toast_utils.dart';
import '../../models/song_detail.dart';
import '../../widgets/player_error_banner.dart';
import '../../widgets/player_speed_selector.dart';

/// 移动端流体云播放器布局
/// 参考 HTML 设计：统一在同一页面显示歌曲信息、歌词、控制按钮
/// 歌词样式参考桌面端流体云歌词，显示3行
class MobilePlayerFluidCloudLayout extends StatefulWidget {
  final List<LyricLine> lyrics;
  final int currentLyricIndex;
  final bool showTranslation;
  final LyricLoadState lyricState;
  final VoidCallback onBackPressed;
  final VoidCallback? onPlaylistPressed;
  final VoidCallback? onVolumeControlPressed;

  const MobilePlayerFluidCloudLayout({
    super.key,
    required this.lyrics,
    required this.currentLyricIndex,
    required this.showTranslation,
    required this.lyricState,
    required this.onBackPressed,
    this.onPlaylistPressed,
    this.onVolumeControlPressed,
  });

  @override
  State<MobilePlayerFluidCloudLayout> createState() =>
      _MobilePlayerFluidCloudLayoutState();
}

class _MobilePlayerFluidCloudLayoutState
    extends State<MobilePlayerFluidCloudLayout>
    with TickerProviderStateMixin {
  final GlobalKey _volumeButtonKey = GlobalKey();

  // 自动折叠逻辑
  bool _isControlsVisible = true;
  Timer? _collapseTimer;
  bool _wasPlaying = false;
  // 封面模式 (经典模式)
  bool _showCoverMode = true;
  // 歌曲信息面板
  bool _showSongWikiPanel = false;

  // 下滑关闭相关
  double _dragOffset = 0;
  late AnimationController _snapController;
  late Animation<double> _snapAnimation;

  @override
  void initState() {
    super.initState();
    _wasPlaying = PlayerService().isPlaying;
    // 监听播放状态变化以控制计时器
    PlayerService().addListener(_onPlayerStateChanged);
    // 监听设置变化
    AutoCollapseService().addListener(_onSettingsChanged);

    // 初始化时如果正在播放且开启了折叠，启动计时器
    if (_wasPlaying && AutoCollapseService().isAutoCollapseEnabled) {
      _resetCollapseTimer();
    }

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
    _collapseTimer?.cancel();
    PlayerService().removeListener(_onPlayerStateChanged);
    AutoCollapseService().removeListener(_onSettingsChanged);
    _snapController.dispose();
    super.dispose();
  }

  void _onSettingsChanged() {
    if (mounted) setState(() {});
    // 如果设置关闭，确保控件显示
    if (!AutoCollapseService().isAutoCollapseEnabled) {
      _showControls(autoHide: false);
    } else {
      // 开启时，如果正在播放，重置计时器
      if (PlayerService().isPlaying && _isControlsVisible) {
        _resetCollapseTimer();
      }
    }
  }

  void _onPlayerStateChanged() {
    // 仅在播放状态改变时处理
    final isPlaying = PlayerService().isPlaying;
    if (isPlaying != _wasPlaying) {
      _wasPlaying = isPlaying;

      // Trigger rebuild for cover animation
      if (mounted) setState(() {});

      if (AutoCollapseService().isAutoCollapseEnabled) {
        if (isPlaying) {
          // 开始播放，如果控件可见，启动计时器
          if (_isControlsVisible) {
            _resetCollapseTimer();
          }
        } else {
          // 暂停时始终显示
          _showControls(autoHide: false);
        }
      }
    }
  }

  /// 显示控制栏
  /// [autoHide] 是否在显示后自动启动隐藏倒计时
  void _showControls({bool autoHide = true}) {
    if (!_isControlsVisible) {
      setState(() => _isControlsVisible = true);
    }

    if (autoHide &&
        AutoCollapseService().isAutoCollapseEnabled &&
        PlayerService().isPlaying) {
      _resetCollapseTimer();
    } else {
      _collapseTimer?.cancel();
    }
  }

  void _resetCollapseTimer() {
    _collapseTimer?.cancel();
    if (AutoCollapseService().isAutoCollapseEnabled &&
        PlayerService().isPlaying) {
      _collapseTimer = Timer(const Duration(seconds: 5), () {
        if (mounted) {
          setState(() => _isControlsVisible = false);
        }
      });
    }
  }

  /// 切换控制栏可见性
  void _toggleControls() {
    if (AutoCollapseService().isAutoCollapseEnabled) {
      if (_isControlsVisible) {
        // 如果当前可见，手动点击则隐藏（可选，或只是忽略）
        setState(() => _isControlsVisible = false);
      } else {
        // 如果当前隐藏，点击则显示
        _showControls();
      }
    }
  }

  void _onVerticalDragUpdate(DragUpdateDetails details) {
    setState(() {
      _dragOffset += details.delta.dy;
      if (_dragOffset < 0) _dragOffset = 0; // 不允许向上拖动
    });
  }

  void _onVerticalDragEnd(DragEndDetails details) {
    if (_dragOffset > 150 || (details.primaryVelocity ?? 0) > 800) {
      // 下滑超过阈值或速度足够快，关闭播放器
      widget.onBackPressed();
    } else {
      // 回弹
      _snapAnimation = Tween<double>(begin: _dragOffset, end: 0).animate(
        CurvedAnimation(parent: _snapController, curve: Curves.easeOutCubic),
      );
      _snapController.forward(from: 0);
    }
  }

  @override
  Widget build(BuildContext context) {
    final player = PlayerService();
    final isPending = player.isLoading && player.pendingTrack != null;
    final displayTrack = player.displayTrack;
    final song = isPending ? null : player.currentSong;
    final track = displayTrack;
    final imageUrl = player.displayCoverUrl ?? '';

    // 检测屏幕方向
    final orientation = MediaQuery.of(context).orientation;
    final isLandscape = orientation == Orientation.landscape;

    // 不再这里提前返回，统一在下方的 Stack 中处理
    // if (isLandscape) {
    //   // 横屏模式：左右分栏布局
    //   return _buildLandscapeLayout(context, player, song, track, imageUrl);
    // }

    return GestureDetector(
      onVerticalDragUpdate: _onVerticalDragUpdate,
      onVerticalDragEnd: _onVerticalDragEnd,
      child: Transform.translate(
        offset: Offset(0, _dragOffset),
        child: ClipRRect(
          // 仅在向下拖动时显示圆角，全屏状态无圆角
          borderRadius: _dragOffset > 0
              ? const BorderRadius.vertical(top: Radius.circular(32))
              : BorderRadius.zero,
          child: Stack(
            children: [
              // 0. 背景层 (现在作为布局的一部分，以便同步平移)
              MobilePlayerBackground(dragOffset: _dragOffset),

              // 1. 横屏布局
              if (isLandscape)
                _buildLandscapeLayout(context, player, song, track, imageUrl)
              else
                SafeArea(
                  child: Column(
                    children: [
                      // 1.1 顶部操作栏（小白条居中，更多与百科靠右）
                      _buildTopBar(context, track),

                      // 1.2 中间展示舞台（封面 vs 歌词/百科，同位无缝平滑切换）
                      Expanded(
                        child: Stack(
                          alignment: Alignment.center,
                          children: [
                            // 歌词与歌曲百科视图
                            AnimatedOpacity(
                              duration: const Duration(milliseconds: 250),
                              curve: Curves.easeInOut,
                              opacity: _showCoverMode ? 0.0 : 1.0,
                              child: IgnorePointer(
                                ignoring: _showCoverMode,
                                child: GestureDetector(
                                  onTap: () {
                                    if (AutoCollapseService()
                                        .isAutoCollapseEnabled) {
                                      _toggleControls();
                                    } else {
                                      setState(() => _showCoverMode = true);
                                    }
                                  },
                                  behavior: HitTestBehavior.translucent,
                                  child: _showSongWikiPanel
                                      ? const MobilePlayerFluidCloudSongWikiPanel(
                                          key: ValueKey('wiki'),
                                        )
                                      : _buildLyricsSection(),
                                ),
                              ),
                            ),

                            // 专辑封面视图
                            AnimatedOpacity(
                              duration: const Duration(milliseconds: 250),
                              curve: Curves.easeInOut,
                              opacity: _showCoverMode ? 1.0 : 0.0,
                              child: IgnorePointer(
                                ignoring: !_showCoverMode,
                                child: GestureDetector(
                                  onTap: () =>
                                      setState(() => _showCoverMode = false),
                                  child: Center(
                                    child: _buildAlbumCoverView(
                                      context,
                                      player,
                                      imageUrl,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),

                      const SizedBox(height: 8),

                      // 1.3 统一歌曲信息（标题、歌手、收藏、下载）—— 坐标与位置双模式完全锁死！
                      _buildUnifiedSongInfoSection(context, song, track),

                      const SizedBox(height: 10),

                      // 1.4 控制区域（进度条、时间、播放按钮）—— 坐标与位置双模式完全锁死！
                      AnimatedSize(
                        duration: const Duration(milliseconds: 250),
                        curve: Curves.easeInOut,
                        alignment: Alignment.topCenter,
                        child: AnimatedOpacity(
                          duration: const Duration(milliseconds: 250),
                          opacity: _isControlsVisible ? 1.0 : 0.0,
                          child: _isControlsVisible
                              ? _buildControlsSection(player)
                              : const SizedBox.shrink(),
                        ),
                      ),

                      const SizedBox(height: 8),

                      // 1.5 底部固定导航栏（歌词、模式、音量、队列）—— 4个图标双模式完全一致！
                      _buildBottomNavigation(context, track),

                      const SizedBox(height: 8),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  /// 构建顶部操作栏（居中小白条，右侧为百科与更多设置）
  Widget _buildTopBar(BuildContext context, Track? track) {
    final isNetease = track != null && track.source == MusicSource.netease;

    return SizedBox(
      height: 48,
      child: Stack(
        alignment: Alignment.center,
        children: [
          // 居中小白条
          Center(
            child: Container(
              width: 36,
              height: 4.5,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.35),
                borderRadius: BorderRadius.circular(2.25),
              ),
            ),
          ),

          // 右侧操作按钮
          Positioned(
            right: 8,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (isNetease)
                  IconButton(
                    icon: Icon(
                      _showSongWikiPanel
                          ? CupertinoIcons.text_quote
                          : CupertinoIcons.info_circle,
                      color: _showSongWikiPanel
                          ? Colors.white
                          : Colors.white.withValues(alpha: 0.7),
                      size: 22,
                    ),
                    tooltip: _showSongWikiPanel ? '显示歌词' : '歌曲百科',
                    onPressed: () {
                      setState(() {
                        _showSongWikiPanel = !_showSongWikiPanel;
                        if (_showSongWikiPanel) {
                          _showCoverMode = false;
                        }
                      });
                    },
                  ),
                IconButton(
                  icon: Icon(
                    Icons.more_horiz,
                    color: Colors.white.withValues(alpha: 0.8),
                    size: 24,
                  ),
                  tooltip: '播放器设置',
                  onPressed: () {
                    MobilePlayerSettingsSheet.show(
                      context,
                      currentTrack: track,
                    );
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// 构建居中的专辑封面视图 (带呼吸动画与投影)
  Widget _buildAlbumCoverView(
    BuildContext context,
    PlayerService player,
    String imageUrl,
  ) {
    final isPlaying = player.isPlaying;

    return LayoutBuilder(
      builder: (context, constraints) {
        final maxSide = min(
          constraints.maxWidth - 48,
          constraints.maxHeight - 20,
        );
        final baseCoverSize = maxSide.clamp(140.0, 360.0);
        final targetCoverSize = isPlaying ? baseCoverSize : baseCoverSize * 0.92;

        return AnimatedContainer(
          duration: const Duration(milliseconds: 350),
          curve: Curves.easeOutCubic,
          width: targetCoverSize,
          height: targetCoverSize,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: isPlaying ? 0.45 : 0.3),
                blurRadius: isPlaying ? 36 : 24,
                offset: Offset(0, isPlaying ? 16 : 8),
                spreadRadius: 2,
              ),
            ],
          ),
          clipBehavior: Clip.antiAlias,
          child: imageUrl.isNotEmpty
              ? _buildCoverImage(imageUrl)
              : Container(
                  color: Colors.grey[900],
                  child: const Icon(
                    Icons.music_note,
                    color: Colors.white54,
                    size: 80,
                  ),
                ),
        );
      },
    );
  }

  /// 横屏模式布局：左右平衡设计
  /// 左侧：专辑封面 + 歌曲标题与歌手 + 音质/倍速标签
  /// 右侧：顶部快捷操作 + 5行 Apple Music 沉浸式流体歌词 + 完整进度条与控制按键坞
  Widget _buildLandscapeLayout(
    BuildContext context,
    PlayerService player,
    dynamic song,
    dynamic track,
    String imageUrl,
  ) {
    final name = song?.name ?? track?.name ?? '未知歌曲';
    final artist = song?.arName ?? track?.artists ?? '未知艺术家';

    final mediaQuery = MediaQuery.of(context);
    final screenHeight = mediaQuery.size.height;
    final screenWidth = mediaQuery.size.width;
    final safePadding = mediaQuery.padding;

    // 自适应封面尺寸：(屏幕高度 - 边距 - 歌曲信息留白)
    final availableHeight = screenHeight - safePadding.top - safePadding.bottom;
    final coverSize = (availableHeight - 110).clamp(150.0, 215.0);

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          safePadding.left > 0 ? 8 : 24,
          6,
          safePadding.right > 0 ? 8 : 24,
          10,
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // ──────────────────────────────────────────
            // 1. 左侧面板：专辑封面展示与元数据
            // ──────────────────────────────────────────
            SizedBox(
              width: (screenWidth * 0.36).clamp(240.0, 310.0),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  const Spacer(flex: 2),

                  // 封面容器：圆角、高光边框、高斯投影
                  Container(
                    width: coverSize,
                    height: coverSize,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(
                        color: Colors.white.withValues(alpha: 0.14),
                        width: 0.8,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.48),
                          blurRadius: 26,
                          offset: const Offset(0, 10),
                          spreadRadius: 1,
                        ),
                      ],
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: imageUrl.isNotEmpty
                        ? _buildCoverImage(imageUrl)
                        : Container(
                            color: Colors.grey[900],
                            child: const Icon(
                              Icons.music_note_rounded,
                              size: 72,
                              color: Colors.white54,
                            ),
                          ),
                  ),

                  const SizedBox(height: 12),

                  // 歌曲名称
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    child: Text(
                      name,
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                        fontFamily: 'Microsoft YaHei',
                        letterSpacing: 0.3,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                    ),
                  ),
                  const SizedBox(height: 4),

                  // 歌手名称
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                    child: Text(
                      artist,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                        color: Colors.white.withValues(alpha: 0.7),
                        fontFamily: 'Microsoft YaHei',
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                    ),
                  ),

                  const SizedBox(height: 10),

                  // 音质 + 倍速标签
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _buildQualityButton(context),
                      const SizedBox(width: 8),
                      _buildSpeedButton(context),
                    ],
                  ),

                  const Spacer(flex: 3),
                ],
              ),
            ),

            const SizedBox(width: 16),

            // ──────────────────────────────────────────
            // 2. 右侧面板：快捷栏 + 5行流体歌词 + 进度条 + 控制坞
            // ──────────────────────────────────────────
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // 顶部快捷工具栏
                  SizedBox(
                    height: 36,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        if (track != null && track.source == MusicSource.netease)
                          IconButton(
                            icon: Icon(
                              _showSongWikiPanel
                                  ? CupertinoIcons.text_quote
                                  : CupertinoIcons.info_circle,
                              color: _showSongWikiPanel
                                  ? Colors.white
                                  : Colors.white.withValues(alpha: 0.7),
                              size: 20,
                            ),
                            tooltip: _showSongWikiPanel ? '歌词' : '歌曲百科',
                            onPressed: () {
                              setState(() => _showSongWikiPanel = !_showSongWikiPanel);
                            },
                          ),
                        IconButton(
                          icon: Icon(
                            Icons.more_horiz,
                            color: Colors.white.withValues(alpha: 0.85),
                            size: 22,
                          ),
                          tooltip: '更多选项',
                          onPressed: () {
                            MobilePlayerSettingsSheet.show(
                              context,
                              currentTrack: track,
                            );
                          },
                        ),
                      ],
                    ),
                  ),

                  // 歌词主展示区 (或歌曲百科)
                  Expanded(
                    child: AnimatedSwitcher(
                      duration: const Duration(milliseconds: 300),
                      child: _showSongWikiPanel
                          ? const MobilePlayerFluidCloudSongWikiPanel(
                              key: ValueKey('wiki_landscape'),
                            )
                          : _buildLandscapeLyricsSection(),
                    ),
                  ),

                  const SizedBox(height: 10),

                  // 底部：准确进度条与完整控制按键
                  _buildLandscapeControlsArea(context, player, track),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 构建横屏底部完整的控制区（进度条 + 播放控制坞）
  Widget _buildLandscapeControlsArea(
    BuildContext context,
    PlayerService player,
    Track? track,
  ) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // 1. 进度条 (两端准确显示起止时间)
        AnimatedBuilder(
          animation: Listenable.merge([player.positionNotifier, player]),
          builder: (context, _) {
            final position = player.positionNotifier.value;
            final effectiveDuration = _getEffectiveDuration(player);
            final durationMs = effectiveDuration.inMilliseconds.toDouble();
            final positionMs = position.inMilliseconds.toDouble();
            final progress = (durationMs > 0)
                ? (positionMs / durationMs).clamp(0.0, 1.0)
                : 0.0;
            final bufferedProgress = durationMs > 0
                ? (player.bufferedPosition.inMilliseconds / durationMs)
                    .clamp(0.0, 1.0)
                : 0.0;

            final totalStr = effectiveDuration.inSeconds > 0
                ? _formatDurationCompact(effectiveDuration)
                : '--:--';
            final currentStr = _formatDurationCompact(position);

            return Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // 播放进度起止时间显示
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        currentStr,
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.65),
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          fontFamily: 'Consolas',
                          letterSpacing: 0.4,
                        ),
                      ),
                      Text(
                        totalStr,
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.65),
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          fontFamily: 'Consolas',
                          letterSpacing: 0.4,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 2),

                // 流体 Apple Music 进度滑块
                SizedBox(
                  height: 22,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      Container(
                        height: 3.5,
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(999),
                        ),
                      ),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: FractionallySizedBox(
                          widthFactor: bufferedProgress,
                          child: Container(
                            height: 3.5,
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.35),
                              borderRadius: BorderRadius.circular(999),
                            ),
                          ),
                        ),
                      ),
                      _AppleMusicSlider(
                        value: progress,
                        onChanged: (v) {
                          final pos = Duration(
                            milliseconds: (v * durationMs).round(),
                          );
                          player.seek(pos);
                        },
                      ),
                    ],
                  ),
                ),
              ],
            );
          },
        ),

        const SizedBox(height: 6),

        // 2. 完整播放控制按键行 (播放模式、上一首、播放/暂停、下一首、收藏、队列)
        Row(
          children: [
            // 播放模式切换按钮 (单击切换，长按唤出模式面板)
            _buildPlaybackModeButton(context),

            const Spacer(),

            // 上一首
            IconButton(
              icon: const Icon(CupertinoIcons.backward_fill),
              color: Colors.white.withValues(alpha: 0.9),
              iconSize: 32,
              onPressed: player.hasPrevious ? player.playPrevious : null,
            ),
            const SizedBox(width: 14),

            // 播放 / 暂停
            AnimatedBuilder(
              animation: player,
              builder: (context, _) {
                return IconButton(
                  icon: Icon(
                    player.isPlaying
                        ? CupertinoIcons.pause_fill
                        : CupertinoIcons.play_fill,
                    color: Colors.white,
                  ),
                  iconSize: 52,
                  padding: EdgeInsets.zero,
                  onPressed: player.togglePlayPause,
                );
              },
            ),
            const SizedBox(width: 14),

            // 下一首
            IconButton(
              icon: const Icon(CupertinoIcons.forward_fill),
              color: Colors.white.withValues(alpha: 0.9),
              iconSize: 32,
              onPressed: player.hasNext ? player.playNext : null,
            ),

            const Spacer(),

            // 收藏按钮
            if (track != null) _FavoriteButton(track: track),
            const SizedBox(width: 6),

            // 播放队列抽屉入口
            IconButton(
              icon: const Icon(Icons.queue_music_rounded),
              color: Colors.white.withValues(alpha: 0.85),
              iconSize: 26,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(),
              tooltip: '播放队列',
              onPressed: widget.onPlaylistPressed,
            ),
          ],
        ),
      ],
    );
  }

  /// 横屏模式歌词区域 (5 行平滑流体云歌词 + 渐变遮罩)
  Widget _buildLandscapeLyricsSection() {
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
          stops: [0.0, 0.12, 0.88, 1.0],
        ).createShader(bounds);
      },
      blendMode: BlendMode.dstIn,
      child: MobilePlayerFluidCloudLyricsPanel(
        lyrics: widget.lyrics,
        currentLyricIndex: widget.currentLyricIndex,
        lyricState: widget.lyricState,
        showTranslation: widget.showTranslation,
        visibleLineCount: 5,
      ),
    );
  }

  /// 格式化时间（紧凑格式：00:01）
  String _formatDurationCompact(Duration duration) {
    if (duration.inSeconds <= 0) return '00:00';
    final minutes = duration.inMinutes.toString().padLeft(2, '0');
    final seconds = (duration.inSeconds % 60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }

  /// 构建统一的歌曲信息区域（双模式完全复用，位置与尺寸绝对固定）
  Widget _buildUnifiedSongInfoSection(
    BuildContext context,
    dynamic song,
    dynamic track,
  ) {
    final name = song?.name ?? track?.name ?? '未知歌曲';
    final artists = song?.arName ?? track?.artists ?? '未知艺术家';

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 28),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // 歌曲标题和歌手
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  name,
                  style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                    fontFamily: 'Microsoft YaHei',
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 4),
                Text(
                  artists,
                  style: TextStyle(
                    fontSize: 16,
                    color: Colors.white.withValues(alpha: 0.7),
                    fontFamily: 'Microsoft YaHei',
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),

          // 右侧操作：收藏与下载
          if (track != null) ...[
            _FavoriteButton(track: track),
            const SizedBox(width: 4),
            _DownloadButton(track: track),
          ],
        ],
      ),
    );
  }

  /// 构建歌词区域 - 复用桌面端流体云歌词组件，通过遮罩限制只显示3行
  Widget _buildLyricsSection() {
    return ShaderMask(
      shaderCallback: (Rect bounds) {
        // 上下渐变遮罩
        return LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Colors.transparent,
            Colors.black,
            Colors.black,
            Colors.black,
            Colors.transparent,
            Colors.transparent,
          ],
          stops: const [
            0.0, // 顶部完全透明
            0.15, // 开始可见
            0.5, // 中心
            0.85, // 依然可见
            0.95, // 开始渐变
            1.0, // 底部完全透明
          ],
        ).createShader(bounds);
      },
      blendMode: BlendMode.dstIn,
      child: MobilePlayerFluidCloudLyricsPanel(
        lyrics: widget.lyrics,
        currentLyricIndex: widget.currentLyricIndex,
        lyricState: widget.lyricState,
        showTranslation: widget.showTranslation,
        // 当控制栏隐藏时，显示更多行数 (例如 9 行)，否则显示 5 行 (原有逻辑似乎是3行可见，但Panel默认7)
        // 这里的可见行数决定了字体大小和行高计算
        visibleLineCount: _isControlsVisible ? 5 : 8,
      ),
    );
  }

  /// 构建控制区域（进度条 + 播放按钮）
  Widget _buildControlsSection(PlayerService player) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Column(
        children: [
          // 进度条
          Column(
            children: [
              // 进度条 - Apple Music 风格
              AnimatedBuilder(
                animation: Listenable.merge([player.positionNotifier, player]),
                builder: (context, _) {
                  final position = player.positionNotifier.value.inMilliseconds
                      .toDouble();
                  final effectiveDuration = _getEffectiveDuration(player);
                  final duration = effectiveDuration.inMilliseconds.toDouble();
                  final value = (duration > 0)
                      ? (position / duration).clamp(0.0, 1.0)
                      : 0.0;
                  final bufferedValue = duration > 0
                      ? (player.bufferedPosition.inMilliseconds / duration)
                            .clamp(0.0, 1.0)
                      : 0.0;

                  return SizedBox(
                    height: 24, // 增加点击热区
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        Container(
                          height: 3,
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.14),
                            borderRadius: BorderRadius.circular(999),
                          ),
                        ),
                        Align(
                          alignment: Alignment.centerLeft,
                          child: FractionallySizedBox(
                            widthFactor: bufferedValue,
                            child: Container(
                              height: 3,
                              decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha: 0.32),
                                borderRadius: BorderRadius.circular(999),
                              ),
                            ),
                          ),
                        ),
                        _AppleMusicSlider(
                          value: value,
                          onChanged: (v) {
                            final pos = Duration(
                              milliseconds: (v * duration).round(),
                            );
                            player.seek(pos);
                          },
                        ),
                      ],
                    ),
                  );
                },
              ),

              const SizedBox(height: 8),

              // 时间显示
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    AnimatedBuilder(
                      animation: player.positionNotifier,
                      builder: (context, _) => Text(
                        _formatDuration(player.positionNotifier.value),
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.6),
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                          fontFamily: 'Consolas',
                        ),
                      ),
                    ),

                    // --- 核心：音质切换按钮 ---
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _buildQualityButton(context),
                        const SizedBox(width: 8),
                        _buildSpeedButton(context),
                      ],
                    ),

                    AnimatedBuilder(
                      animation: Listenable.merge([player.positionNotifier, player]),
                      builder: (context, _) {
                        final effectiveDuration = _getEffectiveDuration(player);
                        return Text(
                          effectiveDuration.inSeconds > 0
                              ? _formatDuration(effectiveDuration)
                              : '--:--',
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.6),
                            fontSize: 13,
                            fontWeight: FontWeight.bold,
                            fontFamily: 'Consolas',
                          ),
                        );
                      },
                    ),
                  ],
                ),
              ),
              PlayerErrorBanner(
                message: player.isAudioSourceNotConfigured
                    ? null
                    : player.errorMessage,
                margin: const EdgeInsets.only(top: 6),
                onRetry: () {
                  player.retryCurrent();
                },
                showSkip: player.hasNext,
                onSkip: player.hasNext
                    ? () {
                        player.playNext();
                      }
                    : null,
              ),
            ],
          ),

          const SizedBox(height: 40),

          // 播放控制按钮 (iOS 风格)
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              // 上一首
              IconButton(
                icon: const Icon(CupertinoIcons.backward_fill),
                color: Colors.white.withValues(alpha: 0.9),
                iconSize: 42,
                onPressed: player.hasPrevious ? player.playPrevious : null,
              ),

              // 播放/暂停（大图标，无圆形背景）
              AnimatedBuilder(
                animation: player,
                builder: (context, _) {
                  return IconButton(
                    icon: Icon(
                      player.isPlaying
                          ? CupertinoIcons.pause_fill
                          : CupertinoIcons.play_fill,
                      color: Colors.white,
                    ),
                    iconSize: 72,
                    padding: EdgeInsets.zero,
                    onPressed: player.togglePlayPause,
                  );
                },
              ),

              // 下一首
              IconButton(
                icon: const Icon(CupertinoIcons.forward_fill),
                color: Colors.white.withValues(alpha: 0.9),
                iconSize: 42,
                onPressed: player.hasNext ? player.playNext : null,
              ),
            ],
          ),

          const SizedBox(height: 12),
        ],
      ),
    );
  }

  /// 构建底部导航（4个固定导航按键：歌词切换、播放模式、音量调节、播放列表，双模式绝对一致）
  Widget _buildBottomNavigation(BuildContext context, Track? track) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          // 1. 歌词模式切换按钮 (最左侧)
          IconButton(
            icon: Icon(
              CupertinoIcons.quote_bubble,
              color: !_showCoverMode
                  ? Colors.white
                  : Colors.white.withValues(alpha: 0.5),
            ),
            iconSize: 24,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
            tooltip: !_showCoverMode ? '显示封面' : '显示歌词',
            onPressed: () {
              setState(() => _showCoverMode = !_showCoverMode);
            },
          ),

          // 2. 播放模式切换按钮 (居中：单点切换，长按呼出面板)
          _buildPlaybackModeButton(context),

          // 3. 音量控制按钮 (双模式始终显示，位置完全固定)
          AnimatedBuilder(
            animation: PlayerService(),
            builder: (context, _) {
              final volume = PlayerService().volume;
              return IconButton(
                key: _volumeButtonKey,
                icon: Icon(
                  volume == 0
                      ? Icons.volume_off_rounded
                      : volume < 0.5
                          ? Icons.volume_down_rounded
                          : Icons.volume_up_rounded,
                  color: Colors.white.withValues(alpha: 0.85),
                ),
                iconSize: 24,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
                tooltip: '音量调节',
                onPressed: () {
                  MobilePlayerDialogs.showVolumePopup(
                    context,
                    buttonKey: _volumeButtonKey,
                  );
                },
              );
            },
          ),

          // 4. 播放列表按钮 (最右侧)
          IconButton(
            icon: const Icon(Icons.queue_music_rounded),
            color: Colors.white.withValues(alpha: 0.85),
            iconSize: 26,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
            tooltip: '播放队列',
            onPressed: widget.onPlaylistPressed,
          ),
        ],
      ),
    );
  }

  /// 构建播放模式按钮（1键切换，长按呼出模式面板）
  Widget _buildPlaybackModeButton(BuildContext context) {
    return AnimatedBuilder(
      animation: PlaybackModeService(),
      builder: (context, _) {
        final modeService = PlaybackModeService();
        final currentMode = modeService.currentMode;
        final isLoopAll = currentMode == PlaybackMode.loopAll;

        return Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(20),
            onTap: () {
              HapticFeedback.lightImpact();
              modeService.toggleMode();
              ToastUtils.infoWithIcon(
                modeService.getModeName(),
                icon: modeService.getModeIcon(),
              );
            },
            onLongPress: () {
              HapticFeedback.mediumImpact();
              MobilePlayerDialogs.showPlaybackModeSelector(context);
            },
            child: Padding(
              padding: const EdgeInsets.all(6),
              child: Icon(
                modeService.getModeIcon(),
                color: isLoopAll
                    ? Colors.white.withValues(alpha: 0.75)
                    : Colors.white,
                size: 24,
              ),
            ),
          ),
        );
      },
    );
  }

  String _formatDuration(Duration duration) {
    final minutes = duration.inMinutes;
    final seconds = duration.inSeconds % 60;
    return '${minutes.toString().padLeft(1, '0')}:${seconds.toString().padLeft(2, '0')}';
  }

  /// 获取有效时长，优先使用引擎时长，兜底使用歌词时间戳估算，并确保不低于当前播放进度
  Duration _getEffectiveDuration(PlayerService player) {
    Duration duration = player.duration;
    if (duration.inSeconds <= 0 &&
        player.lyricSnapshot != null &&
        player.lyricSnapshot!.lines.isNotEmpty) {
      final lastLine = player.lyricSnapshot!.lines.last;
      duration = lastLine.startTime +
          (lastLine.lineDuration ?? const Duration(seconds: 4));
    }
    final position = player.positionNotifier.value;
    if (duration.inSeconds > 0 && position > duration) {
      duration = position;
    }
    return duration;
  }

  /// 构建音质选择按钮
  Widget _buildQualityButton(BuildContext context) {
    return ListenableBuilder(
      listenable: AudioQualityService(),
      builder: (context, _) {
        final qualityService = AudioQualityService();
        final label = qualityService.getShortLabel();

        return GestureDetector(
          onTap: () => _showQualitySelectionSheet(context),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              label,
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.6),
                fontSize: 9.5,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.2,
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildSpeedButton(BuildContext context) {
    final player = PlayerService();
    return PlayerSpeedSelector(
      speed: player.playbackSpeed,
      onSelected: (value) => player.setPlaybackSpeed(value),
      compact: true,
      menuColor: Colors.black.withValues(alpha: 0.85),
      borderColor: Colors.transparent,
      fillColor: Colors.white.withValues(alpha: 0.1),
      textColor: Colors.white.withValues(alpha: 0.7),
      fontSize: 9.5,
    );
  }

  /// 显示音质选择底部菜单
  void _showQualitySelectionSheet(BuildContext context) {
    final qualityService = AudioQualityService();
    final sourceService = AudioSourceService();
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final colorScheme = theme.colorScheme;
    final supportedQualities = sourceService.activeSource != null
        ? qualityService.getSupportedQualities(sourceService.sourceType)
        : [AudioQuality.standard, AudioQuality.exhigh, AudioQuality.lossless];

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withValues(alpha: 0.5),
      builder: (context) => ClipRRect(
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 25, sigmaY: 25),
          child: Container(
            decoration: BoxDecoration(
              color: (isDark ? const Color(0xFF141418) : Colors.white)
                  .withValues(alpha: 0.92),
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(28)),
              border: Border(
                top: BorderSide(
                  color: Colors.white.withValues(alpha: isDark ? 0.12 : 0.4),
                  width: 0.8,
                ),
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: isDark ? 0.45 : 0.12),
                  blurRadius: 30,
                  offset: const Offset(0, -10),
                ),
              ],
            ),
            child: SafeArea(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    margin: const EdgeInsets.only(top: 12, bottom: 8),
                    width: 38,
                    height: 4.5,
                    decoration: BoxDecoration(
                      color: isDark ? Colors.white24 : Colors.black12,
                      borderRadius: BorderRadius.circular(2.5),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 10, 20, 14),
                    child: Row(
                      children: [
                        Text(
                          '选择播放音质',
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w800,
                            letterSpacing: -0.3,
                            color: colorScheme.onSurface,
                          ),
                        ),
                        const Spacer(),
                        IconButton(
                          icon: Icon(Icons.close_rounded,
                              color: colorScheme.onSurfaceVariant, size: 20),
                          onPressed: () => Navigator.pop(context),
                          style: IconButton.styleFrom(
                            backgroundColor: isDark
                                ? Colors.white.withValues(alpha: 0.08)
                                : Colors.black.withValues(alpha: 0.05),
                            padding: const EdgeInsets.all(6),
                            minimumSize: const Size(32, 32),
                          ),
                        ),
                      ],
                    ),
                  ),
                  Divider(
                    height: 1,
                    thickness: 0.6,
                    color: isDark
                        ? Colors.white10
                        : Colors.black.withValues(alpha: 0.06),
                  ),
                  ...supportedQualities.map((quality) {
                    final isSelected =
                        qualityService.currentQuality == quality;
                    return ListTile(
                      title: Text(
                        qualityService.getQualityName(quality),
                        style: TextStyle(
                          color: isSelected
                              ? colorScheme.primary
                              : colorScheme.onSurface,
                          fontWeight:
                              isSelected ? FontWeight.bold : FontWeight.w500,
                        ),
                      ),
                      subtitle: Text(
                        qualityService.getQualityDescription(quality),
                        style: TextStyle(
                          color:
                              colorScheme.onSurfaceVariant.withValues(alpha: 0.7),
                          fontSize: 12,
                        ),
                      ),
                      trailing: isSelected
                          ? Icon(Icons.check_circle_rounded,
                              color: colorScheme.primary)
                          : null,
                      onTap: () {
                        qualityService.setQuality(quality);
                        Navigator.pop(context);
                        ToastUtils.success(
                          '音质已设置为 ${qualityService.getQualityName(quality)}，将在下次切换歌曲时生效',
                        );
                      },
                    );
                  }),
                  const SizedBox(height: 16),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// 构建封面图片（支持网络 URL 和本地文件路径）
  Widget _buildCoverImage(String imageUrl) {
    // 判断是网络 URL 还是本地文件路径
    final isNetwork =
        imageUrl.startsWith('http://') || imageUrl.startsWith('https://');

    if (isNetwork) {
      return CachedNetworkImage(
        imageUrl: imageUrl,
        httpHeaders: getImageHeaders(imageUrl),
        fit: BoxFit.cover,
        memCacheWidth: 1080,
        memCacheHeight: 1080,
        placeholder: (context, url) => Container(color: Colors.grey[900]),
        errorWidget: (context, url, error) => Container(
          color: Colors.grey[900],
          child: const Icon(Icons.music_note, color: Colors.white54),
        ),
      );
    } else {
      // 本地文件
      return Image.file(
        File(imageUrl),
        fit: BoxFit.cover,
        errorBuilder: (context, error, stackTrace) => Container(
          color: Colors.grey[900],
          child: const Icon(Icons.music_note, color: Colors.white54),
        ),
      );
    }
  }
}

/// 收藏按钮组件
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
    if (oldWidget.track.id != widget.track.id ||
        oldWidget.track.source != widget.track.source) {
      _checkIfInPlaylist();
    }
  }

  Future<void> _checkIfInPlaylist() async {
    setState(() => _isLoading = true);

    final playlistService = PlaylistService();
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

  void _showManageOptions(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final colorScheme = theme.colorScheme;

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withValues(alpha: 0.5),
      builder: (context) => ClipRRect(
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 25, sigmaY: 25),
          child: Container(
            decoration: BoxDecoration(
              color: (isDark ? const Color(0xFF141418) : Colors.white)
                  .withValues(alpha: 0.92),
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(28)),
              border: Border(
                top: BorderSide(
                  color: Colors.white.withValues(alpha: isDark ? 0.12 : 0.4),
                  width: 0.8,
                ),
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: isDark ? 0.45 : 0.12),
                  blurRadius: 30,
                  offset: const Offset(0, -10),
                ),
              ],
            ),
            child: SafeArea(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    margin: const EdgeInsets.only(top: 12, bottom: 8),
                    width: 38,
                    height: 4.5,
                    decoration: BoxDecoration(
                      color: isDark ? Colors.white24 : Colors.black12,
                      borderRadius: BorderRadius.circular(2.5),
                    ),
                  ),
                  Padding(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                    child: Text(
                      '已收藏到: ${_playlistNames.join(", ")}',
                      style: TextStyle(
                        color: colorScheme.onSurfaceVariant.withValues(alpha: 0.75),
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),
                  Divider(
                    height: 1,
                    thickness: 0.6,
                    color: isDark
                        ? Colors.white10
                        : Colors.black.withValues(alpha: 0.06),
                  ),
                  ListTile(
                    leading: Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        color: Colors.red.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(
                        Icons.remove_circle_outline_rounded,
                        color: Colors.redAccent,
                        size: 20,
                      ),
                    ),
                    title: const Text(
                      '从所有歌单移除',
                      style: TextStyle(
                        color: Colors.redAccent,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    onTap: () async {
                      Navigator.pop(context);
                      await _removeFromPlaylists();
                    },
                  ),
                  ListTile(
                    leading: Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        color: colorScheme.primary.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Icon(
                        Icons.playlist_add_rounded,
                        color: colorScheme.primary,
                        size: 20,
                      ),
                    ),
                    title: Text(
                      '添加到其他歌单',
                      style: TextStyle(
                        color: colorScheme.onSurface,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    onTap: () {
                      Navigator.pop(context);
                      MobilePlayerDialogs.showAddToPlaylist(
                          context, widget.track);
                    },
                  ),
                  const SizedBox(height: 16),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const SizedBox(
        width: 40,
        height: 40,
        child: Padding(
          padding: EdgeInsets.all(10.0),
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

    return IconButton(
      icon: Icon(
        _isInPlaylist ? Icons.favorite : Icons.favorite_border,
        color: _isInPlaylist ? Colors.redAccent : Colors.white.withValues(alpha: 0.8),
      ),
      onPressed: () {
        if (_isInPlaylist) {
          _showManageOptions(context);
        } else {
          MobilePlayerDialogs.showAddToPlaylist(context, widget.track);
        }
      },
      tooltip: tooltip,
    );
  }
}

/// 下载按钮组件
class _DownloadButton extends StatefulWidget {
  final Track track;

  const _DownloadButton({required this.track});

  @override
  State<_DownloadButton> createState() => _DownloadButtonState();
}

class _DownloadButtonState extends State<_DownloadButton> {
  bool _isDownloaded = false;
  bool _isDownloading = false;
  bool _isLoading = true;
  double _progress = 0.0;

  @override
  void initState() {
    super.initState();
    _checkDownloadStatus();
    DownloadService().addListener(_onDownloadChanged);
  }

  @override
  void dispose() {
    DownloadService().removeListener(_onDownloadChanged);
    super.dispose();
  }

  @override
  void didUpdateWidget(_DownloadButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.track.id != widget.track.id ||
        oldWidget.track.source != widget.track.source) {
      _checkDownloadStatus();
    }
  }

  void _onDownloadChanged() {
    if (!mounted) return;

    final downloadService = DownloadService();
    final trackId = '${widget.track.source.name}_${widget.track.id}';
    final tasks = downloadService.downloadTasks;
    final task = tasks[trackId];

    if (task != null) {
      setState(() {
        _isDownloading = !task.isCompleted && !task.isFailed;
        _progress = task.progress;
        if (task.isCompleted) {
          _isDownloaded = true;
          _isDownloading = false;
        }
      });
    }
  }

  Future<void> _checkDownloadStatus() async {
    setState(() => _isLoading = true);

    final isDownloaded = await DownloadService().isDownloaded(widget.track);

    if (mounted) {
      setState(() {
        _isDownloaded = isDownloaded;
        _isLoading = false;
      });
    }
  }

  Future<void> _startDownload() async {
    if (_isDownloading || _isDownloaded) return;

    setState(() {
      _isDownloading = true;
      _progress = 0.0;
    });

    try {
      // 获取歌曲详情
      final songDetail = PlayerService().currentSong;
      if (songDetail == null) {
        // 如果当前没有歌曲详情，尝试获取
        final detail = await MusicService().fetchSongDetail(
          songId: widget.track.id.toString(),
          source: widget.track.source,
          title: widget.track.name,
          artist: widget.track.artists,
        );

        if (detail == null) {
          if (mounted) {
            ScaffoldMessenger.of(
              context,
            ).showSnackBar(const SnackBar(content: Text('获取歌曲信息失败')));
            setState(() => _isDownloading = false);
          }
          return;
        }

        final success = await DownloadService().downloadSong(
          widget.track,
          detail,
          onProgress: (progress) {
            if (mounted) {
              setState(() => _progress = progress);
            }
          },
        );

        if (mounted) {
          if (success) {
            setState(() {
              _isDownloaded = true;
              _isDownloading = false;
            });
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('${widget.track.name} 下载完成')),
            );
          } else {
            setState(() => _isDownloading = false);
            ScaffoldMessenger.of(
              context,
            ).showSnackBar(const SnackBar(content: Text('下载失败')));
          }
        }
      } else {
        final success = await DownloadService().downloadSong(
          widget.track,
          songDetail,
          onProgress: (progress) {
            if (mounted) {
              setState(() => _progress = progress);
            }
          },
        );

        if (mounted) {
          if (success) {
            setState(() {
              _isDownloaded = true;
              _isDownloading = false;
            });
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('${widget.track.name} 下载完成')),
            );
          } else {
            setState(() => _isDownloading = false);
            ScaffoldMessenger.of(
              context,
            ).showSnackBar(const SnackBar(content: Text('下载失败或文件已存在')));
          }
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isDownloading = false);
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('下载失败: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const SizedBox(
        width: 48,
        height: 48,
        child: Padding(
          padding: EdgeInsets.all(12.0),
          child: CircularProgressIndicator(
            strokeWidth: 2,
            color: Colors.white54,
          ),
        ),
      );
    }

    if (_isDownloading) {
      return SizedBox(
        width: 48,
        height: 48,
        child: Stack(
          alignment: Alignment.center,
          children: [
            CircularProgressIndicator(
              value: _progress,
              strokeWidth: 2,
              color: Colors.white,
              backgroundColor: Colors.white24,
            ),
            Text(
              '${(_progress * 100).toInt()}%',
              style: const TextStyle(color: Colors.white, fontSize: 10),
            ),
          ],
        ),
      );
    }

    return IconButton(
      icon: Icon(
        _isDownloaded ? Icons.download_done_rounded : Icons.download_rounded,
        color: _isDownloaded ? Colors.green : Colors.white.withValues(alpha: 0.8),
      ),
      onPressed: _isDownloaded ? null : _startDownload,
      tooltip: _isDownloaded ? '已下载' : '下载',
    );
  }
}

/// Apple Music 风格的 Slider 组件
/// 1. 默认显示微弱滑块
/// 2. 交互时激活轨道变亮
/// 3. 使用圆形滑块，触摸拖动时放大
class _AppleMusicSlider extends StatefulWidget {
  final double value;
  final ValueChanged<double>? onChanged;
  static const double min = 0.0;
  static const double max = 1.0;
  static const Color activeColor = Colors.white;
  static const Color inactiveColor = Color(0x1FFFFFFF); // 约 12% 不透明度

  const _AppleMusicSlider({
    required this.value,
    required this.onChanged,
  });

  @override
  State<_AppleMusicSlider> createState() => _AppleMusicSliderState();
}

class _AppleMusicSliderState extends State<_AppleMusicSlider>
    with SingleTickerProviderStateMixin {
  double? _dragValue; // 用于处理移动端拖动时的平滑感
  late AnimationController _controller;
  late Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 200),
    );
    _animation = CurvedAnimation(
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
    return AnimatedBuilder(
      animation: _animation,
      builder: (context, child) {
        // 交互时 active track 变亮
        final currentActiveColor = _AppleMusicSlider.activeColor.withValues(
          alpha:
          lerpDouble(0.65, 0.9, _animation.value) ?? 0.65,
        );

        final currentInactiveColor =
            Color.lerp(
              _AppleMusicSlider.inactiveColor,
              Colors.white.withValues(alpha: 0.3),
              _animation.value,
            ) ??
            _AppleMusicSlider.inactiveColor;

        return SliderTheme(
          data: SliderThemeData(
            trackHeight: 6,
            trackShape: const RoundedRectSliderTrackShape(),
            thumbShape: _AppleMusicThumbShape(
              scale: _animation.value, // 完全跟随动画，未交互时为 0 (隐藏)
              opacity: _animation.value,
            ),
            overlayShape: SliderComponentShape.noOverlay,
            activeTrackColor: currentActiveColor,
            inactiveTrackColor: currentInactiveColor,
          ),
          child: Slider(
            value: _dragValue ?? widget.value,
            onChanged: (v) {
              setState(() {
                _dragValue = v; // 立即更新本地值以确保拖动流畅
              });
              if (widget.onChanged != null) widget.onChanged!(v);
            },
            onChangeStart: (_) {
              setState(() {
                _dragValue = widget.value;
              });
              _controller.forward();
            },
            onChangeEnd: (_) {
              setState(() {
                _dragValue = null; // 释放拖动，恢复跟随外部进度
              });
              _controller.reverse();
            },
            min: _AppleMusicSlider.min,
            max: _AppleMusicSlider.max,
          ),
        );
      },
    );
  }
}

/// 自定义圆形滑块，支持缩放和透明度动画
class _AppleMusicThumbShape extends SliderComponentShape {
  final double scale;
  final double opacity;
  static const double maxRadius = 6.0;

  const _AppleMusicThumbShape({
    required this.scale,
    this.opacity = 1.0,
  });

  @override
  Size getPreferredSize(bool isEnabled, bool isDiscrete) {
    return Size.fromRadius(maxRadius);
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
    if (scale <= 0.01) return; // 隐藏不绘制

    final Canvas canvas = context.canvas;

    // 绘制阴影
    final path = Path()
      ..addOval(Rect.fromCircle(center: center, radius: maxRadius * scale));

    canvas.drawShadow(path, Colors.black.withValues(alpha: 0.3 * opacity), 3.0, true);

    // 绘制白色圆点
    final Paint paint = Paint()
      ..color = Colors.white.withValues(alpha: opacity)
      ..style = PaintingStyle.fill;

    canvas.drawCircle(center, maxRadius * scale, paint);
  }
}
