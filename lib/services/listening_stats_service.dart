import 'structured_log_service.dart';
import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:dio/dio.dart';
import '../models/track.dart';
import 'auth_service.dart';
import 'api/api_client.dart';
import 'url_service.dart';

/// 听歌统计数据模型
class ListeningStatsData {
  final int totalListeningTime; // 总听歌时长（秒）
  final int totalPlayCount; // 总播放次数
  final List<PlayCountItem> playCounts; // 播放次数列表

  ListeningStatsData({
    required this.totalListeningTime,
    required this.totalPlayCount,
    required this.playCounts,
  });

  factory ListeningStatsData.fromJson(Map<String, dynamic> json) {
    return ListeningStatsData(
      totalListeningTime: json['totalListeningTime'] as int? ?? 0,
      totalPlayCount: json['totalPlayCount'] as int? ?? 0,
      playCounts:
          (json['playCounts'] as List<dynamic>?)
              ?.map(
                (item) => PlayCountItem.fromJson(item as Map<String, dynamic>),
              )
              .toList() ??
          [],
    );
  }
}

/// 播放次数数据项
class PlayCountItem {
  final String trackId;
  final String trackName;
  final String artists;
  final String album;
  final String picUrl;
  final String source;
  final int playCount;
  final DateTime lastPlayedAt;

  PlayCountItem({
    required this.trackId,
    required this.trackName,
    required this.artists,
    required this.album,
    required this.picUrl,
    required this.source,
    required this.playCount,
    required this.lastPlayedAt,
  });

  factory PlayCountItem.fromJson(Map<String, dynamic> json) {
    return PlayCountItem(
      trackId: json['track_id'] as String,
      trackName: json['track_name'] as String,
      artists: json['artists'] as String? ?? '',
      album: json['album'] as String? ?? '',
      picUrl: json['pic_url'] as String? ?? '',
      source: json['source'] as String,
      playCount: json['play_count'] as int,
      lastPlayedAt: DateTime.parse(json['last_played_at'] as String),
    );
  }

  /// 转换为 Track 对象
  Track toTrack() {
    return Track(
      id: trackId,
      name: trackName,
      artists: artists,
      album: album,
      picUrl: picUrl,
      source: _parseSource(source),
    );
  }

  /// 解析音乐来源
  MusicSource _parseSource(String source) {
    switch (source.toLowerCase()) {
      case 'netease':
        return MusicSource.netease;
      case 'apple':
        return MusicSource.apple;
      case 'qq':
        return MusicSource.qq;
      case 'kugou':
        return MusicSource.kugou;
      case 'kuwo':
        return MusicSource.kuwo;
      case 'navidrome':
        return MusicSource.navidrome;
      case 'local':
        return MusicSource.local;
      default:
        return MusicSource.netease;
    }
  }
}

class PlayCountPage {
  final List<PlayCountItem> records;
  final int page;
  final bool hasMore;

  PlayCountPage({
    required this.records,
    required this.page,
    required this.hasMore,
  });
}

/// 听歌统计服务
class ListeningStatsService extends ChangeNotifier {
  static final ListeningStatsService _instance =
      ListeningStatsService._internal();
  factory ListeningStatsService() => _instance;
  ListeningStatsService._internal() {
    _observedSession = AuthService().sessionIdentity;
    _observedBackendRevision = UrlService().backendRevision;
    AuthService().addListener(_onAuthChanged);
    UrlService().addListener(_onAuthChanged);
  }

  String? _observedSession;
  int _observedBackendRevision = 0;
  String? _syncingSession;

  void _onAuthChanged() {
    final session = AuthService().sessionIdentity;
    final backendRevision = UrlService().backendRevision;
    if (session == _observedSession &&
        backendRevision == _observedBackendRevision) {
      return;
    }
    _observedSession = session;
    _observedBackendRevision = backendRevision;
    _pendingSeconds = 0;
    _statsData = null;
    _statsFetchedAt = null;
    _lastError = null;
    _statsRequest?.cancel('登录会话已改变');
    _statsRequest = null;
    _statsInFlight = null;
    _syncingSession = null;
    notifyListeners();
  }

  final ApiClient _api = ApiClient();

  Timer? _syncTimer;
  int _pendingSeconds = 0; // 待同步的秒数
  ListeningStatsData? _statsData;
  DateTime? _statsFetchedAt;
  String? _lastError;
  CancelToken? _statsRequest;
  Future<ListeningStatsData?>? _statsInFlight;

  /// Includes backend generation so even A → B → A invalidates old operations.
  String? get contextIdentity {
    final session = AuthService().sessionIdentity;
    return session == null ? null : '${UrlService().backendRevision}:$session';
  }

  ListeningStatsData? get statsData =>
      _observedSession == AuthService().sessionIdentity &&
          _observedBackendRevision == UrlService().backendRevision
      ? _statsData
      : null;
  String? get lastError => _lastError;

  /// 初始化服务
  void initialize() {
    if (_syncTimer?.isActive ?? false) return;
    // 每30秒同步一次听歌时长
    _syncTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      _syncListeningTime();
    });
    StructuredLogService.log('📊 [ListeningStatsService] 服务已初始化');
  }

  /// 累积听歌时长
  void accumulateListeningTime(int seconds) {
    _onAuthChanged();
    if (AuthService().sessionIdentity == null || seconds <= 0) return;
    _pendingSeconds += seconds;
  }

  /// 同步听歌时长到服务器
  Future<void> _syncListeningTime() async {
    _onAuthChanged();
    final session = contextIdentity;
    if (session == null || _syncingSession == session) return;
    if (_pendingSeconds <= 0) {
      StructuredLogService.log(
        '📊 [ListeningStatsService] 无待同步数据（待同步: $_pendingSeconds秒）',
      );
      return;
    }

    if (!AuthService().isLoggedIn) {
      StructuredLogService.log('⚠️ [ListeningStatsService] 用户未登录，无法同步');
      return;
    }

    final seconds = _pendingSeconds;
    _syncingSession = session;
    _pendingSeconds = 0; // 重置待同步秒数

    StructuredLogService.log('📤 [ListeningStatsService] 准备同步听歌时长: $seconds秒');

    try {
      final result = await _api.postJson(
        '/stats/listening-time',
        data: {'seconds': seconds},
      );
      if (session != contextIdentity) return;

      StructuredLogService.log(
        '📥 [ListeningStatsService] 同步响应状态: ${result.statusCode}',
      );

      if (result.ok) {
        StructuredLogService.log(
          '✅ [ListeningStatsService] 听歌时长已同步: +$seconds秒',
        );
      } else {
        StructuredLogService.log(
          '❌ [ListeningStatsService] 同步听歌时长失败: ${result.statusCode}',
        );
        // 同步失败，将秒数加回待同步队列
        _pendingSeconds += seconds;
      }
    } catch (e) {
      StructuredLogService.log('❌ [ListeningStatsService] 同步听歌时长异常: $e');
      // 异常时将秒数加回待同步队列
      if (session == contextIdentity) _pendingSeconds += seconds;
    } finally {
      if (_syncingSession == session) _syncingSession = null;
    }
  }

  /// 立即同步听歌时长（用于调试）
  Future<void> syncNow() async {
    StructuredLogService.log(
      '🔄 [ListeningStatsService] 手动触发同步，待同步: $_pendingSeconds秒',
    );
    await _syncListeningTime();
  }

  /// 记录播放次数
  Future<void> recordPlayCount(Track track) async {
    if (!AuthService().isLoggedIn) return;

    try {
      final result = await _api.postJson(
        '/stats/play-count',
        data: {
          'trackId': track.id.toString(),
          'trackName': track.name,
          'artists': track.artists,
          'album': track.album,
          'picUrl': track.picUrl,
          'source': track.source.name,
        },
      );

      if (result.ok) {
        StructuredLogService.log(
          '✅ [ListeningStatsService] 播放次数已记录: ${track.name}',
        );
      } else {
        StructuredLogService.log(
          '❌ [ListeningStatsService] 记录播放次数失败: ${result.statusCode}',
        );
      }
    } catch (e) {
      StructuredLogService.log('❌ [ListeningStatsService] 记录播放次数异常: $e');
    }
  }

  /// 获取统计数据
  Future<ListeningStatsData?> fetchStats({bool forceRefresh = false}) async {
    _onAuthChanged();
    final session = contextIdentity;
    if (session == null) {
      StructuredLogService.log('⚠️ [ListeningStatsService] 用户未登录');
      return null;
    }

    final pending = _statsInFlight;
    if (pending != null) return pending;
    final fetchedAt = _statsFetchedAt;
    if (!forceRefresh &&
        _statsData != null &&
        fetchedAt != null &&
        DateTime.now().difference(fetchedAt) < const Duration(seconds: 60)) {
      return _statsData;
    }
    final request = _fetchStats(session);
    _statsInFlight = request;
    try {
      return await request;
    } finally {
      if (identical(_statsInFlight, request)) _statsInFlight = null;
    }
  }

  Future<ListeningStatsData?> _fetchStats(String session) async {
    final token = CancelToken();
    _statsRequest = token;
    _lastError = null;
    try {
      final result = await _api.getJson('/stats', cancelToken: token);
      if (session != contextIdentity) return null;

      if (result.ok) {
        if (result.data is! Map ||
            result.data['status'] != 200 ||
            result.bodyData is! Map<String, dynamic>) {
          throw const FormatException('统计数据格式错误');
        }
        final body = result.bodyData as Map<String, dynamic>;
        if (body['totalListeningTime'] is! int ||
            body['totalPlayCount'] is! int ||
            body['playCounts'] is! List) {
          throw const FormatException('统计数据字段缺失');
        }
        _statsData = ListeningStatsData.fromJson(
          result.bodyData as Map<String, dynamic>,
        );
        _statsFetchedAt = DateTime.now();
        notifyListeners();
        StructuredLogService.log('✅ [ListeningStatsService] 统计数据已获取');
        return _statsData;
      } else {
        _lastError = '统计更新失败，请重试';
        StructuredLogService.log(
          '❌ [ListeningStatsService] 获取统计数据失败: ${result.statusCode}',
        );
        return null;
      }
    } catch (e) {
      if (session != contextIdentity) return null;
      _lastError = '统计更新失败，请重试';
      StructuredLogService.log('❌ [ListeningStatsService] 获取统计数据异常: $e');
      return null;
    } finally {
      if (identical(_statsRequest, token)) _statsRequest = null;
    }
  }

  /// 完整排行榜按需分页，不使用首页的 Top 10 快照。
  Future<PlayCountPage> fetchRecords({int page = 1}) async {
    final session = contextIdentity;
    if (session == null) throw StateError('请先登录');
    final result = await _api.getJson(
      '/stats/records',
      queryParameters: {'page': page, 'limit': 20},
      dedupe: false,
    );
    if (session != contextIdentity) throw StateError('登录会话或后端已改变');
    final data = result.bodyData;
    if (!result.ok ||
        result.data is! Map ||
        result.data['status'] != 200 ||
        data is! Map ||
        data['page'] != page ||
        data['records'] is! List ||
        data['hasMore'] is! bool) {
      throw StateError('播放记录加载失败，请重试');
    }
    return PlayCountPage(
      records: (data['records'] as List)
          .map((item) => PlayCountItem.fromJson(item as Map<String, dynamic>))
          .toList(),
      page: page,
      hasMore: data['hasMore'] as bool,
    );
  }

  /// 格式化时长（秒转为时分秒）
  static String formatDuration(int seconds) {
    if (seconds < 60) {
      return '$seconds秒';
    } else if (seconds < 3600) {
      final minutes = seconds ~/ 60;
      final secs = seconds % 60;
      return '$minutes分$secs秒';
    } else {
      final hours = seconds ~/ 3600;
      final minutes = (seconds % 3600) ~/ 60;
      return '$hours小时$minutes分';
    }
  }

  /// 在退出前同步数据
  Future<void> syncBeforeExit() async {
    StructuredLogService.log('🔄 [ListeningStatsService] 退出前同步数据...');
    _syncTimer?.cancel();
    await _syncListeningTime();
    StructuredLogService.log('✅ [ListeningStatsService] 退出前同步完成');
  }

  /// 清理资源
  @override
  void dispose() {
    AuthService().removeListener(_onAuthChanged);
    UrlService().removeListener(_onAuthChanged);
    _statsRequest?.cancel('统计服务已释放');
    _syncTimer?.cancel();
    StructuredLogService.log('🗑️ [ListeningStatsService] 服务已释放');
    super.dispose();
  }
}
