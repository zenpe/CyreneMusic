import '../models/track.dart';

Track neteaseSongToTrack(Map<String, dynamic> song) {
  final album =
      (song['al'] ?? song['album'] ?? <String, dynamic>{})
          as Map<String, dynamic>;
  final artists = (song['ar'] ?? song['artists'] ?? []) as List<dynamic>;
  return Track(
    id: song['id'] ?? 0,
    name: song['name']?.toString() ?? '',
    artists: artists
        .map((e) => (e as Map<String, dynamic>)['name']?.toString() ?? '')
        .where((e) => e.isNotEmpty)
        .join(' / '),
    album: album['name']?.toString() ?? '',
    picUrl: album['picUrl']?.toString() ?? '',
    source: MusicSource.netease,
  );
}
