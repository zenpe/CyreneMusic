import 'dart:async';
import 'dart:collection';

import '../../models/song_detail.dart';
import '../../models/track.dart';
import '../cache_service.dart';
import 'lyric_cache_service.dart';
import 'lyric_snapshot.dart';

typedef LyricRepositoryLogFn =
    void Function(String message, {bool toDeveloperPanel});

class LyricLookupResult {
  final LyricLoadState state;
  final SongDetail? song;
  final String source;
  final String category;
  final bool skipRemote;
  final String? error;

  const LyricLookupResult({
    required this.state,
    required this.song,
    required this.source,
    required this.category,
    required this.skipRemote,
    this.error,
  });
}

class LyricRepository {
  static final LyricRepository _instance = LyricRepository._internal();
  factory LyricRepository() => _instance;
  LyricRepository._internal();

  static const int _memoryCapacity = 64;
  static const Duration _readyTtl = Duration(days: 7);
  static const Duration _confirmedEmptyTtl = Duration(hours: 24);

  final LinkedHashMap<String, LyricCacheEntry> _memory =
      LinkedHashMap<String, LyricCacheEntry>();

  Future<LyricLookupResult?> lookup({
    required Track track,
    required String quality,
    required SongDetail? currentSong,
    required LyricRepositoryLogFn log,
  }) async {
    final cacheKey = _cacheKey(track);
    final legacyCacheKey = _legacyCacheKey(track, quality);

    var memoryHitKey = cacheKey;
    var memoryEntry = _takeMemory(cacheKey);
    if (memoryEntry == null && legacyCacheKey != cacheKey) {
      memoryEntry = _takeMemory(legacyCacheKey);
      memoryHitKey = legacyCacheKey;
    }
    final memoryHit = _toLookupResult(
      track,
      quality,
      currentSong,
      memoryEntry,
      source: 'memory',
    );
    if (memoryHit != null) {
      if (memoryEntry != null && memoryHitKey != cacheKey) {
        _remember(cacheKey, memoryEntry);
        _memory.remove(memoryHitKey);
        log(
          '[LyricService] legacy memory key hit: $memoryHitKey -> $cacheKey',
          toDeveloperPanel: true,
        );
      }
      log('[LyricService] memory hit: $cacheKey', toDeveloperPanel: true);
      return memoryHit;
    }
    if (memoryEntry != null) {
      _memory.remove(memoryHitKey);
    }

    var diskHitKey = cacheKey;
    var diskEntry = await LyricCacheService().readEntry(cacheKey);
    if (diskEntry == null && legacyCacheKey != cacheKey) {
      diskEntry = await LyricCacheService().readEntry(legacyCacheKey);
      diskHitKey = legacyCacheKey;
    }
    final diskHit = _toLookupResult(
      track,
      quality,
      currentSong,
      diskEntry,
      source: 'disk',
    );
    if (diskHit != null) {
      _remember(cacheKey, diskEntry!);
      if (diskHitKey != cacheKey) {
        unawaited(_migrateLegacyEntryKey(cacheKey, diskHitKey, diskEntry, log));
      }
      log('[LyricService] disk hit: $cacheKey', toDeveloperPanel: true);
      return diskHit;
    }
    if (diskEntry != null) {
      try {
        await LyricCacheService().deleteEntry(diskHitKey);
      } catch (_) {}
    }

    return null;
  }

  Future<void> storeReady({
    required Track track,
    required String quality,
    required SongDetail song,
    required LyricRepositoryLogFn log,
  }) async {
    final cacheKey = _cacheKey(track);
    final hasPayload = _hasPayload(song);
    final entry = LyricCacheEntry(
      trackKey: _trackKey(track),
      quality: quality,
      source: track.source.name,
      title: song.name.isNotEmpty ? song.name : track.name,
      artist: song.arName.isNotEmpty ? song.arName : track.artists,
      lyric: song.lyric,
      tlyric: song.tlyric,
      yrc: song.yrc,
      ytlrc: song.ytlrc,
      qrc: song.qrc,
      qrcTrans: song.qrcTrans,
      hasContent: hasPayload,
      completeness: _completenessFromSong(song),
      state: LyricCacheState.ready,
      authoritativeEmpty: false,
      fetchedAt: DateTime.now(),
      expiresAt: DateTime.now().add(_readyTtl),
    );
    await _persistEntry(track, quality, cacheKey, entry, log);
  }

  Future<void> storeConfirmedEmpty({
    required Track track,
    required String quality,
    required SongDetail? currentSong,
    required LyricRepositoryLogFn log,
  }) async {
    final cacheKey = _cacheKey(track);
    final entry = LyricCacheEntry(
      trackKey: _trackKey(track),
      quality: quality,
      source: track.source.name,
      title: currentSong?.name.isNotEmpty == true
          ? currentSong!.name
          : track.name,
      artist: currentSong?.arName.isNotEmpty == true
          ? currentSong!.arName
          : track.artists,
      lyric: '',
      tlyric: '',
      yrc: '',
      ytlrc: '',
      qrc: '',
      qrcTrans: '',
      hasContent: false,
      completeness: 'empty',
      state: LyricCacheState.empty,
      authoritativeEmpty: true,
      fetchedAt: DateTime.now(),
      expiresAt: DateTime.now().add(_confirmedEmptyTtl),
    );
    await _persistEntry(track, quality, cacheKey, entry, log);
  }

  String _cacheKey(Track track) => _trackKey(track);

  String _legacyCacheKey(Track track, String quality) =>
      '${_trackKey(track)}_$quality';

  String _trackKey(Track track) => '${track.source.name}_${track.id}';

  void clearMemory() {
    _memory.clear();
  }

  void evictTrack(Track track, {String? quality}) {
    final trackKey = _trackKey(track);
    final keysToRemove = quality == null
        ? _memory.keys
              .where((key) => key == trackKey || key.startsWith('${trackKey}_'))
              .toList(growable: false)
        : <String>[
            _legacyCacheKey(track, CacheService.normalizeQualityValue(quality)),
          ];
    for (final key in keysToRemove) {
      _memory.remove(key);
    }
  }

  LyricLookupResult? _toLookupResult(
    Track track,
    String quality,
    SongDetail? currentSong,
    LyricCacheEntry? entry, {
    required String source,
  }) {
    if (entry == null) return null;
    switch (entry.state) {
      case LyricCacheState.ready:
        if (!entry.hasContent || entry.isExpired) return null;
        return LyricLookupResult(
          state: LyricLoadState.ready,
          song: _buildSongFromEntry(track, quality, currentSong, entry),
          source: source,
          category: source == 'memory' ? 'memory_hit' : 'disk_hit',
          skipRemote: true,
        );
      case LyricCacheState.empty:
        if (!entry.authoritativeEmpty || entry.isExpired) return null;
        if (currentSong != null && _hasPayload(currentSong)) {
          return LyricLookupResult(
            state: LyricLoadState.ready,
            song: currentSong,
            source: source,
            category: source == 'memory' ? 'memory_hit' : 'disk_hit',
            skipRemote: true,
          );
        }
        return LyricLookupResult(
          state: LyricLoadState.empty,
          song: currentSong,
          source: source,
          category: 'empty_cache_hit',
          skipRemote: true,
        );
      case LyricCacheState.failed:
        return null;
    }
  }

  SongDetail _buildSongFromEntry(
    Track track,
    String quality,
    SongDetail? currentSong,
    LyricCacheEntry entry,
  ) {
    return SongDetail(
      id: currentSong?.id ?? track.id,
      name: currentSong?.name.isNotEmpty == true
          ? currentSong!.name
          : (entry.title.isNotEmpty ? entry.title : track.name),
      pic: currentSong?.pic.isNotEmpty == true
          ? currentSong!.pic
          : track.picUrl,
      arName: currentSong?.arName.isNotEmpty == true
          ? currentSong!.arName
          : (entry.artist.isNotEmpty ? entry.artist : track.artists),
      alName: currentSong?.alName ?? track.album,
      level: currentSong?.level.isNotEmpty == true
          ? currentSong!.level
          : quality,
      size: currentSong?.size ?? '0',
      url: currentSong?.url ?? '',
      lyric: entry.lyric,
      tlyric: entry.tlyric,
      yrc: entry.yrc,
      ytlrc: entry.ytlrc,
      qrc: entry.qrc,
      qrcTrans: entry.qrcTrans,
      source: currentSong?.source ?? track.source,
    );
  }

  bool _hasPayload(SongDetail song) {
    return song.lyric.isNotEmpty ||
        song.tlyric.isNotEmpty ||
        song.yrc.isNotEmpty ||
        song.ytlrc.isNotEmpty ||
        song.qrc.isNotEmpty ||
        song.qrcTrans.isNotEmpty;
  }

  String _completenessFromSong(SongDetail song) {
    return _completenessFromPayload(
      lyric: song.lyric,
      tlyric: song.tlyric,
      yrc: song.yrc,
      ytlrc: song.ytlrc,
      qrc: song.qrc,
      qrcTrans: song.qrcTrans,
    );
  }

  String _completenessFromPayload({
    required String lyric,
    required String tlyric,
    required String yrc,
    required String ytlrc,
    required String qrc,
    required String qrcTrans,
  }) {
    final hasTimed = yrc.isNotEmpty || qrc.isNotEmpty;
    final hasTimedTranslation = ytlrc.isNotEmpty || qrcTrans.isNotEmpty;
    final hasTranslation = tlyric.isNotEmpty || hasTimedTranslation;
    final hasPlain = lyric.isNotEmpty || hasTimed;
    if (hasTimed && hasTimedTranslation) {
      return 'timed-translated';
    }
    if (hasTimed) {
      return 'timed';
    }
    if (hasPlain && hasTranslation) {
      return 'translated';
    }
    if (hasPlain) {
      return 'plain';
    }
    return 'empty';
  }

  LyricCacheEntry? _takeMemory(String cacheKey) {
    final entry = _memory.remove(cacheKey);
    if (entry == null) return null;
    _memory[cacheKey] = entry;
    return entry;
  }

  void _remember(String cacheKey, LyricCacheEntry entry) {
    _memory.remove(cacheKey);
    _memory[cacheKey] = entry;
    while (_memory.length > _memoryCapacity) {
      _memory.remove(_memory.keys.first);
    }
  }

  Future<void> _writeEntry(
    String cacheKey,
    LyricCacheEntry entry,
    LyricRepositoryLogFn log,
  ) async {
    try {
      await LyricCacheService().writeEntry(cacheKey, entry);
      log(
        '[LyricService] cache write success: $cacheKey',
        toDeveloperPanel: true,
      );
    } catch (e) {
      log(
        '[LyricService] cache write failed: $cacheKey, $e',
        toDeveloperPanel: true,
      );
    }
  }

  Future<void> _persistEntry(
    Track track,
    String quality,
    String cacheKey,
    LyricCacheEntry entry,
    LyricRepositoryLogFn log,
  ) async {
    _remember(cacheKey, entry);
    await _writeEntry(cacheKey, entry, log);
    final legacyCacheKey = _legacyCacheKey(track, quality);
    if (legacyCacheKey == cacheKey) {
      return;
    }
    _memory.remove(legacyCacheKey);
    try {
      await LyricCacheService().deleteEntry(legacyCacheKey);
      log(
        '[LyricService] legacy cache key cleaned: $legacyCacheKey',
        toDeveloperPanel: true,
      );
    } catch (_) {}
  }

  Future<void> _migrateLegacyEntryKey(
    String cacheKey,
    String legacyCacheKey,
    LyricCacheEntry entry,
    LyricRepositoryLogFn log,
  ) async {
    try {
      await LyricCacheService().writeEntry(cacheKey, entry);
      await LyricCacheService().deleteEntry(legacyCacheKey);
      log(
        '[LyricService] legacy cache key migrated: $legacyCacheKey -> $cacheKey',
        toDeveloperPanel: true,
      );
    } catch (e) {
      log(
        '[LyricService] legacy cache key migrate failed: $legacyCacheKey -> $cacheKey, $e',
        toDeveloperPanel: true,
      );
    }
  }
}
