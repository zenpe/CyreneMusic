import 'playback_candidate_planner.dart';
import 'playback_transition.dart';

enum PlaybackCandidateAttemptStatus {
  committed,
  trackFailure,
  sourceFailure,
  engineFailure,
  budgetExhausted,
  cancelled,
}

class PlaybackCandidateAttemptResult {
  final PlaybackCandidateAttemptStatus status;
  final String? message;
  final bool attempted;

  const PlaybackCandidateAttemptResult(
    this.status, {
    this.message,
    this.attempted = true,
  });

  static const committed = PlaybackCandidateAttemptResult(
    PlaybackCandidateAttemptStatus.committed,
  );
  static const cancelled = PlaybackCandidateAttemptResult(
    PlaybackCandidateAttemptStatus.cancelled,
  );
}

enum PlaybackTransitionResultStatus {
  committed,
  exhausted,
  sourceFailure,
  budgetExhausted,
  cancelled,
}

class PlaybackTransitionResult {
  final PlaybackTransitionResultStatus status;
  final PlaybackQueueEntry? committedCandidate;
  final PlaybackQueueEntry? lastFailedCandidate;
  final int skippedCount;
  final String? message;

  const PlaybackTransitionResult({
    required this.status,
    required this.committedCandidate,
    required this.lastFailedCandidate,
    required this.skippedCount,
    this.message,
  });
}

typedef PlaybackCandidateAttempt =
    Future<PlaybackCandidateAttemptResult> Function(
      PlaybackQueueEntry candidate,
      PlaybackTransitionBudget budget,
      bool Function() isCurrent,
    );

class PlaybackTransitionCoordinator {
  const PlaybackTransitionCoordinator();

  Future<PlaybackTransitionResult> run({
    required PlaybackCandidatePlan plan,
    required PlaybackTransitionBudget budget,
    required bool Function() isCurrent,
    required PlaybackCandidateAttempt attempt,
  }) async {
    PlaybackQueueEntry? lastFailed;
    var skippedCount = 0;
    var remoteBudgetExhausted = false;
    var consideredCount = 0;

    for (var index = 0; index < plan.candidates.length; index++) {
      final candidate = plan.candidates[index];
      if (!isCurrent()) {
        return _result(
          PlaybackTransitionResultStatus.cancelled,
          lastFailed: lastFailed,
          skippedCount: skippedCount,
        );
      }
      if (consideredCount >= budget.maxCandidateAttempts) {
        return _result(
          remoteBudgetExhausted
              ? PlaybackTransitionResultStatus.budgetExhausted
              : PlaybackTransitionResultStatus.exhausted,
          lastFailed: lastFailed,
          skippedCount: skippedCount,
        );
      }
      if (!budget.hasTimeRemaining || !budget.visit(candidate.entryId)) {
        if (!budget.hasTimeRemaining) {
          return _result(
            PlaybackTransitionResultStatus.budgetExhausted,
            lastFailed: lastFailed,
            skippedCount: skippedCount,
          );
        }
        continue;
      }

      consideredCount++;

      budget.prepareCandidate(
        remainingCandidates: plan.candidates.length - index,
        failedCandidates: consideredCount - 1,
      );
      final outcome = await attempt(candidate, budget, isCurrent);
      if (!isCurrent() ||
          outcome.status == PlaybackCandidateAttemptStatus.cancelled) {
        return _result(
          PlaybackTransitionResultStatus.cancelled,
          lastFailed: lastFailed,
          skippedCount: skippedCount,
          message: outcome.message,
        );
      }
      if (outcome.status == PlaybackCandidateAttemptStatus.committed) {
        return PlaybackTransitionResult(
          status: PlaybackTransitionResultStatus.committed,
          committedCandidate: candidate,
          lastFailedCandidate: lastFailed,
          skippedCount: skippedCount,
        );
      }

      if (outcome.attempted) {
        lastFailed = candidate;
        skippedCount++;
      }
      if (outcome.status == PlaybackCandidateAttemptStatus.sourceFailure) {
        return _result(
          PlaybackTransitionResultStatus.sourceFailure,
          lastFailed: lastFailed,
          skippedCount: skippedCount,
          message: outcome.message,
        );
      }
      if (skippedCount >= budget.maxCandidateAttempts) {
        return _result(
          PlaybackTransitionResultStatus.exhausted,
          lastFailed: lastFailed,
          skippedCount: skippedCount,
          message: outcome.message,
        );
      }
      if (!budget.hasTimeRemaining) {
        return _result(
          PlaybackTransitionResultStatus.budgetExhausted,
          lastFailed: lastFailed,
          skippedCount: skippedCount,
          message: outcome.message,
        );
      }
      if (outcome.status == PlaybackCandidateAttemptStatus.budgetExhausted) {
        // A cached entry may still play, but only inside the same bounded
        // candidate window. Never walk the entire queue looking for a cache hit.
        remoteBudgetExhausted = true;
      }
    }

    return _result(
      remoteBudgetExhausted
          ? PlaybackTransitionResultStatus.budgetExhausted
          : PlaybackTransitionResultStatus.exhausted,
      lastFailed: lastFailed,
      skippedCount: skippedCount,
    );
  }

  PlaybackTransitionResult _result(
    PlaybackTransitionResultStatus status, {
    required PlaybackQueueEntry? lastFailed,
    required int skippedCount,
    String? message,
  }) => PlaybackTransitionResult(
    status: status,
    committedCandidate: null,
    lastFailedCandidate: lastFailed,
    skippedCount: skippedCount,
    message: message,
  );
}
