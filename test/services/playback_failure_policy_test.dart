import 'package:cyrene_music/services/playback/playback_failure_policy.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const policy = PlaybackFailurePolicy();

  test('manual playback failure never advances the queue', () {
    final decision = policy.evaluate(
      intent: PlaybackRequestIntent.manual,
      consecutiveFailures: 1,
      queueLength: 10,
    );

    expect(decision.shouldAutoSkip, isFalse);
  });

  test('retry and restore failures never advance the queue', () {
    for (final intent in [
      PlaybackRequestIntent.retry,
      PlaybackRequestIntent.restore,
    ]) {
      final decision = policy.evaluate(
        intent: intent,
        consecutiveFailures: 1,
        queueLength: 3,
      );
      expect(decision.shouldAutoSkip, isFalse);
    }
  });

  test('automatic playback failure advances when another track exists', () {
    final decision = policy.evaluate(
      intent: PlaybackRequestIntent.automatic,
      consecutiveFailures: 1,
      queueLength: 10,
    );

    expect(decision.shouldAutoSkip, isTrue);
    expect(decision.delay, const Duration(seconds: 2));
  });

  test('automatic playback stops at the consecutive failure limit', () {
    final decision = policy.evaluate(
      intent: PlaybackRequestIntent.automatic,
      consecutiveFailures: 3,
      queueLength: 10,
    );

    expect(decision.shouldAutoSkip, isFalse);
    expect(decision.reachedFailureLimit, isTrue);
  });

  test('automatic playback cannot advance a single-item queue', () {
    final decision = policy.evaluate(
      intent: PlaybackRequestIntent.automatic,
      consecutiveFailures: 1,
      queueLength: 1,
    );

    expect(decision.shouldAutoSkip, isFalse);
  });
}
