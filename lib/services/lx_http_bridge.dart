import 'structured_log_service.dart';
import 'dart:convert';
import 'dart:async';
import 'resolution_request.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

class LxHttpBridge {
  static Future<Map<String, dynamic>> performHttpRequest(
    String url,
    Map<String, dynamic> options, {
    Duration timeout = const Duration(seconds: 30),
    ResolutionRequest? request,
    String? requestId,
    String? resolutionId,
  }) async {
    request ??= ResolutionRequest.current;
    request?.check();
    final client = http.Client();
    final unsubscribe = request?.onCancel(client.close);
    final clock = Stopwatch()..start();
    var stage = 'headers';
    Future<http.Response> sendAndRead(http.Request message) async {
      Duration remaining() {
        final value = timeout - clock.elapsed;
        return value.isNegative ? Duration.zero : value;
      }

      final streamed = await client.send(message).timeout(remaining());
      StructuredLogService.event(
        'lx.http_headers_received',
        fields: {
          'request_id': requestId,
          'resolution_id': resolutionId,
          'elapsed_ms': clock.elapsedMilliseconds,
          'status': streamed.statusCode,
          'content_length': streamed.contentLength,
          'content_type': streamed.headers['content-type'],
          'transfer_encoding': streamed.headers['transfer-encoding'],
        },
      );
      stage = 'body';
      return http.Response.fromStream(streamed).timeout(remaining());
    }

    try {
      final debug = kDebugMode;
      if (debug) {
        StructuredLogService.log('========== [HTTP Request Debug] ==========');
        StructuredLogService.log('🔍 [HTTP] 原始 URL: $url');
        StructuredLogService.log('🔍 [HTTP] 原始 options: $options');
        if (options['headers'] != null) {
          StructuredLogService.log(
            '🔍 [HTTP] 原始 headers: ${options['headers']}',
          );
          StructuredLogService.log(
            '🔍 [HTTP] headers 类型: ${options['headers'].runtimeType}',
          );
        } else {
          StructuredLogService.log('🔍 [HTTP] 原始 headers: (null - 脚本未传递请求头)');
        }
        StructuredLogService.log('==========================================');
      }

      final method = (options['method'] as String?)?.toUpperCase() ?? 'GET';
      final headers = <String, String>{};

      if (options['headers'] != null) {
        final headerMap = options['headers'];
        if (headerMap is Map) {
          headerMap.forEach((key, value) {
            headers[key.toString()] = value.toString();
          });
        }
      }

      if (!headers.containsKey('User-Agent')) {
        headers['User-Agent'] = 'lx-music-request';
      }

      if (!headers.containsKey('accept') && !headers.containsKey('Accept')) {
        headers['accept'] = 'application/json';
      }

      if (method == 'GET') {
        headers.remove('Content-Type');
        headers.remove('content-type');
      }

      final normalizedHeaders = <String, String>{};
      headers.forEach((key, value) {
        normalizedHeaders[key.toLowerCase()] = value;
      });

      if (debug) {
        StructuredLogService.log('🌐 [HTTP] $method $url');
        StructuredLogService.log('   Headers (原始): $headers');
        StructuredLogService.log('   Headers (规范化): $normalizedHeaders');
      }

      http.Response response;

      if (method == 'GET') {
        response = await sendAndRead(
          http.Request('GET', Uri.parse(url))
            ..headers.addAll(normalizedHeaders),
        );
      } else if (method == 'POST') {
        dynamic body;
        String? contentType;

        if (options['body'] != null) {
          body = options['body'];
          if (body is Map) {
            body = jsonEncode(body);
            contentType = 'application/json';
          }
        } else if (options['form'] != null) {
          body = options['form'];
          if (body is Map) {
            body = body.entries
                .map(
                  (e) =>
                      '${Uri.encodeComponent(e.key.toString())}=${Uri.encodeComponent(e.value.toString())}',
                )
                .join('&');
            contentType = 'application/x-www-form-urlencoded';
          }
        }

        if (contentType != null &&
            !normalizedHeaders.containsKey('content-type')) {
          normalizedHeaders['content-type'] = contentType;
        }

        final message = http.Request('POST', Uri.parse(url))
          ..headers.addAll(normalizedHeaders);
        if (body is String) {
          message.body = body;
        } else if (body is List) {
          message.bodyBytes = body.cast<int>();
        } else if (body != null) {
          throw ArgumentError(
            'Unsupported HTTP body type: ${body.runtimeType}',
          );
        }
        response = await sendAndRead(message);
      } else {
        throw Exception('Unsupported HTTP method: $method');
      }

      if (debug) {
        StructuredLogService.log('📥 [HTTP] Status: ${response.statusCode}');
      }

      dynamic responseBody = response.body;
      try {
        responseBody = jsonDecode(response.body);
      } catch (_) {
        // Not JSON
      }

      return {
        'statusCode': response.statusCode,
        'statusMessage': response.reasonPhrase ?? '',
        'headers': response.headers,
        'body': responseBody,
        'raw': response.bodyBytes,
        'bytes': response.bodyBytes.length,
      };
    } catch (e) {
      StructuredLogService.event(
        'lx.http_transport_ended',
        level: request?.isCancelled == true ? LogLevel.info : LogLevel.warning,
        fields: {
          'request_id': requestId,
          'resolution_id': resolutionId,
          'stage': stage,
          'elapsed_ms': clock.elapsedMilliseconds,
          'cancelled': request?.isCancelled == true,
          'failure_type': e.runtimeType.toString(),
        },
      );
      if (request?.isCancelled == true) throw const ResolutionCancelled();
      StructuredLogService.log('❌ [HTTP] Error: $e');
      rethrow;
    } finally {
      unsubscribe?.call();
      client.close();
    }
  }
}
