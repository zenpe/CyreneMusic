import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:audio_metadata_reader/audio_metadata_reader.dart';
import 'package:crypto/crypto.dart';
import 'dart:convert';
import '../models/track.dart';
import '../utils/metadata_reader.dart';

/// 本地音乐库服务：负责扫描目录、管理本地歌曲与歌词
/// 支持读取音频文件元数据（标题、艺术家、专辑封面等）
class LocalLibraryService extends ChangeNotifier {
  static final LocalLibraryService _instance = LocalLibraryService._internal();
  factory LocalLibraryService() => _instance;
  LocalLibraryService._internal();

  /// 支持的音频扩展名（全部小写，不带点）
  static const Set<String> supportedAudioExts = {
    'mp3', 'wav', 'flac', 'aac', 'm4a', 'ogg', 'opus', 'ape', 'wma', 'alac'
  };

  /// 歌词扩展名
  static const String lyricExt = 'lrc';

  /// 路径 -> 歌词内容缓存
  final Map<String, String> _pathToLyric = {};

  /// 已扫描的本地歌曲列表
  final List<Track> _tracks = [];

  /// 封面缓存目录
  Directory? _coverCacheDir;

  /// 库数据文件
  File? _libraryFile;

  /// 是否已初始化
  bool _initialized = false;

  List<Track> get tracks => List.unmodifiable(_tracks);

  /// 初始化服务，加载已保存的本地音乐库
  Future<void> init() async {
    if (_initialized) return;
    _initialized = true;
    await _loadLibrary(validateFiles: false);
    _validateLocalFilesInBackground();
  }

  /// 获取库数据文件路径
  Future<File> _getLibraryFile() async {
    if (_libraryFile != null) return _libraryFile!;
    final appDir = await getApplicationSupportDirectory();
    _libraryFile = File(p.join(appDir.path, 'local_library.json'));
    return _libraryFile!;
  }

  /// 从文件加载本地音乐库
  Future<void> _loadLibrary({bool validateFiles = true}) async {
    try {
      final file = await _getLibraryFile();
      if (!await file.exists()) {
        debugPrint('📀 [LocalLibrary] 没有保存的本地音乐库');
        return;
      }

      final content = await file.readAsString();
      final data = json.decode(content) as Map<String, dynamic>;
      
      // 加载曲目列表
      final tracksJson = data['tracks'] as List<dynamic>? ?? [];
      final lyricsJson = data['lyrics'] as Map<String, dynamic>? ?? {};
      
      _tracks.clear();
      _pathToLyric.clear();
      
      for (final trackJson in tracksJson) {
        try {
          final map = trackJson as Map<String, dynamic>;
          // 解析 source
          MusicSource source = MusicSource.local;
          if (map['source'] != null) {
            final sourceStr = map['source'] as String;
            source = MusicSource.values.firstWhere(
              (s) => s.name == sourceStr,
              orElse: () => MusicSource.local,
            );
          }
          
          final track = Track.fromJson(map, source: source);
          
          // 验证本地文件是否还存在（可选，启动时可跳过以加速）
          if (validateFiles && track.source == MusicSource.local && track.id is String) {
            final file = File(track.id as String);
            if (!await file.exists()) {
              debugPrint('📀 [LocalLibrary] 文件已不存在，跳过: ${track.id}');
              continue;
            }
          }
          
          _tracks.add(track);
        } catch (e) {
          debugPrint('📀 [LocalLibrary] 解析曲目失败: $e');
        }
      }
      
      // 加载歌词映射
      for (final entry in lyricsJson.entries) {
        _pathToLyric[entry.key] = entry.value as String;
      }
      
      debugPrint('📀 [LocalLibrary] 加载了 ${_tracks.length} 首本地歌曲');
      notifyListeners();
    } catch (e) {
      debugPrint('📀 [LocalLibrary] 加载本地音乐库失败: $e');
    }
  }

  /// 保存本地音乐库到文件
  Future<void> _saveLibrary() async {
    try {
      final file = await _getLibraryFile();
      
      final data = {
        'version': 1,
        'updatedAt': DateTime.now().toIso8601String(),
        'tracks': _tracks.map((t) => t.toJson()).toList(),
        'lyrics': _pathToLyric,
      };
      
      await file.writeAsString(json.encode(data));
      debugPrint('📀 [LocalLibrary] 保存了 ${_tracks.length} 首本地歌曲');
    } catch (e) {
      debugPrint('📀 [LocalLibrary] 保存本地音乐库失败: $e');
    }
  }

  /// 后台校验本地文件是否存在，避免阻塞启动
  void _validateLocalFilesInBackground() {
    Future(() async {
      if (_tracks.isEmpty) return;

      final missingPaths = <String>{};
      for (final track in List<Track>.from(_tracks)) {
        if (track.source != MusicSource.local || track.id is! String) continue;
        final path = track.id as String;
        if (!await File(path).exists()) {
          missingPaths.add(path);
        }
      }

      if (missingPaths.isEmpty) return;

      _tracks.removeWhere((t) =>
          t.source == MusicSource.local &&
          t.id is String &&
          missingPaths.contains(t.id as String));
      for (final path in missingPaths) {
        _pathToLyric.remove(path);
      }

      notifyListeners();
      await _saveLibrary();
      debugPrint('📀 [LocalLibrary] 后台校验移除 ${missingPaths.length} 个不存在的文件');
    });
  }

  /// 根据 Track.id（本地为完整文件路径）获取歌词文本
  String getLyricByTrackId(dynamic id) {
    if (id is String) {
      return _pathToLyric[id] ?? '';
    }
    return '';
  }

  /// 初始化封面缓存目录
  Future<Directory> _getCoverCacheDir() async {
    if (_coverCacheDir != null) return _coverCacheDir!;
    
    final appDir = await getApplicationSupportDirectory();
    _coverCacheDir = Directory(p.join(appDir.path, 'local_covers'));
    if (!await _coverCacheDir!.exists()) {
      await _coverCacheDir!.create(recursive: true);
    }
    return _coverCacheDir!;
  }

  /// 选择单首歌曲文件
  Future<void> pickSingleSong() async {
    final result = await FilePicker.platform.pickFiles(
      allowMultiple: false,
      type: FileType.custom,
      allowedExtensions: supportedAudioExts.toList(),
    );
    if (result == null || result.files.isEmpty) return;

    final path = result.files.single.path;
    if (path == null) return;

    await _addAudioFile(path);
    await _saveLibrary();
    notifyListeners();
  }

  /// 选择并扫描一个文件夹（递归）
  /// 在 Android 上由于 SAF 限制，改为选择多个音频文件
  Future<void> pickAndScanFolder() async {
    if (Platform.isAndroid) {
      // Android 上使用多文件选择模式，因为 SAF 对文件夹访问有限制
      await _pickMultipleFiles();
    } else {
      // 桌面端正常使用文件夹选择
      final dirPath = await FilePicker.platform.getDirectoryPath();
      if (dirPath == null || dirPath.isEmpty) return;
      await scanFolder(dirPath);
    }
  }

  /// Android 专用：选择多个音频文件
  Future<void> _pickMultipleFiles() async {
    try {
      debugPrint('📀 [LocalLibrary] 开始选择多个音频文件...');
      final result = await FilePicker.platform.pickFiles(
        allowMultiple: true,
        type: FileType.custom,
        allowedExtensions: supportedAudioExts.toList(),
      );
      
      if (result == null || result.files.isEmpty) {
        debugPrint('📀 [LocalLibrary] 用户取消了文件选择');
        return;
      }

      debugPrint('📀 [LocalLibrary] 选择了 ${result.files.length} 个文件');
      
      final List<Future<void>> futures = [];
      for (final file in result.files) {
        if (file.path != null) {
          futures.add(_addAudioFile(file.path!));
        }
      }
      
      if (futures.isNotEmpty) {
        await Future.wait(futures);
        await _saveLibrary();
        notifyListeners();
        debugPrint('📀 [LocalLibrary] 成功导入 ${futures.length} 个音频文件');
      }
    } catch (e) {
      debugPrint('📀 [LocalLibrary] 选择文件失败: $e');
    }
  }

  /// 扫描指定文件夹（递归）
  Future<void> scanFolder(String folderPath) async {
    final dir = Directory(folderPath);
    if (!await dir.exists()) return;

    final List<Future<void>> futures = [];
    await for (final entity in dir.list(recursive: true, followLinks: false)) {
      if (entity is File) {
        final ext = p.extension(entity.path).toLowerCase().replaceFirst('.', '');
        if (supportedAudioExts.contains(ext)) {
          futures.add(_addAudioFile(entity.path));
        }
      }
    }
    if (futures.isNotEmpty) {
      await Future.wait(futures);
      await _saveLibrary();
      notifyListeners();
    }
  }

  /// 清空已扫描结果
  Future<void> clear() async {
    _tracks.clear();
    _pathToLyric.clear();
    await _saveLibrary();
    notifyListeners();
  }

  /// 从文件名解析歌曲名和艺术家（格式：艺术家 - 歌曲名 或 歌曲名 - 艺术家）
  /// 返回 (歌曲名, 艺术家)，如果无法解析则返回 (文件名, null)
  (String, String?) _parseFilename(String filenameWithoutExt) {
    // 常见分隔符：" - ", " – ", " — ", "-"
    final separators = [' - ', ' – ', ' — ', ' _ '];
    
    for (final sep in separators) {
      if (filenameWithoutExt.contains(sep)) {
        final parts = filenameWithoutExt.split(sep);
        if (parts.length >= 2) {
          // 假设格式为 "艺术家 - 歌曲名"
          final artist = parts[0].trim();
          final title = parts.sublist(1).join(sep).trim();
          return (title, artist);
        }
      }
    }
    
    // 尝试用简单的 "-" 分隔（但要避免误判为歌名中的连字符）
    if (filenameWithoutExt.contains('-')) {
      final idx = filenameWithoutExt.indexOf('-');
      if (idx > 0 && idx < filenameWithoutExt.length - 1) {
        final artist = filenameWithoutExt.substring(0, idx).trim();
        final title = filenameWithoutExt.substring(idx + 1).trim();
        // 只有当两部分都有内容时才认为解析成功
        if (artist.isNotEmpty && title.isNotEmpty) {
          return (title, artist);
        }
      }
    }
    
    return (filenameWithoutExt, null);
  }

  /// 将封面图片保存到缓存目录，返回本地文件路径
  Future<String?> _saveCoverImage(String audioPath, Uint8List imageData, String mimeType) async {
    try {
      final cacheDir = await _getCoverCacheDir();
      
      // 使用音频文件路径的 MD5 作为封面文件名
      final hash = md5.convert(utf8.encode(audioPath)).toString();
      
      // 根据 MIME 类型确定扩展名
      String ext = 'jpg';
      if (mimeType.contains('png')) {
        ext = 'png';
      } else if (mimeType.contains('webp')) {
        ext = 'webp';
      } else if (mimeType.contains('gif')) {
        ext = 'gif';
      }
      
      final coverFile = File(p.join(cacheDir.path, '$hash.$ext'));
      
      // 如果封面已存在，直接返回路径
      if (await coverFile.exists()) {
        return coverFile.path;
      }
      
      // 保存封面
      await coverFile.writeAsBytes(imageData);
      return coverFile.path;
    } catch (e) {
      debugPrint('保存封面失败: $e');
      return null;
    }
  }

  /// 内部：将单个音频文件加入库
  Future<void> _addAudioFile(String filePath) async {
    try {
      // 去重
      if (_tracks.any((t) => t.id == filePath)) return;

      final file = File(filePath);
      if (!await file.exists()) return;

      final filename = p.basename(filePath);
      final nameNoExt = p.basenameWithoutExtension(filePath);

      // 尝试读取同名歌词
      String lyricText = '';
      final lyricPath = p.join(p.dirname(filePath), '$nameNoExt.$lyricExt');
      final lyricFile = File(lyricPath);
      if (await lyricFile.exists()) {
        lyricText = await lyricFile.readAsString();
      } else {
        // 兼容 Lyrics 子目录
        final altLyricPath = p.join(p.dirname(filePath), 'Lyrics', '$nameNoExt.$lyricExt');
        final altLyricFile = File(altLyricPath);
        if (await altLyricFile.exists()) {
          lyricText = await altLyricFile.readAsString();
        }
      }

      // 如果外部歌词为空，尝试读取文件内嵌歌词
      if (lyricText.isEmpty) {
        final embeddedLyric = await MetadataReader.extractLyrics(filePath);
        if (embeddedLyric != null && embeddedLyric.isNotEmpty) {
          lyricText = embeddedLyric;
          debugPrint('📀 [LocalLibrary] 成功提取内嵌歌词: ${p.basename(filePath)}');
        }
      }

      _pathToLyric[filePath] = lyricText;

      // 默认值（基于文件名）
      String trackName = nameNoExt;
      String trackArtists = '本地文件';
      String trackAlbum = '';
      String trackPicUrl = '';

      // 尝试读取音频元数据
      try {
        final metadata = readMetadata(file, getImage: true);
        
        // 读取标题
        if (metadata.title != null && metadata.title!.isNotEmpty) {
          trackName = metadata.title!;
        }
        
        // 读取艺术家
        if (metadata.artist != null && metadata.artist!.isNotEmpty) {
          trackArtists = metadata.artist!;
        }
        
        // 读取专辑
        if (metadata.album != null && metadata.album!.isNotEmpty) {
          trackAlbum = metadata.album!;
        }
        
        // 读取封面图片
        if (metadata.pictures.isNotEmpty) {
          final picture = metadata.pictures.first;
          final coverPath = await _saveCoverImage(
            filePath,
            picture.bytes,
            picture.mimetype ?? 'image/jpeg',
          );
          if (coverPath != null) {
            trackPicUrl = coverPath;
          }
        }
        
        debugPrint('📀 [LocalLibrary] 读取元数据成功: $trackName - $trackArtists');
      } catch (e) {
        // 元数据读取失败，尝试从文件名解析
        debugPrint('📀 [LocalLibrary] 元数据读取失败 ($filename): $e');
        final (parsedName, parsedArtist) = _parseFilename(nameNoExt);
        trackName = parsedName;
        if (parsedArtist != null) {
          trackArtists = parsedArtist;
        }
      }

      // 构造本地 Track（使用完整路径作为 id）
      final track = Track(
        id: filePath,
        name: trackName,
        artists: trackArtists,
        album: trackAlbum,
        picUrl: trackPicUrl,
        source: MusicSource.local,
      );

      _tracks.add(track);
    } catch (_) {
      // 忽略单个文件失败，避免中断扫描
    }
  }
}
