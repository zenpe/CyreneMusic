import 'dart:convert';
import 'package:crypto/crypto.dart';

import '../models/track.dart';
import 'navidrome_session_service.dart';
import 'playback/playback_resolver_registry.dart';

/// Public catalog identities do not depend on the Cyrene login. Private library
/// IDs are scoped to their server/user; credentials are never persisted.
Map<String, String> buildAudioCacheIdentity({
  required String source,
  required String songId,
  required String quality,
  required String resolverFingerprint,
  String? privateServer,
  String? privateUser,
}) {
  String digest(Object value) =>
      sha256.convert(utf8.encode(jsonEncode(value))).toString();
  return {
    'source': source,
    'songId': songId,
    'quality': quality,
    'owner': privateServer == null
        ? 'public'
        : digest([privateServer, privateUser]),
    // Diagnostic provenance only; never part of the complete-file key.
    'origin': digest(resolverFingerprint),
  };
}

String completeAudioCacheKey(Map<String, String> identity) => sha256
    .convert(
      utf8.encode(
        jsonEncode([
          identity['source'],
          identity['songId'],
          identity['quality'],
          identity['owner'],
        ]),
      ),
    )
    .toString();

Map<String, String> audioCacheIdentityFor(
  Track track,
  String quality, {
  bool includeOrigin = false,
}) {
  final private = track.source == MusicSource.navidrome;
  final session = NavidromeSessionService();
  return buildAudioCacheIdentity(
    source: track.source.name,
    songId: track.id.toString(),
    quality: quality,
    // Queries need only the stable key; do not hash an entire source script
    // on every cache lookup. Network-source registration retains provenance.
    resolverFingerprint: includeOrigin
        ? PlaybackResolverRegistry().fingerprintFor(track.source) ?? ''
        : '',
    privateServer: private ? session.baseUrl : null,
    privateUser: private ? session.username : null,
  );
}
