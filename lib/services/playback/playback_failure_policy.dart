enum PlaybackRequestIntent { manual, automatic, retry, restore }

class PlaybackFailureDecision {
  final bool shouldAutoSkip;
  final bool reachedFailureLimit;
  final Duration delay;

  const PlaybackFailureDecision({
    required this.shouldAutoSkip,
    required this.reachedFailureLimit,
    required this.delay,
  });
}

class PlaybackFailurePolicy {
  final int maxConsecutiveFailures;
  final Duration autoSkipDelay;

  const PlaybackFailurePolicy({
    this.maxConsecutiveFailures = 3,
    this.autoSkipDelay = const Duration(seconds: 2),
  });

  PlaybackFailureDecision evaluate({
    required PlaybackRequestIntent intent,
    required int consecutiveFailures,
    required int queueLength,
  }) {
    final reachedLimit = consecutiveFailures >= maxConsecutiveFailures;
    final canAdvance = queueLength > 1;
    final shouldAutoSkip =
        intent == PlaybackRequestIntent.automatic &&
        canAdvance &&
        !reachedLimit;
    return PlaybackFailureDecision(
      shouldAutoSkip: shouldAutoSkip,
      reachedFailureLimit: reachedLimit,
      delay: autoSkipDelay,
    );
  }
}
