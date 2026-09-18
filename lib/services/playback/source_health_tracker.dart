enum SourceHealthStatus { healthy, degraded, unavailable }

enum SourceHealthFailureKind {
  transientTimeout,
  runtimeNotReady,
  systemicRejection,
  trackSpecific,
}

class SourceHealthSnapshot {
  final String sourceFingerprint;
  final SourceHealthStatus status;
  final int consecutiveSystemicFailures;
  final int consecutiveTransientFailures;
  final DateTime? circuitOpenedAt;
  final bool probeInFlight;

  const SourceHealthSnapshot({
    required this.sourceFingerprint,
    required this.status,
    required this.consecutiveSystemicFailures,
    required this.consecutiveTransientFailures,
    required this.circuitOpenedAt,
    required this.probeInFlight,
  });

  bool get isCircuitOpen => status == SourceHealthStatus.unavailable;
}

class SourceHealthTracker {
  final int systemicFailureThreshold;
  final int transientFailureThreshold;
  final Duration cooldown;
  final DateTime Function() _now;
  final Map<String, _MutableSourceHealth> _states = {};

  SourceHealthTracker({
    this.systemicFailureThreshold = 2,
    this.transientFailureThreshold = 3,
    this.cooldown = const Duration(minutes: 5),
    DateTime Function()? now,
  }) : assert(systemicFailureThreshold > 0),
       assert(transientFailureThreshold > 0),
       _now = now ?? DateTime.now;

  SourceHealthSnapshot snapshot(String sourceFingerprint) =>
      _snapshot(sourceFingerprint, _stateFor(sourceFingerprint));

  SourceHealthSnapshot prepareManualProbe(String sourceFingerprint) {
    final state = _stateFor(sourceFingerprint)
      ..status = SourceHealthStatus.degraded
      ..manualProbePending = true
      ..probeInFlight = false;
    return _snapshot(sourceFingerprint, state);
  }

  /// Returns whether a remote resolution may start. After an open circuit's
  /// cooldown, exactly one request is admitted as a recovery probe.
  bool allowRequest(String sourceFingerprint) {
    final state = _stateFor(sourceFingerprint);
    if (state.probeInFlight) return false;
    if (state.manualProbePending) {
      state
        ..manualProbePending = false
        ..probeInFlight = true;
      return true;
    }
    if (state.status != SourceHealthStatus.unavailable) return true;

    final openedAt = state.circuitOpenedAt;
    if (openedAt == null || _now().difference(openedAt) < cooldown) {
      return false;
    }
    state
      ..status = SourceHealthStatus.degraded
      ..probeInFlight = true;
    return true;
  }

  void cancelRequest(String sourceFingerprint) {
    final state = _states[sourceFingerprint];
    if (state == null || !state.probeInFlight) return;
    state
      ..status = SourceHealthStatus.unavailable
      ..probeInFlight = false;
  }

  SourceHealthSnapshot recordSuccess(String sourceFingerprint) {
    final state = _stateFor(sourceFingerprint)
      ..status = SourceHealthStatus.healthy
      ..consecutiveSystemicFailures = 0
      ..consecutiveTransientFailures = 0
      ..circuitOpenedAt = null
      ..manualProbePending = false
      ..probeInFlight = false;
    return _snapshot(sourceFingerprint, state);
  }

  SourceHealthSnapshot recordFailure(
    String sourceFingerprint,
    SourceHealthFailureKind kind,
  ) {
    final state = _stateFor(sourceFingerprint);
    final wasRecoveryProbe = state.probeInFlight;
    state
      ..manualProbePending = false
      ..probeInFlight = false;

    switch (kind) {
      case SourceHealthFailureKind.systemicRejection:
        state
          ..consecutiveSystemicFailures = state.consecutiveSystemicFailures + 1
          ..consecutiveTransientFailures = 0;
        if (wasRecoveryProbe ||
            state.consecutiveSystemicFailures >= systemicFailureThreshold) {
          _openCircuit(state);
        } else {
          state.status = SourceHealthStatus.degraded;
        }
        break;
      case SourceHealthFailureKind.transientTimeout:
      case SourceHealthFailureKind.runtimeNotReady:
        state
          ..consecutiveTransientFailures =
              state.consecutiveTransientFailures + 1
          ..consecutiveSystemicFailures = 0;
        if (wasRecoveryProbe) {
          _openCircuit(state);
        } else if (state.consecutiveTransientFailures >=
            transientFailureThreshold) {
          state.status = SourceHealthStatus.degraded;
        }
        break;
      case SourceHealthFailureKind.trackSpecific:
        state.consecutiveSystemicFailures = 0;
        if (wasRecoveryProbe) state.status = SourceHealthStatus.degraded;
        break;
    }
    return _snapshot(sourceFingerprint, state);
  }

  void _openCircuit(_MutableSourceHealth state) {
    state
      ..status = SourceHealthStatus.unavailable
      ..circuitOpenedAt = _now()
      ..probeInFlight = false;
  }

  _MutableSourceHealth _stateFor(String sourceFingerprint) =>
      _states.putIfAbsent(sourceFingerprint, _MutableSourceHealth.new);

  SourceHealthSnapshot _snapshot(
    String sourceFingerprint,
    _MutableSourceHealth state,
  ) => SourceHealthSnapshot(
    sourceFingerprint: sourceFingerprint,
    status: state.status,
    consecutiveSystemicFailures: state.consecutiveSystemicFailures,
    consecutiveTransientFailures: state.consecutiveTransientFailures,
    circuitOpenedAt: state.circuitOpenedAt,
    probeInFlight: state.probeInFlight,
  );
}

class _MutableSourceHealth {
  SourceHealthStatus status = SourceHealthStatus.healthy;
  int consecutiveSystemicFailures = 0;
  int consecutiveTransientFailures = 0;
  DateTime? circuitOpenedAt;
  bool probeInFlight = false;
  bool manualProbePending = false;
}
