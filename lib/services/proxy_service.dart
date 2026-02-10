import 'dart:async';
import 'dart:io';
import 'dart:convert';
import 'package:shelf/shelf.dart' as shelf;
import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:http/http.dart' as http;
import 'developer_mode_service.dart';

/// 本地 HTTP 代理服务
/// 用于处理 QQ 音乐等需要特殊请求头的音频流
class ProxyService {
  static final ProxyService _instance = ProxyService._internal();
  factory ProxyService() => _instance;
  ProxyService._internal();

  HttpServer? _server;
  int _port = 8888;
  bool _isRunning = false;

  bool get isRunning => _isRunning;
  int get port => _port;

  /// 启动代理服务器
  Future<bool> start() async {
    if (_isRunning) {
      print('🌐 [ProxyService] 代理服务器已在运行');
      DeveloperModeService().addLog('🌐 [ProxyService] 代理服务器已在运行');
      return true;
    }

    try {
      // 尝试多个端口，避免端口冲突
      for (int port = 8888; port < 8898; port++) {
        try {
          print('🌐 [ProxyService] 尝试端口: $port');
          DeveloperModeService().addLog('🌐 [ProxyService] 尝试端口: $port');
          
          _server = await shelf_io.serve(
            _handleRequest,
            InternetAddress.loopbackIPv4,
            port,
          );
          _port = port;
          _isRunning = true;
          print('✅ [ProxyService] 代理服务器已启动: http://localhost:$_port');
          DeveloperModeService().addLog('✅ [ProxyService] 代理服务器已启动: http://localhost:$_port');
          return true;
        } catch (e) {
          print('⚠️ [ProxyService] 端口 $port 启动失败: $e');
          DeveloperModeService().addLog('⚠️ [ProxyService] 端口 $port 启动失败: $e');
          // 端口被占用，尝试下一个
          if (port == 8897) {
            throw Exception('无法找到可用端口 (8888-8897)');
          }
        }
      }
      return false;
    } catch (e, stackTrace) {
      print('❌ [ProxyService] 启动代理服务器失败: $e');
      print('Stack trace: $stackTrace');
      DeveloperModeService().addLog('❌ [ProxyService] 启动代理服务器失败: $e');
      DeveloperModeService().addLog('📜 [ProxyService] 堆栈: ${stackTrace.toString().split('\n').take(5).join(' | ')}');
      _isRunning = false;
      return false;
    }
  }

  /// 停止代理服务器
  Future<void> stop() async {
    if (_server != null) {
      await _server!.close();
      _server = null;
      _isRunning = false;
      print('⏹️ [ProxyService] 代理服务器已停止');
      DeveloperModeService().addLog('⏹️ [ProxyService] 代理服务器已停止');
    }
  }

  /// 处理代理请求
  Future<shelf.Response> _handleRequest(shelf.Request request) async {
    try {
      final method = request.method.toUpperCase();
      if (method != 'GET' && method != 'HEAD') {
        return shelf.Response(405, body: 'Method Not Allowed');
      }

      // 获取原始 URL
      var targetUrl = request.url.queryParameters['url'];
      if (targetUrl == null || targetUrl.isEmpty) {
        return shelf.Response.badRequest(body: 'Missing url parameter');
      }
      targetUrl = targetUrl.trim(); // 去除可能的空白字符

      // 获取平台类型（用于设置不同的 referer）
      final platform = request.url.queryParameters['platform'] ?? 'qq';

      final targetUri = Uri.parse(targetUrl);

      final rangeHeader = request.headers['range'];
      final rangeText = (rangeHeader != null && rangeHeader.isNotEmpty)
          ? ' range=$rangeHeader'
          : '';

      print('🌐 [ProxyService] 代理请求: $method $targetUrl$rangeText');
      DeveloperModeService().addLog(
        '🌐 [ProxyService] 代理请求: $method ${targetUrl.length > 100 ? '${targetUrl.substring(0, 100)}...' : targetUrl}$rangeText',
      );

      // 设置请求头
      // 统一移除可能引起冲突的原始头
      final targetHeaders = <String, String>{};
      request.headers.forEach((key, value) {
        final lowerKey = key.toLowerCase();
        if (lowerKey != 'host' &&
            lowerKey != 'connection' &&
            lowerKey != 'user-agent' &&
            lowerKey != 'referer' &&
            lowerKey != 'accept-encoding') { // 移除 accept-encoding，防止上游返回压缩数据
          targetHeaders[key] = value;
        }
      });
      // 强制使用 identity 编码，防止上游返回压缩数据导致流媒体解析失败
      targetHeaders['Accept-Encoding'] = 'identity';

      // 根据平台设置不同的 User-Agent 和 Referer
      if (platform == 'qq') {
        // QQ 音乐对 Headers 检查非常严格，尤其是 Origin 和 Referer
        // 模拟洛雪音乐桌面端使用的 UA，包含 lx-music-desktop 标识
        targetHeaders['User-Agent'] = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/114.0.0.0 Safari/537.36 lx-music-desktop/2.12.0';
        targetHeaders['Referer'] = 'https://y.qq.com';
        targetHeaders['Origin'] = 'https://y.qq.com';
        targetHeaders['Accept'] = 'audio/*,*/*;q=0.9';
        targetHeaders['Accept-Language'] = 'zh-CN,zh;q=0.9';
        // 移除 Sec-Fetch-* 等现代浏览器安全头，回归更传统的伪装
      } else if (platform == 'kugou') {
        targetHeaders['User-Agent'] = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/121.0.0.0 Safari/537.36';
        targetHeaders['Referer'] = 'https://www.kugou.com';
        targetHeaders['Accept'] = '*/*';
      } else if (platform == 'apple') {
        targetHeaders['User-Agent'] = 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.5 Safari/605.1.15';
        targetHeaders['Referer'] = 'https://music.apple.com';
        targetHeaders['Origin'] = 'https://music.apple.com';
        targetHeaders['Accept'] = 'audio/*,*/*;q=0.9';
        targetHeaders['Accept-Language'] = request.headers['accept-language'] ??
            'zh-CN,zh;q=0.9,en;q=0.8,en-GB;q=0.7,en-US;q=0.6';
        targetHeaders['Connection'] = 'keep-alive';
        targetHeaders['Cache-Control'] = 'no-cache';
        targetHeaders['Pragma'] = 'no-cache';
      } else {
        // 默认使用一个通用的 PC User-Agent
        targetHeaders['User-Agent'] = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/121.0.0.0 Safari/537.36';
        targetHeaders['Accept'] = '*/*';
      }

      final client = http.Client();
      final upstreamRequest = http.Request(method, targetUri);

      // 应用处理后的 Header
      targetHeaders.forEach((key, value) {
        upstreamRequest.headers[key] = value;
      });

      // 透传 Range 头
      if (rangeHeader != null && rangeHeader.isNotEmpty) {
        upstreamRequest.headers['Range'] = rangeHeader;
      }

      final isMaybeM3u8 = targetUri.path.toLowerCase().endsWith('.m3u8');
      print('🔍 [ProxyService] isMaybeM3u8: $isMaybeM3u8, path: ${targetUri.path}');

      // 发起请求（使用流式传输）
      http.StreamedResponse streamedResponse;
      try {
        streamedResponse = await client.send(upstreamRequest);
      } catch (e) {
        print('❌ [ProxyService] 发送上游请求失败: $e');
        client.close();
        rethrow;
      }

      final upstreamStatus = streamedResponse.statusCode;
      final upstreamContentRange = streamedResponse.headers['content-range'];
      final upstreamContentLength = streamedResponse.headers['content-length'];

      DeveloperModeService().addLog(
        '⬆️ [ProxyService] 上游响应: $upstreamStatus'
        '${upstreamContentLength != null ? ' len=$upstreamContentLength' : ''}'
        '${upstreamContentRange != null ? ' cr=$upstreamContentRange' : ''}',
      );

      final upstreamContentType =
          (streamedResponse.headers['content-type'] ?? '').toLowerCase();
      
      print('🔍 [ProxyService] Content-Type: $upstreamContentType');
      
      final isM3u8 = isMaybeM3u8 ||
          upstreamContentType.contains('mpegurl') ||
          upstreamContentType.contains('application/vnd.apple.mpegurl') ||
          upstreamContentType.contains('application/x-mpegurl');

      if (method == 'HEAD') {
        final responseHeaders = <String, String>{
          if (streamedResponse.headers['content-type'] != null)
            'Content-Type': streamedResponse.headers['content-type']!,
          'Accept-Ranges': streamedResponse.headers['accept-ranges'] ?? 'bytes',
          'Cache-Control': 'no-cache',
        };
        if (streamedResponse.headers['content-length'] != null) {
          responseHeaders['Content-Length'] =
              streamedResponse.headers['content-length']!;
        }
        if (streamedResponse.headers['content-range'] != null) {
          responseHeaders['Content-Range'] =
              streamedResponse.headers['content-range']!;
        }
        client.close();
        return shelf.Response(upstreamStatus, headers: responseHeaders);
      }

      if (isM3u8 && (upstreamStatus == 200 || upstreamStatus == 206)) {
        // m3u8 必须重写分片 URL，确保分片也走代理（否则鉴权会失败）
        final bodyBytes = await streamedResponse.stream.toBytes();
        client.close();
        final playlistText = utf8.decode(bodyBytes);
        final lines = playlistText.split(RegExp(r'\r?\n'));

        final rewritten = lines.map((line) {
          final trimmed = line.trim();
          if (trimmed.isEmpty) return line;
          if (trimmed.startsWith('#')) {
            final uriAttrRegex = RegExp(r'URI="([^"]+)"');
            if (!uriAttrRegex.hasMatch(line)) return line;

            return line.replaceAllMapped(uriAttrRegex, (m) {
              final raw = m.group(1);
              if (raw == null || raw.isEmpty) return m.group(0) ?? '';
              if (raw.startsWith('skd://')) return m.group(0) ?? '';

              Uri resolved;
              try {
                if (raw.startsWith('http://') || raw.startsWith('https://')) {
                  resolved = Uri.parse(raw);
                } else if (raw.startsWith('//')) {
                  resolved = Uri.parse('${targetUri.scheme}:$raw');
                } else {
                  resolved = targetUri.resolve(raw);
                }
              } catch (_) {
                return m.group(0) ?? '';
              }

              final proxied = getProxyUrl(resolved.toString(), platform);
              return 'URI="$proxied"';
            });
          }

          Uri resolved;
          try {
            if (trimmed.startsWith('http://') || trimmed.startsWith('https://')) {
              resolved = Uri.parse(trimmed);
            } else if (trimmed.startsWith('//')) {
              resolved = Uri.parse('${targetUri.scheme}:$trimmed');
            } else {
              resolved = targetUri.resolve(trimmed);
            }
          } catch (_) {
            return line;
          }

          return getProxyUrl(resolved.toString(), platform);
        }).join('\n');

        final responseHeaders = <String, String>{
          'Content-Type':
              streamedResponse.headers['content-type'] ?? 'application/vnd.apple.mpegurl',
          'Cache-Control': 'no-cache',
        };

        return shelf.Response.ok(
          rewritten,
          headers: responseHeaders,
        );
      }

      if (upstreamStatus == 200 || upstreamStatus == 206) {
        // 设置响应头
        final responseHeaders = <String, String>{
          'Content-Type': streamedResponse.headers['content-type'] ?? 'audio/mpeg',
          'Accept-Ranges': 'bytes',
          'Cache-Control': 'no-cache',
        };

        if (streamedResponse.headers['content-length'] != null) {
          responseHeaders['Content-Length'] =
              streamedResponse.headers['content-length']!;
        }
        if (upstreamStatus == 206 && streamedResponse.headers['content-range'] != null) {
          responseHeaders['Content-Range'] =
              streamedResponse.headers['content-range']!;
        }

        print('✅ [ProxyService] 开始流式传输音频数据');
        DeveloperModeService().addLog('✅ [ProxyService] 开始流式传输音频数据');
        final controller = StreamController<List<int>>();
        late final StreamSubscription<List<int>> sub;
        sub = streamedResponse.stream.listen(
          controller.add,
          onError: (e, st) {
            DeveloperModeService().addLog('❌ [ProxyService] 流式传输错误: $e');
            controller.addError(e, st);
            controller.close();
            client.close();
          },
          onDone: () async {
            await controller.close();
            client.close();
          },
          cancelOnError: false,
        );
        controller.onCancel = () async {
          await sub.cancel();
          client.close();
        };

        return shelf.Response(
          upstreamStatus,
          body: controller.stream,
          headers: responseHeaders,
        );
      }

        print('❌ [ProxyService] 上游服务器返回: $upstreamStatus');
        DeveloperModeService().addLog('❌ [ProxyService] 上游服务器返回: $upstreamStatus');
        client.close();
        return shelf.Response(
          upstreamStatus,
          body: 'Upstream server error: $upstreamStatus',
        );
    } catch (e, stackTrace) {
      print('❌ [ProxyService] 处理请求失败: $e');
      print('Stack trace: $stackTrace');
      DeveloperModeService().addLog('❌ [ProxyService] 处理请求失败: $e');
      DeveloperModeService().addLog('📜 [ProxyService] 堆栈: ${stackTrace.toString().split('\n').take(3).join(' | ')}');
      return shelf.Response.internalServerError(
        body: 'Proxy error: $e',
      );
    }
  }

  /// 生成代理 URL
  String getProxyUrl(String originalUrl, String platform) {
    if (!_isRunning) {
      print('⚠️ [ProxyService] 代理服务器未运行，返回原始 URL');
      DeveloperModeService().addLog('⚠️ [ProxyService] 代理服务器未运行，返回原始 URL');
      return originalUrl;
    }
    
    final encodedUrl = Uri.encodeComponent(originalUrl);
    final proxyUrl = 'http://localhost:$_port/proxy?url=$encodedUrl&platform=$platform';
    
    print('🔗 [ProxyService] 生成代理 URL: $proxyUrl');
    DeveloperModeService().addLog('🔗 [ProxyService] 生成代理 URL (端口: $_port, 平台: $platform)');
    return proxyUrl;
  }

  /// 清理资源
  Future<void> dispose() async {
    await stop();
  }
}

