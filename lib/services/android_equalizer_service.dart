import 'dart:io';
import 'package:flutter/services.dart';

class AndroidEqualizerService {
  static final AndroidEqualizerService _instance =
      AndroidEqualizerService._internal();
  factory AndroidEqualizerService() => _instance;
  AndroidEqualizerService._internal();

  static const MethodChannel _channel =
      MethodChannel('com.cyrene.music/android_equalizer');

  int? _attachedSessionId;

  Future<bool> attachToSession(int sessionId) async {
    if (!Platform.isAndroid || sessionId <= 0) return false;
    if (_attachedSessionId == sessionId) return true;

    try {
      final ok = await _channel.invokeMethod<bool>(
            'attach',
            {'sessionId': sessionId},
          ) ??
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
    required bool enabled,
    required List<double> gains,
    required List<int> frequencies,
  }) async {
    if (!Platform.isAndroid) return false;
    try {
      return await _channel.invokeMethod<bool>(
            'apply',
            {
              'enabled': enabled,
              'gains': gains,
              'frequencies': frequencies,
            },
          ) ??
          false;
    } catch (_) {
      return false;
    }
  }

  Future<void> release() async {
    if (!Platform.isAndroid) return;
    try {
      await _channel.invokeMethod('release');
    } catch (_) {}
    _attachedSessionId = null;
  }
}
