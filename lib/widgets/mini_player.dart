import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:fluent_ui/fluent_ui.dart' as fluent;
import 'package:cached_network_image/cached_network_image.dart';
import '../services/player_service.dart';
import '../pages/player_page.dart';
import '../services/playlist_queue_service.dart';
import '../services/play_history_service.dart';
import '../services/system_volume_service.dart';
import '../services/playback_mode_service.dart';
import '../models/track.dart';
import '../utils/theme_manager.dart';
import '../utils/image_utils.dart';
import '../utils/dynamic_color_utils.dart';
import 'track_action_menu.dart';

/// 迷你播放器组件（底部播放栏）
class MiniPlayer extends StatefulWidget {
  final bool transparent;
  const MiniPlayer({super.key, this.transparent = false});

  @override
  State<MiniPlayer> createState() => _MiniPlayerState();
}

class _MiniPlayerState extends State<MiniPlayer> {
  bool _isSeeking = false;   // 拖拽 seek 中，屏蔽外层 onTap 跳全屏
  double? _seekRatio;         // 拖拽时的临时进度比例
  DateTime? _lastSeekGestureAt;
  int? _activeSeekPointer;
  static bool _showRemainingTime = true; // 默认显示剩余时间（可点击切换总时长/剩余时间）

  bool get _isCupertino => ThemeManager().isCupertinoFramework;

  /// iOS Cupertino 风格的控制按钮
  Widget _buildCenterControlsCupertino(
    PlayerService player,
    BuildContext context, {
    bool hideSkip = false,
    bool compact = false,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final double skipIconSize = compact ? 20 : 24;
    final double playIconSize = compact ? 24 : 28;
    final EdgeInsets buttonPadding =
        compact ? const EdgeInsets.all(4) : const EdgeInsets.all(8);

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (!hideSkip)
          CupertinoButton(
            padding: buttonPadding,
            minimumSize: Size.zero,
            onPressed: player.hasPrevious ? () => player.playPrevious() : null,
            child: Icon(
              CupertinoIcons.backward_fill,
              size: skipIconSize,
              color: player.hasPrevious
                  ? (isDark ? CupertinoColors.white : CupertinoColors.black)
                  : CupertinoColors.systemGrey,
            ),
          ),
        if (player.isLoading)
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 8.0),
            child: CupertinoActivityIndicator(radius: 14),
          )
        else
          CupertinoButton(
            padding: buttonPadding,
            minimumSize: Size.zero,
            onPressed: () => player.togglePlayPause(),
            child: Icon(
              player.isPlaying ? CupertinoIcons.pause_fill : CupertinoIcons.play_fill,
              size: playIconSize,
              color: DynamicColorUtils.resolveAccent(
                player.themeColorNotifier.value,
                Theme.of(context).colorScheme,
                isDark: isDark,
              ),
            ),
          ),
        if (!hideSkip)
          CupertinoButton(
            padding: buttonPadding,
            minimumSize: Size.zero,
            onPressed: player.hasNext ? () => player.playNext() : null,
            child: Icon(
              CupertinoIcons.forward_fill,
              size: skipIconSize,
              color: player.hasNext
                  ? (isDark ? CupertinoColors.white : CupertinoColors.black)
                  : CupertinoColors.systemGrey,
            ),
          ),
      ],
    );
  }

  Widget _buildCenterControlsFluent(
    PlayerService player,
    BuildContext context, {
    bool hideSkip = false,
    bool compact = false,
  }) {
    final double skipIconSize = compact ? 18 : 20;
    final double playIconSize = compact ? 20 : 22;
    final theme = fluent.FluentTheme.of(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (!hideSkip)
          fluent.IconButton(
            icon: Icon(Icons.skip_previous_rounded, size: skipIconSize, color: theme.resources.textFillColorPrimary),
            onPressed: player.hasPrevious ? () => player.playPrevious() : null,
          ),
        if (player.isLoading)
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 8.0),
            child: SizedBox(width: 22, height: 22, child: fluent.ProgressRing(strokeWidth: 3)),
          )
        else
          fluent.IconButton(
            icon: Icon(player.isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
                size: playIconSize, color: theme.accentColor.defaultBrushFor(theme.brightness)),
            onPressed: () => player.togglePlayPause(),
          ),
        if (!hideSkip)
          fluent.IconButton(
            icon: Icon(Icons.skip_next_rounded, size: skipIconSize, color: theme.resources.textFillColorPrimary),
            onPressed: player.hasNext ? () => player.playNext() : null,
          ),
      ],
    );
  }


  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: PlayerService(),
      builder: (context, child) {
        final player = PlayerService();
        final track = player.currentTrack;
        final song = player.currentSong;

        final mediaQuery = MediaQuery.of(context);
        final bool isCompactWidth = mediaQuery.size.width < 600;
        final bool hasContent = track != null || song != null;

        if (!hasContent) {
          return const SizedBox.shrink();
        }

        final colorScheme = Theme.of(context).colorScheme;
        final expanded = _buildExpandedPlayer(
          context: context,
          player: player,
          song: song,
          track: track,
          colorScheme: colorScheme,
          isCompactWidth: isCompactWidth,
        );

        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          excludeFromSemantics: true,
          onTap: () {
            if (_isSeeking || _shouldBlockOpenFullPlayerTap()) return;
            _openFullPlayer(context);
          },
          child: expanded,
        );
      },
    );
  }

  void _openFullPlayer(BuildContext context) {
    Navigator.of(context).push(
      PageRouteBuilder(
        opaque: false,
        barrierColor: Colors.transparent,
        maintainState: true,
        pageBuilder: (context, animation, secondaryAnimation) => const PlayerPage(),
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          const begin = Offset(0.0, 1.0);
          const end = Offset.zero;
          const curve = Curves.easeOutCubic;

          final tween = Tween(begin: begin, end: end).chain(CurveTween(curve: curve));
          final offsetAnimation = animation.drive(tween);

          return SlideTransition(
            position: offsetAnimation,
            child: child,
          );
        },
        transitionDuration: const Duration(milliseconds: 300),
        reverseTransitionDuration: const Duration(milliseconds: 250),
      ),
    );
  }

  bool _shouldBlockOpenFullPlayerTap() {
    final t = _lastSeekGestureAt;
    if (t == null) return false;
    return DateTime.now().difference(t) < const Duration(milliseconds: 220);
  }

  void _markSeekGesture() {
    _lastSeekGestureAt = DateTime.now();
  }

  void _onSeekStart(PlayerService player, double width, double dx) {
    if (width <= 0 || player.duration.inMilliseconds <= 0) return;
    _markSeekGesture();
    setState(() {
      _isSeeking = true;
      _seekRatio = (dx / width).clamp(0.0, 1.0);
    });
  }

  void _onSeekUpdate(PlayerService player, double width, double dx) {
    if (width <= 0 || player.duration.inMilliseconds <= 0) return;
    _markSeekGesture();
    setState(() {
      _seekRatio = (dx / width).clamp(0.0, 1.0);
    });
  }

  void _onSeekEnd(PlayerService player) {
    _markSeekGesture();
    final ratio = _seekRatio;
    if (ratio != null && player.duration.inMilliseconds > 0) {
      final targetMs = (player.duration.inMilliseconds * ratio).round();
      player.seek(Duration(milliseconds: targetMs));
    }
    setState(() {
      _isSeeking = false;
      _seekRatio = null;
    });
  }

  void _onSeekCancel(PlayerService player) {
    _markSeekGesture();
    setState(() {
      _isSeeking = false;
      _seekRatio = null;
    });
  }

  Widget _buildSeekableProgressBar({
    required PlayerService player,
    required Widget child,
    double hitHeight = 24,
  }) {
    return SizedBox(
      height: hitHeight,
      child: LayoutBuilder(
        builder: (context, constraints) => Listener(
          behavior: HitTestBehavior.opaque,
          onPointerDown: (event) {
            _activeSeekPointer = event.pointer;
            _onSeekStart(player, constraints.maxWidth, event.localPosition.dx);
          },
          onPointerMove: (event) {
            if (_activeSeekPointer != event.pointer) return;
            _onSeekUpdate(player, constraints.maxWidth, event.localPosition.dx);
          },
          onPointerUp: (event) {
            if (_activeSeekPointer != event.pointer) return;
            _activeSeekPointer = null;
            _onSeekEnd(player);
          },
          onPointerCancel: (event) {
            if (_activeSeekPointer != event.pointer) return;
            _activeSeekPointer = null;
            _onSeekCancel(player);
          },
          child: Center(child: child),
        ),
      ),
    );
  }

  Widget _buildExpandedPlayer({
    required BuildContext context,
    required PlayerService player,
    required dynamic song,
    required dynamic track,
    required ColorScheme colorScheme,
    required bool isCompactWidth,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final dynamicAccent = DynamicColorUtils.resolveAccent(
      player.themeColorNotifier.value,
      colorScheme,
      isDark: isDark,
    );
    final dynamicAmbient = DynamicColorUtils.resolveAmbient(
      player.themeColorNotifier.value,
      colorScheme,
      isDark: isDark,
    );
    final progressBarActiveColor = dynamicAccent;
    final bool useAlignedLayout = !isCompactWidth;

    if (!useAlignedLayout) {
      final decoration = widget.transparent
          ? const BoxDecoration(color: Colors.transparent)
          : BoxDecoration(
              color: colorScheme.surface.withValues(alpha: isDark ? 0.88 : 0.96),
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  colorScheme.surface.withValues(alpha: isDark ? 0.92 : 0.97),
                  dynamicAmbient.withValues(alpha: isDark ? 0.16 : 0.08),
                  colorScheme.surface.withValues(alpha: isDark ? 0.88 : 0.94),
                ],
              ),
              borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.08),
                  blurRadius: 16,
                  offset: const Offset(0, -4),
                ),
              ],
              border: Border(
                top: BorderSide(
                  color: dynamicAccent.withValues(alpha: isDark ? 0.28 : 0.35),
                  width: 1,
                ),
              ),
            );

      return Container(
        key: const ValueKey('mini_expanded'),
        height: 66,
        margin: EdgeInsets.zero,
        clipBehavior: Clip.antiAlias,
        decoration: decoration,
        child: Column(
          children: [
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 5, 12, 0),
                child: Row(
                  children: [
                    _buildCover(song, track, colorScheme, size: 40),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _buildSongInfo(context),
                    ),
                    _buildAdaptiveControls(
                      player,
                      context,
                      colorScheme,
                      hideSkip: true,
                      compact: true,
                    ),
                    IconButton(
                      icon: Icon(
                        Icons.skip_next_rounded,
                        color: player.hasNext ? colorScheme.onSurface : colorScheme.onSurface.withValues(alpha: 0.4),
                        size: 24,
                      ),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints.tightFor(width: 34, height: 34),
                      onPressed: player.hasNext ? () => player.playNext() : null,
                      tooltip: '下一首',
                    ),
                    const SizedBox(width: 2),
                    _buildQueueButton(context, colorScheme, compact: true),
                  ],
                ),
              ),
            ),
            // Middle divider progress line with total duration on the far right
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
              child: AnimatedBuilder(
                animation: Listenable.merge([player.positionNotifier, player]),
                builder: (context, _) {
                  final position = player.positionNotifier.value;
                  // Authoritative duration, with fallback to lyric timestamps
                  Duration duration = player.duration;
                  if (duration.inSeconds <= 0 && player.lyricSnapshot != null && player.lyricSnapshot!.lines.isNotEmpty) {
                    final lastLine = player.lyricSnapshot!.lines.last;
                    duration = lastLine.startTime + (lastLine.lineDuration ?? const Duration(seconds: 4));
                  }
                  final progress = _seekRatio ??
                      (duration.inMilliseconds > 0
                          ? (position.inMilliseconds / duration.inMilliseconds).clamp(0.0, 1.0)
                          : 0.0);
                  // 计算剩余时间与总时长（默认显示倒计时剩余时间，点击可在剩余时间与总时长间切换）
                  final remaining = duration > position ? duration - position : Duration.zero;
                  final String durationStr = duration.inSeconds > 0
                      ? (_showRemainingTime ? '-${_formatDuration(remaining)}' : _formatDuration(duration))
                      : '--:--';
                  return Row(
                    children: [
                      Expanded(
                        child: _buildSeekableProgressBar(
                          player: player,
                          hitHeight: 12,
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(1.5),
                            child: LinearProgressIndicator(
                              value: progress,
                              minHeight: 2.5,
                              backgroundColor: colorScheme.onSurface.withValues(alpha: 0.08),
                              valueColor: AlwaysStoppedAnimation<Color>(
                                progressBarActiveColor,
                              ),
                            ),
                          ),
                        ),
                      ),
                      GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: () {
                          setState(() {
                            _showRemainingTime = !_showRemainingTime;
                          });
                        },
                        child: Padding(
                          padding: const EdgeInsets.only(left: 10),
                          child: Text(
                            durationStr,
                            style: TextStyle(
                              fontSize: 10.5,
                              fontWeight: FontWeight.w700,
                              color: dynamicAccent,
                            ),
                          ),
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
          ],
        ),
      );
    }

    final isMobile = Platform.isAndroid || Platform.isIOS;

    if (isMobile || widget.transparent) {
      return Container(
        key: const ValueKey('mini_expanded_glass'),
        margin: const EdgeInsets.fromLTRB(8, 0, 14, 8),
        constraints: const BoxConstraints(minHeight: 68),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: isDark ? 0.35 : 0.08),
              blurRadius: 18,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(20),
          child: Stack(
            children: [
              Positioned.fill(
                child: BackdropFilter(
                  filter: ui.ImageFilter.blur(sigmaX: 25, sigmaY: 25),
                  child: const SizedBox.shrink(),
                ),
              ),
              Positioned.fill(
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 400),
                  curve: Curves.easeOutCubic,
                  decoration: BoxDecoration(
                    color: colorScheme.surface.withValues(alpha: isDark ? 0.82 : 0.88),
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        colorScheme.surface.withValues(alpha: isDark ? 0.88 : 0.92),
                        dynamicAmbient.withValues(alpha: isDark ? 0.16 : 0.08),
                        dynamicAmbient.withValues(alpha: isDark ? 0.06 : 0.03),
                        colorScheme.surface.withValues(alpha: isDark ? 0.84 : 0.88),
                      ],
                    ),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: dynamicAccent.withValues(alpha: isDark ? 0.30 : 0.38),
                      width: 1.0,
                    ),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
                child: Row(
                  children: [
                    _buildCover(song, track, colorScheme, size: 42),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _buildSongInfo(context, singleLine: true),
                          const SizedBox(height: 4),
                          _buildAlignedProgressRow(player, colorScheme),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _buildAdaptiveControls(
                          player,
                          context,
                          colorScheme,
                          hideSkip: false,
                          compact: true,
                        ),
                        const SizedBox(width: 4),
                        _buildPlaybackModeButton(context, colorScheme, compact: true),
                        const SizedBox(width: 2),
                        _buildVolumeButton(
                          context,
                          colorScheme,
                          player,
                          compact: true,
                        ),
                        const SizedBox(width: 2),
                        _buildQueueButton(context, colorScheme, compact: true),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Container(
      key: const ValueKey('mini_expanded'),
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      constraints: const BoxConstraints(minHeight: 80),
      decoration: BoxDecoration(color: colorScheme.surfaceContainerHighest),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Row(
          children: [
            _buildCover(song, track, colorScheme, size: 44),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildSongInfo(context, singleLine: true),
                  const SizedBox(height: 6),
                  _buildAlignedProgressRow(player, colorScheme),
                ],
              ),
            ),
            const SizedBox(width: 16),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _buildAdaptiveControls(
                  player,
                  context,
                  colorScheme,
                  hideSkip: false,
                  compact: true,
                ),
                const SizedBox(width: 6),
                _buildPlaybackModeButton(context, colorScheme, compact: true),
                const SizedBox(width: 4),
                _buildVolumeButton(
                  context,
                  colorScheme,
                  player,
                  compact: true,
                ),
                const SizedBox(width: 4),
                _buildQueueButton(context, colorScheme, compact: true),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildQueueButton(
    BuildContext context,
    ColorScheme colorScheme, {
    bool compact = false,
  }) {
    if (ThemeManager().isFluentFramework) {
      final theme = fluent.FluentTheme.of(context);
      return fluent.IconButton(
        icon: Icon(
          Icons.queue_music_rounded,
          color: theme.resources.textFillColorPrimary,
          size: compact ? 20 : 22,
        ),
        onPressed: () => _showQueueSheet(context),
      );
    }
    if (_isCupertino) {
      return CupertinoButton(
        padding: compact ? const EdgeInsets.all(2) : const EdgeInsets.all(6),
        minimumSize: Size.zero,
        onPressed: () => _showQueueSheet(context),
        child: Icon(
          CupertinoIcons.music_note_list,
          color: CupertinoColors.activeBlue,
          size: compact ? 20 : 22,
        ),
      );
    }
    return IconButton(
      icon: Icon(
        Icons.queue_music_rounded,
        color: colorScheme.onSurface,
        size: compact ? 20 : 22,
      ),
      padding: EdgeInsets.zero,
      constraints: compact
          ? const BoxConstraints.tightFor(width: 32, height: 32)
          : null,
      tooltip: '播放队列',
      onPressed: () => _showQueueSheet(context),
    );
  }

  Widget _buildPlaybackModeButton(
    BuildContext context,
    ColorScheme colorScheme, {
    bool compact = false,
  }) {
    return AnimatedBuilder(
      animation: PlaybackModeService(),
      builder: (context, _) {
        final modeService = PlaybackModeService();
        final icon = modeService.getModeIcon();

        if (ThemeManager().isFluentFramework) {
          final theme = fluent.FluentTheme.of(context);
          return fluent.IconButton(
            icon: Icon(
              icon,
              color: theme.resources.textFillColorPrimary,
              size: compact ? 18 : 20,
            ),
            onPressed: () {
              modeService.toggleMode();
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('播放模式: ${modeService.getModeName()}'),
                  duration: const Duration(seconds: 1),
                ),
              );
            },
          );
        }
        if (_isCupertino) {
          return CupertinoButton(
            padding: compact ? const EdgeInsets.all(2) : const EdgeInsets.all(6),
            minimumSize: Size.zero,
            onPressed: () {
              modeService.toggleMode();
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('播放模式: ${modeService.getModeName()}'),
                  duration: const Duration(seconds: 1),
                ),
              );
            },
            child: Icon(
              icon,
              color: CupertinoColors.activeBlue,
              size: compact ? 18 : 20,
            ),
          );
        }
        return IconButton(
          icon: Icon(
            icon,
            color: colorScheme.onSurface,
            size: compact ? 18 : 20,
          ),
          padding: EdgeInsets.zero,
          constraints: compact
              ? const BoxConstraints.tightFor(width: 32, height: 32)
              : null,
          tooltip: modeService.getModeName(),
          onPressed: () {
            modeService.toggleMode();
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('播放模式: ${modeService.getModeName()}'),
                duration: const Duration(seconds: 1),
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildVolumeButton(
    BuildContext context,
    ColorScheme colorScheme,
    PlayerService player, {
    bool compact = false,
  }) {
    if (ThemeManager().isFluentFramework) {
      final theme = fluent.FluentTheme.of(context);
      return fluent.IconButton(
        icon: Icon(
          _volumeIcon(player.volume),
          color: theme.resources.textFillColorPrimary,
          size: compact ? 20 : 22,
        ),
        onPressed: () => _showVolumeDialog(context, player),
      );
    }
    if (_isCupertino) {
      return CupertinoButton(
        padding: compact ? const EdgeInsets.all(2) : const EdgeInsets.all(6),
        minimumSize: Size.zero,
        onPressed: () => _showVolumeDialog(context, player),
        child: Icon(
          _volumeIconCupertino(player.volume),
          color: CupertinoColors.activeBlue,
          size: compact ? 20 : 22,
        ),
      );
    }
    return Builder(
      builder: (buttonContext) {
        return IconButton(
          icon: Icon(
            _volumeIcon(player.volume),
            color: colorScheme.onSurface,
            size: compact ? 20 : 22,
          ),
          padding: EdgeInsets.zero,
          constraints: compact
              ? const BoxConstraints.tightFor(width: 32, height: 32)
              : null,
          tooltip: '音量',
          onPressed: () => _showVolumePopover(buttonContext, player),
        );
      },
    );
  }

  Future<void> _showVolumePopover(
    BuildContext context,
    PlayerService player,
  ) async {
    final overlay = Overlay.of(context);
    final renderBox = context.findRenderObject() as RenderBox?;
    final overlayBox = overlay.context.findRenderObject() as RenderBox?;
    if (renderBox == null || overlayBox == null) {
      await _showVolumeDialog(context, player);
      return;
    }

    final target = renderBox.localToGlobal(Offset.zero, ancestor: overlayBox);
    final size = renderBox.size;
    final screen = overlayBox.size;

    final systemService = SystemVolumeService();
    bool systemSupported = false;
    double systemTemp = 0.0;
    try {
      systemSupported = await systemService.isSupported();
      if (systemSupported) {
        systemTemp = (await systemService.getVolume()) ?? player.volume;
      }
    } catch (_) {}

    final double cardWidth = systemSupported ? 240 : 220;
    final double cardHeight = systemSupported ? 118 : 72;
    const double padding = 8;

    final double preferredTop = target.dy - cardHeight - padding;
    final double top = preferredTop >= 0
        ? preferredTop
        : target.dy + size.height + padding;
    final double left = (target.dx + size.width / 2 - cardWidth / 2)
        .clamp(padding, screen.width - cardWidth - padding);

    double appTemp = player.volume;
    if (!context.mounted) return;
    await showGeneralDialog(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Volume',
      barrierColor: Colors.transparent,
      pageBuilder: (context, animation, secondaryAnimation) {
        final colorScheme = Theme.of(context).colorScheme;
        return Stack(
          children: [
            Positioned(
              left: left,
              top: top,
              child: Material(
                color: Colors.transparent,
                child: Container(
                  width: cardWidth,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  decoration: BoxDecoration(
                    color: colorScheme.surface,
                    borderRadius: BorderRadius.circular(12),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.15),
                        blurRadius: 16,
                        offset: const Offset(0, 6),
                      ),
                    ],
                  ),
                  child: StatefulBuilder(
                    builder: (context, setLocal) {
                      if (!systemSupported) {
                        return Row(
                          children: [
                            Icon(
                              _volumeIcon(appTemp),
                              size: 18,
                              color: colorScheme.onSurfaceVariant,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Slider(
                                value: appTemp,
                                min: 0.0,
                                max: 1.0,
                                onChanged: (v) {
                                  setLocal(() => appTemp = v);
                                  player.setVolume(v);
                                },
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              '${(appTemp * 100).round()}%',
                              style: TextStyle(
                                fontSize: 12,
                                color: colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                        );
                      }

                      return Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Row(
                            children: [
                              Icon(
                                Icons.speaker,
                                size: 18,
                                color: colorScheme.onSurfaceVariant,
                              ),
                              const SizedBox(width: 6),
                              SizedBox(
                                width: 28,
                                child: Text(
                                  '系统',
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: colorScheme.onSurfaceVariant,
                                  ),
                                ),
                              ),
                              Expanded(
                                child: Slider(
                                  value: systemTemp,
                                  min: 0.0,
                                  max: 1.0,
                                  onChanged: (v) {
                                    setLocal(() => systemTemp = v);
                                    systemService.setVolume(v);
                                  },
                                ),
                              ),
                              const SizedBox(width: 8),
                              Text(
                                '${(systemTemp * 100).round()}%',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: colorScheme.onSurfaceVariant,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          Row(
                            children: [
                              Icon(
                                _volumeIcon(appTemp),
                                size: 18,
                                color: colorScheme.onSurfaceVariant,
                              ),
                              const SizedBox(width: 6),
                              SizedBox(
                                width: 28,
                                child: Text(
                                  '应用',
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: colorScheme.onSurfaceVariant,
                                  ),
                                ),
                              ),
                              Expanded(
                                child: Slider(
                                  value: appTemp,
                                  min: 0.0,
                                  max: 1.0,
                                  onChanged: (v) {
                                    setLocal(() => appTemp = v);
                                    player.setVolume(v);
                                  },
                                ),
                              ),
                              const SizedBox(width: 8),
                              Text(
                                '${(appTemp * 100).round()}%',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: colorScheme.onSurfaceVariant,
                                ),
                              ),
                            ],
                          ),
                        ],
                      );
                    },
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  /// 构建进度条
  /// 使用 ValueListenableBuilder 监听 positionNotifier 以实时更新进度

  Widget _buildAlignedProgressRow(PlayerService player, ColorScheme colorScheme) {
    final timeStyle = TextStyle(
      fontSize: 11,
      color: colorScheme.onSurfaceVariant,
    );
    return ValueListenableBuilder<Duration>(
      valueListenable: player.positionNotifier,
      builder: (context, position, child) {
        final effectiveDuration = _getEffectiveDuration(player);
        final progress = _seekRatio ??
            (effectiveDuration.inMilliseconds > 0
                ? position.inMilliseconds / effectiveDuration.inMilliseconds
                : 0.0);
        final displayPosition = _seekRatio != null
            ? Duration(milliseconds: (effectiveDuration.inMilliseconds * _seekRatio!).round())
            : position;
        final indicator = ThemeManager().isFluentFramework
            ? fluent.ProgressBar(
                value: (progress * 100).clamp(0.0, 100.0).toDouble(),
              )
            : ClipRRect(
                borderRadius: BorderRadius.circular(1.5),
                child: LinearProgressIndicator(
                  value: progress.clamp(0.0, 1.0),
                  minHeight: 3,
                  backgroundColor:
                      colorScheme.onSurface.withValues(alpha: 0.08),
                  valueColor:
                      AlwaysStoppedAnimation<Color>(colorScheme.primary),
                ),
              );

        final totalDurationStr = effectiveDuration.inSeconds > 0
            ? _formatDuration(effectiveDuration)
            : '--:--';

        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 10),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Text(_formatDuration(displayPosition), style: timeStyle),
              const SizedBox(width: 8),
              Expanded(
                child: _buildSeekableProgressBar(
                  player: player,
                  hitHeight: 24,
                  child: indicator,
                ),
              ),
              const SizedBox(width: 8),
              Text(totalDurationStr, style: timeStyle),
            ],
          ),
        );
      },
    );
  }

  /// 构建封面
  Widget _buildCover(dynamic song, dynamic track, ColorScheme colorScheme, {double size = 48}) {
    final imageUrl = _resolveCoverUrl(song, track);
    final provider = PlayerService().currentCoverImageProvider;

    return ClipRRect(
      borderRadius: BorderRadius.circular(6),
      child: provider != null
          ? Image(
              image: provider,
              width: size,
              height: size,
              fit: BoxFit.cover,
            )
          : imageUrl.isNotEmpty
              ? _optimizedCover(imageUrl, size, colorScheme)
              : Container(
                  width: size,
                  height: size,
                  color: colorScheme.surfaceContainerHighest,
                  child: Icon(
                    Icons.music_note,
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
    );
  }

  String _resolveCoverUrl(dynamic song, dynamic track) {
    final songPic = song?.pic;
    if (songPic is String && songPic.isNotEmpty) {
      return songPic;
    }

    final trackPic = track?.picUrl;
    if (trackPic is String && trackPic.isNotEmpty) {
      return trackPic;
    }

    return '';
  }

  Widget _optimizedCover(String imageUrl, double size, ColorScheme colorScheme) {
    final provider = PlayerService().currentCoverImageProvider;
    if (provider != null) {
      return Image(
        image: provider,
        width: size,
        height: size,
        fit: BoxFit.cover,
      );
    }
    // 检查是否为网络图片
    final isNetwork = imageUrl.startsWith('http') || imageUrl.startsWith('https');

    if (!isNetwork) {
      // 本地文件
      return Image.file(
        File(imageUrl),
        width: size,
        height: size,
        fit: BoxFit.cover,
        errorBuilder: (context, error, stackTrace) => Container(
          width: size,
          height: size,
          color: colorScheme.surfaceContainerHighest,
          child: Icon(
            Icons.music_note,
            color: colorScheme.onSurfaceVariant,
          ),
        ),
      );
    }

    return CachedNetworkImage(
      imageUrl: imageUrl,
      httpHeaders: getImageHeaders(imageUrl),
      width: size,
      height: size,
      memCacheWidth: 128,
      memCacheHeight: 128,
      fit: BoxFit.cover,
      placeholder: (context, url) => Container(
        width: size,
        height: size,
        color: colorScheme.surfaceContainerHighest,
        child: const Center(
          child: SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
      ),
      errorWidget: (context, url, error) => Container(
        width: 48,
        height: 48,
        color: colorScheme.surfaceContainerHighest,
        child: Icon(
          Icons.music_note,
          color: colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }

  /// 构建歌曲信息
  Widget _buildSongInfo(
    BuildContext context, {
    bool singleLine = false,
  }) {
    final player = PlayerService();
    final name = player.displayTitle.isNotEmpty ? player.displayTitle : '未知歌曲';
    final artist = player.displayArtist.isNotEmpty ? player.displayArtist : '未知艺术家';
    final bool isFluent = ThemeManager().isFluentFramework;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    if (singleLine) {
      final String artistText = artist.isNotEmpty ? ' · $artist' : '';
      if (isFluent) {
        final fluentTheme = fluent.FluentTheme.of(context);
        final primaryStyle = TextStyle(
          fontFamily: 'Microsoft YaHei',
          fontSize: 14,
          fontWeight: FontWeight.w500,
          color: fluentTheme.resources.textFillColorPrimary,
        );
        final secondaryStyle = TextStyle(
          fontFamily: 'Microsoft YaHei',
          fontSize: 12,
          color: fluentTheme.resources.textFillColorSecondary,
        );
        return Text.rich(
          TextSpan(
            text: name,
            style: primaryStyle,
            children: [
              if (artistText.isNotEmpty)
                TextSpan(text: artistText, style: secondaryStyle),
            ],
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        );
      }
      if (_isCupertino) {
        final primaryStyle = TextStyle(
          fontSize: 15,
          fontWeight: FontWeight.w600,
          color: isDark ? CupertinoColors.white : CupertinoColors.black,
        );
        final secondaryStyle = const TextStyle(
          fontSize: 13,
          color: CupertinoColors.systemGrey,
        );
        return Text.rich(
          TextSpan(
            text: name,
            style: primaryStyle,
            children: [
              if (artistText.isNotEmpty)
                TextSpan(text: artistText, style: secondaryStyle),
            ],
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        );
      }
      final theme = Theme.of(context);
      final primaryStyle = theme.textTheme.bodyMedium?.copyWith(
        fontWeight: FontWeight.w500,
        color: theme.colorScheme.onSurface,
      );
      final secondaryStyle = theme.textTheme.bodySmall?.copyWith(
        color: theme.colorScheme.onSurfaceVariant,
      );
      return Text.rich(
        TextSpan(
          text: name,
          style: primaryStyle,
          children: [
            if (artistText.isNotEmpty)
              TextSpan(text: artistText, style: secondaryStyle),
          ],
        ),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      );
    }

    // Fluent UI 主题下使用微软雅黑字体
    if (isFluent) {
      final fluentTheme = fluent.FluentTheme.of(context);
      return Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            name,
            style: TextStyle(
              fontFamily: 'Microsoft YaHei',
              fontSize: 14,
              fontWeight: FontWeight.w500,
              color: fluentTheme.resources.textFillColorPrimary,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 2),
          Text(
            artist,
            style: TextStyle(
              fontFamily: 'Microsoft YaHei',
              fontSize: 12,
              color: fluentTheme.resources.textFillColorSecondary,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      );
    }

    // iOS Cupertino 风格
    if (_isCupertino) {
      return Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            name,
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: isDark ? CupertinoColors.white : CupertinoColors.black,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 2),
          Text(
            artist,
            style: TextStyle(
              fontSize: 13,
              color: CupertinoColors.systemGrey,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      );
    }

    // Material Design 主题
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          name,
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
            fontWeight: FontWeight.w600,
            fontSize: 14,
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        const SizedBox(height: 2),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 3.5, vertical: 0.5),
              margin: const EdgeInsets.only(right: 5),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(3),
                border: Border.all(
                  color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.28),
                  width: 0.6,
                ),
              ),
              child: Text(
                'SQ',
                style: TextStyle(
                  fontSize: 8.5,
                  fontWeight: FontWeight.w800,
                  color: Theme.of(context).colorScheme.primary,
                  height: 1.1,
                ),
              ),
            ),
            Flexible(
              child: Text(
                artist,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                  fontSize: 12,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ],
    );
  }

  /// 自适应控制按钮（根据主题选择）
  Widget _buildAdaptiveControls(
    PlayerService player,
    BuildContext context,
    ColorScheme colorScheme, {
    bool hideSkip = false,
    bool compact = false,
  }) {
    if (ThemeManager().isFluentFramework) {
      return _buildCenterControlsFluent(
        player,
        context,
        hideSkip: hideSkip,
        compact: compact,
      );
    }
    if (_isCupertino) {
      return _buildCenterControlsCupertino(
        player,
        context,
        hideSkip: hideSkip,
        compact: compact,
      );
    }
    return _buildCenterControls(
      player,
      colorScheme,
      hideSkip: hideSkip,
      compact: compact,
    );
  }

  /// 中间控制（上一首/播放暂停/下一首）- Material 风格
  Widget _buildCenterControls(
    PlayerService player,
    ColorScheme colorScheme, {
    bool hideSkip = false,
    bool compact = false,
  }) {
    final double skipIconSize = compact ? 22 : 28;
    final double playIconSize = compact ? 20 : 24;
    final double skipButtonSize = compact ? 32 : 40;
    final double playButtonSize = compact ? 36 : 44;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final activeColor = DynamicColorUtils.resolveAccent(
      player.themeColorNotifier.value,
      colorScheme,
      isDark: isDark,
    );
    final iconColor = colorScheme.onSurface;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (!hideSkip)
        IconButton(
          icon: Icon(
            Icons.skip_previous_rounded,
            color: player.hasPrevious ? iconColor : iconColor.withValues(alpha: 0.5),
            size: skipIconSize,
          ),
          padding: EdgeInsets.zero,
          constraints:
              BoxConstraints.tightFor(width: skipButtonSize, height: skipButtonSize),
          onPressed: player.hasPrevious ? () => player.playPrevious() : null,
          tooltip: '上一首',
        ),
        if (player.isLoading)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8.0),
            child: SizedBox(
              width: playButtonSize,
              height: playButtonSize,
              child: CircularProgressIndicator(
                strokeWidth: 2.5,
                color: activeColor,
              ),
            ),
          )
        else
          Container(
             margin: EdgeInsets.symmetric(horizontal: compact ? 6 : 8),
             decoration: BoxDecoration(
               color: activeColor,
               shape: BoxShape.circle,
               boxShadow: [
                 BoxShadow(
                   color: activeColor.withValues(alpha: 0.3),
                   blurRadius: 8,
                   offset: const Offset(0, 2),
                 )
               ]
             ),
             child: IconButton(
                 icon: Icon(player.isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded),
                 color: ThemeData.estimateBrightnessForColor(activeColor) == Brightness.dark
                     ? Colors.white
                     : const Color(0xFF0F172A),
                iconSize: playIconSize,
                padding: EdgeInsets.zero,
                constraints: BoxConstraints.tightFor(
                  width: playButtonSize,
                  height: playButtonSize,
                ),
                onPressed: () => player.togglePlayPause(),
                tooltip: player.isPlaying ? '暂停' : '播放',
             ),
           ),
        if (!hideSkip)
        IconButton(
          icon: Icon(
            Icons.skip_next_rounded,
            color: player.hasNext ? iconColor : iconColor.withValues(alpha: 0.5),
            size: skipIconSize,
          ),
          padding: EdgeInsets.zero,
          constraints:
              BoxConstraints.tightFor(width: skipButtonSize, height: skipButtonSize),
          onPressed: player.hasNext ? () => player.playNext() : null,
          tooltip: '下一首',
        ),
      ],
    );
  }

  /// 自适应右侧面板

  /// iOS Cupertino 风格右侧面板

  IconData _volumeIconCupertino(double volume) {
    if (volume == 0) return CupertinoIcons.volume_off;
    if (volume < 0.5) return CupertinoIcons.volume_down;
    return CupertinoIcons.volume_up;
  }

  /// 右侧面板（时长 + 音量 + 列表）- Material 风格

  IconData _volumeIcon(double volume) {
    if (volume == 0) return Icons.volume_off_rounded;
    if (volume < 0.5) return Icons.volume_down_rounded;
    return Icons.volume_up_rounded;
  }

  Future<void> _showVolumeDialog(BuildContext context, PlayerService player) async {
    final systemService = SystemVolumeService();
    bool systemSupported = false;
    double systemTemp = 0.0;
    try {
      systemSupported = await systemService.isSupported();
      if (systemSupported) {
        systemTemp = (await systemService.getVolume()) ?? player.volume;
      }
    } catch (_) {}
    double appTemp = player.volume;
    if (ThemeManager().isFluentFramework) {
      if (!context.mounted) return;
      await fluent.showDialog(
        context: context,
        builder: (context) {
          return fluent.ContentDialog(
            title: const Text('音量'),
            content: StatefulBuilder(
              builder: (context, setLocal) {
                if (!systemSupported) {
                  return Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      fluent.Slider(
                        value: appTemp,
                        min: 0.0,
                        max: 1.0,
                        onChanged: (v) {
                          setLocal(() => appTemp = v);
                          player.setVolume(v);
                        },
                      ),
                      Text('${(appTemp * 100).toInt()}%'),
                    ],
                  );
                }

                return Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Align(
                      alignment: Alignment.centerLeft,
                      child: Text('系统音量'),
                    ),
                    fluent.Slider(
                      value: systemTemp,
                      min: 0.0,
                      max: 1.0,
                      onChanged: (v) {
                        setLocal(() => systemTemp = v);
                        systemService.setVolume(v);
                      },
                    ),
                    Text('${(systemTemp * 100).toInt()}%'),
                    const SizedBox(height: 12),
                    const Align(
                      alignment: Alignment.centerLeft,
                      child: Text('应用音量'),
                    ),
                    fluent.Slider(
                      value: appTemp,
                      min: 0.0,
                      max: 1.0,
                      onChanged: (v) {
                        setLocal(() => appTemp = v);
                        player.setVolume(v);
                      },
                    ),
                    Text('${(appTemp * 100).toInt()}%'),
                  ],
                );
              },
            ),
            actions: [
              fluent.FilledButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('关闭'),
              ),
            ],
          );
        },
      );
      return;
    }

    // iOS Cupertino 风格
    if (_isCupertino) {
      if (!context.mounted) return;
      await showCupertinoModalPopup(
        context: context,
        builder: (context) {
          return Material(
            type: MaterialType.transparency,
            child: Container(
              height: 200,
              decoration: BoxDecoration(
                color: Theme.of(context).brightness == Brightness.dark
                    ? const Color(0xFF1C1C1E)
                    : CupertinoColors.white,
                borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
              ),
              child: SafeArea(
                top: false,
                child: StatefulBuilder(
                  builder: (context, setLocal) {
                    if (!systemSupported) {
                      return Column(
                        children: [
                          Container(
                            margin: const EdgeInsets.only(top: 8),
                            width: 36,
                            height: 5,
                            decoration: BoxDecoration(
                              color: CupertinoColors.systemGrey.withValues(alpha: 0.3),
                              borderRadius: BorderRadius.circular(2.5),
                            ),
                          ),
                          const SizedBox(height: 20),
                          const Text(
                            '音量',
                            style: TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 20),
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 24),
                            child: CupertinoSlider(
                              value: appTemp,
                              min: 0.0,
                              max: 1.0,
                              onChanged: (v) {
                                setLocal(() => appTemp = v);
                                player.setVolume(v);
                              },
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            '${(appTemp * 100).toInt()}%',
                            style: const TextStyle(
                              fontSize: 15,
                              color: CupertinoColors.systemGrey,
                            ),
                          ),
                        ],
                      );
                    }

                    return Column(
                      children: [
                        Container(
                          margin: const EdgeInsets.only(top: 8),
                          width: 36,
                          height: 5,
                          decoration: BoxDecoration(
                            color: CupertinoColors.systemGrey.withValues(alpha: 0.3),
                            borderRadius: BorderRadius.circular(2.5),
                          ),
                        ),
                        const SizedBox(height: 16),
                        const Text(
                          '系统音量',
                          style: TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 12),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 24),
                          child: CupertinoSlider(
                            value: systemTemp,
                            min: 0.0,
                            max: 1.0,
                            onChanged: (v) {
                              setLocal(() => systemTemp = v);
                              systemService.setVolume(v);
                            },
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          '${(systemTemp * 100).toInt()}%',
                          style: const TextStyle(
                            fontSize: 15,
                            color: CupertinoColors.systemGrey,
                          ),
                        ),
                        const SizedBox(height: 16),
                        const Text(
                          '应用音量',
                          style: TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 12),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 24),
                          child: CupertinoSlider(
                            value: appTemp,
                            min: 0.0,
                            max: 1.0,
                            onChanged: (v) {
                              setLocal(() => appTemp = v);
                              player.setVolume(v);
                            },
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          '${(appTemp * 100).toInt()}%',
                          style: const TextStyle(
                            fontSize: 15,
                            color: CupertinoColors.systemGrey,
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ),
            ),
          );
        },
      );
      return;
    }

    if (!context.mounted) return;
    await showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('音量'),
          content: StatefulBuilder(
            builder: (context, setLocal) {
              if (!systemSupported) {
                return Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Slider(
                      value: appTemp,
                      min: 0.0,
                      max: 1.0,
                      onChanged: (v) {
                        setLocal(() => appTemp = v);
                        player.setVolume(v);
                      },
                    ),
                    Text('${(appTemp * 100).toInt()}%'),
                  ],
                );
              }

              return Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Align(
                    alignment: Alignment.centerLeft,
                    child: Text('系统音量'),
                  ),
                  Slider(
                    value: systemTemp,
                    min: 0.0,
                    max: 1.0,
                    onChanged: (v) {
                      setLocal(() => systemTemp = v);
                      systemService.setVolume(v);
                    },
                  ),
                  Text('${(systemTemp * 100).toInt()}%'),
                  const SizedBox(height: 12),
                  const Align(
                    alignment: Alignment.centerLeft,
                    child: Text('应用音量'),
                  ),
                  Slider(
                    value: appTemp,
                    min: 0.0,
                    max: 1.0,
                    onChanged: (v) {
                      setLocal(() => appTemp = v);
                      player.setVolume(v);
                    },
                  ),
                  Text('${(appTemp * 100).toInt()}%'),
                ],
              );
            },
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('关闭'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _showQueueSheet(BuildContext context) async {
    final queueService = PlaylistQueueService();
    final history = PlayHistoryService().history;
    final historyTracks = history.map((h) => h.toTrack()).toList();

    bool isHighlightedTrack(Track track) {
      final activeTrack = PlayerService().activeTrack;
      final pendingTrack = PlayerService().pendingTrack;
      final isActive = activeTrack != null &&
          track.id.toString() == activeTrack.id.toString() &&
          track.source == activeTrack.source;
      final isPending = pendingTrack != null &&
          track.id.toString() == pendingTrack.id.toString() &&
          track.source == pendingTrack.source;
      return isActive || isPending;
    }
    if (ThemeManager().isFluentFramework) {
      await fluent.showDialog(
        context: context,
        builder: (context) {
          return AnimatedBuilder(
            animation: queueService,
            builder: (context, _) {
              final hasQueueNow = queueService.hasQueue;
              final List<dynamic> displayListNow =
                  hasQueueNow ? queueService.queue : historyTracks;
              return fluent.ContentDialog(
                title: Text(hasQueueNow ? '播放队列' : '播放历史'),
                content: SizedBox(
                  width: 520,
                  height: 420,
                  child: displayListNow.isEmpty
                      ? const Center(child: Text('播放列表为空'))
                      : ListView.separated(
                          itemCount: displayListNow.length,
                          separatorBuilder: (_, __) => const SizedBox(height: 8),
                          itemBuilder: (context, i) {
                            final Track t = displayListNow[i] as Track;
                            final isCurrent = isHighlightedTrack(t);
                            return fluent.Card(
                              padding: const EdgeInsets.all(8),
                              child: fluent.ListTile(
                                title: Text(t.name, maxLines: 1, overflow: TextOverflow.ellipsis),
                                subtitle: Text(t.artists, maxLines: 1, overflow: TextOverflow.ellipsis),
                                leading: ClipRRect(
                                  borderRadius: BorderRadius.circular(4),
                                  child: (t.picUrl.startsWith('http') || t.picUrl.startsWith('https'))
                                      ? CachedNetworkImage(
                                          imageUrl: t.picUrl,
                                          httpHeaders: getImageHeaders(t.picUrl),
                                          memCacheWidth: 128,
                                          memCacheHeight: 128,
                                          imageBuilder: (context, imageProvider) {
                                            PlaylistQueueService().updateCoverProvider(t, imageProvider);
                                            return Image(image: imageProvider, width: 44, height: 44, fit: BoxFit.cover);
                                          },
                                          placeholder: (context, url) => Container(width: 44, height: 44, color: fluent.Colors.grey[20]),
                                          errorWidget: (context, url, error) => Container(
                                            width: 44,
                                            height: 44,
                                            color: fluent.Colors.grey[20],
                                            child: const Icon(Icons.music_note),
                                          ),
                                        )
                                      : Image.file(
                                          File(t.picUrl),
                                          width: 44,
                                          height: 44,
                                          fit: BoxFit.cover,
                                          errorBuilder: (context, error, stackTrace) => Container(
                                            width: 44,
                                            height: 44,
                                            color: fluent.Colors.grey[20],
                                            child: const Icon(Icons.music_note),
                                          ),
                                        ),
                                ),
                                tileColor: isCurrent
                                    ? WidgetStateColor.resolveWith(
                                        (_) =>
                                        fluent.FluentTheme.of(context).resources.controlFillColorSecondary,
                                      )
                                    : null,
                                trailing: TrackMoreButton(
                                  track: t,
                                  onPlay: () {
                                    final coverProvider = PlaylistQueueService().getCoverProvider(t);
                                    PlayerService().playTrack(t, coverProvider: coverProvider);
                                    Navigator.pop(context);
                                  },
                                  size: 28,
                                ),
                                onPressed: () {
                                  final coverProvider = PlaylistQueueService().getCoverProvider(t);
                                  PlayerService().playTrack(t, coverProvider: coverProvider);
                                  Navigator.pop(context);
                                },
                              ),
                            );
                          },
                        ),
                ),
                actions: [
                  fluent.FilledButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('关闭'),
                  ),
                ],
              );
            },
          );
        },
      );
      return;
    }

    // iOS Cupertino 风格
    if (_isCupertino) {
      final isDark = Theme.of(context).brightness == Brightness.dark;
      final media = MediaQuery.of(context);
      final isLandscape = media.orientation == Orientation.landscape;
      final sheetHeight = media.size.height * (isLandscape ? 0.72 : 0.6);
      await showCupertinoModalPopup(
        context: context,
        builder: (context) {
          return Material(
            type: MaterialType.transparency,
            child: StatefulBuilder(
              builder: (context, setState) {
                return AnimatedBuilder(
                  animation: queueService,
                  builder: (context, _) {
                    final hasQueueNow = queueService.hasQueue;
                    final List<Track> list = hasQueueNow ? queueService.queue : historyTracks;
                    return Container(
                      height: sheetHeight,
                      decoration: BoxDecoration(
                        color: isDark ? const Color(0xFF1C1C1E) : CupertinoColors.white,
                        borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
                      ),
                      child: SafeArea(
                        top: false,
                        child: Column(
                          children: [
                            Container(
                              margin: const EdgeInsets.only(top: 8),
                              width: 36,
                              height: 5,
                              decoration: BoxDecoration(
                                color: CupertinoColors.systemGrey.withValues(alpha: 0.3),
                                borderRadius: BorderRadius.circular(2.5),
                              ),
                            ),
                            Padding(
                              padding: const EdgeInsets.fromLTRB(16, 8, 12, 8),
                              child: Row(
                                children: [
                                  Text(
                                    hasQueueNow ? '播放队列' : '播放历史',
                                    style: TextStyle(
                                      fontSize: 17,
                                      fontWeight: FontWeight.w600,
                                      color: isDark ? CupertinoColors.white : CupertinoColors.black,
                                    ),
                                  ),
                                  const Spacer(),
                                  CupertinoButton(
                                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                    minimumSize: Size.zero,
                                    onPressed: hasQueueNow ? () => queueService.clear() : null,
                                    child: Text(
                                      '清空',
                                      style: TextStyle(
                                        fontSize: 13,
                                        color: hasQueueNow ? CupertinoColors.systemRed : CupertinoColors.systemGrey,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            Expanded(
                              child: list.isEmpty
                                  ? Center(
                                      child: Text(
                                        '播放列表为空',
                                        style: TextStyle(color: CupertinoColors.systemGrey),
                                      ),
                                    )
                                  : (hasQueueNow
                                      ? ReorderableListView.builder(
                                          buildDefaultDragHandles: false,
                                          onReorder: (oldIndex, newIndex) {
                                            if (newIndex > oldIndex) newIndex -= 1;
                                            queueService.move(oldIndex, newIndex);
                                          },
                                          itemCount: list.length,
                                          itemBuilder: (context, i) {
                                            final Track t = list[i];
                                            final isCurrent = isHighlightedTrack(t);
                                            final content = Container(
                                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                                              decoration: BoxDecoration(
                                                color: isCurrent
                                                    ? CupertinoColors.activeBlue.withValues(alpha: 0.1)
                                                    : null,
                                              ),
                                              child: Row(
                                                children: [
                                                  ClipRRect(
                                                    borderRadius: BorderRadius.circular(6),
                                                    child: (t.picUrl.startsWith('http') || t.picUrl.startsWith('https'))
                                                        ? CachedNetworkImage(
                                                            imageUrl: t.picUrl,
                                                            httpHeaders: getImageHeaders(t.picUrl),
                                                            memCacheWidth: 128,
                                                            memCacheHeight: 128,
                                                            imageBuilder: (context, imageProvider) {
                                                              PlaylistQueueService().updateCoverProvider(t, imageProvider);
                                                              return Image(image: imageProvider, width: 44, height: 44, fit: BoxFit.cover);
                                                            },
                                                            placeholder: (context, url) => Container(
                                                              width: 44,
                                                              height: 44,
                                                              color: isDark ? const Color(0xFF2C2C2E) : CupertinoColors.systemGrey5,
                                                              child: const CupertinoActivityIndicator(radius: 10),
                                                            ),
                                                            errorWidget: (context, url, error) => Container(
                                                              width: 44,
                                                              height: 44,
                                                              color: isDark ? const Color(0xFF2C2C2E) : CupertinoColors.systemGrey5,
                                                              child: Icon(CupertinoIcons.music_note, color: CupertinoColors.systemGrey),
                                                            ),
                                                          )
                                                        : Image.file(
                                                            File(t.picUrl),
                                                            width: 44,
                                                            height: 44,
                                                            fit: BoxFit.cover,
                                                            errorBuilder: (context, error, stackTrace) => Container(
                                                              width: 44,
                                                              height: 44,
                                                              color: isDark ? const Color(0xFF2C2C2E) : CupertinoColors.systemGrey5,
                                                              child: Icon(CupertinoIcons.music_note, color: CupertinoColors.systemGrey),
                                                            ),
                                                          ),
                                                  ),
                                                  const SizedBox(width: 12),
                                                  Expanded(
                                                    child: Column(
                                                      crossAxisAlignment: CrossAxisAlignment.start,
                                                      children: [
                                                        Text(
                                                          t.name,
                                                          maxLines: 1,
                                                          overflow: TextOverflow.ellipsis,
                                                          style: TextStyle(
                                                            fontSize: 16,
                                                            color: isCurrent
                                                                ? CupertinoColors.activeBlue
                                                                : (isDark ? CupertinoColors.white : CupertinoColors.black),
                                                          ),
                                                        ),
                                                        Text(
                                                          t.artists,
                                                          maxLines: 1,
                                                          overflow: TextOverflow.ellipsis,
                                                          style: TextStyle(
                                                            fontSize: 13,
                                                            color: CupertinoColors.systemGrey,
                                                          ),
                                                        ),
                                                      ],
                                                    ),
                                                  ),
                                                  if (isCurrent)
                                                    Icon(
                                                      CupertinoIcons.play_fill,
                                                      color: CupertinoColors.activeBlue,
                                                      size: 18,
                                                    ),
                                                  TrackMoreButton(
                                                    track: t,
                                                    onPlay: () {
                                                      final coverProvider = PlaylistQueueService().getCoverProvider(t);
                                                      PlayerService().playTrack(t, coverProvider: coverProvider);
                                                      Navigator.pop(context);
                                                    },
                                                    size: 28,
                                                  ),
                                                  const SizedBox(width: 4),
                                                  ReorderableDelayedDragStartListener(
                                                    index: i,
                                                    child: Icon(
                                                      CupertinoIcons.line_horizontal_3,
                                                      color: CupertinoColors.systemGrey,
                                                      size: 18,
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            );
                                            return Dismissible(
                                              key: ObjectKey(t),
                                              direction: DismissDirection.endToStart,
                                              background: Container(
                                                alignment: Alignment.centerRight,
                                                padding: const EdgeInsets.only(right: 16),
                                                color: CupertinoColors.systemRed,
                                                child: const Icon(CupertinoIcons.delete, color: CupertinoColors.white),
                                              ),
                                              onDismissed: (_) {
                                                queueService.removeAt(i);
                                                ScaffoldMessenger.of(context).showSnackBar(
                                                  const SnackBar(content: Text('已移除'), duration: Duration(seconds: 1)),
                                                );
                                              },
                                              child: GestureDetector(
                                                behavior: HitTestBehavior.opaque,
                                                onTap: () {
                                                  final coverProvider = PlaylistQueueService().getCoverProvider(t);
                                                  PlayerService().playTrack(t, coverProvider: coverProvider);
                                                  Navigator.pop(context);
                                                },
                                                child: content,
                                              ),
                                            );
                                          },
                                        )
                                      : ListView.builder(
                                          itemCount: list.length,
                                          itemBuilder: (context, i) {
                                            final Track t = list[i];
                                            final isCurrent = isHighlightedTrack(t);
                                            return GestureDetector(
                                              behavior: HitTestBehavior.opaque,
                                              onTap: () {
                                                final coverProvider = PlaylistQueueService().getCoverProvider(t);
                                                PlayerService().playTrack(t, coverProvider: coverProvider);
                                                Navigator.pop(context);
                                              },
                                              child: Container(
                                                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                                                decoration: BoxDecoration(
                                                  color: isCurrent
                                                      ? CupertinoColors.activeBlue.withValues(alpha: 0.1)
                                                      : null,
                                                ),
                                                child: Row(
                                                  children: [
                                                    ClipRRect(
                                                      borderRadius: BorderRadius.circular(6),
                                                      child: (t.picUrl.startsWith('http') || t.picUrl.startsWith('https'))
                                                          ? CachedNetworkImage(
                                                              imageUrl: t.picUrl,
                                                              httpHeaders: getImageHeaders(t.picUrl),
                                                              memCacheWidth: 128,
                                                              memCacheHeight: 128,
                                                              imageBuilder: (context, imageProvider) {
                                                                PlaylistQueueService().updateCoverProvider(t, imageProvider);
                                                                return Image(image: imageProvider, width: 44, height: 44, fit: BoxFit.cover);
                                                              },
                                                              placeholder: (context, url) => Container(
                                                                width: 44,
                                                                height: 44,
                                                                color: isDark ? const Color(0xFF2C2C2E) : CupertinoColors.systemGrey5,
                                                                child: const CupertinoActivityIndicator(radius: 10),
                                                              ),
                                                              errorWidget: (context, url, error) => Container(
                                                                width: 44,
                                                                height: 44,
                                                                color: isDark ? const Color(0xFF2C2C2E) : CupertinoColors.systemGrey5,
                                                                child: Icon(CupertinoIcons.music_note, color: CupertinoColors.systemGrey),
                                                              ),
                                                            )
                                                          : Image.file(
                                                              File(t.picUrl),
                                                              width: 44,
                                                              height: 44,
                                                              fit: BoxFit.cover,
                                                              errorBuilder: (context, error, stackTrace) => Container(
                                                                width: 44,
                                                                height: 44,
                                                                color: isDark ? const Color(0xFF2C2C2E) : CupertinoColors.systemGrey5,
                                                                child: Icon(CupertinoIcons.music_note, color: CupertinoColors.systemGrey),
                                                              ),
                                                            ),
                                                    ),
                                                    const SizedBox(width: 12),
                                                    Expanded(
                                                      child: Column(
                                                        crossAxisAlignment: CrossAxisAlignment.start,
                                                        children: [
                                                          Text(
                                                            t.name,
                                                            maxLines: 1,
                                                            overflow: TextOverflow.ellipsis,
                                                            style: TextStyle(
                                                              fontSize: 16,
                                                              color: isCurrent
                                                                  ? CupertinoColors.activeBlue
                                                                  : (isDark ? CupertinoColors.white : CupertinoColors.black),
                                                            ),
                                                          ),
                                                          Text(
                                                            t.artists,
                                                            maxLines: 1,
                                                            overflow: TextOverflow.ellipsis,
                                                            style: TextStyle(
                                                              fontSize: 13,
                                                              color: CupertinoColors.systemGrey,
                                                            ),
                                                          ),
                                                        ],
                                                      ),
                                                    ),
                                                    TrackMoreButton(
                                                      track: t,
                                                      onPlay: () {
                                                        final coverProvider = PlaylistQueueService().getCoverProvider(t);
                                                        PlayerService().playTrack(t, coverProvider: coverProvider);
                                                        Navigator.pop(context);
                                                      },
                                                      size: 28,
                                                    ),
                                                  ],
                                                ),
                                              ),
                                            );
                                          },
                                        )),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          );
        },
      );
      return;
    }

    final media = MediaQuery.of(context);
    final isLandscape = media.orientation == Orientation.landscape;
    final sheetHeight = media.size.height * (isLandscape ? 0.78 : 0.6);
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setState) {
            return AnimatedBuilder(
              animation: queueService,
              builder: (context, _) {
                final hasQueueNow = queueService.hasQueue;
                final List<Track> list = hasQueueNow ? queueService.queue : historyTracks;
                final colorScheme = Theme.of(context).colorScheme;

                return SafeArea(
                  child: SizedBox(
                    height: sheetHeight,
                    child: Column(
                      children: [
                        Padding(
                          padding: const EdgeInsets.fromLTRB(16, 4, 8, 4),
                          child: Row(
                            children: [
                              Text(
                                hasQueueNow ? '播放队列' : '播放历史',
                                style: Theme.of(context).textTheme.titleMedium,
                              ),
                              const Spacer(),
                              TextButton(
                                onPressed: hasQueueNow ? () => queueService.clear() : null,
                                child: const Text('清空'),
                              ),
                            ],
                          ),
                        ),
                        Expanded(
                          child: list.isEmpty
                              ? Center(
                                  child: Padding(
                                    padding: const EdgeInsets.all(24.0),
                                    child: Text('播放列表为空', style: Theme.of(context).textTheme.bodyMedium),
                                  ),
                                )
                              : (hasQueueNow
                                  ? ReorderableListView.builder(
                                      buildDefaultDragHandles: false,
                                      onReorder: (oldIndex, newIndex) {
                                        if (newIndex > oldIndex) newIndex -= 1;
                                        queueService.move(oldIndex, newIndex);
                                      },
                                      itemCount: list.length,
                                      itemBuilder: (context, i) {
                                        final Track t = list[i];
                                        final isCurrent = isHighlightedTrack(t);

                                        final tile = ListTile(
                                          tileColor: isCurrent ? colorScheme.surfaceContainerHigh : null,
                                          leading: ClipRRect(
                                            borderRadius: BorderRadius.circular(4),
                                            child: (t.picUrl.startsWith('http') || t.picUrl.startsWith('https'))
                                              ? CachedNetworkImage(
                                                  imageUrl: t.picUrl,
                                                  httpHeaders: getImageHeaders(t.picUrl),
                                                  memCacheWidth: 128,
                                                  memCacheHeight: 128,
                                                  imageBuilder: (context, imageProvider) {
                                                    PlaylistQueueService().updateCoverProvider(t, imageProvider);
                                                    return Image(
                                                      image: imageProvider,
                                                      width: 44,
                                                      height: 44,
                                                      fit: BoxFit.cover,
                                                    );
                                                  },
                                                  placeholder: (context, url) => Container(width: 44, height: 44, color: Colors.black12),
                                                  errorWidget: (context, url, error) => Container(
                                                    width: 44,
                                                    height: 44,
                                                    color: Colors.black12,
                                                    child: Icon(Icons.music_note, color: colorScheme.onSurfaceVariant),
                                                  ),
                                                )
                                              : Image.file(
                                                  File(t.picUrl),
                                                  width: 44,
                                                  height: 44,
                                                  fit: BoxFit.cover,
                                                  errorBuilder: (context, error, stackTrace) => Container(
                                                    width: 44,
                                                    height: 44,
                                                    color: Colors.black12,
                                                    child: Icon(Icons.music_note, color: colorScheme.onSurfaceVariant),
                                                  ),
                                                ),
                                          ),
                                          title: Text(t.name, maxLines: 1, overflow: TextOverflow.ellipsis),
                                          subtitle: Text(t.artists, maxLines: 1, overflow: TextOverflow.ellipsis),
                                          trailing: Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              TrackMoreButton(
                                                track: t,
                                                onPlay: () {
                                                  final coverProvider = PlaylistQueueService().getCoverProvider(t);
                                                  PlayerService().playTrack(t, coverProvider: coverProvider);
                                                  Navigator.pop(context);
                                                },
                                                size: 32,
                                              ),
                                              IconButton(
                                                icon: Icon(Icons.close_rounded, color: colorScheme.onSurfaceVariant, size: 18),
                                                constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                                                padding: EdgeInsets.zero,
                                                onPressed: () {
                                                  queueService.removeAt(i);
                                                  ScaffoldMessenger.of(context).showSnackBar(
                                                    const SnackBar(content: Text('已移除'), duration: Duration(seconds: 1)),
                                                  );
                                                },
                                                tooltip: '移除',
                                              ),
                                              ReorderableDelayedDragStartListener(
                                                index: i,
                                                child: Icon(Icons.drag_handle_rounded, color: colorScheme.onSurfaceVariant),
                                              ),
                                            ],
                                          ),
                                          onTap: () {
                                            final coverProvider = PlaylistQueueService().getCoverProvider(t);
                                            PlayerService().playTrack(t, coverProvider: coverProvider);
                                            Navigator.pop(context);
                                            // snackbar removed
                                          },
                                        );

                                        return Dismissible(
                                          key: ObjectKey(t),
                                          direction: DismissDirection.endToStart,
                                          background: Container(
                                            alignment: Alignment.centerRight,
                                            padding: const EdgeInsets.only(right: 16),
                                            color: colorScheme.error,
                                            child: const Icon(Icons.delete, color: Colors.white),
                                          ),
                                          onDismissed: (_) {
                                            queueService.removeAt(i);
                                            ScaffoldMessenger.of(context).showSnackBar(
                                              const SnackBar(content: Text('已移除'), duration: Duration(seconds: 1)),
                                            );
                                          },
                                          child: tile,
                                        );
                                      },
                                    )
                                  : ListView.separated(
                                      itemCount: list.length,
                                      separatorBuilder: (_, __) => const Divider(height: 1),
                                      itemBuilder: (context, i) {
                                        final Track t = list[i];
                                        final isCurrent = isHighlightedTrack(t);

                                        return ListTile(
                                          tileColor: isCurrent ? colorScheme.surfaceContainerHigh : null,
                                          leading: ClipRRect(
                                            borderRadius: BorderRadius.circular(4),
                                            child: (t.picUrl.startsWith('http') || t.picUrl.startsWith('https'))
                                              ? CachedNetworkImage(
                                                  imageUrl: t.picUrl,
                                                  httpHeaders: getImageHeaders(t.picUrl),
                                                  memCacheWidth: 128,
                                                  memCacheHeight: 128,
                                                  imageBuilder: (context, imageProvider) {
                                                    PlaylistQueueService().updateCoverProvider(t, imageProvider);
                                                    return Image(
                                                      image: imageProvider,
                                                      width: 44,
                                                      height: 44,
                                                      fit: BoxFit.cover,
                                                    );
                                                  },
                                                  placeholder: (context, url) => Container(width: 44, height: 44, color: Colors.black12),
                                                  errorWidget: (context, url, error) => Container(
                                                    width: 44,
                                                    height: 44,
                                                    color: Colors.black12,
                                                    child: Icon(Icons.music_note, color: colorScheme.onSurfaceVariant),
                                                  ),
                                                )
                                              : Image.file(
                                                  File(t.picUrl),
                                                  width: 44,
                                                  height: 44,
                                                  fit: BoxFit.cover,
                                                  errorBuilder: (context, error, stackTrace) => Container(
                                                    width: 44,
                                                    height: 44,
                                                    color: Colors.black12,
                                                    child: Icon(Icons.music_note, color: colorScheme.onSurfaceVariant),
                                                  ),
                                                ),
                                          ),
                                          title: Text(t.name, maxLines: 1, overflow: TextOverflow.ellipsis),
                                          subtitle: Text(t.artists, maxLines: 1, overflow: TextOverflow.ellipsis),
                                          trailing: TrackMoreButton(
                                            track: t,
                                            onPlay: () {
                                              final coverProvider = PlaylistQueueService().getCoverProvider(t);
                                              PlayerService().playTrack(t, coverProvider: coverProvider);
                                              Navigator.pop(context);
                                            },
                                            size: 32,
                                          ),
                                          onTap: () {
                                            final coverProvider = PlaylistQueueService().getCoverProvider(t);
                                            PlayerService().playTrack(t, coverProvider: coverProvider);
                                            Navigator.pop(context);
                                            // snackbar removed
                                          },
                                        );
                                      },
                                    )),
                        ),
                      ],
                    ),
                  ),
                );
              },
            );
          },
        );
      },
    );
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

  /// 格式化时长
  String _formatDuration(Duration duration) {
    final minutes = duration.inMinutes;
    final seconds = duration.inSeconds % 60;
    return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }
}
