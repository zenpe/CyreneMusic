import '../../models/song_detail.dart';
import '../../models/track.dart';

enum LyricFetchKind { ready, empty, unavailable, unsupported, cancelled }

/// Lyrics only: applying a response must never replace audio or track metadata.
class LyricPayload {
  final String lyric, tlyric, yrc, ytlrc, qrc, qrcTrans;
  const LyricPayload({
    this.lyric = '',
    this.tlyric = '',
    this.yrc = '',
    this.ytlrc = '',
    this.qrc = '',
    this.qrcTrans = '',
  });

  factory LyricPayload.fromMap(Map data) => LyricPayload(
    lyric: data['lyric'] is String ? data['lyric'] : '',
    tlyric: data['tlyric'] is String ? data['tlyric'] : '',
    yrc: data['yrc'] is String ? data['yrc'] : '',
    ytlrc: data['ytlrc'] is String ? data['ytlrc'] : '',
    qrc: data['qrc'] is String ? data['qrc'] : '',
    qrcTrans: data['qrcTrans'] is String ? data['qrcTrans'] : '',
  );

  factory LyricPayload.fromSong(SongDetail song) => LyricPayload(
    lyric: song.lyric,
    tlyric: song.tlyric,
    yrc: song.yrc,
    ytlrc: song.ytlrc,
    qrc: song.qrc,
    qrcTrans: song.qrcTrans,
  );

  bool get hasPrimary =>
      lyric.trim().isNotEmpty || yrc.trim().isNotEmpty || qrc.trim().isNotEmpty;

  SongDetail merge(Track track, SongDetail? current) => SongDetail(
    id: current?.id ?? track.id,
    name: current?.name ?? track.name,
    pic: current?.pic ?? track.picUrl,
    arName: current?.arName ?? track.artists,
    alName: current?.alName ?? track.album,
    level: current?.level ?? '',
    size: current?.size ?? '0',
    url: current?.url ?? '',
    source: track.source,
    lyric: lyric.isNotEmpty ? lyric : current?.lyric ?? '',
    tlyric: tlyric.isNotEmpty ? tlyric : current?.tlyric ?? '',
    yrc: yrc.isNotEmpty ? yrc : current?.yrc ?? '',
    ytlrc: ytlrc.isNotEmpty ? ytlrc : current?.ytlrc ?? '',
    qrc: qrc.isNotEmpty ? qrc : current?.qrc ?? '',
    qrcTrans: qrcTrans.isNotEmpty ? qrcTrans : current?.qrcTrans ?? '',
  );
}

class LyricFetchResult {
  final LyricFetchKind kind;
  final LyricPayload payload;
  final bool retryable;
  final Duration? retryAfter;
  const LyricFetchResult(
    this.kind, {
    this.payload = const LyricPayload(),
    this.retryable = false,
    this.retryAfter,
  });
}
