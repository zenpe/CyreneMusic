enum PlaybackFailureScope {
  track,
  source,
  network,
  engine,
  configuration,
  cancelled,
}

enum PlaybackFailureCause {
  sourceNotConfigured,
  sourceRejected,
  sourceNotReady,
  timeout,
  networkUnavailable,
  requestFailed,
  emptyUrl,
  invalidTrackIdentifier,
  localFileMissing,
  accessDenied,
  unsupportedFormat,
  sourceLoad,
  playback,
  unknown,
}

class PlaybackFailureEvidence {
  final PlaybackFailureCause cause;
  final PlaybackFailureScope scope;

  const PlaybackFailureEvidence({required this.cause, required this.scope});
}

class PlaybackRecoveryContext {
  final bool retryAvailable;
  final bool navigatingQueue;

  const PlaybackRecoveryContext({
    required this.retryAvailable,
    required this.navigatingQueue,
  });
}

class PlaybackRecoveryDecision {
  final bool retryResolution;
  final bool continueQueue;
  final bool stopForSource;

  const PlaybackRecoveryDecision({
    required this.retryResolution,
    required this.continueQueue,
    required this.stopForSource,
  });
}

/// Pure recovery policy. It classifies facts without reading or mutating
/// playback, presentation, cache, or source-health state.
class PlaybackRecoveryPolicy {
  const PlaybackRecoveryPolicy();

  PlaybackRecoveryDecision decide(
    PlaybackFailureEvidence failure,
    PlaybackRecoveryContext context,
  ) {
    final sourceWide =
        failure.scope == PlaybackFailureScope.source ||
        failure.scope == PlaybackFailureScope.configuration;
    final retryableResolution = switch (failure.cause) {
      PlaybackFailureCause.timeout ||
      PlaybackFailureCause.requestFailed ||
      PlaybackFailureCause.emptyUrl ||
      PlaybackFailureCause.sourceNotReady => true,
      _ => false,
    };
    final retry = context.retryAvailable && retryableResolution;
    return PlaybackRecoveryDecision(
      retryResolution: retry,
      continueQueue: context.navigatingQueue && !retry && !sourceWide,
      stopForSource: !retry && sourceWide,
    );
  }
}
