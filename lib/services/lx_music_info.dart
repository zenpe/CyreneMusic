import '../utils/audio_duration_evidence.dart';
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
  int? durationMs,
  TrackSourceIds sourceIds = const TrackSourceIds(),
  LxMusicMetadata lxMetadata = const LxMusicMetadata(),
}) {
  final info = <String, dynamic>{
    'source': source,
    'interval': ?lxInterval(durationMs),
    'songmid': source == 'wy' || source == 'kw'
        ? int.tryParse(songId.toString()) ?? songId
        : songId.toString(),
    'img': lxMetadata.img,
    'typeUrl': <String, dynamic>{},
    'types': [
      for (final type in LxMusicMetadata.qualityOrder)
        if (lxMetadata.qualities.containsKey(type))
          {
            'type': type,
            if (lxMetadata.qualities[type]!['size'] != null)
              'size': lxMetadata.qualities[type]!['size'],
          },
    ],
    '_types': {
      for (final type in LxMusicMetadata.qualityOrder)
        if (lxMetadata.qualities.containsKey(type))
          type: {
            if (lxMetadata.qualities[type]!['size'] != null)
              'size': lxMetadata.qualities[type]!['size'],
          },
    },
    if (lxMetadata.albumId != null)
      'albumId': source == 'wy'
          ? int.tryParse(lxMetadata.albumId!) ?? lxMetadata.albumId
          : lxMetadata.albumId,
    if (source == 'tx' && lxMetadata.songId != null)
      'songId': int.tryParse(lxMetadata.songId!) ?? lxMetadata.songId,
    if (source == 'tx' && lxMetadata.strMediaMid != null)
      'strMediaMid': lxMetadata.strMediaMid,
    if (source == 'tx' && lxMetadata.albumMid != null)
      'albumMid': lxMetadata.albumMid,
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
