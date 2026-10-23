import 'package:cyrene_music/models/track.dart';
import 'package:cyrene_music/services/playback/playback_candidate_planner.dart';
import 'package:cyrene_music/services/playback/playback_transition.dart';
import 'package:cyrene_music/services/playback/playback_transition_coordinator.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const coordinator = PlaybackTransitionCoordinator();

  test(
    'automatic candidates share resolution time and preserve native reserve',
    () async {
      var elapsed = Duration.zero;
      final budget = PlaybackTransitionBudget(
        shareResolutionBudget: true,
        elapsed: () => elapsed,
      );
      final slices = <Duration>[];
      await coordinator.run(
        plan: PlaybackCandidatePlan(
          candidates: [entry(1), entry(2), entry(3)],
          stopsAtQueueEnd: false,
        ),
        budget: budget,
        isCurrent: () => true,
        attempt: (_, budget, _) async {
          expect(budget.consumeRemoteRequest(), isTrue);
          final slice = budget.resolutionTimeout(const Duration(seconds: 6));
          slices.add(slice);
          elapsed += slice;
          return const PlaybackCandidateAttemptResult(
            PlaybackCandidateAttemptStatus.trackFailure,
          );
        },
      );
      expect(slices, List.filled(3, const Duration(seconds: 3)));
      expect(budget.remaining(), PlaybackTransitionBudget.nativeLoadReserve);
    },
  );

  test('single automatic candidate keeps a normal resolution window', () {
    final budget = PlaybackTransitionBudget(
      shareResolutionBudget: true,
      elapsed: () => Duration.zero,
    );
    budget.prepareCandidate(remainingCandidates: 1, failedCandidates: 0);
    expect(budget.consumeRemoteRequest(), isTrue);
    expect(
      budget.resolutionTimeout(const Duration(seconds: 6)),
      const Duration(seconds: 6),
    );
  });

  test(
    'bounded startup network wait does not spend resolution/load budget',
    () {
      var elapsed = const Duration(seconds: 9);
      final budget = PlaybackTransitionBudget(
        maxDuration: const Duration(seconds: 10),
        elapsed: () => elapsed,
      );
      budget.excludeElapsed(const Duration(seconds: 8));
      expect(budget.remaining(), const Duration(seconds: 9));
      expect(
        budget.resolutionTimeout(const Duration(seconds: 6)),
        const Duration(seconds: 6),
      );
      elapsed = const Duration(seconds: 15);
      expect(budget.remaining(), const Duration(seconds: 3));
      expect(budget.consumeRemoteRequest(), isFalse);
    },
  );
  final candidates = [entry(1), entry(2), entry(3)];
  final plan = PlaybackCandidatePlan(
    candidates: candidates,
    stopsAtQueueEnd: false,
  );

  test(
    'resolution retries leave a native load window instead of spending the deadline',
    () {
      var elapsed = Duration.zero;
      final budget = PlaybackTransitionBudget(
        maxDuration: const Duration(seconds: 10),
        elapsed: () => elapsed,
      );
      expect(
        budget.resolutionTimeout(const Duration(seconds: 6)),
        const Duration(seconds: 6),
      );
      expect(budget.consumeRemoteRequest(), isTrue);
      elapsed = const Duration(seconds: 6);
      expect(budget.resolutionTimeRemaining, const Duration(seconds: 1));
      expect(budget.consumeRemoteRequest(), isFalse);
      expect(budget.remoteRequests, 1);
      expect(budget.remaining(), const Duration(seconds: 4));
    },
  );

  test('local failures also obey the candidate limit', () async {
    final attempted = <int>[];
    final result = await coordinator.run(
      plan: PlaybackCandidatePlan(
        candidates: List.generate(20, (i) => entry(i)),
        stopsAtQueueEnd: false,
      ),
      budget: fixedBudget(),
      isCurrent: () => true,
      attempt: (candidate, budget, isCurrent) async {
        attempted.add(candidate.entryId);
        return const PlaybackCandidateAttemptResult(
          PlaybackCandidateAttemptStatus.trackFailure,
        );
      },
    );
    expect(attempted, [0, 1, 2]);
    expect(result.status, PlaybackTransitionResultStatus.exhausted);
    expect(result.skippedCount, 3);
  });

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
          attempted: false,
        );
      },
    );

    expect(attempted, [1, 2, 3]);
    expect(result.status, PlaybackTransitionResultStatus.budgetExhausted);
    expect(result.skippedCount, 0);
    expect(result.lastFailedCandidate, isNull);
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
            attempted: false,
          );
        }
        return PlaybackCandidateAttemptResult.committed;
      },
    );

    expect(attempted, [1, 2]);
    expect(result.status, PlaybackTransitionResultStatus.committed);
    expect(result.committedCandidate?.entryId, 2);
    expect(result.skippedCount, 0);
  });

  test(
    'unrequested candidates cannot bypass the bound to find distant cache',
    () async {
      final visited = <int>[];
      final result = await coordinator.run(
        plan: PlaybackCandidatePlan(
          candidates: List.generate(24, entry),
          stopsAtQueueEnd: false,
        ),
        budget: fixedBudget(),
        isCurrent: () => true,
        attempt: (candidate, budget, _) async {
          visited.add(candidate.entryId);
          if (candidate.entryId == 23) {
            return PlaybackCandidateAttemptResult.committed;
          }
          return const PlaybackCandidateAttemptResult(
            PlaybackCandidateAttemptStatus.budgetExhausted,
            attempted: false,
          );
        },
      );
      expect(visited, [0, 1, 2]);
      expect(result.status, PlaybackTransitionResultStatus.budgetExhausted);
      expect(result.skippedCount, 0);
    },
  );

  test('time exhaustion stops after the actual failed candidate', () async {
    var elapsed = Duration.zero;
    final attempted = <int>[];
    final result = await coordinator.run(
      plan: plan,
      budget: PlaybackTransitionBudget(elapsed: () => elapsed),
      isCurrent: () => true,
      attempt: (candidate, budget, isCurrent) async {
        attempted.add(candidate.entryId);
        elapsed = const Duration(seconds: 12);
        return const PlaybackCandidateAttemptResult(
          PlaybackCandidateAttemptStatus.trackFailure,
        );
      },
    );
    expect(attempted, [1]);
    expect(result.status, PlaybackTransitionResultStatus.budgetExhausted);
    expect(result.lastFailedCandidate?.entryId, 1);
    expect(result.skippedCount, 1);
  });

  test('budget uses elapsed duration and bounds remote requests', () {
    var elapsed = Duration.zero;
    final budget = PlaybackTransitionBudget(
      maxDuration: const Duration(seconds: 10),
      maxRemoteRequests: 2,
      elapsed: () => elapsed,
    );

    expect(budget.remaining(), const Duration(seconds: 10));
    expect(budget.consumeRemoteRequest(), isTrue);
    elapsed = const Duration(seconds: 5);
    expect(budget.remaining(), const Duration(seconds: 5));
    expect(budget.consumeRemoteRequest(), isTrue);
    expect(budget.consumeRemoteRequest(), isFalse);
    elapsed = const Duration(seconds: 6);
    expect(budget.remaining(), const Duration(seconds: 4));
    expect(budget.consumeRemoteRequest(), isFalse);
    elapsed = const Duration(seconds: 11);
    expect(budget.remaining(), Duration.zero);
    expect(budget.hasTimeRemaining, isFalse);
  });

  test(
    'request cap does not move failure cursor past the last attempted track',
    () async {
      final result = await coordinator.run(
        plan: plan,
        budget: fixedBudget(),
        isCurrent: () => true,
        attempt: (candidate, budget, isCurrent) async => candidate.entryId == 1
            ? const PlaybackCandidateAttemptResult(
                PlaybackCandidateAttemptStatus.trackFailure,
              )
            : const PlaybackCandidateAttemptResult(
                PlaybackCandidateAttemptStatus.budgetExhausted,
                attempted: false,
              ),
      );
      expect(result.lastFailedCandidate?.entryId, 1);
      expect(result.skippedCount, 1);
    },
  );
}

PlaybackTransitionBudget fixedBudget() {
  return PlaybackTransitionBudget(elapsed: () => Duration.zero);
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
