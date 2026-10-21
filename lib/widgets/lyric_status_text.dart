import 'package:flutter/material.dart';
import '../services/player_service.dart';
import '../services/lyric/lyric_service.dart';

/// Shared empty-state action for all player themes. It retries lyrics only.
class LyricStatusText extends StatelessWidget {
  final LyricLoadState state;
  final TextStyle? style;
  const LyricStatusText({super.key, required this.state, this.style});

  @override
  Widget build(BuildContext context) {
    final canRetry =
        state == LyricLoadState.failed || state == LyricLoadState.transientMiss;
    final text = Text(
      '${state.displayText}${canRetry ? ' · 点击重试' : ''}',
      style: style,
      textAlign: TextAlign.center,
    );
    if (!canRetry) return text;
    final snapshot = PlayerService().lyricSnapshot;
    return TextButton(
      style: TextButton.styleFrom(foregroundColor: style?.color),
      onPressed: () {
        if (snapshot != null) {
          LyricService().retryCurrentLyrics(
            trackKey: snapshot.trackKey,
            playbackToken: snapshot.playbackToken,
          );
        }
      },
      child: text,
    );
  }
}
