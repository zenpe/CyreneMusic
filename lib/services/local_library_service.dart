import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:audio_metadata_reader/audio_metadata_reader.dart';
import 'package:crypto/crypto.dart';
import 'dart:convert';
import '../models/track.dart';
import '../utils/metadata_reader.dart';
import 'download_file_writer.dart';

/// 本地音乐库服务：负责扫描目录、管理本地歌曲与歌词
/// 支持读取音频文件元数据（标题、艺术家、专辑封面等）
class LocalLibraryService extends ChangeNotifier {
  static final LocalLibraryService _instance = LocalLibraryService._internal();
  factory LocalLibraryService() => _instance;
  LocalLibraryService._internal() : _copyPickedFiles = Platform.isAndroid;

  @visibleForTesting
  LocalLibraryService.forTesting({
    required Directory directory,
    Directory? temporaryDirectory,
    bool copyPickedFiles = true,
  }) : _directoryOverride = directory,
       _temporaryDirectoryOverride = temporaryDirectory,
       _copyPickedFiles = copyPickedFiles;

  Directory? _directoryOverride;
  Directory? _temporaryDirectoryOverride;
  final bool _copyPickedFiles;
  final DownloadFileWriter _fileWriter = DownloadFileWriter();
  final Set<String> _missingPaths = {};
  Future<void>? _initialization;
  Future<void> _maintenance = Future<void>.value();
  Future<void> _importTail = Future<void>.value();
  Future<void> _saveTail = Future<void>.value();
  int _revision = 0;

  bool isUnavailable(Track track) => _missingPaths.contains(track.id);
  Future<Directory> _supportDirectory() async =>
      _directoryOverride ?? await getApplicationSupportDirectory();

  /// 支持的音频扩展名（全部小写，不带点）
  static const Set<String> supportedAudioExts = {
    'mp3',
    'wav',
    'flac',
    'aac',
    'm4a',
    'ogg',
    'opus',
    'ape',
    'wma',
    'alac',
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

  List<Track> get tracks => List.unmodifiable(_tracks);

  /// 初始化服务，加载已保存的本地音乐库
  Future<void> init({bool waitForMaintenance = false}) async {
    await (_initialization ??= _initialize());
    if (waitForMaintenance) await _maintenance;
  }

  Future<void> _initialize() async {
    await _loadLibrary();
    // Legacy file copies and filesystem checks must not hold up app startup.
    // Mutations wait for this work, so migration cannot overwrite newer imports.
    _maintenance =
        (() async {
          if (_copyPickedFiles) await _migratePickerFiles();
          await refreshAvailability();
        })().catchError((Object error) {
          debugPrint('本地音乐库后台检查失败: $error');
        });
  }

  /// 获取库数据文件路径
  Future<File> _getLibraryFile() async {
    if (_libraryFile != null) return _libraryFile!;
    final appDir = await _supportDirectory();
    await appDir.create(recursive: true);
    _libraryFile = File(p.join(appDir.path, 'local_library.json'));
    return _libraryFile!;
  }

  /// 从文件加载本地音乐库
  Future<void> _loadLibrary() async {
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
  Future<void> _saveLibrary() {
    _saveTail = _saveTail.then((_) => _writeLibrary());
    return _saveTail;
  }

  Future<void> _writeLibrary() async {
    try {
      final file = await _getLibraryFile();

      final data = {
        'version': 1,
        'updatedAt': DateTime.now().toIso8601String(),
        'tracks': _tracks.map((t) => t.toJson()).toList(),
        'lyrics': _pathToLyric,
      };

      final staged = File('${file.path}.tmp');
      await staged.writeAsString(json.encode(data), flush: true);
      await staged.rename(file.path);
      debugPrint('📀 [LocalLibrary] 保存了 ${_tracks.length} 首本地歌曲');
    } catch (e) {
      debugPrint('📀 [LocalLibrary] 保存本地音乐库失败: $e');
    }
  }

  /// Keep unavailable entries: removable storage and picker caches can disappear.
  Future<void> refreshAvailability() async {
    final revision = _revision;
    final missingPaths = <String>{};
    for (final track in List<Track>.from(_tracks)) {
      if (track.source != MusicSource.local || track.id is! String) continue;
      final path = track.id as String;
      if (!await File(path).exists()) {
        missingPaths.add(path);
      }
    }

    if (revision != _revision) return;
    _missingPaths
      ..clear()
      ..addAll(missingPaths);
    notifyListeners();
  }

  Future<String> _persistAudio(String sourcePath) async {
    final dir = Directory(
      p.join((await _supportDirectory()).path, 'local_audio'),
    );
    await dir.create(recursive: true);
    final hash = await compute(_audioDigest, sourcePath);
    final target = File(
      p.join(dir.path, '$hash${p.extension(sourcePath).toLowerCase()}'),
    );
    if (!await target.exists()) {
      await _fileWriter.write(target.path, (staged) async {
        await File(sourcePath).copy(staged.path);
      });
    }
    return target.path;
  }

  Future<void> _migratePickerFiles() async {
    final temporary =
        _temporaryDirectoryOverride ?? await getTemporaryDirectory();
    final pickerRoot = p.join(temporary.path, 'file_picker');
    var changed = false;
    for (var i = 0; i < _tracks.length; i++) {
      final track = _tracks[i];
      final oldPath = track.id;
      if (oldPath is! String || !p.isWithin(pickerRoot, oldPath)) continue;
      if (!await File(oldPath).exists()) continue;
      try {
        final target = await _persistAudio(oldPath);
        _tracks[i] = Track.fromJson({...track.toJson(), 'id': target});
        final lyric = _pathToLyric.remove(oldPath);
        if (lyric != null) _pathToLyric[target] = lyric;
        changed = true;
      } catch (e) {
        debugPrint('本地音乐迁移失败，保留原条目: $e');
      }
    }
    if (changed) await _saveLibrary();
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

    final appDir = await _supportDirectory();
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

    await importFiles([path]);
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

      await importFiles(
        result.files.map((file) => file.path).whereType<String>(),
      );
    } catch (e) {
      debugPrint('📀 [LocalLibrary] 选择文件失败: $e');
    }
  }

  /// 扫描指定文件夹（递归）
  Future<void> scanFolder(String folderPath) async {
    final dir = Directory(folderPath);
    if (!await dir.exists()) return;

    await _enqueueImport(
      dir
          .list(recursive: true, followLinks: false)
          .where((entry) => entry is File)
          .map((entry) => entry.path),
      copy: false,
    );
  }

  /// File-picker imports are durable on Android; desktop scans reference originals.
  Future<void> importFiles(Iterable<String> paths) => _enqueueImport(
    Stream.fromIterable(List<String>.of(paths)),
    copy: _copyPickedFiles,
  );

  Future<void> _enqueueImport(Stream<String> paths, {required bool copy}) {
    final revision = _revision;
    final operation = _importTail.then((_) async {
      await init(waitForMaintenance: true);
      // One active file at a time bounds handles, memory and isolate work.
      try {
        await for (final path in paths) {
          if (revision != _revision) break;
          final ext = p.extension(path).toLowerCase().replaceFirst('.', '');
          if (!supportedAudioExts.contains(ext)) continue;
          await _addAudioFile(path, copy: copy, revision: revision);
        }
      } finally {
        if (revision == _revision) {
          await _saveLibrary();
          await refreshAvailability();
        }
      }
    });
    // A failed directory traversal must not poison future imports.
    _importTail = operation.catchError((Object error) {
      debugPrint('本地音乐导入失败: $error');
    });
    return operation;
  }

  /// 清空已扫描结果
  Future<void> clear() async {
    await init(waitForMaintenance: true);
    _revision++;
    _tracks.clear();
    _pathToLyric.clear();
    _missingPaths.clear();
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
  Future<String?> _saveCoverImage(
    String audioPath,
    Uint8List imageData,
    String mimeType,
  ) async {
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
  Future<void> _addAudioFile(
    String filePath, {
    required bool copy,
    required int revision,
  }) async {
    try {
      // 去重
      if (_tracks.any((t) => t.id == filePath)) return;

      final file = File(filePath);
      if (!await file.exists()) return;

      final nameNoExt = p.basenameWithoutExtension(filePath);
      final audioPath = copy ? await _persistAudio(filePath) : filePath;
      if (revision != _revision || _tracks.any((t) => t.id == audioPath)) {
        return;
      }
      final metadata = await compute(_readLocalMetadata, filePath);
      if (revision != _revision) return;
      final (parsedName, parsedArtist) = _parseFilename(nameNoExt);
      final trackName = metadata.title ?? parsedName;
      final trackArtists = metadata.artist ?? parsedArtist ?? '本地文件';
      final trackAlbum = metadata.album ?? '';
      String trackPicUrl = '';
      if (metadata.image != null) {
        trackPicUrl =
            await _saveCoverImage(audioPath, metadata.image!, metadata.mime) ??
            '';
      }
      if (revision != _revision) return;
      _pathToLyric[audioPath] = metadata.lyrics;

      // 构造本地 Track（使用完整路径作为 id）
      final track = Track(
        id: audioPath,
        name: trackName,
        artists: trackArtists,
        album: trackAlbum,
        picUrl: trackPicUrl,
        source: MusicSource.local,
      );

      _tracks.add(track);
    } catch (e) {
      debugPrint('本地文件导入失败: $e');
    }
  }
}

Future<String> _audioDigest(String path) async =>
    (await sha256.bind(File(path).openRead()).first).toString();

typedef _LocalMetadata = ({
  String? title,
  String? artist,
  String? album,
  Uint8List? image,
  String mime,
  String lyrics,
});

/// Runs in a worker isolate. No plugins or service singletons are accessed here.
Future<_LocalMetadata> _readLocalMetadata(String filePath) async {
  var lyrics = '';
  final name = p.basenameWithoutExtension(filePath);
  for (final path in [
    p.join(p.dirname(filePath), '$name.lrc'),
    p.join(p.dirname(filePath), 'Lyrics', '$name.lrc'),
  ]) {
    final file = File(path);
    try {
      if (await file.exists()) {
        if (await file.length() <= 4 * 1024 * 1024) {
          lyrics = await file.readAsString();
        }
        if (lyrics.isNotEmpty) break;
      }
    } on Exception catch (_) {
      // An unreadable sidecar must not prevent importing the audio itself.
    }
  }
  if (lyrics.isEmpty) {
    lyrics = await MetadataReader.extractLyrics(filePath) ?? '';
  }
  String? nonempty(String? value) =>
      value == null || value.isEmpty ? null : value;
  try {
    final data = readMetadata(File(filePath), getImage: true);
    final picture = data.pictures.firstOrNull;
    return (
      title: nonempty(data.title),
      artist: nonempty(data.artist),
      album: nonempty(data.album),
      image: picture?.bytes,
      mime: picture?.mimetype ?? '',
      lyrics: lyrics,
    );
  } catch (_) {
    return (
      title: null,
      artist: null,
      album: null,
      image: null,
      mime: '',
      lyrics: lyrics,
    );
  }
}
