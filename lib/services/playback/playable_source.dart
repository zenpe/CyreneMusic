import 'package:just_audio/just_audio.dart' as ja;

abstract class PlayableSource {
  const PlayableSource();

  String? get playbackPathOrUrl;
  String? get sourceUrl;
  bool get isLocal;
  Map<String, String>? get headers => null;
  ja.AudioSource? get audioSource => null;
}

class PreparedPlaybackSlot {
  final String key;
  final PlayableSource source;
  final DateTime expiresAt;
  final int queueRevision;

  const PreparedPlaybackSlot({
    required this.key,
    required this.source,
    required this.expiresAt,
    required this.queueRevision,
  });

  bool get isExpired => DateTime.now().isAfter(expiresAt);
}

class PreparedPlaybackWindow {
  final PreparedPlaybackSlot current;
  final PreparedPlaybackSlot? previous;
  final PreparedPlaybackSlot? next;

  const PreparedPlaybackWindow({
    required this.current,
    this.previous,
    this.next,
  });
}

class DirectHttpPlayableSource extends PlayableSource {
  final String url;
  final Map<String, String>? requestHeaders;

  const DirectHttpPlayableSource(this.url, {this.requestHeaders});

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

  const ProxyHttpPlayableSource(this.url, {this.originalUrl});

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

  const LocalFilePlayableSource(this.filePath, {this.originalUrl});

  @override
  String get playbackPathOrUrl => filePath;

  @override
  String get sourceUrl => originalUrl ?? filePath;

  @override
  bool get isLocal => true;
}
