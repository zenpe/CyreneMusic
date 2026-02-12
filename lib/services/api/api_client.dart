import 'dart:convert';

import 'package:dio/dio.dart';

import '../developer_mode_service.dart';
import '../url_service.dart';
import 'api_result.dart';
import 'auth_token_store.dart';

class ApiClient {
  static final ApiClient _instance = ApiClient._internal();
  factory ApiClient() => _instance;

  final Dio _dio;

  ApiClient._internal()
      : _dio = Dio(BaseOptions(
          connectTimeout: const Duration(seconds: 10),
          sendTimeout: const Duration(seconds: 15),
          receiveTimeout: const Duration(seconds: 15),
          responseType: ResponseType.bytes,
          validateStatus: (status) => status != null && status > 0,
        )) {
    _dio.interceptors.add(_BaseUrlInterceptor());
    _dio.interceptors.add(_AuthInterceptor());
    _dio.interceptors.add(_LogInterceptor());
    _dio.interceptors.add(_UnauthorizedInterceptor());
  }

  Options _buildOptions({
    required String method,
    Map<String, String>? headers,
    String? contentType,
    required ResponseType responseType,
    required bool auth,
    Duration? timeout,
  }) {
    var options = Options(
      method: method,
      headers: headers,
      contentType: contentType,
      responseType: responseType,
      extra: <String, dynamic>{'auth': auth},
    );
    if (timeout != null) {
      options = options.copyWith(
        connectTimeout: timeout,
        sendTimeout: timeout,
        receiveTimeout: timeout,
      );
    }
    return options;
  }

  Future<ApiResult<dynamic>> requestJson(
    String path, {
    String method = 'GET',
    Map<String, dynamic>? queryParameters,
    dynamic data,
    Map<String, String>? headers,
    bool auth = true,
    Duration? timeout,
    String? contentType,
  }) async {
    try {
      final options = _buildOptions(
        method: method,
        headers: headers,
        contentType: contentType,
        responseType: ResponseType.bytes,
        auth: auth,
        timeout: timeout,
      );

      final response = await _dio.request<List<int>>(
        path,
        queryParameters: queryParameters,
        data: data,
        options: options,
      );

      final bytes = response.data ?? const <int>[];
      final text =
          bytes.isNotEmpty ? utf8.decode(bytes, allowMalformed: true) : '';

      dynamic json;
      if (text.isNotEmpty) {
        try {
          json = jsonDecode(text);
        } catch (e) {
          DeveloperModeService().addLog('[Network] JSON parse error: $e');
          json = null;
        }
      }

      return ApiResult<dynamic>(
        statusCode: response.statusCode ?? 0,
        data: json,
        text: text,
        headers: response.headers.map,
      );
    } on DioException catch (e) {
      return ApiResult<dynamic>(
        statusCode: e.response?.statusCode ?? 0,
        data: null,
        text: e.message ?? e.type.name,
        isNetworkError: true,
      );
    }
  }

  Future<ApiResult<List<int>>> requestBytes(
    String path, {
    String method = 'GET',
    Map<String, dynamic>? queryParameters,
    dynamic data,
    Map<String, String>? headers,
    bool auth = true,
    Duration? timeout,
    String? contentType,
  }) async {
    try {
      final options = _buildOptions(
        method: method,
        headers: headers,
        contentType: contentType,
        responseType: ResponseType.bytes,
        auth: auth,
        timeout: timeout,
      );

      final response = await _dio.request<List<int>>(
        path,
        queryParameters: queryParameters,
        data: data,
        options: options,
      );

      return ApiResult<List<int>>(
        statusCode: response.statusCode ?? 0,
        data: response.data ?? const <int>[],
        headers: response.headers.map,
      );
    } on DioException catch (e) {
      return ApiResult<List<int>>(
        statusCode: e.response?.statusCode ?? 0,
        data: const <int>[],
        text: e.message ?? e.type.name,
        isNetworkError: true,
      );
    }
  }

  /// 流式请求。网络错误时抛出 [DioException]，调用方需自行 catch。
  /// 因为流的生命周期由调用方管理，无法包装为 [ApiResult]。
  Future<Response<ResponseBody>> requestStream(
    String path, {
    String method = 'GET',
    Map<String, dynamic>? queryParameters,
    dynamic data,
    Map<String, String>? headers,
    bool auth = true,
    Duration? timeout,
    String? contentType,
  }) async {
    try {
      final options = _buildOptions(
        method: method,
        headers: headers,
        contentType: contentType,
        responseType: ResponseType.stream,
        auth: auth,
        timeout: timeout,
      );

      return await _dio.request<ResponseBody>(
        path,
        queryParameters: queryParameters,
        data: data,
        options: options,
      );
    } on DioException catch (e) {
      DeveloperModeService().addLog(
        '[Network] Stream request failed: ${e.type} ${e.message}',
      );
      rethrow;
    }
  }

  Future<ApiResult<dynamic>> getJson(
    String path, {
    Map<String, dynamic>? queryParameters,
    Map<String, String>? headers,
    bool auth = true,
    Duration? timeout,
  }) {
    return requestJson(
      path,
      method: 'GET',
      queryParameters: queryParameters,
      headers: headers,
      auth: auth,
      timeout: timeout,
    );
  }

  Future<ApiResult<dynamic>> postJson(
    String path, {
    dynamic data,
    Map<String, dynamic>? queryParameters,
    Map<String, String>? headers,
    bool auth = true,
    Duration? timeout,
    String? contentType,
  }) {
    return requestJson(
      path,
      method: 'POST',
      queryParameters: queryParameters,
      data: data,
      headers: headers,
      auth: auth,
      timeout: timeout,
      contentType: contentType,
    );
  }

  Future<ApiResult<dynamic>> putJson(
    String path, {
    dynamic data,
    Map<String, dynamic>? queryParameters,
    Map<String, String>? headers,
    bool auth = true,
    Duration? timeout,
    String? contentType,
  }) {
    return requestJson(
      path,
      method: 'PUT',
      queryParameters: queryParameters,
      data: data,
      headers: headers,
      auth: auth,
      timeout: timeout,
      contentType: contentType,
    );
  }

  Future<ApiResult<dynamic>> deleteJson(
    String path, {
    dynamic data,
    Map<String, dynamic>? queryParameters,
    Map<String, String>? headers,
    bool auth = true,
    Duration? timeout,
    String? contentType,
  }) {
    return requestJson(
      path,
      method: 'DELETE',
      queryParameters: queryParameters,
      data: data,
      headers: headers,
      auth: auth,
      timeout: timeout,
      contentType: contentType,
    );
  }

  Future<ApiResult<dynamic>> patchJson(
    String path, {
    dynamic data,
    Map<String, dynamic>? queryParameters,
    Map<String, String>? headers,
    bool auth = true,
    Duration? timeout,
    String? contentType,
  }) {
    return requestJson(
      path,
      method: 'PATCH',
      queryParameters: queryParameters,
      data: data,
      headers: headers,
      auth: auth,
      timeout: timeout,
      contentType: contentType,
    );
  }
}

class _BaseUrlInterceptor extends Interceptor {
  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    if (!options.path.startsWith('http://') &&
        !options.path.startsWith('https://')) {
      options.baseUrl = UrlService().baseUrl;
    }
    handler.next(options);
  }
}

class _AuthInterceptor extends Interceptor {
  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    final authEnabled = options.extra['auth'] != false;
    if (authEnabled) {
      final token = AuthTokenStore.token;
      if (token != null && token.isNotEmpty) {
        options.headers['Authorization'] = 'Bearer $token';
      }
    }
    handler.next(options);
  }
}

class _LogInterceptor extends Interceptor {
  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    options.extra['ts'] = DateTime.now().millisecondsSinceEpoch;
    handler.next(options);
  }

  @override
  void onResponse(Response response, ResponseInterceptorHandler handler) {
    final ts = response.requestOptions.extra['ts'] as int?;
    final duration = ts == null
        ? 0
        : DateTime.now().millisecondsSinceEpoch - ts;
    final method = response.requestOptions.method;
    final uri = response.requestOptions.uri.toString();
    final status = response.statusCode ?? 0;
    final line = '$method $uri $status ${duration}ms';
    DeveloperModeService().addLog('[Network] $line');
    handler.next(response);
  }

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) {
    final ts = err.requestOptions.extra['ts'] as int?;
    final duration = ts == null
        ? 0
        : DateTime.now().millisecondsSinceEpoch - ts;
    final method = err.requestOptions.method;
    final uri = err.requestOptions.uri.toString();
    final status = err.response?.statusCode ?? 0;
    final line = '$method $uri $status ${duration}ms error=${err.type}';
    DeveloperModeService().addLog('[Network] $line');
    handler.next(err);
  }
}

class _UnauthorizedInterceptor extends Interceptor {
  // Primary path: validateStatus accepts all status codes, so 401 arrives here
  // as a normal response (not a DioException).
  @override
  void onResponse(Response response, ResponseInterceptorHandler handler) {
    final authEnabled = response.requestOptions.extra['auth'] != false;
    if (authEnabled && response.statusCode == 401) {
      AuthTokenStore.onUnauthorized?.call();
    }
    handler.next(response);
  }

  // Defensive fallback: in case validateStatus changes or a plugin throws.
  @override
  void onError(DioException err, ErrorInterceptorHandler handler) {
    final authEnabled = err.requestOptions.extra['auth'] != false;
    if (authEnabled && err.response?.statusCode == 401) {
      AuthTokenStore.onUnauthorized?.call();
    }
    handler.next(err);
  }
}
