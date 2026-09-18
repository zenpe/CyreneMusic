import 'package:cyrene_music/services/playback/source_health_tracker.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const source = 'source:v1:hash';
  late DateTime now;
  late SourceHealthTracker tracker;

  setUp(() {
    now = DateTime(2026, 1, 1);
    tracker = SourceHealthTracker(now: () => now);
  });

  test('opens the circuit after consecutive systemic rejections', () {
    final first = tracker.recordFailure(
      source,
      SourceHealthFailureKind.systemicRejection,
    );
    expect(first.status, SourceHealthStatus.degraded);
    expect(tracker.allowRequest(source), isTrue);

    final second = tracker.recordFailure(
      source,
      SourceHealthFailureKind.systemicRejection,
    );
    expect(second.status, SourceHealthStatus.unavailable);
    expect(tracker.allowRequest(source), isFalse);
  });

  test('admits one recovery probe after cooldown', () {
    tracker
      ..recordFailure(source, SourceHealthFailureKind.systemicRejection)
      ..recordFailure(source, SourceHealthFailureKind.systemicRejection);

    now = now.add(const Duration(minutes: 5));
    expect(tracker.allowRequest(source), isTrue);
    expect(tracker.snapshot(source).probeInFlight, isTrue);
    expect(tracker.allowRequest(source), isFalse);

    final recovered = tracker.recordSuccess(source);
    expect(recovered.status, SourceHealthStatus.healthy);
    expect(tracker.allowRequest(source), isTrue);
  });

  test('reopens the circuit when a recovery probe fails', () {
    tracker
      ..recordFailure(source, SourceHealthFailureKind.systemicRejection)
      ..recordFailure(source, SourceHealthFailureKind.systemicRejection);
    now = now.add(const Duration(minutes: 5));
    expect(tracker.allowRequest(source), isTrue);

    final failedProbe = tracker.recordFailure(
      source,
      SourceHealthFailureKind.transientTimeout,
    );
    expect(failedProbe.status, SourceHealthStatus.unavailable);
    expect(failedProbe.circuitOpenedAt, now);
  });

  test('cancelled recovery probe leaves the circuit open', () {
    tracker
      ..recordFailure(source, SourceHealthFailureKind.systemicRejection)
      ..recordFailure(source, SourceHealthFailureKind.systemicRejection);
    now = now.add(const Duration(minutes: 5));
    expect(tracker.allowRequest(source), isTrue);

    tracker.cancelRequest(source);
    expect(tracker.snapshot(source).status, SourceHealthStatus.unavailable);
    expect(tracker.snapshot(source).probeInFlight, isFalse);
  });

  test('manual validation admits one probe before cooldown', () {
    tracker
      ..recordFailure(source, SourceHealthFailureKind.systemicRejection)
      ..recordFailure(source, SourceHealthFailureKind.systemicRejection)
      ..prepareManualProbe(source);

    expect(tracker.allowRequest(source), isTrue);
    expect(tracker.allowRequest(source), isFalse);
  });

  test('timeouts degrade but do not open the circuit', () {
    for (var i = 0; i < 3; i++) {
      tracker.recordFailure(source, SourceHealthFailureKind.transientTimeout);
    }
    expect(tracker.snapshot(source).status, SourceHealthStatus.degraded);
    expect(tracker.allowRequest(source), isTrue);
  });

  test('track-specific failure does not damage source health', () {
    final snapshot = tracker.recordFailure(
      source,
      SourceHealthFailureKind.trackSpecific,
    );
    expect(snapshot.status, SourceHealthStatus.healthy);
    expect(snapshot.consecutiveSystemicFailures, 0);
    expect(snapshot.consecutiveTransientFailures, 0);
  });

  test('a different fingerprint starts with independent healthy state', () {
    tracker
      ..recordFailure(source, SourceHealthFailureKind.systemicRejection)
      ..recordFailure(source, SourceHealthFailureKind.systemicRejection);
    expect(
      tracker.snapshot('source:v2:new-hash').status,
      SourceHealthStatus.healthy,
    );
  });
}
