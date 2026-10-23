import '../models/track.dart';

Map<String, String> buildAudioRequestHeaders(MusicSource source) {
  final headers = <String, String>{
    'User-Agent':
        'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36',
  };

  if (source == MusicSource.qq) {
    headers['Referer'] = 'https://y.qq.com/';
    headers['Origin'] = 'https://y.qq.com';
  } else if (source == MusicSource.kugou) {
    headers['Referer'] = 'https://www.kugou.com/';
    headers['Origin'] = 'https://www.kugou.com';
  }

  return headers;
}
