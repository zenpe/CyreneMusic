import 'dart:math' as math;

/// A single completed track-switch timing sample.
///
/// Values are kept in milliseconds so the collector remains independent of
/// Flutter and can be tested without an engine or platform channel.
class PlaybackTimingSample {
  final int totalMs;
  final int settleMs;
  final int lookupMs;
  final int remoteResolveMs;
  final int planPrepareMs;
  final int softFadeOutMs;
  final int engineStartupMs;
  final int engineSetSourceMs;
  final int enginePlayToReadyMs;
  final int preparedActivationMs;
  final bool prefetched;
  final bool preparedEngineHit;
  final bool l1MemoryCached;
  final bool audioCacheHit;
  final int remoteResolutionAttempts;

  const PlaybackTimingSample({
    required this.totalMs,
    required this.settleMs,
    required this.lookupMs,
    required this.remoteResolveMs,
    required this.planPrepareMs,
    required this.softFadeOutMs,
    required this.engineStartupMs,
    required this.engineSetSourceMs,
    required this.enginePlayToReadyMs,
    required this.preparedActivationMs,
    required this.prefetched,
    required this.preparedEngineHit,
    required this.l1MemoryCached,
    required this.audioCacheHit,
    required this.remoteResolutionAttempts,
  });
}

/// Summary for one timing stage.
class PlaybackTimingSummary {
  final int count;
  final int totalMs;
  final int minMs;
  final int maxMs;
  final int averageMs;
  final int p50Ms;
  final int p95Ms;

  const PlaybackTimingSummary({
    required this.count,
    required this.totalMs,
    required this.minMs,
    required this.maxMs,
    required this.averageMs,
    required this.p50Ms,
    required this.p95Ms,
  });

  const PlaybackTimingSummary.empty()
    : count = 0,
      totalMs = 0,
      minMs = 0,
      maxMs = 0,
      averageMs = 0,
      p50Ms = 0,
      p95Ms = 0;
}

/// Read-only playback performance snapshot.
///
/// Timing summaries describe the retained recent sample window. The counters
/// remain cumulative until [PlaybackPerformanceMetrics.reset] is called, so a
/// long-running session does not need to retain every sample.
class PlaybackPerformanceSnapshot {
  final int completedSwitches;
  final int prefetchedSwitches;
  final int preparedEngineHits;
  final int l1MemoryCacheHits;
  final int audioCacheHits;
  final int remoteResolutionAttempts;
  final int engineFailures;
  final int engineRetries;
  final PlaybackTimingSummary total;
  final PlaybackTimingSummary settle;
  final PlaybackTimingSummary lookup;
  final PlaybackTimingSummary remoteResolve;
  final PlaybackTimingSummary planPrepare;
  final PlaybackTimingSummary softFadeOut;
  final PlaybackTimingSummary engineStartup;
  final PlaybackTimingSummary engineSetSource;
  final PlaybackTimingSummary enginePlayToReady;
  final PlaybackTimingSummary preparedActivation;

  const PlaybackPerformanceSnapshot({
    required this.completedSwitches,
    required this.prefetchedSwitches,
    required this.preparedEngineHits,
    required this.l1MemoryCacheHits,
    required this.audioCacheHits,
    required this.remoteResolutionAttempts,
    required this.engineFailures,
    required this.engineRetries,
    required this.total,
    required this.settle,
    required this.lookup,
    required this.remoteResolve,
    required this.planPrepare,
    required this.softFadeOut,
    required this.engineStartup,
    required this.engineSetSource,
    required this.enginePlayToReady,
    required this.preparedActivation,
  });

  const PlaybackPerformanceSnapshot.empty()
    : completedSwitches = 0,
      prefetchedSwitches = 0,
      preparedEngineHits = 0,
      l1MemoryCacheHits = 0,
      audioCacheHits = 0,
      remoteResolutionAttempts = 0,
      engineFailures = 0,
      engineRetries = 0,
      total = const PlaybackTimingSummary.empty(),
      settle = const PlaybackTimingSummary.empty(),
      lookup = const PlaybackTimingSummary.empty(),
      remoteResolve = const PlaybackTimingSummary.empty(),
      planPrepare = const PlaybackTimingSummary.empty(),
      softFadeOut = const PlaybackTimingSummary.empty(),
      engineStartup = const PlaybackTimingSummary.empty(),
      engineSetSource = const PlaybackTimingSummary.empty(),
      enginePlayToReady = const PlaybackTimingSummary.empty(),
      preparedActivation = const PlaybackTimingSummary.empty();
}

class PlaybackPerformanceMetrics {
  PlaybackPerformanceMetrics({this.maxSamples = 128}) : assert(maxSamples > 0);

  final int maxSamples;
  final List<int> _totalSamples = <int>[];
  final List<int> _settleSamples = <int>[];
  final List<int> _lookupSamples = <int>[];
  final List<int> _remoteResolveSamples = <int>[];
  final List<int> _planPrepareSamples = <int>[];
  final List<int> _softFadeOutSamples = <int>[];
  final List<int> _engineStartupSamples = <int>[];
  final List<int> _engineSetSourceSamples = <int>[];
  final List<int> _enginePlayToReadySamples = <int>[];
  final List<int> _preparedActivationSamples = <int>[];

  int _completedSwitches = 0;
  int _prefetchedSwitches = 0;
  int _preparedEngineHits = 0;
  int _l1MemoryCacheHits = 0;
  int _audioCacheHits = 0;
  int _remoteResolutionAttempts = 0;
  int _engineFailures = 0;
  int _engineRetries = 0;

  void recordSwitch(PlaybackTimingSample sample) {
    _completedSwitches++;
    if (sample.prefetched) _prefetchedSwitches++;
    if (sample.preparedEngineHit) _preparedEngineHits++;
    if (sample.l1MemoryCached) _l1MemoryCacheHits++;
    if (sample.audioCacheHit) _audioCacheHits++;
    _remoteResolutionAttempts += sample.remoteResolutionAttempts;

    _append(_totalSamples, sample.totalMs);
    _append(_settleSamples, sample.settleMs);
    _append(_lookupSamples, sample.lookupMs);
    _append(_remoteResolveSamples, sample.remoteResolveMs);
    _append(_planPrepareSamples, sample.planPrepareMs);
    _append(_softFadeOutSamples, sample.softFadeOutMs);
    _append(_engineStartupSamples, sample.engineStartupMs);
    _append(_engineSetSourceSamples, sample.engineSetSourceMs);
    _append(_enginePlayToReadySamples, sample.enginePlayToReadyMs);
    if (sample.preparedEngineHit) {
      _append(_preparedActivationSamples, sample.preparedActivationMs);
    }
  }

  void recordEngineFailure() => _engineFailures++;

  void recordEngineRetry() => _engineRetries++;

  PlaybackPerformanceSnapshot get snapshot => PlaybackPerformanceSnapshot(
    completedSwitches: _completedSwitches,
    prefetchedSwitches: _prefetchedSwitches,
    preparedEngineHits: _preparedEngineHits,
    l1MemoryCacheHits: _l1MemoryCacheHits,
    audioCacheHits: _audioCacheHits,
    remoteResolutionAttempts: _remoteResolutionAttempts,
    engineFailures: _engineFailures,
    engineRetries: _engineRetries,
    total: _summary(_totalSamples),
    settle: _summary(_settleSamples),
    remoteResolve: _summary(_remoteResolveSamples),
    lookup: _summary(_lookupSamples),
    planPrepare: _summary(_planPrepareSamples),
    softFadeOut: _summary(_softFadeOutSamples),
    engineStartup: _summary(_engineStartupSamples),
    engineSetSource: _summary(_engineSetSourceSamples),
    enginePlayToReady: _summary(_enginePlayToReadySamples),
    preparedActivation: _summary(_preparedActivationSamples),
  );

  void reset() {
    _completedSwitches = 0;
    _prefetchedSwitches = 0;
    _preparedEngineHits = 0;
    _l1MemoryCacheHits = 0;
    _audioCacheHits = 0;
    _remoteResolutionAttempts = 0;
    _engineFailures = 0;
    _engineRetries = 0;
    _totalSamples.clear();
    _settleSamples.clear();
    _lookupSamples.clear();
    _remoteResolveSamples.clear();
    _planPrepareSamples.clear();
    _softFadeOutSamples.clear();
    _engineStartupSamples.clear();
    _engineSetSourceSamples.clear();
    _enginePlayToReadySamples.clear();
    _preparedActivationSamples.clear();
  }

  void _append(List<int> samples, int value) {
    samples.add(math.max(0, value));
    if (samples.length > maxSamples) samples.removeAt(0);
  }

  PlaybackTimingSummary _summary(List<int> samples) {
    if (samples.isEmpty) return const PlaybackTimingSummary.empty();
    final sorted = List<int>.from(samples)..sort();
    final total = sorted.fold<int>(0, (sum, value) => sum + value);
    return PlaybackTimingSummary(
      count: sorted.length,
      totalMs: total,
      minMs: sorted.first,
      maxMs: sorted.last,
      averageMs: total ~/ sorted.length,
      p50Ms: _percentile(sorted, 0.50),
      p95Ms: _percentile(sorted, 0.95),
    );
  }

  int _percentile(List<int> sorted, double percentile) {
    final index = (sorted.length * percentile).ceil() - 1;
    return sorted[index.clamp(0, sorted.length - 1)];
  }
}
