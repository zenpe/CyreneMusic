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
  final DateTime startedAt;
  final Duration maxDuration;
  final int maxRemoteRequests;
  final DateTime Function() _now;
  final Set<int> _visitedEntryIds = <int>{};
  int _remoteRequests = 0;

  PlaybackTransitionBudget({
    DateTime? startedAt,
    this.maxDuration = const Duration(seconds: 20),
    this.maxRemoteRequests = 4,
    DateTime Function()? now,
  }) : _now = now ?? DateTime.now,
       startedAt = startedAt ?? (now ?? DateTime.now)();

  int get remoteRequests => _remoteRequests;
  Set<int> get visitedEntryIds => Set.unmodifiable(_visitedEntryIds);

  Duration remaining([DateTime? now]) {
    final elapsed = (now ?? _now()).difference(startedAt);
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
