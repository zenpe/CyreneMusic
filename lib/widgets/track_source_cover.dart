import 'package:flutter/material.dart';

import '../models/track.dart';

extension MusicSourceLabel on MusicSource {
  String get shortLabel => switch (this) {
    MusicSource.netease => '网易',
    MusicSource.qq => 'QQ',
    MusicSource.kugou => '酷狗',
    MusicSource.kuwo => '酷我',
    MusicSource.apple => 'Apple',
    MusicSource.navidrome => 'NAS',
    MusicSource.spotify => 'Spotify',
    MusicSource.local => '本地',
  };

  String get platformLabel => switch (this) {
    MusicSource.netease => '网易云',
    MusicSource.qq => 'QQ音乐',
    MusicSource.kugou => '酷狗',
    MusicSource.kuwo => '酷我',
    MusicSource.apple => 'Apple Music',
    MusicSource.navidrome => 'Navidrome',
    MusicSource.spotify => 'Spotify',
    MusicSource.local => '本地音乐',
  };
}

/// Keeps platform information on the cover without consuming title space.
class TrackSourceCover extends StatelessWidget {
  const TrackSourceCover({
    super.key,
    required this.source,
    required this.child,
  });

  final MusicSource source;
  final Widget child;

  @override
  Widget build(BuildContext context) => Stack(
    children: [
      child,
      Positioned(
        right: 0,
        bottom: 0,
        child: IgnorePointer(
          child: Semantics(
            label: '来源平台：${source.platformLabel}',
            excludeSemantics: true,
            child: Container(
              constraints: const BoxConstraints(maxWidth: 46),
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
              decoration: const BoxDecoration(
                color: Color(0xB3222222),
                borderRadius: BorderRadius.only(topLeft: Radius.circular(5)),
              ),
              child: Text(
                source.shortLabel,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 9,
                  height: 1.1,
                  fontWeight: FontWeight.w500,
                  decoration: TextDecoration.none,
                ),
              ),
            ),
          ),
        ),
      ),
    ],
  );
}
