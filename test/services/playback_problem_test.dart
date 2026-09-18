import 'package:cyrene_music/models/track.dart';
import 'package:cyrene_music/services/playback/playback_problem.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final track = Track(
    id: 1,
    name: 'Test track',
    artists: 'Test artist',
    album: 'Test album',
    picUrl: '',
    source: MusicSource.netease,
  );

  test('retry capability is derived from recovery actions', () {
    final problem = PlaybackProblem(
      id: 1,
      transactionId: 9,
      track: track,
      kind: PlaybackProblemKind.networkTimeout,
      message: 'Network timeout',
      recoveryActions: const {PlaybackRecoveryAction.retry},
      occurredAt: DateTime.utc(2026),
    );

    expect(problem.canRetry, isTrue);
  });

  test('recovery actions have one consistent presentation order', () {
    final problem = PlaybackProblem(
      id: 1,
      transactionId: 1,
      track: track,
      kind: PlaybackProblemKind.sourceInvalid,
      message: 'failed',
      recoveryActions: const {
        PlaybackRecoveryAction.reimportSource,
        PlaybackRecoveryAction.retry,
        PlaybackRecoveryAction.switchSource,
      },
      occurredAt: DateTime(2026),
    );

    expect(problem.orderedRecoveryActions, [
      PlaybackRecoveryAction.retry,
      PlaybackRecoveryAction.switchSource,
      PlaybackRecoveryAction.reimportSource,
    ]);
  });

  test('non-retriable problem remains actionable without retry', () {
    final problem = PlaybackProblem(
      id: 2,
      transactionId: 10,
      track: track,
      kind: PlaybackProblemKind.sourceInvalid,
      message: 'Source invalid',
      recoveryActions: const {
        PlaybackRecoveryAction.switchSource,
        PlaybackRecoveryAction.reimportSource,
      },
      occurredAt: DateTime.utc(2026),
    );

    expect(problem.canRetry, isFalse);
    expect(
      problem.recoveryActions,
      containsAll({
        PlaybackRecoveryAction.switchSource,
        PlaybackRecoveryAction.reimportSource,
      }),
    );
  });

  test('store emits at most one problem per playback transaction', () {
    final store = PlaybackProblemStore();
    final first = store.report(
      transactionId: 20,
      track: track,
      kind: PlaybackProblemKind.sourceInvalid,
      message: 'Source invalid',
      recoveryActions: const {PlaybackRecoveryAction.reimportSource},
    );
    final duplicate = store.report(
      transactionId: 20,
      track: track,
      kind: PlaybackProblemKind.unknown,
      message: 'Duplicate',
      recoveryActions: const {},
    );

    expect(first, isNotNull);
    expect(duplicate, isNull);
    expect(store.current, same(first));
  });

  test('store clears visible state and accepts the next transaction', () {
    final store = PlaybackProblemStore();
    final first = store.report(
      transactionId: 30,
      track: track,
      kind: PlaybackProblemKind.networkTimeout,
      message: 'Timeout',
      recoveryActions: const {PlaybackRecoveryAction.retry},
    );

    expect(store.clear(), isTrue);
    expect(store.current, isNull);
    expect(store.clear(), isFalse);

    final next = store.report(
      transactionId: 31,
      track: track,
      kind: PlaybackProblemKind.accessDenied,
      message: 'Denied',
      recoveryActions: const {},
    );
    expect(next, isNotNull);
    expect(next!.id, greaterThan(first!.id));
  });
}
