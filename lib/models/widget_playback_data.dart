import 'song_detail.dart';
import 'track.dart';

/// One committed media snapshot for the Android home widget.
class WidgetPlaybackData {
  final String title;
  final String artist;
  final String mediaKey;
  final String coverUrl;
  final bool playing;

  WidgetPlaybackData({
    SongDetail? song,
    Track? track,
    required this.coverUrl,
    required this.playing,
  }) : title = song?.name ?? track?.name ?? '未在播放',
       artist = song?.arName ?? track?.artists ?? 'Cyrene Music',
       mediaKey = track != null
           ? '${track.source.name}:${track.id}'
           : song != null
           ? '${song.source.name}:${song.id}'
           : '';
}
