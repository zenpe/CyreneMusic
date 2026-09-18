import '../../models/track.dart';

enum PlaybackProblemKind {
  sourceNotConfigured,
  sourceInvalid,
  resourceUnavailable,
  networkTimeout,
  accessDenied,
  unsupportedFormat,
  localFileMissing,
  engineFailure,
  unknown,
}

enum PlaybackRecoveryAction {
  retry,
  switchSource,
  reimportSource,
  openSourceSettings,
}

class PlaybackProblem {
  final int id;
  final int transactionId;
  final Track track;
  final PlaybackProblemKind kind;
  final String message;
  final Set<PlaybackRecoveryAction> recoveryActions;
  final DateTime occurredAt;

  const PlaybackProblem({
    required this.id,
    required this.transactionId,
    required this.track,
    required this.kind,
    required this.message,
    required this.recoveryActions,
    required this.occurredAt,
  });

  bool get canRetry => recoveryActions.contains(PlaybackRecoveryAction.retry);

  List<PlaybackRecoveryAction> get orderedRecoveryActions => [
    PlaybackRecoveryAction.retry,
    PlaybackRecoveryAction.switchSource,
    PlaybackRecoveryAction.reimportSource,
    PlaybackRecoveryAction.openSourceSettings,
  ].where(recoveryActions.contains).toList(growable: false);
}

class PlaybackProblemStore {
  int _sequence = 0;
  int? _reportedTransactionId;
  PlaybackProblem? _current;

  PlaybackProblem? get current => _current;

  PlaybackProblem? report({
    required int transactionId,
    required Track track,
    required PlaybackProblemKind kind,
    required String message,
    required Set<PlaybackRecoveryAction> recoveryActions,
    DateTime? occurredAt,
  }) {
    if (_reportedTransactionId == transactionId) return null;
    _reportedTransactionId = transactionId;
    return _current = PlaybackProblem(
      id: ++_sequence,
      transactionId: transactionId,
      track: track,
      kind: kind,
      message: message,
      recoveryActions: Set.unmodifiable(recoveryActions),
      occurredAt: occurredAt ?? DateTime.now(),
    );
  }

  bool clear() {
    if (_current == null) return false;
    _current = null;
    return true;
  }
}
