import 'package:cyrene_music/models/track.dart';
import 'package:cyrene_music/services/playback/playback_candidate_planner.dart';
import 'package:cyrene_music/services/playback/playback_transition.dart';
import 'package:cyrene_music/services/playback_mode_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const planner = PlaybackCandidatePlanner();

  PlaybackQueueSnapshot queue({int active = 2}) => PlaybackQueueSnapshot(
    entries: [entry(1, 10), entry(2, 10), entry(3, 30), entry(4, 40)],
    activeEntryId: active,
    structureRevision: 7,
  );

  test('manual next selects only the adjacent target', () {
    final plan = planner.plan(
      queue: queue(),
      mode: PlaybackMode.sequential,
      intent: PlaybackTransitionIntent.manualAdvance,
    );

    expect(plan.candidates.map((item) => item.entryId), [3]);
    expect(plan.stopsAtQueueEnd, isTrue);
  });

  test('automatic sequential advance stops at the queue end', () {
    final plan = planner.plan(
      queue: queue(),
      mode: PlaybackMode.sequential,
      intent: PlaybackTransitionIntent.automaticAdvance,
    );

    expect(plan.candidates.map((item) => item.entryId), [3, 4]);
    expect(plan.stopsAtQueueEnd, isTrue);
  });

  test('loop-all automatic advance scans at most one complete cycle', () {
    final plan = planner.plan(
      queue: queue(active: 4),
      mode: PlaybackMode.loopAll,
      intent: PlaybackTransitionIntent.automaticAdvance,
    );

    expect(plan.candidates.map((item) => item.entryId), [1, 2, 3]);
  });

  test('duplicate tracks remain distinct candidates by entry id', () {
    final plan = planner.plan(
      queue: queue(active: 4),
      mode: PlaybackMode.loopAll,
      intent: PlaybackTransitionIntent.automaticAdvance,
    );

    expect(plan.candidates.take(2).map((item) => item.entryId), [1, 2]);
    expect(plan.candidates.take(2).map((item) => item.track.id), [10, 10]);
  });

  test('shuffle order is deduplicated and excludes the active entry', () {
    final plan = planner.plan(
      queue: queue(),
      mode: PlaybackMode.shuffle,
      intent: PlaybackTransitionIntent.automaticAdvance,
      shuffleEntryOrder: const [4, 3, 4, 2, 1],
    );

    expect(plan.candidates.map((item) => item.entryId), [4, 3, 1]);
  });

  test('direct selection never scans adjacent entries', () {
    final plan = planner.plan(
      queue: queue(),
      mode: PlaybackMode.loopAll,
      intent: PlaybackTransitionIntent.directSelection,
    );

    expect(plan.candidates.map((item) => item.entryId), [2]);
  });

  test('manual next in a one-item loop has no adjacent target', () {
    final plan = planner.plan(
      queue: PlaybackQueueSnapshot(
        entries: [entry(1, 10)],
        activeEntryId: 1,
        structureRevision: 1,
      ),
      mode: PlaybackMode.loopAll,
      intent: PlaybackTransitionIntent.manualAdvance,
    );

    expect(plan.candidates, isEmpty);
  });

  test('manual boundaries follow sequential mode in both directions', () {
    for (final pair in [
      (4, PlaybackTransitionDirection.forward),
      (1, PlaybackTransitionDirection.backward),
    ]) {
      expect(
        planner
            .plan(
              queue: queue(active: pair.$1),
              mode: PlaybackMode.sequential,
              intent: PlaybackTransitionIntent.manualAdvance,
              direction: pair.$2,
            )
            .candidates,
        isEmpty,
      );
    }
    expect(
      planner
          .plan(
            queue: queue(active: 4),
            mode: PlaybackMode.loopAll,
            intent: PlaybackTransitionIntent.manualAdvance,
          )
          .candidates
          .single
          .entryId,
      1,
    );
    expect(
      planner
          .plan(
            queue: queue(),
            mode: PlaybackMode.repeatOne,
            intent: PlaybackTransitionIntent.manualAdvance,
          )
          .candidates
          .single
          .entryId,
      3,
    );
  });

  test('transition budget bounds time, requests, and duplicate visits', () {
    var elapsed = Duration.zero;
    final budget = PlaybackTransitionBudget(
      elapsed: () => elapsed,
      maxDuration: const Duration(seconds: 20),
      maxRemoteRequests: 2,
    );

    expect(budget.visit(1), isTrue);
    expect(budget.visit(1), isFalse);
    expect(budget.consumeRemoteRequest(), isTrue);
    expect(budget.consumeRemoteRequest(), isTrue);
    expect(budget.consumeRemoteRequest(), isFalse);
    elapsed = const Duration(seconds: 7);
    expect(budget.remaining(), const Duration(seconds: 13));
    elapsed = const Duration(seconds: 30);
    expect(budget.remaining(), Duration.zero);
    expect(budget.consumeRemoteRequest(), isFalse);
  });
}

PlaybackQueueEntry entry(int entryId, int trackId) => PlaybackQueueEntry(
  entryId: entryId,
  track: Track(
    id: trackId,
    name: 'Track $trackId',
    artists: 'Artist',
    album: 'Album',
    picUrl: '',
    source: MusicSource.netease,
  ),
);
