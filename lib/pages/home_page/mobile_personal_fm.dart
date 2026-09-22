import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:fluent_ui/fluent_ui.dart' as fluent;
import '../../models/track.dart';
import '../../services/player_service.dart';
import '../../services/playlist_queue_service.dart';
import '../../utils/theme_manager.dart';
import 'hero_section.dart'; // 复用 convertToTrack 函数

/// 私人FM（移动端）
class MobilePersonalFm extends StatelessWidget {
  final List<Map<String, dynamic>> list;
  const MobilePersonalFm({super.key, required this.list});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final themeManager = ThemeManager();
    final isCupertino = (Platform.isIOS || Platform.isAndroid) && themeManager.isCupertinoFramework;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    if (list.isEmpty) return Text('暂无数据', style: Theme.of(context).textTheme.bodySmall);

    return AnimatedBuilder(
      animation: PlayerService(),
      builder: (context, _) {
        Map<String, dynamic> display = list.first;
        final current = PlayerService().currentTrack;
        if (current != null && current.source == MusicSource.netease) {
          for (final m in list) {
            final id = (m['id'] ?? (m['song'] != null ? (m['song'] as Map<String, dynamic>)['id'] : null)) as dynamic;
            if (id != null && id.toString() == current.id.toString()) {
              display = m;
              break;
            }
          }
        }

        final album = (display['album'] ?? display['al'] ?? {}) as Map<String, dynamic>;
        final artists = (display['artists'] ?? display['ar'] ?? []) as List<dynamic>;
        final artistsText = artists.map((e) => (e as Map<String, dynamic>)['name']?.toString() ?? '').where((e) => e.isNotEmpty).join('/');
        final pic = (album['picUrl'] ?? '').toString();

        final fmTracks = _convertListToTracks(list);
        final isFmCurrent = _currentTrackInList(fmTracks);
        final isFmQueue = _isSameQueueAs(fmTracks);
        final isFmPlaying = PlayerService().isPlaying && (isFmCurrent || isFmQueue);

        // Common click handler to jump to player
        final void Function() onOpenPlayer = () {
            // PlayerService handles navigation to full screen usually via a global state or callback
            // For now we just implement the play logic as required by the card
        };

        if (themeManager.isFluentFramework) {
          return fluent.Card(
            padding: EdgeInsets.zero,
            child: _buildOldCardContent(context, pic, display, artistsText, isFmPlaying, fmTracks, isFmQueue, isFmCurrent, cs, isCupertino),
          );
        }

        if (isCupertino) {
          return Container(
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF1C1C1E) : CupertinoColors.white,
              borderRadius: BorderRadius.circular(12),
              boxShadow: [
                BoxShadow(
                  color: CupertinoColors.black.withValues(alpha: isDark ? 0.2 : 0.08),
                  blurRadius: 10,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: _buildOldCardContent(context, pic, display, artistsText, isFmPlaying, fmTracks, isFmQueue, isFmCurrent, cs, isCupertino),
          );
        }

        // Android 16 Expressive Style
        return Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(32),
            gradient: LinearGradient(
              begin: Alignment.centerLeft,
              end: Alignment.centerRight,
              colors: [
                cs.surfaceContainer,
                cs.surfaceContainerHigh.withValues(alpha: 0.9),
              ],
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: isDark ? 0.25 : 0.04),
                blurRadius: 16,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: onOpenPlayer,
              borderRadius: BorderRadius.circular(32),
              child: _buildMaterialFmContent(context, pic, display, artistsText, isFmPlaying, fmTracks, isFmQueue, isFmCurrent, cs),
            ),
          ),
        );
      },
    );
  }

  /// 这里的样式代码主要是为了兼容旧版和其他主题
  Widget _buildOldCardContent(
    BuildContext context,
    String pic,
    Map<String, dynamic> display,
    String artistsText,
    bool isFmPlaying,
    List<Track> fmTracks,
    bool isFmQueue,
    bool isFmCurrent,
    ColorScheme cs,
    bool isCupertino,
  ) {
    return Padding(
      padding: const EdgeInsets.all(12.0),
      child: Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: Image.network(pic, width: 120, height: 120, fit: BoxFit.cover),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(display['name']?.toString() ?? '', maxLines: 1, overflow: TextOverflow.ellipsis, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600)),
                const SizedBox(height: 6),
                Text(artistsText, maxLines: 1, overflow: TextOverflow.ellipsis, style: Theme.of(context).textTheme.bodySmall),
              ],
            ),
          ),
          const SizedBox(width: 12),
          _buildControls(context, isFmPlaying, fmTracks, isFmQueue, isFmCurrent, cs, isCupertino),
        ],
      ),
    );
  }

  /// Android 16 表现力风格内容 - Redesigned for better control placement
  Widget _buildMaterialFmContent(
    BuildContext context,
    String pic,
    Map<String, dynamic> display,
    String artistsText,
    bool isFmPlaying,
    List<Track> fmTracks,
    bool isFmQueue,
    bool isFmCurrent,
    ColorScheme cs,
  ) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // Album Art - Fixed Size
          Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(24),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.15),
                  blurRadius: 12,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(24),
              child: Image.network(pic, width: 120, height: 120, fit: BoxFit.cover),
            ),
          ),
          const SizedBox(width: 20),
          // Info and Controls - Pushed to right
          Expanded(
            child: SizedBox(
              height: 120, // Increased to fix overflow (needs > 100 for bold text + 52dp btn)
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Text Content at the top
                  Text(
                    display['name']?.toString() ?? '',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w900,
                      color: cs.onSurface,
                      letterSpacing: -0.5,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    artistsText,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                      color: cs.onSurface.withValues(alpha: 0.6),
                    ),
                  ),
                  const Spacer(),
                  // Controls Cluster - Grouped in the bottom right
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      // Skip Button - Subtle Surface
                      _buildMaterialControlBtn(
                        onPressed: () => _handleSkipAction(fmTracks),
                        icon: Icon(Icons.skip_next_rounded, color: cs.onSurface.withValues(alpha: 0.8), size: 26),
                        bgColor: cs.surfaceContainerHighest.withValues(alpha: 0.5),
                        size: 40,
                      ),
                      const SizedBox(width: 12),
                      // Play Button - Primary Prominent
                      _buildMaterialControlBtn(
                        onPressed: () => _handlePlayAction(context, fmTracks, isFmPlaying, isFmQueue, isFmCurrent),
                        icon: Icon(isFmPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded, color: cs.onPrimary, size: 30),
                        bgColor: cs.primary,
                        size: 52,
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMaterialControlBtn({
    required VoidCallback onPressed,
    required Widget icon,
    required Color bgColor,
    double size = 48,
  }) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(size / 3), // Dynamic rounded square
        boxShadow: [
          if (bgColor != Colors.transparent && bgColor != Colors.transparent.withValues(alpha: 0.5))
            BoxShadow(
              color: bgColor.withValues(alpha: 0.3),
              blurRadius: 8,
              offset: const Offset(0, 4),
            ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onPressed,
          borderRadius: BorderRadius.circular(size / 3),
          child: Center(child: icon),
        ),
      ),
    );
  }

  Widget _buildControls(BuildContext context, bool isFmPlaying, List<Track> fmTracks, bool isFmQueue, bool isFmCurrent, ColorScheme cs, bool isCupertino) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        isCupertino
            ? CupertinoButton(
                padding: const EdgeInsets.all(8),
                onPressed: () => _handlePlayAction(context, fmTracks, isFmPlaying, isFmQueue, isFmCurrent),
                child: Icon(
                  isFmPlaying ? CupertinoIcons.pause_fill : CupertinoIcons.play_fill,
                  color: ThemeManager.iosBlue,
                  size: 28,
                ),
              )
            : IconButton(
                onPressed: () => _handlePlayAction(context, fmTracks, isFmPlaying, isFmQueue, isFmCurrent),
                style: IconButton.styleFrom(
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
                icon: Icon(isFmPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded, color: cs.onSurface),
              ),
        const SizedBox(width: 8),
        isCupertino
            ? CupertinoButton(
                padding: const EdgeInsets.all(8),
                onPressed: () => _handleSkipAction(fmTracks),
                child: Icon(
                  CupertinoIcons.forward_fill,
                  color: ThemeManager.iosBlue,
                  size: 28,
                ),
              )
            : IconButton(
                onPressed: () => _handleSkipAction(fmTracks),
                style: IconButton.styleFrom(
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
                icon: Icon(Icons.skip_next_rounded, color: cs.onSurface),
              ),
      ],
    );
  }

  Future<void> _handlePlayAction(BuildContext context, List<Track> fmTracks, bool isFmPlaying, bool isFmQueue, bool isFmCurrent) async {
    final tracks = fmTracks;
    if (tracks.isEmpty) return;
    final ps = PlayerService();
    if (isFmPlaying) {
      await ps.pause();
    } else if (ps.isPaused && (isFmQueue || isFmCurrent)) {
      await ps.resume();
    } else {
      PlaylistQueueService().setQueue(tracks, 0, QueueSource.playlist);
      await ps.playTrack(tracks.first);
      if (context.mounted) {
         try {
           ScaffoldMessenger.of(context).showSnackBar(
             const SnackBar(content: Text('开始播放私人FM'), duration: Duration(seconds: 1)),
           );
         } catch (_) {}
      }
    }
  }

  Future<void> _handleSkipAction(List<Track> fmTracks) async {
    final tracks = fmTracks;
    if (tracks.isEmpty) return;
    if (_isSameQueueAs(tracks)) {
      await PlayerService().playNext();
    } else {
      final startIndex = tracks.length > 1 ? 1 : 0;
      PlaylistQueueService().setQueue(tracks, startIndex, QueueSource.playlist);
      await PlayerService().playTrack(tracks[startIndex]);
    }
  }

  List<Track> _convertListToTracks(List<Map<String, dynamic>> src) {
    return src.map((m) => convertToTrack(m)).toList();
  }

  bool _isSameQueueAs(List<Track> tracks) {
    final q = PlaylistQueueService().queue;
    if (q.length != tracks.length) return false;
    for (var i = 0; i < q.length; i++) {
      if (q[i].id.toString() != tracks[i].id.toString() || q[i].source != tracks[i].source) {
        return false;
      }
    }
    return true;
  }

  bool _currentTrackInList(List<Track> tracks) {
    final ct = PlayerService().currentTrack;
    if (ct == null) return false;
    return tracks.any((t) => t.id.toString() == ct.id.toString() && t.source == ct.source);
  }
}
