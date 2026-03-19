import 'package:just_audio/just_audio.dart' as ja;

import '../cache_service.dart';

abstract class PlayableSource {
  const PlayableSource();

  String? get playbackPathOrUrl;
  String? get sourceUrl;
  bool get isLocal;
  Map<String, String>? get headers => null;
  ja.AudioSource? get audioSource => null;
}

class DirectHttpPlayableSource extends PlayableSource {
  final String url;
  final Map<String, String>? requestHeaders;

  const DirectHttpPlayableSource(
    this.url, {
    this.requestHeaders,
  });

  @override
  String get playbackPathOrUrl => url;

  @override
  String get sourceUrl => url;

  @override
  bool get isLocal => false;

  @override
  Map<String, String>? get headers => requestHeaders;
}

class ProxyHttpPlayableSource extends PlayableSource {
  final String url;
  final String? originalUrl;

  const ProxyHttpPlayableSource(
    this.url, {
    this.originalUrl,
  });

  @override
  String get playbackPathOrUrl => url;

  @override
  String get sourceUrl => originalUrl ?? url;

  @override
  bool get isLocal => false;
}

class LocalFilePlayableSource extends PlayableSource {
  final String filePath;
  final String? originalUrl;

  const LocalFilePlayableSource(
    this.filePath, {
    this.originalUrl,
  });

  @override
  String get playbackPathOrUrl => filePath;

  @override
  String get sourceUrl => originalUrl ?? filePath;

  @override
  bool get isLocal => true;
}

class CachedCyrenePlayableSource extends PlayableSource {
  final CyreneFileInfo cacheInfo;
  final String? playbackUrl;
  final ja.AudioSource? playbackAudioSource;

  const CachedCyrenePlayableSource.proxy({
    required this.cacheInfo,
    required this.playbackUrl,
  }) : playbackAudioSource = null;

  const CachedCyrenePlayableSource.stream({
    required this.cacheInfo,
    required this.playbackAudioSource,
  }) : playbackUrl = null;

  @override
  String? get playbackPathOrUrl => playbackUrl;

  @override
  String get sourceUrl => cacheInfo.metadata.originalUrl;

  @override
  bool get isLocal => playbackUrl == null;

  @override
  ja.AudioSource? get audioSource => playbackAudioSource;
}
