import 'dart:convert';
import 'dart:developer' as developer;

import 'package:flutter/foundation.dart';

enum LogLevel { debug, info, warning, error }

typedef StructuredLogSink = void Function(String line);

class StructuredLogService {
  StructuredLogService._();

  static StructuredLogSink? sink;

  static void event(
    String event, {
    LogLevel level = LogLevel.info,
    Map<String, Object?> fields = const {},
    Object? error,
  }) {
    if (kReleaseMode && level.index < LogLevel.warning.index) {
      return;
    }
    final payload = <String, Object?>{
      'ts': DateTime.now().toUtc().toIso8601String(),
      'level': level.name,
      'event': event,
      ..._redactMap(fields),
      if (error != null) 'error': _sanitizeText(error.toString()),
    };
    final line = jsonEncode(payload);
    final output = sink;
    if (output != null) {
      output(line);
      return;
    }
    developer.log(line, name: 'cyrene');
  }

  static Map<String, Object?> _redactMap(Map<String, Object?> input) {
    return input.map((key, value) {
      final normalized = key.toLowerCase();
      if (_sensitiveKeys.any(normalized.contains)) {
        return MapEntry(key, '<redacted>');
      }
      return MapEntry(key, _redactValue(value));
    });
  }

  static Object? _redactValue(Object? value) {
    if (value is Map<String, Object?>) {
      return _redactMap(value);
    }
    if (value is Iterable) {
      return value.map(_redactValue).toList(growable: false);
    }
    if (value is String) {
      return _sanitizeText(value);
    }
    return value;
  }

  static String _sanitizeText(String value) {
    var result = value.replaceAll(
      RegExp(r'https?://[^\s]+', caseSensitive: false),
      '<url>',
    );
    result = result.replaceAllMapped(
      RegExp(
        r'(token|cookie|authorization|password|secret)=([^&\s,]+)',
        caseSensitive: false,
      ),
      (match) => '${match.group(1)}=<redacted>',
    );
    return result;
  }

  static const _sensitiveKeys = <String>{
    'url',
    'token',
    'cookie',
    'authorization',
    'password',
    'secret',
    'script',
    'headers',
  };
}

class OperationTrace {
  final String operation;
  final Map<String, Object?> context;
  final Stopwatch _total = Stopwatch()..start();
  int _lastMarkMs = 0;

  OperationTrace(this.operation, {this.context = const {}}) {
    mark('start');
  }

  int get elapsedMilliseconds => _total.elapsedMilliseconds;

  void mark(
    String stage, {
    LogLevel level = LogLevel.info,
    Map<String, Object?> fields = const {},
    Object? error,
  }) {
    final elapsed = _total.elapsedMilliseconds;
    StructuredLogService.event(
      '$operation.$stage',
      level: level,
      fields: {
        ...context,
        'stage_ms': elapsed - _lastMarkMs,
        'total_ms': elapsed,
        ...fields,
      },
      error: error,
    );
    _lastMarkMs = elapsed;
  }
}
