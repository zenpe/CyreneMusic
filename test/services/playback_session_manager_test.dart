import 'package:cyrene_music/services/playback/playback_session_manager.dart';
import 'package:cyrene_music/services/playback/playback_session_persistence.dart';
import 'package:cyrene_music/services/playback/playback_session_snapshot.dart';
import 'package:cyrene_music/services/playback/queue_controller.dart';
import 'package:cyrene_music/services/playback_mode_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('persists a snapshot supplied by the coordinator', () async {
    final persistence = _FakePersistence();
    final snapshot = _emptySnapshot();
    final manager = PlaybackSessionManager(
      snapshotBuilder: () => snapshot,
      persistence: persistence,
    );

    await manager.persistImmediately();

    expect(persistence.saved, same(snapshot));
    expect(persistence.clearCount, 0);
  });

  test('clears persistence when there is no restorable session', () async {
    final persistence = _FakePersistence();
    final manager = PlaybackSessionManager(
      snapshotBuilder: () => null,
      persistence: persistence,
    );

    await manager.persistImmediately();

    expect(persistence.saved, isNull);
    expect(persistence.clearCount, 1);
  });
}

PlaybackSessionSnapshot _emptySnapshot() => PlaybackSessionSnapshot(
  version: 1,
  savedAt: DateTime(2026),
  queue: const [],
  currentIndex: -1,
  source: QueueSource.none,
  position: Duration.zero,
  state: PlaybackSessionState.idle,
  playbackMode: PlaybackMode.loopAll,
);

class _FakePersistence implements PlaybackSessionPersistence {
  PlaybackSessionSnapshot? saved;
  int clearCount = 0;

  @override
  Future<void> clear() async => clearCount++;

  @override
  Future<PlaybackSessionSnapshot?> loadSnapshot() async => saved;

  @override
  Future<void> saveSnapshot(PlaybackSessionSnapshot snapshot) async {
    saved = snapshot;
  }
}
