import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 应用通用设置（轻量级开关）
class AppSettingsService extends ChangeNotifier {
  static final AppSettingsService _instance = AppSettingsService._internal();
  factory AppSettingsService() => _instance;
  AppSettingsService._internal();

  static const String _keyResumePromptOnStartup =
      'app_setting_resume_prompt_on_startup';
  static const String _keyUpdatePromptOnStartup =
      'app_setting_update_prompt_on_startup';

  bool _showResumePromptOnStartup = true;
  bool _showUpdatePromptOnStartup = true;

  Future<void>? _initFuture;
  bool _isInitialized = false;

  bool get isInitialized => _isInitialized;
  bool get showResumePromptOnStartup => _showResumePromptOnStartup;
  bool get showUpdatePromptOnStartup => _showUpdatePromptOnStartup;

  /// 初始化服务（首次读取本地设置）
  Future<void> initialize() {
    _initFuture ??= _loadSettings();
    return _initFuture!;
  }

  /// 等待初始化完成（如果尚未初始化则先初始化）
  Future<void> ensureInitialized() => initialize();

  Future<void> _loadSettings() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _showResumePromptOnStartup =
          prefs.getBool(_keyResumePromptOnStartup) ?? true;
      _showUpdatePromptOnStartup =
          prefs.getBool(_keyUpdatePromptOnStartup) ?? true;
    } catch (e) {
      // 保持默认值
      print('❌ [AppSettings] 读取设置失败: $e');
    } finally {
      _isInitialized = true;
      notifyListeners();
    }
  }

  Future<void> _saveSettings() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_keyResumePromptOnStartup, _showResumePromptOnStartup);
      await prefs.setBool(_keyUpdatePromptOnStartup, _showUpdatePromptOnStartup);
    } catch (e) {
      print('❌ [AppSettings] 保存设置失败: $e');
    }
  }

  Future<void> setShowResumePromptOnStartup(bool value) async {
    if (_showResumePromptOnStartup == value) return;
    _showResumePromptOnStartup = value;
    await _saveSettings();
    notifyListeners();
  }

  Future<void> setShowUpdatePromptOnStartup(bool value) async {
    if (_showUpdatePromptOnStartup == value) return;
    _showUpdatePromptOnStartup = value;
    await _saveSettings();
    notifyListeners();
  }
}
