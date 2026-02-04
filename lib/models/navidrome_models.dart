class NavidromeAlbum {
  final String id;
  final String name;
  final String artist;
  final String coverArt;
  final int songCount;

  NavidromeAlbum({
    required this.id,
    required this.name,
    required this.artist,
    required this.coverArt,
    required this.songCount,
  });

  factory NavidromeAlbum.fromJson(Map<String, dynamic> json) {
    return NavidromeAlbum(
      id: json['id']?.toString() ?? '',
      name: json['name'] as String? ?? '',
      artist: json['artist'] as String? ?? '',
      coverArt: json['coverArt'] as String? ?? '',
      songCount: (json['songCount'] as num?)?.toInt() ?? 0,
    );
  }
}

class NavidromeSong {
  final String id;
  final String title;
  final String artist;
  final String album;
  final String coverArt;
  final int duration;

  NavidromeSong({
    required this.id,
    required this.title,
    required this.artist,
    required this.album,
    required this.coverArt,
    required this.duration,
  });

  factory NavidromeSong.fromJson(Map<String, dynamic> json) {
    return NavidromeSong(
      id: json['id']?.toString() ?? '',
      title: json['title'] as String? ?? '',
      artist: json['artist'] as String? ?? '',
      album: json['album'] as String? ?? '',
      coverArt: json['coverArt'] as String? ?? '',
      duration: (json['duration'] as num?)?.toInt() ?? 0,
    );
  }
}

class NavidromePlaylist {
  final String id;
  final String name;
  final int songCount;
  final String coverArt;

  NavidromePlaylist({
    required this.id,
    required this.name,
    required this.songCount,
    required this.coverArt,
  });

  factory NavidromePlaylist.fromJson(Map<String, dynamic> json) {
    return NavidromePlaylist(
      id: json['id']?.toString() ?? '',
      name: json['name'] as String? ?? '',
      songCount: (json['songCount'] as num?)?.toInt() ?? 0,
      coverArt: json['coverArt'] as String? ?? '',
    );
  }
}

class NavidromeSearchResult {
  final List<NavidromeSong> songs;

  NavidromeSearchResult({required this.songs});
}
