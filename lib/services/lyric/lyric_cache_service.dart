import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import '../../utils/format_utils.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';

import '../../models/track.dart';
import '../cache_service.dart';
import '../developer_mode_service.dart';

enum LyricCacheState {
  ready,
  empty,
  failed,
}

class LyricCacheEntry {
  final String trackKey;
  final String quality;
  final String source;
  final String title;
  final String artist;
  final String lyric;
  final String tlyric;
  final String yrc;
  final String ytlrc;
  final String qrc;
  final String qrcTrans;
  final bool hasContent;
  final String completeness;
  final LyricCacheState state;
  final DateTime fetchedAt;
  final DateTime? expiresAt;
  final int failureCount;
  final DateTime? retryAfter;
  final String? error;

  const LyricCacheEntry({
    required this.trackKey,
    required this.quality,
    required this.source,
    required this.title,
    required this.artist,
    required this.lyric,
    required this.tlyric,
    required this.yrc,
    required this.ytlrc,
    required this.qrc,
    required this.qrcTrans,
    required this.hasContent,
    required this.completeness,
    required this.state,
    required this.fetchedAt,
    this.expiresAt,
    this.failureCount = 0,
    this.retryAfter,
    this.error,
  });

  factory LyricCacheEntry.fromJson(Map<String, dynamic> json) {
    final entry = LyricCacheEntry.tryFromJson(json);
    if (entry == null) {
      throw const FormatException('Invalid lyric cache entry');
    }
    return entry;
  }

  static LyricCacheEntry? tryFromJson(Map<String, dynamic> json) {
    final trackKey = (json['trackKey'] as String?)?.trim();
    if (trackKey == null || trackKey.isEmpty) {
      return null;
    }

    return LyricCacheEntry(
      trackKey: trackKey,
      quality: json['quality'] as String? ?? 'standard',
      source: json['source'] as String? ?? '',
      title: json['title'] as String? ?? '',
      artist: json['artist'] as String? ?? '',
      lyric: json['lyric'] as String? ?? '',
      tlyric: json['tlyric'] as String? ?? '',
      yrc: json['yrc'] as String? ?? '',
      ytlrc: json['ytlrc'] as String? ?? '',
      qrc: json['qrc'] as String? ?? '',
      qrcTrans: json['qrcTrans'] as String? ?? '',
      hasContent: json['hasContent'] as bool? ?? false,
      completeness: json['completeness'] as String? ?? 'empty',
      state: _stateFromName(json['state'] as String?),
      fetchedAt: DateTime.tryParse(json['fetchedAt'] as String? ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0),
      expiresAt: json['expiresAt'] == null
          ? null
          : DateTime.tryParse(json['expiresAt'] as String),
      failureCount: json['failureCount'] as int? ?? 0,
      retryAfter: json['retryAfter'] == null
          ? null
          : DateTime.tryParse(json['retryAfter'] as String),
      error: json['error'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'trackKey': trackKey,
      'quality': quality,
      'source': source,
      'title': title,
      'artist': artist,
      'lyric': lyric,
      'tlyric': tlyric,
      'yrc': yrc,
      'ytlrc': ytlrc,
      'qrc': qrc,
      'qrcTrans': qrcTrans,
      'hasContent': hasContent,
      'completeness': completeness,
      'state': state.name,
      'fetchedAt': fetchedAt.toIso8601String(),
      'expiresAt': expiresAt?.toIso8601String(),
      'failureCount': failureCount,
      'retryAfter': retryAfter?.toIso8601String(),
      'error': error,
    };
  }

  bool get isExpired {
    final value = expiresAt;
    if (value == null) return false;
    return DateTime.now().isAfter(value);
  }

  bool get isFailureBackoffActive {
    final value = retryAfter;
    if (value == null) return false;
    return DateTime.now().isBefore(value);
  }

  static LyricCacheState _stateFromName(String? name) {
    switch (name) {
      case 'ready':
        return LyricCacheState.ready;
      case 'empty':
        return LyricCacheState.empty;
      case 'failed':
        return LyricCacheState.failed;
      default:
        return LyricCacheState.empty;
    }
  }
}

class LyricCacheStats {
  final int totalFiles;
  final int totalSize;
  final int readyCount;
  final int emptyCount;
  final int failedCount;

  const LyricCacheStats({
    required this.totalFiles,
    required this.totalSize,
    required this.readyCount,
    required this.emptyCount,
    required this.failedCount,
  });

  String get formattedSize => formatFileSize(totalSize);
}

class LyricCacheService extends ChangeNotifier {
  static final LyricCacheService _instance = LyricCacheService._internal();
  factory LyricCacheService() => _instance;
  LyricCacheService._internal();

  Directory? _cacheDir;
  bool _isInitialized = false;
  bool _indexDirty = false;
  final Map<String, Map<String, dynamic>> _index = <String, Map<String, dynamic>>{};
  final Map<String, Set<String>> _trackCacheKeys =
      <String, Set<String>>{};

  bool get isInitialized => _isInitialized;
  String? get currentCacheDir => _cacheDir?.path;

  /// 如果 index 有未持久化的变更，立即写盘。
  Future<void> flushIndex() async {
    if (_indexDirty) {
      await _saveIndex();
    }
  }

  void _log(String message, {bool toDeveloperPanel = false}) {
    if (kDebugMode) {
      debugPrint(message);
    }
    if (toDeveloperPanel) {
      DeveloperModeService().addLog(message);
    }
  }

  Future<void> initialize() async {
    if (_isInitialized) {
      return;
    }

    try {
      final musicCacheDir = CacheService().currentCacheDir;
      if (musicCacheDir != null && musicCacheDir.isNotEmpty) {
        final parentDir = path.dirname(musicCacheDir);
        _cacheDir = Directory(path.join(parentDir, 'lyrics_cache'));
      } else if (Platform.isWindows) {
        final executablePath = Platform.resolvedExecutable;
        final executableDir = path.dirname(executablePath);
        _cacheDir = Directory(path.join(executableDir, 'lyrics_cache'));
      } else {
        final appDir = await getApplicationDocumentsDirectory();
        _cacheDir = Directory(path.join(appDir.path, 'lyrics_cache'));
      }

      if (!await _cacheDir!.exists()) {
        await _cacheDir!.create(recursive: true);
      }

      await _loadIndex();
      await _migrateLegacyTrackScopedKeys();
      _isInitialized = true;
      unawaited(_cleanupExpiredEntries());
      _log(
        '📝 [LyricCacheService] 歌词缓存已初始化: ${_cacheDir!.path}',
        toDeveloperPanel: true,
      );
    } catch (e) {
      _isInitialized = false;
      _log('❌ [LyricCacheService] 初始化失败: $e', toDeveloperPanel: true);
    }
  }

  Future<LyricCacheEntry?> readEntry(String cacheKey) async {
    await initialize();
    if (!_isInitialized || _cacheDir == null) return null;

    final file = File(_entryPath(cacheKey));
    if (!await file.exists()) {
      _removeIndexEntry(cacheKey);
      return null;
    }

    try {
      final raw = await file.readAsString();
      final json = jsonDecode(raw) as Map<String, dynamic>;
      final entry = LyricCacheEntry.tryFromJson(json);
      if (entry == null) {
        throw const FormatException('Missing required lyric cache fields');
      }
      _replaceIndexEntry(
        cacheKey,
        _buildIndexValue(entry, fileSize: raw.length),
      );
      return entry;
    } catch (e) {
      _log(
        '❌ [LyricCacheService] 读取歌词缓存失败: $cacheKey, $e',
        toDeveloperPanel: true,
      );
      try {
        if (await file.exists()) {
          await file.delete();
        }
      } catch (_) {}
      _removeIndexEntry(cacheKey);
      await _saveIndex();
      return null;
    }
  }

  Future<void> writeEntry(String cacheKey, LyricCacheEntry entry) async {
    await initialize();
    if (!_isInitialized || _cacheDir == null) return;

    final file = File(_entryPath(cacheKey));
    final content = jsonEncode(entry.toJson());
    await file.writeAsString(content, flush: true);
    _replaceIndexEntry(
      cacheKey,
      _buildIndexValue(entry, fileSize: content.length),
    );
    await _saveIndex();
    notifyListeners();
  }

  Future<void> deleteEntry(String cacheKey) async {
    await initialize();
    if (!_isInitialized || _cacheDir == null) return;

    final file = File(_entryPath(cacheKey));
    try {
      if (await file.exists()) {
        await file.delete();
      }
    } catch (_) {}
    _removeIndexEntry(cacheKey);
    await _saveIndex();
    notifyListeners();
  }

  Future<LyricCacheStats> getCacheStats() async {
    await initialize();
    if (!_isInitialized || _cacheDir == null) {
      return const LyricCacheStats(
        totalFiles: 0,
        totalSize: 0,
        readyCount: 0,
        emptyCount: 0,
        failedCount: 0,
      );
    }

    int totalFiles = 0;
    int totalSize = 0;
    int readyCount = 0;
    int emptyCount = 0;
    int failedCount = 0;

    for (final entry in _index.entries) {
      if (entry.key.isEmpty) continue;
      final stateName = entry.value['state'] as String? ?? '';
      final size = entry.value['fileSize'] as int? ?? 0;

      totalFiles++;
      totalSize += size;

      switch (stateName) {
        case 'ready':
          readyCount++;
          break;
        case 'failed':
          failedCount++;
          break;
        case 'empty':
        default:
          emptyCount++;
          break;
      }
    }

    return LyricCacheStats(
      totalFiles: totalFiles,
      totalSize: totalSize,
      readyCount: readyCount,
      emptyCount: emptyCount,
      failedCount: failedCount,
    );
  }

  Future<void> clearAllCache() async {
    await initialize();
    if (!_isInitialized || _cacheDir == null) return;

    try {
      _log('🗑️ [LyricCacheService] 清除所有歌词缓存...', toDeveloperPanel: true);
      final files = await _cacheDir!.list().toList();
      for (final entity in files) {
        if (entity is File) {
          try {
            await entity.delete();
          } catch (_) {}
        }
      }
      _index.clear();
      _trackCacheKeys.clear();
      await _saveIndex();
      notifyListeners();
      _log('✅ [LyricCacheService] 歌词缓存已清除', toDeveloperPanel: true);
    } catch (e) {
      _log('❌ [LyricCacheService] 清除歌词缓存失败: $e', toDeveloperPanel: true);
    }
  }

  Future<void> deleteTrackCache(Track track, {String? quality}) async {
    await initialize();
    if (!_isInitialized || _cacheDir == null) return;

    final targetTrackKey = '${track.source.name}_${track.id}';
    final keysToRemove = (_trackCacheKeys[targetTrackKey] ?? const <String>{})
        .toList(growable: false);

    if (keysToRemove.isEmpty) return;

    for (final cacheKey in keysToRemove) {
      final file = File(_entryPath(cacheKey));
      try {
        if (await file.exists()) {
          await file.delete();
        }
      } catch (_) {}
      _removeIndexEntry(cacheKey);
    }

    await _saveIndex();
    notifyListeners();
    _log(
      '🗑️ [LyricCacheService] 删除歌词缓存: ${track.name} removed=${keysToRemove.length} requestedQuality=${quality ?? 'shared'}',
      toDeveloperPanel: true,
    );
  }

  String _entryPath(String cacheKey) {
    return path.join(_cacheDir!.path, '$cacheKey.json');
  }

  String _indexPath() {
    return path.join(_cacheDir!.path, 'lyric_index.json');
  }

  Map<String, dynamic> _buildIndexValue(LyricCacheEntry entry, {int fileSize = 0}) {
    return {
      'trackKey': entry.trackKey,
      'quality': entry.quality,
      'source': entry.source,
      'title': entry.title,
      'artist': entry.artist,
      'state': entry.state.name,
      'hasContent': entry.hasContent,
      'completeness': entry.completeness,
      'fetchedAt': entry.fetchedAt.toIso8601String(),
      'expiresAt': entry.expiresAt?.toIso8601String(),
      'failureCount': entry.failureCount,
      'retryAfter': entry.retryAfter?.toIso8601String(),
      'error': entry.error,
      'fileSize': fileSize,
    };
  }

  Future<void> _loadIndex() async {
    if (_cacheDir == null) return;
    final file = File(_indexPath());
    if (!await file.exists()) {
      _index.clear();
      _trackCacheKeys.clear();
      return;
    }
    try {
      final raw = await file.readAsString();
      final json = jsonDecode(raw) as Map<String, dynamic>;
      _index
        ..clear()
        ..addAll(
          json.map(
            (key, value) => MapEntry(
              key,
              (value as Map).cast<String, dynamic>(),
            ),
          ),
        );
      _rebuildTrackCacheKeys();
    } catch (e) {
      _index.clear();
      _trackCacheKeys.clear();
      _log('❌ [LyricCacheService] 加载歌词索引失败: $e', toDeveloperPanel: true);
    }
  }

  Future<void> _saveIndex() async {
    if (_cacheDir == null) return;
    _indexDirty = false;
    final file = File(_indexPath());
    try {
      await file.writeAsString(jsonEncode(_index), flush: true);
    } catch (e) {
      _log('❌ [LyricCacheService] 保存歌词索引失败: $e', toDeveloperPanel: true);
    }
  }

  Future<void> _migrateLegacyTrackScopedKeys() async {
    if (_cacheDir == null || _index.isEmpty) return;

    var migratedCount = 0;
    var removedCount = 0;
    final entries = _index.entries.toList(growable: false);

    for (final entry in entries) {
      final cacheKey = entry.key;
      final indexValue = entry.value;
      final trackKey = indexValue['trackKey'] as String? ?? '';
      if (trackKey.isEmpty || cacheKey == trackKey) {
        continue;
      }
      if (!cacheKey.startsWith('${trackKey}_')) {
        continue;
      }

      final legacyFile = File(_entryPath(cacheKey));
      final sharedFile = File(_entryPath(trackKey));
      final sharedExistsInIndex = _index.containsKey(trackKey);
      final sharedExistsOnDisk = await sharedFile.exists();

      if (sharedExistsInIndex || sharedExistsOnDisk) {
        try {
          if (await legacyFile.exists()) {
            await legacyFile.delete();
          }
        } catch (_) {}
        _index.remove(cacheKey);
        removedCount++;
        continue;
      }

      try {
        if (await legacyFile.exists()) {
          await legacyFile.rename(sharedFile.path);
        }
      } catch (_) {
        try {
          if (await legacyFile.exists()) {
            await legacyFile.copy(sharedFile.path);
            await legacyFile.delete();
          }
        } catch (_) {
          continue;
        }
      }

      _index.remove(cacheKey);
      _index[trackKey] = Map<String, dynamic>.from(indexValue);
      migratedCount++;
    }

    if (migratedCount == 0 && removedCount == 0) {
      return;
    }

    _rebuildTrackCacheKeys();
    await _saveIndex();
    _log(
      '🧹 [LyricCacheService] 旧歌词缓存键迁移完成: migrated=$migratedCount removed=$removedCount',
      toDeveloperPanel: true,
    );
  }

  Future<void> _cleanupExpiredEntries() async {
    if (_cacheDir == null || _index.isEmpty) return;

    final entries = _index.entries.toList(growable: false);
    final expiredKeys = <String>[];
    final invalidKeys = <String>[];

    for (final entry in entries) {
      final cacheEntry = LyricCacheEntry.tryFromJson(entry.value);
      if (cacheEntry == null) {
        invalidKeys.add(entry.key);
        continue;
      }
      if (cacheEntry.isExpired) {
        expiredKeys.add(entry.key);
      }
    }

    if (expiredKeys.isEmpty && invalidKeys.isEmpty) {
      return;
    }

    for (final cacheKey in <String>{...invalidKeys, ...expiredKeys}) {
      final file = File(_entryPath(cacheKey));
      try {
        if (await file.exists()) {
          await file.delete();
        }
      } catch (_) {}
      _removeIndexEntry(cacheKey);
    }

    await _saveIndex();
    notifyListeners();
    _log(
      '🧹 [LyricCacheService] 已清理歌词缓存: expired=${expiredKeys.length} invalid=${invalidKeys.length}',
      toDeveloperPanel: true,
    );
  }

  void _rebuildTrackCacheKeys() {
    _trackCacheKeys
      ..clear()
      ..addEntries(_buildTrackCacheKeyEntries());
  }

  Iterable<MapEntry<String, Set<String>>> _buildTrackCacheKeyEntries() sync* {
    final grouped = <String, Set<String>>{};
    for (final entry in _index.entries) {
      final trackKey = _trackKeyFromIndexValue(entry.value);
      if (trackKey == null || trackKey.isEmpty) continue;
      grouped.putIfAbsent(trackKey, () => <String>{}).add(entry.key);
    }
    yield* grouped.entries;
  }

  String? _trackKeyFromIndexValue(Map<String, dynamic>? indexValue) {
    final trackKey = indexValue?['trackKey'] as String?;
    if (trackKey == null || trackKey.isEmpty) {
      return null;
    }
    return trackKey;
  }

  void _replaceIndexEntry(String cacheKey, Map<String, dynamic> nextValue) {
    final previousValue = _index[cacheKey];
    if (previousValue != null && mapEquals(previousValue, nextValue)) {
      return;
    }

    final previousTrackKey = _trackKeyFromIndexValue(previousValue);
    if (previousTrackKey != null) {
      _unlinkTrackCacheKey(previousTrackKey, cacheKey);
    }

    _index[cacheKey] = nextValue;
    final nextTrackKey = _trackKeyFromIndexValue(nextValue);
    if (nextTrackKey != null) {
      _trackCacheKeys.putIfAbsent(nextTrackKey, () => <String>{}).add(cacheKey);
    }
    _indexDirty = true;
  }

  void _removeIndexEntry(String cacheKey) {
    final removed = _index.remove(cacheKey);
    if (removed == null) {
      return;
    }
    final trackKey = _trackKeyFromIndexValue(removed);
    if (trackKey != null) {
      _unlinkTrackCacheKey(trackKey, cacheKey);
    }
    _indexDirty = true;
  }

  void _unlinkTrackCacheKey(String trackKey, String cacheKey) {
    final keys = _trackCacheKeys[trackKey];
    if (keys == null) {
      return;
    }
    keys.remove(cacheKey);
    if (keys.isEmpty) {
      _trackCacheKeys.remove(trackKey);
    }
  }
}
