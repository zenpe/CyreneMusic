import 'dart:async';
import 'dart:io';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as path;
import 'structured_log_service.dart';

/// 持久化存储服务 - 解决 Windows 平台数据丢失问题
///
/// 使用双重存储策略:
/// 1. SharedPreferences (内存+注册表/文件)
/// 2. 备份 JSON 文件（文件系统）
///
/// 如果 SharedPreferences 数据丢失，会从备份文件恢复
class PersistentStorageService extends ChangeNotifier {
  static final PersistentStorageService _instance =
      PersistentStorageService._internal();
  factory PersistentStorageService() => _instance;
  PersistentStorageService._internal();

  static const String _keyTermsAccepted = 'terms_accepted';
  static const String _keyEnableLocalMode = 'enable_local_mode';
  static const String _keyThemeConfigured = 'theme_configured';

  late SharedPreferences _prefs;
  File? _backupFile;
  File? _legacyBackupFile;
  bool _isInitialized = false;
  Map<String, dynamic> _backupData = {};
  Timer? _backupDebounce;

  void _log(String message, {Object? error}) {
    final level = message.contains('❌')
        ? LogLevel.error
        : message.contains('⚠️')
        ? LogLevel.warning
        : LogLevel.debug;
    StructuredLogService.event(
      'persistent_storage.log',
      level: level,
      fields: {'message': message},
      error: error,
    );
  }

  /// 延迟备份：多次写入合并为一次磁盘写入
  void _scheduleBackup() {
    _backupDebounce?.cancel();
    _backupDebounce = Timer(const Duration(seconds: 5), () {
      _createBackup();
    });
  }

  bool get isInitialized => _isInitialized;

  /// 通知依赖入口路由的 UI 重新读取持久化状态。
  ///
  /// 写入方法负责保存数据，入口状态变更由业务门面在一次事务完成后
  /// 统一通知，避免 UI 在连续写入中间态时重复重建。
  void refresh() => notifyListeners();

  /// 初始化持久化存储服务（必须在 main 函数中最早调用）
  Future<void> initialize() async {
    if (_isInitialized) {
      _log('⚠️ [PersistentStorage] 已初始化，跳过');
      return;
    }

    try {
      _log('💾 [PersistentStorage] 初始化持久化存储服务...');

      // 1. 初始化 SharedPreferences
      _prefs = await SharedPreferences.getInstance();
      _log('✅ [PersistentStorage] SharedPreferences 已初始化');

      // 2. 初始化备份文件
      await _initBackupFile();

      // 3. 从备份恢复数据（如果 SharedPreferences 为空）
      await _restoreFromBackup();

      // 4. 创建初始备份（首次运行则立即创建，否则延迟避免阻塞启动）
      if (_backupFile != null && !await _backupFile!.exists()) {
        await _createBackup();
      } else {
        Future(() => _createBackup());
      }

      _isInitialized = true;
      _log('✅ [PersistentStorage] 持久化存储服务初始化完成');
      _log('📊 [PersistentStorage] 当前存储键数量: ${_prefs.getKeys().length}');
    } catch (e, stackTrace) {
      _log('❌ [PersistentStorage] 初始化失败: $e', error: e);
      _log('❌ [PersistentStorage] 堆栈: $stackTrace');
      _isInitialized = false;
      rethrow;
    }
  }

  /// 初始化备份文件
  Future<void> _initBackupFile() async {
    try {
      String backupDir;

      if (Platform.isWindows) {
        // Windows: 使用应用支持目录，避免安装目录无写权限或被更新覆盖
        final appDir = await getApplicationSupportDirectory();
        backupDir = appDir.path;
        _legacyBackupFile = File(
          path.join(
            path.dirname(Platform.resolvedExecutable),
            'data',
            'app_settings_backup.json',
          ),
        );
      } else if (Platform.isAndroid) {
        // Android: 使用应用文档目录
        final appDir = await getApplicationDocumentsDirectory();
        backupDir = appDir.path;
      } else {
        // 其他平台: 使用应用支持目录
        final appDir = await getApplicationSupportDirectory();
        backupDir = appDir.path;
      }

      // 创建目录
      final dir = Directory(backupDir);
      if (!await dir.exists()) {
        await dir.create(recursive: true);
        _log('📁 [PersistentStorage] 创建备份目录: $backupDir');
      }

      _backupFile = File(path.join(backupDir, 'app_settings_backup.json'));
      _log('📂 [PersistentStorage] 备份文件路径: ${_backupFile!.path}');

      if (_legacyBackupFile != null &&
          !await _backupFile!.exists() &&
          await _legacyBackupFile!.exists()) {
        try {
          await _backupFile!.parent.create(recursive: true);
          await _legacyBackupFile!.copy(_backupFile!.path);
          _log('📦 [PersistentStorage] 已迁移旧版 Windows 设置备份');
        } catch (e) {
          _log('⚠️ [PersistentStorage] 迁移旧版设置备份失败: $e', error: e);
        }
      }
    } catch (e) {
      _log('❌ [PersistentStorage] 初始化备份文件失败: $e', error: e);
      rethrow;
    }
  }

  /// 从备份文件恢复数据
  Future<void> _restoreFromBackup() async {
    final candidates = <File>[];
    if (_backupFile != null) candidates.add(_backupFile!);
    if (_legacyBackupFile != null &&
        _legacyBackupFile!.path != _backupFile?.path) {
      candidates.add(_legacyBackupFile!);
    }

    Map<String, dynamic>? loadedData;
    File? loadedFile;
    for (final candidate in candidates) {
      if (!await candidate.exists()) continue;
      try {
        final decoded = jsonDecode(await candidate.readAsString());
        if (decoded is Map) {
          loadedData = Map<String, dynamic>.from(decoded);
          loadedFile = candidate;
          break;
        }
      } catch (e) {
        _log('⚠️ [PersistentStorage] 读取备份候选失败: ${candidate.path}', error: e);
      }
    }

    if (loadedData == null) {
      _log('ℹ️ [PersistentStorage] 备份文件不存在，跳过恢复');
      return;
    }

    try {
      _backupData = loadedData;

      _log(
        '📥 [PersistentStorage] 从备份加载 ${_backupData.length} 个键: '
        '${loadedFile?.path}',
      );

      // 检查 SharedPreferences 是否为空或数据过少
      final currentKeys = _prefs.getKeys();
      if (currentKeys.isEmpty || currentKeys.length < _backupData.length / 2) {
        _log('⚠️ [PersistentStorage] 检测到数据丢失，从备份恢复...');

        int restoredCount = 0;
        for (final entry in _backupData.entries) {
          final key = entry.key;
          final value = entry.value;

          // 只恢复缺失的键
          if (!_prefs.containsKey(key)) {
            if (value is String) {
              await _prefs.setString(key, value);
            } else if (value is int) {
              await _prefs.setInt(key, value);
            } else if (value is double) {
              await _prefs.setDouble(key, value);
            } else if (value is bool) {
              await _prefs.setBool(key, value);
            } else if (value is List) {
              await _prefs.setStringList(key, List<String>.from(value));
            }
            restoredCount++;
          }
        }

        _log('✅ [PersistentStorage] 恢复了 $restoredCount 个键');
        notifyListeners();
      } else {
        _log('✅ [PersistentStorage] SharedPreferences 数据完整，无需恢复');
      }
    } catch (e) {
      _log('❌ [PersistentStorage] 从备份恢复失败: $e', error: e);
    }
  }

  /// 创建备份
  Future<void> _createBackup() async {
    if (_backupFile == null) {
      _log('⚠️ [PersistentStorage] 备份文件未初始化');
      return;
    }

    try {
      _backupData.clear();

      // 将 SharedPreferences 的所有数据保存到备份
      for (final key in _prefs.getKeys()) {
        final value = _prefs.get(key);
        if (value != null) {
          _backupData[key] = value;
        }
      }

      // 写入文件
      final jsonContent = jsonEncode(_backupData);
      await _backupFile!.writeAsString(jsonContent);

      _log('💾 [PersistentStorage] 创建备份: ${_backupData.length} 个键');
    } catch (e) {
      _log('❌ [PersistentStorage] 创建备份失败: $e', error: e);
    }
  }

  // ============== 封装的 SharedPreferences 方法 ==============

  /// 设置字符串值（自动备份）
  Future<bool> setString(String key, String value) async {
    if (!_isInitialized) {
      _log('⚠️ [PersistentStorage] 服务未初始化');
      return false;
    }

    try {
      final result = await _prefs.setString(key, value);
      if (result) {
        _backupData[key] = value;
        _scheduleBackup();
      }
      return result;
    } catch (e) {
      _log('❌ [PersistentStorage] setString 失败: $e', error: e);
      return false;
    }
  }

  /// 设置整数值（自动备份）
  Future<bool> setInt(String key, int value) async {
    if (!_isInitialized) {
      _log('⚠️ [PersistentStorage] 服务未初始化');
      return false;
    }

    try {
      final result = await _prefs.setInt(key, value);
      if (result) {
        _backupData[key] = value;
        _scheduleBackup();
      }
      return result;
    } catch (e) {
      _log('❌ [PersistentStorage] setInt 失败: $e', error: e);
      return false;
    }
  }

  /// 设置布尔值（自动备份）
  Future<bool> setBool(String key, bool value) async {
    if (!_isInitialized) {
      _log('⚠️ [PersistentStorage] 服务未初始化');
      return false;
    }

    try {
      final result = await _prefs.setBool(key, value);
      if (result) {
        _backupData[key] = value;
        _scheduleBackup();
      }
      return result;
    } catch (e) {
      _log('❌ [PersistentStorage] setBool 失败: $e', error: e);
      return false;
    }
  }

  /// 设置双精度浮点值（自动备份）
  Future<bool> setDouble(String key, double value) async {
    if (!_isInitialized) {
      _log('⚠️ [PersistentStorage] 服务未初始化');
      return false;
    }

    try {
      final result = await _prefs.setDouble(key, value);
      if (result) {
        _backupData[key] = value;
        _scheduleBackup();
      }
      return result;
    } catch (e) {
      _log('❌ [PersistentStorage] setDouble 失败: $e', error: e);
      return false;
    }
  }

  /// 设置字符串列表（自动备份）
  Future<bool> setStringList(String key, List<String> value) async {
    if (!_isInitialized) {
      _log('⚠️ [PersistentStorage] 服务未初始化');
      return false;
    }

    try {
      final result = await _prefs.setStringList(key, value);
      if (result) {
        _backupData[key] = value;
        _scheduleBackup();
      }
      return result;
    } catch (e) {
      _log('❌ [PersistentStorage] setStringList 失败: $e', error: e);
      return false;
    }
  }

  /// 移除键（自动备份）
  Future<bool> remove(String key) async {
    if (!_isInitialized) {
      _log('⚠️ [PersistentStorage] 服务未初始化');
      return false;
    }

    try {
      final result = await _prefs.remove(key);
      if (result) {
        _backupData.remove(key);
        _scheduleBackup();
      }
      return result;
    } catch (e) {
      _log('❌ [PersistentStorage] remove 失败: $e', error: e);
      return false;
    }
  }

  /// 清除所有数据（自动备份）
  Future<bool> clear() async {
    if (!_isInitialized) {
      _log('⚠️ [PersistentStorage] 服务未初始化');
      return false;
    }

    try {
      final result = await _prefs.clear();
      if (result) {
        _backupData.clear();
        _scheduleBackup();
      }
      return result;
    } catch (e) {
      _log('❌ [PersistentStorage] clear 失败: $e', error: e);
      return false;
    }
  }

  // ============== 读取方法 ==============

  /// 获取字符串值
  String? getString(String key) {
    if (!_isInitialized) return null;
    return _prefs.getString(key);
  }

  /// 获取整数值
  int? getInt(String key) {
    if (!_isInitialized) return null;
    return _prefs.getInt(key);
  }

  /// 获取布尔值
  bool? getBool(String key) {
    if (!_isInitialized) return null;
    return _prefs.getBool(key);
  }

  /// 获取双精度浮点值
  double? getDouble(String key) {
    if (!_isInitialized) return null;
    return _prefs.getDouble(key);
  }

  /// 获取字符串列表
  List<String>? getStringList(String key) {
    if (!_isInitialized) return null;
    return _prefs.getStringList(key);
  }

  /// 检查键是否存在
  bool containsKey(String key) {
    if (!_isInitialized) return false;
    return _prefs.containsKey(key);
  }

  /// 获取所有键
  Set<String> getKeys() {
    if (!_isInitialized) return {};
    return _prefs.getKeys();
  }

  /// 获取原始 SharedPreferences 实例（用于向后兼容）
  SharedPreferences? get rawPrefs => _isInitialized ? _prefs : null;

  /// 手动触发备份
  Future<void> forceBackup() async {
    await _createBackup();
    _log('💾 [PersistentStorage] 强制备份完成');
  }

  /// 获取备份文件路径（用于调试）
  String? get backupFilePath => _backupFile?.path;

  /// 获取备份数据统计
  Map<String, dynamic> getBackupStats() {
    return {
      'sharedPreferences_keys': _prefs.getKeys().length,
      'backup_keys': _backupData.length,
      'backup_file_path': _backupFile?.path,
      'backup_file_exists': _backupFile?.existsSync() ?? false,
    };
  }
  // ============== 业务便捷方法 ==============

  /// 用户协议是否已确认
  bool get termsAccepted => getBool(_keyTermsAccepted) ?? false;

  /// 设置用户协议确认状态
  Future<void> setTermsAccepted(bool value) =>
      setBool(_keyTermsAccepted, value);

  /// 主题是否已完成初始化配置
  bool get themeConfigured => getBool(_keyThemeConfigured) ?? false;

  /// 设置主题初始化配置状态
  Future<void> setThemeConfigured(bool value) =>
      setBool(_keyThemeConfigured, value);

  /// 是否启用本地模式
  bool get enableLocalMode => getBool(_keyEnableLocalMode) ?? false;

  /// 设置是否启用本地模式
  Future<void> setEnableLocalMode(bool value) =>
      setBool(_keyEnableLocalMode, value);
}
