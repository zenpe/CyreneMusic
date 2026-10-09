enum PlaybackRequestIntent { manual, automatic, retry, restore }

enum PlaybackTransitionIntent {
  directSelection,
  manualAdvance,
  automaticAdvance,
  retry,
  restore,
  removeCurrent,
}

enum PlaybackTransitionDirection { forward, backward }

enum PlaybackTransitionFailureScope { track, source, engine, cancelled }

class PlaybackTransitionBudget {
  final Duration maxDuration;
  final int maxRemoteRequests;
  final Stopwatch _stopwatch;
  final Duration Function()? _elapsedOverride;
  final Set<int> _visitedEntryIds = <int>{};
  int _remoteRequests = 0;

  PlaybackTransitionBudget({
    this.maxDuration = const Duration(seconds: 12),
    this.maxRemoteRequests = 3,
    Duration Function()? elapsed,
  }) : _elapsedOverride = elapsed,
       _stopwatch = Stopwatch()..start();

  int get remoteRequests => _remoteRequests;
  Set<int> get visitedEntryIds => Set.unmodifiable(_visitedEntryIds);

  Duration remaining() {
    final elapsed = _elapsedOverride?.call() ?? _stopwatch.elapsed;
    final value = maxDuration - elapsed;
    return value.isNegative ? Duration.zero : value;
  }

  bool get hasTimeRemaining => remaining() > Duration.zero;
  bool get canStartRemoteRequest =>
      hasTimeRemaining && _remoteRequests < maxRemoteRequests;

  bool visit(int entryId) => _visitedEntryIds.add(entryId);

  bool consumeRemoteRequest() {
    if (!canStartRemoteRequest) return false;
    _remoteRequests++;
    return true;
  }
}
