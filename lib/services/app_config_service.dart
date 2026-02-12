import 'package:flutter/foundation.dart';
import 'api/api_client.dart';

/// QQ群配置
class QQGroupConfig {
  final bool enabled;
  final String url;
  final String name;

  QQGroupConfig({
    required this.enabled,
    required this.url,
    required this.name,
  });

  factory QQGroupConfig.fromJson(Map<String, dynamic> json) {
    return QQGroupConfig(
      enabled: json['enabled'] ?? false,
      url: json['url'] ?? '',
      name: json['name'] ?? '',
    );
  }

  factory QQGroupConfig.disabled() {
    return QQGroupConfig(enabled: false, url: '', name: '');
  }
}

/// 应用公共配置
class AppPublicConfig {
  final QQGroupConfig qqGroup;

  AppPublicConfig({required this.qqGroup});

  factory AppPublicConfig.fromJson(Map<String, dynamic> json) {
    return AppPublicConfig(
      qqGroup: json['qq_group'] != null
          ? QQGroupConfig.fromJson(json['qq_group'])
          : QQGroupConfig.disabled(),
    );
  }

  factory AppPublicConfig.empty() {
    return AppPublicConfig(qqGroup: QQGroupConfig.disabled());
  }
}

/// 应用配置服务 - 从后端获取公共配置
class AppConfigService extends ChangeNotifier {
  static final AppConfigService _instance = AppConfigService._internal();
  factory AppConfigService() => _instance;
  AppConfigService._internal();

  AppPublicConfig? _config;
  bool _loading = false;
  String? _error;

  AppPublicConfig? get config => _config;
  bool get loading => _loading;
  String? get error => _error;

  /// 获取公共配置
  Future<AppPublicConfig> fetchPublicConfig({bool forceRefresh = false}) async {
    // 如果已有配置且不强制刷新，直接返回
    if (_config != null && !forceRefresh) {
      return _config!;
    }

    _loading = true;
    _error = null;
    notifyListeners();

    try {
      print('[AppConfigService] Fetching public config from: /config/public');

      final result = await ApiClient().getJson(
        '/config/public',
        auth: false,
        timeout: const Duration(seconds: 10),
      );

      print('[AppConfigService] Status: ${result.statusCode}');
      print('[AppConfigService] Body: ${result.data}');

      if (result.ok && result.data != null) {
        final body = result.data as Map<String, dynamic>;
        if (body['status'] == 200 && body['data'] != null) {
          _config = AppPublicConfig.fromJson(body['data']);
          _loading = false;
          notifyListeners();
          return _config!;
        }
      }

      throw Exception('获取配置失败: ${result.statusCode}');
    } catch (e) {
      print('[AppConfigService] Exception: $e');
      _error = e.toString();
      _loading = false;
      _config = AppPublicConfig.empty();
      notifyListeners();
      return _config!;
    }
  }

  /// 重置配置（用于调试）
  void reset() {
    _config = null;
    _error = null;
    _loading = false;
    notifyListeners();
  }
}
