import '../models/track.dart';

/// Search providers are independent from the active playback resolver.
/// The current backend exposes a fixed set of platform search endpoints.
class SearchProviderCatalog {
  static const List<MusicSource> defaultPlatforms = <MusicSource>[
    MusicSource.netease,
    MusicSource.qq,
    MusicSource.kugou,
    MusicSource.kuwo,
  ];

  const SearchProviderCatalog();

  List<String> get platformKeys => defaultPlatforms
      .map((platform) => platform.name)
      .toList(growable: false);

  bool supports(MusicSource platform) => defaultPlatforms.contains(platform);
}
