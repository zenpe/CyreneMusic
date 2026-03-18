import '../../models/track.dart';
import '../playback_mode_service.dart';
import '../playlist_queue_service.dart';

enum PlaybackSessionState { idle, playing, paused }

class PlaybackSessionSnapshot {
  PlaybackSessionSnapshot({
    required this.version,
    required this.savedAt,
    required this.queue,
    required this.currentIndex,
    required this.source,
    required this.position,
    required this.state,
    required this.playbackMode,
  });

  final int version;
  final DateTime savedAt;
  final List<Track> queue;
  final int currentIndex;
  final QueueSource source;
  final Duration position;
  final PlaybackSessionState state;
  final PlaybackMode playbackMode;

  bool get isValid =>
      queue.isNotEmpty &&
      currentIndex >= 0 &&
      currentIndex < queue.length &&
      position >= Duration.zero;

  Map<String, dynamic> toJson() {
    return {
      'version': version,
      'savedAt': savedAt.toIso8601String(),
      'queue': queue.map((track) => track.toJson()).toList(),
      'currentIndex': currentIndex,
      'source': source.name,
      'positionMs': position.inMilliseconds,
      'state': state.name,
      'playbackMode': playbackMode.name,
    };
  }

  factory PlaybackSessionSnapshot.fromJson(Map<String, dynamic> json) {
    final queueJson = json['queue'];
    if (queueJson is! List) {
      throw const FormatException('queue is missing or invalid');
    }

    final queue = queueJson
        .whereType<Map>()
        .map(
          (item) => Track.fromJson(
            Map<String, dynamic>.from(item.cast<String, dynamic>()),
            source: _parseMusicSource(item['source']),
          ),
        )
        .toList();

    return PlaybackSessionSnapshot(
      version: (json['version'] as num?)?.toInt() ?? 1,
      savedAt: DateTime.tryParse(json['savedAt'] as String? ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0),
      queue: queue,
      currentIndex: (json['currentIndex'] as num?)?.toInt() ?? -1,
      source: _parseQueueSource(json['source'] as String?),
      position: Duration(
        milliseconds: (json['positionMs'] as num?)?.toInt() ?? 0,
      ),
      state: _parseSessionState(json['state'] as String?),
      playbackMode: _parsePlaybackMode(json['playbackMode'] as String?),
    );
  }

  static MusicSource _parseMusicSource(String? sourceName) {
    return MusicSource.values.firstWhere(
      (source) => source.name == sourceName,
      orElse: () => MusicSource.netease,
    );
  }

  static QueueSource _parseQueueSource(String? sourceName) {
    return QueueSource.values.firstWhere(
      (source) => source.name == sourceName,
      orElse: () => QueueSource.none,
    );
  }

  static PlaybackSessionState _parseSessionState(String? stateName) {
    return PlaybackSessionState.values.firstWhere(
      (state) => state.name == stateName,
      orElse: () => PlaybackSessionState.idle,
    );
  }

  static PlaybackMode _parsePlaybackMode(String? modeName) {
    return PlaybackMode.values.firstWhere(
      (mode) => mode.name == modeName,
      orElse: () => PlaybackMode.loopAll,
    );
  }
}
