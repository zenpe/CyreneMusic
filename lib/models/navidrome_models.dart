/// Navidrome/Subsonic API 数据模型

/// 专辑模型
class NavidromeAlbum {
  final String id;
  final String name;
  final String artist;
  final String artistId;
  final String coverArt;
  final int songCount;
  final int? year;
  final String? genre;
  final int? duration; // 总时长（秒）
  final bool starred;

  NavidromeAlbum({
    required this.id,
    required this.name,
    required this.artist,
    this.artistId = '',
    required this.coverArt,
    required this.songCount,
    this.year,
    this.genre,
    this.duration,
    this.starred = false,
  });

  factory NavidromeAlbum.fromJson(Map<String, dynamic> json) {
    return NavidromeAlbum(
      id: json['id']?.toString() ?? '',
      name: json['name'] as String? ?? '',
      artist: json['artist'] as String? ?? '',
      artistId: json['artistId']?.toString() ?? '',
      coverArt: json['coverArt'] as String? ?? '',
      songCount: (json['songCount'] as num?)?.toInt() ?? 0,
      year: (json['year'] as num?)?.toInt(),
      genre: json['genre'] as String?,
      duration: (json['duration'] as num?)?.toInt(),
      starred: json['starred'] != null,
    );
  }

  /// 格式化时长显示
  String get durationFormatted {
    if (duration == null) return '';
    final minutes = duration! ~/ 60;
    return '$minutes 分钟';
  }
}

/// 歌曲模型
class NavidromeSong {
  final String id;
  final String title;
  final String artist;
  final String artistId;
  final String album;
  final String albumId;
  final String coverArt;
  final int duration;
  final int? track; // 音轨号
  final int? discNumber; // 碟片号
  final int? year;
  final String? genre;
  final int? bitRate;
  final String? suffix; // 文件格式 (mp3, flac, etc.)
  final bool starred;

  NavidromeSong({
    required this.id,
    required this.title,
    required this.artist,
    this.artistId = '',
    required this.album,
    this.albumId = '',
    required this.coverArt,
    required this.duration,
    this.track,
    this.discNumber,
    this.year,
    this.genre,
    this.bitRate,
    this.suffix,
    this.starred = false,
  });

  factory NavidromeSong.fromJson(Map<String, dynamic> json) {
    return NavidromeSong(
      id: json['id']?.toString() ?? '',
      title: json['title'] as String? ?? '',
      artist: json['artist'] as String? ?? '',
      artistId: json['artistId']?.toString() ?? '',
      album: json['album'] as String? ?? '',
      albumId: json['albumId']?.toString() ?? '',
      coverArt: json['coverArt'] as String? ?? '',
      duration: (json['duration'] as num?)?.toInt() ?? 0,
      track: (json['track'] as num?)?.toInt(),
      discNumber: (json['discNumber'] as num?)?.toInt(),
      year: (json['year'] as num?)?.toInt(),
      genre: json['genre'] as String?,
      bitRate: (json['bitRate'] as num?)?.toInt(),
      suffix: json['suffix'] as String?,
      starred: json['starred'] != null,
    );
  }

  /// 格式化时长显示
  String get durationFormatted {
    final minutes = duration ~/ 60;
    final seconds = duration % 60;
    return '$minutes:${seconds.toString().padLeft(2, '0')}';
  }
}

/// 艺术家模型
class NavidromeArtist {
  final String id;
  final String name;
  final String? coverArt;
  final int albumCount;
  final bool starred;

  NavidromeArtist({
    required this.id,
    required this.name,
    this.coverArt,
    this.albumCount = 0,
    this.starred = false,
  });

  factory NavidromeArtist.fromJson(Map<String, dynamic> json) {
    return NavidromeArtist(
      id: json['id']?.toString() ?? '',
      name: json['name'] as String? ?? '',
      coverArt: json['coverArt'] as String?,
      albumCount: (json['albumCount'] as num?)?.toInt() ?? 0,
      starred: json['starred'] != null,
    );
  }
}

/// 艺术家详情（包含专辑列表）
class NavidromeArtistInfo {
  final NavidromeArtist artist;
  final List<NavidromeAlbum> albums;
  final String? biography;
  final String? musicBrainzId;
  final String? lastFmUrl;
  final List<String> similarArtistIds;

  NavidromeArtistInfo({
    required this.artist,
    required this.albums,
    this.biography,
    this.musicBrainzId,
    this.lastFmUrl,
    this.similarArtistIds = const [],
  });
}

/// 歌单模型
class NavidromePlaylist {
  final String id;
  final String name;
  final int songCount;
  final String coverArt;
  final int? duration;
  final String? owner;
  final bool public;
  final String? comment;

  NavidromePlaylist({
    required this.id,
    required this.name,
    required this.songCount,
    required this.coverArt,
    this.duration,
    this.owner,
    this.public = false,
    this.comment,
  });

  factory NavidromePlaylist.fromJson(Map<String, dynamic> json) {
    return NavidromePlaylist(
      id: json['id']?.toString() ?? '',
      name: json['name'] as String? ?? '',
      songCount: (json['songCount'] as num?)?.toInt() ?? 0,
      coverArt: json['coverArt'] as String? ?? '',
      duration: (json['duration'] as num?)?.toInt(),
      owner: json['owner'] as String?,
      public: json['public'] as bool? ?? false,
      comment: json['comment'] as String?,
    );
  }
}

/// 网络电台模型
class NavidromeRadioStation {
  final String id;
  final String name;
  final String streamUrl;
  final String? homePageUrl;

  NavidromeRadioStation({
    required this.id,
    required this.name,
    required this.streamUrl,
    this.homePageUrl,
  });

  factory NavidromeRadioStation.fromJson(Map<String, dynamic> json) {
    return NavidromeRadioStation(
      id: json['id']?.toString() ?? '',
      name: json['name'] as String? ?? '',
      streamUrl: json['streamUrl'] as String? ?? '',
      homePageUrl: json['homePageUrl'] as String?,
    );
  }
}

/// 搜索结果模型
class NavidromeSearchResult {
  final List<NavidromeArtist> artists;
  final List<NavidromeAlbum> albums;
  final List<NavidromeSong> songs;

  NavidromeSearchResult({
    this.artists = const [],
    this.albums = const [],
    this.songs = const [],
  });

  bool get isEmpty => artists.isEmpty && albums.isEmpty && songs.isEmpty;

  int get totalCount => artists.length + albums.length + songs.length;
}

/// 流派模型
class NavidromeGenre {
  final String name;
  final int songCount;
  final int albumCount;

  NavidromeGenre({
    required this.name,
    this.songCount = 0,
    this.albumCount = 0,
  });

  factory NavidromeGenre.fromJson(Map<String, dynamic> json) {
    return NavidromeGenre(
      name: json['value'] as String? ?? '',
      songCount: (json['songCount'] as num?)?.toInt() ?? 0,
      albumCount: (json['albumCount'] as num?)?.toInt() ?? 0,
    );
  }
}

/// 专辑列表类型枚举
enum AlbumListType {
  random('random'),
  newest('newest'),
  highest('highest'),
  frequent('frequent'),
  recent('recent'),
  alphabeticalByName('alphabeticalByName'),
  alphabeticalByArtist('alphabeticalByArtist'),
  starred('starred'),
  byYear('byYear'),
  byGenre('byGenre');

  final String value;
  const AlbumListType(this.value);
}
