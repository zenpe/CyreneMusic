import 'package:cyrene_music/models/track.dart';
import 'package:cyrene_music/services/playback/playback_candidate_planner.dart';
import 'package:cyrene_music/services/playback/playback_transition.dart';
import 'package:cyrene_music/services/playback/playback_transition_coordinator.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const coordinator = PlaybackTransitionCoordinator();
  final candidates = [entry(1), entry(2), entry(3)];
  final plan = PlaybackCandidatePlan(
    candidates: candidates,
    stopsAtQueueEnd: false,
  );

  test(
    'continues track failures and commits the first playable candidate',
    () async {
      final attempted = <int>[];
      final result = await coordinator.run(
        plan: plan,
        budget: fixedBudget(),
        isCurrent: () => true,
        attempt: (candidate, budget, isCurrent) async {
          attempted.add(candidate.entryId);
          return candidate.entryId == 3
              ? PlaybackCandidateAttemptResult.committed
              : const PlaybackCandidateAttemptResult(
                  PlaybackCandidateAttemptStatus.trackFailure,
                );
        },
      );

      expect(attempted, [1, 2, 3]);
      expect(result.status, PlaybackTransitionResultStatus.committed);
      expect(result.committedCandidate?.entryId, 3);
      expect(result.skippedCount, 2);
    },
  );

  test('source failure stops without trying another track', () async {
    final attempted = <int>[];
    final result = await coordinator.run(
      plan: plan,
      budget: fixedBudget(),
      isCurrent: () => true,
      attempt: (candidate, budget, isCurrent) async {
        attempted.add(candidate.entryId);
        return const PlaybackCandidateAttemptResult(
          PlaybackCandidateAttemptStatus.sourceFailure,
        );
      },
    );

    expect(attempted, [1]);
    expect(result.status, PlaybackTransitionResultStatus.sourceFailure);
  });

  test('newer request cancels a scan before the next candidate', () async {
    var current = true;
    final result = await coordinator.run(
      plan: plan,
      budget: fixedBudget(),
      isCurrent: () => current,
      attempt: (candidate, budget, isCurrent) async {
        current = false;
        return const PlaybackCandidateAttemptResult(
          PlaybackCandidateAttemptStatus.trackFailure,
        );
      },
    );

    expect(result.status, PlaybackTransitionResultStatus.cancelled);
  });

  test('reports remote budget exhaustion after checking the cycle', () async {
    final attempted = <int>[];
    final result = await coordinator.run(
      plan: plan,
      budget: fixedBudget(),
      isCurrent: () => true,
      attempt: (candidate, budget, isCurrent) async {
        attempted.add(candidate.entryId);
        return const PlaybackCandidateAttemptResult(
          PlaybackCandidateAttemptStatus.budgetExhausted,
        );
      },
    );

    expect(attempted, [1, 2, 3]);
    expect(result.status, PlaybackTransitionResultStatus.budgetExhausted);
    expect(result.skippedCount, 3);
  });

  test('can commit a local candidate after remote budget exhaustion', () async {
    final attempted = <int>[];
    final result = await coordinator.run(
      plan: plan,
      budget: fixedBudget(),
      isCurrent: () => true,
      attempt: (candidate, budget, isCurrent) async {
        attempted.add(candidate.entryId);
        if (candidate.entryId == 1) {
          return const PlaybackCandidateAttemptResult(
            PlaybackCandidateAttemptStatus.budgetExhausted,
          );
        }
        return PlaybackCandidateAttemptResult.committed;
      },
    );

    expect(attempted, [1, 2]);
    expect(result.status, PlaybackTransitionResultStatus.committed);
    expect(result.committedCandidate?.entryId, 2);
    expect(result.skippedCount, 1);
  });
}

PlaybackTransitionBudget fixedBudget() {
  final now = DateTime(2026, 1, 1);
  return PlaybackTransitionBudget(startedAt: now, now: () => now);
}

PlaybackQueueEntry entry(int id) => PlaybackQueueEntry(
  entryId: id,
  track: Track(
    id: id,
    name: 'Track $id',
    artists: 'Artist',
    album: 'Album',
    picUrl: '',
    source: MusicSource.netease,
  ),
);
