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

  test('manual next scans forward once and wraps without repeating active', () {
    final plan = planner.plan(
      queue: queue(),
      mode: PlaybackMode.sequential,
      intent: PlaybackTransitionIntent.manualAdvance,
    );

    expect(plan.candidates.map((item) => item.entryId), [3, 4, 1, 2]);
    expect(plan.stopsAtQueueEnd, isFalse);
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

    expect(plan.candidates.map((item) => item.entryId), [1, 2, 3, 4]);
  });

  test('duplicate tracks remain distinct candidates by entry id', () {
    final plan = planner.plan(
      queue: queue(active: 4),
      mode: PlaybackMode.loopAll,
      intent: PlaybackTransitionIntent.manualAdvance,
    );

    expect(plan.candidates.take(2).map((item) => item.entryId), [1, 2]);
    expect(plan.candidates.take(2).map((item) => item.track.id), [10, 10]);
  });

  test('shuffle order is deduplicated and excludes the active entry', () {
    final plan = planner.plan(
      queue: queue(),
      mode: PlaybackMode.shuffle,
      intent: PlaybackTransitionIntent.manualAdvance,
      shuffleEntryOrder: const [4, 3, 4, 2, 1],
    );

    expect(plan.candidates.map((item) => item.entryId), [4, 3, 1, 2]);
  });

  test('direct selection never scans adjacent entries', () {
    final plan = planner.plan(
      queue: queue(),
      mode: PlaybackMode.loopAll,
      intent: PlaybackTransitionIntent.directSelection,
    );

    expect(plan.candidates.map((item) => item.entryId), [2]);
  });

  test('manual next in a one-item loop retries that single entry once', () {
    final plan = planner.plan(
      queue: PlaybackQueueSnapshot(
        entries: [entry(1, 10)],
        activeEntryId: 1,
        structureRevision: 1,
      ),
      mode: PlaybackMode.loopAll,
      intent: PlaybackTransitionIntent.manualAdvance,
    );

    expect(plan.candidates.map((item) => item.entryId), [1]);
  });

  test('transition budget bounds time, requests, and duplicate visits', () {
    final started = DateTime(2026, 1, 1, 12);
    final budget = PlaybackTransitionBudget(
      startedAt: started,
      now: () => started,
      maxDuration: const Duration(seconds: 20),
      maxRemoteRequests: 2,
    );

    expect(budget.visit(1), isTrue);
    expect(budget.visit(1), isFalse);
    expect(budget.consumeRemoteRequest(), isTrue);
    expect(budget.consumeRemoteRequest(), isTrue);
    expect(budget.consumeRemoteRequest(), isFalse);
    expect(
      budget.remaining(started.add(const Duration(seconds: 7))),
      const Duration(seconds: 13),
    );
    expect(
      budget.remaining(started.add(const Duration(seconds: 30))),
      Duration.zero,
    );
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
