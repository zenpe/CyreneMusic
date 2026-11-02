/// Official stable release metadata, independent of the music API.
class VersionInfo {
  static const repository = 'https://github.com/zenpe/CyreneMusic';
  static const latestReleasePage = '$repository/releases/latest';
  static const assets = {
    'windows-x64': 'cyrene_music-windows-x64.zip',
    'android-arm64': 'app-release.apk',
  };

  final String version;
  final String changelog;
  final Map<String, String> platformDownloads;
  String get tag => 'v$version';
  String get releasePage => '$repository/releases/tag/$tag';

  VersionInfo({
    required this.version,
    required this.changelog,
    Map<String, String> platformDownloads = const {},
  }) : platformDownloads = Map.unmodifiable(platformDownloads);

  static final _stable = RegExp(r'^(0|[1-9]\d*)\.(0|[1-9]\d*)\.(0|[1-9]\d*)$');
  static bool isStableVersion(String value) => _stable.hasMatch(value);

  /// Build metadata does not change release precedence.
  static int compare(String a, String b) {
    List<int> parts(String value) {
      final base = value.split('+').first;
      if (!isStableVersion(base)) {
        throw const FormatException('Invalid version');
      }
      return base.split('.').map(int.parse).toList();
    }

    final left = parts(a), right = parts(b);
    for (var i = 0; i < 3; i++) {
      final result = left[i].compareTo(right[i]);
      if (result != 0) return result;
    }
    return 0;
  }

  factory VersionInfo.fromRelease(Map<String, dynamic> json) {
    final tag = json['tag_name'];
    if (json['draft'] != false ||
        json['prerelease'] != false ||
        tag is! String ||
        !tag.startsWith('v') ||
        !isStableVersion(tag.substring(1))) {
      throw const FormatException('Not an official stable release');
    }
    final downloads = <String, String>{};
    final releaseAssets = json['assets'];
    if (releaseAssets is! List) throw const FormatException('Missing assets');
    for (final entry in releaseAssets) {
      if (entry is! Map ||
          entry['size'] is! num ||
          entry['size'] <= 0 ||
          entry['state'] != 'uploaded') {
        continue;
      }
      for (final asset in assets.entries) {
        final expected = '$repository/releases/download/$tag/${asset.value}';
        if (entry['name'] == asset.value &&
            entry['browser_download_url'] == expected) {
          downloads[asset.key] = expected;
        }
      }
    }
    return VersionInfo(
      version: tag.substring(1),
      changelog: json['body'] is String ? json['body'] as String : '',
      platformDownloads: downloads,
    );
  }

  Map<String, dynamic> toJson() => {
    'tag_name': tag,
    'draft': false,
    'prerelease': false,
    'body': changelog,
    'assets': platformDownloads.entries
        .map(
          (entry) => {
            'name': assets[entry.key],
            'browser_download_url': entry.value,
            'state': 'uploaded',
            'size': 1,
          },
        )
        .toList(),
  };

  String? platformDownloadUrl(String platformKey) =>
      platformDownloads[platformKey];
}
