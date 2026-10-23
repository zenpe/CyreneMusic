import '../models/track.dart';

/// Search providers are independent from the active playback resolver.
/// Only platforms with an operational backend search are exposed.
class SearchProviderCatalog {
  static const List<MusicSource> defaultPlatforms = <MusicSource>[
    MusicSource.netease,
    MusicSource.qq,
    MusicSource.kugou,
    // Kuwo's backend currently returns a placeholder empty list.
  ];

  const SearchProviderCatalog();

  List<String> get platformKeys => defaultPlatforms
      .map((platform) => platform.name)
      .toList(growable: false);

  bool supports(MusicSource platform) => defaultPlatforms.contains(platform);
}
