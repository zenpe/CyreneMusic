/// Monotonic request router for user-visible playback operations.
///
/// A request can still finish its network call, but only the newest request
/// is allowed to commit a track switch.
class PlaybackRequestRouter {
  int _epoch = 0;

  int begin() => ++_epoch;

  int get currentEpoch => _epoch;

  bool isCurrent(int epoch) => epoch == _epoch;
}
