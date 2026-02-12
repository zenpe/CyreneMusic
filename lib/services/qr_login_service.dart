import 'api/api_client.dart';
import 'auth_service.dart';

class QrLoginCreateResult {
  final String rid;
  final String code;
  final DateTime expiresAt;
  final String qrData;

  QrLoginCreateResult({
    required this.rid,
    required this.code,
    required this.expiresAt,
    required this.qrData,
  });

  factory QrLoginCreateResult.fromJson(Map<String, dynamic> json) {
    return QrLoginCreateResult(
      rid: json['rid'] as String,
      code: json['code'] as String,
      expiresAt: DateTime.parse(json['expiresAt'] as String),
      qrData: json['qrData'] as String,
    );
  }
}

class QrLoginPollResult {
  final String status;
  final String? token;
  final Map<String, dynamic>? user;
  final int? expiresIn;
  final String? desktopDeviceName;
  final String? desktopIp;
  final String? desktopLocation;

  QrLoginPollResult({
    required this.status,
    this.token,
    this.user,
    this.expiresIn,
    this.desktopDeviceName,
    this.desktopIp,
    this.desktopLocation,
  });

  factory QrLoginPollResult.fromJson(Map<String, dynamic> json) {
    return QrLoginPollResult(
      status: json['status'] as String? ?? 'waiting',
      token: json['token'] as String?,
      user: json['user'] is Map ? (json['user'] as Map).cast<String, dynamic>() : null,
      expiresIn: json['expiresIn'] as int?,
      desktopDeviceName: json['desktopDeviceName'] as String?,
      desktopIp: json['desktopIp'] as String?,
      desktopLocation: json['desktopLocation'] as String?,
    );
  }
}

class QrLoginScanResult {
  final String status;
  final String? desktopDeviceName;
  final String? desktopIp;
  final String? desktopLocation;

  QrLoginScanResult({
    required this.status,
    this.desktopDeviceName,
    this.desktopIp,
    this.desktopLocation,
  });

  factory QrLoginScanResult.fromJson(Map<String, dynamic> json) {
    return QrLoginScanResult(
      status: json['status'] as String? ?? 'scanned',
      desktopDeviceName: json['desktopDeviceName'] as String?,
      desktopIp: json['desktopIp'] as String?,
      desktopLocation: json['desktopLocation'] as String?,
    );
  }
}

class QrLoginService {
  static final QrLoginService _instance = QrLoginService._internal();
  factory QrLoginService() => _instance;
  QrLoginService._internal();

  final ApiClient _api = ApiClient();

  Future<QrLoginCreateResult> create({
    String? desktopDeviceName,
    String? desktopIp,
    String? desktopLocation,
    int expiresInSeconds = 120,
  }) async {
    final result = await _api.postJson(
      '/auth/qr-login/create',
      data: {
        'desktopDeviceName': desktopDeviceName,
        'desktopIp': desktopIp,
        'desktopLocation': desktopLocation,
        'expiresInSeconds': expiresInSeconds,
      },
      auth: false,
    );

    if (!result.ok) {
      throw Exception(result.message ?? 'create failed');
    }
    return QrLoginCreateResult.fromJson(
      (result.bodyData as Map).cast<String, dynamic>(),
    );
  }

  Future<QrLoginPollResult> poll({required String rid, required String code}) async {
    final result = await _api.getJson(
      '/auth/qr-login/poll',
      queryParameters: {'rid': rid, 'code': code},
      auth: false,
    );

    if (!result.ok) {
      throw Exception(result.message ?? 'poll failed');
    }
    return QrLoginPollResult.fromJson(
      (result.bodyData as Map).cast<String, dynamic>(),
    );
  }

  Future<QrLoginScanResult> scan({required String rid, required String code}) async {
    final token = AuthService().token;
    if (token == null || token.isEmpty) {
      throw Exception('not logged in');
    }

    final result = await _api.postJson(
      '/auth/qr-login/scan',
      data: {'rid': rid, 'code': code},
      headers: {'Authorization': 'Bearer $token'},
      auth: false,
    );

    if (!result.ok) {
      throw Exception(result.message ?? 'scan failed');
    }
    return QrLoginScanResult.fromJson(
      (result.bodyData as Map).cast<String, dynamic>(),
    );
  }

  Future<void> confirm({required String rid, required String code}) async {
    final token = AuthService().token;
    if (token == null || token.isEmpty) {
      throw Exception('not logged in');
    }

    final result = await _api.postJson(
      '/auth/qr-login/confirm',
      data: {'rid': rid, 'code': code},
      headers: {'Authorization': 'Bearer $token'},
      auth: false,
    );

    if (!result.ok) {
      throw Exception(result.message ?? 'confirm failed');
    }
  }

  Future<void> cancel({required String rid, required String code}) async {
    final result = await _api.postJson(
      '/auth/qr-login/cancel',
      data: {'rid': rid, 'code': code},
      auth: false,
    );

    if (!result.ok) {
      throw Exception(result.message ?? 'cancel failed');
    }
  }
}
