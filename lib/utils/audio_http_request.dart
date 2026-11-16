import 'dart:io';

import 'package:http/http.dart' as http;

import '../models/track.dart';
import 'audio_request_headers.dart';

const _redirectStatuses = {301, 302, 303, 307, 308};

Uri _redirectTarget(Uri current, String location) {
  final next = current.resolve(location);
  if (!{'http', 'https'}.contains(next.scheme) ||
      next.host.isEmpty ||
      next.userInfo.isNotEmpty) {
    throw const HttpException('Invalid audio redirect');
  }
  return next;
}

/// Only GET/HEAD audio transfers. Recompute platform headers at every hop;
/// native automatic redirects can otherwise carry a Referer to another CDN.
Future<({HttpClientResponse response, Uri uri})> openAudioRequest(
  HttpClient client,
  String method,
  Uri uri,
  MusicSource source, {
  Map<String, String> headers = const {},
}) async {
  for (var redirects = 0; ; redirects++) {
    final request = await client.openUrl(method, uri);
    request.followRedirects = false;
    buildAudioRequestHeaders(source, uri: uri).forEach(request.headers.set);
    headers.forEach(request.headers.set);
    request.headers.set(HttpHeaders.acceptEncodingHeader, 'identity');
    final response = await request.close();
    final location = response.headers.value(HttpHeaders.locationHeader);
    if (!_redirectStatuses.contains(response.statusCode) || location == null) {
      return (response: response, uri: uri);
    }
    // Do not read arbitrarily large redirect bodies just to reuse a connection.
    await response.listen((_) {}).cancel();
    if (redirects >= 5) throw const HttpException('Audio redirect limit');
    uri = _redirectTarget(uri, location);
  }
}

/// The cache uses package:http; share the same per-hop audio header policy.
class AudioHttpClient extends http.BaseClient {
  AudioHttpClient(this._inner, this.source);

  final http.Client _inner;
  final MusicSource source;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    if (request.method != 'GET' && request.method != 'HEAD') {
      throw ArgumentError('Audio transfers require GET or HEAD');
    }
    var uri = request.url;
    for (var redirects = 0; ; redirects++) {
      final outgoing =
          http.AbortableRequest(
              request.method,
              uri,
              abortTrigger: request is http.Abortable
                  ? request.abortTrigger
                  : null,
            )
            ..followRedirects = false
            ..headers.addAll(buildAudioRequestHeaders(source, uri: uri))
            ..headers['Accept-Encoding'] = 'identity';
      for (final name in ['range', 'if-range', 'accept']) {
        final value = request.headers[name];
        if (value != null) outgoing.headers[name] = value;
      }
      final response = await _inner.send(outgoing);
      final location = response.headers['location'];
      if (!_redirectStatuses.contains(response.statusCode) ||
          location == null) {
        return response;
      }
      await response.stream.listen((_) {}).cancel();
      if (redirects >= 5) throw const HttpException('Audio redirect limit');
      uri = _redirectTarget(uri, location);
    }
  }

  @override
  void close() => _inner.close();
}
