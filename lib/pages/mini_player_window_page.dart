import 'dart:io';
import 'dart:ui';
import 'package:fluent_ui/fluent_ui.dart' as fluent;
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:window_manager/window_manager.dart';
import '../models/track.dart';
import '../services/desktop_lyric_service.dart';
import '../services/player_service.dart';
import '../services/mini_player_window_service.dart';
import '../services/playlist_queue_service.dart';

/// 迷你播放器窗口页面
/// 类似 Apple Music 的迷你播放器
/// 布局：上方封面+歌曲信息，中间进度条，下方控制按钮
class MiniPlayerWindowPage extends StatefulWidget {
  const MiniPlayerWindowPage({super.key});

  @override
  State<MiniPlayerWindowPage> createState() => _MiniPlayerWindowPageState();
}

class _MiniPlayerWindowPageState extends State<MiniPlayerWindowPage>
    with SingleTickerProviderStateMixin, WindowListener {
  static const double _queuePanelTargetHeight = 760;
  static const double _queuePanelMinHeight = 560;

  bool _isQueuePanelOpen = false;
  bool _isQueuePanelVisible = false;

  Size? _restoreSize;
  Offset? _restorePosition;
  Size? _lastKnownSize;
  Offset? _lastKnownPosition;
  bool _isWindowMetricsUpdating = false;
  Offset? _anchorPosition;

  late final AnimationController _queuePanelController;
  late final Animation<double> _queuePanelCurve;
  double? _collapsedHeight;
  double? _expandedHeight;
  double _lastAppliedWindowHeight = -1;

  int? _hoveredQueueIndex;

  @override
  void initState() {
    super.initState();
    if (Platform.isWindows) {
      windowManager.addListener(this);
      _refreshWindowMetrics();
    }

    PlayerService().addListener(_onPlayerServiceChanged);

    _queuePanelController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 220),
    );
    _queuePanelCurve = CurvedAnimation(
      parent: _queuePanelController,
      curve: Curves.easeInOutCubic,
    );
    _queuePanelController.addListener(_syncWindowSizeWithQueueAnimation);
    _queuePanelController.addStatusListener((status) {
      if (!Platform.isWindows) return;
      if (status == AnimationStatus.completed) {
        final width = _restoreSize?.width ?? MiniPlayerWindowService.miniPlayerSize.width;
        final minWidth = width < MiniPlayerWindowService.miniPlayerMinSize.width
            ? MiniPlayerWindowService.miniPlayerMinSize.width
            : width;
        windowManager.setMinimumSize(Size(minWidth, _queuePanelMinHeight));
      }
      if (status == AnimationStatus.dismissed) {
        windowManager.setMinimumSize(MiniPlayerWindowService.miniPlayerMinSize);
        windowManager.setSize(_restoreSize ?? MiniPlayerWindowService.miniPlayerSize);
        if (_restorePosition != null) {
          windowManager.setPosition(_restorePosition!);
        }
        if (mounted) {
          setState(() {
            _isQueuePanelVisible = false;
          });
        } else {
          _isQueuePanelVisible = false;
        }
      }
    });
  }

  @override
  void dispose() {
    if (Platform.isWindows) {
      windowManager.removeListener(this);
    }
    PlayerService().removeListener(_onPlayerServiceChanged);
    _queuePanelController.removeListener(_syncWindowSizeWithQueueAnimation);
    _queuePanelController.dispose();
    super.dispose();
  }

  void _onPlayerServiceChanged() {
    if (!mounted) return;
    setState(() {});
  }

  Future<void> _refreshWindowMetrics() async {
    if (!Platform.isWindows) return;
    if (_isWindowMetricsUpdating) return;
    _isWindowMetricsUpdating = true;
    try {
      _lastKnownPosition = await windowManager.getPosition();
      _lastKnownSize = await windowManager.getSize();
    } finally {
      _isWindowMetricsUpdating = false;
    }
  }

  @override
  void onWindowMove() {
    if (_queuePanelController.isAnimating) return;
    _refreshWindowMetrics();
  }

  @override
  void onWindowResize() {
    if (_queuePanelController.isAnimating) return;
    _refreshWindowMetrics();
  }

  void _syncWindowSizeWithQueueAnimation() {
    if (!Platform.isWindows) return;
    if (_collapsedHeight == null || _expandedHeight == null) return;

    final t = _queuePanelCurve.value;
    final rawHeight = _collapsedHeight! + (_expandedHeight! - _collapsedHeight!) * t;
    final height = rawHeight.roundToDouble();
    if ((_lastAppliedWindowHeight - height).abs() < 2.0) return;
    _lastAppliedWindowHeight = height;

    final width = _restoreSize?.width ?? MiniPlayerWindowService.miniPlayerSize.width;
    windowManager.setSize(Size(width, height));
  }

  Future<void> _openQueuePanel() async {
    if (_isQueuePanelOpen) return;

    try {
      if (Platform.isWindows) {
        await _refreshWindowMetrics();
        _restoreSize = _lastKnownSize ?? await windowManager.getSize();
        _restorePosition = _lastKnownPosition ?? await windowManager.getPosition();
        if (_restorePosition != null) {
          _anchorPosition = Offset(
            _restorePosition!.dx.roundToDouble(),
            _restorePosition!.dy.roundToDouble(),
          );
          await windowManager.setPosition(_anchorPosition!);
        }

        final width = _restoreSize?.width ?? MiniPlayerWindowService.miniPlayerSize.width;
        final minWidth = width < MiniPlayerWindowService.miniPlayerMinSize.width
            ? MiniPlayerWindowService.miniPlayerMinSize.width
            : width;
        _collapsedHeight = (_restoreSize?.height ?? MiniPlayerWindowService.miniPlayerSize.height).toDouble();
        _expandedHeight = _queuePanelTargetHeight;
        _lastAppliedWindowHeight = -1;
        await windowManager.setMinimumSize(Size(minWidth, MiniPlayerWindowService.miniPlayerMinSize.height));
      }
    } finally {
      if (mounted) {
        setState(() {
          _isQueuePanelOpen = true;
          _isQueuePanelVisible = true;
        });
      }
    }

    _queuePanelController.forward(from: 0);
  }

  Future<void> _closeQueuePanel() async {
    if (!_isQueuePanelOpen) return;

    if (Platform.isWindows) {
      await _refreshWindowMetrics();
      _restorePosition = _lastKnownPosition ?? _restorePosition;
      if (_restorePosition != null) {
        _anchorPosition = Offset(
          _restorePosition!.dx.roundToDouble(),
          _restorePosition!.dy.roundToDouble(),
        );
        await windowManager.setPosition(_anchorPosition!);
      }
    }

    if (mounted) {
      setState(() {
        _isQueuePanelOpen = false;
      });
    } else {
      _isQueuePanelOpen = false;
    }

    _queuePanelController.reverse(from: 1);
  }

  Future<void> _showVolumeDialog(PlayerService player) async {
    if (!mounted) return;

    var volume = player.volume.clamp(0.0, 1.0);

    await fluent.showDialog<void>(
      context: context,
      builder: (context) {
        final size = MediaQuery.of(context).size;
        return fluent.ContentDialog(
          constraints: BoxConstraints(
            maxWidth: (size.width * 0.92).clamp(280.0, 420.0),
            maxHeight: (size.height * 0.9).clamp(200.0, 420.0),
          ),
          title: const Text('音量'),
          content: StatefulBuilder(
            builder: (context, setState) {
              return Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  fluent.Slider(
                    value: volume,
                    min: 0.0,
                    max: 1.0,
                    onChanged: (v) {
                      setState(() {
                        volume = v;
                      });
                      player.setVolume(v);
                    },
                  ),
                  Text('${(volume * 100).round()}%'),
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
  }

  Future<void> _toggleDesktopLyric() async {
    if (!Platform.isWindows) return;
    await DesktopLyricService().toggle();
  }

  Future<void> _showQueueDialog(PlayerService player) async {
    if (!mounted) return;

    final queueService = PlaylistQueueService();
    final queue = queueService.queue;
    final currentIndex = queueService.currentIndex;

    await fluent.showDialog<void>(
      context: context,
      builder: (context) {
        final theme = fluent.FluentTheme.of(context);
        final size = MediaQuery.of(context).size;
        final contentWidth = (size.width * 0.95).clamp(300.0, 520.0);
        final contentHeight = (size.height * 0.75).clamp(220.0, 520.0);
        return fluent.ContentDialog(
          constraints: BoxConstraints(
            maxWidth: contentWidth,
            maxHeight: (size.height * 0.9).clamp(260.0, 720.0),
          ),
          title: Text(queue.isEmpty ? '播放队列' : '播放队列 (${queue.length})'),
          content: SizedBox(
            width: contentWidth,
            height: contentHeight,
            child: queue.isEmpty
                ? const Text('无播放队列')
                : ListView.builder(
                    shrinkWrap: true,
                    itemCount: queue.length,
                    itemBuilder: (context, index) {
                      final Track t = queue[index];
                      final bool isCurrent = index == currentIndex;
                      return Container(
                        decoration: BoxDecoration(
                          color: isCurrent ? theme.resources.controlFillColorSecondary : null,
                          border: Border(
                            bottom: BorderSide(
                              color: theme.resources.dividerStrokeColorDefault,
                              width: 0.6,
                            ),
                          ),
                        ),
                        child: fluent.ListTile(
                          title: Text(
                            t.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontWeight: isCurrent ? FontWeight.w700 : FontWeight.w400,
                            ),
                          ),
                          subtitle: Text(
                            t.artists,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          trailing: isCurrent
                              ? const Icon(Icons.equalizer_rounded, size: 18)
                              : null,
                          onPressed: () async {
                            final coverProvider = queueService.getCoverProvider(t);
                            queueService.playTrack(t);
                            await player.playTrack(
                              t,
                              coverProvider: coverProvider,
                              fromPlaylist: queueService.source == QueueSource.playlist,
                            );
                            if (context.mounted) {
                              Navigator.of(context).pop();
                            }
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
  }

  String _formatDuration(Duration duration) {
    final minutes = duration.inMinutes;
    final seconds = duration.inSeconds % 60;
    return '$minutes:${seconds.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: PlayerService(),
      builder: (context, _) {
        final player = PlayerService();
        final track = player.currentTrack;
        final song = player.currentSong;
        final materialTheme = Theme.of(context);
        final fluentTheme = fluent.FluentTheme.of(context);
        final materialThemeWithYaHei = materialTheme.copyWith(
          textTheme: materialTheme.textTheme.apply(fontFamily: 'Microsoft YaHei'),
          primaryTextTheme: materialTheme.primaryTextTheme.apply(fontFamily: 'Microsoft YaHei'),
        );

        // 获取封面URL
        final coverUrl = song?.pic ?? track?.picUrl ?? '';

        return ValueListenableBuilder<Color?>(
          valueListenable: PlayerService().themeColorNotifier,
          builder: (context, themeColorValue, _) {
            // 获取主题色
            final themeColor = themeColorValue ?? Colors.grey[700]!;

            // 计算背景色（更浅的灰色调，类似参考图）
            final backgroundColor = Color.lerp(themeColor, Colors.grey[600]!, 0.7)!;

        return fluent.FluentTheme(
          data: fluentTheme,
          child: Theme(
            data: materialThemeWithYaHei,
            child: DefaultTextStyle.merge(
              style: const TextStyle(fontFamily: 'Microsoft YaHei'),
              child: Scaffold(
                backgroundColor: Colors.transparent,
                body: ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: GestureDetector(
                    behavior: HitTestBehavior.translucent,
                    onPanStart: (_) => windowManager.startDragging(),
                    child: Stack(
                      children: [
                        // 背景层
                        Positioned.fill(
                          child: _buildBackground(coverUrl, backgroundColor),
                        ),

                        // 主要内容（垂直布局）
                        Positioned.fill(
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                            child: Column(
                              children: [
                                // 原迷你播放器布局保持不变
                                GestureDetector(
                                  behavior: HitTestBehavior.translucent,
                                  onDoubleTap: () async {
                                    await Future.delayed(const Duration(milliseconds: 50));
                                    if (mounted) {
                                      await MiniPlayerWindowService().exitMiniMode();
                                    }
                                  },
                                  child: _buildTopRow(track, song, coverUrl),
                                ),

                                const SizedBox(height: 8),

                                if (_isQueuePanelVisible) ...[
                                  Expanded(
                                    child: FadeTransition(
                                      opacity: _queuePanelCurve,
                                      child: SlideTransition(
                                        position: Tween<Offset>(
                                          begin: const Offset(0, 0.03),
                                          end: Offset.zero,
                                        ).animate(_queuePanelCurve),
                                        child: _buildQueuePanel(player),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(height: 12),
                                ],

                                _buildProgressRow(player),

                                const SizedBox(height: 4),

                                _buildControlsRow(player),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
          },  // ValueListenableBuilder builder
        );  // ValueListenableBuilder
      },
    );
  }

  Widget _buildQueuePanel(PlayerService player) {
    final queueService = PlaylistQueueService();
    final queue = queueService.queue;
    final currentTrack = player.currentTrack;

    return queue.isEmpty
        ? Center(
            child: Text(
              '无播放队列',
              style: TextStyle(color: Colors.white.withOpacity(0.75)),
            ),
          )
        : ListView.separated(
            itemCount: queue.length,
            separatorBuilder: (_, __) => Container(
              height: 1,
              margin: const EdgeInsets.only(left: 64, right: 10),
              color: Colors.white.withOpacity(0.10),
            ),
            itemBuilder: (context, index) {
              final t = queue[index];
              final isCurrent = currentTrack != null &&
                  t.id.toString() == currentTrack.id.toString() &&
                  t.source == currentTrack.source;

              final isHovered = _hoveredQueueIndex == index;

              return MouseRegion(
                cursor: SystemMouseCursors.click,
                onEnter: (_) {
                  if (!mounted) return;
                  setState(() {
                    _hoveredQueueIndex = index;
                  });
                },
                onExit: (_) {
                  if (!mounted) return;
                  setState(() {
                    if (_hoveredQueueIndex == index) {
                      _hoveredQueueIndex = null;
                    }
                  });
                },
                child: _QueueListItem(
                  track: t,
                  cover: _queueCover(t),
                  isCurrent: isCurrent,
                  isHovered: isHovered,
                  onTap: () async {
                    final coverProvider = queueService.getCoverProvider(t);
                    queueService.playTrack(t);
                    await player.playTrack(
                      t,
                      coverProvider: coverProvider,
                      fromPlaylist: queueService.source == QueueSource.playlist,
                    );
                  },
                ),
              );
            },
          );
  }

  Widget _queueCover(Track t) {
    final cachedProvider = PlaylistQueueService().getCoverProvider(t);
    if (cachedProvider != null) {
      return Image(image: cachedProvider, width: 44, height: 44, fit: BoxFit.cover);
    }

    if (t.picUrl.isEmpty) {
      return Container(
        width: 44,
        height: 44,
        color: Colors.white.withOpacity(0.12),
        child: const Icon(Icons.music_note, size: 18, color: Colors.white70),
      );
    }

    return CachedNetworkImage(
      imageUrl: t.picUrl,
      imageBuilder: (context, imageProvider) {
        PlaylistQueueService().updateCoverProvider(t, imageProvider);
        return Image(image: imageProvider, width: 44, height: 44, fit: BoxFit.cover);
      },
      placeholder: (_, __) => Container(
        width: 44,
        height: 44,
        color: Colors.white.withOpacity(0.12),
      ),
      errorWidget: (_, __, ___) => Container(
        width: 44,
        height: 44,
        color: Colors.white.withOpacity(0.12),
        child: const Icon(Icons.music_note, size: 18, color: Colors.white70),
      ),
    );
  }

  /// 构建背景
  Widget _buildBackground(String coverUrl, Color backgroundColor) {
    return Stack(
      fit: StackFit.expand,
      children: [
        // 专辑封面作为背景
        if (coverUrl.isNotEmpty)
          CachedNetworkImage(
            imageUrl: coverUrl,
            fit: BoxFit.cover,
            memCacheWidth: 1080,
            memCacheHeight: 1080,
            errorWidget: (_, __, ___) => Container(color: backgroundColor),
          ),
        
        // 模糊 + 半透明遮罩
        BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 40, sigmaY: 40),
          child: Container(
            color: backgroundColor.withOpacity(0.85),
          ),
        ),
        
        // 边框
        Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: Colors.white.withOpacity(0.15),
              width: 1,
            ),
          ),
        ),
      ],
    );
  }

  /// 构建顶部行：封面 + 歌曲信息 + 返回按钮
  Widget _buildTopRow(dynamic track, dynamic song, String coverUrl) {
    final name = song?.name ?? track?.name ?? '未知歌曲';
    final artist = song?.arName ?? track?.artists ?? '未知歌手';
    final album = song?.alName ?? track?.album ?? '';
    
    // 组合歌手和专辑名
    final subtitle = album.isNotEmpty ? '$artist — $album' : artist;
    
    return Row(
      children: [
        // 封面
        Container(
          width: 56,
          height: 56,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(6),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.2),
                blurRadius: 6,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: coverUrl.isNotEmpty
                ? CachedNetworkImage(
                    imageUrl: coverUrl,
                    fit: BoxFit.cover,
                    placeholder: (_, __) => Container(
                      color: Colors.grey[700],
                      child: const Icon(Icons.music_note, color: Colors.white54, size: 24),
                    ),
                    errorWidget: (_, __, ___) => Container(
                      color: Colors.grey[700],
                      child: const Icon(Icons.music_note, color: Colors.white54, size: 24),
                    ),
                  )
                : Container(
                    color: Colors.grey[700],
                    child: const Icon(Icons.music_note, color: Colors.white54, size: 24),
                  ),
          ),
        ),
        
        const SizedBox(width: 12),
        
        // 歌曲信息
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              // 歌曲名
              Text(
                name,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 2),
              // 歌手 — 专辑
              Text(
                subtitle,
                style: TextStyle(
                  color: Colors.white.withOpacity(0.7),
                  fontSize: 12,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
        
        const SizedBox(width: 8),
        
        // 返回全屏按钮
        Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: () async {
              await Future.delayed(const Duration(milliseconds: 50));
              if (mounted) {
                await MiniPlayerWindowService().exitMiniMode();
              }
            },
            borderRadius: BorderRadius.circular(6),
            child: Padding(
              padding: const EdgeInsets.all(6),
              child: Icon(
                Icons.fullscreen_exit_rounded,
                color: Colors.white.withOpacity(0.85),
                size: 20,
              ),
            ),
          ),
        ),
      ],
    );
  }

  /// 构建进度条行
  Widget _buildProgressRow(PlayerService player) {
    final progress = player.duration.inMilliseconds > 0
        ? player.position.inMilliseconds / player.duration.inMilliseconds
        : 0.0;
    
    return Row(
      children: [
        // 当前时间
        Text(
          _formatDuration(player.position),
          style: TextStyle(
            color: Colors.white.withOpacity(0.6),
            fontSize: 11,
          ),
        ),
        
        const SizedBox(width: 8),
        
        // 进度条
        Expanded(
          child: SizedBox(
            height: 4,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(2),
              child: LinearProgressIndicator(
                value: progress.clamp(0.0, 1.0),
                backgroundColor: Colors.white.withOpacity(0.2),
                valueColor: AlwaysStoppedAnimation<Color>(
                  Colors.white.withOpacity(0.7),
                ),
              ),
            ),
          ),
        ),
        
        const SizedBox(width: 8),
        
        // 总时长
        Text(
          _formatDuration(player.duration),
          style: TextStyle(
            color: Colors.white.withOpacity(0.6),
            fontSize: 11,
          ),
        ),
      ],
    );
  }

  /// 构建控制按钮行
  Widget _buildControlsRow(PlayerService player) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        // 音量按钮
        _buildControlButton(
          icon: Icons.volume_up_rounded,
          onPressed: () => _showVolumeDialog(player),
          size: 20,
        ),
        
        const SizedBox(width: 8),
        
        // 更多按钮
        _buildControlButton(
          icon: Icons.more_horiz_rounded,
          onPressed: () {},
          size: 20,
        ),
        
        const SizedBox(width: 12),
        
        // 上一首
        _buildControlButton(
          icon: Icons.fast_rewind_rounded,
          onPressed: player.hasPrevious ? () => player.playPrevious() : null,
          size: 24,
        ),
        
        const SizedBox(width: 8),
        
        // 播放/暂停
        _buildControlButton(
          icon: player.isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
          onPressed: () => player.togglePlayPause(),
          size: 28,
          isPrimary: true,
        ),
        
        const SizedBox(width: 8),
        
        // 下一首
        _buildControlButton(
          icon: Icons.fast_forward_rounded,
          onPressed: player.hasNext ? () => player.playNext() : null,
          size: 24,
        ),
        
        const SizedBox(width: 12),
        
        // 歌词按钮
        _buildControlButton(
          icon: Icons.subtitles_rounded,
          onPressed: Platform.isWindows ? () => _toggleDesktopLyric() : null,
          size: 20,
        ),
        
        const SizedBox(width: 8),
        
        // 播放列表按钮
        _buildControlButton(
          icon: Icons.queue_music_rounded,
          onPressed: _queuePanelController.isAnimating
              ? null
              : (_isQueuePanelOpen ? _closeQueuePanel : _openQueuePanel),
          size: 20,
        ),
      ],
    );
  }

  /// 构建单个控制按钮
  Widget _buildControlButton({
    required IconData icon,
    required VoidCallback? onPressed,
    required double size,
    bool isPrimary = false,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(4),
          child: Icon(
            icon,
            color: onPressed != null
                ? (isPrimary ? Colors.white : Colors.white.withOpacity(0.85))
                : Colors.white.withOpacity(0.3),
            size: size,
          ),
        ),
      ),
    );
  }
}

class _QueueListItem extends StatelessWidget {
  const _QueueListItem({
    required this.track,
    required this.cover,
    required this.isCurrent,
    required this.isHovered,
    required this.onTap,
  });

  final Track track;
  final Widget cover;
  final bool isCurrent;
  final bool isHovered;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final backgroundOpacity = isCurrent ? 0.18 : (isHovered ? 0.10 : 0.0);

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 140),
        curve: Curves.easeOutCubic,
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(backgroundOpacity),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: cover,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    track.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 13,
                      fontWeight: isCurrent ? FontWeight.w700 : FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    track.artists,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: Colors.white.withOpacity(isCurrent ? 0.85 : 0.75),
                      fontSize: 11.5,
                      fontWeight: FontWeight.w400,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            AnimatedOpacity(
              duration: const Duration(milliseconds: 140),
              opacity: isCurrent ? 1 : (isHovered ? 0.9 : 0.0),
              child: Icon(
                isCurrent ? Icons.equalizer_rounded : Icons.play_arrow_rounded,
                size: 18,
                color: Colors.white.withOpacity(0.9),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
