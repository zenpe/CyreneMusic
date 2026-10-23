import 'dart:async';

import 'package:cyrene_music/services/playback/startup_network_gate.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final status in [
    StartupNetworkStatus.available,
    StartupNetworkStatus.unknown,
  ]) {
    test('$status allows a real request without waiting', () async {
      final gate = StartupNetworkGate(
        check: () async => status,
        changes: const Stream.empty(),
      );
      expect(
        await gate.wait(isCurrent: () => true, onWaiting: () => fail('wait')),
        StartupNetworkWaitResult.ready,
      );
    });
  }

  test('offline startup waits once, resumes once, and unsubscribes', () async {
    final events = StreamController<StartupNetworkStatus>.broadcast();
    final waiting = Completer<void>();
    final gate = StartupNetworkGate(
      check: () async => StartupNetworkStatus.unavailable,
      changes: events.stream,
    );
    final result = gate.wait(
      isCurrent: () => true,
      onWaiting: waiting.complete,
    );
    await waiting.future;
    events.add(StartupNetworkStatus.unavailable);
    events.add(StartupNetworkStatus.available);
    events.add(StartupNetworkStatus.available);
    expect(await result, StartupNetworkWaitResult.ready);
    expect(events.hasListener, isFalse);
    await events.close();
  });

  test(
    'deadline finishes and later connectivity cannot restart the wait',
    () async {
      final events = StreamController<StartupNetworkStatus>.broadcast();
      final gate = StartupNetworkGate(
        check: () async => StartupNetworkStatus.unavailable,
        changes: events.stream,
        maxWait: const Duration(milliseconds: 30),
      );
      expect(
        await gate.wait(isCurrent: () => true, onWaiting: () {}),
        StartupNetworkWaitResult.timedOut,
      );
      expect(events.hasListener, isFalse);
      events.add(StartupNetworkStatus.available);
      expect(
        await gate.wait(isCurrent: () => true, onWaiting: () {}),
        StartupNetworkWaitResult.timedOut,
      );
      await events.close();
    },
  );

  test('new intent cancels offline waiting and releases listener', () async {
    final events = StreamController<StartupNetworkStatus>.broadcast();
    final waiting = Completer<void>();
    var current = true;
    final gate = StartupNetworkGate(
      check: () async => StartupNetworkStatus.unavailable,
      changes: events.stream,
      cancellationInterval: const Duration(milliseconds: 5),
    );
    final result = gate.wait(
      isCurrent: () => current,
      onWaiting: waiting.complete,
    );
    await waiting.future;
    current = false;
    expect(await result, StartupNetworkWaitResult.cancelled);
    expect(events.hasListener, isFalse);
    await events.close();
  });

  test('a hung connectivity query does not block playback', () async {
    final gate = StartupNetworkGate(
      check: () => Completer<StartupNetworkStatus>().future,
      changes: const Stream.empty(),
      checkTimeout: const Duration(milliseconds: 10),
    );
    expect(
      await gate.wait(isCurrent: () => true, onWaiting: () {}),
      StartupNetworkWaitResult.ready,
    );
  });

  test('newer available event wins over a late offline query', () async {
    final events = StreamController<StartupNetworkStatus>.broadcast();
    final query = Completer<StartupNetworkStatus>();
    final gate = StartupNetworkGate(
      check: () => query.future,
      changes: events.stream,
    );
    final result = gate.wait(
      isCurrent: () => true,
      onWaiting: () => fail('wait'),
    );
    events.add(StartupNetworkStatus.available);
    expect(await result, StartupNetworkWaitResult.ready);
    query.complete(StartupNetworkStatus.unavailable);
    await events.close();
  });
}
