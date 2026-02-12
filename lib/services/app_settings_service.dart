import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum StartupQueueMode { none, favorites, specificPlaylist }

/// 应用通用设置（轻量级开关）
class AppSettingsService extends ChangeNotifier {
  static final AppSettingsService _instance = AppSettingsService._internal();
  factory AppSettingsService() => _instance;
  AppSettingsService._internal();

  static const String _keyResumePromptOnStartup =
      'app_setting_resume_prompt_on_startup';
  static const String _keyUpdatePromptOnStartup =
      'app_setting_update_prompt_on_startup';
  static const String _keyStartupQueueMode = 'app_setting_startup_queue_mode';
  static const String _keyStartupQueuePlaylistId =
      'app_setting_startup_queue_playlist_id';
  static const String _keyStartupQueuePlaylistName =
      'app_setting_startup_queue_playlist_name';

  bool _showResumePromptOnStartup = true;
  bool _showUpdatePromptOnStartup = true;
  StartupQueueMode _startupQueueMode = StartupQueueMode.none;
  int? _startupQueuePlaylistId;
  String? _startupQueuePlaylistName;

  Future<void>? _initFuture;
  bool _isInitialized = false;

  bool get isInitialized => _isInitialized;
  bool get showResumePromptOnStartup => _showResumePromptOnStartup;
  bool get showUpdatePromptOnStartup => _showUpdatePromptOnStartup;
  StartupQueueMode get startupQueueMode => _startupQueueMode;
  int? get startupQueuePlaylistId => _startupQueuePlaylistId;
  String? get startupQueuePlaylistName => _startupQueuePlaylistName;

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
      final modeName =
          prefs.getString(_keyStartupQueueMode) ?? StartupQueueMode.none.name;
      _startupQueueMode = StartupQueueMode.values.firstWhere(
        (mode) => mode.name == modeName,
        orElse: () => StartupQueueMode.none,
      );
      _startupQueuePlaylistId = prefs.getInt(_keyStartupQueuePlaylistId);
      _startupQueuePlaylistName = prefs.getString(_keyStartupQueuePlaylistName);
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
      await prefs.setBool(
        _keyResumePromptOnStartup,
        _showResumePromptOnStartup,
      );
      await prefs.setBool(
        _keyUpdatePromptOnStartup,
        _showUpdatePromptOnStartup,
      );
      await prefs.setString(_keyStartupQueueMode, _startupQueueMode.name);
      if (_startupQueuePlaylistId != null) {
        await prefs.setInt(
          _keyStartupQueuePlaylistId,
          _startupQueuePlaylistId!,
        );
      } else {
        await prefs.remove(_keyStartupQueuePlaylistId);
      }
      if (_startupQueuePlaylistName != null &&
          _startupQueuePlaylistName!.isNotEmpty) {
        await prefs.setString(
          _keyStartupQueuePlaylistName,
          _startupQueuePlaylistName!,
        );
      } else {
        await prefs.remove(_keyStartupQueuePlaylistName);
      }
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

  Future<void> setStartupQueueMode(StartupQueueMode value) async {
    if (_startupQueueMode == value) return;
    _startupQueueMode = value;
    if (value != StartupQueueMode.specificPlaylist) {
      _startupQueuePlaylistId = null;
      _startupQueuePlaylistName = null;
    }
    await _saveSettings();
    notifyListeners();
  }

  Future<void> setStartupQueuePlaylist({
    required int playlistId,
    required String playlistName,
  }) async {
    _startupQueuePlaylistId = playlistId;
    _startupQueuePlaylistName = playlistName;
    if (_startupQueueMode != StartupQueueMode.specificPlaylist) {
      _startupQueueMode = StartupQueueMode.specificPlaylist;
    }
    await _saveSettings();
    notifyListeners();
  }

  Future<void> clearStartupQueuePlaylist() async {
    if (_startupQueuePlaylistId == null && _startupQueuePlaylistName == null) {
      return;
    }
    _startupQueuePlaylistId = null;
    _startupQueuePlaylistName = null;
    await _saveSettings();
    notifyListeners();
  }
}
