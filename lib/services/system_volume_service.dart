import 'dart:io';
import 'package:flutter/services.dart';

class SystemVolumeService {
  SystemVolumeService._internal();
  static final SystemVolumeService _instance = SystemVolumeService._internal();
  factory SystemVolumeService() => _instance;

  static const MethodChannel _channel = MethodChannel('com.cyrene.music/system_volume');

  Future<bool> isSupported() async {
    if (!Platform.isAndroid) return false;
    try {
      return await _channel.invokeMethod<bool>('isSupported') ?? false;
    } catch (_) {
      return false;
    }
  }

  Future<double?> getVolume() async {
    if (!Platform.isAndroid) return null;
    try {
      final value = await _channel.invokeMethod<dynamic>('getVolume');
      if (value is num) {
        return value.toDouble().clamp(0.0, 1.0);
      }
    } catch (_) {}
    return null;
  }

  Future<void> setVolume(double volume) async {
    if (!Platform.isAndroid) return;
    final v = volume.clamp(0.0, 1.0);
    try {
      await _channel.invokeMethod('setVolume', {'volume': v});
    } catch (_) {}
  }
}
