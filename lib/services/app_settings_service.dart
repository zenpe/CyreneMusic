import 'structured_log_service.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 应用通用设置（轻量级开关）
class AppSettingsService extends ChangeNotifier {
  static final AppSettingsService _instance = AppSettingsService._internal();
  factory AppSettingsService() => _instance;
  AppSettingsService._internal();

  static const String _keyRestorePlaybackSessionOnStartup =
      'app_setting_restore_playback_session_on_startup';
  static const String _keyAutoPlayAfterRestoreOnStartup =
      'app_setting_auto_play_after_restore_on_startup';
  static const String _legacyKeyResumePromptOnStartup =
      'app_setting_resume_prompt_on_startup';
  static const String _keyUpdatePromptOnStartup =
      'app_setting_update_prompt_on_startup';

  bool _restorePlaybackSessionOnStartup = true;
  bool _autoPlayAfterRestoreOnStartup = false;
  bool _showUpdatePromptOnStartup = true;

  Future<void>? _initFuture;
  bool _isInitialized = false;

  bool get isInitialized => _isInitialized;
  bool get restorePlaybackSessionOnStartup => _restorePlaybackSessionOnStartup;
  bool get autoPlayAfterRestoreOnStartup => _autoPlayAfterRestoreOnStartup;
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
      _restorePlaybackSessionOnStartup =
          prefs.getBool(_keyRestorePlaybackSessionOnStartup) ??
          prefs.getBool(_legacyKeyResumePromptOnStartup) ??
          true;
      _autoPlayAfterRestoreOnStartup =
          prefs.getBool(_keyAutoPlayAfterRestoreOnStartup) ?? false;
      _showUpdatePromptOnStartup =
          prefs.getBool(_keyUpdatePromptOnStartup) ?? true;
    } catch (e) {
      // 保持默认值
      StructuredLogService.log('❌ [AppSettings] 读取设置失败: $e');
    } finally {
      _isInitialized = true;
      notifyListeners();
    }
  }

  Future<void> _saveSettings() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(
        _keyRestorePlaybackSessionOnStartup,
        _restorePlaybackSessionOnStartup,
      );
      await prefs.setBool(
        _keyAutoPlayAfterRestoreOnStartup,
        _autoPlayAfterRestoreOnStartup,
      );
      await prefs.remove(_legacyKeyResumePromptOnStartup);
      await prefs.setBool(
        _keyUpdatePromptOnStartup,
        _showUpdatePromptOnStartup,
      );
    } catch (e) {
      StructuredLogService.log('❌ [AppSettings] 保存设置失败: $e');
    }
  }

  Future<void> setRestorePlaybackSessionOnStartup(bool value) async {
    if (_restorePlaybackSessionOnStartup == value) return;
    _restorePlaybackSessionOnStartup = value;
    await _saveSettings();
    notifyListeners();
  }

  Future<void> setAutoPlayAfterRestoreOnStartup(bool value) async {
    if (_autoPlayAfterRestoreOnStartup == value) return;
    _autoPlayAfterRestoreOnStartup = value;
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
