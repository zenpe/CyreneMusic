import '../structured_log_service.dart';
import 'dart:convert';

import '../persistent_storage_service.dart';
import 'playback_session_snapshot.dart';
import 'playback_session_persistence.dart';

class PlaybackSessionStore implements PlaybackSessionPersistence {
  PlaybackSessionStore._internal();

  static final PlaybackSessionStore _instance =
      PlaybackSessionStore._internal();
  factory PlaybackSessionStore() => _instance;

  static const String _sessionKey = 'playback_session_snapshot_v1';

  @override
  Future<void> saveSnapshot(PlaybackSessionSnapshot snapshot) async {
    await _ensureStorageReady();
    await PersistentStorageService().setString(
      _sessionKey,
      jsonEncode(snapshot.toJson()),
    );
  }

  @override
  Future<PlaybackSessionSnapshot?> loadSnapshot() async {
    await _ensureStorageReady();
    final raw = PersistentStorageService().getString(_sessionKey);
    if (raw == null || raw.isEmpty) return null;

    try {
      final json = jsonDecode(raw);
      if (json is! Map<String, dynamic>) {
        await clear();
        return null;
      }

      final snapshot = PlaybackSessionSnapshot.fromJson(json);
      if (!snapshot.isValid) {
        await clear();
        return null;
      }
      return snapshot;
    } catch (e) {
      StructuredLogService.log('[PlaybackSessionStore] 读取播放会话失败: $e');
      await clear();
      return null;
    }
  }

  @override
  Future<void> clear() async {
    await _ensureStorageReady();
    await PersistentStorageService().remove(_sessionKey);
  }

  Future<void> _ensureStorageReady() async {
    if (PersistentStorageService().isInitialized) return;
    await PersistentStorageService().initialize();
  }
}
