import 'structured_log_service.dart';
import 'dart:convert';
import 'dart:async';
import 'package:charset/charset.dart';
import 'lx_http_client.dart';
import 'lx_runtime_interface.dart';
import 'resolution_request.dart';
import 'package:http/http.dart' as http;

class LxHttpBridge {
  static const maxResponseBytes = 8 * 1024 * 1024;
  // Reuse idle connections; cancellation belongs to each HTTP request rather
  // than the client, which can also be serving another resolution.
  static http.Client? _client;

  /// Only for transport shutdown, never for cancelling a single resolution.
  static void close() {
    _client?.close();
    _client = null;
  }

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
    // Script timeouts are milliseconds. A script can shorten a request, never
    // extend the owning resolution's remaining deadline (including timeout=0).
    final scriptTimeout = options['timeout'];
    if (scriptTimeout is num && scriptTimeout.isFinite && scriptTimeout > 0) {
      final milliseconds = scriptTimeout.ceil();
      if (milliseconds < timeout.inMilliseconds) {
        timeout = Duration(milliseconds: milliseconds);
      }
    }
    final client = _client ??= LxHttpClient();
    final aborted = Completer<void>();
    void abort() {
      if (!aborted.isCompleted) aborted.complete();
    }

    final unsubscribe = request?.onCancel(abort);
    final clock = Stopwatch()..start();
    var stage = 'preparing';
    var finished = false;
    var outcome = 'success';
    String? failureType;
    int? sendStartedMs;
    int? connectionReadyMs;
    int? responseReceivedMs;
    int? status;
    String? transportHost;
    String? transportMethod;
    // The response wait includes sending the request and automatic redirects;
    // it is not a measurement of server processing time alone.
    Map<String, Object?> timingFields() {
      final elapsed = clock.elapsedMilliseconds;
      return {
        'request_id': requestId,
        'resolution_id': resolutionId,
        'elapsed_ms': elapsed,
        'connection_ready': connectionReadyMs != null,
        'connection_ms': sendStartedMs == null
            ? null
            : (connectionReadyMs ?? elapsed) - sendStartedMs!,
        'response_wait_ms': connectionReadyMs == null
            ? null
            : (responseReceivedMs ?? elapsed) - connectionReadyMs!,
        'body_ms': responseReceivedMs == null
            ? null
            : elapsed - responseReceivedMs!,
      };
    }

    Future<http.Response> sendAndRead(http.Request message) async {
      Duration remaining() {
        final value = timeout - clock.elapsed;
        return value.isNegative ? Duration.zero : value;
      }

      request?.check();
      stage = 'connection';
      sendStartedMs = clock.elapsedMilliseconds;
      transportHost = message.url.host;
      transportMethod = message.method;
      StructuredLogService.event(
        'lx.http_transport_started',
        fields: {
          'request_id': requestId,
          'resolution_id': resolutionId,
          'host': message.url.host,
          'method': message.method,
        },
      );
      final streamed = await LxHttpClient.observeConnection(
        () => client.send(message),
        () {
          // A timed-out openUrl may finish later. It must not modify the
          // already-recorded terminal result or emit a late ready event.
          if (finished) return;
          connectionReadyMs = clock.elapsedMilliseconds;
          stage = 'response_headers';
          StructuredLogService.event(
            'lx.http_connection_ready',
            fields: timingFields(),
          );
        },
      ).timeout(remaining());
      responseReceivedMs = clock.elapsedMilliseconds;
      status = streamed.statusCode;
      StructuredLogService.event(
        'lx.http_headers_received',
        fields: {
          ...timingFields(),
          'status': streamed.statusCode,
          'content_length': streamed.contentLength,
          'content_type': streamed.headers['content-type'],
          'transfer_encoding': streamed.headers['transfer-encoding'],
        },
      );
      stage = 'body';
      var byteCount = 0;
      final bytes = await http.ByteStream(
        streamed.stream.map((chunk) {
          byteCount += chunk.length;
          if (byteCount > maxResponseBytes) {
            abort();
            throw const FormatException('音源接口返回内容过大');
          }
          return chunk;
        }),
      ).toBytes().timeout(remaining());
      return http.Response.bytes(
        bytes,
        streamed.statusCode,
        headers: streamed.headers,
        reasonPhrase: streamed.reasonPhrase,
      );
    }

    try {
      final method = (options['method'] as String?)?.toUpperCase() ?? 'GET';
      final headers = <String, String>{};

      if (options['headers'] != null) {
        final headerMap = options['headers'];
        if (headerMap is Map) {
          headerMap.forEach((key, value) {
            headers[key.toString().toLowerCase()] = value.toString();
          });
        }
      }

      if (!headers.containsKey('user-agent')) {
        headers['user-agent'] = 'lx-music-request';
      }

      if (!headers.containsKey('accept')) {
        headers['accept'] = 'application/json';
      }

      // IOClient transparently decodes gzip, but not Brotli. Advertising br
      // can otherwise turn compressed bytes into apparent garbage text.
      headers['accept-encoding'] = 'gzip';

      if (method == 'GET') {
        headers.remove('content-type');
      }

      final normalizedHeaders = headers;

      http.Response response;

      if (method == 'GET' || method == 'HEAD') {
        response = await sendAndRead(
          http.AbortableRequest(
            method,
            Uri.parse(url),
            abortTrigger: aborted.future,
          )..headers.addAll(normalizedHeaders),
        );
      } else if (const [
        'POST',
        'PUT',
        'PATCH',
        'DELETE',
        'OPTIONS',
      ].contains(method)) {
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

        final message = http.AbortableRequest(
          method,
          Uri.parse(url),
          abortTrigger: aborted.future,
        )..headers.addAll(normalizedHeaders);
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

      request?.check();
      final contentEncoding = response.headers['content-encoding']
          ?.toLowerCase();
      if (contentEncoding != null &&
          contentEncoding != 'identity' &&
          contentEncoding != 'gzip') {
        throw const FormatException('音源接口返回了不支持的压缩格式');
      }
      final charset = RegExp(
        r'charset\s*=\s*["\x27]?([^;"\x27\s]+)',
        caseSensitive: false,
      ).firstMatch(response.headers['content-type'] ?? '')?.group(1);
      final encoding = charset == null ? utf8 : Charset.getByName(charset);
      if (encoding == null) {
        throw const FormatException('音源接口返回了不支持的字符编码');
      }
      final text = encoding.decode(response.bodyBytes);
      dynamic responseBody = text;
      if (options['json'] != false) {
        try {
          responseBody = jsonDecode(text);
        } catch (_) {
          // LX callbacks also accept plain text; browser APIs need it intact.
        }
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
      failureType = e.runtimeType.toString();
      outcome =
          e is TimeoutException ||
              request?.failure?.kind == LxRuntimeFailureKind.timeout
          ? 'timeout'
          : request?.isCancelled == true
          ? 'cancelled'
          : 'failure';
      if (request?.isCancelled == true) throw const ResolutionCancelled();
      rethrow;
    } finally {
      finished = true;
      unsubscribe?.call();
      // Future.timeout does not cancel its input. Abort on every exit so a
      // timed-out send/body cannot continue occupying a pooled connection.
      // Aborting an already completed response has no effect.
      abort();
      StructuredLogService.event(
        'lx.http_transport_ended',
        level: outcome == 'success' || outcome == 'cancelled'
            ? LogLevel.info
            : LogLevel.warning,
        fields: {
          ...timingFields(),
          'host': transportHost,
          'method': transportMethod,
          'stage': stage,
          'outcome': outcome,
          'status': status,
          'cancelled': request?.isCancelled == true,
          'failure_type': failureType,
        },
      );
    }
  }
}
