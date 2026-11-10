import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../models/track.dart';
import '../utils/audio_request_headers.dart';
import 'playback/audio_transport_failure.dart';
import 'structured_log_service.dart';

/// Desktop audio transport. Each source owns an opaque local route, so errors
/// and cancellation cannot leak into another song's request.
class ProxyService {
  static final ProxyService _instance = ProxyService._();
  factory ProxyService() => _instance;
  ProxyService._()
    : headerTimeout = const Duration(seconds: 6),
      idleTimeout = const Duration(seconds: 8);

  ProxyService.forTesting({
    this.headerTimeout = const Duration(seconds: 6),
    this.idleTimeout = const Duration(seconds: 8),
  });

  final Duration headerTimeout;
  final Duration idleTimeout;
  HttpServer? _server;
  Future<bool>? _starting;
  Future<void>? _stopping;
  int _sequence = 0;
  int _revision = 0;
  final Map<String, _AudioRoute> _routes = {};
  final Set<_AudioTransfer> _transfers = {};

  bool get isRunning => _server != null;
  int get port => _server?.port ?? 0;

  Future<bool> start() async {
    final revision = _revision;
    await _stopping;
    if (revision != _revision) return false;
    if (isRunning) return true;
    return _starting ??= _start(revision);
  }

  Future<bool> _start(int revision) async {
    try {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      if (revision != _revision) {
        await server.close(force: true);
        return false;
      }
      _server = server;
      server.listen((request) => unawaited(_handleRequest(request)));
      return true;
    } catch (error) {
      StructuredLogService.event(
        'audio_proxy.start_failed',
        level: LogLevel.error,
        error: error,
      );
      return false;
    } finally {
      _starting = null;
    }
  }

  Future<void> stop() {
    if (_stopping != null) return _stopping!;
    _revision++;
    return _stopping = _stop();
  }

  Future<void> _stop() async {
    try {
      await _starting;
      final server = _server;
      _server = null;
      for (final transfer in _transfers.toList()) {
        transfer.cancel();
      }
      _routes.clear();
      await server?.close(force: true);
    } finally {
      _stopping = null;
    }
  }

  Future<void> dispose() => stop();

  String getProxyUrl(String originalUrl, String platform) =>
      _register(Uri.parse(originalUrl), platform);

  String _register(Uri target, String platform, {String? group}) {
    if (!isRunning) throw StateError('Audio proxy is not running');
    if ((target.scheme != 'http' && target.scheme != 'https') ||
        target.host.isEmpty) {
      throw const FormatException('Invalid audio URL');
    }
    // Bound abandoned preloads; HLS child routes share their parent's scope.
    if (group != null) {
      for (final entry in _routes.entries) {
        if (entry.value.group == group && entry.value.target == target) {
          return 'http://127.0.0.1:$port/proxy/${entry.key}';
        }
      }
      if (_routes.values.where((route) => route.group == group).length >=
          10000) {
        throw const FormatException('Audio manifest has too many resources');
      }
    } else {
      while (_routes.entries.where((e) => e.key == e.value.group).length >=
          64) {
        final victim = _routes.entries.firstWhere(
          (e) => e.key == e.value.group,
        );
        _releaseGroup(victim.key);
      }
    }
    final id = (++_sequence).toString();
    _routes[id] = _AudioRoute(target, platform, group ?? id);
    return 'http://127.0.0.1:$port/proxy/$id';
  }

  _AudioRoute? _routeFor(String? localUrl) {
    final uri = Uri.tryParse(localUrl ?? '');
    if (uri == null ||
        uri.host != '127.0.0.1' ||
        uri.port != port ||
        uri.pathSegments.length != 2 ||
        uri.pathSegments.first != 'proxy') {
      return null;
    }
    return _routes[uri.pathSegments.last];
  }

  AudioTransportFailure? failureFor(String? localUrl) {
    final route = _routeFor(localUrl);
    return route == null ? null : _routes[route.group]?.failure;
  }

  void release(String? localUrl) {
    final route = _routeFor(localUrl);
    if (route != null) _releaseGroup(route.group);
  }

  void _releaseGroup(String group) {
    _routes.removeWhere((_, route) => route.group == group);
    for (final transfer in _transfers.toList()) {
      if (transfer.group == group) transfer.cancel();
    }
  }

  void _recordFailure(
    _AudioRoute route,
    AudioTransportFailure failure,
    Stopwatch clock, {
    int receivedBytes = 0,
    int? headersMs,
  }) {
    final root = _routes[route.group];
    if (root == null) return;
    root.failure = failure;
    StructuredLogService.event(
      'audio_proxy.failed',
      level: LogLevel.warning,
      fields: {
        'request_id': route.group,
        'host': route.target.host,
        'platform': route.platform,
        'stage': failure.stage.name,
        'status': failure.statusCode,
        'timed_out': failure.timedOut,
        'elapsed_ms': clock.elapsedMilliseconds,
        'headers_ms': headersMs,
        'received_bytes': receivedBytes,
        'timeout_ms': failure.stage == AudioTransportStage.read
            ? idleTimeout.inMilliseconds
            : headerTimeout.inMilliseconds,
      },
    );
  }

  Future<void> _handleRequest(HttpRequest request) async {
    final response = request.response;
    _AudioTransfer? transfer;
    _AudioRoute? route;
    final clock = Stopwatch()..start();
    var stage = AudioTransportStage.connect;
    var headersSent = false;
    var receivedBytes = 0;
    int? headersMs;
    try {
      if (request.method != 'GET' && request.method != 'HEAD') {
        response.statusCode = HttpStatus.methodNotAllowed;
        return;
      }
      final segments = request.uri.pathSegments;
      route = segments.length == 2 && segments.first == 'proxy'
          ? _routes[segments.last]
          : null;
      if (route == null) {
        response.statusCode = HttpStatus.gone;
        return;
      }
      final client = HttpClient()
        ..autoUncompress = false
        ..connectionTimeout = headerTimeout;
      transfer = _AudioTransfer(route.group, client, response);
      _transfers.add(transfer);
      final current = transfer;
      unawaited(
        response.done.then<void>(
          (_) => current.cancel(),
          onError: (Object error, StackTrace stack) => current.cancel(),
        ),
      );
      final upstream = await (() async {
        final outgoing = await client.openUrl(request.method, route!.target);
        final source = route.platform == 'qq'
            ? MusicSource.qq
            : route.platform == 'kugou'
            ? MusicSource.kugou
            : MusicSource.netease;
        buildAudioRequestHeaders(source).forEach(outgoing.headers.set);
        outgoing.headers.set(HttpHeaders.acceptEncodingHeader, 'identity');
        for (final name in ['range', 'if-range', 'accept']) {
          final value = request.headers.value(name);
          if (value != null) outgoing.headers.set(name, value);
        }
        return await outgoing.close();
      })().timeout(headerTimeout);
      if (current.cancelled) return;
      headersMs = clock.elapsedMilliseconds;
      final status = upstream.statusCode;
      if (status != 200 && status != 206) {
        _recordFailure(
          route,
          AudioTransportFailure(
            AudioTransportStage.upstream,
            statusCode: status,
          ),
          clock,
        );
        response.statusCode = status;
        response.write('Audio upstream unavailable');
        return;
      }
      stage = AudioTransportStage.read;
      final body = upstream.timeout(idleTimeout).map((chunk) {
        receivedBytes += chunk.length;
        return chunk;
      });
      final effectiveUri = upstream.redirects.fold<Uri>(
        route.target,
        (uri, redirect) => uri.resolveUri(redirect.location),
      );
      final type = upstream.headers.contentType?.toString() ?? 'audio/mpeg';
      final hls =
          route.target.path.toLowerCase().endsWith('.m3u8') ||
          type.toLowerCase().contains('mpegurl');
      response.statusCode = status;
      response.headers.set(HttpHeaders.contentTypeHeader, type);
      response.headers.set(HttpHeaders.cacheControlHeader, 'no-store');
      if (hls && request.method != 'HEAD') {
        final bytes = <int>[];
        await for (final chunk in body) {
          bytes.addAll(chunk);
          if (bytes.length > 2 * 1024 * 1024) {
            throw const FormatException('Audio manifest too large');
          }
        }
        if (current.cancelled) return;
        String rewrite(String raw) {
          final target = effectiveUri.resolve(raw);
          if (target.scheme != 'http' && target.scheme != 'https') return raw;
          return _register(target, route!.platform, group: route.group);
        }

        final manifest = utf8
            .decode(bytes)
            .split(RegExp(r'\r?\n'))
            .map((line) {
              final trimmed = line.trim();
              if (trimmed.isEmpty) return line;
              if (trimmed.startsWith('#')) {
                return line.replaceAllMapped(
                  RegExp(r'URI="([^"]+)"'),
                  (match) => 'URI="${rewrite(match[1]!)}"',
                );
              }
              return rewrite(trimmed);
            })
            .join('\n');
        response.write(manifest);
      } else {
        for (final name in [
          'content-length',
          'content-range',
          'accept-ranges',
        ]) {
          final value = upstream.headers.value(name);
          if (value != null) response.headers.set(name, value);
        }
        if (request.method != 'HEAD') {
          headersSent = true;
          await response.addStream(body);
        }
      }
    } catch (error) {
      if (transfer?.cancelled != true && route != null) {
        _recordFailure(
          route,
          AudioTransportFailure(stage, timedOut: error is TimeoutException),
          clock,
          receivedBytes: receivedBytes,
          headersMs: headersMs,
        );
        if (!headersSent) {
          response.statusCode = error is TimeoutException ? 504 : 502;
          response.headers.removeAll(HttpHeaders.contentLengthHeader);
          response.write('Audio connection failed');
        }
      }
    } finally {
      if (transfer != null) {
        transfer.client.close(force: true);
        _transfers.remove(transfer);
      }
      try {
        await response.close();
      } catch (_) {}
    }
  }
}

class _AudioRoute {
  final Uri target;
  final String platform;
  final String group;
  AudioTransportFailure? failure;
  _AudioRoute(this.target, this.platform, this.group);
}

class _AudioTransfer {
  final String group;
  final HttpClient client;
  final HttpResponse response;
  bool cancelled = false;
  _AudioTransfer(this.group, this.client, this.response);

  void cancel() {
    if (cancelled) return;
    cancelled = true;
    client.close(force: true);
    unawaited(response.close().then<void>((_) {}, onError: (Object _) {}));
  }
}
