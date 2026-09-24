import '../../models/track.dart';
import '../../models/audio_source_config.dart';
import '../audio_source_service.dart';

/// Describes one playback resolver without exposing its implementation.
class PlaybackResolverDescriptor {
  final String id;
  final String name;
  final AudioSourceType type;
  final Set<MusicSource> supportedPlatforms;
  final String fingerprint;

  const PlaybackResolverDescriptor({
    required this.id,
    required this.name,
    required this.type,
    required this.supportedPlatforms,
    required this.fingerprint,
  });

  bool supports(MusicSource platform) => supportedPlatforms.contains(platform);
}

/// Registry for playback capabilities. Search providers are intentionally not
/// registered here; they have a separate catalog.
class PlaybackResolverRegistry {
  static final PlaybackResolverRegistry _instance =
      PlaybackResolverRegistry._internal();

  factory PlaybackResolverRegistry() => _instance;

  PlaybackResolverRegistry._internal();

  List<PlaybackResolverDescriptor> get resolvers {
    final service = AudioSourceService();
    return service.sources
        .map((config) => _fromConfig(config, service: service))
        .toList(growable: false);
  }

  PlaybackResolverDescriptor? get activeResolver {
    final service = AudioSourceService();
    final source = service.activeSource;
    if (source == null) return null;
    return _fromConfig(source, service: service);
  }

  List<PlaybackResolverDescriptor> candidatesFor(MusicSource platform) {
    final active = activeResolver;
    final all = <PlaybackResolverDescriptor>[];
    if (active != null && active.supports(platform)) all.add(active);
    for (final resolver in resolvers) {
      if (active != null && resolver.id == active.id) continue;
      if (resolver.supports(platform)) all.add(resolver);
    }
    return all;
  }

  String? fingerprintFor(MusicSource platform) {
    final active = activeResolver;
    // Fingerprint the active resolver even when it does not support the
    // platform. A null fingerprint would make CacheService fall back to
    // unqualified/legacy entries created by another resolver.
    return active?.fingerprint;
  }

  PlaybackResolverDescriptor _fromConfig(
    AudioSourceConfig config, {
    required AudioSourceService service,
  }) {
    final platforms = config.supportedPlatforms.isNotEmpty
        ? config.supportedPlatforms
        : _defaultPlatformsFor(
            config.type,
            isActive: service.activeSource?.id == config.id,
            service: service,
          );
    final fingerprint = [
      config.id,
      config.type.name,
      config.version,
      config.url,
      config.scriptSource,
      config.scriptContent,
      platforms.join(','),
    ].join('\u0000');
    return PlaybackResolverDescriptor(
      id: config.id,
      name: config.name,
      type: config.type,
      supportedPlatforms: platforms
          .map(_platformFromKey)
          .whereType<MusicSource>()
          .toSet(),
      fingerprint: fingerprint,
    );
  }

  List<String> _defaultPlatformsFor(
    AudioSourceType type, {
    required bool isActive,
    required AudioSourceService service,
  }) {
    switch (type) {
      case AudioSourceType.lxmusic:
        return isActive ? service.currentSupportedPlaybackPlatforms : const [];
      case AudioSourceType.navidrome:
        return const ['navidrome'];
    }
  }

  MusicSource? _platformFromKey(String key) {
    for (final platform in MusicSource.values) {
      if (platform.name == key) return platform;
    }
    return null;
  }
}
