import 'package:cyrene_music/services/audio_cache_identity.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Map<String, String> identity({
    String source = 'qq',
    String song = 'AbC',
    String quality = 'standard',
    String origin = 'script',
    String? server,
    String? user,
  }) => buildAudioCacheIdentity(
    source: source,
    songId: song,
    quality: quality,
    resolverFingerprint: origin,
    privateServer: server,
    privateUser: user,
  );
  test('public resource identity has no Cyrene login or expiring URL', () {
    final value = identity();
    expect(value['owner'], 'public');
    expect(value['songId'], 'AbC');
    expect(
      value.keys,
      unorderedEquals(['source', 'songId', 'quality', 'origin', 'owner']),
    );
    expect(identity(), value);
    expect(identity(song: 'abc'), isNot(value));
    expect(identity(quality: 'lossless'), isNot(value));
    expect(identity(source: 'netease'), isNot(value));
    expect(identity(origin: 'other'), isNot(value));
    expect(
      completeAudioCacheKey(identity(origin: 'other')),
      completeAudioCacheKey(value),
    );
    for (final other in [
      identity(song: 'abc'),
      identity(quality: 'lossless'),
      identity(source: 'netease'),
    ]) {
      expect(completeAudioCacheKey(other), isNot(completeAudioCacheKey(value)));
    }
  });
  test(
    'private libraries isolate server and user without storing credentials',
    () {
      final value = identity(
        source: 'navidrome',
        server: 'https://one',
        user: 'alice',
      );
      expect(value['owner'], isNot(contains('alice')));
      expect(
        identity(source: 'navidrome', server: 'https://two', user: 'alice'),
        isNot(value),
      );
      expect(
        identity(source: 'navidrome', server: 'https://one', user: 'bob'),
        isNot(value),
      );
    },
  );
}
