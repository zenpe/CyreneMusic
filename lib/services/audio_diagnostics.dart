import 'structured_log_service.dart';

/// Presentation of observed facts only; never used for playback decisions.
class AudioDiagnostics {
  AudioDiagnostics._();

  static String compact(Object? value, {int limit = 240}) {
    String raw;
    try {
      raw = value?.toString() ?? '未记录';
    } catch (_) {
      return '无法格式化诊断信息';
    }
    final text = StructuredLogService.sanitizeText(raw)
        .split(RegExp(r'[\r\n]'))
        .first
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    return text.length > limit ? '${text.substring(0, limit)}…' : text;
  }

  static String? businessMessage(Object? body) {
    if (body is! Map) return null;
    for (final key in ['msg', 'message', 'error']) {
      final value = body[key];
      if (value is String && value.trim().isNotEmpty) return compact(value);
    }
    return null;
  }

  static Object? businessCode(Object? body) {
    if (body is! Map) return null;
    final code = body['code'];
    return code is num
        ? code
        : code is String
        ? compact(code, limit: 64)
        : null;
  }

  static String? format(Map<String, Object?> event) {
    final name = event['event'];
    // Keep unrelated startup/statistics logs out of the audio diagnostic feed.
    if (name is! String ||
        !(name.startsWith('lx.') || name.startsWith('audio_proxy.'))) {
      return null;
    }
    final context = [
      if (event['playback_tx'] != null) 'tx=${event['playback_tx']}',
      if (event['playback_request'] != null)
        'request=${event['playback_request']}',
      if (event['purpose'] != null) 'purpose=${event['purpose']}',
      if (event['source_name'] != null) '音源=${compact(event['source_name'])}',
      if (event['source'] != null) '平台=${compact(event['source'])}',
      if (event['quality'] != null) '音质=${compact(event['quality'])}',
      if (event['playback_track'] != null)
        'track=${compact(event['playback_track'])}',
      if (event['request_id'] != null) '子请求=${event['request_id']}',
    ].join(' ');
    String field(String key) => compact(event[key]);
    switch (name) {
      case 'lx.http_transport_started':
        return '[音源HTTP] 发起 $context 主机=${field('host')} 方法=${field('method')}';
      case 'lx.http_response':
        return '[音源HTTP] 响应 $context 主机=${field('host')} '
            'HTTP=${field('status')} 业务码=${field('business_code')} '
            '消息=${field('business_message')} 耗时=${field('elapsed_ms')}ms '
            '内容=${field('body_type')} 类型=${field('content_type')} '
            '字节=${field('bytes')}（HTTP成功不代表业务成功）';
      case 'lx.http_transport_ended':
        if (event['outcome'] == 'success' || event['outcome'] == 'cancelled') {
          return null;
        }
        return '[音源HTTP] 传输结束 $context 主机=${field('host')} '
            '结果=${field('outcome')} 阶段=${field('stage')} '
            'HTTP=${field('status')} 耗时=${field('elapsed_ms')}ms '
            '错误=${field('failure_type')}';
      case 'lx.http_failed':
        return '[音源HTTP] 请求或回调失败 $context '
            '耗时=${field('elapsed_ms')}ms 原因=${field('error')}';
      case 'lx.music_url_failed':
        return '[音源解析] 失败 $context 平台=${field('source')} '
            '音质=${field('quality')} 耗时=${field('elapsed_ms')}ms '
            '最后响应HTTP=${field('last_http_status')} '
            '最后业务码=${field('last_business_code')} '
            '脚本错误=${field('error')}（最后响应仅供排查，不代表所有后端）';
      case 'audio_proxy.response':
        return '[音频下载] 响应 $context 主机=${field('host')} '
            '平台=${field('platform')} HTTP=${field('status')} '
            '类型=${field('content_type')} 长度=${field('content_length')} '
            '耗时=${field('elapsed_ms')}ms（尚未确认可解码）';
      case 'audio_proxy.failed':
        return '[音频下载] 失败 $context 主机=${field('host')} '
            '阶段=${field('stage')} HTTP=${field('status')} '
            '超时=${field('timed_out')} 已收字节=${field('received_bytes')} '
            '耗时=${field('elapsed_ms')}ms';
      default:
        return null;
    }
  }
}
