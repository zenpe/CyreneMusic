import 'dart:async';
import 'dart:io';
import 'dart:convert';
import 'dart:typed_data';
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
  final String lyric;
  final String tlyric;
  final String yrc;
  final String ytlrc;
  final String qrc;
  final String qrcTrans;

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
    required this.lyric,
    required this.tlyric,
    this.yrc = '',
    this.ytlrc = '',
    this.qrc = '',
    this.qrcTrans = '',
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
    if (songId == null ||
        songName == null ||
        artists == null ||
        source == null ||
        fileSize == null ||
        cachedAt == null ||
        checksum == null) {
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
      lyric: _readOptionalString(json['lyric']),
      tlyric: _readOptionalString(json['tlyric']),
      yrc: _readOptionalString(json['yrc']),
      ytlrc: _readOptionalString(json['ytlrc']),
      qrc: _readOptionalString(json['qrc']),
      qrcTrans: _readOptionalString(json['qrcTrans']),
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
      'lyric': lyric,
      'tlyric': tlyric,
      'yrc': yrc,
      'ytlrc': ytlrc,
      'qrc': qrc,
      'qrcTrans': qrcTrans,
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
    String? lyric,
    String? tlyric,
    String? yrc,
    String? ytlrc,
    String? qrc,
    String? qrcTrans,
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
      lyric: lyric ?? this.lyric,
      tlyric: tlyric ?? this.tlyric,
      yrc: yrc ?? this.yrc,
      ytlrc: ytlrc ?? this.ytlrc,
      qrc: qrc ?? this.qrc,
      qrcTrans: qrcTrans ?? this.qrcTrans,
    );
  }
}

class _ResolvedCacheEntry {
  final String key;
  final CacheMetadata metadata;

  const _ResolvedCacheEntry({
    required this.key,
    required this.metadata,
  });
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

class _DownloadedCachePayload {
  final File encryptedPayloadFile;
  final int audioLength;
  final String checksum;

  const _DownloadedCachePayload({
    required this.encryptedPayloadFile,
    required this.audioLength,
    required this.checksum,
  });
}

class CyreneFileInfo {
  final String cacheKey;
  final String filePath;
  final CacheMetadata metadata;
  final int metadataLength;
  final int payloadOffset;
  final int audioLength;
  final String contentType;

  const CyreneFileInfo({
    required this.cacheKey,
    required this.filePath,
    required this.metadata,
    required this.metadataLength,
    required this.payloadOffset,
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

  // 加密密钥（用于简单的异或加密）
  static const String _encryptionKey = 'CyreneMusicCacheKey2025';
  static const int _defaultMaxCacheSizeBytes = 2 * 1024 * 1024 * 1024;
  static const Duration _maintenanceDebounce = Duration(seconds: 2);
  static const Duration _cacheDownloadTimeout = Duration(seconds: 30);
  static const String _maxCacheSizePrefsKey = 'max_cache_size_bytes_v2';
  static const String _legacyMaxCacheSizePrefsKey = 'max_cache_size_bytes';

  Directory? _cacheDir;
  Map<String, CacheMetadata> _cacheIndex = {};
  final Map<String, Future<bool>> _pendingCacheWrites = {};
  bool _isInitialized = false;
  bool _cacheEnabled = false;  // 缓存开关，默认关闭
  String? _customCacheDir;    // 自定义缓存目录
  int _maxCacheSizeBytes = _defaultMaxCacheSizeBytes;
  Timer? _indexSaveDebounce;
  Timer? _maintenanceTimer;
  bool _maintenanceRunning = false;
  final Map<String, String> _verifiedCacheChecksums = <String, String>{};

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

  static String _payloadPartPathFor(String targetPath) => '$targetPath.payload.part';

  static String _preferNonEmpty(String primary, String fallback) {
    return primary.isNotEmpty ? primary : fallback;
  }

  void _logCacheDebug(
    String message, {
    bool toDeveloperPanel = false,
  }) {
    print(message);
    if (toDeveloperPanel) {
      DeveloperModeService().addLog(message);
    }
  }

  /// 初始化缓存服务
  Future<void> initialize() async {
    if (_isInitialized) {
      print('ℹ️ [CacheService] 缓存服务已初始化，跳过');
      return;
    }

    try {
      print('💾 [CacheService] 开始初始化缓存服务...');

      // 加载缓存设置
      await _loadSettings();

      // 获取缓存目录
      if (_customCacheDir != null && _customCacheDir!.isNotEmpty) {
        // 使用自定义目录
        _cacheDir = Directory(_customCacheDir!);
        print('📂 [CacheService] 使用自定义目录: ${_customCacheDir!}');
      } else if (Platform.isWindows) {
        // Windows: 使用当前运行目录
        final executablePath = Platform.resolvedExecutable;
        final executableDir = path.dirname(executablePath);
        _cacheDir = Directory(path.join(executableDir, 'music_cache'));
        print('📂 [CacheService] 运行目录: $executableDir');
      } else {
        // 其他平台: 使用应用文档目录
        final appDir = await getApplicationDocumentsDirectory();
        _cacheDir = Directory('${appDir.path}/music_cache');
        print('📂 [CacheService] 应用文档目录: ${appDir.path}');
      }
      
      print('📂 [CacheService] 缓存目录路径: ${_cacheDir!.path}');
      print('🔧 [CacheService] 缓存开关状态: ${_cacheEnabled ? "已启用" : "已禁用"}');

      // 创建缓存目录
      if (!await _cacheDir!.exists()) {
        print('📁 [CacheService] 缓存目录不存在，创建中...');
        await _cacheDir!.create(recursive: true);
        print('✅ [CacheService] 缓存目录已创建: ${_cacheDir!.path}');
      } else {
        print('✅ [CacheService] 缓存目录已存在: ${_cacheDir!.path}');
      }

      // 验证目录是否可写
      try {
        final testFile = File('${_cacheDir!.path}/.test');
        await testFile.writeAsString('test');
        await testFile.delete();
        print('✅ [CacheService] 缓存目录可写');
      } catch (e) {
        print('❌ [CacheService] 缓存目录不可写: $e');
        throw Exception('缓存目录不可写');
      }

      await _recoverCacheFileSidecars();

      // 加载缓存索引
      await _loadCacheIndex();

      _isInitialized = true;
      notifyListeners();

      _scheduleMaintenance();

      print('✅ [CacheService] 缓存服务初始化完成！');
      print('📊 [CacheService] 已缓存歌曲数: ${_cacheIndex.length}');
      print('📁 [CacheService] 缓存位置: ${_cacheDir!.path}');
    } catch (e, stackTrace) {
      print('❌ [CacheService] 初始化失败: $e');
      print('❌ [CacheService] 错误堆栈: $stackTrace');
      _isInitialized = false;
    }
  }

  String _qualityKey([String? quality]) {
    return normalizeQualityValue(quality);
  }

  String _generateCacheKey(String songId, MusicSource source, [String? quality]) {
    return '${source.name}_${songId}_${_qualityKey(quality)}';
  }

  String _generateCacheKeyFromMetadata(CacheMetadata metadata) {
    return '${metadata.source}_${metadata.songId}_${_qualityKey(metadata.quality)}';
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

    final legacyKey = _generateLegacyCacheKey(track.id.toString(), track.source);
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
      return _ResolvedCacheEntry(
        key: key,
        metadata: metadata,
      );
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

      if (migrated || changedIndex || removedOrphans > 0 || trimmedEntries > 0) {
        await _saveCacheIndex();
        notifyListeners();
      }
    } catch (e) {
      print('❌ [CacheService] 缓存治理失败: $e');
    } finally {
      _maintenanceRunning = false;
    }
  }

  Future<bool> _migrateLegacyCacheEntries() async {
    if (_cacheDir == null || _cacheIndex.isEmpty) return false;

    final migratedIndex = <String, CacheMetadata>{};
    var changed = false;
    for (final entry in _cacheIndex.entries) {
      final metadata = _normalizeMetadata(entry.value);
      if (!identical(metadata, entry.value)) {
        changed = true;
      }
      final targetKey = _generateCacheKeyFromMetadata(metadata);
      final sourceKey = entry.key;
      final sourcePath = _getCacheFilePath(sourceKey);
      final targetPath = _getCacheFilePath(targetKey);

      if (sourceKey != targetKey) {
        changed = true;
        _forgetVerifiedChecksum(sourceKey);
        _forgetVerifiedChecksum(targetKey);
        final sourceFile = File(sourcePath);
        final targetFile = File(targetPath);
        var migrationFailed = false;
        if (await sourceFile.exists() && !await targetFile.exists()) {
          try {
            await sourceFile.rename(targetPath);
          } catch (renameError) {
            try {
              await sourceFile.copy(targetPath);
              await sourceFile.delete();
            } catch (copyError) {
              migrationFailed = true;
              print(
                '⚠️ [CacheService] 迁移旧缓存文件失败: $sourcePath -> $targetPath, '
                'rename=$renameError, copy=$copyError',
              );
            }
          }
        }
        if (migrationFailed) {
          final existing = migratedIndex[sourceKey];
          if (existing == null ||
              metadata.lastAccessedAt.isAfter(existing.lastAccessedAt)) {
            migratedIndex[sourceKey] = metadata;
          }
          continue;
        }
      }

      final existing = migratedIndex[targetKey];
      if (existing == null ||
          metadata.lastAccessedAt.isAfter(existing.lastAccessedAt)) {
        if (existing != null) {
          changed = true;
        }
        migratedIndex[targetKey] = metadata;
      }
    }

    if (!_sameCacheKeys(_cacheIndex, migratedIndex)) {
      changed = true;
    }
    _cacheIndex = migratedIndex;
    return changed;
  }

  bool _sameCacheKeys(
    Map<String, CacheMetadata> a,
    Map<String, CacheMetadata> b,
  ) {
    if (identical(a, b)) return true;
    if (a.length != b.length) return false;
    for (final key in a.keys) {
      if (!b.containsKey(key)) {
        return false;
      }
    }
    return true;
  }

  Future<bool> _removeMissingIndexedFiles() async {
    if (_cacheDir == null || _cacheIndex.isEmpty) return false;
    final keysToRemove = <String>[];
    for (final entry in _cacheIndex.entries) {
      final file = File(_getCacheFilePath(entry.key));
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
    final expectedPaths = _cacheIndex.keys
        .map(_getCacheFilePath)
        .map(path.normalize)
        .toSet();
    var removed = 0;
    await for (final entity in _cacheDir!.list()) {
      if (entity is! File) continue;
      if (!entity.path.endsWith('.cyrene')) continue;
      if (path.basename(entity.path) == 'cache_index.cyrene') continue;
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
      final file = File(_getCacheFilePath(entry.key));
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
      final cacheFilePath = _getCacheFilePath(entry.key);
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
  String _getCacheFilePath(String cacheKey) {
    return path.join(_cacheDir!.path, '$cacheKey.cyrene');
  }

  String _getCacheIndexPath() {
    return path.join(_cacheDir!.path, 'cache_index.cyrene');
  }

  static String _contentTypeForQuality(String quality) {
    final extension = AudioQualityService.getExtensionFromLevel(quality);
    switch (extension) {
      case 'flac':
        return 'audio/flac';
      case 'mp3':
      default:
        return 'audio/mpeg';
    }
  }

  static Uint8List decryptAudioBytes(
    List<int> encryptedData, {
    int startOffset = 0,
  }) {
    final keyBytes = utf8.encode(_encryptionKey);
    final decrypted = Uint8List(encryptedData.length);

    for (int i = 0; i < encryptedData.length; i++) {
      decrypted[i] =
          encryptedData[i] ^ keyBytes[(startOffset + i) % keyBytes.length];
    }

    return decrypted;
  }

  /// 加密数据（简单的异或加密，防止直接播放）
  Uint8List _encryptData(Uint8List data) {
    return decryptAudioBytes(data);
  }

  /// 解密数据
  Uint8List _decryptData(
    Uint8List encryptedData, {
    int startOffset = 0,
  }) {
    // 异或加密是对称的，加密和解密使用相同的方法
    return decryptAudioBytes(encryptedData, startOffset: startOffset);
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

  Future<void> _writeBytesAtomically(
    String targetPath,
    List<int> bytes,
  ) async {
    final tempFile = File(_partPathFor(targetPath));
    await _deleteFileIfExists(tempFile);
    await tempFile.writeAsBytes(bytes, flush: true);
    await _promotePreparedTempFile(
      tempFile: tempFile,
      targetFile: File(targetPath),
    );
  }

  Future<_DownloadedCachePayload?> _downloadEncryptedPayload(
    Track track,
    SongDetail songDetail,
    String cacheKey,
  ) async {
    final client = http.Client();
    final payloadTempFile = File('${_getCacheFilePath(cacheKey)}.payload.part');
    await _deleteFileIfExists(payloadTempFile);

    IOSink? sink;
    try {
      final request = http.Request('GET', Uri.parse(songDetail.url))
        ..headers.addAll(buildAudioRequestHeaders(track.source));
      final response = await client.send(request).timeout(_cacheDownloadTimeout);
      if (response.statusCode != 200) {
        _logCacheDebug(
          '❌ [CacheService] 缓存下载失败: HTTP ${response.statusCode} '
          'track=${track.name} url=${songDetail.url}',
          toDeveloperPanel: true,
        );
        return null;
      }

      final digestSink = _DigestCaptureSink();
      final md5Sink = md5.startChunkedConversion(digestSink);
      sink = payloadTempFile.openWrite();

      var audioLength = 0;
      var chunkOffset = 0;
      await for (final chunk in response.stream.timeout(_cacheDownloadTimeout)) {
        audioLength += chunk.length;
        md5Sink.add(chunk);
        sink.add(decryptAudioBytes(chunk, startOffset: chunkOffset));
        chunkOffset += chunk.length;
      }

      md5Sink.close();
      await sink.flush();
      await sink.close();
      sink = null;

      _logCacheDebug(
        '📥 [CacheService] 下载完成: $audioLength bytes key=$cacheKey',
        toDeveloperPanel: true,
      );

      return _DownloadedCachePayload(
        encryptedPayloadFile: payloadTempFile,
        audioLength: audioLength,
        checksum: digestSink.value?.toString() ?? '',
      );
    } catch (e) {
      await _deleteFileIfExists(payloadTempFile);
      rethrow;
    } finally {
      client.close();
      if (sink != null) {
        try {
          await sink.flush();
          await sink.close();
        } catch (_) {}
      }
    }
  }

  Future<void> _writeCyreneContainer(
    String cacheKey, {
    required CacheMetadata metadata,
    required File encryptedPayloadFile,
  }) async {
    final metadataJson = jsonEncode(metadata.toJson());
    final metadataBytes = utf8.encode(metadataJson);
    final metadataLength = metadataBytes.length;
    final cacheFilePath = _getCacheFilePath(cacheKey);
    final tempFile = File(_partPathFor(cacheFilePath));
    await _deleteFileIfExists(tempFile);

    final sink = tempFile.openWrite();
    try {
      sink.add(<int>[
        (metadataLength >> 24) & 0xFF,
        (metadataLength >> 16) & 0xFF,
        (metadataLength >> 8) & 0xFF,
        metadataLength & 0xFF,
      ]);
      sink.add(metadataBytes);
      await sink.addStream(encryptedPayloadFile.openRead());
      await sink.flush();
      await sink.close();

      await _promotePreparedTempFile(
        tempFile: tempFile,
        targetFile: File(cacheFilePath),
      );

      _logCacheDebug('🔒 [CacheService] 保存缓存文件: $cacheFilePath');
      _logCacheDebug(
        '📊 [CacheService] 文件大小: ${metadata.fileSize + metadataLength + 4} bytes '
        '(元数据: $metadataLength bytes)',
      );
    } catch (e) {
      try {
        await sink.flush();
        await sink.close();
      } catch (_) {}
      rethrow;
    } finally {
      await _deleteFileIfExists(encryptedPayloadFile);
      await _deleteFileIfExists(tempFile);
    }
  }

  Future<void> _verifyCachedPayloadChecksum({
    required String cacheKey,
    required CacheMetadata metadata,
    required RandomAccessFile raf,
    required int payloadOffset,
    required int audioLength,
  }) async {
    if (_verifiedCacheChecksums[cacheKey] == metadata.checksum) {
      return;
    }
    if (metadata.fileSize != audioLength) {
      throw Exception(
        '缓存音频长度不匹配: metadata=${metadata.fileSize}, actual=$audioLength',
      );
    }

    final digestSink = _DigestCaptureSink();
    final md5Sink = md5.startChunkedConversion(digestSink);
    await raf.setPosition(payloadOffset);

    var remaining = audioLength;
    var chunkOffset = 0;
    while (remaining > 0) {
      final chunkSize = remaining > 64 * 1024 ? 64 * 1024 : remaining;
      final chunk = await raf.read(chunkSize);
      if (chunk.isEmpty) {
        throw Exception('缓存 payload 提前结束');
      }
      md5Sink.add(decryptAudioBytes(chunk, startOffset: chunkOffset));
      chunkOffset += chunk.length;
      remaining -= chunk.length;
    }

    md5Sink.close();
    final actualChecksum = digestSink.value?.toString() ?? '';
    if (actualChecksum != metadata.checksum) {
      throw Exception(
        '缓存 checksum 不匹配: expected=${metadata.checksum}, actual=$actualChecksum',
      );
    }
    _verifiedCacheChecksums[cacheKey] = metadata.checksum;
  }

  Future<void> _recoverCacheFileSidecars() async {
    if (_cacheDir == null || !await _cacheDir!.exists()) return;

    final indexPath = _getCacheIndexPath();
    await for (final entity in _cacheDir!.list()) {
      if (entity is! File) continue;
      final filePath = entity.path;
      if (filePath == _backupPathFor(indexPath) ||
          filePath == _partPathFor(indexPath)) {
        continue;
      }

      if (filePath.endsWith('.payload.part')) {
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

      if (filePath.endsWith('.cyrene.part')) {
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

  /// 获取加密缓存容器文件路径（不解密）
  String? getCachedContainerFilePath(Track track, {String? quality}) {
    if (!_isInitialized || !_cacheEnabled || _cacheDir == null) return null;
    final resolved = _resolveCacheEntry(track, quality: quality);
    if (resolved == null) return null;
    return _getCacheFilePath(resolved.key);
  }

  CacheMetadata _buildCacheMetadata(
    Track track,
    SongDetail songDetail, {
    required String normalizedQuality,
    required int fileSize,
    required DateTime cachedAt,
    required DateTime lastAccessedAt,
    required String checksum,
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
      lyric: songDetail.lyric,
      tlyric: songDetail.tlyric,
      yrc: songDetail.yrc,
      ytlrc: songDetail.ytlrc,
      qrc: songDetail.qrc,
      qrcTrans: songDetail.qrcTrans,
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
      lyric: _preferNonEmpty(songDetail.lyric, existing.lyric),
      tlyric: _preferNonEmpty(songDetail.tlyric, existing.tlyric),
      yrc: _preferNonEmpty(songDetail.yrc, existing.yrc),
      ytlrc: _preferNonEmpty(songDetail.ytlrc, existing.ytlrc),
      qrc: _preferNonEmpty(songDetail.qrc, existing.qrc),
      qrcTrans: _preferNonEmpty(songDetail.qrcTrans, existing.qrcTrans),
    );
  }

  bool _isSameCacheMetadataPayload(CacheMetadata a, CacheMetadata b) {
    return a.songName == b.songName &&
        a.artists == b.artists &&
        a.album == b.album &&
        a.picUrl == b.picUrl &&
        a.quality == b.quality &&
        a.originalUrl == b.originalUrl &&
        a.lyric == b.lyric &&
        a.tlyric == b.tlyric &&
        a.yrc == b.yrc &&
        a.ytlrc == b.ytlrc &&
        a.qrc == b.qrc &&
        a.qrcTrans == b.qrcTrans;
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
      print('ℹ️ [CacheService] 歌曲已缓存: ${track.name}');
      return true;
    }

    _cacheIndex[cacheKey] = updated;
    await _saveCacheIndex();
    print('📝 [CacheService] 更新缓存元数据: ${track.name}');
    notifyListeners();
    return true;
  }

  Future<CyreneFileInfo?> getCyreneFileInfo(
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
      print(
        '⚠️ [CacheService] 缓存音质不匹配: ${resolved.metadata.quality} != $expectedQuality',
      );
      return null;
    }

    final cacheKey = resolved.key;
    final metadata = resolved.metadata;
    final cacheFilePath = _getCacheFilePath(cacheKey);
    final cacheFile = File(cacheFilePath);

    if (!await cacheFile.exists()) {
      print('⚠️ [CacheService] 缓存文件不存在: $cacheFilePath');
      await _deleteCacheArtifacts(cacheFilePath);
      _cacheIndex.remove(cacheKey);
      _forgetVerifiedChecksum(cacheKey);
      await _saveCacheIndex();
      return null;
    }

    RandomAccessFile? raf;
    try {
      raf = await cacheFile.open(mode: FileMode.read);
      final header = await raf.read(4);
      if (header.length < 4) {
        throw Exception('文件格式错误');
      }

      final metadataLength = (header[0] << 24) |
          (header[1] << 16) |
          (header[2] << 8) |
          header[3];
      final totalLength = await raf.length();
      final payloadOffset = 4 + metadataLength;
      final audioLength = totalLength - payloadOffset;

      if (metadataLength <= 0 ||
          payloadOffset <= 4 ||
          payloadOffset > totalLength ||
          audioLength <= 0) {
        throw Exception('文件格式错误');
      }

      await _verifyCachedPayloadChecksum(
        cacheKey: cacheKey,
        metadata: metadata,
        raf: raf,
        payloadOffset: payloadOffset,
        audioLength: audioLength,
      );
      _touchCacheEntry(cacheKey, metadata);

      return CyreneFileInfo(
        cacheKey: cacheKey,
        filePath: cacheFilePath,
        metadata: metadata,
        metadataLength: metadataLength,
        payloadOffset: payloadOffset,
        audioLength: audioLength,
        contentType: _contentTypeForQuality(metadata.quality),
      );
    } catch (e) {
      print('❌ [CacheService] 读取缓存容器信息失败: $e');
      try {
        await raf?.close();
      } catch (_) {}
      raf = null;
      await _deleteCacheArtifacts(cacheFilePath);
      _cacheIndex.remove(cacheKey);
      _forgetVerifiedChecksum(cacheKey);
      await _saveCacheIndex();
      return null;
    } finally {
      await raf?.close();
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

      final downloadedPayload = await _downloadEncryptedPayload(
        track,
        songDetail,
        cacheKey,
      );
      if (downloadedPayload == null) {
        return false;
      }

      final now = DateTime.now();
      final metadata = _buildCacheMetadata(
        track,
        songDetail,
        normalizedQuality: normalizedQuality,
        fileSize: downloadedPayload.audioLength,
        cachedAt: now,
        lastAccessedAt: now,
        checksum: downloadedPayload.checksum,
      );

      _forgetVerifiedChecksum(cacheKey);
      await _writeCyreneContainer(
        cacheKey,
        metadata: metadata,
        encryptedPayloadFile: downloadedPayload.encryptedPayloadFile,
      );

      _cacheIndex[cacheKey] = metadata;
      await _saveCacheIndex();
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
        final encryptedData = await candidate.readAsBytes();
        final decryptedData = _decryptData(encryptedData);
        final indexJson = utf8.decode(decryptedData);
        final indexData = jsonDecode(indexJson);
        if (indexData is! Map<String, dynamic>) {
          throw const FormatException('cache index payload is not a map');
        }

        final nextIndex = <String, CacheMetadata>{};
        var skippedEntries = 0;
        for (final entry in indexData.entries) {
          if (entry.value is! Map) {
            skippedEntries++;
            continue;
          }
          final metadata = CacheMetadata.tryFromJson(
            Map<String, dynamic>.from((entry.value as Map).cast<String, dynamic>()),
          );
          if (metadata == null) {
            skippedEntries++;
            continue;
          }
          nextIndex[entry.key] = metadata;
        }

        _cacheIndex = nextIndex;
        _verifiedCacheChecksums.clear();
        print(
          '📑 [CacheService] 加载缓存索引: ${_cacheIndex.length} 条记录 '
          'source=${path.basename(candidate.path)} skipped=$skippedEntries',
        );
        if (candidate.path != indexPath) {
          await _saveCacheIndex();
        }
        return;
      } catch (e) {
        print(
          '❌ [CacheService] 读取缓存索引候选失败: ${path.basename(candidate.path)}, $e',
        );
      }
    }

    print('📑 [CacheService] 未找到可用缓存索引，创建新索引');
    _cacheIndex = {};
    _verifiedCacheChecksums.clear();
  }

  /// 保存缓存索引
  Future<void> _saveCacheIndex() async {
    try {
      _indexSaveDebounce?.cancel();
      final indexData = <String, dynamic>{};

      for (final entry in _cacheIndex.entries) {
        indexData[entry.key] = entry.value.toJson();
      }

      // 转换为 JSON 字符串
      final jsonString = jsonEncode(indexData);
      final jsonBytes = utf8.encode(jsonString);
      
      // 加密索引数据
      final encryptedData = _encryptData(jsonBytes);
      
      // 保存加密后的索引文件
      await _writeBytesAtomically(_getCacheIndexPath(), encryptedData);
      print('💾 [CacheService] 保存加密的缓存索引: ${_cacheIndex.length} 条记录');
    } catch (e) {
      print('❌ [CacheService] 保存缓存索引失败: $e');
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
      print('🗑️ [CacheService] 清除所有缓存...');

      // 删除所有缓存文件
      final files = await _cacheDir!.list().toList();
      for (final file in files) {
        if (file is File) {
          await file.delete();
        }
      }

      // 清空索引
      _cacheIndex.clear();
      _verifiedCacheChecksums.clear();
      await _saveCacheIndex();

      print('✅ [CacheService] 缓存已清除');
      notifyListeners();
    } catch (e) {
      print('❌ [CacheService] 清除缓存失败: $e');
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
        final cacheFilePath = _getCacheFilePath(cacheKey);
        try {
          await _deleteCacheArtifacts(cacheFilePath);
        } catch (e) {
          print('⚠️ [CacheService] 删除缓存文件失败，将仅移除索引: $cacheFilePath, $e');
        }
        _cacheIndex.remove(cacheKey);
        _forgetVerifiedChecksum(cacheKey);
      }

      await _saveCacheIndex();

      print('🗑️ [CacheService] 删除缓存: ${track.name}');
      notifyListeners();
    } catch (e) {
      print('❌ [CacheService] 删除缓存失败: $e');
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
          final isAudioTemp = file.path.endsWith('.mp3') || file.path.endsWith('.flac');
          if (isAudioTemp) {
            try {
              await file.delete();
            } catch (e) {
              // 忽略删除失败的文件
            }
          }
        }
      }

      print('🧹 [CacheService] 清理临时文件完成');
    } catch (e) {
      print('⚠️ [CacheService] 清理临时文件失败: $e');
    }
  }

  /// 加载缓存设置
  Future<void> _loadSettings() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      
      // 加载缓存开关状态（默认关闭）
      _cacheEnabled = prefs.getBool('cache_enabled') ?? false;
      
      // 加载自定义缓存目录
      _customCacheDir = prefs.getString('custom_cache_dir');
      _maxCacheSizeBytes = await _loadStoredMaxCacheSizeBytes(prefs);
      
      print(
        '⚙️ [CacheService] 加载设置 - '
        '缓存开关: $_cacheEnabled, '
        '自定义目录: ${_customCacheDir ?? "无"}, '
        '空间上限: ${formatFileSize(_maxCacheSizeBytes)}',
      );
    } catch (e) {
      print('❌ [CacheService] 加载设置失败: $e');
      _cacheEnabled = false;  // 加载失败时默认关闭
      _customCacheDir = null;
      _maxCacheSizeBytes = _defaultMaxCacheSizeBytes;
    }
  }

  /// 保存缓存开关状态
  Future<void> _saveCacheEnabled() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('cache_enabled', _cacheEnabled);
      print('💾 [CacheService] 缓存开关已保存: $_cacheEnabled');
    } catch (e) {
      print('❌ [CacheService] 保存缓存开关失败: $e');
    }
  }

  /// 保存自定义缓存目录
  Future<void> _saveCustomCacheDir() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (_customCacheDir != null && _customCacheDir!.isNotEmpty) {
        await prefs.setString('custom_cache_dir', _customCacheDir!);
        print('💾 [CacheService] 自定义目录已保存: $_customCacheDir');
      } else {
        await prefs.remove('custom_cache_dir');
        print('💾 [CacheService] 已清除自定义目录');
      }
    } catch (e) {
      print('❌ [CacheService] 保存自定义目录失败: $e');
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
      await prefs.setString(_maxCacheSizePrefsKey, _maxCacheSizeBytes.toString());
      await prefs.remove(_legacyMaxCacheSizePrefsKey);
      print(
        '💾 [CacheService] 缓存空间上限已保存: '
        '${formatFileSize(_maxCacheSizeBytes)} ($_maxCacheSizeBytes bytes)',
      );
    } catch (e) {
      print('❌ [CacheService] 保存缓存空间上限失败: $e');
    }
  }

  /// 设置缓存开关
  Future<void> setCacheEnabled(bool enabled) async {
    if (_cacheEnabled != enabled) {
      _cacheEnabled = enabled;
      await _saveCacheEnabled();
      print('🔧 [CacheService] 缓存功能${enabled ? "已启用" : "已禁用"}');
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
    print(
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
        print('✅ [CacheService] 自定义目录验证成功: $dirPath');
      } else {
        _customCacheDir = null;
        print('ℹ️ [CacheService] 清除自定义目录，使用默认目录');
      }
      
      await _saveCustomCacheDir();
      
      // 提示需要重启应用
      print('⚠️ [CacheService] 目录更改已保存，需要重启应用才能生效');
      print('ℹ️ [CacheService] 当前缓存目录: ${_cacheDir?.path}');
      print('ℹ️ [CacheService] 新目录将在重启后使用: ${dirPath ?? "默认目录"}');
      notifyListeners();
      
      return true;
    } catch (e) {
      print('❌ [CacheService] 设置自定义目录失败: $e');
      return false;
    }
  }

  /// 获取默认缓存目录路径
  Future<String> getDefaultCacheDir() async {
    if (Platform.isWindows) {
      final executablePath = Platform.resolvedExecutable;
      final executableDir = path.dirname(executablePath);
      return path.join(executableDir, 'music_cache');
    } else {
      final appDir = await getApplicationDocumentsDirectory();
      return '${appDir.path}/music_cache';
    }
  }
}
