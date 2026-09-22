import 'structured_log_service.dart';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

class LxHttpBridge {
  static Future<Map<String, dynamic>> performHttpRequest(
    String url,
    Map<String, dynamic> options,
  ) async {
    try {
      final debug = kDebugMode;
      if (debug) {
        StructuredLogService.log('========== [HTTP Request Debug] ==========');
        StructuredLogService.log('🔍 [HTTP] 原始 URL: $url');
        StructuredLogService.log('🔍 [HTTP] 原始 options: $options');
        if (options['headers'] != null) {
          StructuredLogService.log('🔍 [HTTP] 原始 headers: ${options['headers']}');
          StructuredLogService.log('🔍 [HTTP] headers 类型: ${options['headers'].runtimeType}');
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
        response = await http.get(
          Uri.parse(url),
          headers: normalizedHeaders,
        ).timeout(const Duration(seconds: 30));
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
                .map((e) =>
                    '${Uri.encodeComponent(e.key.toString())}=${Uri.encodeComponent(e.value.toString())}')
                .join('&');
            contentType = 'application/x-www-form-urlencoded';
          }
        }

        if (contentType != null &&
            !normalizedHeaders.containsKey('content-type')) {
          normalizedHeaders['content-type'] = contentType;
        }

        response = await http.post(
          Uri.parse(url),
          headers: normalizedHeaders,
          body: body,
        ).timeout(const Duration(seconds: 30));
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
      StructuredLogService.log('❌ [HTTP] Error: $e');
      rethrow;
    }
  }
}
