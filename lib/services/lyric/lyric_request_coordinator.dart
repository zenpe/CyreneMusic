import 'dart:async';
import 'package:dio/dio.dart';
import 'lyric_fetch_result.dart';

typedef LyricFetch =
    Future<LyricFetchResult> Function(
      CancelToken cancelToken,
      Duration timeout,
      bool bypassCache,
    );

class _Job {
  final CancelToken cancel = CancelToken();
  final Stopwatch clock = Stopwatch()..start();
  final LyricFetch fetch;
  final bool Function() isValid;
  bool foreground;
  int attempts = 0;
  Future<LyricFetchResult>? running;
  LyricFetchResult? result;
  _Job(this.fetch, this.isValid, this.foreground);
}

/// One lifecycle is shared by foreground and prefetch consumers. Only this
/// layer retries. Cancellation releases callers even if a transport misbehaves.
class LyricRequestCoordinator {
  final Duration attemptTimeout;
  final Duration retryDelay;
  final Duration totalTimeout;
  final Map<String, _Job> _jobs = {};
  final Map<String, DateTime> _restrictedUntil = {};
  LyricRequestCoordinator({
    this.attemptTimeout = const Duration(seconds: 8),
    this.retryDelay = const Duration(seconds: 1),
    this.totalTimeout = const Duration(seconds: 18),
  });

  void retain(String key) {
    for (final entry in _jobs.entries.toList()) {
      if (entry.key != key) {
        entry.value.cancel.cancel('selection changed');
        _jobs.remove(entry.key);
      }
    }
  }

  void clear() {
    for (final job in _jobs.values) {
      job.cancel.cancel('lyrics invalidated');
    }
    _jobs.clear();
  }

  Future<LyricFetchResult> request(
    String key, {
    required LyricFetch fetch,
    required bool foreground,
    required bool Function() isValid,
    bool force = false,
  }) {
    if (!isValid()) {
      return Future.value(const LyricFetchResult(LyricFetchKind.cancelled));
    }
    final restriction = _restrictedUntil[key];
    if (restriction != null && restriction.isAfter(DateTime.now())) {
      return Future.value(const LyricFetchResult(LyricFetchKind.unavailable));
    }
    var job = _jobs[key];
    if (job != null &&
        job.running == null &&
        (force || job.clock.elapsed >= totalTimeout)) {
      _jobs.remove(key);
      job = null;
    }
    if (job == null) {
      // Bound completed/background bookkeeping during long listening sessions.
      if (_jobs.length >= 8) {
        final oldest = _jobs.keys.first;
        _jobs.remove(oldest)?.cancel.cancel('obsolete lyrics');
      }
      job = _Job(fetch, isValid, foreground);
      _jobs[key] = job;
    }
    job.foreground |= foreground;
    if (job.running != null) return job.running!;
    final previous = job.result;
    if (previous != null &&
        !(foreground && previous.retryable && job.attempts < 2)) {
      return Future.value(previous);
    }
    final selected = job;
    final future = _run(key, selected, force);
    selected.running = future;
    return future;
  }

  Future<LyricFetchResult> _run(String key, _Job job, bool bypass) async {
    var result = const LyricFetchResult(LyricFetchKind.cancelled);
    try {
      while (!job.cancel.isCancelled && job.isValid()) {
        if (job.attempts > 0) {
          await Future.any([
            Future<void>.delayed(retryDelay),
            job.cancel.whenCancel,
          ]);
        }
        final remaining = totalTimeout - job.clock.elapsed;
        if (remaining <= Duration.zero ||
            job.cancel.isCancelled ||
            !job.isValid()) {
          break;
        }
        final timeout = remaining < attemptTimeout ? remaining : attemptTimeout;
        job.attempts++;
        final attemptCancel = CancelToken();
        // Parent cancellation is raced below; no unbounded listener per retry.
        Timer? timer;
        try {
          final timeoutResult = Completer<LyricFetchResult>();
          timer = Timer(timeout, () {
            attemptCancel.cancel('lyric deadline');
            timeoutResult.complete(
              const LyricFetchResult(
                LyricFetchKind.unavailable,
                retryable: true,
              ),
            );
          });
          result = await Future.any([
            Future.sync(
              () =>
                  job.fetch(attemptCancel, timeout, bypass || job.attempts > 1),
            ),
            timeoutResult.future,
            job.cancel.whenCancel.then(
              (_) => const LyricFetchResult(LyricFetchKind.cancelled),
            ),
          ]);
        } catch (_) {
          result = const LyricFetchResult(LyricFetchKind.unavailable);
        } finally {
          timer?.cancel();
          attemptCancel.cancel('attempt finished');
        }
        if (!job.isValid() || job.cancel.isCancelled) {
          result = const LyricFetchResult(LyricFetchKind.cancelled);
          break;
        }
        if (result.retryAfter != null) {
          _restrictedUntil.removeWhere(
            (_, until) => !until.isAfter(DateTime.now()),
          );
          if (_restrictedUntil.length >= 64) {
            _restrictedUntil.remove(_restrictedUntil.keys.first);
          }
          _restrictedUntil[key] = DateTime.now().add(result.retryAfter!);
        }
        if (!result.retryable || !job.foreground || job.attempts >= 2) break;
      }
      return result;
    } finally {
      job.result = result;
      job.running = null;
    }
  }
}
