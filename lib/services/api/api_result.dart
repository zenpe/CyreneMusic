class ApiResult<T> {
  final int statusCode;
  final T? data;
  final String? text;
  final Map<String, List<String>> headers;
  final bool isNetworkError;

  ApiResult({
    required this.statusCode,
    this.data,
    this.text,
    Map<String, List<String>>? headers,
    this.isNetworkError = false,
  }) : headers = headers ?? const {};

  bool get ok => !isNetworkError && statusCode >= 200 && statusCode < 300;

  /// Backend standard response: data['message']
  String? get message {
    final d = data;
    final raw = d is Map ? d['message'] : null;
    final message = raw is String && raw.trim().isNotEmpty ? raw : null;
    if (statusCode == 429) {
      final seconds = retryAfterSeconds;
      if (seconds != null && !(message?.contains('秒后重试') ?? false)) {
        return '${message ?? '操作过于频繁'}，请在 $seconds 秒后重试';
      }
      return message ?? '操作过于频繁，请稍后重试';
    }
    return message;
  }

  int? get retryAfterSeconds {
    final d = data;
    final raw = d is Map ? d['retryAfterSeconds'] : null;
    final bodySeconds = int.tryParse('$raw');
    if (bodySeconds != null && bodySeconds > 0) return bodySeconds;
    for (final entry in headers.entries) {
      if (entry.key.toLowerCase() != 'retry-after' || entry.value.isEmpty) {
        continue;
      }
      final seconds = int.tryParse(entry.value.first);
      if (seconds != null && seconds > 0) return seconds;
    }
    return null;
  }

  /// Backend standard response: data['data']
  dynamic get bodyData {
    final d = data;
    if (d is Map<String, dynamic>) {
      return d['data'];
    }
    return null;
  }
}
