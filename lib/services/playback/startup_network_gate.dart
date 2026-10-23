import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';

enum StartupNetworkStatus { available, unavailable, unknown }

enum StartupNetworkWaitResult { ready, timedOut, cancelled }

/// Only used by startup restoration, after local/cache lookup. Connectivity is
/// a hint, not an Internet probe: unknown state never prevents a real request.
class StartupNetworkGate {
  final Future<StartupNetworkStatus> Function() check;
  final Stream<StartupNetworkStatus> changes;
  final Duration maxWait;
  final Duration checkTimeout;
  final Duration cancellationInterval;
  Duration _waited = Duration.zero;

  StartupNetworkGate({
    required this.check,
    required this.changes,
    this.maxWait = const Duration(seconds: 10),
    this.checkTimeout = const Duration(milliseconds: 500),
    this.cancellationInterval = const Duration(milliseconds: 100),
  });

  factory StartupNetworkGate.system() {
    final connectivity = Connectivity();
    StartupNetworkStatus status(List<ConnectivityResult> values) =>
        values.isEmpty
        ? StartupNetworkStatus.unknown
        : values.every((value) => value == ConnectivityResult.none)
        ? StartupNetworkStatus.unavailable
        : StartupNetworkStatus.available;
    return StartupNetworkGate(
      check: () async => status(await connectivity.checkConnectivity()),
      changes: connectivity.onConnectivityChanged.map(status),
    );
  }

  Future<StartupNetworkWaitResult> wait({
    required bool Function() isCurrent,
    required void Function() onWaiting,
  }) async {
    if (!isCurrent()) return StartupNetworkWaitResult.cancelled;
    final remaining = maxWait - _waited;
    if (remaining <= Duration.zero) return StartupNetworkWaitResult.timedOut;
    final clock = Stopwatch()..start();
    final result = Completer<StartupNetworkWaitResult>();
    var eventRevision = 0;
    var announcedWaiting = false;
    void finish(StartupNetworkWaitResult value) {
      if (!result.isCompleted) result.complete(value);
    }

    void accept(StartupNetworkStatus status) {
      if (result.isCompleted) return;
      if (!isCurrent()) {
        finish(StartupNetworkWaitResult.cancelled);
      } else if (status != StartupNetworkStatus.unavailable) {
        finish(StartupNetworkWaitResult.ready);
      } else if (!announcedWaiting) {
        announcedWaiting = true;
        onWaiting();
      }
    }

    StreamSubscription<StartupNetworkStatus>? subscription;
    final deadline = Timer(remaining, () {
      finish(
        isCurrent()
            ? StartupNetworkWaitResult.timedOut
            : StartupNetworkWaitResult.cancelled,
      );
    });
    final cancellation = Timer.periodic(cancellationInterval, (_) {
      if (!isCurrent()) finish(StartupNetworkWaitResult.cancelled);
    });
    try {
      subscription = changes.listen(
        (status) {
          eventRevision++;
          accept(status);
        },
        onError: (Object error) {
          eventRevision++;
          accept(StartupNetworkStatus.unknown);
        },
      );
      // Subscribe before checking so a network transition cannot be missed.
      // A newer event wins over an older check that finishes late.
      final revision = eventRevision;
      unawaited(() async {
        StartupNetworkStatus status;
        try {
          status = await check().timeout(checkTimeout);
        } catch (_) {
          status = StartupNetworkStatus.unknown;
        }
        if (revision == eventRevision) accept(status);
      }());
      return await result.future;
    } catch (_) {
      return isCurrent()
          ? StartupNetworkWaitResult.ready
          : StartupNetworkWaitResult.cancelled;
    } finally {
      deadline.cancel();
      cancellation.cancel();
      _waited += clock.elapsed;
      // A broken plugin must not hold the playback transaction indefinitely.
      try {
        await subscription?.cancel().timeout(checkTimeout);
      } catch (_) {}
    }
  }
}
