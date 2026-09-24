import 'package:cyrene_music/services/playback/playback_transaction.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('PlaybackTransactionGuard', () {
    test('new transaction invalidates an older switch result', () {
      final guard = PlaybackTransactionGuard();
      final first = guard.begin();
      final second = guard.begin();

      expect(guard.isCurrent(first), isFalse);
      expect(guard.isCurrent(second), isTrue);
    });

    test('current transaction remains committable', () {
      final guard = PlaybackTransactionGuard();
      final token = guard.begin();

      expect(guard.isCurrent(token), isTrue);
    });
  });

  group('PlaybackStartCommitter', () {
    test('failed switch leaves the start commit marker empty', () {
      final committer = PlaybackStartCommitter();

      expect(committer.committedToken, isNull);
    });

    test('engine start events commit history once per transaction', () {
      final committer = PlaybackStartCommitter();
      var historyWrites = 0;

      committer.commitOnce(token: 1, commit: () => historyWrites++);
      committer.commitOnce(token: 1, commit: () => historyWrites++);
      committer.commitOnce(token: 2, commit: () => historyWrites++);

      expect(historyWrites, 2);
    });
  });

  group('TransactionEventGate', () {
    test('publishes only the event belonging to the committed generation', () {
      final gate = TransactionEventGate<String>();
      gate.arm(1);
      expect(gate.capture(1, 'playing'), isTrue);
      gate.arm(2);
      expect(gate.capture(1, 'stale'), isFalse);
      expect(gate.capture(2, 'paused'), isTrue);

      expect(gate.take(1), isNull);
      expect(gate.take(2), 'paused');
      expect(gate.take(2), isNull);
    });

    test('discard prevents a failed transition event from being committed', () {
      final gate = TransactionEventGate<String>();
      gate.arm(3);
      gate.capture(3, 'playing');
      gate.discard(3);

      expect(gate.take(3), isNull);
    });
  });
}
