import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'persistent_storage_service.dart';
import 'navidrome_api.dart';

/// Navidrome 会话服务
///
/// 安全特性:
/// - 密码使用 flutter_secure_storage 加密存储
/// - API 实例缓存为单例，配置变更时自动重建
class NavidromeSessionService extends ChangeNotifier {
  static final NavidromeSessionService _instance = NavidromeSessionService._internal();
  factory NavidromeSessionService() => _instance;
  NavidromeSessionService._internal();

  static const String _baseUrlKey = 'navidrome_base_url';
  static const String _usernameKey = 'navidrome_username';
  static const String _passwordKey = 'navidrome_password';

  String _baseUrl = '';
  String _username = '';
  String _password = '';
  bool _isInitialized = false;

  // API 单例缓存
  NavidromeApi? _cachedApi;
  String? _cachedConfigHash;

  // 安全存储实例
  FlutterSecureStorage? _secureStorage;

  String get baseUrl => _baseUrl;
  String get username => _username;
  bool get isInitialized => _isInitialized;

  bool get isConfigured =>
      _baseUrl.isNotEmpty && _username.isNotEmpty && _password.isNotEmpty;

  /// 获取 API 实例（单例缓存）
  NavidromeApi? get api {
    if (!isConfigured) return null;

    // 计算当前配置的哈希值
    final configHash = '$_baseUrl|$_username|$_password';

    // 如果配置未变化，返回缓存的实例
    if (_cachedApi != null && _cachedConfigHash == configHash) {
      return _cachedApi;
    }

    // 配置变化，创建新实例
    _cachedApi = NavidromeApi(
      baseUrl: _baseUrl,
      username: _username,
      password: _password,
    );
    _cachedConfigHash = configHash;
    return _cachedApi;
  }

  /// 初始化服务（必须在使用前调用）
  Future<void> initialize() async {
    if (_isInitialized) return;

    try {
      // 初始化安全存储
      _secureStorage = _createSecureStorage();

      // 从存储加载配置
      await _loadFromStorage();

      _isInitialized = true;
      debugPrint('[NavidromeSession] 初始化完成');
    } catch (e) {
      debugPrint('[NavidromeSession] 初始化失败: $e');
      rethrow;
    }
  }

  /// 创建安全存储实例（平台适配）
  FlutterSecureStorage _createSecureStorage() {
    if (Platform.isAndroid) {
      return const FlutterSecureStorage(
        aOptions: AndroidOptions(
          encryptedSharedPreferences: true,
        ),
      );
    } else if (Platform.isIOS || Platform.isMacOS) {
      return const FlutterSecureStorage(
        iOptions: IOSOptions(
          accessibility: KeychainAccessibility.first_unlock_this_device,
        ),
        mOptions: MacOsOptions(
          accessibility: KeychainAccessibility.first_unlock_this_device,
        ),
      );
    } else if (Platform.isLinux) {
      return const FlutterSecureStorage(
        lOptions: LinuxOptions(),
      );
    } else {
      // Windows 和其他平台
      return const FlutterSecureStorage(
        webOptions: WebOptions(
          dbName: 'CyreneMusic',
          publicKey: 'CyreneMusic',
        ),
      );
    }
  }

  /// 从存储加载配置
  Future<void> _loadFromStorage() async {
    final storage = PersistentStorageService();

    // URL 和用户名从普通存储读取
    _baseUrl = storage.getString(_baseUrlKey) ?? '';
    _username = storage.getString(_usernameKey) ?? '';

    // 密码从安全存储读取
    try {
      _password = await _secureStorage?.read(key: _passwordKey) ?? '';
    } catch (e) {
      debugPrint('[NavidromeSession] 读取安全存储失败，尝试迁移: $e');
      // 尝试从旧的不安全存储迁移密码
      await _migratePasswordFromInsecureStorage();
    }
  }

  /// 从旧的不安全存储迁移密码
  Future<void> _migratePasswordFromInsecureStorage() async {
    final storage = PersistentStorageService();
    final insecurePassword = storage.getString(_passwordKey);

    if (insecurePassword != null && insecurePassword.isNotEmpty) {
      debugPrint('[NavidromeSession] 迁移密码到安全存储...');
      _password = insecurePassword;

      // 保存到安全存储
      await _secureStorage?.write(key: _passwordKey, value: _password);

      // 从不安全存储删除
      await storage.remove(_passwordKey);

      debugPrint('[NavidromeSession] 密码迁移完成');
    }
  }

  /// 保存配置
  Future<void> saveConfig({
    required String baseUrl,
    required String username,
    required String password,
  }) async {
    _baseUrl = _normalizeBaseUrl(baseUrl);
    _username = username.trim();
    _password = password;

    // 清除缓存的 API 实例
    _cachedApi = null;
    _cachedConfigHash = null;

    final storage = PersistentStorageService();

    // URL 和用户名保存到普通存储
    await storage.setString(_baseUrlKey, _baseUrl);
    await storage.setString(_usernameKey, _username);

    // 密码保存到安全存储
    await _secureStorage?.write(key: _passwordKey, value: _password);

    notifyListeners();
  }

  /// 清除配置
  Future<void> clear() async {
    _baseUrl = '';
    _username = '';
    _password = '';

    // 清除缓存的 API 实例
    _cachedApi = null;
    _cachedConfigHash = null;

    final storage = PersistentStorageService();
    await storage.remove(_baseUrlKey);
    await storage.remove(_usernameKey);

    // 从安全存储删除密码
    await _secureStorage?.delete(key: _passwordKey);

    notifyListeners();
  }

  /// 测试连接
  Future<bool> testConnection() async {
    if (!isConfigured) return false;

    try {
      final apiInstance = api;
      if (apiInstance == null) return false;
      return await apiInstance.ping();
    } catch (e) {
      debugPrint('[NavidromeSession] 连接测试失败: $e');
      return false;
    }
  }

  String _normalizeBaseUrl(String input) {
    var value = input.trim();
    if (value.endsWith('/')) {
      value = value.substring(0, value.length - 1);
    }
    return value;
  }
}
