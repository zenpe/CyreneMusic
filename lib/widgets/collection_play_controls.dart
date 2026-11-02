import 'package:flutter/material.dart';
import '../services/playback_mode_service.dart';
import '../services/playlist_queue_service.dart';

/// Keep play-all labels reactive without rebuilding an entire detail page.
class PlayAllLabel extends StatelessWidget {
  const PlayAllLabel(
    this.text, {
    super.key,
    this.style,
    this.maxLines,
    this.overflow,
    this.textAlign,
  });
  final String text;
  final TextStyle? style;
  final int? maxLines;
  final TextOverflow? overflow;
  final TextAlign? textAlign;
  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: PlaybackModeService(),
    builder: (context, _) => Text(
      PlaybackModeService().currentMode == PlaybackMode.shuffle
          ? text.replaceAll('播放全部', '随机播放').replaceAll('全部播放', '随机播放')
          : text,
      style: style,
      maxLines: maxLines,
      overflow: overflow,
      textAlign: textAlign,
    ),
  );
}

class PlayAllIcon extends StatelessWidget {
  const PlayAllIcon(this.icon, {super.key, this.size, this.color});
  final IconData icon;
  final double? size;
  final Color? color;
  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: PlaybackModeService(),
    builder: (context, _) => Icon(
      PlaybackModeService().currentMode == PlaybackMode.shuffle
          ? Icons.shuffle_rounded
          : icon,
      size: size,
      color: color,
    ),
  );
}

/// FM owns its playback order; ordinary controls return when leaving FM.
class OrdinaryPlaybackModeBuilder extends StatelessWidget {
  const OrdinaryPlaybackModeBuilder({super.key, required this.builder});
  final TransitionBuilder builder;
  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: Listenable.merge([
      PlaybackModeService(),
      PlaylistQueueService(),
    ]),
    builder: (context, child) =>
        PlaylistQueueService().source == QueueSource.neteaseFm
        ? const SizedBox.shrink()
        : builder(context, child),
  );
}
