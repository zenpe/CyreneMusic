import 'dart:io';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/services.dart';
import '../../services/sleep_timer_service.dart';
import '../../services/playlist_service.dart';
import '../../services/playlist_queue_service.dart';
import '../../services/play_history_service.dart';
import '../../services/playback_mode_service.dart';
import '../../services/player_service.dart';
import '../../services/system_volume_service.dart';
import '../../utils/image_utils.dart';
import '../../utils/toast_utils.dart';
import '../../models/track.dart';
import '../../widgets/track_action_menu.dart';

/// 移动端播放器对话框工具类
/// 包含睡眠定时器、添加到歌单、播放列表、音量调节等对话框
class MobilePlayerDialogs {
  /// 显示轻量音量调节悬浮气泡
  static Future<void> showVolumePopup(
    BuildContext context, {
    GlobalKey? buttonKey,
  }) async {
    final player = PlayerService();
    final systemService = SystemVolumeService();
    bool systemSupported = false;
    double systemTemp = 0.0;
    try {
      systemSupported = await systemService.isSupported();
      if (systemSupported) {
        systemTemp = (await systemService.getVolume()) ?? player.volume;
      }
    } catch (_) {}

    final overlay = Overlay.of(context);
    final overlayBox = overlay.context.findRenderObject() as RenderBox?;
    final screenSize = overlayBox?.size ?? MediaQuery.of(context).size;

    final cardWidth = (screenSize.width - 48).clamp(240.0, 320.0);
    final cardHeight = systemSupported ? 116.0 : 64.0;
    const double padding = 12.0;

    double left = (screenSize.width - cardWidth) / 2;
    double top = screenSize.height * 0.75;

    if (buttonKey != null &&
        buttonKey.currentContext != null &&
        overlayBox != null) {
      final renderBox =
          buttonKey.currentContext!.findRenderObject() as RenderBox?;
      if (renderBox != null) {
        final target = renderBox.localToGlobal(
          Offset.zero,
          ancestor: overlayBox,
        );
        final size = renderBox.size;
        final preferredTop = target.dy - cardHeight - padding;
        top = preferredTop >= 60
            ? preferredTop
            : target.dy + size.height + padding;
        left = (target.dx + size.width / 2 - cardWidth / 2).clamp(
          16.0,
          screenSize.width - cardWidth - 16.0,
        );
      }
    }

    double appTemp = player.volume;
    if (!context.mounted) return;

    await showGeneralDialog(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'VolumePopup',
      barrierColor: Colors.transparent,
      transitionDuration: const Duration(milliseconds: 180),
      transitionBuilder: (context, anim, _, child) {
        return FadeTransition(
          opacity: CurvedAnimation(parent: anim, curve: Curves.easeOutCubic),
          child: ScaleTransition(
            scale: Tween<double>(begin: 0.92, end: 1.0).animate(
              CurvedAnimation(parent: anim, curve: Curves.easeOutCubic),
            ),
            child: child,
          ),
        );
      },
      pageBuilder: (context, _, __) {
        final isDark = Theme.of(context).brightness == Brightness.dark;

        return Stack(
          children: [
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.translucent,
                onTap: () => Navigator.of(context).pop(),
              ),
            ),
            Positioned(
              left: left,
              top: top,
              child: Material(
                color: Colors.transparent,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(20),
                  child: BackdropFilter(
                    filter: ImageFilter.blur(sigmaX: 25, sigmaY: 25),
                    child: Container(
                      width: cardWidth,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 12,
                      ),
                      decoration: BoxDecoration(
                        color: (isDark ? const Color(0xFF1E1E24) : Colors.white)
                            .withValues(alpha: 0.92),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: Colors.white.withValues(
                            alpha: isDark ? 0.12 : 0.3,
                          ),
                          width: 0.8,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.35),
                            blurRadius: 24,
                            offset: const Offset(0, 8),
                          ),
                        ],
                      ),
                      child: StatefulBuilder(
                        builder: (context, setLocal) {
                          Widget buildRow({
                            required IconData icon,
                            required String label,
                            required double value,
                            required ValueChanged<double> onChanged,
                          }) {
                            return Row(
                              children: [
                                Icon(
                                  value == 0
                                      ? Icons.volume_off_rounded
                                      : value < 0.5
                                      ? Icons.volume_down_rounded
                                      : Icons.volume_up_rounded,
                                  size: 20,
                                  color: isDark
                                      ? Colors.white70
                                      : Colors.black87,
                                ),
                                if (systemSupported) ...[
                                  const SizedBox(width: 6),
                                  Text(
                                    label,
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600,
                                      color: isDark
                                          ? Colors.white70
                                          : Colors.black87,
                                    ),
                                  ),
                                ],
                                const SizedBox(width: 8),
                                Expanded(
                                  child: SliderTheme(
                                    data: SliderTheme.of(context).copyWith(
                                      trackHeight: 4,
                                      thumbShape: const RoundSliderThumbShape(
                                        enabledThumbRadius: 7,
                                      ),
                                      overlayShape:
                                          const RoundSliderOverlayShape(
                                            overlayRadius: 14,
                                          ),
                                      activeTrackColor: isDark
                                          ? Colors.white
                                          : Colors.black87,
                                      inactiveTrackColor:
                                          (isDark ? Colors.white : Colors.black)
                                              .withValues(alpha: 0.15),
                                      thumbColor: isDark
                                          ? Colors.white
                                          : Colors.black87,
                                    ),
                                    child: Slider(
                                      value: value,
                                      min: 0.0,
                                      max: 1.0,
                                      onChanged: onChanged,
                                    ),
                                  ),
                                ),
                                SizedBox(
                                  width: 38,
                                  child: Text(
                                    '${(value * 100).toInt()}%',
                                    textAlign: TextAlign.end,
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.bold,
                                      color: isDark
                                          ? Colors.white70
                                          : Colors.black87,
                                      fontFamily: 'Consolas',
                                    ),
                                  ),
                                ),
                              ],
                            );
                          }

                          if (!systemSupported) {
                            return buildRow(
                              icon: Icons.volume_up_rounded,
                              label: '应用',
                              value: appTemp,
                              onChanged: (v) {
                                setLocal(() => appTemp = v);
                                player.setVolume(v);
                              },
                            );
                          }

                          return Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              buildRow(
                                icon: Icons.speaker,
                                label: '系统',
                                value: systemTemp,
                                onChanged: (v) {
                                  setLocal(() => systemTemp = v);
                                  systemService.setVolume(v);
                                },
                              ),
                              const SizedBox(height: 6),
                              buildRow(
                                icon: Icons.music_note,
                                label: '应用',
                                value: appTemp,
                                onChanged: (v) {
                                  setLocal(() => appTemp = v);
                                  player.setVolume(v);
                                },
                              ),
                            ],
                          );
                        },
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  /// 显示睡眠定时器对话框
  static void showSleepTimer(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => const MobileSleepTimerDialog(),
    );
  }

  /// 显示播放模式选择弹窗
  static void showPlaybackModeSelector(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final colorScheme = theme.colorScheme;
    final modeService = PlaybackModeService();

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withValues(alpha: 0.5),
      builder: (context) => ValueListenableBuilder<Color?>(
        valueListenable: PlayerService().themeColorNotifier,
        builder: (context, dynamicColor, _) {
          final accentColor = dynamicColor ?? colorScheme.primary;

          return ClipRRect(
            borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 25, sigmaY: 25),
              child: Container(
                decoration: BoxDecoration(
                  color: (isDark ? const Color(0xFF141418) : Colors.white)
                      .withValues(alpha: 0.92),
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(28),
                  ),
                  border: Border(
                    top: BorderSide(
                      color: Colors.white.withValues(
                        alpha: isDark ? 0.12 : 0.4,
                      ),
                      width: 0.8,
                    ),
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(
                        alpha: isDark ? 0.45 : 0.12,
                      ),
                      blurRadius: 30,
                      offset: const Offset(0, -10),
                    ),
                  ],
                ),
                child: SafeArea(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // 顶部指示条
                      Container(
                        margin: const EdgeInsets.only(top: 12, bottom: 8),
                        width: 38,
                        height: 4.5,
                        decoration: BoxDecoration(
                          color: isDark ? Colors.white24 : Colors.black12,
                          borderRadius: BorderRadius.circular(2.5),
                        ),
                      ),
                      // 标题行
                      Padding(
                        padding: const EdgeInsets.fromLTRB(20, 10, 20, 14),
                        child: Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(6),
                              decoration: BoxDecoration(
                                color: accentColor.withValues(
                                  alpha: isDark ? 0.18 : 0.1,
                                ),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Icon(
                                Icons.shuffle_rounded,
                                color: accentColor,
                                size: 20,
                              ),
                            ),
                            const SizedBox(width: 10),
                            Text(
                              '切换播放模式',
                              style: theme.textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.w800,
                                letterSpacing: -0.3,
                                color: colorScheme.onSurface,
                              ),
                            ),
                            const Spacer(),
                            IconButton(
                              icon: const Icon(Icons.close_rounded, size: 20),
                              onPressed: () => Navigator.pop(context),
                              style: IconButton.styleFrom(
                                backgroundColor: isDark
                                    ? Colors.white10
                                    : Colors.black.withValues(alpha: 0.05),
                              ),
                            ),
                          ],
                        ),
                      ),
                      // 4 种播放模式
                      AnimatedBuilder(
                        animation: modeService,
                        builder: (context, _) {
                          final currentMode = modeService.currentMode;
                          return Padding(
                            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                            child: Column(
                              children: [
                                _buildModeTile(
                                  context: context,
                                  title: '列表循环',
                                  subtitle: '循环播放当前列表所有歌曲',
                                  icon: Icons.repeat_rounded,
                                  isSelected:
                                      currentMode == PlaybackMode.loopAll,
                                  accentColor: accentColor,
                                  isDark: isDark,
                                  onTap: () {
                                    HapticFeedback.lightImpact();
                                    modeService.setMode(PlaybackMode.loopAll);
                                    ToastUtils.infoWithIcon(
                                      '列表循环',
                                      icon: Icons.repeat_rounded,
                                    );
                                    Navigator.pop(context);
                                  },
                                ),
                                const SizedBox(height: 8),
                                _buildModeTile(
                                  context: context,
                                  title: '随机播放',
                                  subtitle: '随机打乱播放队列中的歌曲',
                                  icon: Icons.shuffle_rounded,
                                  isSelected:
                                      currentMode == PlaybackMode.shuffle,
                                  accentColor: accentColor,
                                  isDark: isDark,
                                  onTap: () {
                                    HapticFeedback.lightImpact();
                                    modeService.setMode(PlaybackMode.shuffle);
                                    ToastUtils.infoWithIcon(
                                      '随机播放',
                                      icon: Icons.shuffle_rounded,
                                    );
                                    Navigator.pop(context);
                                  },
                                ),
                                const SizedBox(height: 8),
                                _buildModeTile(
                                  context: context,
                                  title: '单曲循环',
                                  subtitle: '单曲播放结束后自动重播',
                                  icon: Icons.repeat_one_rounded,
                                  isSelected:
                                      currentMode == PlaybackMode.repeatOne,
                                  accentColor: accentColor,
                                  isDark: isDark,
                                  onTap: () {
                                    HapticFeedback.lightImpact();
                                    modeService.setMode(PlaybackMode.repeatOne);
                                    ToastUtils.infoWithIcon(
                                      '单曲循环',
                                      icon: Icons.repeat_one_rounded,
                                    );
                                    Navigator.pop(context);
                                  },
                                ),
                                const SizedBox(height: 8),
                                _buildModeTile(
                                  context: context,
                                  title: '顺序播放',
                                  subtitle: '按顺序播放，播完最后一首后停止',
                                  icon: Icons.arrow_forward_rounded,
                                  isSelected:
                                      currentMode == PlaybackMode.sequential,
                                  accentColor: accentColor,
                                  isDark: isDark,
                                  onTap: () {
                                    HapticFeedback.lightImpact();
                                    modeService.setMode(
                                      PlaybackMode.sequential,
                                    );
                                    ToastUtils.infoWithIcon(
                                      '顺序播放',
                                      icon: Icons.arrow_forward_rounded,
                                    );
                                    Navigator.pop(context);
                                  },
                                ),
                              ],
                            ),
                          );
                        },
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  static Widget _buildModeTile({
    required BuildContext context,
    required String title,
    required String subtitle,
    required IconData icon,
    required bool isSelected,
    required Color accentColor,
    required bool isDark,
    required VoidCallback onTap,
  }) {
    final colorScheme = Theme.of(context).colorScheme;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: isSelected
                ? accentColor.withValues(alpha: isDark ? 0.18 : 0.1)
                : (isDark
                      ? Colors.white.withValues(alpha: 0.04)
                      : Colors.black.withValues(alpha: 0.03)),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: isSelected
                  ? accentColor.withValues(alpha: isDark ? 0.35 : 0.25)
                  : Colors.white.withValues(alpha: isDark ? 0.06 : 0.1),
              width: isSelected ? 1.2 : 0.8,
            ),
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: isSelected
                      ? accentColor
                      : (isDark
                            ? Colors.white10
                            : Colors.black.withValues(alpha: 0.06)),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  icon,
                  size: 20,
                  color: isSelected
                      ? Colors.white
                      : colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: isSelected
                            ? FontWeight.w800
                            : FontWeight.w600,
                        color: isSelected ? accentColor : colorScheme.onSurface,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: TextStyle(
                        fontSize: 12,
                        color: colorScheme.onSurfaceVariant.withValues(
                          alpha: 0.8,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              if (isSelected)
                Icon(Icons.check_circle_rounded, color: accentColor, size: 22)
              else
                const SizedBox(width: 22),
            ],
          ),
        ),
      ),
    );
  }

  /// 显示添加到歌单对话框
  /// 显示添加到歌单对话框
  static void showAddToPlaylist(BuildContext context, Track track) {
    final playlistService = PlaylistService();
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final colorScheme = theme.colorScheme;

    // 确保已加载歌单列表
    if (playlistService.playlists.isEmpty) {
      playlistService.loadPlaylists();
    }

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
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
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(28),
              ),
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
              child: AnimatedBuilder(
                animation: playlistService,
                builder: (context, child) {
                  final playlists = playlistService.playlists;

                  if (playlists.isEmpty) {
                    return Center(
                      child: Padding(
                        padding: const EdgeInsets.all(32.0),
                        child: CircularProgressIndicator(
                          color: colorScheme.primary,
                        ),
                      ),
                    );
                  }

                  return Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // 拖动手柄
                      Container(
                        margin: const EdgeInsets.only(top: 12, bottom: 6),
                        width: 38,
                        height: 4.5,
                        decoration: BoxDecoration(
                          color: isDark ? Colors.white24 : Colors.black12,
                          borderRadius: BorderRadius.circular(2.5),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 20,
                          vertical: 8,
                        ),
                        child: Row(
                          children: [
                            Text(
                              '添加到歌单',
                              style: theme.textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.w800,
                                letterSpacing: -0.3,
                                color: colorScheme.onSurface,
                              ),
                            ),
                            const Spacer(),
                            IconButton(
                              icon: Icon(
                                Icons.close_rounded,
                                color: colorScheme.onSurfaceVariant,
                                size: 20,
                              ),
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
                      Flexible(
                        child: ListView.builder(
                          shrinkWrap: true,
                          padding: const EdgeInsets.symmetric(vertical: 6),
                          itemCount: playlists.length,
                          itemBuilder: (context, index) {
                            final playlist = playlists[index];
                            return ListTile(
                              leading: Container(
                                width: 40,
                                height: 40,
                                decoration: BoxDecoration(
                                  color: playlist.isDefault
                                      ? Colors.red.withValues(alpha: 0.12)
                                      : colorScheme.primary.withValues(
                                          alpha: 0.12,
                                        ),
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: Icon(
                                  playlist.isDefault
                                      ? Icons.favorite_rounded
                                      : Icons.queue_music_rounded,
                                  color: playlist.isDefault
                                      ? Colors.red
                                      : colorScheme.primary,
                                  size: 20,
                                ),
                              ),
                              title: Text(
                                playlist.name,
                                style: TextStyle(
                                  color: colorScheme.onSurface,
                                  fontWeight: FontWeight.w600,
                                  fontSize: 15,
                                ),
                              ),
                              subtitle: Text(
                                '${playlist.trackCount} 首歌曲',
                                style: TextStyle(
                                  color: colorScheme.onSurfaceVariant
                                      .withValues(alpha: 0.75),
                                  fontSize: 12,
                                ),
                              ),
                              onTap: () async {
                                Navigator.pop(context);
                                final success = await playlistService
                                    .addTrackToPlaylist(playlist.id, track);
                                if (context.mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: Text(
                                        success
                                            ? '已添加到「${playlist.name}」'
                                            : '添加失败',
                                      ),
                                      duration: const Duration(seconds: 1),
                                    ),
                                  );
                                }
                              },
                            );
                          },
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
  }

  static String _getQueueSourceTitle(QueueSource source) {
    switch (source) {
      case QueueSource.favorites:
        return '播放队列 · 收藏';
      case QueueSource.playlist:
        return '播放队列 · 歌单';
      case QueueSource.album:
        return '播放队列 · 专辑';
      case QueueSource.history:
        return '播放历史';
      case QueueSource.search:
        return '播放队列 · 搜索';
      case QueueSource.radio:
        return '播放队列 · 电台';
      case QueueSource.toplist:
        return '播放队列 · 榜单';
      case QueueSource.none:
        return '播放队列';
    }
  }

  /// 显示播放列表底部抽屉
  static void showPlaylistBottomSheet(BuildContext context) {
    final queueService = PlaylistQueueService();
    final historyService = PlayHistoryService();
    final currentTrack = PlayerService().currentTrack;
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final colorScheme = theme.colorScheme;

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      barrierColor: Colors.black.withValues(alpha: 0.5),
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.72,
        minChildSize: 0.5,
        maxChildSize: 0.95,
        expand: false,
        builder: (context, scrollController) {
          return ClipRRect(
            borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 25, sigmaY: 25),
              child: Container(
                decoration: BoxDecoration(
                  color: (isDark ? const Color(0xFF141418) : Colors.white)
                      .withValues(alpha: 0.92),
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(28),
                  ),
                  border: Border(
                    top: BorderSide(
                      color: Colors.white.withValues(
                        alpha: isDark ? 0.12 : 0.4,
                      ),
                      width: 0.8,
                    ),
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(
                        alpha: isDark ? 0.45 : 0.12,
                      ),
                      blurRadius: 30,
                      offset: const Offset(0, -10),
                    ),
                  ],
                ),
                child: ValueListenableBuilder<Color?>(
                  valueListenable: PlayerService().themeColorNotifier,
                  builder: (context, dynamicColor, _) {
                    final accentColor = dynamicColor ?? colorScheme.primary;

                    return AnimatedBuilder(
                      animation: Listenable.merge([
                        queueService,
                        historyService,
                      ]),
                      builder: (context, _) {
                        final bool hasQueue = queueService.hasQueue;
                        final List<Track> displayList = hasQueue
                            ? List<Track>.from(queueService.queue)
                            : historyService.history
                                  .map((h) => h.toTrack())
                                  .toList();
                        final String listTitle = hasQueue
                            ? _getQueueSourceTitle(queueService.source)
                            : '播放历史';

                        return Column(
                          children: [
                            // 拖动指示器
                            Container(
                              width: 38,
                              height: 4.5,
                              margin: const EdgeInsets.only(top: 12, bottom: 8),
                              decoration: BoxDecoration(
                                color: isDark ? Colors.white24 : Colors.black12,
                                borderRadius: BorderRadius.circular(2.5),
                              ),
                            ),
                            // 标题栏（集成一键切换播放模式胶囊）
                            Padding(
                              padding: const EdgeInsets.fromLTRB(18, 4, 18, 12),
                              child: Row(
                                children: [
                                  AnimatedBuilder(
                                    animation: PlaybackModeService(),
                                    builder: (context, _) {
                                      final modeService = PlaybackModeService();
                                      final modeName = modeService
                                          .getModeName();
                                      return Material(
                                        color: Colors.transparent,
                                        child: InkWell(
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
                                            MobilePlayerDialogs.showPlaybackModeSelector(
                                              context,
                                            );
                                          },
                                          borderRadius: BorderRadius.circular(
                                            12,
                                          ),
                                          child: Container(
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 10,
                                              vertical: 6,
                                            ),
                                            decoration: BoxDecoration(
                                              color: accentColor.withValues(
                                                alpha: isDark ? 0.16 : 0.08,
                                              ),
                                              borderRadius:
                                                  BorderRadius.circular(12),
                                              border: Border.all(
                                                color: accentColor.withValues(
                                                  alpha: isDark ? 0.25 : 0.15,
                                                ),
                                                width: 0.8,
                                              ),
                                            ),
                                            child: Row(
                                              mainAxisSize: MainAxisSize.min,
                                              children: [
                                                Icon(
                                                  modeService.getModeIcon(),
                                                  color: accentColor,
                                                  size: 18,
                                                ),
                                                const SizedBox(width: 6),
                                                Text(
                                                  hasQueue
                                                      ? modeName
                                                      : '$listTitle · $modeName',
                                                  style: TextStyle(
                                                    color:
                                                        colorScheme.onSurface,
                                                    fontSize: 15,
                                                    fontWeight: FontWeight.w700,
                                                    letterSpacing: -0.2,
                                                  ),
                                                ),
                                                const SizedBox(width: 6),
                                                Container(
                                                  padding:
                                                      const EdgeInsets.symmetric(
                                                        horizontal: 6,
                                                        vertical: 1.5,
                                                      ),
                                                  decoration: BoxDecoration(
                                                    color: accentColor
                                                        .withValues(
                                                          alpha: isDark
                                                              ? 0.2
                                                              : 0.12,
                                                        ),
                                                    borderRadius:
                                                        BorderRadius.circular(
                                                          8,
                                                        ),
                                                  ),
                                                  child: Text(
                                                    '${displayList.length} 首',
                                                    style: TextStyle(
                                                      color: accentColor,
                                                      fontSize: 11,
                                                      fontWeight:
                                                          FontWeight.bold,
                                                    ),
                                                  ),
                                                ),
                                                const SizedBox(width: 4),
                                                Icon(
                                                  Icons.swap_horiz_rounded,
                                                  size: 14,
                                                  color: accentColor.withValues(
                                                    alpha: 0.6,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                        ),
                                      );
                                    },
                                  ),
                                  const Spacer(),
                                  TextButton.icon(
                                    onPressed: displayList.isEmpty
                                        ? null
                                        : () {
                                            if (hasQueue) {
                                              queueService.clear();
                                            } else {
                                              historyService.clearHistory();
                                            }
                                          },
                                    icon: Icon(
                                      Icons.delete_outline_rounded,
                                      size: 16,
                                      color: displayList.isEmpty
                                          ? colorScheme.onSurfaceVariant
                                                .withValues(alpha: 0.3)
                                          : colorScheme.onSurfaceVariant,
                                    ),
                                    label: Text(
                                      '清空',
                                      style: TextStyle(
                                        color: displayList.isEmpty
                                            ? colorScheme.onSurfaceVariant
                                                  .withValues(alpha: 0.3)
                                            : colorScheme.onSurfaceVariant,
                                        fontSize: 13,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                    style: TextButton.styleFrom(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 10,
                                        vertical: 6,
                                      ),
                                      minimumSize: Size.zero,
                                      tapTargetSize:
                                          MaterialTapTargetSize.shrinkWrap,
                                    ),
                                  ),
                                ],
                              ),
                            ),

                            Divider(
                              color: isDark
                                  ? Colors.white10
                                  : Colors.black.withValues(alpha: 0.06),
                              height: 1,
                              thickness: 0.6,
                            ),

                            // 播放列表
                            Expanded(
                              child: displayList.isEmpty
                                  ? Center(
                                      child: Column(
                                        mainAxisAlignment:
                                            MainAxisAlignment.center,
                                        children: [
                                          Icon(
                                            Icons.music_off_rounded,
                                            size: 56,
                                            color: colorScheme.onSurfaceVariant
                                                .withValues(alpha: 0.3),
                                          ),
                                          const SizedBox(height: 12),
                                          Text(
                                            '播放列表为空',
                                            style: TextStyle(
                                              color: colorScheme
                                                  .onSurfaceVariant
                                                  .withValues(alpha: 0.6),
                                              fontSize: 15,
                                              fontWeight: FontWeight.w500,
                                            ),
                                          ),
                                        ],
                                      ),
                                    )
                                  : (hasQueue
                                        ? ReorderableListView.builder(
                                            buildDefaultDragHandles: false,
                                            scrollController: scrollController,
                                            padding: const EdgeInsets.symmetric(
                                              vertical: 4,
                                            ),
                                            itemCount: displayList.length,
                                            onReorder: (oldIndex, newIndex) {
                                              if (newIndex > oldIndex) {
                                                newIndex -= 1;
                                              }
                                              queueService.move(
                                                oldIndex,
                                                newIndex,
                                              );
                                            },
                                            itemBuilder: (context, index) {
                                              final track = displayList[index];
                                              final isCurrentTrack =
                                                  currentTrack != null &&
                                                  track.id.toString() ==
                                                      currentTrack.id
                                                          .toString() &&
                                                  track.source ==
                                                      currentTrack.source;

                                              return _buildPlaylistItem(
                                                context,
                                                track,
                                                index,
                                                isCurrentTrack,
                                                hasQueue: true,
                                                queueService: queueService,
                                                accentColor: accentColor,
                                                key: ValueKey(
                                                  '${track.source.name}_${track.id}',
                                                ),
                                              );
                                            },
                                          )
                                        : ListView.builder(
                                            controller: scrollController,
                                            padding: const EdgeInsets.symmetric(
                                              vertical: 4,
                                            ),
                                            itemCount: displayList.length,
                                            itemBuilder: (context, index) {
                                              final track = displayList[index];
                                              final isCurrentTrack =
                                                  currentTrack != null &&
                                                  track.id.toString() ==
                                                      currentTrack.id
                                                          .toString() &&
                                                  track.source ==
                                                      currentTrack.source;

                                              return _buildPlaylistItem(
                                                context,
                                                track,
                                                index,
                                                isCurrentTrack,
                                                hasQueue: false,
                                                accentColor: accentColor,
                                              );
                                            },
                                          )),
                            ),
                          ],
                        );
                      },
                    );
                  },
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  /// 构建播放列表项
  static Widget _buildPlaylistItem(
    BuildContext context,
    Track track,
    int index,
    bool isCurrentTrack, {
    required bool hasQueue,
    PlaylistQueueService? queueService,
    Color? accentColor,
    Key? key,
  }) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;
    final activeColor = accentColor ?? colorScheme.primary;

    return Material(
      key: key,
      color: isCurrentTrack
          ? activeColor.withValues(alpha: isDark ? 0.16 : 0.08)
          : Colors.transparent,
      child: InkWell(
        onTap: () {
          PlayerService().playTrack(track);
          Navigator.pop(context);
        },
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            children: [
              // 序号或正在播放图标
              SizedBox(
                width: 30,
                child: isCurrentTrack
                    ? Icon(
                        Icons.volume_up_rounded,
                        color: activeColor,
                        size: 20,
                      )
                    : Text(
                        '${index + 1}',
                        style: TextStyle(
                          color: colorScheme.onSurfaceVariant.withValues(
                            alpha: 0.55,
                          ),
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                        ),
                        textAlign: TextAlign.center,
                      ),
              ),

              const SizedBox(width: 8),

              // 封面
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: _buildCoverImage(track.picUrl),
              ),

              const SizedBox(width: 12),

              // 歌曲信息
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      track.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: isCurrentTrack
                            ? activeColor
                            : colorScheme.onSurface,
                        fontSize: 15,
                        fontWeight: isCurrentTrack
                            ? FontWeight.w700
                            : FontWeight.w500,
                        letterSpacing: -0.2,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      track.artists,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: colorScheme.onSurfaceVariant.withValues(
                          alpha: 0.7,
                        ),
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(width: 6),

              // 操作按钮
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Builder(
                    builder: (buttonContext) {
                      return IconButton(
                        icon: Icon(
                          Icons.more_vert_rounded,
                          color: colorScheme.onSurfaceVariant.withValues(
                            alpha: 0.7,
                          ),
                          size: 20,
                        ),
                        onPressed: () {
                          TrackActionMenu.show(
                            context: buttonContext,
                            track: track,
                            onDelete: hasQueue
                                ? () => queueService?.removeAt(index)
                                : null,
                          );
                        },
                        tooltip: '更多',
                      );
                    },
                  ),
                  if (hasQueue) ...[
                    IconButton(
                      icon: Icon(
                        Icons.close_rounded,
                        color: colorScheme.onSurfaceVariant.withValues(
                          alpha: 0.7,
                        ),
                        size: 20,
                      ),
                      onPressed: () => queueService?.removeAt(index),
                      tooltip: '移除',
                    ),
                    ReorderableDragStartListener(
                      index: index,
                      child: SizedBox(
                        width: 36,
                        height: 36,
                        child: Icon(
                          Icons.drag_handle_rounded,
                          color: colorScheme.onSurfaceVariant.withValues(
                            alpha: 0.5,
                          ),
                          size: 20,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 构建封面图片（支持网络 URL 和本地文件路径）
  static Widget _buildCoverImage(String imageUrl) {
    // 判断是网络 URL 还是本地文件路径
    final isNetwork =
        imageUrl.startsWith('http://') || imageUrl.startsWith('https://');

    if (isNetwork) {
      return CachedNetworkImage(
        imageUrl: imageUrl,
        httpHeaders: getImageHeaders(imageUrl),
        width: 48,
        height: 48,
        fit: BoxFit.cover,
        memCacheWidth: 128,
        memCacheHeight: 128,
        placeholder: (context, url) =>
            Container(width: 48, height: 48, color: Colors.white12),
        errorWidget: (context, url, error) => Container(
          width: 48,
          height: 48,
          color: Colors.white12,
          child: const Icon(Icons.music_note, color: Colors.white38, size: 24),
        ),
      );
    } else {
      // 本地文件
      return SizedBox(
        width: 48,
        height: 48,
        child: Image.file(
          File(imageUrl),
          fit: BoxFit.cover,
          errorBuilder: (context, error, stackTrace) => Container(
            width: 48,
            height: 48,
            color: Colors.white12,
            child: const Icon(
              Icons.music_note,
              color: Colors.white38,
              size: 24,
            ),
          ),
        ),
      );
    }
  }
}

/// 睡眠定时器对话框（移动端版本）
class MobileSleepTimerDialog extends StatefulWidget {
  const MobileSleepTimerDialog({super.key});

  @override
  State<MobileSleepTimerDialog> createState() => _MobileSleepTimerDialogState();
}

class _MobileSleepTimerDialogState extends State<MobileSleepTimerDialog> {
  int _selectedTabIndex = 0; // 0: 时长, 1: 时间
  int _selectedDuration = 30; // 默认30分钟

  // 预设时长选项（分钟）
  final List<int> _durationOptions = [15, 30, 45, 60, 90, 120];

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final timer = SleepTimerService();

    return AlertDialog(
      title: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          const Text('睡眠定时器'),
          if (timer.isActive)
            TextButton.icon(
              onPressed: () {
                timer.cancel();
                Navigator.pop(context);
                ScaffoldMessenger.of(
                  context,
                ).showSnackBar(const SnackBar(content: Text('定时器已取消')));
              },
              icon: const Icon(Icons.cancel),
              label: const Text('取消定时'),
              style: TextButton.styleFrom(foregroundColor: Colors.red),
            ),
        ],
      ),
      content: SizedBox(
        width: double.maxFinite,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // 当前定时器状态
            if (timer.isActive)
              Container(
                padding: const EdgeInsets.all(16),
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                  color: colorScheme.primaryContainer,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    Icon(Icons.schedule, color: colorScheme.onPrimaryContainer),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '定时器运行中',
                            style: TextStyle(
                              color: colorScheme.onPrimaryContainer,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 4),
                          AnimatedBuilder(
                            animation: timer,
                            builder: (context, child) {
                              return Text(
                                '剩余时间: ${timer.remainingTimeString}',
                                style: TextStyle(
                                  color: colorScheme.onPrimaryContainer,
                                ),
                              );
                            },
                          ),
                        ],
                      ),
                    ),
                    if (timer.isActive)
                      IconButton(
                        icon: const Icon(Icons.add_circle_outline),
                        onPressed: () {
                          timer.extend(15);
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('已延长15分钟')),
                          );
                        },
                        tooltip: '延长15分钟',
                        color: colorScheme.onPrimaryContainer,
                      ),
                  ],
                ),
              ),

            // 标签选择器
            SegmentedButton<int>(
              segments: const [
                ButtonSegment(
                  value: 0,
                  label: Text('播放时长'),
                  icon: Icon(Icons.timer_outlined),
                ),
                ButtonSegment(
                  value: 1,
                  label: Text('指定时间'),
                  icon: Icon(Icons.schedule),
                ),
              ],
              selected: {_selectedTabIndex},
              onSelectionChanged: (Set<int> selected) {
                setState(() {
                  _selectedTabIndex = selected.first;
                });
              },
            ),

            const SizedBox(height: 24),

            // 内容区域
            if (_selectedTabIndex == 0) _buildDurationTab(colorScheme),
            if (_selectedTabIndex == 1) _buildTimeTab(context, colorScheme),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('取消'),
        ),
      ],
    );
  }

  /// 时长选择标签页
  Widget _buildDurationTab(ColorScheme colorScheme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '选择播放时长',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            color: colorScheme.onSurface,
          ),
        ),
        const SizedBox(height: 16),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: _durationOptions.map((duration) {
            final isSelected = duration == _selectedDuration;
            return FilterChip(
              label: Text('${duration}分钟'),
              selected: isSelected,
              onSelected: (selected) {
                if (selected) {
                  setState(() {
                    _selectedDuration = duration;
                  });
                  SleepTimerService().setTimerByDuration(duration);
                  Navigator.pop(context);
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('定时器已设置: ${duration}分钟后停止播放')),
                  );
                }
              },
              showCheckmark: false,
            );
          }).toList(),
        ),
      ],
    );
  }

  /// 时间选择标签页
  Widget _buildTimeTab(BuildContext context, ColorScheme colorScheme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '选择停止时间',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            color: colorScheme.onSurface,
          ),
        ),
        const SizedBox(height: 16),
        SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            onPressed: () async {
              final TimeOfDay? selectedTime = await showTimePicker(
                context: context,
                initialTime: TimeOfDay.now(),
                builder: (context, child) {
                  return MediaQuery(
                    data: MediaQuery.of(
                      context,
                    ).copyWith(alwaysUse24HourFormat: true),
                    child: child!,
                  );
                },
              );

              if (!context.mounted) return;
              if (selectedTime != null) {
                SleepTimerService().setTimerByTime(selectedTime);
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                      '定时器已设置: ${selectedTime.hour.toString().padLeft(2, '0')}:${selectedTime.minute.toString().padLeft(2, '0')} 停止播放',
                    ),
                  ),
                );
              }
            },
            icon: const Icon(Icons.access_time),
            label: const Text('选择时间'),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          '音乐将在指定时间自动停止播放',
          style: TextStyle(
            fontSize: 12,
            color: colorScheme.onSurface.withValues(alpha: 0.6),
          ),
        ),
      ],
    );
  }
}
