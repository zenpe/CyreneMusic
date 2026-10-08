/// Tracks user transport commands independently of source generations.
/// A pause on the same source must invalidate an older resume continuation.
class PlaybackControlIntent {
  int _revision = 0;
  bool? _pendingPlaying;

  bool? get pendingPlaying => _pendingPlaying;

  int begin(bool playing) {
    _pendingPlaying = playing;
    return ++_revision;
  }

  bool isCurrent(int revision) => revision == _revision;

  void settle(int revision) {
    if (isCurrent(revision)) _pendingPlaying = null;
  }

  void acknowledge(bool playing) {
    if (_pendingPlaying == playing) _pendingPlaying = null;
  }

  void invalidate() {
    _revision++;
    _pendingPlaying = null;
  }
}
