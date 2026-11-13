import 'dart:convert';
import 'dart:async';
import 'dart:developer' as developer;

import 'package:flutter/foundation.dart';

enum LogLevel { debug, info, warning, error }

typedef StructuredLogSink = void Function(String line);

class StructuredLogService {
  StructuredLogService._();

  static StructuredLogSink? sink;
  static final _listeners = <void Function(Map<String, Object?>)>{};
  static final _contextKey = Object();
  static final _detailedKey = Object();

  /// Observers receive the same redacted payload as the console/sink.
  static void Function() listen(void Function(Map<String, Object?>) listener) {
    _listeners.add(listener);
    return () => _listeners.remove(listener);
  }

  /// Context follows asynchronous callbacks, including late worker HTTP events.
  static T inContext<T>({
    required Map<String, Object?> fields,
    required bool detailed,
    required T Function() action,
  }) => runZoned(
    action,
    zoneValues: {_contextKey: fields, _detailedKey: detailed},
  );

  static void _notify(Map<String, Object?> payload) {
    for (final listener in _listeners.toList()) {
      try {
        listener(Map.unmodifiable(payload));
      } catch (_) {
        // Diagnostics must never change the operation being observed.
      }
    }
  }

  /// A worker already serialized/redacted this event. Do not emit it twice.
  static void relay(String line) {
    if (_listeners.isEmpty) return;
    try {
      final payload = jsonDecode(line);
      if (payload is Map<String, dynamic>) _notify(_redactMap(payload));
    } catch (_) {
      // Ignore malformed diagnostics without interrupting worker delivery.
    }
  }

  static String sanitizeText(String value) => _sanitizeText(value);

  /// Records a free-form diagnostic message without writing directly to stdout.
  static void log(Object? message, {LogLevel level = LogLevel.debug}) {
    event(
      'diagnostic.message',
      level: level,
      fields: {'message': message?.toString() ?? 'null'},
    );
  }

  static void event(
    String event, {
    LogLevel level = LogLevel.info,
    Map<String, Object?> fields = const {},
    Object? error,
  }) {
    if (kReleaseMode &&
        level.index < LogLevel.warning.index &&
        _listeners.isEmpty &&
        Zone.current[_detailedKey] != true) {
      return;
    }
    final payload = <String, Object?>{
      ..._redactMap(
        Zone.current[_contextKey] as Map<String, Object?>? ?? const {},
      ),
      'ts': DateTime.now().toUtc().toIso8601String(),
      'level': level.name,
      'event': event,
      ..._redactMap(fields),
      if (error != null) 'error': _sanitizeText(error.toString()),
    };
    final line = jsonEncode(payload);
    _notify(payload);
    final output = sink;
    if (output != null) {
      output(line);
      return;
    }
    if (kReleaseMode || level.index >= LogLevel.warning.index) {
      Zone.root.print(line);
    } else {
      developer.log(line, name: 'cyrene');
    }
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
    result = result.replaceAll(
      RegExp(r'\bBearer\s+[^\s,;]+', caseSensitive: false),
      'Bearer <redacted>',
    );
    result = result.replaceAllMapped(
      RegExp(
        r'''((?:api[_-]?key|card[_-]?key|access[_-]?token|token|cookie|authorization|password|secret|signature|sign|key)["']?\s*[:=]\s*)(?:"[^"]*"|'[^']*'|[^&\s,;}]+)''',
        caseSensitive: false,
      ),
      (match) => '${match.group(1)}<redacted>',
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
    'card_key',
    'card-key',
    'resolver_fp',
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
