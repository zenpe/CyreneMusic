import 'package:flutter/foundation.dart';
import 'api/api_client.dart';
import 'auth_service.dart';
import 'url_service.dart';

/// A same-machine loopback connection does not transmit credentials over a LAN.
/// Every other server must use HTTPS.
bool isNeteaseCredentialTransportAllowed(String address) {
  final uri = Uri.tryParse(address);
  if (uri == null ||
      !uri.hasAuthority ||
      uri.host.isEmpty ||
      uri.userInfo.isNotEmpty) {
    return false;
  }
  if (uri.scheme == 'https') return true;
  return uri.scheme == 'http' &&
      [
        'localhost',
        '127.0.0.1',
        '::1',
        '[::1]',
      ].contains(uri.host.toLowerCase());
}

class NeteaseAccountException implements Exception {
  final String code;
  final String message;
  const NeteaseAccountException(this.code, this.message);
  @override
  String toString() => message;
}

class NeteaseQrCreateResult {
  final String key;
  final String? qrimg;
  final String qrUrl;
  NeteaseQrCreateResult({required this.key, required this.qrUrl, this.qrimg});
}

class NeteaseQrCheckResult {
  final int code;
  final String? message;
  final Map<String, dynamic>? profile;
  NeteaseQrCheckResult({required this.code, this.message, this.profile});
}

class NeteaseLoginService extends ChangeNotifier {
  static final NeteaseLoginService _instance = NeteaseLoginService._();
  factory NeteaseLoginService() => _instance;
  NeteaseLoginService._() {
    AuthService().addListener(_scopeChanged);
    UrlService().addListener(_scopeChanged);
  }
  String get scope =>
      '${UrlService().baseUrl}:${UrlService().backendRevision}:${AuthService().dataSessionIdentity}';
  String? _lastScope;
  int? bindingRevision;
  void _scopeChanged() {
    if (_lastScope == scope) return;
    _lastScope = scope;
    bindingRevision = null;
    notifyListeners();
  }

  Future<Map<String, dynamic>> _request(
    String path, {
    String method = 'GET',
    Map<String, dynamic>? data,
  }) async {
    final identity = scope;
    final result = await ApiClient().requestJson(
      path,
      method: method,
      data: data,
      dedupe: false,
    );
    if (identity != scope) {
      throw const NeteaseAccountException('SESSION_CHANGED', '服务器或登录账号已变化');
    }
    if (!result.ok) {
      final body = result.data;
      throw NeteaseAccountException(
        body is Map
            ? '${body['error'] ?? (body['code'] is String ? body['code'] : 'REQUEST_FAILED')}'
            : 'REQUEST_FAILED',
        result.message ?? '网易云请求失败，请稍后重试',
      );
    }
    return Map<String, dynamic>.from(result.data as Map);
  }

  Future<Map<String, dynamic>> startBinding(String method) async =>
      Map<String, dynamic>.from(
        (await _request(
              '/accounts/netease/bind-sessions',
              method: 'POST',
              data: {'method': method},
            ))['data']
            as Map,
      );
  Future<Map<String, dynamic>> pollBinding(String id) async =>
      Map<String, dynamic>.from(
        (await _request('/accounts/netease/bind-sessions/$id'))['data'] as Map,
      );
  Future<void> cancelBinding(String id) async {
    await _request('/accounts/netease/bind-sessions/$id', method: 'DELETE');
  }

  Future<void> completeBinding(String id, String cookie) async {
    // Credentials require HTTPS, except for a connection on this same machine.
    if (!isNeteaseCredentialTransportAllowed(UrlService().baseUrl)) {
      throw const NeteaseAccountException(
        'HTTPS_REQUIRED',
        '网页登录绑定需要使用 HTTPS 服务器地址',
      );
    }
    final result = await _request(
      '/accounts/netease/bind-sessions/$id/complete',
      method: 'POST',
      data: {'cookie': cookie},
    );
    bindingRevision = (result['data'] as Map?)?['revision'] as int?;
    notifyListeners();
  }

  Future<NeteaseQrCreateResult> createQrKey() async {
    final session = await startBinding('qr');
    final id = session['id'] as String;
    try {
      final state = await pollBinding(id);
      final url = state['qrUrl'] as String?;
      if (url == null || url.isEmpty) {
        throw const NeteaseAccountException('QR_UNAVAILABLE', '无法获取二维码，请重试');
      }
      return NeteaseQrCreateResult(key: id, qrUrl: url);
    } catch (_) {
      try {
        await cancelBinding(id);
      } catch (_) {}
      rethrow;
    }
  }

  Future<NeteaseQrCheckResult> checkQrStatus({
    required String key,
    int? userId,
  }) async {
    final data = await pollBinding(key);
    final state = data['status'];
    if (state == 'bound') {
      await fetchBindings();
      notifyListeners();
    }
    return NeteaseQrCheckResult(
      code: switch (state) {
        'expired' => 800,
        'scanned' => 802,
        'bound' => 803,
        _ => 801,
      },
    );
  }

  Future<Map<String, dynamic>> fetchBindings() async {
    final result = await _request('/accounts/bindings');
    final b = (result['data'] as Map?)?['netease'] as Map?;
    final revision = b?['revision'] as int?;
    if (revision != bindingRevision) {
      bindingRevision = revision;
      notifyListeners();
    }
    return result;
  }

  Future<bool> unbindNetease() async {
    await _request('/accounts/netease/unbind', method: 'POST');
    await fetchBindings();
    notifyListeners();
    return true;
  }

  Future<bool> isNeteaseBound() async =>
      ((await fetchBindings())['data'] as Map?)?['netease']?['bound'] == true;
  Future<Map<String, dynamic>> fetchPlaylistPage({
    int limit = 100,
    int offset = 0,
  }) async => Map<String, dynamic>.from(
    (await _request(
          '/netease/user/playlists?limit=$limit&offset=$offset',
        ))['data']
        as Map,
  );
  Future<void> importPlaylist({
    required String id,
    required String name,
    required bool follow,
    required String operationId,
  }) async {
    await _request(
      follow ? '/playlists/follow' : '/playlists/import',
      method: 'POST',
      data: {
        'source': 'netease',
        'sourcePlaylistId': id,
        'name': name,
        'operationId': operationId,
      },
    );
  }

  Future<List<NeteasePlaylistInfo>> fetchUserPlaylists({
    int limit = 50,
    int offset = 0,
  }) async {
    final result = await _request(
      '/netease/user/playlists?limit=$limit&offset=$offset',
    );
    final rows = (result['data'] as Map)['playlists'] as List;
    return rows
        .map(
          (p) =>
              NeteasePlaylistInfo.fromJson(Map<String, dynamic>.from(p as Map)),
        )
        .toList();
  }
}

/// 网易云歌单信息
class NeteasePlaylistInfo {
  final String id;
  final String name;
  final String coverImgUrl;
  final int trackCount;
  final int playCount;
  final String creator;
  final String creatorId;
  final String? description;
  final bool subscribed; // 是否为收藏的歌单（非自己创建）

  NeteasePlaylistInfo({
    required this.id,
    required this.name,
    required this.coverImgUrl,
    required this.trackCount,
    required this.playCount,
    required this.creator,
    required this.creatorId,
    this.description,
    required this.subscribed,
  });

  factory NeteasePlaylistInfo.fromJson(Map<String, dynamic> json) {
    return NeteasePlaylistInfo(
      id: json['id']?.toString() ?? '',
      name: json['name']?.toString() ?? '未命名歌单',
      coverImgUrl: json['coverImgUrl']?.toString() ?? '',
      trackCount: (json['trackCount'] is int)
          ? json['trackCount']
          : int.tryParse(json['trackCount']?.toString() ?? '0') ?? 0,
      playCount: (json['playCount'] is int)
          ? json['playCount']
          : int.tryParse(json['playCount']?.toString() ?? '0') ?? 0,
      creator: json['creator']?.toString() ?? '',
      creatorId: json['creatorId']?.toString() ?? '',
      description: json['description']?.toString(),
      subscribed: json['subscribed'] == true,
    );
  }
}
