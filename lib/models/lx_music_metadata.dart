import 'dart:convert';

/// Original platform fields required by LX scripts. Never substitutes one ID
/// for another or infers song quality from a script's supported qualities.
class LxMusicMetadata {
  final String? songId;
  final String? strMediaMid;
  final String? albumId;
  final String? albumMid;
  final String img;
  final Map<String, Map<String, dynamic>> qualities;

  const LxMusicMetadata({
    this.songId,
    this.strMediaMid,
    this.albumId,
    this.albumMid,
    this.img = '',
    this.qualities = const {},
  });

  static const qualityOrder = ['128k', '192k', '320k', 'flac', 'flac24bit'];

  factory LxMusicMetadata.fromPlatformJson(Map raw, {required String source}) {
    final fields = <String, dynamic>{};
    final album = raw['album'] is Map
        ? raw['album'] as Map
        : raw['al'] is Map
        ? raw['al'] as Map
        : const {};
    final sizes = <String, dynamic>{};
    if (source == 'qq') {
      final id = raw['id'] ?? raw['songid'];
      final number = int.tryParse(id?.toString() ?? '');
      if (number != null && number > 0 && number <= 9007199254740991) {
        fields['songId'] = '$number';
      }
      final file = raw['file'] is Map ? raw['file'] as Map : const {};
      fields['strMediaMid'] = file['media_mid'] ?? raw['strMediaMid'];
      fields['albumId'] = album['mid'] ?? raw['albummid'];
      fields['albumMid'] = album['mid'] ?? raw['albummid'];
      for (final entry in const {
        '128k': 'size_128mp3',
        '320k': 'size_320mp3',
        'flac': 'size_flac',
        'flac24bit': 'size_hires',
      }.entries) {
        sizes[entry.key] = file[entry.value];
      }
    } else if (source == 'netease') {
      fields['albumId'] = album['id'];
      fields['img'] = album['picUrl'];
      for (final entry in const {
        '128k': 'l',
        '320k': 'h',
        'flac': 'sq',
        'flac24bit': 'hr',
      }.entries) {
        final info = raw[entry.value];
        if (info is Map) sizes[entry.key] = info['size'];
      }
    } else if (source == 'kugou') {
      fields['albumId'] = raw['album_id'] ?? raw['AlbumID'];
    }
    final qualities = <String, Map<String, dynamic>>{};
    for (final entry in sizes.entries) {
      final bytes = entry.value;
      if (bytes is! int || bytes <= 0 || bytes > 9007199254740991) continue;
      var value = bytes.toDouble();
      var unit = 0;
      const units = ['B', 'KiB', 'MiB', 'GiB', 'TiB'];
      while (value >= 1024 && unit < units.length - 1) {
        value /= 1024;
        unit++;
      }
      qualities[entry.key] = {
        'size': '${value.toStringAsFixed(2)} ${units[unit]}',
        'bytes': bytes,
      };
    }
    fields['qualities'] = qualities;
    return LxMusicMetadata.fromJson(raw['lxMetadata'])
        .fillMissing(LxMusicMetadata.fromJson(fields));
  }

  factory LxMusicMetadata.fromJson(dynamic raw) {
    if (raw is! Map) return const LxMusicMetadata();
    String? id(String key) {
      final value = raw[key];
      if (value is! String && value is! int) return null;
      final text = value.toString().trim();
      return text.isEmpty || text.length > 512 ? null : text;
    }

    final qualities = <String, Map<String, dynamic>>{};
    final source = raw['qualities'];
    if (source is Map) {
      for (final quality in qualityOrder) {
        final info = source[quality];
        if (info is! Map) continue;
        final size = info['size'];
        final bytes = info['bytes'];
        qualities[quality] = Map.unmodifiable({
          if (size is String && size.length <= 64) 'size': size,
          if (bytes is int && bytes > 0 && bytes <= 9007199254740991)
            'bytes': bytes,
        });
      }
    }
    final img = raw['img'];
    return LxMusicMetadata(
      songId: id('songId'),
      strMediaMid: id('strMediaMid'),
      albumId: id('albumId'),
      albumMid: id('albumMid'),
      img: img is String && img.length <= 8192 ? img : '',
      qualities: Map.unmodifiable(qualities),
    );
  }

  Map<String, dynamic> toJson() => {
    if (songId != null) 'songId': songId,
    if (strMediaMid != null) 'strMediaMid': strMediaMid,
    if (albumId != null) 'albumId': albumId,
    if (albumMid != null) 'albumMid': albumMid,
    if (img.isNotEmpty) 'img': img,
    if (qualities.isNotEmpty)
      'qualities': {
        for (final key in qualityOrder)
          if (qualities.containsKey(key)) key: qualities[key],
      },
  };

  bool get isEmpty => toJson().isEmpty;

  /// Known fields win; an incomplete response must not erase known evidence.
  LxMusicMetadata fillMissing(LxMusicMetadata other) =>
      LxMusicMetadata.fromJson({
        ...other.toJson(),
        ...toJson(),
        if (other.qualities.isNotEmpty || qualities.isNotEmpty)
          'qualities': {...other.qualities, ...qualities},
      });

  LxMusicMetadata withImage(String image) => image.isEmpty || img == image
      ? this
      : LxMusicMetadata.fromJson({...toJson(), 'img': image});

  String get fingerprint => jsonEncode(toJson());
}
