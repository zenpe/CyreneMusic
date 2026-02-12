import 'package:flutter/foundation.dart';
import 'api/api_client.dart';

/// 酷狗歌单信息
class KugouPlaylistInfo {
  final String listid;
  final String globalCollectionId;  // 用于获取歌曲的 ID
  final String name;
  final String pic;
  final int count;
  final String createTime;
  final String? intro;

  KugouPlaylistInfo({
    required this.listid,
    required this.globalCollectionId,
    required this.name,
    required this.pic,
    required this.count,
    required this.createTime,
    this.intro,
  });

  factory KugouPlaylistInfo.fromJson(Map<String, dynamic> json) {
    return KugouPlaylistInfo(
      listid: json['listid']?.toString() ?? '',
      globalCollectionId: json['global_collection_id']?.toString() ?? '',
      name: json['name']?.toString() ?? '未命名歌单',
      pic: json['pic']?.toString() ?? '',
      count: (json['count'] is int) ? json['count'] : int.tryParse(json['count']?.toString() ?? '0') ?? 0,
      createTime: json['create_time']?.toString() ?? '',
      intro: json['intro']?.toString(),
    );
  }
}

/// 酷狗歌曲信息
class KugouTrackInfo {
  final String hash;
  final String albumAudioId;
  final String filename;  // 格式: "艺术家 - 歌名"
  final String albumId;
  final String albumName;
  final int duration;
  final String? img;

  KugouTrackInfo({
    required this.hash,
    required this.albumAudioId,
    required this.filename,
    required this.albumId,
    required this.albumName,
    required this.duration,
    this.img,
  });

  factory KugouTrackInfo.fromJson(Map<String, dynamic> json) {
    // hash 字段是必需的，用于获取播放链接，确保转换为大写
    final hashValue = json['hash']?.toString() ?? '';
    final hash = hashValue.isNotEmpty ? hashValue.toUpperCase() : '';

    // album_audio_id 可能有多种字段名
    final albumAudioId = json['album_audio_id']?.toString() ??
                         json['add_mixsongid']?.toString() ??
                         json['mixsongid']?.toString() ??
                         json['audio_id']?.toString() ?? '';

    return KugouTrackInfo(
      hash: hash,
      albumAudioId: albumAudioId,
      filename: json['filename']?.toString() ?? '未知歌曲',
      albumId: json['album_id']?.toString() ?? '',
      albumName: json['album_name']?.toString() ?? '',
      duration: (json['duration'] is int) ? json['duration'] : int.tryParse(json['duration']?.toString() ?? '0') ?? 0,
      img: json['img']?.toString(),
    );
  }

  /// 解析 filename 获取歌名
  String get name {
    final parts = filename.split(' - ');
    return parts.length > 1 ? parts.sublist(1).join(' - ') : filename;
  }

  /// 解析 filename 获取艺术家
  String get artists {
    final parts = filename.split(' - ');
    return parts.isNotEmpty ? parts[0] : '未知艺术家';
  }
}

class KugouQrCreateResult {
  final String qrcode;
  final int expire;
  final String qrUrl;
  KugouQrCreateResult({
    required this.qrcode,
    required this.expire,
    required this.qrUrl,
  });
}

class KugouQrCheckResult {
  final int status; // 0: 过期, 1: 等待扫码, 2: 待确认, 4: 授权登录成功
  final String? message;
  final String? token;
  final String? userid;
  final String? username;
  final String? avatar;
  final int? vip_type;
  final String? vip_token;
  KugouQrCheckResult({
    required this.status,
    this.message,
    this.token,
    this.userid,
    this.username,
    this.avatar,
    this.vip_type,
    this.vip_token,
  });
}

class KugouLoginService extends ChangeNotifier {
  static final KugouLoginService _instance = KugouLoginService._internal();
  factory KugouLoginService() => _instance;
  KugouLoginService._internal();

  Future<KugouQrCreateResult> createQrKey() async {
    final keyResult = await ApiClient().getJson(
      '/kugou/login/qr/key',
      timeout: const Duration(seconds: 10),
    );
    if (!keyResult.ok) {
      throw Exception('HTTP ${keyResult.statusCode}');
    }
    final keyData = keyResult.data as Map<String, dynamic>;
    if ((keyData['code'] as int?) != 200) {
      throw Exception(keyData['message'] ?? '获取二维码 key 失败');
    }
    final data = keyData['data'] as Map<String, dynamic>;
    final qrcode = data['qrcode'] as String;
    final expire = data['expire'] as int;
    final qrUrl = data['qrUrl'] as String;

    return KugouQrCreateResult(
      qrcode: qrcode,
      expire: expire,
      qrUrl: qrUrl,
    );
  }

  Future<KugouQrCheckResult> checkQrStatus({
    required String qrcode,
    int? userId,
  }) async {
    final ts = DateTime.now().millisecondsSinceEpoch;
    final queryParams = <String, dynamic>{
      'qrcode': qrcode,
      if (userId != null) 'userId': userId.toString(),
      'timestamp': ts.toString(),
    };

    if (kDebugMode) {
      print('[KugouLoginService] checkQrStatus 请求: /kugou/login/qr/check $queryParams');
    }

    final r = await ApiClient().getJson(
      '/kugou/login/qr/check',
      queryParameters: queryParams,
      timeout: const Duration(seconds: 10),
    );

    // 即使 HTTP 状态码不是 200，也尝试解析响应
    final data = r.data as Map<String, dynamic>? ?? {};

    if (kDebugMode) {
      print('[KugouLoginService] checkQrStatus 响应: statusCode=${r.statusCode}, data=$data');
    }

    if (!r.ok) {
      // 如果响应中有 status 字段，使用它；否则抛出异常
      if (data['status'] == null) {
        throw Exception('HTTP ${r.statusCode}: ${data['message'] ?? '未知错误'}');
      }
    }

    final statusVal = data['status'] as int?;
    if (statusVal == null) {
      throw Exception('无效响应: ${data['message'] ?? '缺少 status 字段'}');
    }

    if (kDebugMode) {
      print('[KugouLoginService] checkQrStatus 解析结果: status=$statusVal');
    }

    final result = KugouQrCheckResult(
      status: statusVal,
      message: data['message'] as String?,
      token: data['token'] as String?,
      userid: data['userid'] as String?,
      username: data['username'] as String?,
      avatar: data['avatar'] as String?,
      vip_type: data['vip_type'] as int?,
      vip_token: data['vip_token'] as String?,
    );

    // 如果绑定成功（status 4），通知监听者刷新 UI
    if (statusVal == 4) {
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

  Future<bool> unbindKugou() async {
    final timestamp = DateTime.now().millisecondsSinceEpoch ~/ 1000; // 秒级时间戳
    final r = await ApiClient().postJson(
      '/accounts/kugou/unbind',
      data: {'timestamp': timestamp},
      timeout: const Duration(seconds: 10),
    );
    final success = r.ok;
    if (success) {
      notifyListeners();
    }
    return success;
  }

  /// 获取用户酷狗歌单列表
  Future<List<KugouPlaylistInfo>> fetchUserPlaylists({int page = 1, int pagesize = 30}) async {
    final r = await ApiClient().getJson(
      '/kugou/user/playlists',
      queryParameters: {
        'page': page.toString(),
        'pagesize': pagesize.toString(),
      },
      timeout: const Duration(seconds: 15),
    );

    if (!r.ok) {
      throw Exception('HTTP ${r.statusCode}');
    }

    final data = r.data as Map<String, dynamic>;
    if ((data['code'] as int?) != 200) {
      throw Exception(data['message'] ?? '获取歌单失败');
    }

    final playlistsData = data['data']?['playlists'] as List<dynamic>? ?? [];
    return playlistsData
        .map((item) => KugouPlaylistInfo.fromJson(item as Map<String, dynamic>))
        .toList();
  }

  /// 获取酷狗歌单内的歌曲
  /// [globalCollectionId] - 歌单的 global_collection_id
  Future<List<KugouTrackInfo>> fetchPlaylistTracks(String globalCollectionId, {int page = 1, int pagesize = 100}) async {
    final r = await ApiClient().getJson(
      '/kugou/playlist/tracks',
      queryParameters: {
        'listid': globalCollectionId,
        'page': page.toString(),
        'pagesize': pagesize.toString(),
      },
      timeout: const Duration(seconds: 30),
    );

    if (!r.ok) {
      throw Exception('HTTP ${r.statusCode}');
    }

    final data = r.data as Map<String, dynamic>;
    if ((data['code'] as int?) != 200) {
      throw Exception(data['message'] ?? '获取歌曲失败');
    }

    final tracksData = data['data']?['tracks'] as List<dynamic>? ?? [];
    return tracksData
        .map((item) => KugouTrackInfo.fromJson(item as Map<String, dynamic>))
        .toList();
  }

  /// 检查用户是否已绑定酷狗账号
  Future<bool> isKugouBound() async {
    try {
      final bindings = await fetchBindings();
      final kugou = bindings['data']?['kugou'] as Map<String, dynamic>?;
      return kugou != null && kugou['bound'] == true;
    } catch (e) {
      return false;
    }
  }

  /// 搜索酷狗歌曲
  /// [keyword] - 搜索关键词（通常是歌曲名或"艺术家 - 歌曲名"）
  /// [limit] - 返回结果数量限制，默认20
  /// 返回搜索结果列表，每个结果包含 emixsongid
  Future<List<KugouSearchResult>> searchKugou(String keyword, {int limit = 20}) async {
    final r = await ApiClient().getJson(
      '/kugou/search',
      queryParameters: {
        'keywords': keyword,
        'limit': limit.toString(),
      },
      timeout: const Duration(seconds: 10),
    );

    if (!r.ok) {
      throw Exception('HTTP ${r.statusCode}');
    }

    final data = r.data as Map<String, dynamic>;
    if ((data['status'] as int?) != 200) {
      throw Exception(data['msg'] ?? '搜索失败');
    }

    final resultsData = data['result'] as List<dynamic>? ?? [];
    return resultsData
        .map((item) => KugouSearchResult.fromJson(item as Map<String, dynamic>))
        .toList();
  }
}

/// 酷狗搜索结果
class KugouSearchResult {
  final String name;
  final String singer;
  final String album;
  final String emixsongid;
  final String? pic;
  final int? duration;

  KugouSearchResult({
    required this.name,
    required this.singer,
    required this.album,
    required this.emixsongid,
    this.pic,
    this.duration,
  });

  factory KugouSearchResult.fromJson(Map<String, dynamic> json) {
    return KugouSearchResult(
      name: json['name']?.toString() ?? '',
      singer: json['singer']?.toString() ?? '',
      album: json['album']?.toString() ?? '',
      emixsongid: json['emixsongid']?.toString() ?? '',
      pic: json['pic']?.toString(),
      duration: json['duration'] is int ? json['duration'] : int.tryParse(json['duration']?.toString() ?? '0'),
    );
  }
}
