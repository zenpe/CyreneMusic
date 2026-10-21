import 'dart:convert';
import 'package:crypto/crypto.dart';
import '../../models/track.dart';
import '../navidrome_session_service.dart';
import '../api/auth_token_store.dart';
import '../url_service.dart';

String lyricCacheKey(Track track) {
  final key = '${track.source.name}_${track.id}';
  if (track.source != MusicSource.navidrome) return key;
  final session = NavidromeSessionService();
  final scope = sha256.convert(
    utf8.encode(jsonEncode([session.baseUrl, session.username])),
  );
  return '${key}_$scope';
}

String lyricRequestScope(Track track) =>
    '${lyricCacheKey(track)}_${sha256.convert(utf8.encode(jsonEncode([UrlService().backendRevision, AuthTokenStore.token, track.sourceIds.emixSongId, if (track.source == MusicSource.navidrome) NavidromeSessionService().api?.password])))}';
