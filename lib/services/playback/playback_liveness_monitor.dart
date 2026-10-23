import 'dart:async';

class PlaybackStallEvidence {
  final int generation;
  final Duration position;
  final Duration bufferedPosition;

  const PlaybackStallEvidence({
    required this.generation,
    required this.position,
    required this.bufferedPosition,
  });
}

/// Detects a committed stream that has stopped making playback or buffering
/// progress. Recovery remains the coordinator's responsibility.
class PlaybackLivenessMonitor {
  final Duration stallThreshold;
  final Duration minimumProgress;
  final Duration minimumBufferGrowth;
  final Duration maximumStarvedBuffer;
  final void Function(PlaybackStallEvidence evidence) onStalled;

  Timer? _timer;
  int? _generation;
  Duration _position = Duration.zero;
  Duration _bufferedPosition = Duration.zero;
  Duration _baselinePosition = Duration.zero;
  Duration _baselineBufferedPosition = Duration.zero;

  PlaybackLivenessMonitor({
    this.stallThreshold = const Duration(seconds: 6),
    this.minimumProgress = const Duration(milliseconds: 250),
    this.minimumBufferGrowth = const Duration(milliseconds: 250),
    this.maximumStarvedBuffer = const Duration(milliseconds: 500),
    required this.onStalled,
  });

  void start({
    required int generation,
    required Duration position,
    required Duration bufferedPosition,
  }) {
    if (_generation == generation && _timer != null) return;
    _generation = generation;
    _position = position;
    _bufferedPosition = bufferedPosition;
    _arm();
  }

  void updatePosition(Duration value) => _position = value;

  void updateBufferedPosition(Duration value) => _bufferedPosition = value;

  void restart({
    required int generation,
    required Duration position,
    required Duration bufferedPosition,
  }) {
    suspend();
    start(
      generation: generation,
      position: position,
      bufferedPosition: bufferedPosition,
    );
  }

  void suspend() {
    _timer?.cancel();
    _timer = null;
    _generation = null;
  }

  void dispose() => suspend();

  void _arm() {
    _timer?.cancel();
    _baselinePosition = _position;
    _baselineBufferedPosition = _bufferedPosition;
    _timer = Timer(stallThreshold, _evaluate);
  }

  void _evaluate() {
    _timer = null;
    final generation = _generation;
    if (generation == null) return;

    final positionDelta = _position - _baselinePosition;
    final bufferedDelta = _bufferedPosition - _baselineBufferedPosition;
    final bufferedAhead = _bufferedPosition - _position;
    final progressed = positionDelta >= minimumProgress;
    final bufferGrowing = bufferedDelta >= minimumBufferGrowth;
    final starved = bufferedAhead <= maximumStarvedBuffer;

    if (!progressed && !bufferGrowing && starved) {
      _generation = null;
      onStalled(
        PlaybackStallEvidence(
          generation: generation,
          position: _position,
          bufferedPosition: _bufferedPosition,
        ),
      );
      return;
    }

    _arm();
  }
}
