import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'playback/command_queue.dart';

class AndroidEqualizerService {
  static final AndroidEqualizerService _instance =
      AndroidEqualizerService._internal();
  factory AndroidEqualizerService() => _instance;
  AndroidEqualizerService._internal();

  static const MethodChannel _channel = MethodChannel(
    'com.cyrene.music/android_equalizer',
  );
  static const Duration _platformCallTimeout = Duration(milliseconds: 500);

  int? _attachedSessionId;
  int? _requestedSessionId;
  final CommandQueue _operations = CommandQueue();

  Future<bool> attachToSession(int sessionId) =>
      _operations.enqueue(() => _attachToSession(sessionId));

  Future<bool> _attachToSession(int sessionId) async {
    if (!Platform.isAndroid || sessionId <= 0) return false;
    if (_attachedSessionId == sessionId) return true;
    _attachedSessionId = null;
    _requestedSessionId = sessionId;

    try {
      final ok =
          await _channel
              .invokeMethod<bool>('attach', {'sessionId': sessionId})
              .timeout(_platformCallTimeout) ??
          false;
      if (ok) {
        _attachedSessionId = sessionId;
      }
      return ok;
    } catch (_) {
      return false;
    }
  }

  Future<bool> apply({
    required int sessionId,
    required bool enabled,
    required List<double> gains,
    required List<int> frequencies,
  }) => _operations.enqueue(
    () => _apply(
      sessionId: sessionId,
      enabled: enabled,
      gains: List.of(gains),
      frequencies: List.of(frequencies),
    ),
  );

  Future<bool> _apply({
    required int sessionId,
    required bool enabled,
    required List<double> gains,
    required List<int> frequencies,
  }) async {
    if (!Platform.isAndroid || _attachedSessionId != sessionId) return false;
    try {
      return await _channel
              .invokeMethod<bool>('apply', {
                'sessionId': sessionId,
                'enabled': enabled,
                'gains': gains,
                'frequencies': frequencies,
              })
              .timeout(_platformCallTimeout) ??
          false;
    } catch (_) {
      return false;
    }
  }

  Future<bool> release({int? sessionId}) =>
      _operations.enqueue(() => _release(sessionId: sessionId));

  Future<bool> _release({int? sessionId}) async {
    if (!Platform.isAndroid) return true;
    final releasedSessionId = _attachedSessionId ?? _requestedSessionId;
    if (releasedSessionId == null ||
        (sessionId != null && releasedSessionId != sessionId)) {
      return true;
    }
    if (sessionId == null || releasedSessionId == sessionId) {
      _attachedSessionId = null;
      _requestedSessionId = null;
    }
    try {
      await _channel
          .invokeMethod('release', {
            'sessionId': sessionId ?? releasedSessionId,
          })
          .timeout(_platformCallTimeout);
      return true;
    } catch (_) {
      return false;
    }
  }
}
