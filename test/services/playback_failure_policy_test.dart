import 'package:cyrene_music/services/playback/playback_failure_policy.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const policy = PlaybackRecoveryPolicy();

  test(
    'typed connection failure retries once; script and empty results do not',
    () {
      for (final cause in [
        PlaybackFailureCause.transientNetwork,
        PlaybackFailureCause.requestFailed,
        PlaybackFailureCause.emptyUrl,
      ]) {
        for (final available in [false, true]) {
          final decision = policy.decide(
            PlaybackFailureEvidence(
              cause: cause,
              scope: PlaybackFailureScope.network,
            ),
            PlaybackRecoveryContext(
              retryAvailable: available,
              navigatingQueue: false,
            ),
          );
          expect(
            decision.retryResolution,
            available && cause == PlaybackFailureCause.transientNetwork,
          );
        }
      }
    },
  );

  test('transient resolution failure retries only when budget allows', () {
    const failure = PlaybackFailureEvidence(
      cause: PlaybackFailureCause.timeout,
      scope: PlaybackFailureScope.network,
    );

    expect(
      policy
          .decide(
            failure,
            const PlaybackRecoveryContext(
              retryAvailable: true,
              navigatingQueue: true,
            ),
          )
          .retryResolution,
      isTrue,
    );
    final exhausted = policy.decide(
      failure,
      const PlaybackRecoveryContext(
        retryAvailable: false,
        navigatingQueue: true,
      ),
    );
    expect(exhausted.retryResolution, isFalse);
    expect(exhausted.continueQueue, isFalse);
  });

  test('source failure stops queue scan without retrying', () {
    final decision = policy.decide(
      const PlaybackFailureEvidence(
        cause: PlaybackFailureCause.sourceRejected,
        scope: PlaybackFailureScope.source,
      ),
      const PlaybackRecoveryContext(
        retryAvailable: true,
        navigatingQueue: true,
      ),
    );

    expect(decision.retryResolution, isFalse);
    expect(decision.continueQueue, isFalse);
    expect(decision.stopForSource, isTrue);
  });

  test('permanent track failure stays on the selected song', () {
    const failure = PlaybackFailureEvidence(
      cause: PlaybackFailureCause.invalidTrackIdentifier,
      scope: PlaybackFailureScope.track,
    );

    expect(
      policy
          .decide(
            failure,
            const PlaybackRecoveryContext(
              retryAvailable: true,
              navigatingQueue: true,
            ),
          )
          .continueQueue,
      isFalse,
    );
    expect(
      policy
          .decide(
            failure,
            const PlaybackRecoveryContext(
              retryAvailable: true,
              navigatingQueue: false,
            ),
          )
          .continueQueue,
      isFalse,
    );
  });
}
