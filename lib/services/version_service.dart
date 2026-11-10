import 'dart:async';
import 'dart:convert';
import 'dart:ffi';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/version_info.dart';

/// Checks metadata only. Downloading and installation belong to the browser/user.
class VersionService extends ChangeNotifier {
  static final VersionService _instance = VersionService._();
  factory VersionService() => _instance;
  VersionService._()
    : _client = http.Client(),
      _now = DateTime.now,
      _loadVersion = _installedVersion,
      platformKey = _platformKey();

  @visibleForTesting
  VersionService.forTesting({
    required this._client,
    required this._loadVersion,
    DateTime Function()? now,
    this.platformKey = 'windows-x64',
  }) : _now = now ?? DateTime.now;

  static final endpoint = Uri.parse(
    'https://api.github.com/repos/zenpe/CyreneMusic/releases/latest',
  );
  static const successInterval = Duration(hours: 24);
  static const failureInterval = Duration(minutes: 15);
  final http.Client _client;
  final Future<String> Function() _loadVersion;
  final DateTime Function() _now;
  final String platformKey;
  Future<void>? _initialization;
  bool _initialized = false;
  Future<VersionInfo?>? _inFlight;
  late SharedPreferences _prefs;
  String _currentVersion = '';
  VersionInfo? _latestVersion;
  String? _lastError;
  bool _enabled = true;
  final Set<String> _remindedVersions = {};

  String get currentVersion => _currentVersion.isEmpty ? '未知' : _currentVersion;
  VersionInfo? get latestVersion => _latestVersion;
  String? get lastError => _lastError;
  bool get isChecking => _inFlight != null;
  bool get isEnabled => _enabled;
  bool get hasUpdate =>
      _latestVersion != null &&
      _currentVersion.isNotEmpty &&
      VersionInfo.compare(_latestVersion!.version, _currentVersion) > 0;
  bool get hasVisibleUpdate =>
      hasUpdate &&
      _prefs.getString('ignored_update_version') != _latestVersion!.version;

  static Future<String> _installedVersion() async =>
      (await PackageInfo.fromPlatform()).version;
  static String _platformKey() {
    final abi = Abi.current();
    if (abi == Abi.windowsX64) return 'windows-x64';
    if (abi == Abi.androidArm64) return 'android-arm64';
    return 'unsupported';
  }

  Future<void> initialize() async {
    if (_initialized) return;
    await (_initialization ??= _initialize());
  }

  Future<void> _initialize() async {
    _prefs = await SharedPreferences.getInstance();
    // Preserve the old switch, including an explicitly disabled preference.
    _enabled = _prefs.getBool('auto_update_enabled') ?? true;
    try {
      final version = await _loadVersion();
      if (VersionInfo.isStableVersion(version.split('+').first)) {
        _currentVersion = version;
      }
    } catch (_) {
      /* Unknown installed version must not be guessed. */
    }
    try {
      final cached = _prefs.getString('client_release_cache');
      if (cached != null) {
        _latestVersion = VersionInfo.fromRelease(
          jsonDecode(cached) as Map<String, dynamic>,
        );
      }
    } catch (_) {
      /* Ignore corrupt/stale metadata. */
    }
    _initialized = true;
    notifyListeners();
  }

  Future<void> setEnabled(bool enabled) async {
    await initialize();
    await _prefs.setBool('auto_update_enabled', enabled);
    _enabled = enabled;
    notifyListeners();
  }

  /// Manual requests bypass cooldown/ignore; concurrent callers share one request.
  Future<VersionInfo?> checkForUpdate({bool silent = false}) async {
    await initialize();
    if (_inFlight != null) return _inFlight;
    if (silent) {
      if (!_enabled) return _latestVersion;
      final now = _now().millisecondsSinceEpoch;
      final success = _prefs.getInt('client_release_success');
      final failure = _prefs.getInt('client_release_failure');
      if ((failure != null && now - failure < failureInterval.inMilliseconds) ||
          (failure == null &&
              success != null &&
              now - success < successInterval.inMilliseconds)) {
        return _latestVersion;
      }
    }
    final operation = _check();
    _inFlight = operation;
    notifyListeners();
    try {
      return await operation;
    } finally {
      _inFlight = null;
      notifyListeners();
    }
  }

  Future<VersionInfo?> _check() async {
    _lastError = null;
    try {
      if (_currentVersion.isEmpty) throw StateError('无法读取当前应用版本');
      final response = await _client
          .get(
            endpoint,
            headers: {
              'Accept': 'application/vnd.github+json',
              'User-Agent': 'CyreneMusic',
            },
          )
          .timeout(const Duration(seconds: 15));
      if (response.statusCode != 200) {
        throw StateError('GitHub HTTP ${response.statusCode}');
      }
      final release = VersionInfo.fromRelease(
        jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>,
      );
      _latestVersion = release;
      await _prefs.setString(
        'client_release_cache',
        jsonEncode(release.toJson()),
      );
      await _prefs.setInt(
        'client_release_success',
        _now().millisecondsSinceEpoch,
      );
      await _prefs.remove('client_release_failure');
      return release;
    } catch (_) {
      _lastError = '检查失败，请稍后重试，或打开 GitHub 发行页查看。';
      await _prefs.setInt(
        'client_release_failure',
        _now().millisecondsSinceEpoch,
      );
      return null;
    }
  }

  Future<bool> shouldShowUpdateDialog(VersionInfo release) async {
    await initialize();
    return _prefs.getString('ignored_update_version') != release.version &&
        !hasRemindedInSession(release.version);
  }

  void markVersionReminded(String version) => _remindedVersions.add(version);
  bool hasRemindedInSession(String version) =>
      _remindedVersions.contains(version);
  Future<void> ignoreCurrentVersion(String version) async {
    await initialize();
    await _prefs.setString('ignored_update_version', version);
    notifyListeners();
  }
}
