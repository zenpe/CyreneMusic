import 'structured_log_service.dart';
import 'dart:convert';
import 'dart:async';
import 'lx_http_client.dart';
import 'lx_runtime_interface.dart';
import 'resolution_request.dart';
import 'package:http/http.dart' as http;

class LxHttpBridge {
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
      return http.Response.fromStream(streamed).timeout(remaining());
    }

    try {
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

      http.Response response;

      if (method == 'GET') {
        response = await sendAndRead(
          http.AbortableRequest(
            'GET',
            Uri.parse(url),
            abortTrigger: aborted.future,
          )..headers.addAll(normalizedHeaders),
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

        final message = http.AbortableRequest(
          'POST',
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
