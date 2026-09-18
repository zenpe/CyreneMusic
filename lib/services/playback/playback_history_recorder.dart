import 'dart:async';

import '../../models/track.dart';
import '../listening_stats_service.dart';
import '../play_history_service.dart';
import 'playback_transaction.dart';

class PlaybackHistoryRecorder {
  PlaybackHistoryRecorder({
    void Function(Track track)? addToHistory,
    void Function(Track track)? recordPlayCount,
    void Function(int seconds)? accumulateListeningTime,
    DateTime Function()? now,
    Duration listeningTick = const Duration(seconds: 5),
  }) : _addToHistory = addToHistory ?? PlayHistoryService().addToHistory,
       _recordPlayCount =
           recordPlayCount ?? ListeningStatsService().recordPlayCount,
       _accumulateListeningTime =
           accumulateListeningTime ??
           ListeningStatsService().accumulateListeningTime,
       _now = now ?? DateTime.now,
       _listeningTick = listeningTick;

  final void Function(Track track) _addToHistory;
  final void Function(Track track) _recordPlayCount;
  final void Function(int seconds) _accumulateListeningTime;
  final DateTime Function() _now;
  final Duration _listeningTick;
  final PlaybackStartCommitter _startCommitter = PlaybackStartCommitter();

  Timer? _listeningTimer;
  DateTime? _listeningStartedAt;

  bool recordStarted({required int transactionId, required Track track}) {
    return _startCommitter.commitOnce(
      token: transactionId,
      commit: () {
        _addToHistory(track);
        _recordPlayCount(track);
      },
    );
  }

  void startListening() {
    if (_listeningTimer?.isActive ?? false) return;
    _listeningStartedAt = _now();
    _listeningTimer = Timer.periodic(_listeningTick, (_) => _flushElapsed());
  }

  void pauseListening() {
    _flushElapsed();
    _listeningTimer?.cancel();
    _listeningTimer = null;
    _listeningStartedAt = null;
  }

  void _flushElapsed() {
    final startedAt = _listeningStartedAt;
    if (startedAt == null) return;
    final current = _now();
    final elapsed = current.difference(startedAt).inSeconds;
    if (elapsed > 0) _accumulateListeningTime(elapsed);
    _listeningStartedAt = current;
  }

  void dispose() => pauseListening();
}
