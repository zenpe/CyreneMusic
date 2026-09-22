import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import '../../services/player_service.dart';
import '../../services/playlist_service.dart';
import '../../services/lyric_style_service.dart';
import '../../services/lyric_font_service.dart';
import '../../services/playback_mode_service.dart';
import '../../models/lyric_line.dart';
import '../../models/track.dart';
import 'player_immersive_backdrop.dart';
import 'player_immersive_playback_button.dart';
import 'player_window_controls.dart';
import 'player_dialogs.dart';

/// 沉浸样式布局
/// 底部左右分栏 + 居中单行歌词
class PlayerImmersiveLayout extends StatelessWidget {
  final List<LyricLine> lyrics;
  final int currentLyricIndex;
  final bool showTranslation;
  final LyricLoadState lyricState;
  final bool isMaximized;
  final VoidCallback onBackPressed;
  final VoidCallback onPlaylistPressed;
  final VoidCallback onVolumeControlPressed;
  final VoidCallback? onSleepTimerPressed;
  final VoidCallback? onTranslationToggle;
  final VoidCallback? onMorePressed;
  final double uiScale;
  final bool carMode;
  final bool reducedEffects;

  const PlayerImmersiveLayout({
    super.key,
    required this.lyrics,
    required this.currentLyricIndex,
    required this.showTranslation,
    required this.lyricState,
    required this.isMaximized,
    required this.onBackPressed,
    required this.onPlaylistPressed,
    required this.onVolumeControlPressed,
    this.onSleepTimerPressed,
    this.onTranslationToggle,
    this.onMorePressed,
    this.uiScale = 1.0,
    this.carMode = false,
    this.reducedEffects = false,
  });

  @override
  Widget build(BuildContext context) {
    final player = PlayerService();
    final track = player.currentTrack;

    return IconButtonTheme(
      data: IconButtonThemeData(
        style: IconButton.styleFrom(
          minimumSize: Size.square(carMode ? 56 : 48),
        ),
      ),
      child: Stack(
        children: [
          Positioned.fill(
            child: PlayerImmersiveBackdrop(reducedEffects: reducedEffects),
          ),

          // 3. 顶部控件
          SafeArea(
            child: uiScale < 1.0
                ? _buildMobileTopBar()
                : PlayerWindowControls(
                    isMaximized: isMaximized,
                    onBackPressed: onBackPressed,
                    onSleepTimerPressed: onSleepTimerPressed,
                    showTranslationButton: true,
                    showTranslation: showTranslation,
                    onTranslationToggle: onTranslationToggle,
                    currentTrack: track,
                    currentSong: player.currentSong,
                    isLyricsActive: true,
                  ),
          ),

          // 4. 内容区域
          Padding(
            padding: EdgeInsets.symmetric(
              horizontal: 60 * uiScale,
              vertical: 40 * uiScale,
            ),
            child: Stack(
              children: [
                // 居中单行歌词
                Center(
                  child: PlayerImmersiveLyricsPanel(
                    lyrics: lyrics,
                    currentLyricIndex: currentLyricIndex,
                    showTranslation: showTranslation,
                    lyricState: lyricState,
                    uiScale: uiScale,
                    reducedEffects: reducedEffects,
                  ),
                ),

                // 左下角：歌曲信息 (放大)
                Positioned(
                  left: 0,
                  bottom: 0,
                  child: _buildSongInfo(context, track),
                ),

                // 右下角：控制按钮
                Positioned(
                  right: 0,
                  bottom: 0,
                  child: _buildControls(context, player),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMobileTopBar() {
    return Padding(
      padding: EdgeInsets.symmetric(
        horizontal: 16 * uiScale,
        vertical: 8 * uiScale,
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          // 返回按钮
          IconButton(
            icon: const Icon(Icons.keyboard_arrow_down, color: Colors.white),
            iconSize: 32 * uiScale,
            onPressed: onBackPressed,
            tooltip: '返回',
          ),
          // 更多设置按钮
          IconButton(
            icon: const Icon(Icons.more_vert, color: Colors.white),
            iconSize: 28 * uiScale,
            onPressed: onMorePressed,
            tooltip: '更多设置',
          ),
        ],
      ),
    );
  }

  Widget _buildSongInfo(BuildContext context, Track? track) {
    final player = PlayerService();
    final imageUrl = player.currentCoverUrl ?? '';
    final coverProvider = player.currentCoverImageProvider;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        // 专辑封面 (大幅放大)
        Container(
          width: 200 * uiScale,
          height: 200 * uiScale,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20 * uiScale),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.5),
                blurRadius: 40 * uiScale,
                offset: Offset(0, 15 * uiScale),
              ),
            ],
          ),
          clipBehavior: Clip.antiAlias,
          child: AnimatedSwitcher(
            duration: reducedEffects
                ? Duration.zero
                : const Duration(milliseconds: 600),
            switchInCurve: Curves.easeOut,
            switchOutCurve: Curves.easeIn,
            transitionBuilder: (Widget child, Animation<double> animation) {
              return FadeTransition(opacity: animation, child: child);
            },
            child: imageUrl.isNotEmpty
                ? Image(
                    key: ValueKey(imageUrl),
                    image:
                        coverProvider ??
                        NetworkImage(imageUrl) as ImageProvider,
                    fit: BoxFit.cover,
                    width: 200 * uiScale,
                    height: 200 * uiScale,
                  )
                : Container(
                    color: Colors.grey[900],
                    child: Icon(
                      Icons.music_note,
                      color: Colors.white54,
                      size: 80 * uiScale,
                    ),
                  ),
          ),
        ),
        SizedBox(width: 32 * uiScale),
        // 文本信息
        Padding(
          padding: EdgeInsets.only(bottom: 20 * uiScale),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                track?.name ?? '未知歌曲',
                style: TextStyle(
                  fontSize: 40 * uiScale,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                  letterSpacing: -0.5 * uiScale,
                  fontFamily: 'Microsoft YaHei',
                ),
              ),
              SizedBox(height: 8 * uiScale),
              Text(
                track?.artists ?? '未知歌手',
                style: TextStyle(
                  fontSize: 24 * uiScale,
                  color: Colors.white.withValues(alpha: 0.8),
                  fontWeight: FontWeight.w500,
                  fontFamily: 'Microsoft YaHei',
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildControls(BuildContext context, PlayerService player) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      mainAxisSize: MainAxisSize.min,
      children: [
        // 播放控制
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            // 循环模式
            _buildPlaybackModeButton(),
            SizedBox(width: 8 * uiScale),
            // 喜欢按钮
            if (player.currentTrack != null)
              _ImmersiveFavoriteButton(
                track: player.currentTrack!,
                uiScale: uiScale,
              ),
            SizedBox(width: 16 * uiScale),
            // 上一首
            IconButton(
              icon: const Icon(CupertinoIcons.backward_fill),
              color: Colors.white.withValues(alpha: 0.9),
              iconSize: 32 * uiScale,
              onPressed: player.hasPrevious ? player.playPrevious : null,
            ),
            SizedBox(width: 16 * uiScale),
            PlayerImmersivePlaybackButton(uiScale: uiScale),
            SizedBox(width: 16 * uiScale),
            // 下一首
            IconButton(
              icon: const Icon(CupertinoIcons.forward_fill),
              color: Colors.white.withValues(alpha: 0.9),
              iconSize: 32 * uiScale,
              onPressed: player.hasNext ? player.playNext : null,
            ),
          ],
        ),
        SizedBox(height: 24 * uiScale),
        // 底部辅助控制
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            // 布局快速切换按钮
            _buildLayoutToggleButton(),
            SizedBox(width: 24 * uiScale),
            // 音量按钮
            IconButton(
              icon: const Icon(CupertinoIcons.speaker_2_fill),
              color: Colors.white.withValues(alpha: 0.7),
              iconSize: 22 * uiScale,
              onPressed: onVolumeControlPressed,
              tooltip: '音量调节',
            ),
            SizedBox(width: 8 * uiScale),
            // 播放队列按钮
            IconButton(
              icon: const Icon(Icons.format_list_bulleted_rounded),
              color: Colors.white.withValues(alpha: 0.7),
              iconSize: 24 * uiScale,
              onPressed: onPlaylistPressed,
              tooltip: '播放队列',
            ),
          ],
        ),
        SizedBox(height: 20 * uiScale),
        // 进度条微缩版或者音量？
        // 这里根据用户需求，先只放控制按钮。
      ],
    );
  }

  Widget _buildPlaybackModeButton() {
    return ListenableBuilder(
      listenable: PlaybackModeService(),
      builder: (context, _) {
        final mode = PlaybackModeService().currentMode;
        IconData icon;
        switch (mode) {
          case PlaybackMode.sequential:
            icon = Icons.arrow_forward_rounded;
            break;
          case PlaybackMode.loopAll:
            icon = Icons.repeat_rounded;
            break;
          case PlaybackMode.repeatOne:
            icon = Icons.repeat_one_rounded;
            break;
          case PlaybackMode.shuffle:
            icon = Icons.shuffle_rounded;
            break;
        }
        return IconButton(
          icon: Icon(icon),
          color: Colors.white.withValues(alpha: 0.7),
          iconSize: 24 * uiScale,
          onPressed: () => PlaybackModeService().toggleMode(),
          tooltip: PlaybackModeService().getModeName(),
        );
      },
    );
  }

  Widget _buildLayoutToggleButton() {
    return ListenableBuilder(
      listenable: LyricStyleService(),
      builder: (context, _) {
        final currentStyle = LyricStyleService().currentStyle;
        return InkWell(
          onTap: () {
            // 在流体云和沉浸样式之间切换
            final nextStyle = currentStyle == LyricStyle.immersive
                ? LyricStyle.fluidCloud
                : LyricStyle.immersive;
            LyricStyleService().setStyle(nextStyle);
          },
          borderRadius: BorderRadius.circular(20 * uiScale),
          child: Container(
            padding: EdgeInsets.symmetric(
              horizontal: 16 * uiScale,
              vertical: 8 * uiScale,
            ),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(20 * uiScale),
              border: Border.all(color: Colors.white.withValues(alpha: 0.2)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.style_rounded,
                  color: Colors.white,
                  size: 16 * uiScale,
                ),
                SizedBox(width: 8 * uiScale),
                Text(
                  currentStyle == LyricStyle.immersive ? '沉浸样式' : '流体云样式',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 13 * uiScale,
                    fontFamily: 'Microsoft YaHei',
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// 沉浸式单行歌词面板
class PlayerImmersiveLyricsPanel extends StatefulWidget {
  final List<LyricLine> lyrics;
  final int currentLyricIndex;
  final bool showTranslation;
  final LyricLoadState lyricState;
  final double uiScale;
  final bool reducedEffects;

  const PlayerImmersiveLyricsPanel({
    super.key,
    required this.lyrics,
    required this.currentLyricIndex,
    required this.showTranslation,
    required this.lyricState,
    this.uiScale = 1.0,
    this.reducedEffects = false,
  });

  @override
  State<PlayerImmersiveLyricsPanel> createState() =>
      _PlayerImmersiveLyricsPanelState();
}

class _PlayerImmersiveLyricsPanelState extends State<PlayerImmersiveLyricsPanel>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  // 数据快照
  LyricLine? _incomingLine;
  LyricLine? _outgoingLine;

  // 动画曲线
  static const Curve _curve = Cubic(0.44, 0.05, 0.55, 0.95);

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );

    // 初始化当前行
    _updateIncomingLine(false);
    _controller.value = 1.0; // 初始状态直接显示
  }

  @override
  void didUpdateWidget(PlayerImmersiveLyricsPanel oldWidget) {
    super.didUpdateWidget(oldWidget);

    //只在歌词索引变化时触发切换动画
    if (widget.currentLyricIndex != oldWidget.currentLyricIndex) {
      _outgoingLine = _incomingLine;
      _updateIncomingLine(true);
      if (widget.reducedEffects) {
        _outgoingLine = null;
        _controller.value = 1.0;
      } else {
        _controller.forward(from: 0.0);
      }
    }
    // 如果仅仅是 showTranslation 变化或 lyrics 内容刷新但索引没变（如修正时间），
    // 更新 incomingLine 但不触发动画，或者根据需求...
    // 这里简单起见，且为了响应翻译切换，我们实时从 build 中读取配置，
    // _incomingLine 仅用于存储"当前是哪一行"的引用以防止 index 越界。
    // 但是，为了让 outgoingLine 能保持旧状态（比如旧的翻译设置），我们应该在 snapshot 时不仅仅存 LyricLine 对象，
    // 还需要知道当时的显示状态？
    // 实际上 LyricLine 对象本身包含了 text 和 translation。
    // showTranslation 是外部传入的开关。
    else if (widget.showTranslation != oldWidget.showTranslation) {
      // 配置变化，强制刷新当前行引用（虽然不用动画）
      _updateIncomingLine(false);
    }
  }

  void _updateIncomingLine(bool animate) {
    if (widget.lyrics.isNotEmpty &&
        widget.currentLyricIndex >= 0 &&
        widget.currentLyricIndex < widget.lyrics.length) {
      _incomingLine = widget.lyrics[widget.currentLyricIndex];
    } else {
      _incomingLine = null;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.lyrics.isEmpty) {
      final message = widget.lyricState.displayText;
      return Text(
        message,
        style: TextStyle(color: Colors.white54, fontSize: 24 * widget.uiScale),
      );
    }

    // 字体服务
    final fontFamily =
        LyricFontService().currentFontFamily ?? 'Microsoft YaHei';

    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        final t = _curve.transform(_controller.value);

        return Stack(
          alignment: Alignment.center,
          children: [
            // Outgoing Line (Exit animation)
            // 弹出动画：向上飞出 + 放大 + 渐隐 (Splash Out)
            if (_outgoingLine != null && _controller.value < 1.0)
              _buildOutgoingLine(_outgoingLine!, fontFamily, t),

            // Incoming Line (Enter animation)
            // 屏幕两侧将中间聚集
            if (_incomingLine != null)
              _buildIncomingLine(_incomingLine!, fontFamily, t),
          ],
        );
      },
    );
  }

  /// 构建出场动画：溅出效果 (Splash Out)
  Widget _buildOutgoingLine(LyricLine line, String fontFamily, double t) {
    // 动画参数
    final double opacity = (1.0 - t).clamp(0.0, 1.0);
    // 位移：向上飘 (0 -> -50)
    final double offsetY = -50.0 * widget.uiScale * t;
    // 缩放：放大 (1.0 -> 1.3)
    final double scale = 1.0 + (0.3 * t);
    // 模糊：变模糊 (0 -> 20)
    final double blur = 20.0 * widget.uiScale * t;

    return Opacity(
      opacity: opacity,
      child: ImageFiltered(
        imageFilter: ImageFilter.blur(sigmaX: blur, sigmaY: blur),
        child: Transform(
          transform: Matrix4.identity()
            ..translateByDouble(0.0, offsetY, 0.0, 1.0)
            ..scaleByDouble(scale, scale, 1.0, 1.0),
          alignment: Alignment.center,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  line.text,
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: _buildTextStyle(fontFamily, 64 * widget.uiScale),
                ),
              ),
              if (widget.showTranslation &&
                  line.translation != null &&
                  line.translation!.isNotEmpty)
                Padding(
                  padding: EdgeInsets.only(top: 24 * widget.uiScale),
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      line.translation!,
                      textAlign: TextAlign.center,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: _buildTextStyle(
                        fontFamily,
                        32 * widget.uiScale,
                        isTranslation: true,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  /// 构建进场动画：底部滑入 + 横向展开
  Widget _buildIncomingLine(LyricLine line, String fontFamily, double t) {
    // 动画参数
    final double opacity = t.clamp(0.0, 1.0);
    // 位移：从下往上 (40 -> 0)
    final double offsetY = 40.0 * widget.uiScale * (1 - t);
    // 缩放：横向拉伸 (0.9 -> 1.0)
    final double scaleX = 0.9 + (0.1 * t);
    // 模糊：渐渐清晰 (10 -> 0)
    final double blur = 10.0 * widget.uiScale * (1 - t);

    return Opacity(
      opacity: opacity,
      child: ImageFiltered(
        imageFilter: ImageFilter.blur(sigmaX: blur, sigmaY: blur),
        child: Transform(
          transform: Matrix4.identity()
            ..translateByDouble(0.0, offsetY, 0.0, 1.0)
            ..scaleByDouble(scaleX, 1.0, 1.0, 1.0),
          alignment: Alignment.center,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  line.text,
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: _buildTextStyle(fontFamily, 64 * widget.uiScale),
                ),
              ),
              if (widget.showTranslation &&
                  line.translation != null &&
                  line.translation!.isNotEmpty)
                Padding(
                  padding: EdgeInsets.only(top: 24 * widget.uiScale),
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      line.translation!,
                      textAlign: TextAlign.center,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: _buildTextStyle(
                        fontFamily,
                        32 * widget.uiScale,
                        isTranslation: true,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  TextStyle _buildTextStyle(
    String fontFamily,
    double size, {
    bool isTranslation = false,
  }) {
    return TextStyle(
      fontSize: size,
      fontWeight: isTranslation ? FontWeight.w600 : FontWeight.w900,
      color: isTranslation ? Colors.white.withValues(alpha: 0.7) : Colors.white,
      fontFamily: fontFamily,
      letterSpacing: isTranslation ? 0 : -1,
      shadows: [
        Shadow(
          color: Colors.black.withValues(alpha: 0.5),
          blurRadius: 30 * widget.uiScale,
          offset: Offset(0, 8 * widget.uiScale),
        ),
      ],
    );
  }
}

class _ImmersiveFavoriteButton extends StatefulWidget {
  final Track track;
  final double uiScale;
  const _ImmersiveFavoriteButton({required this.track, this.uiScale = 1.0});

  @override
  State<_ImmersiveFavoriteButton> createState() =>
      _ImmersiveFavoriteButtonState();
}

class _ImmersiveFavoriteButtonState extends State<_ImmersiveFavoriteButton> {
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
  void didUpdateWidget(_ImmersiveFavoriteButton oldWidget) {
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
    final RenderBox overlay =
        Overlay.of(context).context.findRenderObject() as RenderBox;

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
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.6),
              fontSize: 12,
            ),
          ),
        ),
        const PopupMenuDivider(),
        PopupMenuItem<String>(
          value: 'remove',
          child: Row(
            children: [
              Icon(
                Icons.remove_circle_outline,
                color: Colors.redAccent,
                size: 18,
              ),
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
        if (!context.mounted) return;
        PlayerDialogs.showAddToPlaylist(context, widget.track);
        // 添加后刷新
        // 由于 dialog 是异步的，这里可能无法立即刷新，需要监听 PlaylistService 或回调
        // 简单处理：延迟一点刷新
        Future.delayed(const Duration(seconds: 1), _checkIfInPlaylist);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return SizedBox(
        width: 36 * widget.uiScale,
        height: 36 * widget.uiScale,
        child: Padding(
          padding: EdgeInsets.all(8.0 * widget.uiScale),
          child: CircularProgressIndicator(
            strokeWidth: 2 * widget.uiScale,
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
          PlayerDialogs.showAddToPlaylist(context, widget.track).then((_) {
            // 简单处理：延迟一点刷新，确保添加完成
            Future.delayed(
              const Duration(milliseconds: 500),
              _checkIfInPlaylist,
            );
          });
        }
      },
      child: Tooltip(
        message: tooltip,
        child: Container(
          width: 36 * widget.uiScale,
          height: 36 * widget.uiScale,
          alignment: Alignment.center,
          color: Colors.transparent, // 增加热区
          child: Icon(
            _isInPlaylist ? CupertinoIcons.heart_fill : CupertinoIcons.heart,
            color: _isInPlaylist
                ? Colors.redAccent
                : Colors.white.withValues(alpha: 0.9),
            size: 32 * widget.uiScale,
          ),
        ),
      ),
    );
  }
}
