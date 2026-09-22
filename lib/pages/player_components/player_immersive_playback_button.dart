import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../../services/player_service.dart';

class PlayerImmersivePlaybackButton extends StatelessWidget {
  final double uiScale;

  const PlayerImmersivePlaybackButton({super.key, required this.uiScale});

  @override
  Widget build(BuildContext context) {
    final player = PlayerService();
    return RepaintBoundary(
      child: ListenableBuilder(
        listenable: player,
        builder: (context, _) {
          return DecoratedBox(
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.15),
              shape: BoxShape.circle,
            ),
            child: IconButton(
              icon: Icon(
                player.isPlaying
                    ? CupertinoIcons.pause_fill
                    : CupertinoIcons.play_fill,
                color: Colors.white,
              ),
              iconSize: 48 * uiScale,
              onPressed: player.togglePlayPause,
              tooltip: player.isPlaying ? '暂停' : '播放',
            ),
          );
        },
      ),
    );
  }
}
