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
    if (d is Map<String, dynamic>) {
      return d['message'] as String?;
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
