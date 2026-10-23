import 'dart:async';
import 'package:flutter/services.dart';
import '../models/equalizer_state.dart';

class AndroidEqualizerResult {
  final EqualizerStatus status;
  final EqualizerCapabilities? capabilities;
  const AndroidEqualizerResult(this.status, [this.capabilities]);
}

class AndroidEqualizerService {
  static final AndroidEqualizerService _instance = AndroidEqualizerService._();
  factory AndroidEqualizerService() => _instance;
  AndroidEqualizerService._();
  static const _channel = MethodChannel('com.cyrene.music/android_equalizer');
  static const _timeout = Duration(milliseconds: 500);
  int _requestId = 0;

  Future<AndroidEqualizerResult> configure({
    required int sessionId,
    required bool enabled,
    required List<double> gains,
    required List<int> frequencies,
  }) async {
    final requestId = ++_requestId;
    try {
      final result = await _channel
          .invokeMapMethod<String, dynamic>('configure', {
            'sessionId': sessionId,
            'requestId': requestId,
            'enabled': enabled,
            'gains': gains,
            'frequencies': frequencies,
          })
          .timeout(_timeout);
      final status = switch (result?['status']) {
        'applied' => EqualizerStatus.applied,
        'bypassed' => EqualizerStatus.bypassed,
        'disabled' => EqualizerStatus.disabled,
        _ => EqualizerStatus.failed,
      };
      return AndroidEqualizerResult(
        status,
        result?.containsKey('frequencies') == true
            ? EqualizerCapabilities.fromMap(result!)
            : null,
      );
    } on TimeoutException {
      // Invalidates queued/late work; does not claim to interrupt a native call.
      unawaited(_invalidate(sessionId, requestId));
      return const AndroidEqualizerResult(EqualizerStatus.failed);
    } catch (_) {
      return const AndroidEqualizerResult(EqualizerStatus.failed);
    }
  }

  Future<void> _invalidate(int sessionId, int requestId) async {
    try {
      await _channel
          .invokeMethod('invalidate', {
            'sessionId': sessionId,
            'requestId': requestId,
          })
          .timeout(_timeout);
    } catch (_) {}
  }

  Future<bool> release({int? sessionId}) async {
    try {
      await _channel
          .invokeMethod('release', {'sessionId': sessionId})
          .timeout(_timeout);
      return true;
    } catch (_) {
      return false;
    }
  }
}
