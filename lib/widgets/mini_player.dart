import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:fluent_ui/fluent_ui.dart' as fluent;
import 'dart:ui' as ui;
import 'package:cached_network_image/cached_network_image.dart';
import '../services/player_service.dart';
import '../pages/player_page.dart';
import '../services/playlist_queue_service.dart';
import '../services/play_history_service.dart';
import '../services/system_volume_service.dart';
import '../models/track.dart';
import '../utils/theme_manager.dart';

/// 迷你播放器组件（底部播放栏）
class MiniPlayer extends StatefulWidget {
  const MiniPlayer({super.key});

  @override
  State<MiniPlayer> createState() => _MiniPlayerState();
}

class _MiniPlayerState extends State<MiniPlayer> with SingleTickerProviderStateMixin {
  bool _isCollapsed = false;
  bool _autoCollapseEnabled = false;
  Timer? _collapseTimer;
  String? _lastTrackKey;
  AnimationController? _breathingController;
  Animation<double>? _breathingScale;
  bool _breathingActive = false;

  bool get _isCupertino => ThemeManager().isCupertinoFramework;

  @override
  void initState() {
    super.initState();
  }

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
            minSize: 0,
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
            minSize: 0,
            onPressed: () => player.togglePlayPause(),
            child: Icon(
              player.isPlaying ? CupertinoIcons.pause_fill : CupertinoIcons.play_fill,
              size: playIconSize,
              color: CupertinoColors.activeBlue,
            ),
          ),
        if (!hideSkip)
          CupertinoButton(
            padding: buttonPadding,
            minSize: 0,
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

  Widget _buildRightPanelFluent(PlayerService player, BuildContext context) {
    final theme = fluent.FluentTheme.of(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        ValueListenableBuilder<Duration>(
          valueListenable: player.positionNotifier,
          builder: (context, position, child) {
            return Text(
              _formatDuration(position),
              style: TextStyle(
                fontFamily: 'Microsoft YaHei',
                fontSize: 12,
                color: theme.resources.textFillColorSecondary,
              ),
            );
          },
        ),
        Text(
          ' / ',
          style: TextStyle(
            fontFamily: 'Microsoft YaHei',
            fontSize: 12,
            color: theme.resources.textFillColorSecondary,
          ),
        ),
        Text(
          _formatDuration(player.duration),
          style: TextStyle(
            fontFamily: 'Microsoft YaHei',
            fontSize: 12,
            color: theme.resources.textFillColorSecondary,
          ),
        ),
        const SizedBox(width: 12),
        fluent.IconButton(
          icon: Icon(_volumeIcon(player.volume), color: theme.resources.textFillColorPrimary),
          onPressed: () => _showVolumeDialog(context, player),
        ),
        fluent.IconButton(
          icon: Icon(Icons.queue_music_rounded, color: theme.resources.textFillColorPrimary),
          onPressed: () => _showQueueSheet(context),
        ),
      ],
    );
  }

  @override
  void dispose() {
    _collapseTimer?.cancel();
    _breathingController?.dispose();
    super.dispose();
  }

  void _configureAutoCollapse(bool enable) {
    if (_autoCollapseEnabled == enable) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      setState(() {
        _autoCollapseEnabled = enable;
        if (!_autoCollapseEnabled) {
          _collapseTimer?.cancel();
          _isCollapsed = false;
        } else {
          _scheduleCollapseTimer();
        }
      });
      if (!enable) {
        _setBreathingActive(false);
      }
    });
  }

  void _scheduleCollapseTimer() {
    _collapseTimer?.cancel();
    if (!_autoCollapseEnabled) return;
    _collapseTimer = Timer(const Duration(seconds: 5), () {
      if (!mounted || !_autoCollapseEnabled) return;
      setState(() {
        _isCollapsed = true;
      });
      _setBreathingActive(true);
    });
  }

  void _resetCollapseTimer({bool expand = false}) {
    if (!_autoCollapseEnabled) return;
    _collapseTimer?.cancel();
    if (expand && _isCollapsed) {
      setState(() {
        _isCollapsed = false;
      });
      _setBreathingActive(false);
    }
    _scheduleCollapseTimer();
  }

  void _handlePointerDown() {
    if (!_autoCollapseEnabled) return;
    _collapseTimer?.cancel();
  }

  void _setBreathingActive(bool active) {
    if (_breathingActive == active) return;
    _breathingActive = active;
    if (active) {
      final controller = _breathingController ??= AnimationController(
        vsync: this,
        duration: const Duration(milliseconds: 2800),
      );
      _breathingScale ??= Tween<double>(begin: 0.94, end: 1.06).animate(
        CurvedAnimation(parent: controller, curve: Curves.easeInOut),
      );
      controller
        ..reset()
        ..repeat(reverse: true);
    } else {
      _breathingController?.stop();
      _breathingController?.reset();
    }
  }

  void _handleTrackChange(String? trackKey) {
    if (_lastTrackKey == trackKey) return;
    _lastTrackKey = trackKey;
    if (!_autoCollapseEnabled) {
      if (_isCollapsed) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            setState(() => _isCollapsed = false);
          }
        });
        _setBreathingActive(false);
      }
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      setState(() {
        _isCollapsed = false;
      });
      _setBreathingActive(false);
      _scheduleCollapseTimer();
    });
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
        final bool isPortrait = mediaQuery.orientation == Orientation.portrait;
        final bool isMobile = Platform.isAndroid || Platform.isIOS;
        final bool hasContent = track != null || song != null;

        final bool shouldAutoCollapse =
            hasContent && isMobile && (isPortrait ? isCompactWidth : true);
        _configureAutoCollapse(shouldAutoCollapse);

        final String? trackKey;
        if (track != null) {
          final sourceName = track.source.name;
          trackKey = 'track_${track.id}_$sourceName';
        } else if (song != null) {
          trackKey = 'song_${song.id}_${song.source.name}';
        } else {
          trackKey = null;
        }
        _handleTrackChange(trackKey);

        if (!hasContent) {
          return const SizedBox.shrink();
        }

        final colorScheme = Theme.of(context).colorScheme;
        final Color? themeTint = PlayerService().themeColorNotifier.value;
        final bool showCollapsed = _autoCollapseEnabled && _isCollapsed;

        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          _setBreathingActive(showCollapsed);
        });

        final expanded = _buildExpandedPlayer(
          context: context,
          player: player,
          song: song,
          track: track,
          colorScheme: colorScheme,
          themeTint: themeTint,
          isCompactWidth: isCompactWidth,
          isPortrait: isPortrait,
        );

        final collapsed = _buildCollapsedPlayer(
          context: context,
          song: song,
          track: track,
          colorScheme: colorScheme,
          isCompactWidth: isCompactWidth,
          isActive: showCollapsed,
        );

        return Listener(
          onPointerDown: (_) => _handlePointerDown(),
          onPointerUp: (_) => _resetCollapseTimer(),
          child: AnimatedSize(
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeInOutCubic,
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 250),
              switchInCurve: Curves.easeOutCubic,
              switchOutCurve: Curves.easeInCubic,
              child: showCollapsed ? collapsed : GestureDetector(
                behavior: HitTestBehavior.opaque,
                excludeFromSemantics: true,
                onTap: () {
                  _resetCollapseTimer();
                  _openFullPlayer(context);
                },
                child: expanded,
              ),
            ),
          ),
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

  Widget _buildExpandedPlayer({
    required BuildContext context,
    required PlayerService player,
    required dynamic song,
    required dynamic track,
    required ColorScheme colorScheme,
    required Color? themeTint,
    required bool isCompactWidth,
    required bool isPortrait,
  }) {
    final backgroundColor = colorScheme.surfaceContainerHighest;
    final progressBarTrackColor = colorScheme.surfaceContainerHighest;
    final progressBarActiveColor = colorScheme.primary;
    final bool useAlignedLayout = !isCompactWidth;

    if (!useAlignedLayout) {
      return Container(
        key: const ValueKey('mini_expanded'),
        height: 64,
        margin: EdgeInsets.zero,
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(color: backgroundColor),
        child: Column(
          children: [
            // Top-aligned full-width progress bar
            SizedBox(
              height: 2,
              width: double.infinity,
              child: ValueListenableBuilder<Duration>(
                valueListenable: player.positionNotifier,
                builder: (context, position, child) {
                  final progress = player.duration.inMilliseconds > 0
                      ? position.inMilliseconds /
                          player.duration.inMilliseconds
                      : 0.0;
                  return LinearProgressIndicator(
                    value: progress,
                    minHeight: 2,
                    backgroundColor: progressBarTrackColor,
                    valueColor: AlwaysStoppedAnimation<Color>(
                      progressBarActiveColor,
                    ),
                  );
                },
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(
                  children: [
                    _buildCover(song, track, colorScheme, size: 40),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _buildSongInfo(song, track, context),
                    ),
                    _buildAdaptiveControls(
                      player,
                      context,
                      colorScheme,
                      hideSkip: false,
                      compact: true,
                    ),
                    const SizedBox(width: 6),
                    _buildQueueButton(context, colorScheme, compact: true),
                  ],
                ),
              ),
            ),
          ],
        ),
      );
    }

    return Container(
      key: const ValueKey('mini_expanded'),
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      constraints: const BoxConstraints(minHeight: 80),
      decoration: BoxDecoration(color: backgroundColor),
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
                  _buildSongInfo(song, track, context, singleLine: true),
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
        minSize: 0,
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
        minSize: 0,
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
    final overlayBox = overlay?.context.findRenderObject() as RenderBox?;
    if (overlay == null || renderBox == null || overlayBox == null) {
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
                        color: Colors.black.withOpacity(0.15),
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

  Widget _buildCollapsedPlayer({
    required BuildContext context,
    required dynamic song,
    required dynamic track,
    required ColorScheme colorScheme,
    required bool isCompactWidth,
    required bool isActive,
  }) {
    final margin = isCompactWidth ? const EdgeInsets.fromLTRB(12, 8, 12, 8) : EdgeInsets.zero;
    final cover = _buildCover(song, track, colorScheme, size: 64);

    final backgroundColor = colorScheme.surface;

    if (!isActive) {
      return Container(
        key: const ValueKey('mini_collapsed'),
        margin: margin,
        alignment: Alignment.bottomLeft,
        child: GestureDetector(
          onTap: () => _resetCollapseTimer(expand: true),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: backgroundColor,
              borderRadius: BorderRadius.circular(22),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.12),
                  blurRadius: 8,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: cover,
          ),
        ),
      );
    }

    return Container(
      key: const ValueKey('mini_collapsed'),
      margin: margin,
      alignment: Alignment.bottomLeft,
      child: GestureDetector(
        onTap: () => _resetCollapseTimer(expand: true),
        child: AnimatedBuilder(
          animation: _breathingController ?? kAlwaysCompleteAnimation,
          child: cover,
          builder: (context, child) {
            final controller = _breathingController;
            final scaleAnim = _breathingScale;
            final t = controller?.value ?? 1.0;
            final scale = scaleAnim?.value ?? 1.0;
            final glowColor = colorScheme.primary.withOpacity(
              ui.lerpDouble(0.35, 0.6, t) ?? 0.45,
            );
            final blur = ui.lerpDouble(18, 32, t) ?? 24;
            final spread = ui.lerpDouble(3, 10, t) ?? 6;

            return Transform.scale(
              scale: scale,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  boxShadow: [
                    BoxShadow(
                      color: glowColor,
                      blurRadius: blur,
                      spreadRadius: spread,
                    ),
                  ],
                ),
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(
                      color: colorScheme.primary
                          .withOpacity(ui.lerpDouble(0.25, 0.4, t) ?? 0.3),
                    ),
                    color: backgroundColor,
                  ),
                  child: child,
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  /// 构建进度条
  /// 使用 ValueListenableBuilder 监听 positionNotifier 以实时更新进度
  Widget _buildProgressBar(PlayerService player, ColorScheme colorScheme) {
    return ValueListenableBuilder<Duration>(
      valueListenable: player.positionNotifier,
      builder: (context, position, child) {
        final progress = player.duration.inMilliseconds > 0
            ? position.inMilliseconds / player.duration.inMilliseconds
            : 0.0;
        if (ThemeManager().isFluentFramework) {
          return fluent.ProgressBar(
            value: progress,
          );
        }
        if (_isCupertino) {
          return Container(
            height: 2,
            child: LinearProgressIndicator(
              value: progress,
              minHeight: 2,
              backgroundColor: CupertinoColors.systemGrey.withOpacity(0.2),
              valueColor: const AlwaysStoppedAnimation<Color>(CupertinoColors.activeBlue),
            ),
          );
        }
        return LinearProgressIndicator(
          value: progress,
          minHeight: 2,
          backgroundColor: colorScheme.surfaceContainerHighest,
          valueColor: AlwaysStoppedAnimation<Color>(colorScheme.primary),
        );
      },
    );
  }

  Widget _buildAlignedProgressRow(PlayerService player, ColorScheme colorScheme) {
    final timeStyle = TextStyle(
      fontSize: 11,
      color: colorScheme.onSurfaceVariant,
    );
    return ValueListenableBuilder<Duration>(
      valueListenable: player.positionNotifier,
      builder: (context, position, child) {
        final progress = player.duration.inMilliseconds > 0
            ? position.inMilliseconds / player.duration.inMilliseconds
            : 0.0;
        final indicator = ThemeManager().isFluentFramework
            ? SizedBox(
                height: 4,
                child: fluent.ProgressBar(value: progress),
              )
            : SizedBox(
                height: 3,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(999),
                  child: LinearProgressIndicator(
                    value: progress,
                    minHeight: 3,
                    backgroundColor:
                        colorScheme.onSurface.withOpacity(0.08),
                    valueColor:
                        AlwaysStoppedAnimation<Color>(colorScheme.primary),
                  ),
                ),
              );

        return Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Text(_formatDuration(position), style: timeStyle),
            const SizedBox(width: 8),
            Expanded(child: indicator),
            const SizedBox(width: 8),
            Text(_formatDuration(player.duration), style: timeStyle),
          ],
        );
      },
    );
  }

  /// 构建封面
  Widget _buildCover(dynamic song, dynamic track, ColorScheme colorScheme, {double size = 48}) {
    final imageUrl = song?.pic ?? track?.picUrl ?? '';

    return ClipRRect(
      borderRadius: BorderRadius.circular(6),
      child: imageUrl.isNotEmpty
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
    dynamic song,
    dynamic track,
    BuildContext context, {
    bool singleLine = false,
  }) {
    final name = song?.name ?? track?.name ?? '未知歌曲';
    final artist = song?.arName ?? track?.artists ?? '未知艺术家';
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

    // Material Design 主题保持原样
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          name,
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
            fontWeight: FontWeight.w500,
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        const SizedBox(height: 2),
        Text(
          artist,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
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
    final activeColor = colorScheme.primary;
    final iconColor = colorScheme.onSurface;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (!hideSkip)
        IconButton(
          icon: Icon(
            Icons.skip_previous_rounded,
            color: player.hasPrevious ? iconColor : iconColor.withOpacity(0.5),
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
                   color: activeColor.withOpacity(0.3),
                   blurRadius: 8,
                   offset: const Offset(0, 2),
                 )
               ]
             ),
             child: IconButton(
                icon: Icon(player.isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded),
                color: Colors.white,
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
            color: player.hasNext ? iconColor : iconColor.withOpacity(0.5),
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
  Widget _buildAdaptiveRightPanel(PlayerService player, BuildContext context, ColorScheme colorScheme) {
    if (ThemeManager().isFluentFramework) {
      return _buildRightPanelFluent(player, context);
    }
    if (_isCupertino) {
      return _buildRightPanelCupertino(player, context);
    }
    return _buildRightPanel(player, colorScheme, context);
  }

  /// iOS Cupertino 风格右侧面板
  Widget _buildRightPanelCupertino(PlayerService player, BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        ValueListenableBuilder<Duration>(
          valueListenable: player.positionNotifier,
          builder: (context, position, child) {
            return Text(
              _formatDuration(position),
              style: TextStyle(
                fontSize: 12,
                color: CupertinoColors.systemGrey,
              ),
            );
          },
        ),
        Text(
          ' / ',
          style: TextStyle(
            fontSize: 12,
            color: CupertinoColors.systemGrey,
          ),
        ),
        Text(
          _formatDuration(player.duration),
          style: TextStyle(
            fontSize: 12,
            color: CupertinoColors.systemGrey,
          ),
        ),
        const SizedBox(width: 12),
        CupertinoButton(
          padding: const EdgeInsets.all(8),
          minSize: 0,
          onPressed: () => _showVolumeDialog(context, player),
          child: Icon(
            _volumeIconCupertino(player.volume),
            color: CupertinoColors.activeBlue,
            size: 22,
          ),
        ),
        CupertinoButton(
          padding: const EdgeInsets.all(8),
          minSize: 0,
          onPressed: () => _showQueueSheet(context),
          child: Icon(
            CupertinoIcons.music_note_list,
            color: CupertinoColors.activeBlue,
            size: 22,
          ),
        ),
      ],
    );
  }

  IconData _volumeIconCupertino(double volume) {
    if (volume == 0) return CupertinoIcons.volume_off;
    if (volume < 0.5) return CupertinoIcons.volume_down;
    return CupertinoIcons.volume_up;
  }

  /// 右侧面板（时长 + 音量 + 列表）- Material 风格
  Widget _buildRightPanel(PlayerService player, ColorScheme colorScheme, BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        // 时长
        ValueListenableBuilder<Duration>(
          valueListenable: player.positionNotifier,
          builder: (context, position, child) {
            return Text(
              _formatDuration(position),
              style: TextStyle(
                fontSize: 12,
                color: colorScheme.onSurfaceVariant,
              ),
            );
          },
        ),
        const Text(' / '),
        Text(
          _formatDuration(player.duration),
          style: TextStyle(
            fontSize: 12,
            color: colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(width: 12),
        // 音量
        IconButton(
          icon: Icon(_volumeIcon(player.volume), color: colorScheme.onSurface),
          tooltip: '音量',
          onPressed: () => _showVolumeDialog(context, player),
        ),
        // 列表
        IconButton(
          icon: Icon(Icons.queue_music_rounded, color: colorScheme.onSurface),
          tooltip: '播放列表',
          onPressed: () => _showQueueSheet(context),
        ),
      ],
    );
  }

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
                              color: CupertinoColors.systemGrey.withOpacity(0.3),
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
                            color: CupertinoColors.systemGrey.withOpacity(0.3),
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
    final currentTrack = PlayerService().currentTrack;
    final historyTracks = history.map((h) => h.toTrack()).toList();

    // 与全屏播放器一致：优先展示播放队列，否则展示播放历史
    final bool hasQueue = queueService.hasQueue;
    final List<dynamic> displayList = hasQueue
        ? queueService.queue
        : historyTracks;

    if (ThemeManager().isFluentFramework) {
      await fluent.showDialog(
        context: context,
        builder: (context) {
          return fluent.ContentDialog(
            title: Text(hasQueue ? '播放队列' : '播放历史'),
            content: SizedBox(
              width: 520,
              height: 420,
              child: displayList.isEmpty
                  ? const Center(child: Text('播放列表为空'))
                  : ListView.separated(
                      itemCount: displayList.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 8),
                      itemBuilder: (context, i) {
                        final Track t = displayList[i] as Track;
                        final isCurrent = currentTrack != null &&
                            t.id.toString() == currentTrack.id.toString() &&
                            t.source == currentTrack.source;
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
                                ? WidgetStateProperty.all(
                                    fluent.FluentTheme.of(context).resources.controlFillColorSecondary,
                                  )
                                : null,
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
      return;
    }
    
    // iOS Cupertino 风格
    if (_isCupertino) {
      final isDark = Theme.of(context).brightness == Brightness.dark;
      final media = MediaQuery.of(context);
      final isLandscape = media.orientation == Orientation.landscape;
      final sheetHeight = media.size.height * (isLandscape ? 0.72 : 0.6);
      bool insertNextMode = false;
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
                                color: CupertinoColors.systemGrey.withOpacity(0.3),
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
                                    minSize: 0,
                                    onPressed: () => setState(() => insertNextMode = !insertNextMode),
                                    child: Text(
                                      insertNextMode ? '取消追加' : '追加下一首',
                                      style: TextStyle(
                                        fontSize: 13,
                                        color: insertNextMode
                                            ? CupertinoColors.activeBlue
                                            : CupertinoColors.systemGrey,
                                      ),
                                    ),
                                  ),
                                  CupertinoButton(
                                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                    minSize: 0,
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
                                            final isCurrent = currentTrack != null &&
                                                t.id.toString() == currentTrack.id.toString() &&
                                                t.source == currentTrack.source;
                                            final content = Container(
                                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                                              decoration: BoxDecoration(
                                                color: isCurrent
                                                    ? CupertinoColors.activeBlue.withOpacity(0.1)
                                                    : null,
                                              ),
                                              child: Row(
                                                children: [
                                                  ClipRRect(
                                                    borderRadius: BorderRadius.circular(6),
                                                    child: (t.picUrl.startsWith('http') || t.picUrl.startsWith('https'))
                                                        ? CachedNetworkImage(
                                                            imageUrl: t.picUrl,
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
                                                  if (insertNextMode) {
                                                    queueService.insertNext(t);
                                                    ScaffoldMessenger.of(context).showSnackBar(
                                                      const SnackBar(content: Text('已追加到下一首'), duration: Duration(seconds: 1)),
                                                    );
                                                    return;
                                                  }
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
                                            final isCurrent = currentTrack != null &&
                                                t.id.toString() == currentTrack.id.toString() &&
                                                t.source == currentTrack.source;
                                            return GestureDetector(
                                              behavior: HitTestBehavior.opaque,
                                              onTap: () {
                                                if (insertNextMode) {
                                                  queueService.insertNext(t);
                                                  ScaffoldMessenger.of(context).showSnackBar(
                                                    const SnackBar(content: Text('已追加到下一首'), duration: Duration(seconds: 1)),
                                                  );
                                                  return;
                                                }
                                                final coverProvider = PlaylistQueueService().getCoverProvider(t);
                                                PlayerService().playTrack(t, coverProvider: coverProvider);
                                                Navigator.pop(context);
                                              },
                                              child: Container(
                                                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                                                decoration: BoxDecoration(
                                                  color: isCurrent
                                                      ? CupertinoColors.activeBlue.withOpacity(0.1)
                                                      : null,
                                                ),
                                                child: Row(
                                                  children: [
                                                    ClipRRect(
                                                      borderRadius: BorderRadius.circular(6),
                                                      child: (t.picUrl.startsWith('http') || t.picUrl.startsWith('https'))
                                                          ? CachedNetworkImage(
                                                              imageUrl: t.picUrl,
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
    bool insertNextMode = false;

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
                                onPressed: () => setState(() => insertNextMode = !insertNextMode),
                                child: Text(insertNextMode ? '取消追加' : '追加下一首'),
                              ),
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
                                        final isCurrent = currentTrack != null &&
                                            t.id.toString() == currentTrack.id.toString() &&
                                            t.source == currentTrack.source;

                                        final tile = ListTile(
                                          tileColor: isCurrent ? colorScheme.surfaceContainerHigh : null,
                                          leading: ClipRRect(
                                            borderRadius: BorderRadius.circular(4),
                                            child: (t.picUrl.startsWith('http') || t.picUrl.startsWith('https'))
                                              ? CachedNetworkImage(
                                                  imageUrl: t.picUrl,
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
                                          trailing: ReorderableDelayedDragStartListener(
                                            index: i,
                                            child: Icon(Icons.drag_handle_rounded, color: colorScheme.onSurfaceVariant),
                                          ),
                                          onTap: () {
                                            if (insertNextMode) {
                                              queueService.insertNext(t);
                                              ScaffoldMessenger.of(context).showSnackBar(
                                                const SnackBar(content: Text('已追加到下一首'), duration: Duration(seconds: 1)),
                                              );
                                              return;
                                            }
                                            final coverProvider = PlaylistQueueService().getCoverProvider(t);
                                            PlayerService().playTrack(t, coverProvider: coverProvider);
                                            Navigator.pop(context);
                                            ScaffoldMessenger.of(context).showSnackBar(
                                              SnackBar(content: Text('正在播放: ${t.name}'), duration: const Duration(seconds: 1)),
                                            );
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
                                        final isCurrent = currentTrack != null &&
                                            t.id.toString() == currentTrack.id.toString() &&
                                            t.source == currentTrack.source;

                                        return ListTile(
                                          tileColor: isCurrent ? colorScheme.surfaceContainerHigh : null,
                                          leading: ClipRRect(
                                            borderRadius: BorderRadius.circular(4),
                                            child: (t.picUrl.startsWith('http') || t.picUrl.startsWith('https'))
                                              ? CachedNetworkImage(
                                                  imageUrl: t.picUrl,
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
                                          onTap: () {
                                            if (insertNextMode) {
                                              queueService.insertNext(t);
                                              ScaffoldMessenger.of(context).showSnackBar(
                                                const SnackBar(content: Text('已追加到下一首'), duration: Duration(seconds: 1)),
                                              );
                                              return;
                                            }
                                            final coverProvider = PlaylistQueueService().getCoverProvider(t);
                                            PlayerService().playTrack(t, coverProvider: coverProvider);
                                            Navigator.pop(context);
                                            ScaffoldMessenger.of(context).showSnackBar(
                                              SnackBar(content: Text('正在播放: ${t.name}'), duration: const Duration(seconds: 1)),
                                            );
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

  /// 格式化时长
  String _formatDuration(Duration duration) {
    final minutes = duration.inMinutes;
    final seconds = duration.inSeconds % 60;
    return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }
}

