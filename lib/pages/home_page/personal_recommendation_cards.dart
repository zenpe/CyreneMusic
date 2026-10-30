import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:fluent_ui/fluent_ui.dart' as fluent;
import '../../models/track.dart';
import '../../utils/image_utils.dart';
import '../../utils/netease_track.dart';
import '../../utils/theme_manager.dart';

Widget _action(String label, IconData icon, VoidCallback? onPressed) {
  final child = Row(
    mainAxisSize: MainAxisSize.min,
    children: [Icon(icon, size: 18), const SizedBox(width: 6), Text(label)],
  );
  if (ThemeManager().isFluentFramework) {
    return fluent.Button(onPressed: onPressed, child: child);
  }
  if (ThemeManager().isCupertinoFramework) {
    return CupertinoButton(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      onPressed: onPressed,
      child: child,
    );
  }
  return TextButton(onPressed: onPressed, child: child);
}

Widget _surface(BuildContext context, Widget child) {
  if (ThemeManager().isFluentFramework) {
    return fluent.Card(padding: const EdgeInsets.all(16), child: child);
  }
  final cs = Theme.of(context).colorScheme;
  return Container(
    padding: const EdgeInsets.all(20),
    decoration: BoxDecoration(
      color: cs.surfaceContainerLow,
      borderRadius: BorderRadius.circular(
        ThemeManager().isCupertinoFramework ? 12 : 24,
      ),
      border: Border.all(color: cs.outlineVariant.withValues(alpha: .4)),
    ),
    child: child,
  );
}

class RecommendationCover extends StatelessWidget {
  const RecommendationCover({super.key, required this.url, this.size = 48});
  final String url;
  final double size;
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final placeholder = ColoredBox(
      color: cs.surfaceContainerHighest,
      child: Icon(Icons.music_note_rounded, color: cs.onSurfaceVariant),
    );
    return ClipRRect(
      borderRadius: BorderRadius.circular(size > 60 ? 16 : 8),
      child: SizedBox.square(
        dimension: size,
        child: url.isEmpty
            ? placeholder
            : CachedNetworkImage(
                imageUrl: url,
                httpHeaders: getImageHeaders(url),
                fit: BoxFit.cover,
                memCacheWidth: (size * MediaQuery.devicePixelRatioOf(context))
                    .round(),
                placeholder: (_, _) => placeholder,
                errorWidget: (_, _, _) => placeholder,
              ),
      ),
    );
  }
}

/// A small playable sample; opening all keeps the complete daily queue.
class DailySongsPreview extends StatelessWidget {
  const DailySongsPreview({
    super.key,
    required this.songs,
    required this.onOpenAll,
    required this.onPlay,
  });
  final List<Map<String, dynamic>> songs;
  final VoidCallback onOpenAll;
  final ValueChanged<int> onPlay;
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return _surface(
      context,
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 16,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(
                '今日精选 · ${songs.length} 首',
                style: theme.textTheme.titleMedium,
              ),
              _action(
                '播放全部',
                Icons.play_arrow_rounded,
                songs.isEmpty ? null : () => onPlay(0),
              ),
              _action('查看全部', Icons.arrow_forward_rounded, onOpenAll),
            ],
          ),
          const SizedBox(height: 12),
          LayoutBuilder(
            builder: (context, constraints) {
              final wide =
                  constraints.maxWidth >= 720 &&
                  MediaQuery.textScalerOf(context).scale(1) <= 1.5;
              final count = songs.length.clamp(0, wide ? 6 : 3);
              final width = wide
                  ? (constraints.maxWidth - 16) / 2
                  : constraints.maxWidth;
              return Wrap(
                spacing: 16,
                runSpacing: 4,
                children: [
                  for (var i = 0; i < count; i++)
                    SizedBox(width: width, child: _song(context, i)),
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _song(BuildContext context, int index) {
    final track = neteaseSongToTrack(songs[index]);
    final theme = Theme.of(context);
    final child = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
      child: Row(
        children: [
          RecommendationCover(url: track.picUrl),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  track.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodyLarge?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  track.artists,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Icon(
            Icons.play_circle_outline_rounded,
            color: theme.colorScheme.primary,
          ),
        ],
      ),
    );
    return Semantics(
      button: true,
      label: '播放 ${track.name}',
      child: ThemeManager().isFluentFramework
          ? fluent.HoverButton(
              onPressed: () => onPlay(index),
              builder: (_, states) => DecoratedBox(
                decoration: BoxDecoration(
                  color: states.isHovered
                      ? theme.colorScheme.primary.withValues(alpha: .08)
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: child,
              ),
            )
          : Material(
              color: Colors.transparent,
              child: InkWell(
                borderRadius: BorderRadius.circular(12),
                onTap: () => onPlay(index),
                child: child,
              ),
            ),
    );
  }
}

class PersonalFmPreview extends StatelessWidget {
  const PersonalFmPreview({
    super.key,
    required this.track,
    required this.playing,
    required this.loading,
    required this.onPlayPause,
    required this.onRefresh,
    this.error,
  });
  final Track? track;
  final bool playing;
  final bool loading;
  final VoidCallback? onPlayPause;
  final VoidCallback? onRefresh;
  final String? error;
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return _surface(
      context,
      LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxWidth < 480;
          final cover = RecommendationCover(
            url: track?.picUrl ?? '',
            size: compact ? 80 : 120,
          );
          final details = Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                track?.name ?? (loading ? '正在寻找合你口味的歌曲…' : '听点喜欢的，也遇见新鲜的'),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                track?.artists ?? '来自网易云的专属推荐',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              if (!compact) ...[const SizedBox(height: 16), _controls()],
            ],
          );
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  cover,
                  const SizedBox(width: 20),
                  Expanded(child: details),
                ],
              ),
              if (compact) ...[const SizedBox(height: 16), _controls()],
              if (error != null) ...[
                const SizedBox(height: 12),
                Text(
                  error!,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.error,
                  ),
                ),
              ],
            ],
          );
        },
      ),
    );
  }

  Widget _controls() => Wrap(
    spacing: 12,
    runSpacing: 8,
    children: [
      _action(
        loading
            ? '正在加载…'
            : playing
            ? '暂停'
            : '播放',
        playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
        loading ? null : onPlayPause,
      ),
      _action('换一批', Icons.refresh_rounded, loading ? null : onRefresh),
    ],
  );
}
