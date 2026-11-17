import 'dart:convert';
import 'dart:async';
import 'dart:typed_data';

import 'package:dio/dio.dart';

import 'package:crypto/crypto.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/audio_source_config.dart';
import 'api/api_client.dart';
import 'api/api_result.dart';
import 'lx_runtime_interface.dart';
import 'url_service.dart';
import 'audio_source_service.dart';
import 'lx_music_source_parser.dart';

class SourceRecommendation {
  static const catalogPath = '推荐/recommended.js';
  final String releaseId, scriptSha256, resolvedName, note;
  final Map<String, dynamic> health;
  const SourceRecommendation({
    required this.releaseId,
    required this.scriptSha256,
    required this.resolvedName,
    this.note = '',
    this.health = const {},
  });
  factory SourceRecommendation.fromJson(Map<String, dynamic> json) {
    final release = json['releaseId'],
        hash = json['scriptSha256'],
        name = json['resolvedName'];
    if (release is! String ||
        !RegExp(r'^r-[a-f0-9]{32}$').hasMatch(release) ||
        hash is! String ||
        !RegExp(r'^[a-f0-9]{64}$').hasMatch(hash) ||
        name is! String ||
        name.isEmpty) {
      throw const FormatException('推荐音源描述无效');
    }
    return SourceRecommendation(
      releaseId: release,
      scriptSha256: hash,
      resolvedName: name,
      note: json['note'] as String? ?? '',
      health: Map<String, dynamic>.from(json['health'] as Map? ?? {}),
    );
  }
  Map<String, dynamic> toJson() => {
    'releaseId': releaseId,
    'scriptSha256': scriptSha256,
    'resolvedName': resolvedName,
    'note': note,
    'health': health,
  };
  String get healthLabel {
    if (health.isEmpty) return '尚无匹配的检测记录';
    return ['netease', 'qq']
        .map((platform) {
          final h = health[platform];
          final name = platform == 'qq' ? 'QQ' : '网易';
          if (h is! Map) return '$name：未检测';
          final expiry = DateTime.tryParse('${h['expiresAt']}');
          if (expiry == null || expiry.isBefore(DateTime.now())) {
            return '$name：检测已过期';
          }
          return '$name：${h['recognized'] ?? 0} 资源可识别 · ${h['short'] ?? 0} 疑似短资源 · ${h['failed'] ?? 0} 失败 · ${h['unverified'] ?? 0} 未验证';
        })
        .join('\n');
  }
}

class DownloadedRecommendation {
  final String origin, script;
  final SourceRecommendation descriptor;
  const DownloadedRecommendation(this.origin, this.descriptor, this.script);
  AudioSourceConfig config(String id) {
    final info = LxScriptParser.parse(script);
    return AudioSourceConfig(
      id: id,
      type: AudioSourceType.lxmusic,
      name: '推荐音源 · ${descriptor.resolvedName}',
      url: '',
      catalogPath: SourceRecommendation.catalogPath,
      catalogKind: 'recommendation',
      backendOrigin: origin,
      releaseId: descriptor.releaseId,
      scriptSha256: descriptor.scriptSha256,
      resolvedName: descriptor.resolvedName,
      scriptContent: script,
      scriptContentHash: sha256.convert(utf8.encode(script)).toString(),
      version: info.version,
      author: info.author,
      description: info.description,
    );
  }
}

// This service only fetches and caches verified bytes. It never commits a runtime.
class SourceRecommendationService {
  SourceRecommendationService()
    : json = _fetchJson,
      bytes = _fetchBytes,
      checkRequest = null;
  SourceRecommendationService.withDependencies({
    required this.json,
    required this.bytes,
    this.checkRequest,
  });
  final Future<ApiResult<dynamic>> Function()? checkRequest;
  final Future<ApiResult<dynamic>> Function(String) json;
  final Future<ApiResult<List<int>>> Function(String, Map<String, dynamic>)
  bytes;
  static const _pendingKey = 'audio_source_recommendation_pending_v1';
  static String normalizeOrigin(String value) =>
      value.replaceFirst(RegExp(r'/+$'), '');
  static String get currentOrigin => normalizeOrigin(UrlService().baseUrl);

  Future<String>? _checkInFlight;

  /// Requests maintenance only; never selects a source or touches playback.
  Future<String> requestAutomaticCheck() =>
      _checkInFlight ??= _requestAutomaticCheck().whenComplete(() {
        _checkInFlight = null;
      });

  Future<String> _requestAutomaticCheck() async {
    final response =
        await (checkRequest?.call() ??
            ApiClient().requestJson(
              '/lx/recommendation-check',
              method: 'POST',
              timeout: const Duration(seconds: 8),
            ));
    if (response.statusCode == 401) return '请先登录当前后端，再请求巡检';
    if (response.statusCode == 404 || response.statusCode == 405) {
      return '当前后端暂不支持请求巡检';
    }
    if (response.statusCode == 429) {
      final seconds = response.retryAfterSeconds;
      return seconds == null ? '请求过于频繁，请稍后重试' : '请求过于频繁，请在 $seconds 秒后重试';
    }
    final body = response.data;
    final code = body is Map ? body['code'] : null;
    return switch ((response.statusCode, code)) {
      (202, 'accepted') => '已请求后台巡检，检测完成且满足推荐条件后将自动更新',
      (200, 'already_running') => '后台正在检测，无需重复请求',
      (200, 'already_requested') => '后台已安排巡检，无需重复请求',
      (409, 'disabled') => '当前后端未启用自动推荐巡检',
      (409, 'paused') => '后台自动推荐已暂停，请联系管理员',
      (409, 'busy') => '后台正在执行手动检测，请稍后重试',
      _ => '巡检请求未确认，请检查网络或稍后重试',
    };
  }

  static Future<ApiResult<dynamic>> _fetchJson(String origin) =>
      ApiClient().getJson(
        '$origin/lx/recommendation',
        auth: false,
        timeout: const Duration(seconds: 8),
        headers: const {'Cache-Control': 'no-cache'},
      );
  static Future<ApiResult<List<int>>> _fetchBytes(
    String origin,
    Map<String, dynamic> query,
  ) async {
    final cancel = CancelToken();
    final timer = Timer(
      const Duration(seconds: 10),
      () => cancel.cancel('推荐脚本下载超时'),
    );
    try {
      final response = await ApiClient().requestStream(
        '$origin/lx/script',
        queryParameters: query,
        auth: false,
        timeout: const Duration(seconds: 10),
        cancelToken: cancel,
        headers: const {'Cache-Control': 'no-cache'},
      );
      final status = response.statusCode ?? 0;
      if (status != 200) {
        cancel.cancel('响应结束');
        return ApiResult(statusCode: status);
      }
      final data = BytesBuilder(copy: false);
      var size = 0;
      await for (final chunk in response.data!.stream) {
        size += chunk.length;
        if (size > 8 * 1024 * 1024) {
          cancel.cancel('推荐脚本超过大小限制');
          throw const FormatException('推荐脚本超过大小限制');
        }
        data.add(chunk);
      }
      return ApiResult(
        statusCode: status,
        data: data.takeBytes(),
        headers: response.headers.map,
      );
    } on FormatException {
      rethrow;
    } catch (_) {
      return ApiResult(statusCode: 0, isNetworkError: true);
    } finally {
      timer.cancel();
    }
  }

  Future<SourceRecommendation?> describe(String origin) async {
    final response = await json(origin);
    if (response.statusCode == 404) return null;
    final body = response.data;
    if (!response.ok || body is! Map || body['recommendation'] is! Map) {
      throw Exception('无法获取推荐音源，请检查服务器或网络');
    }
    return SourceRecommendation.fromJson(
      Map<String, dynamic>.from(body['recommendation']),
    );
  }

  static String verifiedScript(List<int> bytes, String expectedHash) {
    if (bytes.isEmpty ||
        bytes.length > 8 * 1024 * 1024 ||
        sha256.convert(bytes).toString() != expectedHash) {
      throw const FormatException('推荐脚本完整性验证失败');
    }
    // Hash raw bytes before stripping a BOM or decoding. No line-ending normalization.
    return LxMusicSourceParser().decodeVerifiedScriptBytes(bytes);
  }

  Future<DownloadedRecommendation> download(
    String origin, {
    String? existingHash,
    String? existingScript,
  }) async {
    for (var attempt = 0; attempt < 2; attempt++) {
      final d = await describe(origin);
      if (d == null) throw Exception('当前服务器暂未配置推荐音源');
      if (d.scriptSha256 == existingHash &&
          existingScript != null &&
          existingScript.isNotEmpty) {
        return DownloadedRecommendation(origin, d, existingScript);
      }
      final prefs = await SharedPreferences.getInstance();
      try {
        final raw = prefs.getString(_pendingKey);
        if (raw != null) {
          final stored = jsonDecode(raw);
          if (stored is Map &&
              stored['origin'] == origin &&
              stored['sha256'] == d.scriptSha256) {
            final encoded = stored['bytes'] as String;
            if (encoded.length > 12 * 1024 * 1024) {
              throw const FormatException('缓存大小无效');
            }
            final bytes = base64Decode(encoded);
            return DownloadedRecommendation(
              origin,
              d,
              verifiedScript(bytes, d.scriptSha256),
            );
          }
        }
      } catch (_) {
        /* A corrupt cache never replaces the active script. */
      }
      final response = await this.bytes(origin, {
        'path': SourceRecommendation.catalogPath,
        'sha256': d.scriptSha256,
      });
      if ((response.statusCode == 404 || response.statusCode == 410) &&
          attempt == 0) {
        continue;
      }
      if (!response.ok || response.data == null) {
        throw Exception('推荐脚本下载失败，原音源已保留');
      }
      final bytes = response.data!,
          script = verifiedScript(bytes, d.scriptSha256);
      if (!await prefs.setString(
        _pendingKey,
        jsonEncode({
          'origin': origin,
          'sha256': d.scriptSha256,
          'bytes': base64Encode(bytes),
        }),
      )) {
        throw Exception('无法缓存推荐脚本，原音源已保留');
      }
      return DownloadedRecommendation(origin, d, script);
    }
    throw Exception('推荐版本已改变，请重试');
  }
}
