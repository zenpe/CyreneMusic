import 'music_platform.dart';
import 'track.dart';

/// 通用歌单数据模型（支持网易云和QQ音乐）
class UniversalPlaylist {
  final dynamic id;  // 网易云用int，QQ用String
  final String name;
  final String coverImgUrl;
  final String creator;
  final int trackCount;
  final String? description;
  final List<Track> tracks;
  final MusicPlatform platform;

  UniversalPlaylist({
    required this.id,
    required this.name,
    required this.coverImgUrl,
    required this.creator,
    required this.trackCount,
    this.description,
    required this.tracks,
    required this.platform,
  });

  factory UniversalPlaylist.fromJson(
    Map<String, dynamic> json,
    MusicPlatform platform,
  ) {
    final List<dynamic> tracksJson = json['tracks'] ?? [];

    // 根据平台设置正确的MusicSource
    final MusicSource source = platform == MusicPlatform.netease
        ? MusicSource.netease
        : platform == MusicPlatform.qq
            ? MusicSource.qq
            : platform == MusicPlatform.kuwo
                ? MusicSource.kuwo
                : MusicSource.kugou;

    final tracks = tracksJson.map((trackJson) {
      return Track(
        // QQ音乐使用songmid，网易云使用id，酷狗使用album_audio_id或hash
        id: platform == MusicPlatform.qq
            ? (trackJson['songmid'] ?? trackJson['id'] ?? '')
            : platform == MusicPlatform.kugou
                ? (trackJson['album_audio_id'] ?? trackJson['hash'] ?? '')
                : (trackJson['id'] ?? 0),
        name: (trackJson['name'] ?? '未知歌曲') as String,
        artists: (trackJson['artists'] ?? '未知艺术家') as String,
        album: (trackJson['album'] ?? '未知专辑') as String,
        picUrl: (trackJson['picUrl'] ?? '') as String,
        source: source,  // 🔥 关键：确保标记正确的来源
      );
    }).toList();

    return UniversalPlaylist(
      id: json['id'],
      name: (json['name'] ?? '未命名歌单') as String,
      coverImgUrl: (json['coverImgUrl'] ?? '') as String,
      creator: (json['creator'] ?? '未知') as String,
      trackCount: json['trackCount'] as int? ?? 0,
      description: json['description'] as String?,
      tracks: tracks,
      platform: platform,
    );
  }

  /// 从酷我音乐 API 返回的 JSON 创建 UniversalPlaylist
  /// 酷我音乐返回格式：
  /// {
  ///   "id": 3567349593,
  ///   "name": "dump",
  ///   "img": "https://img1.kuwo.cn/...",
  ///   "total": 3,
  ///   "desc": "",
  ///   "userName": "By苏白",
  ///   "musicList": [...]
  /// }
  factory UniversalPlaylist.fromKuwoJson(Map<String, dynamic> json) {
    final List<dynamic> musicList = json['musicList'] ?? [];

    final tracks = musicList.map((item) {
      // 酷我音乐使用 rid 作为歌曲ID
      final rid = item['rid'];
      return Track(
        id: rid is int ? rid : int.tryParse(rid.toString()) ?? 0,
        name: (item['name'] ?? '未知歌曲') as String,
        artists: (item['artist'] ?? '未知艺术家') as String,
        album: (item['album'] ?? '未知专辑') as String,
        picUrl: (item['pic'] ?? '') as String,
        source: MusicSource.kuwo,
      );
    }).toList();

    return UniversalPlaylist(
      id: json['id'],
      name: (json['name'] ?? '未命名歌单') as String,
      coverImgUrl: (json['img'] ?? '') as String,
      creator: (json['userName'] ?? '未知') as String,
      trackCount: json['total'] as int? ?? tracks.length,
      description: json['desc'] as String?,
      tracks: tracks,
      platform: MusicPlatform.kuwo,
    );
  }

  /// 从 Apple Music API 返回的 JSON 创建 UniversalPlaylist
  /// Apple Music 返回格式：
  /// {
  ///   "id": "pl.u-55D6ZJ3iDyp2AD",
  ///   "name": "歌单名称",
  ///   "coverImgUrl": "https://...",
  ///   "trackCount": 100,
  ///   "tracks": [
  ///     {"id": "1542953977", "name": "歌曲名", "artists": "艺术家", "album": "专辑", "picUrl": "..."}
  ///   ]
  /// }
  /// 注意：由于 Apple Music 有 DRM 保护，导入后需要通过其他平台搜索播放
  factory UniversalPlaylist.fromAppleJson(Map<String, dynamic> json) {
    final List<dynamic> tracksJson = json['tracks'] ?? [];

    // Apple Music 歌曲标记为 apple 来源，以便换源功能正确识别
    final tracks = tracksJson.map((item) {
      return Track(
        id: item['id'] ?? '',
        name: (item['name'] ?? '未知歌曲') as String,
        artists: (item['artists'] ?? '未知艺术家') as String,
        album: (item['album'] ?? '未知专辑') as String,
        picUrl: (item['picUrl'] ?? '') as String,
        source: MusicSource.apple,  // 标记为 Apple Music 来源
      );
    }).toList();

    return UniversalPlaylist(
      id: json['id'] ?? '',
      name: (json['name'] ?? '未命名歌单') as String,
      coverImgUrl: (json['coverImgUrl'] ?? '') as String,
      creator: 'Apple Music',
      trackCount: json['trackCount'] as int? ?? tracks.length,
      description: json['description'] as String?,
      tracks: tracks,
      platform: MusicPlatform.apple,
    );
  }
}
