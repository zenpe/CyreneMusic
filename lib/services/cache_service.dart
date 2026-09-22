import 'dart:async';
import 'dart:io';
import 'dart:convert';
import 'dart:isolate';
import 'package:flutter/foundation.dart';
import '../utils/format_utils.dart';
import 'package:path_provider/path_provider.dart';
import 'package:crypto/crypto.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/track.dart';
import '../models/song_detail.dart';
import '../utils/audio_request_headers.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as path;
import 'audio_quality_service.dart';
import 'developer_mode_service.dart';
import 'structured_log_service.dart';

/// 缓存元数据模型
class CacheMetadata {
  final String songId;
  final String songName;
  final String artists;
  final String album;
  final String picUrl;
  final String source;
  final String quality;
  final String originalUrl;
  final int fileSize;
  final DateTime cachedAt;
  final DateTime lastAccessedAt;
  final String checksum;
  final String relativePath;
  final String contentType;

  CacheMetadata({
    required this.songId,
    required this.songName,
    required this.artists,
    required this.album,
    required this.picUrl,
    required this.source,
    required this.quality,
    required this.originalUrl,
    required this.fileSize,
    required this.cachedAt,
    required this.lastAccessedAt,
    required this.checksum,
    required this.relativePath,
    required this.contentType,
  });

  static String? _readRequiredString(Object? value) {
    if (value == null) return null;
    final text = value.toString().trim();
    if (text.isEmpty) return null;
    return text;
  }

  static String _readOptionalString(Object? value, {String fallback = ''}) {
    if (value == null) return fallback;
    final text = value.toString();
    return text.isEmpty ? fallback : text;
  }

  static int? _readRequiredInt(Object? value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '');
  }

  static DateTime? _readRequiredDateTime(Object? value) {
    final raw = value?.toString();
    if (raw == null || raw.isEmpty) return null;
    return DateTime.tryParse(raw);
  }

  static CacheMetadata? tryFromJson(Map<String, dynamic> json) {
    final songId = _readRequiredString(json['songId']);
    final songName = _readRequiredString(json['songName']);
    final artists = _readRequiredString(json['artists']);
    final source = _readRequiredString(json['source']);
    final fileSize = _readRequiredInt(json['fileSize']);
    final cachedAt = _readRequiredDateTime(json['cachedAt']);
    final checksum = _readRequiredString(json['checksum']);
    final relativePath = _readRequiredString(json['relativePath']);
    final contentType = _readRequiredString(json['contentType']);
    if (songId == null ||
        songName == null ||
        artists == null ||
        source == null ||
        fileSize == null ||
        cachedAt == null ||
        checksum == null ||
        relativePath == null ||
        contentType == null) {
      return null;
    }

    return CacheMetadata(
      songId: songId,
      songName: songName,
      artists: artists,
      album: _readOptionalString(json['album']),
      picUrl: _readOptionalString(json['picUrl']),
      source: source,
      quality: CacheService.normalizeQualityValue(json['quality']?.toString()),
      originalUrl: _readOptionalString(json['originalUrl']),
      fileSize: fileSize,
      cachedAt: cachedAt,
      lastAccessedAt: _readRequiredDateTime(json['lastAccessedAt']) ?? cachedAt,
      checksum: checksum,
      relativePath: relativePath,
      contentType: contentType,
    );
  }

  factory CacheMetadata.fromJson(Map<String, dynamic> json) {
    final metadata = CacheMetadata.tryFromJson(json);
    if (metadata == null) {
      throw const FormatException('Invalid cache metadata');
    }
    return metadata;
  }

  Map<String, dynamic> toJson() {
    return {
      'songId': songId,
      'songName': songName,
      'artists': artists,
      'album': album,
      'picUrl': picUrl,
      'source': source,
      'quality': quality,
      'originalUrl': originalUrl,
      'fileSize': fileSize,
      'cachedAt': cachedAt.toIso8601String(),
      'lastAccessedAt': lastAccessedAt.toIso8601String(),
      'checksum': checksum,
      'relativePath': relativePath,
      'contentType': contentType,
    };
  }

  CacheMetadata copyWith({
    String? songId,
    String? songName,
    String? artists,
    String? album,
    String? picUrl,
    String? source,
    String? quality,
    String? originalUrl,
    int? fileSize,
    DateTime? cachedAt,
    DateTime? lastAccessedAt,
    String? checksum,
    String? relativePath,
    String? contentType,
  }) {
    return CacheMetadata(
      songId: songId ?? this.songId,
      songName: songName ?? this.songName,
      artists: artists ?? this.artists,
      album: album ?? this.album,
      picUrl: picUrl ?? this.picUrl,
      source: source ?? this.source,
      quality: quality ?? this.quality,
      originalUrl: originalUrl ?? this.originalUrl,
      fileSize: fileSize ?? this.fileSize,
      cachedAt: cachedAt ?? this.cachedAt,
      lastAccessedAt: lastAccessedAt ?? this.lastAccessedAt,
      checksum: checksum ?? this.checksum,
      relativePath: relativePath ?? this.relativePath,
      contentType: contentType ?? this.contentType,
    );
  }
}

class _ResolvedCacheEntry {
  final String key;
  final CacheMetadata metadata;

  const _ResolvedCacheEntry({required this.key, required this.metadata});
}

class _DigestCaptureSink implements Sink<Digest> {
  Digest? value;

  @override
  void add(Digest data) {
    value = data;
  }

  @override
  void close() {}
}

class _CacheVerificationRequest {
  final String filePath;
  final String expectedChecksum;

  const _CacheVerificationRequest({
    required this.filePath,
    required this.expectedChecksum,
  });
}

Future<bool> _verifyCachePayloadFile(_CacheVerificationRequest request) async {
  RandomAccessFile? raf;
  try {
    raf = await File(request.filePath).open(mode: FileMode.read);
    final digestSink = _DigestCaptureSink();
    final md5Sink = md5.startChunkedConversion(digestSink);
    var remaining = await raf.length();
    while (remaining > 0) {
      final chunkSize = remaining > 64 * 1024 ? 64 * 1024 : remaining;
      final chunk = await raf.read(chunkSize);
      if (chunk.isEmpty) return false;
      md5Sink.add(chunk);
      remaining -= chunk.length;
    }
    md5Sink.close();
    return digestSink.value?.toString() == request.expectedChecksum;
  } catch (_) {
    return false;
  } finally {
    await raf?.close();
  }
}

class _DownloadedCachePayload {
  final File tempFile;
  final int audioLength;
  final String checksum;
  final String extension;
  final String contentType;

  const _DownloadedCachePayload({
    required this.tempFile,
    required this.audioLength,
    required this.checksum,
    required this.extension,
    required this.contentType,
  });
}

class _AudioFormat {
  final String extension;
  final String contentType;

  const _AudioFormat(this.extension, this.contentType);
}

class CachedAudioFileInfo {
  final String cacheKey;
  final String filePath;
  final CacheMetadata metadata;
  final int audioLength;
  final String contentType;

  const CachedAudioFileInfo({
    required this.cacheKey,
    required this.filePath,
    required this.metadata,
    required this.audioLength,
    required this.contentType,
  });
}

/// 缓存统计信息
class CacheStats {
  final int totalFiles;
  final int totalSize;
  final int neteaseCount;
  final int appleCount;
  final int qqCount;
  final int kugouCount;
  final int kuwoCount;

  CacheStats({
    required this.totalFiles,
    required this.totalSize,
    required this.neteaseCount,
    required this.appleCount,
    required this.qqCount,
    required this.kugouCount,
    required this.kuwoCount,
  });

  String get formattedSize => formatFileSize(totalSize);
}

/// 音乐缓存服务
class CacheService extends ChangeNotifier {
  static final CacheService _instance = CacheService._internal();
  factory CacheService() => _instance;
  CacheService._internal();

  static const int _manifestSchemaVersion = 3;
  static const int _defaultMaxCacheSizeBytes = 512 * 1024 * 1024;
  static const Duration _maintenanceDebounce = Duration(seconds: 2);
  static const Duration _cacheDownloadTimeout = Duration(seconds: 30);
  static const Duration _backgroundChecksumDelay = Duration(seconds: 10);
  static const String _maxCacheSizePrefsKey = 'max_cache_size_bytes_v2';
  static const String _legacyMaxCacheSizePrefsKey = 'max_cache_size_bytes';

  Directory? _cacheDir;
  Map<String, CacheMetadata> _cacheIndex = {};
  final Map<String, Future<bool>> _pendingCacheWrites = {};
  bool _isInitialized = false;
  bool _cacheEnabled = false; // 缓存开关，默认关闭（由用户显式开启，避免移动网络隐式整曲下载）
  String? _customCacheDir; // 自定义缓存目录
  int _maxCacheSizeBytes = _defaultMaxCacheSizeBytes;
  Timer? _indexSaveDebounce;
  Timer? _maintenanceTimer;
  bool _maintenanceRunning = false;
  final Map<String, String> _verifiedCacheChecksums = <String, String>{};
  final Map<String, Future<void>> _pendingChecksumVerifications =
      <String, Future<void>>{};
  final Set<String> _pinnedCacheKeys = <String>{};
  final Map<String, String> _pendingDeletionPaths = <String, String>{};
  Future<void> _checksumVerificationTail = Future<void>.value();
  int _checksumVerificationEpoch = 0;

  bool get isInitialized => _isInitialized;
  int get cachedCount => _cacheIndex.length;
  bool get cacheEnabled => _cacheEnabled;
  String? get customCacheDir => _customCacheDir;
  String? get currentCacheDir => _cacheDir?.path;
  int get maxCacheSizeBytes => _maxCacheSizeBytes;
  String get formattedMaxCacheSize => formatFileSize(
    _maxCacheSizeBytes,
    fractionDigits: 1,
    trimTrailingZeros: true,
  );

  void pinCachedFile(CachedAudioFileInfo fileInfo) {
    _pinnedCacheKeys.add(fileInfo.cacheKey);
  }

  void unpinCachedFile(CachedAudioFileInfo fileInfo) {
    _pinnedCacheKeys.remove(fileInfo.cacheKey);
    final pendingPath = _pendingDeletionPaths.remove(fileInfo.cacheKey);
    if (pendingPath != null) {
      unawaited(_deleteCacheArtifacts(pendingPath));
    }
  }

  Future<void> _removeCacheEntry(String cacheKey) async {
    final metadata = _cacheIndex.remove(cacheKey);
    if (metadata == null) return;
    final filePath = _getCacheFilePath(cacheKey, metadata);
    if (_pinnedCacheKeys.contains(cacheKey)) {
      _pendingDeletionPaths[cacheKey] = filePath;
    } else {
      try {
        await _deleteCacheArtifacts(filePath);
      } finally {
        _forgetVerifiedChecksum(cacheKey);
      }
      return;
    }
    _forgetVerifiedChecksum(cacheKey);
  }

  static String normalizeQualityValue(String? quality) {
    if (quality != null) {
      final trimmed = quality.trim();
      if (trimmed.isNotEmpty) {
        final lowered = trimmed.toLowerCase();
        final parsed = AudioQualityService.stringToQuality(lowered);
        if (parsed != null) {
          return parsed.value;
        }
        return lowered;
      }
    }
    return AudioQuality.standard.value;
  }

  static bool _isRemoteUrl(String url) {
    return url.startsWith('http://') || url.startsWith('https://');
  }

  static String _partPathFor(String targetPath) => '$targetPath.part';

  static String _backupPathFor(String targetPath) => '$targetPath.bak';

  static String _payloadPartPathFor(String targetPath) =>
      '$targetPath.payload.part';

  static String _preferNonEmpty(String primary, String fallback) {
    return primary.isNotEmpty ? primary : fallback;
  }

  void _logCacheDebug(String message, {bool toDeveloperPanel = false}) {
    final level = message.contains('❌')
        ? LogLevel.error
        : message.contains('⚠️')
        ? LogLevel.warning
        : LogLevel.debug;
    StructuredLogService.event(
      'cache_service.log',
      level: level,
      fields: {'message': message},
    );
    if (toDeveloperPanel) {
      DeveloperModeService().addLog(message);
    }
  }

  /// 初始化缓存服务
  Future<void> initialize() async {
    if (_isInitialized) {
      _logCacheDebug('ℹ️ [CacheService] 缓存服务已初始化，跳过');
      return;
    }

    try {
      _logCacheDebug('💾 [CacheService] 开始初始化缓存服务...');

      // 加载缓存设置
      await _loadSettings();

      // 获取缓存目录
      if (_customCacheDir != null && _customCacheDir!.isNotEmpty) {
        // 使用自定义目录
        _cacheDir = Directory(_customCacheDir!);
        _logCacheDebug('📂 [CacheService] 使用自定义目录: ${_customCacheDir!}');
      } else if (Platform.isWindows) {
        // Windows: 使用应用支持目录，避免缓存写入安装目录
        final appDir = await getApplicationSupportDirectory();
        _cacheDir = Directory(path.join(appDir.path, 'music_cache'));
        _logCacheDebug('📂 [CacheService] 应用支持目录: ${appDir.path}');
      } else {
        // 其他平台: 使用应用文档目录
        final appDir = await getApplicationDocumentsDirectory();
        _cacheDir = Directory('${appDir.path}/music_cache');
        _logCacheDebug('📂 [CacheService] 应用文档目录: ${appDir.path}');
      }

      _logCacheDebug('📂 [CacheService] 缓存目录路径: ${_cacheDir!.path}');
      _logCacheDebug(
        '🔧 [CacheService] 缓存开关状态: ${_cacheEnabled ? "已启用" : "已禁用"}',
      );

      // 创建缓存目录
      if (!await _cacheDir!.exists()) {
        _logCacheDebug('📁 [CacheService] 缓存目录不存在，创建中...');
        await _cacheDir!.create(recursive: true);
        _logCacheDebug('✅ [CacheService] 缓存目录已创建: ${_cacheDir!.path}');
      } else {
        _logCacheDebug('✅ [CacheService] 缓存目录已存在: ${_cacheDir!.path}');
      }

      await Directory(
        path.join(_cacheDir!.path, 'audio'),
      ).create(recursive: true);
      await Directory(
        path.join(_cacheDir!.path, 'staging'),
      ).create(recursive: true);

      if (Platform.isWindows &&
          (_customCacheDir == null || _customCacheDir!.isEmpty)) {
        await _migrateLegacyWindowsCache(_cacheDir!);
      }

      // 验证目录是否可写
      try {
        final testFile = File('${_cacheDir!.path}/.test');
        await testFile.writeAsString('test');
        await testFile.delete();
        _logCacheDebug('✅ [CacheService] 缓存目录可写');
      } catch (e) {
        _logCacheDebug('❌ [CacheService] 缓存目录不可写: $e');
        throw Exception('缓存目录不可写');
      }

      await _purgeLegacyCyreneCache();
      await _recoverCacheFileSidecars();

      // 加载缓存索引
      await _loadCacheIndex();

      _isInitialized = true;
      notifyListeners();

      _scheduleMaintenance();

      _logCacheDebug('✅ [CacheService] 缓存服务初始化完成！');
      _logCacheDebug('📊 [CacheService] 已缓存歌曲数: ${_cacheIndex.length}');
      _logCacheDebug('📁 [CacheService] 缓存位置: ${_cacheDir!.path}');
    } catch (e, stackTrace) {
      _logCacheDebug('❌ [CacheService] 初始化失败: $e');
      _logCacheDebug('❌ [CacheService] 错误堆栈: $stackTrace');
      _isInitialized = false;
    }
  }

  /// 将旧版本写入安装目录的缓存补迁移到应用支持目录。
  ///
  /// 只复制目标目录中不存在的文件，并保留旧目录，避免升级过程中因权限
  /// 或磁盘空间问题导致用户已有缓存丢失。
  Future<void> _migrateLegacyWindowsCache(Directory targetDir) async {
    final legacyDir = Directory(
      path.join(path.dirname(Platform.resolvedExecutable), 'music_cache'),
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
        _logCacheDebug('📦 [CacheService] 已迁移 Windows 旧缓存文件: $migratedCount 个');
      }
    } catch (e) {
      _logCacheDebug('⚠️ [CacheService] 迁移 Windows 旧缓存失败: $e');
    }
  }

  String _qualityKey([String? quality]) {
    return normalizeQualityValue(quality);
  }

  String _generateCacheKey(
    String songId,
    MusicSource source, [
    String? quality,
  ]) {
    return '${source.name}_${songId}_${_qualityKey(quality)}';
  }

  String _generateLegacyCacheKey(String songId, MusicSource source) {
    return '${source.name}_$songId';
  }

  CacheMetadata _normalizeMetadata(CacheMetadata metadata) {
    final normalizedQuality = _qualityKey(metadata.quality);
    if (metadata.quality == normalizedQuality) {
      return metadata;
    }
    return metadata.copyWith(quality: normalizedQuality);
  }

  List<String> _matchingCacheKeysForTrack(Track track, {String? quality}) {
    final requestedQuality = quality != null ? _qualityKey(quality) : null;
    final songId = track.id.toString();
    final sourceName = track.source.name;

    return _cacheIndex.entries
        .where((entry) {
          final metadata = entry.value;
          if (metadata.songId != songId || metadata.source != sourceName) {
            return false;
          }
          if (requestedQuality == null) {
            return true;
          }
          return _qualityKey(metadata.quality) == requestedQuality;
        })
        .map((entry) => entry.key)
        .toList(growable: false);
  }

  _ResolvedCacheEntry? _resolveCacheEntry(Track track, {String? quality}) {
    final expectedQuality = _qualityKey(quality);
    final qualifiedKey = _generateCacheKey(
      track.id.toString(),
      track.source,
      quality,
    );
    final qualifiedMetadata = _cacheIndex[qualifiedKey];
    if (qualifiedMetadata != null) {
      final normalizedMetadata = _normalizeMetadata(qualifiedMetadata);
      if (normalizedMetadata.quality == expectedQuality) {
        if (!identical(normalizedMetadata, qualifiedMetadata)) {
          _cacheIndex[qualifiedKey] = normalizedMetadata;
          _scheduleIndexSave();
        }
        return _ResolvedCacheEntry(
          key: qualifiedKey,
          metadata: normalizedMetadata,
        );
      }
    }

    final legacyKey = _generateLegacyCacheKey(
      track.id.toString(),
      track.source,
    );
    final legacyMetadata = _cacheIndex[legacyKey];
    if (legacyMetadata != null) {
      final normalizedMetadata = _normalizeMetadata(legacyMetadata);
      if (normalizedMetadata.quality == expectedQuality) {
        if (!identical(normalizedMetadata, legacyMetadata)) {
          _cacheIndex[legacyKey] = normalizedMetadata;
          _scheduleIndexSave();
        }
        return _ResolvedCacheEntry(
          key: legacyKey,
          metadata: normalizedMetadata,
        );
      }
    }

    for (final key in _matchingCacheKeysForTrack(track, quality: quality)) {
      final metadata = _normalizeMetadata(_cacheIndex[key]!);
      if (!identical(metadata, _cacheIndex[key])) {
        _cacheIndex[key] = metadata;
        _scheduleIndexSave();
      }
      return _ResolvedCacheEntry(key: key, metadata: metadata);
    }

    return null;
  }

  void _touchCacheEntry(String key, CacheMetadata metadata) {
    _cacheIndex[key] = metadata.copyWith(lastAccessedAt: DateTime.now());
    _scheduleIndexSave();
  }

  void _scheduleIndexSave() {
    _indexSaveDebounce?.cancel();
    _indexSaveDebounce = Timer(
      const Duration(milliseconds: 400),
      () => unawaited(_saveCacheIndex()),
    );
  }

  void _scheduleMaintenance() {
    if (!_isInitialized || _cacheDir == null) return;
    _maintenanceTimer?.cancel();
    _maintenanceTimer = Timer(
      _maintenanceDebounce,
      () => unawaited(_runMaintenance()),
    );
  }

  Future<void> _runMaintenance() async {
    if (_maintenanceRunning || _cacheDir == null) return;
    _maintenanceRunning = true;
    try {
      await _recoverCacheFileSidecars();
      final migrated = await _migrateLegacyCacheEntries();
      final changedIndex = await _removeMissingIndexedFiles();
      final removedOrphans = await _removeOrphanCacheFiles();
      final trimmedEntries = await _enforceCacheSizeLimit();

      if (migrated ||
          changedIndex ||
          removedOrphans > 0 ||
          trimmedEntries > 0) {
        await _saveCacheIndex();
        notifyListeners();
      }
    } catch (e) {
      _logCacheDebug('❌ [CacheService] 缓存治理失败: $e');
    } finally {
      _maintenanceRunning = false;
    }
  }

  Future<bool> _migrateLegacyCacheEntries() async {
    if (_cacheIndex.isEmpty || _cacheDir == null) return false;

    final migratedIndex = <String, CacheMetadata>{};
    final discardedPaths = <String>{};
    var changed = false;

    for (final entry in _cacheIndex.entries) {
      final metadata = _normalizeMetadata(entry.value);
      final canonicalKey = [
        metadata.source,
        metadata.songId,
        metadata.quality,
      ].join('_');
      final existing = migratedIndex[canonicalKey];

      if (existing == null) {
        migratedIndex[canonicalKey] = metadata;
      } else {
        final keepIncoming =
            metadata.lastAccessedAt.isAfter(existing.lastAccessedAt) ||
            (metadata.lastAccessedAt == existing.lastAccessedAt &&
                metadata.cachedAt.isAfter(existing.cachedAt));
        final discarded = keepIncoming ? existing : metadata;
        if (keepIncoming) {
          migratedIndex[canonicalKey] = metadata;
        }
        try {
          discardedPaths.add(_getCacheFilePath(entry.key, discarded));
        } catch (_) {}
        changed = true;
      }

      if (entry.key != canonicalKey || !identical(metadata, entry.value)) {
        changed = true;
      }
    }

    if (!changed) return false;

    _cacheIndex = migratedIndex;
    _verifiedCacheChecksums.clear();
    final retainedPaths = migratedIndex.entries
        .map((entry) {
          try {
            return path.normalize(_getCacheFilePath(entry.key, entry.value));
          } catch (_) {
            return '';
          }
        })
        .where((filePath) => filePath.isNotEmpty)
        .toSet();
    for (final discardedPath in discardedPaths) {
      if (retainedPaths.contains(path.normalize(discardedPath))) continue;
      await _deleteCacheArtifacts(discardedPath);
    }

    _logCacheDebug(
      '📦 [CacheService] 已统一缓存身份为平台+歌曲ID+音质: '
      '${_cacheIndex.length} 条记录',
    );
    return true;
  }

  Future<bool> _removeMissingIndexedFiles() async {
    if (_cacheDir == null || _cacheIndex.isEmpty) return false;
    final keysToRemove = <String>[];
    for (final entry in _cacheIndex.entries) {
      final file = File(_getCacheFilePath(entry.key, entry.value));
      if (!await file.exists()) {
        keysToRemove.add(entry.key);
      }
    }
    for (final key in keysToRemove) {
      _cacheIndex.remove(key);
      _forgetVerifiedChecksum(key);
    }
    return keysToRemove.isNotEmpty;
  }

  Future<int> _removeOrphanCacheFiles() async {
    if (_cacheDir == null || !await _cacheDir!.exists()) return 0;
    final expectedPaths = _cacheIndex.entries
        .map((entry) => _getCacheFilePath(entry.key, entry.value))
        .map(path.normalize)
        .toSet();
    var removed = 0;
    final audioDir = Directory(path.join(_cacheDir!.path, 'audio'));
    if (!await audioDir.exists()) return 0;
    await for (final entity in audioDir.list(recursive: true)) {
      if (entity is! File) continue;
      if (expectedPaths.contains(path.normalize(entity.path))) continue;
      try {
        await entity.delete();
        removed++;
      } catch (_) {}
    }
    return removed;
  }

  Future<int> _enforceCacheSizeLimit() async {
    if (_cacheDir == null || _cacheIndex.isEmpty) return 0;

    final maxCacheSizeBytes = _normalizedMaxCacheSizeBytes(_maxCacheSizeBytes);
    final entries = <MapEntry<String, CacheMetadata>>[];
    var totalSize = 0;
    for (final entry in _cacheIndex.entries) {
      final file = File(_getCacheFilePath(entry.key, entry.value));
      if (!await file.exists()) continue;
      final fileLength = await file.length();
      totalSize += fileLength;
      entries.add(entry);
    }

    if (totalSize <= maxCacheSizeBytes) return 0;

    entries.sort(
      (a, b) => a.value.lastAccessedAt.compareTo(b.value.lastAccessedAt),
    );

    var removed = 0;
    for (final entry in entries) {
      if (totalSize <= maxCacheSizeBytes) break;
      if (_pinnedCacheKeys.contains(entry.key)) continue;
      final cacheFilePath = _getCacheFilePath(entry.key, entry.value);
      final file = File(cacheFilePath);
      if (await file.exists()) {
        final fileLength = await file.length();
        await _deleteCacheArtifacts(cacheFilePath);
        totalSize -= fileLength;
      } else {
        await _deleteCacheArtifacts(cacheFilePath);
      }
      _cacheIndex.remove(entry.key);
      _forgetVerifiedChecksum(entry.key);
      removed++;
    }

    return removed;
  }

  /// 获取缓存文件路径
  String _getCacheFilePath(String cacheKey, [CacheMetadata? metadata]) {
    final resolvedMetadata = metadata ?? _cacheIndex[cacheKey];
    if (resolvedMetadata == null) {
      throw StateError('Missing cache metadata for $cacheKey');
    }
    final relativePath = path.normalize(resolvedMetadata.relativePath);
    if (path.isAbsolute(relativePath) || relativePath.startsWith('..')) {
      throw FormatException('Invalid cache path: $relativePath');
    }
    final absolutePath = path.normalize(
      path.join(_cacheDir!.path, relativePath),
    );
    if (!path.isWithin(path.normalize(_cacheDir!.path), absolutePath)) {
      throw FormatException('Cache path escapes root: $relativePath');
    }
    return absolutePath;
  }

  String _getCacheIndexPath() {
    return path.join(_cacheDir!.path, 'cache_manifest_v3.json');
  }

  String _relativeAudioPath(String cacheKey, String extension) {
    final hash = sha256.convert(utf8.encode(cacheKey)).toString();
    return path.join('audio', hash.substring(0, 2), '$hash.$extension');
  }

  Future<void> _deleteFileIfExists(File file) async {
    try {
      if (await file.exists()) {
        await file.delete();
      }
    } catch (_) {}
  }

  Future<void> _deleteCacheArtifacts(String targetPath) async {
    await _deleteFileIfExists(File(targetPath));
    await _deleteFileIfExists(File(_partPathFor(targetPath)));
    await _deleteFileIfExists(File(_backupPathFor(targetPath)));
    await _deleteFileIfExists(File(_payloadPartPathFor(targetPath)));
  }

  void _forgetVerifiedChecksum(String cacheKey) {
    _verifiedCacheChecksums.remove(cacheKey);
    _checksumVerificationEpoch++;
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
    } catch (e) {
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

  Future<void> _writeBytesAtomically(String targetPath, List<int> bytes) async {
    final tempFile = File(_partPathFor(targetPath));
    await _deleteFileIfExists(tempFile);
    await tempFile.writeAsBytes(bytes, flush: true);
    await _promotePreparedTempFile(
      tempFile: tempFile,
      targetFile: File(targetPath),
    );
  }

  Future<_DownloadedCachePayload?> _downloadAudioPayload(
    Track track,
    SongDetail songDetail,
    String cacheKey,
    String quality,
  ) async {
    final client = http.Client();
    final stagingName = sha256.convert(utf8.encode(cacheKey)).toString();
    final payloadTempFile = File(
      path.join(_cacheDir!.path, 'staging', '$stagingName.part'),
    );
    await payloadTempFile.parent.create(recursive: true);
    await _deleteFileIfExists(payloadTempFile);

    IOSink? sink;
    Future<void> closeSink() async {
      final current = sink;
      sink = null;
      if (current == null) return;
      try {
        await current.close();
      } catch (_) {}
    }

    try {
      final request = http.Request('GET', Uri.parse(songDetail.url))
        ..headers.addAll(buildAudioRequestHeaders(track.source));
      final response = await client
          .send(request)
          .timeout(_cacheDownloadTimeout);
      if (response.statusCode != 200) {
        _logCacheDebug(
          '❌ [CacheService] 缓存下载失败: HTTP ${response.statusCode} '
          'track=${track.name} url=${songDetail.url}',
          toDeveloperPanel: true,
        );
        return null;
      }

      final declaredLength = response.contentLength;
      final digestSink = _DigestCaptureSink();
      final md5Sink = md5.startChunkedConversion(digestSink);
      final outputSink = payloadTempFile.openWrite();
      sink = outputSink;

      var audioLength = 0;
      await for (final chunk in response.stream.timeout(
        _cacheDownloadTimeout,
      )) {
        audioLength += chunk.length;
        md5Sink.add(chunk);
        outputSink.add(chunk);
      }

      if (declaredLength != null && audioLength != declaredLength) {
        _logCacheDebug(
          '❌ [CacheService] 缓存下载不完整: '
          'declared=$declaredLength actual=$audioLength track=${track.name}',
          toDeveloperPanel: true,
        );
        await closeSink();
        await _deleteFileIfExists(payloadTempFile);
        return null;
      }

      md5Sink.close();
      await outputSink.flush();
      await outputSink.close();
      sink = null;

      if (audioLength <= 0) {
        await _deleteFileIfExists(payloadTempFile);
        return null;
      }
      final format = await _detectAudioFormat(
        payloadTempFile,
        response.headers['content-type'],
        songDetail.url,
        quality,
      );
      if (format == null) {
        _logCacheDebug(
          '⚠️ [CacheService] 无法识别音频格式，不写入缓存: ${track.name}',
          toDeveloperPanel: true,
        );
        await _deleteFileIfExists(payloadTempFile);
        return null;
      }

      _logCacheDebug(
        '📥 [CacheService] 下载完成: $audioLength bytes key=$cacheKey',
        toDeveloperPanel: true,
      );

      return _DownloadedCachePayload(
        tempFile: payloadTempFile,
        audioLength: audioLength,
        checksum: digestSink.value?.toString() ?? '',
        extension: format.extension,
        contentType: format.contentType,
      );
    } catch (e) {
      await closeSink();
      await _deleteFileIfExists(payloadTempFile);
      rethrow;
    } finally {
      client.close();
      await closeSink();
    }
  }

  Future<_AudioFormat?> _detectAudioFormat(
    File file,
    String? responseContentType,
    String sourceUrl,
    String quality,
  ) async {
    final raf = await file.open(mode: FileMode.read);
    late final List<int> header;
    try {
      header = await raf.read(16);
    } finally {
      await raf.close();
    }

    if (header.length >= 4 &&
        header[0] == 0x66 &&
        header[1] == 0x4c &&
        header[2] == 0x61 &&
        header[3] == 0x43) {
      return const _AudioFormat('flac', 'audio/flac');
    }
    if (header.length >= 4 &&
        header[0] == 0x4f &&
        header[1] == 0x67 &&
        header[2] == 0x67 &&
        header[3] == 0x53) {
      return const _AudioFormat('ogg', 'audio/ogg');
    }
    if (header.length >= 12 &&
        header[4] == 0x66 &&
        header[5] == 0x74 &&
        header[6] == 0x79 &&
        header[7] == 0x70) {
      return const _AudioFormat('m4a', 'audio/mp4');
    }
    if (header.length >= 12 &&
        header[0] == 0x52 &&
        header[1] == 0x49 &&
        header[2] == 0x46 &&
        header[3] == 0x46 &&
        header[8] == 0x57 &&
        header[9] == 0x41 &&
        header[10] == 0x56 &&
        header[11] == 0x45) {
      return const _AudioFormat('wav', 'audio/wav');
    }
    if (header.length >= 3 &&
        header[0] == 0x49 &&
        header[1] == 0x44 &&
        header[2] == 0x33) {
      return const _AudioFormat('mp3', 'audio/mpeg');
    }
    if (header.length >= 2 && header[0] == 0xff) {
      if ((header[1] & 0xf6) == 0xf0) {
        return const _AudioFormat('aac', 'audio/aac');
      }
      if ((header[1] & 0xe0) == 0xe0) {
        return const _AudioFormat('mp3', 'audio/mpeg');
      }
    }

    final contentType = responseContentType
        ?.split(';')
        .first
        .trim()
        .toLowerCase();
    const byContentType = <String, _AudioFormat>{
      'audio/flac': _AudioFormat('flac', 'audio/flac'),
      'audio/x-flac': _AudioFormat('flac', 'audio/flac'),
      'audio/mpeg': _AudioFormat('mp3', 'audio/mpeg'),
      'audio/mp4': _AudioFormat('m4a', 'audio/mp4'),
      'audio/aac': _AudioFormat('aac', 'audio/aac'),
      'audio/ogg': _AudioFormat('ogg', 'audio/ogg'),
      'audio/wav': _AudioFormat('wav', 'audio/wav'),
      'audio/x-wav': _AudioFormat('wav', 'audio/wav'),
    };
    final contentTypeFormat = byContentType[contentType];
    if (contentTypeFormat != null) return contentTypeFormat;

    final urlExtension = path
        .extension(Uri.tryParse(sourceUrl)?.path ?? '')
        .replaceFirst('.', '')
        .toLowerCase();
    const byExtension = <String, _AudioFormat>{
      'flac': _AudioFormat('flac', 'audio/flac'),
      'mp3': _AudioFormat('mp3', 'audio/mpeg'),
      'm4a': _AudioFormat('m4a', 'audio/mp4'),
      'aac': _AudioFormat('aac', 'audio/aac'),
      'ogg': _AudioFormat('ogg', 'audio/ogg'),
      'wav': _AudioFormat('wav', 'audio/wav'),
    };
    return byExtension[urlExtension] ??
        byExtension[AudioQualityService.getExtensionFromLevel(quality)];
  }

  Future<String> _promoteAudioFile(
    String cacheKey, {
    required String extension,
    required File tempFile,
  }) async {
    final relativePath = _relativeAudioPath(cacheKey, extension);
    final targetFile = File(path.join(_cacheDir!.path, relativePath));
    await targetFile.parent.create(recursive: true);
    await _promotePreparedTempFile(tempFile: tempFile, targetFile: targetFile);
    return relativePath;
  }

  void _validateCachedPayloadForPlayback({
    required String cacheKey,
    required CacheMetadata metadata,
    required String filePath,
    required int audioLength,
  }) {
    if (_verifiedCacheChecksums[cacheKey] == metadata.checksum) {
      return;
    }
    if (metadata.fileSize != audioLength) {
      throw Exception(
        '缓存音频长度不匹配: metadata=${metadata.fileSize}, actual=$audioLength',
      );
    }

    _scheduleBackgroundChecksumVerification(
      cacheKey: cacheKey,
      metadata: metadata,
      filePath: filePath,
    );
  }

  void _scheduleBackgroundChecksumVerification({
    required String cacheKey,
    required CacheMetadata metadata,
    required String filePath,
  }) {
    if (_pendingChecksumVerifications.containsKey(cacheKey)) return;
    final epoch = _checksumVerificationEpoch;
    final task = _checksumVerificationTail.then((_) async {
      try {
        await Future<void>.delayed(_backgroundChecksumDelay);
        if (epoch != _checksumVerificationEpoch) return;
        final valid = await Isolate.run(
          () => _verifyCachePayloadFile(
            _CacheVerificationRequest(
              filePath: filePath,
              expectedChecksum: metadata.checksum,
            ),
          ),
        );
        if (epoch != _checksumVerificationEpoch) return;
        final currentMetadata = _cacheIndex[cacheKey];
        if (currentMetadata?.checksum != metadata.checksum) return;
        if (valid) {
          _verifiedCacheChecksums[cacheKey] = metadata.checksum;
          return;
        }

        _logCacheDebug('❌ [CacheService] 后台校验失败，移除损坏缓存: $cacheKey');
        await _removeCacheEntry(cacheKey);
        await _saveCacheIndex();
        notifyListeners();
      } catch (e) {
        _logCacheDebug('⚠️ [CacheService] 后台校验任务失败: $cacheKey, $e');
      }
    });
    _checksumVerificationTail = task;
    _pendingChecksumVerifications[cacheKey] = task;
    unawaited(
      task.whenComplete(() {
        if (identical(_pendingChecksumVerifications[cacheKey], task)) {
          _pendingChecksumVerifications.remove(cacheKey);
        }
      }),
    );
  }

  Future<void> _recoverCacheFileSidecars() async {
    if (_cacheDir == null || !await _cacheDir!.exists()) return;

    final indexPath = _getCacheIndexPath();
    await for (final entity in _cacheDir!.list(recursive: true)) {
      if (entity is! File) continue;
      final filePath = entity.path;
      if (filePath == _backupPathFor(indexPath) ||
          filePath == _partPathFor(indexPath)) {
        continue;
      }

      if (path.isWithin(path.join(_cacheDir!.path, 'staging'), filePath)) {
        await _deleteFileIfExists(entity);
        continue;
      }

      if (filePath.endsWith('.bak')) {
        final targetFile = File(filePath.substring(0, filePath.length - 4));
        if (await targetFile.exists()) {
          await _deleteFileIfExists(entity);
        } else {
          try {
            await entity.rename(targetFile.path);
          } catch (_) {}
        }
        continue;
      }

      if (filePath.endsWith('.part')) {
        final targetFile = File(filePath.substring(0, filePath.length - 5));
        if (await targetFile.exists()) {
          await _deleteFileIfExists(entity);
        } else {
          try {
            await entity.rename(targetFile.path);
          } catch (_) {
            await _deleteFileIfExists(entity);
          }
        }
      }
    }
  }

  Future<void> _purgeLegacyCyreneCache() async {
    if (_cacheDir == null || !await _cacheDir!.exists()) return;
    var removed = 0;
    await for (final entity in _cacheDir!.list(recursive: true)) {
      if (entity is! File) continue;
      final name = path.basename(entity.path).toLowerCase();
      if (name.endsWith('.cyrene') ||
          name.endsWith('.cyrene.part') ||
          name.endsWith('.cyrene.bak') ||
          name.endsWith('.payload.part')) {
        await _deleteFileIfExists(entity);
        removed++;
      }
    }
    if (removed > 0) {
      _logCacheDebug('🧹 [CacheService] 已废弃并清理旧 .cyrene 缓存: $removed 个文件');
    }
  }

  /// 检查缓存是否存在
  bool isCached(Track track, {String? quality}) {
    if (!_isInitialized || !_cacheEnabled) return false;
    return _resolveCacheEntry(track, quality: quality) != null;
  }

  /// 获取缓存的元数据
  CacheMetadata? getCachedMetadata(Track track, {String? quality}) {
    if (!_isInitialized || !_cacheEnabled) return null;
    return _resolveCacheEntry(track, quality: quality)?.metadata;
  }

  String? getCachedAudioFilePath(Track track, {String? quality}) {
    if (!_isInitialized || !_cacheEnabled || _cacheDir == null) return null;
    final resolved = _resolveCacheEntry(track, quality: quality);
    if (resolved == null) return null;
    return _getCacheFilePath(resolved.key, resolved.metadata);
  }

  CacheMetadata _buildCacheMetadata(
    Track track,
    SongDetail songDetail, {
    required String normalizedQuality,
    required int fileSize,
    required DateTime cachedAt,
    required DateTime lastAccessedAt,
    required String checksum,
    required String relativePath,
    required String contentType,
  }) {
    return CacheMetadata(
      songId: track.id.toString(),
      songName: _preferNonEmpty(songDetail.name, track.name),
      artists: _preferNonEmpty(songDetail.arName, track.artists),
      album: _preferNonEmpty(songDetail.alName, track.album),
      picUrl: _preferNonEmpty(songDetail.pic, track.picUrl),
      source: track.source.name,
      quality: normalizedQuality,
      originalUrl: _isRemoteUrl(songDetail.url) ? songDetail.url : '',
      fileSize: fileSize,
      cachedAt: cachedAt,
      lastAccessedAt: lastAccessedAt,
      checksum: checksum,
      relativePath: relativePath,
      contentType: contentType,
    );
  }

  CacheMetadata _mergeCacheMetadata(
    CacheMetadata existing,
    Track track,
    SongDetail songDetail, {
    required String normalizedQuality,
  }) {
    return existing.copyWith(
      songName: _preferNonEmpty(
        songDetail.name,
        _preferNonEmpty(existing.songName, track.name),
      ),
      artists: _preferNonEmpty(
        songDetail.arName,
        _preferNonEmpty(existing.artists, track.artists),
      ),
      album: _preferNonEmpty(
        songDetail.alName,
        _preferNonEmpty(existing.album, track.album),
      ),
      picUrl: _preferNonEmpty(
        songDetail.pic,
        _preferNonEmpty(existing.picUrl, track.picUrl),
      ),
      quality: normalizedQuality,
      originalUrl: _isRemoteUrl(songDetail.url)
          ? songDetail.url
          : existing.originalUrl,
    );
  }

  bool _isSameCacheMetadataPayload(CacheMetadata a, CacheMetadata b) {
    return a.songName == b.songName &&
        a.artists == b.artists &&
        a.album == b.album &&
        a.picUrl == b.picUrl &&
        a.quality == b.quality &&
        a.originalUrl == b.originalUrl;
  }

  Future<bool> _refreshExistingCacheMetadata(
    String cacheKey,
    CacheMetadata existing,
    Track track,
    SongDetail songDetail, {
    required String normalizedQuality,
  }) async {
    final updated = _mergeCacheMetadata(
      existing,
      track,
      songDetail,
      normalizedQuality: normalizedQuality,
    );
    if (_isSameCacheMetadataPayload(existing, updated)) {
      _logCacheDebug('ℹ️ [CacheService] 歌曲已缓存: ${track.name}');
      return true;
    }

    _cacheIndex[cacheKey] = updated;
    await _saveCacheIndex();
    _logCacheDebug('📝 [CacheService] 更新缓存元数据: ${track.name}');
    notifyListeners();
    return true;
  }

  Future<CachedAudioFileInfo?> getCachedAudioFileInfo(
    Track track, {
    String? quality,
  }) async {
    if (!_isInitialized || !_cacheEnabled || _cacheDir == null) return null;

    final resolved = _resolveCacheEntry(track, quality: quality);
    if (resolved == null) {
      return null;
    }

    final expectedQuality = _qualityKey(quality);
    if (resolved.metadata.quality != expectedQuality) {
      _logCacheDebug(
        '⚠️ [CacheService] 缓存音质不匹配: ${resolved.metadata.quality} != $expectedQuality',
      );
      return null;
    }

    final cacheKey = resolved.key;
    final metadata = resolved.metadata;
    final cacheFilePath = _getCacheFilePath(cacheKey, metadata);
    final cacheFile = File(cacheFilePath);

    if (!await cacheFile.exists()) {
      _logCacheDebug('⚠️ [CacheService] 缓存文件不存在: $cacheFilePath');
      await _removeCacheEntry(cacheKey);
      await _saveCacheIndex();
      return null;
    }

    try {
      final audioLength = await cacheFile.length();
      if (audioLength <= 0) throw Exception('缓存音频为空');

      _validateCachedPayloadForPlayback(
        cacheKey: cacheKey,
        metadata: metadata,
        filePath: cacheFilePath,
        audioLength: audioLength,
      );
      _touchCacheEntry(cacheKey, metadata);

      return CachedAudioFileInfo(
        cacheKey: cacheKey,
        filePath: cacheFilePath,
        metadata: metadata,
        audioLength: audioLength,
        contentType: metadata.contentType,
      );
    } catch (e) {
      _logCacheDebug('❌ [CacheService] 读取缓存音频失败: $e');
      await _removeCacheEntry(cacheKey);
      await _saveCacheIndex();
      return null;
    }
  }

  /// 缓存歌曲
  Future<bool> cacheSong(
    Track track,
    SongDetail songDetail,
    String quality,
  ) async {
    final sw = Stopwatch()..start();
    if (!_isInitialized) {
      _logCacheDebug(
        '⚠️ [CacheService] 跳过缓存(未初始化): ${track.name} '
        'source=${track.source.name} quality=$quality',
        toDeveloperPanel: true,
      );
      return false;
    }

    if (!_cacheEnabled) {
      _logCacheDebug(
        'ℹ️ [CacheService] 跳过缓存(功能禁用): ${track.name} '
        'source=${track.source.name} quality=$quality',
        toDeveloperPanel: true,
      );
      return false;
    }

    final normalizedQuality = _qualityKey(quality);
    final cacheKey = _generateCacheKey(
      track.id.toString(),
      track.source,
      normalizedQuality,
    );

    // Apple Music 常用 HLS(m3u8)；当前缓存逻辑是整文件下载，不适用于 HLS。
    if (track.source == MusicSource.apple ||
        songDetail.url.toLowerCase().contains('.m3u8')) {
      _logCacheDebug(
        'ℹ️ [CacheService] 跳过缓存(Apple/HLS): ${track.name} '
        'source=${track.getSourceName()} url=${songDetail.url}',
        toDeveloperPanel: true,
      );
      return false;
    }

    _logCacheDebug(
      '💾 [CacheService] 接收缓存请求: ${track.name} '
      'key=$cacheKey quality=$normalizedQuality dir=${_cacheDir?.path} '
      'url=${songDetail.url}',
      toDeveloperPanel: true,
    );

    final pending = _pendingCacheWrites[cacheKey];
    if (pending != null) {
      _logCacheDebug(
        'ℹ️ [CacheService] 复用进行中的缓存任务: ${track.name} '
        'key=$cacheKey elapsed=${sw.elapsedMilliseconds}ms',
        toDeveloperPanel: true,
      );
      return pending.then((cached) async {
        if (!cached) return false;
        final resolved = _resolveCacheEntry(track, quality: normalizedQuality);
        if (resolved == null) {
          return false;
        }
        return _refreshExistingCacheMetadata(
          resolved.key,
          resolved.metadata,
          track,
          songDetail,
          normalizedQuality: normalizedQuality,
        );
      });
    }

    final task = _cacheSongInternal(
      track,
      songDetail,
      normalizedQuality: normalizedQuality,
      cacheKey: cacheKey,
    );
    _pendingCacheWrites[cacheKey] = task;

    try {
      return await task;
    } finally {
      if (identical(_pendingCacheWrites[cacheKey], task)) {
        _pendingCacheWrites.remove(cacheKey);
      }
    }
  }

  Future<bool> _cacheSongInternal(
    Track track,
    SongDetail songDetail, {
    required String normalizedQuality,
    required String cacheKey,
  }) async {
    final sw = Stopwatch()..start();
    try {
      final resolved = _resolveCacheEntry(track, quality: normalizedQuality);
      if (resolved != null) {
        _logCacheDebug(
          'ℹ️ [CacheService] 命中已存在缓存，转为元数据刷新: ${track.name} '
          'key=${resolved.key}',
          toDeveloperPanel: true,
        );
        return await _refreshExistingCacheMetadata(
          resolved.key,
          resolved.metadata,
          track,
          songDetail,
          normalizedQuality: normalizedQuality,
        );
      }

      _logCacheDebug(
        '💾 [CacheService] 开始缓存音频: ${track.name} '
        'source=${track.getSourceName()} key=$cacheKey',
        toDeveloperPanel: true,
      );

      final downloadedPayload = await _downloadAudioPayload(
        track,
        songDetail,
        cacheKey,
        normalizedQuality,
      );
      if (downloadedPayload == null) {
        return false;
      }

      final now = DateTime.now();
      final relativePath = await _promoteAudioFile(
        cacheKey,
        extension: downloadedPayload.extension,
        tempFile: downloadedPayload.tempFile,
      );
      final metadata = _buildCacheMetadata(
        track,
        songDetail,
        normalizedQuality: normalizedQuality,
        fileSize: downloadedPayload.audioLength,
        cachedAt: now,
        lastAccessedAt: now,
        checksum: downloadedPayload.checksum,
        relativePath: relativePath,
        contentType: downloadedPayload.contentType,
      );

      _forgetVerifiedChecksum(cacheKey);
      _cacheIndex[cacheKey] = metadata;
      await _saveCacheIndex();
      _verifiedCacheChecksums[cacheKey] = metadata.checksum;
      _scheduleMaintenance();

      _logCacheDebug(
        '✅ [CacheService] 缓存完成: ${track.name} key=$cacheKey '
        'elapsed=${sw.elapsedMilliseconds}ms',
        toDeveloperPanel: true,
      );
      notifyListeners();
      return true;
    } catch (e) {
      _logCacheDebug(
        '❌ [CacheService] 缓存失败: ${track.name} '
        'key=$cacheKey url=${songDetail.url} error=$e',
        toDeveloperPanel: true,
      );
      return false;
    }
  }

  /// 加载缓存索引
  Future<void> _loadCacheIndex() async {
    final indexPath = _getCacheIndexPath();
    final candidates = <File>[
      File(indexPath),
      File(_backupPathFor(indexPath)),
      File(_partPathFor(indexPath)),
    ];

    for (final candidate in candidates) {
      if (!await candidate.exists()) {
        continue;
      }

      try {
        final indexData = jsonDecode(await candidate.readAsString());
        if (indexData is! Map<String, dynamic> ||
            indexData['schemaVersion'] != _manifestSchemaVersion ||
            indexData['entries'] is! Map) {
          throw const FormatException('invalid cache manifest');
        }

        final nextIndex = <String, CacheMetadata>{};
        var skippedEntries = 0;
        final entries = Map<String, dynamic>.from(indexData['entries'] as Map);
        for (final entry in entries.entries) {
          if (entry.value is! Map) {
            skippedEntries++;
            continue;
          }
          final metadata = CacheMetadata.tryFromJson(
            Map<String, dynamic>.from(
              (entry.value as Map).cast<String, dynamic>(),
            ),
          );
          if (metadata == null) {
            skippedEntries++;
            continue;
          }
          nextIndex[entry.key] = metadata;
        }

        _cacheIndex = nextIndex;
        _verifiedCacheChecksums.clear();
        final migrated = await _migrateLegacyCacheEntries();
        _logCacheDebug(
          '📑 [CacheService] 加载缓存索引: ${_cacheIndex.length} 条记录 '
          'source=${path.basename(candidate.path)} skipped=$skippedEntries',
        );
        if (candidate.path != indexPath || migrated || skippedEntries > 0) {
          await _saveCacheIndex();
        }
        return;
      } catch (e) {
        _logCacheDebug(
          '❌ [CacheService] 读取缓存索引候选失败: ${path.basename(candidate.path)}, $e',
        );
      }
    }

    _logCacheDebug('📑 [CacheService] 未找到可用缓存索引，创建新索引');
    _cacheIndex = {};
    _verifiedCacheChecksums.clear();
  }

  /// 保存缓存索引
  Future<void> _saveCacheIndex() async {
    try {
      _indexSaveDebounce?.cancel();
      final entries = <String, dynamic>{};

      for (final entry in _cacheIndex.entries) {
        entries[entry.key] = entry.value.toJson();
      }

      final jsonString = jsonEncode(<String, dynamic>{
        'schemaVersion': _manifestSchemaVersion,
        'entries': entries,
      });
      final jsonBytes = utf8.encode(jsonString);
      await _writeBytesAtomically(_getCacheIndexPath(), jsonBytes);
      _logCacheDebug('💾 [CacheService] 保存缓存清单: ${_cacheIndex.length} 条记录');
    } catch (e) {
      _logCacheDebug('❌ [CacheService] 保存缓存索引失败: $e');
    }
  }

  /// 获取缓存统计信息
  Future<CacheStats> getCacheStats() async {
    int totalSize = 0;
    int neteaseCount = 0;
    int appleCount = 0;
    int qqCount = 0;
    int kugouCount = 0;
    int kuwoCount = 0;

    for (final metadata in _cacheIndex.values) {
      totalSize += metadata.fileSize;

      switch (metadata.source) {
        case 'netease':
          neteaseCount++;
          break;
        case 'apple':
          appleCount++;
          break;
        case 'qq':
          qqCount++;
          break;
        case 'kugou':
          kugouCount++;
          break;
        case 'kuwo':
          kuwoCount++;
          break;
      }
    }

    return CacheStats(
      totalFiles: _cacheIndex.length,
      totalSize: totalSize,
      neteaseCount: neteaseCount,
      appleCount: appleCount,
      qqCount: qqCount,
      kugouCount: kugouCount,
      kuwoCount: kuwoCount,
    );
  }

  /// 清除所有缓存
  Future<void> clearAllCache() async {
    if (!_isInitialized) return;

    try {
      _logCacheDebug('🗑️ [CacheService] 清除所有缓存...');

      // 删除所有缓存文件
      final stagingDir = Directory(path.join(_cacheDir!.path, 'staging'));
      if (await stagingDir.exists()) await stagingDir.delete(recursive: true);
      await stagingDir.create(recursive: true);

      final removableKeys = _cacheIndex.keys.toList(growable: false);
      for (final key in removableKeys) {
        await _removeCacheEntry(key);
      }
      _verifiedCacheChecksums.clear();
      await _saveCacheIndex();

      _logCacheDebug('✅ [CacheService] 缓存已清除');
      notifyListeners();
    } catch (e) {
      _logCacheDebug('❌ [CacheService] 清除缓存失败: $e');
    }
  }

  /// 删除单个缓存
  Future<void> deleteCache(Track track, {String? quality}) async {
    if (!_isInitialized) return;

    try {
      final cacheKeys = _matchingCacheKeysForTrack(track, quality: quality);
      if (cacheKeys.isEmpty) {
        return;
      }

      for (final cacheKey in cacheKeys) {
        final metadata = _cacheIndex[cacheKey];
        if (metadata == null) continue;
        final cacheFilePath = _getCacheFilePath(cacheKey, metadata);
        try {
          await _removeCacheEntry(cacheKey);
        } catch (e) {
          _logCacheDebug(
            '⚠️ [CacheService] 删除缓存文件失败，将仅移除索引: $cacheFilePath, $e',
          );
        }
      }

      await _saveCacheIndex();

      _logCacheDebug('🗑️ [CacheService] 删除缓存: ${track.name}');
      notifyListeners();
    } catch (e) {
      _logCacheDebug('❌ [CacheService] 删除缓存失败: $e');
    }
  }

  /// 获取缓存列表
  List<CacheMetadata> getCachedList() {
    return _cacheIndex.values.toList()
      ..sort((a, b) => b.lastAccessedAt.compareTo(a.lastAccessedAt));
  }

  /// 清理临时文件
  Future<void> cleanTempFiles() async {
    try {
      final tempDir = await getTemporaryDirectory();
      final files = await tempDir.list().toList();

      for (final file in files) {
        if (file is File && file.path.contains('temp_')) {
          final isAudioTemp =
              file.path.endsWith('.mp3') || file.path.endsWith('.flac');
          if (isAudioTemp) {
            try {
              await file.delete();
            } catch (e) {
              // 忽略删除失败的文件
            }
          }
        }
      }

      _logCacheDebug('🧹 [CacheService] 清理临时文件完成');
    } catch (e) {
      _logCacheDebug('⚠️ [CacheService] 清理临时文件失败: $e');
    }
  }

  /// 加载缓存设置
  Future<void> _loadSettings() async {
    try {
      final prefs = await SharedPreferences.getInstance();

      // 加载缓存开关状态（默认关闭，保持用户显式开启，避免隐式消耗流量）
      _cacheEnabled = prefs.getBool('cache_enabled') ?? false;

      // 加载自定义缓存目录
      _customCacheDir = prefs.getString('custom_cache_dir');
      _maxCacheSizeBytes = await _loadStoredMaxCacheSizeBytes(prefs);

      _logCacheDebug(
        '⚙️ [CacheService] 加载设置 - '
        '缓存开关: $_cacheEnabled, '
        '自定义目录: ${_customCacheDir ?? "无"}, '
        '空间上限: ${formatFileSize(_maxCacheSizeBytes)}',
      );
    } catch (e) {
      _logCacheDebug('❌ [CacheService] 加载设置失败: $e');
      _cacheEnabled = false; // 加载失败时保守关闭，防止异常导致意外消耗流量
      _customCacheDir = null;
      _maxCacheSizeBytes = _defaultMaxCacheSizeBytes;
    }
  }

  /// 保存缓存开关状态
  Future<void> _saveCacheEnabled() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('cache_enabled', _cacheEnabled);
      _logCacheDebug('💾 [CacheService] 缓存开关已保存: $_cacheEnabled');
    } catch (e) {
      _logCacheDebug('❌ [CacheService] 保存缓存开关失败: $e');
    }
  }

  /// 保存自定义缓存目录
  Future<void> _saveCustomCacheDir() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (_customCacheDir != null && _customCacheDir!.isNotEmpty) {
        await prefs.setString('custom_cache_dir', _customCacheDir!);
        _logCacheDebug('💾 [CacheService] 自定义目录已保存: $_customCacheDir');
      } else {
        await prefs.remove('custom_cache_dir');
        _logCacheDebug('💾 [CacheService] 已清除自定义目录');
      }
    } catch (e) {
      _logCacheDebug('❌ [CacheService] 保存自定义目录失败: $e');
    }
  }

  int _normalizedMaxCacheSizeBytes(int? bytes) {
    if (bytes == null || bytes <= 0) {
      return _defaultMaxCacheSizeBytes;
    }
    return bytes;
  }

  Future<int> _loadStoredMaxCacheSizeBytes(SharedPreferences prefs) async {
    final stored = prefs.getString(_maxCacheSizePrefsKey);
    final parsed = int.tryParse(stored ?? '');
    if (parsed != null && parsed > 0) {
      return _normalizedMaxCacheSizeBytes(parsed);
    }

    final legacy = prefs.getInt(_legacyMaxCacheSizePrefsKey);
    final normalized = _normalizedMaxCacheSizeBytes(legacy);
    if (legacy != null && legacy > 0) {
      await prefs.setString(_maxCacheSizePrefsKey, normalized.toString());
    }
    return normalized;
  }

  /// 保存缓存空间上限
  Future<void> _saveMaxCacheSizeBytes() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        _maxCacheSizePrefsKey,
        _maxCacheSizeBytes.toString(),
      );
      await prefs.remove(_legacyMaxCacheSizePrefsKey);
      _logCacheDebug(
        '💾 [CacheService] 缓存空间上限已保存: '
        '${formatFileSize(_maxCacheSizeBytes)} ($_maxCacheSizeBytes bytes)',
      );
    } catch (e) {
      _logCacheDebug('❌ [CacheService] 保存缓存空间上限失败: $e');
    }
  }

  /// 设置缓存开关
  Future<void> setCacheEnabled(bool enabled) async {
    if (_cacheEnabled != enabled) {
      _cacheEnabled = enabled;
      await _saveCacheEnabled();
      _logCacheDebug('🔧 [CacheService] 缓存功能${enabled ? "已启用" : "已禁用"}');
      if (enabled) {
        _scheduleMaintenance();
      }
      notifyListeners();
    }
  }

  /// 设置缓存空间上限
  Future<void> setMaxCacheSizeBytes(int bytes) async {
    final normalizedBytes = _normalizedMaxCacheSizeBytes(bytes);
    if (_maxCacheSizeBytes == normalizedBytes) {
      return;
    }

    _maxCacheSizeBytes = normalizedBytes;
    await _saveMaxCacheSizeBytes();
    _logCacheDebug(
      '🔧 [CacheService] 缓存空间上限已更新: '
      '${formatFileSize(_maxCacheSizeBytes)} ($_maxCacheSizeBytes bytes)',
    );
    notifyListeners();

    if (_isInitialized && _cacheDir != null) {
      if (_maintenanceRunning) {
        _scheduleMaintenance();
      } else {
        await _runMaintenance();
      }
    }
  }

  /// 设置自定义缓存目录
  Future<bool> setCustomCacheDir(String? dirPath) async {
    try {
      // 验证目录
      if (dirPath != null && dirPath.isNotEmpty) {
        final dir = Directory(dirPath);

        // 检查目录是否存在或可创建
        if (!await dir.exists()) {
          await dir.create(recursive: true);
        }

        // 测试是否可写
        final testFile = File('${dir.path}/.test');
        await testFile.writeAsString('test');
        await testFile.delete();

        _customCacheDir = dirPath;
        _logCacheDebug('✅ [CacheService] 自定义目录验证成功: $dirPath');
      } else {
        _customCacheDir = null;
        _logCacheDebug('ℹ️ [CacheService] 清除自定义目录，使用默认目录');
      }

      await _saveCustomCacheDir();

      // 提示需要重启应用
      _logCacheDebug('⚠️ [CacheService] 目录更改已保存，需要重启应用才能生效');
      _logCacheDebug('ℹ️ [CacheService] 当前缓存目录: ${_cacheDir?.path}');
      _logCacheDebug('ℹ️ [CacheService] 新目录将在重启后使用: ${dirPath ?? "默认目录"}');
      notifyListeners();

      return true;
    } catch (e) {
      _logCacheDebug('❌ [CacheService] 设置自定义目录失败: $e');
      return false;
    }
  }

  /// 获取默认缓存目录路径
  Future<String> getDefaultCacheDir() async {
    if (Platform.isWindows) {
      final appDir = await getApplicationSupportDirectory();
      return path.join(appDir.path, 'music_cache');
    } else {
      final appDir = await getApplicationDocumentsDirectory();
      return '${appDir.path}/music_cache';
    }
  }
}
