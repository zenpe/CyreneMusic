import '../models/track.dart';
import '../utils/format_utils.dart';
import 'cache_service.dart';
import 'lyric/lyric_cache_service.dart';
import 'lyric/lyric_service.dart';

class MediaCacheStats {
  final CacheStats audio;
  final LyricCacheStats lyric;

  const MediaCacheStats({
    required this.audio,
    required this.lyric,
  });

  int get totalSize => audio.totalSize + lyric.totalSize;
  int get totalFiles => audio.totalFiles + lyric.totalFiles;

  String get formattedSize => formatFileSize(totalSize);
}

class MediaCacheService {
  static final MediaCacheService _instance = MediaCacheService._internal();
  factory MediaCacheService() => _instance;

  MediaCacheService._internal();

  Future<MediaCacheStats> getCombinedCacheStats() async {
    final audioStats = await CacheService().getCacheStats();
    final lyricStats = await LyricCacheService().getCacheStats();
    return MediaCacheStats(audio: audioStats, lyric: lyricStats);
  }

  Future<void> clearAllCaches() async {
    await CacheService().clearAllCache();
    await LyricService().clearCachedLyrics();
  }

  Future<void> deleteTrackCaches(Track track, {String? quality}) async {
    await CacheService().deleteCache(track, quality: quality);
    if (quality == null) {
      await LyricService().evictTrackCache(track);
    }
  }
}
