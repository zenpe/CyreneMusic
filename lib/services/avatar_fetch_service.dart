import 'dart:io';
import 'dart:typed_data';
import 'package:dio/dio.dart';
import 'package:path_provider/path_provider.dart';
import 'developer_mode_service.dart';

/// 头像获取服务
///
/// 通过 HTTP 请求获取头像并缓存到本地。
class AvatarFetchService {
  static final AvatarFetchService _instance = AvatarFetchService._internal();
  factory AvatarFetchService() => _instance;
  AvatarFetchService._internal();

  final Dio _dio = Dio(BaseOptions(
    connectTimeout: const Duration(seconds: 10),
    receiveTimeout: const Duration(seconds: 30),
    headers: {
      'User-Agent':
          'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
              '(KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
    },
    responseType: ResponseType.bytes,
  ));

  /// 缓存目录
  Directory? _cacheDir;

  // ==================== 公开方法 ====================

  /// 获取头像数据
  ///
  /// [url] - 头像 URL
  /// [cacheKey] - 缓存 key，用于本地存储
  ///
  /// 返回头像的字节数据，如果获取失败返回 null
  Future<Uint8List?> fetchAvatar(String url, {String? cacheKey}) async {
    final key = cacheKey ?? _generateCacheKey(url);

    // 先检查缓存
    final cached = await _getFromCache(key);
    if (cached != null) {
      DeveloperModeService().addLog('✅ [AvatarFetch] 从缓存加载头像 ($key)');
      return cached;
    }

    DeveloperModeService().addLog('🔄 [AvatarFetch] 开始获取头像: $url');

    try {
      final response = await _dio.get<List<int>>(url);
      final bytes = Uint8List.fromList(response.data!);
      DeveloperModeService()
          .addLog('📥 [AvatarFetch] 获取成功 (${bytes.length} bytes)');
      await _saveToCache(key, bytes);
      return bytes;
    } catch (e) {
      DeveloperModeService().addLog('❌ [AvatarFetch] 获取失败: $e');
      return null;
    }
  }

  /// 获取本地缓存的头像路径
  ///
  /// 如果头像已缓存，返回本地文件路径；否则返回 null
  Future<String?> getCachedAvatarPath(String url, {String? cacheKey}) async {
    await _ensureCacheDir();
    final key = cacheKey ?? _generateCacheKey(url);
    final file = File('${_cacheDir!.path}/$key.png');
    if (await file.exists()) {
      return file.path;
    }
    return null;
  }

  /// 清除缓存
  Future<void> clearCache() async {
    await _ensureCacheDir();
    if (await _cacheDir!.exists()) {
      await _cacheDir!.delete(recursive: true);
      await _cacheDir!.create();
    }
  }

  /// 销毁服务
  Future<void> dispose() async {
    _dio.close();
  }

  // ==================== 私有方法 ====================

  /// 确保缓存目录存在
  Future<void> _ensureCacheDir() async {
    if (_cacheDir != null) return;

    final appDir = await getApplicationDocumentsDirectory();
    _cacheDir = Directory('${appDir.path}/avatar_cache');
    if (!await _cacheDir!.exists()) {
      await _cacheDir!.create(recursive: true);
    }
  }

  /// 从缓存获取
  Future<Uint8List?> _getFromCache(String key) async {
    await _ensureCacheDir();
    final file = File('${_cacheDir!.path}/$key.png');
    if (await file.exists()) {
      return file.readAsBytes();
    }
    return null;
  }

  /// 保存到缓存
  Future<void> _saveToCache(String key, Uint8List data) async {
    await _ensureCacheDir();
    final file = File('${_cacheDir!.path}/$key.png');
    await file.writeAsBytes(data);
  }

  /// 生成缓存 key
  String _generateCacheKey(String url) {
    return url.hashCode.toRadixString(16);
  }
}
