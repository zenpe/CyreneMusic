import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cyrene_music/services/playback/playback_liveness_monitor.dart';

void main() {
  test('reports one starved stall after the threshold', () {
    fakeAsync((async) {
      final stalls = <PlaybackStallEvidence>[];
      final monitor = PlaybackLivenessMonitor(onStalled: stalls.add);
      monitor.start(
        generation: 7,
        position: const Duration(seconds: 10),
        bufferedPosition: const Duration(seconds: 10),
      );

      async.elapse(const Duration(seconds: 26));

      expect(stalls, hasLength(1));
      expect(stalls.single.generation, 7);
      expect(stalls.single.position, const Duration(seconds: 10));
    });
  });

  test('position progress rearms instead of reporting a stall', () {
    fakeAsync((async) {
      final stalls = <PlaybackStallEvidence>[];
      final monitor = PlaybackLivenessMonitor(onStalled: stalls.add);
      monitor.start(
        generation: 1,
        position: Duration.zero,
        bufferedPosition: Duration.zero,
      );

      monitor.updatePosition(const Duration(seconds: 3));
      async.elapse(const Duration(seconds: 6));
      monitor.updatePosition(const Duration(seconds: 9));
      async.elapse(const Duration(seconds: 6));

      expect(stalls, isEmpty);
    });
  });

  test('growing or sufficient buffer is not network starvation', () {
    fakeAsync((async) {
      final stalls = <PlaybackStallEvidence>[];
      final monitor = PlaybackLivenessMonitor(onStalled: stalls.add);
      monitor.start(
        generation: 1,
        position: const Duration(seconds: 4),
        bufferedPosition: const Duration(seconds: 4),
      );

      monitor.updateBufferedPosition(const Duration(seconds: 8));
      async.elapse(const Duration(seconds: 12));

      expect(stalls, isEmpty);
    });
  });

  test('suspend and generation replacement cancel stale observations', () {
    fakeAsync((async) {
      final stalls = <PlaybackStallEvidence>[];
      final monitor = PlaybackLivenessMonitor(onStalled: stalls.add);
      monitor.start(
        generation: 1,
        position: Duration.zero,
        bufferedPosition: Duration.zero,
      );
      async.elapse(const Duration(seconds: 3));
      monitor.restart(
        generation: 2,
        position: const Duration(seconds: 5),
        bufferedPosition: const Duration(seconds: 5),
      );
      async.elapse(const Duration(seconds: 3));
      monitor.suspend();
      async.elapse(const Duration(seconds: 10));

      expect(stalls, isEmpty);
    });
  });
}
