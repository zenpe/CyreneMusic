import 'track.dart';

enum PlaylistType { local, synced }

/// 歌单模型
class Playlist {
  final int id;
  final String name;
  final bool isDefault; // 是否为默认歌单（我的收藏）
  final int trackCount; // 歌曲数量
  final String? coverUrl; // 歌单封面（第一首歌的封面）
  final DateTime createdAt;
  final DateTime updatedAt;
  final String? source; // 来源平台：netease/qq
  final String? sourcePlaylistId; // 来源歌单ID
  final PlaylistType type;
  final int contentRevision;
  final int orderRevision;
  final String syncStatus;
  final DateTime? lastSyncedAt;

  Playlist({
    required this.id,
    required this.name,
    required this.isDefault,
    required this.trackCount,
    this.coverUrl,
    required this.createdAt,
    required this.updatedAt,
    this.source,
    this.sourcePlaylistId,
    this.type = PlaylistType.local,
    this.contentRevision = 0,
    this.orderRevision = 0,
    this.syncStatus = 'idle',
    this.lastSyncedAt,
  });

  bool get isLocal => type == PlaylistType.local;
  bool get isSynced => type == PlaylistType.synced;

  factory Playlist.fromJson(Map<String, dynamic> json) {
    return Playlist(
      id: json['id'] as int,
      name: json['name'] as String,
      isDefault: json['isDefault'] as bool? ?? false,
      trackCount: json['trackCount'] as int? ?? 0,
      coverUrl: json['coverUrl'] as String?,
      createdAt: DateTime.parse(json['createdAt'] as String),
      updatedAt: DateTime.parse(json['updatedAt'] as String),
      source: json['source'] as String?,
      sourcePlaylistId: json['sourcePlaylistId'] as String?,
      type: json['type'] == 'synced' ? PlaylistType.synced : PlaylistType.local,
      contentRevision: (json['contentRevision'] as num?)?.toInt() ?? 0,
      orderRevision: (json['orderRevision'] as num?)?.toInt() ?? 0,
      syncStatus: json['syncStatus'] as String? ?? 'idle',
      lastSyncedAt: json['lastSyncedAt'] == null
          ? null
          : DateTime.tryParse(json['lastSyncedAt'] as String),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'isDefault': isDefault,
      'trackCount': trackCount,
      'coverUrl': coverUrl,
      'createdAt': createdAt.toIso8601String(),
      'updatedAt': updatedAt.toIso8601String(),
      'source': source,
      'sourcePlaylistId': sourcePlaylistId,
      'type': type.name,
      'contentRevision': contentRevision,
      'orderRevision': orderRevision,
      'syncStatus': syncStatus,
      'lastSyncedAt': lastSyncedAt?.toIso8601String(),
    };
  }

  Playlist copyWith({
    String? name,
    int? trackCount,
    int? contentRevision,
    int? orderRevision,
    String? syncStatus,
    DateTime? lastSyncedAt,
    DateTime? updatedAt,
  }) {
    return Playlist(
      id: id,
      name: name ?? this.name,
      isDefault: isDefault,
      trackCount: trackCount ?? this.trackCount,
      coverUrl: coverUrl,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      source: source,
      sourcePlaylistId: sourcePlaylistId,
      type: type,
      contentRevision: contentRevision ?? this.contentRevision,
      orderRevision: orderRevision ?? this.orderRevision,
      syncStatus: syncStatus ?? this.syncStatus,
      lastSyncedAt: lastSyncedAt ?? this.lastSyncedAt,
    );
  }
}

/// 歌单中的歌曲模型
class PlaylistTrack {
  final int? itemId;
  final String trackId;
  final String name;
  final String artists;
  final String album;
  final String picUrl;
  final MusicSource source;
  final TrackSourceIds sourceIds;
  final DateTime addedAt;

  PlaylistTrack({
    this.itemId,
    required this.trackId,
    required this.name,
    required this.artists,
    required this.album,
    required this.picUrl,
    required this.source,
    this.sourceIds = const TrackSourceIds(),
    required this.addedAt,
  });

  factory PlaylistTrack.fromJson(Map<String, dynamic> json) {
    return PlaylistTrack(
      itemId: (json['itemId'] as num?)?.toInt(),
      trackId: json['trackId'] as String,
      name: json['name'] as String,
      artists: json['artists'] as String,
      album: json['album'] as String,
      picUrl: json['picUrl'] as String,
      source: _parseSource(json['source'] as String),
      sourceIds: TrackSourceIds.fromJson(json['sourceIds']),
      addedAt: DateTime.parse(json['addedAt'] as String),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      if (itemId != null) 'itemId': itemId,
      'trackId': trackId,
      'name': name,
      'artists': artists,
      'album': album,
      'picUrl': picUrl,
      'source': source.toString().split('.').last,
      if (!sourceIds.isEmpty) 'sourceIds': sourceIds.toJson(),
      'addedAt': addedAt.toIso8601String(),
    };
  }

  /// 从 Track 创建 PlaylistTrack
  factory PlaylistTrack.fromTrack(Track track) {
    return PlaylistTrack(
      trackId: track.id.toString(),
      name: track.name,
      artists: track.artists,
      album: track.album,
      picUrl: track.picUrl,
      source: track.source,
      sourceIds: track.sourceIds,
      addedAt: DateTime.now(),
    );
  }

  /// 转换为 Track 对象
  Track toTrack() {
    // 尝试解析为 int，如果失败则保持为字符串（用于 QQ 音乐和酷狗音乐）
    final dynamic trackIdValue = int.tryParse(trackId) ?? trackId;

    return Track(
      id: trackIdValue, // 支持 int 和 String 类型
      name: name,
      artists: artists,
      album: album,
      picUrl: picUrl,
      source: source,
      sourceIds: sourceIds,
    );
  }

  /// 解析音乐源
  static MusicSource _parseSource(String source) {
    switch (source.toLowerCase()) {
      case 'netease':
        return MusicSource.netease;
      case 'apple':
        return MusicSource.apple;
      case 'qq':
        return MusicSource.qq;
      case 'kugou':
        return MusicSource.kugou;
      case 'kuwo':
        return MusicSource.kuwo;
      case 'navidrome':
        return MusicSource.navidrome;
      case 'local':
        return MusicSource.local;
      default:
        return MusicSource.netease;
    }
  }
}
