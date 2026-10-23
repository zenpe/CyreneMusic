import 'dart:async';
import 'dart:io';

import 'package:http/io_client.dart';

/// Keeps the official IOClient transport, including its per-request aborts.
class LxHttpClient extends IOClient {
  LxHttpClient()
    : super(
        _ConnectionTimingHttpClient(
          HttpClient()..idleTimeout = const Duration(seconds: 45),
        ),
      );

  static final _observerKey = Object();

  static Future<T> observeConnection<T>(
    Future<T> Function() action,
    void Function() onReady,
  ) => runZoned(action, zoneValues: {_observerKey: onReady});
}

/// Observes the initial openUrl without replacing socket creation, TLS,
/// redirects, request bodies or cancellation. Acquisition includes pool waits
/// and, for a new HTTPS connection, DNS/TCP/TLS. It does not identify reuse.
/// Automatic redirects remain internal to the SDK and are counted in the
/// subsequent response wait rather than as a second acquisition measurement.
class _ConnectionTimingHttpClient implements HttpClient {
  _ConnectionTimingHttpClient(this._inner);

  final HttpClient _inner;

  @override
  Future<HttpClientRequest> openUrl(String method, Uri url) async {
    final onReady = Zone.current[LxHttpClient._observerKey] as void Function()?;
    final request = await _inner.openUrl(method, url);
    onReady?.call();
    return request;
  }

  @override
  bool get autoUncompress => _inner.autoUncompress;
  @override
  set autoUncompress(bool value) => _inner.autoUncompress = value;
  @override
  Duration? get connectionTimeout => _inner.connectionTimeout;
  @override
  set connectionTimeout(Duration? value) => _inner.connectionTimeout = value;
  @override
  Duration get idleTimeout => _inner.idleTimeout;
  @override
  set idleTimeout(Duration value) => _inner.idleTimeout = value;
  @override
  int? get maxConnectionsPerHost => _inner.maxConnectionsPerHost;
  @override
  set maxConnectionsPerHost(int? value) => _inner.maxConnectionsPerHost = value;
  @override
  String? get userAgent => _inner.userAgent;
  @override
  set userAgent(String? value) => _inner.userAgent = value;

  @override
  Future<HttpClientRequest> open(
    String method,
    String host,
    int port,
    String path,
  ) => _inner.open(method, host, port, path);
  @override
  Future<HttpClientRequest> get(String host, int port, String path) =>
      _inner.get(host, port, path);
  @override
  Future<HttpClientRequest> getUrl(Uri url) => _inner.getUrl(url);
  @override
  Future<HttpClientRequest> post(String host, int port, String path) =>
      _inner.post(host, port, path);
  @override
  Future<HttpClientRequest> postUrl(Uri url) => _inner.postUrl(url);
  @override
  Future<HttpClientRequest> put(String host, int port, String path) =>
      _inner.put(host, port, path);
  @override
  Future<HttpClientRequest> putUrl(Uri url) => _inner.putUrl(url);
  @override
  Future<HttpClientRequest> delete(String host, int port, String path) =>
      _inner.delete(host, port, path);
  @override
  Future<HttpClientRequest> deleteUrl(Uri url) => _inner.deleteUrl(url);
  @override
  Future<HttpClientRequest> patch(String host, int port, String path) =>
      _inner.patch(host, port, path);
  @override
  Future<HttpClientRequest> patchUrl(Uri url) => _inner.patchUrl(url);
  @override
  Future<HttpClientRequest> head(String host, int port, String path) =>
      _inner.head(host, port, path);
  @override
  Future<HttpClientRequest> headUrl(Uri url) => _inner.headUrl(url);

  @override
  set authenticate(Future<bool> Function(Uri, String, String?)? value) =>
      _inner.authenticate = value;
  @override
  void addCredentials(
    Uri url,
    String realm,
    HttpClientCredentials credentials,
  ) => _inner.addCredentials(url, realm, credentials);
  @override
  set authenticateProxy(
    Future<bool> Function(String, int, String, String?)? value,
  ) => _inner.authenticateProxy = value;
  @override
  void addProxyCredentials(
    String host,
    int port,
    String realm,
    HttpClientCredentials credentials,
  ) => _inner.addProxyCredentials(host, port, realm, credentials);
  @override
  set findProxy(String Function(Uri)? value) => _inner.findProxy = value;
  @override
  set connectionFactory(
    Future<ConnectionTask<Socket>> Function(Uri, String?, int?)? value,
  ) => _inner.connectionFactory = value;
  @override
  set badCertificateCallback(
    bool Function(X509Certificate, String, int)? value,
  ) => _inner.badCertificateCallback = value;
  @override
  set keyLog(Function(String)? value) => _inner.keyLog = value;
  @override
  void close({bool force = false}) => _inner.close(force: force);
}
