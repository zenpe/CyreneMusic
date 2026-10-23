import 'package:flutter/services.dart';

/// Android owns both fragments and verified complete files. Only committed
/// complete objects are exposed as independently playable paths.
class AndroidStreamCache {
  static const channel = MethodChannel('com.ryanheise.just_audio.methods');

  static Future<void> configure({
    required String directory,
    required bool enabled,
    required int maxBytes,
  }) => channel
      .invokeMethod<void>('streamCache.configure', {
        'directory': directory,
        'enabled': enabled,
        'maxBytes': maxBytes,
      })
      .timeout(const Duration(seconds: 10));

  static Future<Map<String, dynamic>> stats() async =>
      Map<String, dynamic>.from(
        await channel
                .invokeMapMethod<String, dynamic>('streamCache.stats')
                .timeout(const Duration(seconds: 10)) ??
            {},
      );

  static Future<Map<String, dynamic>?> lookup(
    Map<String, String> identity,
  ) async {
    final result = await channel
        .invokeMapMethod<String, dynamic>('streamCache.lookup', {
          'identity': identity,
        })
        .timeout(const Duration(seconds: 2));
    return result == null ? null : Map<String, dynamic>.from(result);
  }

  static Future<void> clear() => channel
      .invokeMethod<void>('streamCache.clear')
      .timeout(const Duration(seconds: 10));

  static Future<void> refresh(Map<String, String> identity) => channel
      .invokeMethod<void>('streamCache.refresh', {'identity': identity})
      .timeout(const Duration(seconds: 2));

  static Future<void> cancelRefresh(Map<String, String> identity) => channel
      .invokeMethod<void>('streamCache.cancelRefresh', {'identity': identity})
      .timeout(const Duration(seconds: 2));

  static Future<void> delete(
    String source,
    String songId,
    String? quality, {
    String? owner,
  }) => channel
      .invokeMethod<void>('streamCache.delete', {
        'source': source,
        'songId': songId,
        'quality': quality,
        'owner': ?owner,
      })
      .timeout(const Duration(seconds: 10));
}
