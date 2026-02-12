import 'package:flutter/foundation.dart';
import 'api/api_client.dart';

class NeteaseQrCreateResult {
  final String key;
  final String? qrimg;
  final String qrUrl;
  NeteaseQrCreateResult({required this.key, required this.qrUrl, this.qrimg});
}

class NeteaseQrCheckResult {
  final int code; // 800 801 802 803
  final String? message;
  final Map<String, dynamic>? profile;
  NeteaseQrCheckResult({required this.code, this.message, this.profile});
}

class NeteaseLoginService extends ChangeNotifier {
  static final NeteaseLoginService _instance = NeteaseLoginService._internal();
  factory NeteaseLoginService() => _instance;
  NeteaseLoginService._internal();

  Future<NeteaseQrCreateResult> createQrKey() async {
    // align with reference: first get key, then build login url; optional create
    final keyResult = await ApiClient().getJson(
      '/login/qr/key',
      timeout: const Duration(seconds: 10),
    );
    if (!keyResult.ok) {
      throw Exception('HTTP ${keyResult.statusCode}');
    }
    final keyData = keyResult.data as Map<String, dynamic>;
    if ((keyData['code'] as int?) != 200) {
      throw Exception(keyData['message'] ?? '获取二维码 key 失败');
    }
    final unikey = (keyData['data'] as Map<String, dynamic>)['unikey'] as String;
    final qrUrl = 'https://music.163.com/login?codekey=$unikey';

    // optional: try create image (not required since we render locally)
    try {
      await ApiClient().getJson(
        '/login/qr/create',
        queryParameters: {
          'key': unikey,
          'qrimg': 'true',
          'timestamp': DateTime.now().millisecondsSinceEpoch.toString(),
        },
      );
    } catch (_) {}

    return NeteaseQrCreateResult(key: unikey, qrUrl: qrUrl);
  }

  Future<NeteaseQrCheckResult> checkQrStatus({required String key, int? userId}) async {
    final ts = DateTime.now().millisecondsSinceEpoch;
    final queryParams = <String, dynamic>{
      'key': key,
      if (userId != null) 'userId': userId.toString(),
      'timestamp': ts.toString(),
    };

    Future<Map<String, dynamic>> doGet(String path) async {
      final r = await ApiClient().getJson(
        path,
        queryParameters: queryParams,
        timeout: const Duration(seconds: 10),
      );
      if (!r.ok) {
        throw Exception('HTTP ${r.statusCode}');
      }
      return r.data as Map<String, dynamic>;
    }

    Map<String, dynamic> data = await doGet('/login/qr/check');

    // 兼容老服务路径：若返回 404/接口未找到，则尝试 /netease/login/qr/check
    final codeVal = data['code'];
    final msgVal = (data['message'] ?? data['msg']) as String?;
    if (codeVal == 404 || (msgVal != null && msgVal.contains('接口未找到'))) {
      data = await doGet('/netease/login/qr/check');
    }

    // 后端直接返回二维码状态码：800/801/802/803
    final statusCode = (data['code'] as num?)?.toInt();
    if (statusCode == null) {
      throw Exception('无效响应');
    }

    final result = NeteaseQrCheckResult(
      code: statusCode,
      message: (data['message'] ?? data['msg']) as String?,
      profile: data['profile'] as Map<String, dynamic>?,
    );

    // 如果绑定成功（803），通知监听者刷新 UI
    if (statusCode == 803) {
      notifyListeners();
    }

    return result;
  }

  // ===== Third-party accounts =====
  Future<Map<String, dynamic>> fetchBindings() async {
    final r = await ApiClient().getJson(
      '/accounts/bindings',
      timeout: const Duration(seconds: 10),
    );
    return r.data as Map<String, dynamic>;
  }

  Future<bool> unbindNetease() async {
    final timestamp = DateTime.now().millisecondsSinceEpoch ~/ 1000; // 秒级时间戳
    final r = await ApiClient().postJson(
      '/accounts/netease/unbind',
      data: {'timestamp': timestamp},
      timeout: const Duration(seconds: 10),
    );
    final success = r.ok;
    if (success) {
      notifyListeners();
    }
    return success;
  }

  /// 检查是否已绑定网易云账号
  Future<bool> isNeteaseBound() async {
    try {
      final resp = await fetchBindings();
      // 后端返回格式: { code: 200, data: { netease: { bound: true, nickname: ... } } }
      final data = resp['data'] as Map<String, dynamic>?;
      final netease = data?['netease'] as Map<String, dynamic>?;
      return netease != null && netease['bound'] == true;
    } catch (e) {
      debugPrint('❌ [NeteaseLoginService] 检查绑定状态失败: $e');
      return false;
    }
  }

  /// 获取用户网易云歌单列表
  Future<List<NeteasePlaylistInfo>> fetchUserPlaylists({int limit = 50, int offset = 0}) async {
    final r = await ApiClient().getJson(
      '/netease/user/playlists',
      queryParameters: {
        'limit': limit.toString(),
        'offset': offset.toString(),
      },
      timeout: const Duration(seconds: 15),
    );

    final data = r.data as Map<String, dynamic>;

    if (!r.ok || data['code'] != 200) {
      throw Exception(data['message'] ?? '获取歌单列表失败');
    }

    final playlistsData = data['data']?['playlists'] as List<dynamic>? ?? [];
    return playlistsData.map((p) => NeteasePlaylistInfo.fromJson(p as Map<String, dynamic>)).toList();
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
  final bool subscribed;  // 是否为收藏的歌单（非自己创建）

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
      trackCount: (json['trackCount'] is int) ? json['trackCount'] : int.tryParse(json['trackCount']?.toString() ?? '0') ?? 0,
      playCount: (json['playCount'] is int) ? json['playCount'] : int.tryParse(json['playCount']?.toString() ?? '0') ?? 0,
      creator: json['creator']?.toString() ?? '',
      creatorId: json['creatorId']?.toString() ?? '',
      description: json['description']?.toString(),
      subscribed: json['subscribed'] == true,
    );
  }
}
