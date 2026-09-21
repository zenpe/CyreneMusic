import 'package:flutter/foundation.dart';
import 'package:dio/dio.dart';
import 'api/api_client.dart';

class NeteaseRecommendService extends ChangeNotifier {
  static final NeteaseRecommendService _instance =
      NeteaseRecommendService._internal();
  factory NeteaseRecommendService() => _instance;
  NeteaseRecommendService._internal();

  final ApiClient _api = ApiClient();
  CancelToken? _forYouCombinedCancelToken;
  int _forYouCombinedRequestId = 0;

  Future<List<Map<String, dynamic>>> fetchDailySongs({
    CancelToken? cancelToken,
  }) async {
    final result = await _api.getJson(
      '/recommend/songs',
      timeout: const Duration(seconds: 15),
      cacheTtl: const Duration(seconds: 10),
      cancelToken: cancelToken,
    );
    if (!result.ok) throw Exception('HTTP ${result.statusCode}');
    final data = result.data as Map<String, dynamic>;
    if ((data['code'] as num?)?.toInt() != 200)
      throw Exception('code ${data['code']}');
    final list = (data['recommend'] as List<dynamic>? ?? [])
        .cast<Map<String, dynamic>>();
    return list;
  }

  Future<List<Map<String, dynamic>>> fetchDailyPlaylists({
    CancelToken? cancelToken,
  }) async {
    final result = await _api.getJson(
      '/recommend/resource',
      timeout: const Duration(seconds: 15),
      cacheTtl: const Duration(seconds: 10),
      cancelToken: cancelToken,
    );
    if (!result.ok) throw Exception('HTTP ${result.statusCode}');
    final data = result.data as Map<String, dynamic>;
    if ((data['code'] as num?)?.toInt() != 200)
      throw Exception('code ${data['code']}');
    final list = (data['recommend'] as List<dynamic>? ?? [])
        .cast<Map<String, dynamic>>();
    return list;
  }

  Future<List<Map<String, dynamic>>> fetchPersonalFm({
    CancelToken? cancelToken,
  }) async {
    final result = await _api.getJson(
      '/personal_fm',
      timeout: const Duration(seconds: 15),
      cacheTtl: const Duration(seconds: 10),
      cancelToken: cancelToken,
    );
    if (!result.ok) throw Exception('HTTP ${result.statusCode}');
    final data = result.data as Map<String, dynamic>;
    if ((data['code'] as num?)?.toInt() != 200)
      throw Exception('code ${data['code']}');
    final list = (data['data'] as List<dynamic>? ?? [])
        .cast<Map<String, dynamic>>();
    return list;
  }

  Future<void> fmTrash(dynamic id) async {
    final result = await _api.postJson(
      '/fm_trash',
      contentType: 'application/x-www-form-urlencoded',
      data: 'id=$id',
      timeout: const Duration(seconds: 15),
    );
    if (!result.ok) throw Exception('HTTP ${result.statusCode}');
  }

  Future<List<Map<String, dynamic>>> fetchPersonalizedPlaylists({
    int limit = 20,
    CancelToken? cancelToken,
  }) async {
    final result = await _api.getJson(
      '/personalized',
      queryParameters: {'limit': limit},
      timeout: const Duration(seconds: 15),
      cacheTtl: const Duration(seconds: 10),
      cancelToken: cancelToken,
    );
    if (!result.ok) throw Exception('HTTP ${result.statusCode}');
    final data = result.data as Map<String, dynamic>;
    if ((data['code'] as num?)?.toInt() != 200)
      throw Exception('code ${data['code']}');
    final list = (data['result'] as List<dynamic>? ?? [])
        .cast<Map<String, dynamic>>();
    return list;
  }

  Future<List<Map<String, dynamic>>> fetchPersonalizedNewsongs({
    int limit = 10,
    CancelToken? cancelToken,
  }) async {
    final result = await _api.getJson(
      '/personalized/newsong',
      queryParameters: {'limit': limit},
      timeout: const Duration(seconds: 15),
      cacheTtl: const Duration(seconds: 10),
      cancelToken: cancelToken,
    );
    if (!result.ok) throw Exception('HTTP ${result.statusCode}');
    final data = result.data as Map<String, dynamic>;
    if ((data['code'] as num?)?.toInt() != 200)
      throw Exception('code ${data['code']}');
    final list = (data['result'] as List<dynamic>? ?? [])
        .cast<Map<String, dynamic>>();
    return list;
  }

  /// 获取雷达歌单：使用一组预置歌单ID并请求后端歌单详情，提取概要信息
  Future<List<Map<String, dynamic>>> fetchRadarPlaylists({
    CancelToken? cancelToken,
  }) async {
    // 预置雷达歌单ID（由产品提供）
    const radarIds = <String>[
      '3136952023', // 私人雷达
      '8402996200', // 会员雷达
      '5320167908', // 时光雷达
      '5327906368', // 乐迷雷达
      '5362359247', // 宝藏雷达
      '5300458264', // 新歌雷达
      '5341776086', // 神秘雷达
    ];

    final futures = radarIds.map((id) async {
      final result = await _api.getJson(
        '/playlist',
        queryParameters: {'id': id, 'limit': 0},
        timeout: const Duration(seconds: 15),
        cacheTtl: const Duration(seconds: 12),
        cancelToken: cancelToken,
      );
      if (!result.ok) throw Exception('HTTP ${result.statusCode}');
      final data = result.data as Map<String, dynamic>;
      if ((data['status'] as num?)?.toInt() != 200)
        throw Exception('status ${data['status']}');
      final playlist =
          (data['data'] as Map<String, dynamic>?)?['playlist']
              as Map<String, dynamic>?;
      if (playlist == null) return <String, dynamic>{};
      return <String, dynamic>{
        'id': playlist['id'],
        'name': playlist['name'],
        'coverImgUrl': playlist['coverImgUrl'],
        'description': playlist['description'],
        'trackCount': playlist['trackCount'],
        'playCount': playlist['playCount'],
      };
    }).toList();

    final results = await Future.wait(futures);
    return results
        .where((e) => e.isNotEmpty)
        .cast<Map<String, dynamic>>()
        .toList();
  }

  /// 聚合接口：一次性获取为你推荐所需的全部数据
  Future<Map<String, List<Map<String, dynamic>>>> fetchForYouCombined({
    int personalizedLimit = 12,
    int newsongLimit = 10,
  }) async {
    final requestId = ++_forYouCombinedRequestId;
    _cancelForYouCombinedRequest('新的首页推荐请求');
    final cancelToken = CancelToken();
    _forYouCombinedCancelToken = cancelToken;

    try {
      final result = await _api.getJson(
        '/recommend/for_you',
        queryParameters: {
          'personalizedLimit': personalizedLimit,
          'newsongLimit': newsongLimit,
        },
        timeout: const Duration(seconds: 20),
        cancelToken: cancelToken,
        cacheTtl: const Duration(seconds: 10),
      );
      if (!_isCurrentForYouCombinedRequest(requestId, cancelToken)) {
        throw StateError('request_cancelled');
      }
      if (!result.ok) throw Exception('HTTP ${result.statusCode}');
      final data = result.data as Map<String, dynamic>;
      if ((data['status'] as num?)?.toInt() != 200 || data['data'] == null) {
        throw Exception('status ${data['status']}');
      }
      final d = data['data'] as Map<String, dynamic>;
      return <String, List<Map<String, dynamic>>>{
        'dailySongs': (d['dailySongs'] as List<dynamic>? ?? [])
            .cast<Map<String, dynamic>>(),
        'fm': (d['fm'] as List<dynamic>? ?? []).cast<Map<String, dynamic>>(),
        'dailyPlaylists': (d['dailyPlaylists'] as List<dynamic>? ?? [])
            .cast<Map<String, dynamic>>(),
        'personalizedPlaylists':
            (d['personalizedPlaylists'] as List<dynamic>? ?? [])
                .cast<Map<String, dynamic>>(),
        'radarPlaylists': (d['radarPlaylists'] as List<dynamic>? ?? [])
            .cast<Map<String, dynamic>>(),
        'personalizedNewsongs':
            (d['personalizedNewsongs'] as List<dynamic>? ?? [])
                .cast<Map<String, dynamic>>(),
      };
    } catch (e) {
      if (_isRequestCancelled(e, cancelToken) ||
          !_isCurrentForYouCombinedRequest(requestId, cancelToken)) {
        throw StateError('request_cancelled');
      }
      rethrow;
    } finally {
      if (identical(_forYouCombinedCancelToken, cancelToken)) {
        _forYouCombinedCancelToken = null;
      }
    }
  }

  bool _isCurrentForYouCombinedRequest(int requestId, CancelToken cancelToken) {
    return requestId == _forYouCombinedRequestId &&
        identical(_forYouCombinedCancelToken, cancelToken);
  }

  void _cancelForYouCombinedRequest(String reason) {
    final token = _forYouCombinedCancelToken;
    if (token == null || token.isCancelled) {
      return;
    }
    token.cancel(reason);
  }

  bool _isRequestCancelled(Object error, CancelToken? cancelToken) {
    if (cancelToken != null && cancelToken.isCancelled) {
      return true;
    }
    if (error is DioException && CancelToken.isCancel(error)) {
      return true;
    }
    return error is DioException && error.type == DioExceptionType.cancel;
  }

  @override
  void dispose() {
    _cancelForYouCombinedRequest('NeteaseRecommendService disposed');
    _forYouCombinedCancelToken = null;
    super.dispose();
  }
}
