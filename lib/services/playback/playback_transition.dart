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
  // Reserve one normal native-operation window for source loading. This is a
  // policy value, not a claim that all streams start within three seconds.
  static const nativeLoadReserve = Duration(seconds: 3);
  static const minimumNativeLoadTime = Duration(milliseconds: 1500);
  static const minimumResolutionTime = Duration(milliseconds: 1500);
  final Duration maxDuration;
  final int maxRemoteRequests;
  final int maxResolutionAttemptsPerTrack;
  final int maxCandidateAttempts;
  final bool shareResolutionBudget;
  int _remainingCandidates = 1;
  final Stopwatch _stopwatch;
  final Duration Function()? _elapsedOverride;
  final Set<int> _visitedEntryIds = <int>{};
  int _remoteRequests = 0;
  Duration _excludedElapsed = Duration.zero;

  PlaybackTransitionBudget({
    this.maxDuration = const Duration(seconds: 12),
    this.maxRemoteRequests = 3,
    this.maxResolutionAttemptsPerTrack = 2,
    this.maxCandidateAttempts = 3,
    this.shareResolutionBudget = false,
    Duration Function()? elapsed,
  }) : _elapsedOverride = elapsed,
       _stopwatch = Stopwatch()..start();

  int get remoteRequests => _remoteRequests;
  Set<int> get visitedEntryIds => Set.unmodifiable(_visitedEntryIds);

  Duration remaining() {
    final elapsed =
        (_elapsedOverride?.call() ?? _stopwatch.elapsed) - _excludedElapsed;
    final value = maxDuration - elapsed;
    return value.isNegative ? Duration.zero : value;
  }

  /// A separately bounded startup network wait must not consume the budget
  /// reserved for actual resolution and native loading.
  void excludeElapsed(Duration elapsed) {
    if (elapsed > Duration.zero) _excludedElapsed += elapsed;
  }

  bool get hasTimeRemaining => remaining() > Duration.zero;
  bool get canStartRemoteRequest =>
      resolutionTimeRemaining >= minimumResolutionTime &&
      _remoteRequests < maxRemoteRequests;

  Duration get resolutionTimeRemaining {
    final value = remaining() - nativeLoadReserve;
    return value.isNegative ? Duration.zero : value;
  }

  Duration resolutionTimeout(Duration maximum) {
    var available = resolutionTimeRemaining;
    if (shareResolutionBudget) {
      // Called after consumeRemoteRequest: include the current request. Fair
      // sharing is for automatic candidates only, never for a manual retry.
      final slots = _remainingCandidates.clamp(
        1,
        (maxRemoteRequests - _remoteRequests + 1).clamp(1, maxRemoteRequests),
      );
      available = available ~/ slots;
      if (available < minimumResolutionTime &&
          resolutionTimeRemaining >= minimumResolutionTime) {
        available = minimumResolutionTime;
      }
    }
    return available < maximum ? available : maximum;
  }

  void prepareCandidate({
    required int remainingCandidates,
    required int failedCandidates,
  }) {
    _remainingCandidates = remainingCandidates.clamp(
      1,
      (maxCandidateAttempts - failedCandidates).clamp(1, maxCandidateAttempts),
    );
  }

  bool visit(int entryId) => _visitedEntryIds.add(entryId);

  bool consumeRemoteRequest() {
    if (!canStartRemoteRequest) return false;
    _remoteRequests++;
    return true;
  }
}
