import 'playback_session_snapshot.dart';

abstract interface class PlaybackSessionPersistence {
  Future<void> saveSnapshot(PlaybackSessionSnapshot snapshot);
  Future<PlaybackSessionSnapshot?> loadSnapshot();
  Future<void> clear();
}
