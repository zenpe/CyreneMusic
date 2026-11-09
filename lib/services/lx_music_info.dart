import '../models/track.dart';

/// Metadata already known by the app, expressed in the LX script contract.
/// QQ songmid is not strMediaMid; a Kugou albumAudioId is not albumId. Unknown
/// platform fields must remain absent instead of substituting another ID.
Map<String, dynamic> buildLxMusicInfo({
  required String source,
  required dynamic songId,
  String? title,
  String? artist,
  String? album,
  TrackSourceIds sourceIds = const TrackSourceIds(),
}) {
  final info = <String, dynamic>{
    'source': source,
    'songmid': songId.toString(),
    if (source == 'wy' || source == 'kw') 'id': songId,
    if (source == 'kw') 'rid': songId,
    if (source == 'kg') 'hash': songId.toString(),
    if (source == 'kg' && sourceIds.albumAudioId != null)
      'albumAudioId': sourceIds.albumAudioId,
    if (source == 'mg') 'copyrightId': songId.toString(),
  };
  if (title != null && title.isNotEmpty) {
    info.addAll({'name': title, 'songName': title});
  }
  if (artist != null && artist.isNotEmpty) {
    info.addAll({'singer': artist, 'artist': artist});
  }
  if (album != null && album.isNotEmpty) {
    info['albumName'] = album;
  }
  return info;
}
