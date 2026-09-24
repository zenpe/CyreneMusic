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

  const PlaybackCandidateAttemptResult(this.status, {this.message});

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

    for (final candidate in plan.candidates) {
      if (!isCurrent()) {
        return _result(
          PlaybackTransitionResultStatus.cancelled,
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

      lastFailed = candidate;
      skippedCount++;
      if (outcome.status == PlaybackCandidateAttemptStatus.sourceFailure) {
        return _result(
          PlaybackTransitionResultStatus.sourceFailure,
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
        // The remote request cap must not hide a later local or cached entry.
        // Candidate attempts still perform their local lookup before reporting
        // that another remote request cannot be started.
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
