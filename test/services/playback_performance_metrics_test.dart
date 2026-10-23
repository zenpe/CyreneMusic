import 'package:cyrene_music/services/playback/playback_performance_metrics.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('aggregates switch counters and timing percentiles', () {
    final metrics = PlaybackPerformanceMetrics(maxSamples: 2);

    metrics.recordSwitch(_sample(totalMs: 100, remoteMs: 40));
    metrics.recordSwitch(
      _sample(
        totalMs: 300,
        remoteMs: 160,
        prefetched: true,
        preparedEngineHit: true,
        preparedActivationMs: 25,
        l1MemoryCached: true,
        audioCacheHit: true,
      ),
    );
    metrics.recordSwitch(_sample(totalMs: 200, remoteMs: 80));
    metrics.recordEngineFailure();
    metrics.recordEngineRetry();

    final snapshot = metrics.snapshot;
    expect(snapshot.completedSwitches, 3);
    expect(snapshot.prefetchedSwitches, 1);
    expect(snapshot.preparedEngineHits, 1);
    expect(snapshot.preparedActivation.count, 1);
    expect(snapshot.preparedActivation.averageMs, 25);
    expect(snapshot.l1MemoryCacheHits, 1);
    expect(snapshot.audioCacheHits, 1);
    expect(snapshot.remoteResolutionAttempts, 3);
    expect(snapshot.engineFailures, 1);
    expect(snapshot.engineRetries, 1);

    // Only the two most recent samples are retained for percentile metrics.
    expect(snapshot.total.count, 2);
    expect(snapshot.total.minMs, 200);
    expect(snapshot.total.maxMs, 300);
    expect(snapshot.total.averageMs, 250);
    expect(snapshot.total.p50Ms, 200);
    expect(snapshot.total.p95Ms, 300);
    expect(snapshot.remoteResolve.averageMs, 120);
  });

  test('reset clears counters and samples', () {
    final metrics = PlaybackPerformanceMetrics();
    metrics.recordSwitch(_sample(totalMs: 100));
    metrics.recordEngineFailure();

    metrics.reset();

    final snapshot = metrics.snapshot;
    expect(snapshot.completedSwitches, 0);
    expect(snapshot.engineFailures, 0);
    expect(snapshot.total, isA<PlaybackTimingSummary>());
    expect(snapshot.total.count, 0);
    expect(snapshot.total.totalMs, 0);
  });
}

PlaybackTimingSample _sample({
  required int totalMs,
  int remoteMs = 10,
  bool prefetched = false,
  bool preparedEngineHit = false,
  int preparedActivationMs = 0,
  bool l1MemoryCached = false,
  bool audioCacheHit = false,
}) => PlaybackTimingSample(
  totalMs: totalMs,
  settleMs: 1,
  lookupMs: 2,
  remoteResolveMs: remoteMs,
  planPrepareMs: 3,
  softFadeOutMs: 4,
  engineStartupMs: 5,
  engineSetSourceMs: 3,
  enginePlayToReadyMs: 2,
  preparedActivationMs: preparedActivationMs,
  prefetched: prefetched,
  preparedEngineHit: preparedEngineHit,
  l1MemoryCached: l1MemoryCached,
  audioCacheHit: audioCacheHit,
  remoteResolutionAttempts: 1,
);
