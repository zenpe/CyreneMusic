import 'package:cyrene_music/services/cache_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('manifest metadata requires a relative audio path', () {
    final json = _metadataJson()..remove('relativePath');

    expect(CacheMetadata.tryFromJson(json), isNull);
  });

  test('manifest metadata persists native audio file information', () {
    final metadata = CacheMetadata.fromJson(_metadataJson());

    expect(metadata.relativePath, 'audio/ab/cache.flac');
    expect(metadata.contentType, 'audio/flac');
    expect(metadata.toJson()['relativePath'], 'audio/ab/cache.flac');
    expect(metadata.toJson()['contentType'], 'audio/flac');
  });

  test('legacy resolver fingerprint is ignored and never persisted', () {
    final json = _metadataJson()
      ..['resolverFingerprint'] = 'const enormousLxScript = true;';

    final metadata = CacheMetadata.fromJson(json);

    expect(metadata.toJson(), isNot(contains('resolverFingerprint')));
  });
}

Map<String, dynamic> _metadataJson() => <String, dynamic>{
  'songId': '1',
  'songName': 'Track',
  'artists': 'Artist',
  'album': 'Album',
  'picUrl': '',
  'source': 'netease',
  'quality': 'exhigh',
  'originalUrl': 'https://example.invalid/audio',
  'fileSize': 1024,
  'cachedAt': DateTime.utc(2026).toIso8601String(),
  'lastAccessedAt': DateTime.utc(2026).toIso8601String(),
  'checksum': 'checksum',
  'relativePath': 'audio/ab/cache.flac',
  'contentType': 'audio/flac',
  'lyric': '',
  'tlyric': '',
};
