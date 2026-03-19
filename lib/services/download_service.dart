import 'dart:io';
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;
import '../models/track.dart';
import '../models/song_detail.dart';
import 'cache_service.dart';
import 'notification_service.dart';
import 'audio_quality_service.dart';

/// 下载进度回调
typedef DownloadProgressCallback = void Function(double progress);

/// 下载任务
class DownloadTask {
  final Track track;
  final String fileName;
  double progress;
  bool isCompleted;
  bool isFailed;
  String? errorMessage;

  DownloadTask({
    required this.track,
    required this.fileName,
    this.progress = 0.0,
    this.isCompleted = false,
    this.isFailed = false,
    this.errorMessage,
  });

  String get trackId => '${track.source.name}_${track.id}';
}

/// 下载服务
class DownloadService extends ChangeNotifier {
  static final DownloadService _instance = DownloadService._internal();
  factory DownloadService() => _instance;
  DownloadService._internal() {
    _loadDownloadPath();
  }

  // 加密密钥（与 CacheService 保持一致）
  static const String _encryptionKey = 'CyreneMusicCacheKey2025';

  String? _downloadPath;
  final Map<String, DownloadTask> _downloadTasks = {};

  String? get downloadPath => _downloadPath;
  Map<String, DownloadTask> get downloadTasks => _downloadTasks;

  /// 加载下载路径
  Future<void> _loadDownloadPath() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _downloadPath = prefs.getString('download_path');

      // 如果没有设置下载路径，使用默认路径
      if (_downloadPath == null) {
        await _setDefaultDownloadPath();
      }

      print('📁 [DownloadService] 下载路径: $_downloadPath');
    } catch (e) {
      print('❌ [DownloadService] 加载下载路径失败: $e');
      await _setDefaultDownloadPath();
    }
    notifyListeners();
  }

  /// 设置默认下载路径
  Future<void> _setDefaultDownloadPath() async {
    try {
      if (Platform.isAndroid) {
        // Android: /storage/emulated/0/Download/Cyrene_Music
        final downloadsDir = Directory('/storage/emulated/0/Download');
        final appDownloadDir = Directory('${downloadsDir.path}/Cyrene_Music');

        if (!await appDownloadDir.exists()) {
          await appDownloadDir.create(recursive: true);
          print('✅ [DownloadService] 创建 Android 下载目录: ${appDownloadDir.path}');
        }

        _downloadPath = appDownloadDir.path;
      } else if (Platform.isWindows) {
        // Windows: 用户文档/Music/Cyrene_Music
        final documentsDir = await getApplicationDocumentsDirectory();
        final musicDir = Directory('${documentsDir.parent.path}\\Music\\Cyrene_Music');

        if (!await musicDir.exists()) {
          await musicDir.create(recursive: true);
          print('✅ [DownloadService] 创建 Windows 下载目录: ${musicDir.path}');
        }

        _downloadPath = musicDir.path;
      } else {
        // 其他平台：使用文档目录
        final documentsDir = await getApplicationDocumentsDirectory();
        final appDownloadDir = Directory('${documentsDir.path}/Cyrene_Music');

        if (!await appDownloadDir.exists()) {
          await appDownloadDir.create(recursive: true);
        }

        _downloadPath = appDownloadDir.path;
      }

      // 保存到偏好设置
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('download_path', _downloadPath!);
    } catch (e) {
      print('❌ [DownloadService] 设置默认下载路径失败: $e');
    }
  }

  /// 设置下载路径（Windows 用户自定义）
  Future<bool> setDownloadPath(String path) async {
    try {
      final dir = Directory(path);

      // 检查目录是否存在，不存在则创建
      if (!await dir.exists()) {
        await dir.create(recursive: true);
      }

      // 验证目录是否可写
      final testFile = File('${dir.path}${Platform.pathSeparator}.test');
      await testFile.writeAsString('test');
      await testFile.delete();

      _downloadPath = path;

      // 保存到偏好设置
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('download_path', path);

      print('✅ [DownloadService] 下载路径已更新: $path');
      notifyListeners();
      return true;
    } catch (e) {
      print('❌ [DownloadService] 设置下载路径失败: $e');
      return false;
    }
  }

  /// 解密缓存数据
  Uint8List _decryptData(Uint8List encryptedData) {
    final keyBytes = utf8.encode(_encryptionKey);
    final decrypted = Uint8List(encryptedData.length);

    for (int i = 0; i < encryptedData.length; i++) {
      decrypted[i] = encryptedData[i] ^ keyBytes[i % keyBytes.length];
    }

    return decrypted;
  }

  /// 生成安全的文件名
  String _generateSafeFileName(Track track, [String? level]) {
    // 移除不安全的字符
    final safeName = '${track.name} - ${track.artists}'
        .replaceAll(RegExp(r'[\\/:*?"<>|]'), '_')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();

    final extension = AudioQualityService.getExtensionFromLevel(level);
    return '$safeName.$extension';
  }

  String _resolveCacheQualityKey(String? level) {
    final quality = (level != null && level.isNotEmpty)
        ? AudioQualityService.stringToQuality(level)
        : null;
    if (quality != null) {
      return quality.value;
    }
    if (level != null && level.isNotEmpty) {
      return level;
    }
    return AudioQuality.standard.value;
  }

  /// 从缓存下载（解密缓存文件）
  Future<bool> _downloadFromCache(
    Track track,
    String outputPath, {
    String? quality,
  }) async {
    try {
      print('📦 [DownloadService] 从缓存下载: ${track.name}');

      final cacheService = CacheService();
      final cacheQuality = _resolveCacheQualityKey(quality);
      final cacheFilePath = cacheService.getCachedContainerFilePath(
        track,
        quality: cacheQuality,
      );
      if (cacheFilePath == null) {
        print('⚠️ [DownloadService] 未找到匹配音质的缓存文件');
        return false;
      }
      final cacheFile = File(cacheFilePath);

      if (!await cacheFile.exists()) {
        print('⚠️ [DownloadService] 缓存文件不存在');
        return false;
      }

      // 读取 .cyrene 文件
      final fileData = await cacheFile.readAsBytes();

      // 读取元数据长度（前4字节）
      if (fileData.length < 4) {
        throw Exception('缓存文件格式错误');
      }

      final metadataLength = (fileData[0] << 24) |
          (fileData[1] << 16) |
          (fileData[2] << 8) |
          fileData[3];

      if (fileData.length < 4 + metadataLength) {
        throw Exception('缓存文件格式错误');
      }

      // 跳过元数据，读取加密的音频数据
      final encryptedAudioData = Uint8List.sublistView(
        fileData,
        (4 + metadataLength).toInt(),
      );

      // 解密音频数据
      final decryptedData = _decryptData(encryptedAudioData);

      // 保存到目标路径
      final outputFile = File(outputPath);
      await outputFile.writeAsBytes(decryptedData);

      print('✅ [DownloadService] 从缓存下载成功: $outputPath');
      return true;
    } catch (e) {
      print('❌ [DownloadService] 从缓存下载失败: $e');
      return false;
    }
  }

  /// 直接下载音频文件
  Future<bool> _downloadFromUrl(
    String url,
    String outputPath,
    DownloadProgressCallback? onProgress,
  ) async {
    try {
      print('🌐 [DownloadService] 从网络下载: $url');

      final request = http.Request('GET', Uri.parse(url));
      final response = await request.send();

      if (response.statusCode != 200) {
        throw Exception('HTTP ${response.statusCode}');
      }

      final contentLength = response.contentLength ?? 0;
      final outputFile = File(outputPath);
      final sink = outputFile.openWrite();

      int downloaded = 0;

      await for (final chunk in response.stream) {
        sink.add(chunk);
        downloaded += chunk.length;

        if (contentLength > 0 && onProgress != null) {
          final progress = downloaded / contentLength;
          onProgress(progress);
        }
      }

      await sink.close();

      print('✅ [DownloadService] 从网络下载成功: $outputPath');
      return true;
    } catch (e) {
      print('❌ [DownloadService] 从网络下载失败: $e');
      return false;
    }
  }

  /// 下载歌曲
  Future<bool> downloadSong(
    Track track,
    SongDetail songDetail, {
    DownloadProgressCallback? onProgress,
  }) async {
    if (_downloadPath == null) {
      print('❌ [DownloadService] 下载路径未设置');
      return false;
    }

    try {
      final fileName = _generateSafeFileName(track, songDetail.level);
      final outputPath = '$_downloadPath${Platform.pathSeparator}$fileName';
      final trackId = '${track.source.name}_${track.id}';

      // 检查文件是否已存在
      if (await File(outputPath).exists()) {
        print('⚠️ [DownloadService] 文件已存在: $outputPath');
        return false;
      }

      // 创建下载任务
      final task = DownloadTask(track: track, fileName: fileName);
      _downloadTasks[trackId] = task;
      notifyListeners();

      print('🎵 [DownloadService] 开始下载: ${track.name}');

      bool success = false;

      // 优先从缓存下载
      final cacheQuality = _resolveCacheQualityKey(songDetail.level);
      if (CacheService().isCached(track, quality: cacheQuality)) {
        print('📦 [DownloadService] 尝试从缓存下载');
        success = await _downloadFromCache(
          track,
          outputPath,
          quality: cacheQuality,
        );
      }

      // 如果缓存下载失败或没有缓存，从网络下载
      if (!success) {
        print('🌐 [DownloadService] 从网络下载');
        success = await _downloadFromUrl(
          songDetail.url,
          outputPath,
          (progress) {
            task.progress = progress;
            notifyListeners();
            onProgress?.call(progress);
          },
        );
      }

      // 更新任务状态
      if (success) {
        task.isCompleted = true;
        task.progress = 1.0;
        print('✅ [DownloadService] 下载完成: $fileName');
        
        // 启动元数据嵌入服务 (封面 & 歌词)
        final coverUrl = songDetail.pic.isNotEmpty ? songDetail.pic : track.picUrl;
        await _embedMetadata(
          outputPath,
          coverUrl: coverUrl,
          lyrics: songDetail.lyric,
          title: track.name,
          artist: track.artists,
          album: track.album,
        );
        
        // 发送下载完成通知
        await _showDownloadCompleteNotification(
          trackName: track.name,
          artist: track.artists,
          filePath: outputPath,
          coverUrl: coverUrl,
        );
        
      } else {
        task.isFailed = true;
        task.errorMessage = '下载失败';
        print('❌ [DownloadService] 下载失败: $fileName');
      }

      notifyListeners();

      // 5秒后移除任务
      Future.delayed(const Duration(seconds: 5), () {
        _downloadTasks.remove(trackId);
        notifyListeners();
      });

      return success;
    } catch (e) {
      print('❌ [DownloadService] 下载歌曲失败: $e');
      return false;
    }
  }

  /// 检查文件是否已下载
  Future<bool> isDownloaded(Track track, [String? level]) async {
    if (_downloadPath == null) return false;

    try {
      final fileName = _generateSafeFileName(track, level);
      final filePath = '$_downloadPath${Platform.pathSeparator}$fileName';
      return await File(filePath).exists();
    } catch (e) {
      return false;
    }
  }

  /// 获取下载的文件路径
  Future<String?> getDownloadedFilePath(Track track, [String? level]) async {
    if (_downloadPath == null) return null;

    try {
      final fileName = _generateSafeFileName(track, level);
      final filePath = '$_downloadPath${Platform.pathSeparator}$fileName';

      if (await File(filePath).exists()) {
        return filePath;
      }

      return null;
    } catch (e) {
      return null;
    }
  }

  /// 统一嵌入元数据 (封面 & 歌词)
  Future<void> _embedMetadata(
    String filePath, {
    String? coverUrl,
    String? lyrics,
    required String title,
    required String artist,
    String? album,
  }) async {
    try {
      final isMp3 = filePath.toLowerCase().endsWith('.mp3');
      final isFlac = filePath.toLowerCase().endsWith('.flac');

      if (!isMp3 && !isFlac) return;

      print('🖼️ [DownloadService] 正在为 ${isMp3 ? "MP3" : "FLAC"} 注入元数据...');
      
      Uint8List? coverData;
      if (coverUrl != null && coverUrl.isNotEmpty) {
        final resp = await http.get(Uri.parse(coverUrl)).timeout(const Duration(seconds: 10));
        if (resp.statusCode == 200) coverData = resp.bodyBytes;
      }

      final audioFile = File(filePath);
      final originalData = await audioFile.readAsBytes();

      if (isMp3) {
        await _embedMp3Metadata(filePath, originalData, coverData, lyrics, title, artist, album);
      } else if (isFlac) {
        await _embedFlacMetadata(filePath, originalData, coverData, lyrics, title, artist, album);
      }
    } catch (e) {
      print('❌ [DownloadService] 元数据嵌入失败: $e');
    }
  }

  /// 内部方法：嵌入 MP3 元数据
  Future<void> _embedMp3Metadata(String filePath, Uint8List originalData, Uint8List? coverData, String? lyrics, String title, String artist, String? album) async {
    int audioDataStart = 0;
    if (originalData.length >= 10 && originalData[0] == 0x49 && originalData[1] == 0x44 && originalData[2] == 0x33) {
      final size = ((originalData[6] & 0x7F) << 21) | ((originalData[7] & 0x7F) << 14) | ((originalData[8] & 0x7F) << 7) | (originalData[9] & 0x7F);
      audioDataStart = 10 + size;
    }
    final audioData = Uint8List.sublistView(originalData, audioDataStart);
    final id3Tag = _buildId3v2Tag(title: title, artist: artist, album: album ?? '', coverData: coverData, lyrics: lyrics);
    final newFileData = Uint8List(id3Tag.length + audioData.length);
    newFileData.setRange(0, id3Tag.length, id3Tag);
    newFileData.setRange(id3Tag.length, newFileData.length, audioData);
    await File(filePath).writeAsBytes(newFileData);
  }

  /// 内部方法：嵌入 FLAC 元数据
  Future<void> _embedFlacMetadata(String filePath, Uint8List fileData, Uint8List? coverData, String? lyrics, String title, String artist, String? album) async {
    if (fileData.length < 4 || utf8.decode(fileData.sublist(0, 4)) != 'fLaC') throw Exception('无效 FLAC');
    
    final builder = BytesBuilder();
    builder.add(fileData.sublist(0, 4));

    int offset = 4;
    bool pictureAdded = false;
    bool commentAdded = false;

    while (offset < fileData.length) {
      final header = fileData[offset];
      final isLastBlock = (header & 0x80) != 0;
      final blockType = header & 0x7F;
      final blockLength = (fileData[offset + 1] << 16) | (fileData[offset + 2] << 8) | fileData[offset + 3];

      if (blockType == 6 || blockType == 4) { // 跳过旧的图片块(6)和注块块(4)
        offset += 4 + blockLength;
        if (isLastBlock) {
          if (!commentAdded) builder.add(_buildVorbisCommentBlock(lyrics, title: title, artist: artist, album: album, isLast: !pictureAdded && coverData == null));
          if (coverData != null && !pictureAdded) builder.add(_buildFlacPictureBlock(coverData, isLast: true));
          break;
        }
        continue;
      }

      if (isLastBlock) {
        builder.addByte(header & 0x7F); // 清除最后标志
        builder.add(fileData.sublist(offset + 1, offset + 4 + blockLength));
        builder.add(_buildVorbisCommentBlock(lyrics, title: title, artist: artist, album: album, isLast: coverData == null));
        if (coverData != null) builder.add(_buildFlacPictureBlock(coverData, isLast: true));
        offset += 4 + blockLength;
        break;
      }

      builder.add(fileData.sublist(offset, offset + 4 + blockLength));
      offset += 4 + blockLength;
    }
    
    if (offset < fileData.length) builder.add(fileData.sublist(offset));
    await File(filePath).writeAsBytes(builder.toBytes());
  }

  /// 构建 Vorbis Comment 块 (Type 4) 用于存放 FLAC 歌词和基本信息
  Uint8List _buildVorbisCommentBlock(String? lyrics, {required String title, required String artist, String? album, bool isLast = false}) {
    final content = BytesBuilder();
    // Vendor string length (4 bytes) + Vendor string ("CyreneMusic")
    final vendor = utf8.encode('CyreneMusic');
    content.addByte(vendor.length & 0xFF); content.addByte(0); content.addByte(0); content.addByte(0);
    content.add(vendor);
    
    // User comment list length (4 bytes)
    final comments = <Uint8List>[];
    comments.add(utf8.encode('TITLE=$title'));
    comments.add(utf8.encode('ARTIST=$artist'));
    if (album != null && album.isNotEmpty) {
      comments.add(utf8.encode('ALBUM=$album'));
    }
    if (lyrics != null && lyrics.isNotEmpty) {
      comments.add(utf8.encode('LYRICS=$lyrics'));
    }
    
    content.addByte(comments.length & 0xFF); content.addByte(0); content.addByte(0); content.addByte(0);
    for (final c in comments) {
      content.addByte(c.length & 0xFF); content.addByte((c.length >> 8) & 0xFF); content.addByte((c.length >> 16) & 0xFF); content.addByte((c.length >> 24) & 0xFF);
      content.add(c);
    }

    final bytes = content.toBytes();
    final result = BytesBuilder();
    result.addByte((isLast ? 0x80 : 0x00) | 0x04);
    result.addByte((bytes.length >> 16) & 0xFF);
    result.addByte((bytes.length >> 8) & 0xFF);
    result.addByte(bytes.length & 0xFF);
    result.add(bytes);
    return result.toBytes();
  }

  /// 构建 FLAC PICTURE 元数据块 (Type 6)
  Uint8List _buildFlacPictureBlock(Uint8List imageData, {bool isLast = false}) {
    final blockContent = BytesBuilder();
    
    // 1. Picture type (4 bytes): 3 = Front Cover
    blockContent.addByte(0); blockContent.addByte(0); blockContent.addByte(0); blockContent.addByte(3);
    
    // 2. MIME type
    final mimeType = imageData.length >= 8 && imageData[0] == 0x89 ? 'image/png' : 'image/jpeg';
    final mimeBytes = utf8.encode(mimeType);
    blockContent.addByte(0); blockContent.addByte(0); blockContent.addByte(0); blockContent.addByte(mimeBytes.length);
    blockContent.add(mimeBytes);
    
    // 3. Description (Empty)
    blockContent.addByte(0); blockContent.addByte(0); blockContent.addByte(0); blockContent.addByte(0);
    
    // 4. Width, Height, Depth, Colors (All 0 for simple embedding, player will auto-detect)
    for (int i = 0; i < 16; i++) blockContent.addByte(0);
    
    // 5. Picture data length
    blockContent.addByte((imageData.length >> 24) & 0xFF);
    blockContent.addByte((imageData.length >> 16) & 0xFF);
    blockContent.addByte((imageData.length >> 8) & 0xFF);
    blockContent.addByte(imageData.length & 0xFF);
    
    // 6. Picture data
    blockContent.add(imageData);
    
    final contentBytes = blockContent.toBytes();
    final result = BytesBuilder();
    
    // Block Header: [Last-flag | Type(6)] [Length(24bit)]
    result.addByte((isLast ? 0x80 : 0x00) | 0x06);
    result.addByte((contentBytes.length >> 16) & 0xFF);
    result.addByte((contentBytes.length >> 8) & 0xFF);
    result.addByte(contentBytes.length & 0xFF);
    result.add(contentBytes);
    
    return result.toBytes();
  }

  /// 构建 ID3v2.3 标签
  Uint8List _buildId3v2Tag({
    required String title,
    required String artist,
    required String album,
    Uint8List? coverData,
    String? lyrics,
  }) {
    final frames = <Uint8List>[];
    
    // TIT2 帧 (标题)
    frames.add(_buildTextFrame('TIT2', title));
    
    // TPE1 帧 (艺术家)
    frames.add(_buildTextFrame('TPE1', artist));
    
    // TALB 帧 (专辑)
    if (album.isNotEmpty) {
      frames.add(_buildTextFrame('TALB', album));
    }
    
    // APIC 帧 (专辑封面)
    if (coverData != null) {
      frames.add(_buildApicFrame(coverData));
    }

    // USLT 帧 (歌词)
    if (lyrics != null && lyrics.isNotEmpty) {
      frames.add(_buildUsltFrame(lyrics));
    }
    
    // 计算所有帧的总大小
    int totalFrameSize = 0;
    for (final frame in frames) {
      totalFrameSize += frame.length;
    }
    
    // 构建 ID3v2.3 头部
    final header = Uint8List(10);
    header[0] = 0x49; // 'I'
    header[1] = 0x44; // 'D'
    header[2] = 0x33; // '3'
    header[3] = 0x03; // 版本 2.3
    header[4] = 0x00; // 修订版本
    header[5] = 0x00; // 标志
    
    // 大小使用 syncsafe 整数（每字节只用7位）
    header[6] = (totalFrameSize >> 21) & 0x7F;
    header[7] = (totalFrameSize >> 14) & 0x7F;
    header[8] = (totalFrameSize >> 7) & 0x7F;
    header[9] = totalFrameSize & 0x7F;
    
    // 合并头部和所有帧
    final result = Uint8List(10 + totalFrameSize);
    result.setRange(0, 10, header);
    
    int offset = 10;
    for (final frame in frames) {
      result.setRange(offset, offset + frame.length, frame);
      offset += frame.length;
    }
    
    return result;
  }

  /// 构建文本帧 (TIT2, TPE1, TALB 等)
  Uint8List _buildTextFrame(String frameId, String text) {
    // 使用 UTF-8 编码
    final textBytes = utf8.encode(text);
    final frameSize = 1 + textBytes.length; // 1 字节编码标识 + 文本
    
    final frame = Uint8List(10 + frameSize);
    
    // 帧 ID (4 字节)
    frame[0] = frameId.codeUnitAt(0);
    frame[1] = frameId.codeUnitAt(1);
    frame[2] = frameId.codeUnitAt(2);
    frame[3] = frameId.codeUnitAt(3);
    
    // 帧大小 (4 字节，大端序)
    frame[4] = (frameSize >> 24) & 0xFF;
    frame[5] = (frameSize >> 16) & 0xFF;
    frame[6] = (frameSize >> 8) & 0xFF;
    frame[7] = frameSize & 0xFF;
    
    // 标志 (2 字节)
    frame[8] = 0x00;
    frame[9] = 0x00;
    
    // 编码标识 (0x03 = UTF-8)
    frame[10] = 0x03;
    
    // 文本内容
    frame.setRange(11, 11 + textBytes.length, textBytes);
    
    return frame;
  }

  /// 构建 APIC 帧 (专辑封面)
  Uint8List _buildApicFrame(Uint8List imageData) {
    // 检测图片类型
    String mimeType = 'image/jpeg';
    if (imageData.length >= 8 &&
        imageData[0] == 0x89 &&
        imageData[1] == 0x50 &&
        imageData[2] == 0x4E &&
        imageData[3] == 0x47) {
      mimeType = 'image/png';
    }
    
    final mimeBytes = utf8.encode(mimeType);
    
    // APIC 帧内容:
    // - 1 字节: 文本编码 (0x00 = ISO-8859-1)
    // - MIME 类型 + 0x00 终止符
    // - 1 字节: 图片类型 (0x03 = 封面正面)
    // - 描述 + 0x00 终止符
    // - 图片数据
    
    final frameContentSize = 1 + mimeBytes.length + 1 + 1 + 1 + imageData.length;
    final frame = Uint8List(10 + frameContentSize);
    
    // 帧 ID
    frame[0] = 0x41; // 'A'
    frame[1] = 0x50; // 'P'
    frame[2] = 0x49; // 'I'
    frame[3] = 0x43; // 'C'
    
    // 帧大小 (4 字节，大端序)
    frame[4] = (frameContentSize >> 24) & 0xFF;
    frame[5] = (frameContentSize >> 16) & 0xFF;
    frame[6] = (frameContentSize >> 8) & 0xFF;
    frame[7] = frameContentSize & 0xFF;
    
    // 标志
    frame[8] = 0x00;
    frame[9] = 0x00;
    
    int offset = 10;
    
    // 文本编码 (ISO-8859-1)
    frame[offset++] = 0x00;
    
    // MIME 类型
    frame.setRange(offset, offset + mimeBytes.length, mimeBytes);
    offset += mimeBytes.length;
    frame[offset++] = 0x00; // 终止符
    
    // 图片类型 (封面正面)
    frame[offset++] = 0x03;
    
    // 描述 (空)
    frame[offset++] = 0x00;
    
    // 图片数据
    frame.setRange(offset, offset + imageData.length, imageData);
    
    return frame;
  }

  /// 构建 USLT 帧 (歌词)
  Uint8List _buildUsltFrame(String lyrics) {
    // 文本编码 (1 byte) + Language (3 bytes) + Content descriptor + lyrics
    final lang = utf8.encode('eng');
    final lyricsBytes = utf8.encode(lyrics);
    
    final frameContentSize = 1 + 3 + 1 + lyricsBytes.length;
    final frame = Uint8List(10 + frameContentSize);
    
    frame[0] = 0x55; frame[1] = 0x53; frame[2] = 0x4C; frame[3] = 0x54; // 'USLT'
    frame[4] = (frameContentSize >> 24) & 0xFF;
    frame[5] = (frameContentSize >> 16) & 0xFF;
    frame[6] = (frameContentSize >> 8) & 0xFF;
    frame[7] = frameContentSize & 0xFF;
    
    int offset = 10;
    frame[offset++] = 0x03; // UTF-8
    frame.setRange(offset, offset + 3, lang); offset += 3;
    frame[offset++] = 0x00; // 描述结束符
    frame.setRange(offset, offset + lyricsBytes.length, lyricsBytes);
    
    return frame;
  }

  /// 显示下载完成通知
  Future<void> _showDownloadCompleteNotification({
    required String trackName,
    required String artist,
    required String filePath,
    String? coverUrl,
  }) async {
    try {
      print('🔔 [DownloadService] 发送下载完成通知...');
      
      await NotificationService().showDownloadCompleteNotification(
        trackName: trackName,
        artist: artist,
        filePath: filePath,
        folderPath: _downloadPath!,
        coverUrl: coverUrl,
      );
      
      print('✅ [DownloadService] 下载完成通知已发送');
    } catch (e) {
      print('❌ [DownloadService] 发送下载完成通知失败: $e');
    }
  }
}

