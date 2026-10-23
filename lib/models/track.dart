/// 音乐平台枚举
enum MusicSource {
  netease,  // 网易云音乐
  qq,       // QQ音乐
  kugou,    // 酷狗音乐
  kuwo,     // 酷我音乐
  apple,    // Apple Music
  navidrome, // Navidrome
  spotify,  // Spotify
  local,    // 本地文件
}

/// 平台原始标识。不同下游只能读取自己协议明确要求的字段。
class TrackSourceIds {
  final String? fileHash;
  final String? emixSongId;
  final String? albumAudioId;

  const TrackSourceIds({this.fileHash, this.emixSongId, this.albumAudioId});

  bool get isEmpty =>
      fileHash == null && emixSongId == null && albumAudioId == null;

  Map<String, dynamic> toJson() => {
    if (fileHash != null) 'fileHash': fileHash,
    if (emixSongId != null) 'emixSongId': emixSongId,
    if (albumAudioId != null) 'albumAudioId': albumAudioId,
  };

  factory TrackSourceIds.fromJson(dynamic json) {
    if (json is! Map) return const TrackSourceIds();
    String? value(String key) {
      final raw = json[key];
      final text = raw?.toString().trim();
      return text == null || text.isEmpty ? null : text;
    }

    return TrackSourceIds(
      fileHash: value('fileHash'),
      emixSongId: value('emixSongId'),
      albumAudioId: value('albumAudioId'),
    );
  }
}

class MissingTrackSourceIdentifierException implements Exception {
  final String message;

  const MissingTrackSourceIdentifierException(this.message);

  @override
  String toString() => message;
}

/// 歌曲模型
class Track {
  final dynamic id;  // 支持 int 和 String 类型（网易云用int，QQ和酷狗用String）
  final String name;
  final String artists;
  final String album;
  final String picUrl;
  final MusicSource source;
  final TrackSourceIds sourceIds;

  Track({
    required this.id,
    required this.name,
    required this.artists,
    required this.album,
    required this.picUrl,
    this.source = MusicSource.netease, // 默认网易云音乐
    this.sourceIds = const TrackSourceIds(),
  });

  /// 从 JSON 创建 Track 对象
  factory Track.fromJson(Map<String, dynamic> json, {MusicSource? source}) {
    return Track(
      id: json['id'],  // 可以是 int 或 String
      name: json['name'] as String,
      artists: json['artists'] as String,
      album: json['album'] as String,
      picUrl: json['picUrl'] as String,
      source: source ?? _parseSource(json['source']),
      sourceIds: TrackSourceIds.fromJson(json['sourceIds']),
    );
  }

  /// 转换为 JSON
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'artists': artists,
      'album': album,
      'picUrl': picUrl,
      'source': source.name,
      if (!sourceIds.isEmpty) 'sourceIds': sourceIds.toJson(),
    };
  }

  static MusicSource _parseSource(dynamic value) {
    return MusicSource.values.firstWhere(
      (source) => source.name == value?.toString(),
      orElse: () => MusicSource.netease,
    );
  }

  /// 获取音乐来源的中文名称
  String getSourceName() {
    switch (source) {
      case MusicSource.netease:
        return '网易云音乐';
      case MusicSource.qq:
        return 'QQ音乐';
      case MusicSource.kugou:
        return '酷狗音乐';
      case MusicSource.kuwo:
        return '酷我音乐';
      case MusicSource.apple:
        return 'Apple Music';
      case MusicSource.navidrome:
        return 'Navidrome';
      case MusicSource.spotify:
        return 'Spotify';
      case MusicSource.local:
        return '本地';
    }
  }

  /// 获取音乐来源的图标
  String getSourceIcon() {
    switch (source) {
      case MusicSource.netease:
        return '🎵';
      case MusicSource.qq:
        return '🎶';
      case MusicSource.kugou:
        return '🎼';
      case MusicSource.kuwo:
        return '🎸';
      case MusicSource.apple:
        return '🍎';
      case MusicSource.navidrome:
        return '🎧';
      case MusicSource.spotify:
        return '🟢';
      case MusicSource.local:
        return '📁';
    }
  }
}
