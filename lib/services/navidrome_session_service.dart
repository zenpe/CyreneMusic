import 'package:flutter/foundation.dart';
import 'persistent_storage_service.dart';
import 'navidrome_api.dart';

class NavidromeSessionService extends ChangeNotifier {
  static final NavidromeSessionService _instance = NavidromeSessionService._internal();
  factory NavidromeSessionService() => _instance;
  NavidromeSessionService._internal() {
    _loadFromStorage();
  }

  static const String _baseUrlKey = 'navidrome_base_url';
  static const String _usernameKey = 'navidrome_username';
  static const String _passwordKey = 'navidrome_password';

  String _baseUrl = '';
  String _username = '';
  String _password = '';

  String get baseUrl => _baseUrl;
  String get username => _username;

  bool get isConfigured =>
      _baseUrl.isNotEmpty && _username.isNotEmpty && _password.isNotEmpty;

  NavidromeApi? get api {
    if (!isConfigured) return null;
    return NavidromeApi(
      baseUrl: _baseUrl,
      username: _username,
      password: _password,
    );
  }

  void _loadFromStorage() {
    final storage = PersistentStorageService();
    _baseUrl = storage.getString(_baseUrlKey) ?? '';
    _username = storage.getString(_usernameKey) ?? '';
    _password = storage.getString(_passwordKey) ?? '';
  }

  Future<void> saveConfig({
    required String baseUrl,
    required String username,
    required String password,
  }) async {
    _baseUrl = _normalizeBaseUrl(baseUrl);
    _username = username.trim();
    _password = password;

    final storage = PersistentStorageService();
    await storage.setString(_baseUrlKey, _baseUrl);
    await storage.setString(_usernameKey, _username);
    await storage.setString(_passwordKey, _password);

    notifyListeners();
  }

  Future<void> clear() async {
    _baseUrl = '';
    _username = '';
    _password = '';

    final storage = PersistentStorageService();
    await storage.remove(_baseUrlKey);
    await storage.remove(_usernameKey);
    await storage.remove(_passwordKey);

    notifyListeners();
  }

  String _normalizeBaseUrl(String input) {
    var value = input.trim();
    if (value.endsWith('/')) {
      value = value.substring(0, value.length - 1);
    }
    return value;
  }
}
