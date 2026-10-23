import 'dart:async';

import 'playback_session_snapshot.dart';
import 'playback_session_store.dart';
import 'playback_session_persistence.dart';

class PlaybackSessionManager {
  PlaybackSessionManager({
    required PlaybackSessionSnapshot? Function() snapshotBuilder,
    PlaybackSessionPersistence? persistence,
    this.debounce = const Duration(milliseconds: 600),
    this.periodicSaveInterval = const Duration(seconds: 10),
  }) : _snapshotBuilder = snapshotBuilder,
       _persistence = persistence ?? PlaybackSessionStore();

  final PlaybackSessionSnapshot? Function() _snapshotBuilder;
  final PlaybackSessionPersistence _persistence;
  final Duration debounce;
  final Duration periodicSaveInterval;

  Timer? _debounceTimer;
  Timer? _periodicTimer;

  Future<PlaybackSessionSnapshot?> load() => _persistence.loadSnapshot();

  void schedulePersist() {
    _debounceTimer?.cancel();
    _debounceTimer = Timer(debounce, () => unawaited(persistImmediately()));
  }

  void startPeriodicSave() {
    if (_periodicTimer?.isActive ?? false) return;
    _periodicTimer = Timer.periodic(
      periodicSaveInterval,
      (_) => schedulePersist(),
    );
  }

  void stopPeriodicSave() {
    _periodicTimer?.cancel();
    _periodicTimer = null;
  }

  Future<void> persistImmediately() async {
    _debounceTimer?.cancel();
    final snapshot = _snapshotBuilder();
    if (snapshot == null) {
      await _persistence.clear();
    } else {
      await _persistence.saveSnapshot(snapshot);
    }
  }

  Future<void> clear() async {
    _debounceTimer?.cancel();
    await _persistence.clear();
  }

  void dispose() {
    _debounceTimer?.cancel();
    stopPeriodicSave();
  }
}
