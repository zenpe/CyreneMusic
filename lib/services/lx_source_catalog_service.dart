import '../models/lx_source_candidate.dart';
import 'api/api_client.dart';
import 'api/api_result.dart';
import 'url_service.dart';

/// A successful refresh replaces the list; failures leave the last list intact.
class LxSourceCatalogService {
  static final LxSourceCatalogService _instance = LxSourceCatalogService._();
  factory LxSourceCatalogService() => _instance;
  LxSourceCatalogService._()
    : _fetch = _fetchSources,
      _baseUrl = _currentBaseUrl;

  LxSourceCatalogService.withDependencies({
    required Future<ApiResult<dynamic>> Function(String) fetch,
    required String Function() baseUrl,
  }) : _fetch = fetch,
       _baseUrl = baseUrl;

  final Future<ApiResult<dynamic>> Function(String) _fetch;
  final String Function() _baseUrl;

  static String _currentBaseUrl() => UrlService().baseUrl;

  static Future<ApiResult<dynamic>> _fetchSources(String baseUrl) =>
      ApiClient().getJson(
        '$baseUrl/lx/sources',
        auth: false,
        timeout: const Duration(seconds: 10),
        headers: const {'Cache-Control': 'no-cache'},
      );

  final Map<String, List<LxSourceCandidate>> _lists = {};

  List<LxSourceCandidate> get candidates => _lists[_baseUrl()] ?? const [];

  Future<List<LxSourceCandidate>> refresh() async {
    final baseUrl = _baseUrl();
    final result = await _fetch(baseUrl);
    final body = result.data;
    if (!result.ok || body is! Map || body['status'] != 200) {
      final message = body is Map ? body['message'] : null;
      throw Exception(message is String ? message : '获取候选音源失败，请稍后重试');
    }
    final rows = body['sources'];
    if (rows is! List) throw const FormatException('音源列表格式无效');
    final list = rows.map((row) {
      if (row is! Map) throw const FormatException('音源列表格式无效');
      return LxSourceCandidate.fromJson(Map<String, dynamic>.from(row));
    }).toList();
    if (list.map((source) => source.path).toSet().length != list.length ||
        list.map((source) => source.downloadUrl).toSet().length != list.length) {
      throw const FormatException('音源列表包含重复项目');
    }
    final sources = List<LxSourceCandidate>.unmodifiable(list);
    _lists[baseUrl] = sources;
    return sources;
  }
}
