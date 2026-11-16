import '../models/track.dart';

Map<String, String> buildAudioRequestHeaders(MusicSource source, {Uri? uri}) {
  final headers = <String, String>{
    'User-Agent':
        'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36',
  };

  // A track's platform does not identify the host serving its audio. Scripts
  // can return third-party CDNs, or even another platform's CDN.
  final host = uri?.host.toLowerCase() ?? '';
  bool belongsTo(String domain) => host == domain || host.endsWith('.$domain');
  if (belongsTo('qqmusic.qq.com') || belongsTo('music.tc.qq.com')) {
    headers['Referer'] = 'https://y.qq.com/';
    headers['Origin'] = 'https://y.qq.com';
  } else if (belongsTo('kugou.com') || belongsTo('kugou.cn')) {
    headers['Referer'] = 'https://www.kugou.com/';
    headers['Origin'] = 'https://www.kugou.com';
  }

  return headers;
}
