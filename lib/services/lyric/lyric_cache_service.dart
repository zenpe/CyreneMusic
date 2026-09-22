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

enum LyricCacheState { ready, empty, failed }

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
  final bool authoritativeEmpty;
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
    this.authoritativeEmpty = false,
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
      authoritativeEmpty: json['authoritativeEmpty'] as bool? ?? false,
      fetchedAt:
          DateTime.tryParse(json['fetchedAt'] as String? ?? '') ??
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
      'authoritativeEmpty': authoritativeEmpty,
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

  static const Map<String, int> _completenessRank = <String, int>{
    'timed-translated': 4,
    'timed': 3,
    'translated': 2,
    'plain': 1,
    'empty': 0,
    'failed': 0,
  };

  @visibleForTesting
  static bool shouldDeleteTrackCacheKey({
    required String cacheKey,
    required String trackKey,
    required Map<String, dynamic>? indexValue,
    String? requestedQuality,
  }) {
    if (requestedQuality == null) {
      return true;
    }
    if (cacheKey == trackKey) {
      return false;
    }
    final entryQuality = CacheService.normalizeQualityValue(
      indexValue?['quality']?.toString(),
    );
    return entryQuality == requestedQuality;
  }

  @visibleForTesting
  static int compareEntriesForMigration({
    required LyricCacheEntry candidate,
    required bool candidateHasFile,
    required LyricCacheEntry incumbent,
    required bool incumbentHasFile,
  }) {
    if (candidateHasFile != incumbentHasFile) {
      return candidateHasFile ? 1 : -1;
    }

    final stateRank = _stateRank(candidate.state);
    final otherStateRank = _stateRank(incumbent.state);
    if (stateRank != otherStateRank) {
      return stateRank.compareTo(otherStateRank);
    }

    if (candidate.hasContent != incumbent.hasContent) {
      return candidate.hasContent ? 1 : -1;
    }

    final completenessRank = _completenessRank[candidate.completeness] ?? 0;
    final otherCompletenessRank =
        _completenessRank[incumbent.completeness] ?? 0;
    if (completenessRank != otherCompletenessRank) {
      return completenessRank.compareTo(otherCompletenessRank);
    }

    final fetchedAtCompare = candidate.fetchedAt.compareTo(incumbent.fetchedAt);
    if (fetchedAtCompare != 0) {
      return fetchedAtCompare;
    }

    return incumbent.failureCount.compareTo(candidate.failureCount);
  }

  static int _stateRank(LyricCacheState state) {
    switch (state) {
      case LyricCacheState.ready:
        return 3;
      case LyricCacheState.empty:
        return 2;
      case LyricCacheState.failed:
        return 1;
    }
  }

  Directory? _cacheDir;
  bool _isInitialized = false;
  bool _indexDirty = false;
  final Map<String, Map<String, dynamic>> _index =
      <String, Map<String, dynamic>>{};
  final Map<String, Set<String>> _trackCacheKeys = <String, Set<String>>{};

  bool get isInitialized => _isInitialized;
  String? get currentCacheDir => _cacheDir?.path;

  static String _partPathFor(String targetPath) => '$targetPath.part';

  static String _backupPathFor(String targetPath) => '$targetPath.bak';

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
        final appDir = await getApplicationSupportDirectory();
        _cacheDir = Directory(path.join(appDir.path, 'lyrics_cache'));
      } else {
        final appDir = await getApplicationDocumentsDirectory();
        _cacheDir = Directory(path.join(appDir.path, 'lyrics_cache'));
      }

      if (!await _cacheDir!.exists()) {
        await _cacheDir!.create(recursive: true);
      }

      if (Platform.isWindows) {
        final defaultMusicCacheDir = await CacheService().getDefaultCacheDir();
        final currentMusicCacheDir = CacheService().currentCacheDir;
        if (currentMusicCacheDir == null ||
            path.normalize(currentMusicCacheDir) ==
                path.normalize(defaultMusicCacheDir)) {
          await _migrateLegacyWindowsCache(_cacheDir!);
        }
      }

      await _recoverSidecars();
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

  /// 将旧版本写入安装目录的歌词缓存补迁移到应用支持目录。
  Future<void> _migrateLegacyWindowsCache(Directory targetDir) async {
    final legacyDir = Directory(
      path.join(path.dirname(Platform.resolvedExecutable), 'lyrics_cache'),
    );
    if (path.normalize(legacyDir.path) == path.normalize(targetDir.path) ||
        !await legacyDir.exists()) {
      return;
    }

    var migratedCount = 0;
    try {
      await for (final entity in legacyDir.list(recursive: true)) {
        if (entity is! File) continue;
        final relativePath = path.relative(entity.path, from: legacyDir.path);
        final targetFile = File(path.join(targetDir.path, relativePath));
        if (await targetFile.exists()) continue;

        await targetFile.parent.create(recursive: true);
        await entity.copy(targetFile.path);
        migratedCount++;
      }
      if (migratedCount > 0) {
        _log(
          '📦 [LyricCacheService] 已迁移 Windows 旧歌词缓存文件: $migratedCount 个',
          toDeveloperPanel: true,
        );
      }
    } catch (e) {
      _log(
        '⚠️ [LyricCacheService] 迁移 Windows 旧歌词缓存失败: $e',
        toDeveloperPanel: true,
      );
    }
  }

  Future<LyricCacheEntry?> readEntry(String cacheKey) async {
    await initialize();
    if (!_isInitialized || _cacheDir == null) return null;

    final targetPath = _entryPath(cacheKey);
    await _recoverTargetSidecars(targetPath);
    final file = File(targetPath);
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

    final targetPath = _entryPath(cacheKey);
    final content = jsonEncode(entry.toJson());
    await _writeStringAtomically(targetPath, content);
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

    await _deleteTargetArtifacts(_entryPath(cacheKey));
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
    final requestedQuality = quality == null
        ? null
        : CacheService.normalizeQualityValue(quality);
    final keysToRemove = (_trackCacheKeys[targetTrackKey] ?? const <String>{})
        .where(
          (cacheKey) => shouldDeleteTrackCacheKey(
            cacheKey: cacheKey,
            trackKey: targetTrackKey,
            indexValue: _index[cacheKey],
            requestedQuality: requestedQuality,
          ),
        )
        .toList(growable: false);

    if (keysToRemove.isEmpty) return;

    for (final cacheKey in keysToRemove) {
      await _deleteTargetArtifacts(_entryPath(cacheKey));
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

  Future<void> _deleteFileIfExists(File file) async {
    try {
      if (await file.exists()) {
        await file.delete();
      }
    } catch (_) {}
  }

  Future<void> _deleteTargetArtifacts(String targetPath) async {
    await _deleteFileIfExists(File(targetPath));
    await _deleteFileIfExists(File(_partPathFor(targetPath)));
    await _deleteFileIfExists(File(_backupPathFor(targetPath)));
  }

  Future<void> _recoverTargetSidecars(String targetPath) async {
    final targetFile = File(targetPath);
    final partFile = File(_partPathFor(targetPath));
    final backupFile = File(_backupPathFor(targetPath));

    if (await partFile.exists()) {
      if (await targetFile.exists()) {
        await _deleteFileIfExists(partFile);
      } else {
        try {
          await partFile.rename(targetFile.path);
        } catch (_) {
          await _deleteFileIfExists(partFile);
        }
      }
    }

    if (await backupFile.exists()) {
      if (await targetFile.exists()) {
        await _deleteFileIfExists(backupFile);
      } else {
        try {
          await backupFile.rename(targetFile.path);
        } catch (_) {
          await _deleteFileIfExists(backupFile);
        }
      }
    }
  }

  Future<void> _recoverSidecars() async {
    if (_cacheDir == null || !await _cacheDir!.exists()) return;

    final targets = <String>{};
    await for (final entity in _cacheDir!.list()) {
      if (entity is! File) continue;
      final filePath = entity.path;
      if (filePath.endsWith('.part')) {
        targets.add(filePath.substring(0, filePath.length - 5));
      } else if (filePath.endsWith('.bak')) {
        targets.add(filePath.substring(0, filePath.length - 4));
      }
    }

    for (final targetPath in targets) {
      await _recoverTargetSidecars(targetPath);
    }
  }

  Future<void> _promotePreparedTempFile({
    required File tempFile,
    required File targetFile,
  }) async {
    final backupFile = File(_backupPathFor(targetFile.path));
    await _deleteFileIfExists(backupFile);

    try {
      if (await targetFile.exists()) {
        await targetFile.rename(backupFile.path);
      }
      await tempFile.rename(targetFile.path);
      await _deleteFileIfExists(backupFile);
    } catch (_) {
      if (!await targetFile.exists() && await backupFile.exists()) {
        try {
          await backupFile.rename(targetFile.path);
        } catch (_) {}
      }
      rethrow;
    } finally {
      await _deleteFileIfExists(tempFile);
      if (await targetFile.exists()) {
        await _deleteFileIfExists(backupFile);
      }
    }
  }

  Future<void> _writeStringAtomically(String targetPath, String content) async {
    final tempFile = File(_partPathFor(targetPath));
    await _deleteFileIfExists(tempFile);
    await tempFile.writeAsString(content, flush: true);
    await _promotePreparedTempFile(
      tempFile: tempFile,
      targetFile: File(targetPath),
    );
  }

  Map<String, dynamic> _buildIndexValue(
    LyricCacheEntry entry, {
    int fileSize = 0,
  }) {
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
    final indexPath = _indexPath();
    final candidates = <String>[
      indexPath,
      _backupPathFor(indexPath),
      _partPathFor(indexPath),
    ];

    for (final candidatePath in candidates) {
      final file = File(candidatePath);
      if (!await file.exists()) {
        continue;
      }
      try {
        final raw = await file.readAsString();
        final json = jsonDecode(raw) as Map<String, dynamic>;
        _index
          ..clear()
          ..addAll(
            json.map(
              (key, value) =>
                  MapEntry(key, (value as Map).cast<String, dynamic>()),
            ),
          );
        _rebuildTrackCacheKeys();
        if (candidatePath != indexPath) {
          await _saveIndex();
        }
        return;
      } catch (e) {
        _log(
          '❌ [LyricCacheService] 加载歌词索引候选失败: ${path.basename(candidatePath)}, $e',
          toDeveloperPanel: true,
        );
      }
    }

    _index.clear();
    _trackCacheKeys.clear();
  }

  Future<void> _saveIndex() async {
    if (_cacheDir == null) return;
    try {
      await _writeStringAtomically(_indexPath(), jsonEncode(_index));
      _indexDirty = false;
    } catch (e) {
      _log('❌ [LyricCacheService] 保存歌词索引失败: $e', toDeveloperPanel: true);
    }
  }

  Future<void> _migrateLegacyTrackScopedKeys() async {
    if (_cacheDir == null || _index.isEmpty) return;

    var migratedCount = 0;
    var removedCount = 0;
    final groupedLegacyKeys = <String, List<String>>{};
    for (final entry in _index.entries) {
      final trackKey = entry.value['trackKey'] as String? ?? '';
      if (trackKey.isEmpty || entry.key == trackKey) {
        continue;
      }
      if (!entry.key.startsWith('${trackKey}_')) {
        continue;
      }
      groupedLegacyKeys.putIfAbsent(trackKey, () => <String>[]).add(entry.key);
    }

    for (final group in groupedLegacyKeys.entries) {
      final trackKey = group.key;
      final candidateKeys = <String>[
        if (_index.containsKey(trackKey)) trackKey,
        ...group.value,
      ];
      final preferredKey = await _selectPreferredMigrationKey(candidateKeys);
      if (preferredKey == null) {
        continue;
      }

      final preferredIndexValue = _index[preferredKey];
      if (preferredIndexValue == null) {
        continue;
      }

      if (preferredKey != trackKey) {
        final promoted = await _promotePreferredEntry(
          fromKey: preferredKey,
          toKey: trackKey,
        );
        if (!promoted) {
          continue;
        }
        migratedCount++;
      }

      _index[trackKey] = Map<String, dynamic>.from(preferredIndexValue);

      for (final cacheKey in candidateKeys) {
        if (cacheKey == trackKey) {
          continue;
        }
        await _deleteTargetArtifacts(_entryPath(cacheKey));
        if (_index.remove(cacheKey) != null) {
          removedCount++;
        }
      }
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

  Future<String?> _selectPreferredMigrationKey(
    List<String> candidateKeys,
  ) async {
    String? bestKey;
    LyricCacheEntry? bestEntry;
    var bestHasFile = false;

    for (final cacheKey in candidateKeys) {
      final entry = LyricCacheEntry.tryFromJson(
        _index[cacheKey] ?? const <String, dynamic>{},
      );
      if (entry == null) {
        continue;
      }
      final hasFile = await File(_entryPath(cacheKey)).exists();
      if (bestKey == null ||
          _compareMigrationCandidates(
                entry,
                hasFile: hasFile,
                other: bestEntry!,
                otherHasFile: bestHasFile,
              ) >
              0) {
        bestKey = cacheKey;
        bestEntry = entry;
        bestHasFile = hasFile;
      }
    }

    return bestKey;
  }

  int _compareMigrationCandidates(
    LyricCacheEntry entry, {
    required bool hasFile,
    required LyricCacheEntry other,
    required bool otherHasFile,
  }) {
    return compareEntriesForMigration(
      candidate: entry,
      candidateHasFile: hasFile,
      incumbent: other,
      incumbentHasFile: otherHasFile,
    );
  }

  Future<bool> _promotePreferredEntry({
    required String fromKey,
    required String toKey,
  }) async {
    final fromPath = _entryPath(fromKey);
    final toPath = _entryPath(toKey);
    await _recoverTargetSidecars(fromPath);
    await _recoverTargetSidecars(toPath);

    final fromFile = File(fromPath);
    final toFile = File(toPath);
    if (!await fromFile.exists()) {
      return false;
    }

    final tempFile = File(_partPathFor(toPath));
    try {
      await _deleteFileIfExists(tempFile);
      await fromFile.copy(tempFile.path);
      await _promotePreparedTempFile(tempFile: tempFile, targetFile: toFile);
      await _deleteTargetArtifacts(fromPath);
      return true;
    } catch (_) {
      await _deleteFileIfExists(tempFile);
      return false;
    }
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
      await _deleteTargetArtifacts(_entryPath(cacheKey));
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
