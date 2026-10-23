import '../../models/track.dart';
import '../playback_mode_service.dart';
import 'playback_transition.dart';

class PlaybackQueueEntry {
  final int entryId;
  final Track track;

  const PlaybackQueueEntry({required this.entryId, required this.track});
}

class PlaybackQueueSnapshot {
  final List<PlaybackQueueEntry> entries;
  final int? activeEntryId;
  final int structureRevision;

  const PlaybackQueueSnapshot({
    required this.entries,
    required this.activeEntryId,
    required this.structureRevision,
  });

  int indexOfEntry(int entryId) =>
      entries.indexWhere((entry) => entry.entryId == entryId);
}

class PlaybackCandidatePlan {
  final List<PlaybackQueueEntry> candidates;
  final bool stopsAtQueueEnd;

  const PlaybackCandidatePlan({
    required this.candidates,
    required this.stopsAtQueueEnd,
  });
}

class PlaybackCandidatePlanner {
  const PlaybackCandidatePlanner();

  PlaybackCandidatePlan plan({
    required PlaybackQueueSnapshot queue,
    required PlaybackMode mode,
    required PlaybackTransitionIntent intent,
    PlaybackTransitionDirection direction = PlaybackTransitionDirection.forward,
    List<int>? shuffleEntryOrder,
  }) {
    if (queue.entries.isEmpty) {
      return const PlaybackCandidatePlan(candidates: [], stopsAtQueueEnd: true);
    }

    if (!_shouldScan(intent)) {
      final activeIndex = queue.activeEntryId == null
          ? -1
          : queue.indexOfEntry(queue.activeEntryId!);
      return PlaybackCandidatePlan(
        candidates: activeIndex < 0 ? const [] : [queue.entries[activeIndex]],
        stopsAtQueueEnd: false,
      );
    }

    final manual = intent == PlaybackTransitionIntent.manualAdvance;
    if (mode == PlaybackMode.shuffle) {
      final plan = _planShuffle(queue, shuffleEntryOrder ?? const <int>[]);
      return PlaybackCandidatePlan(
        candidates: manual
            ? plan.candidates
                  .where((entry) => entry.entryId != queue.activeEntryId)
                  .take(1)
                  .toList()
            : plan.candidates,
        stopsAtQueueEnd: false,
      );
    }

    final activeIndex = queue.activeEntryId == null
        ? -1
        : queue.indexOfEntry(queue.activeEntryId!);
    if (activeIndex < 0) {
      return PlaybackCandidatePlan(
        candidates: List.unmodifiable(
          manual ? queue.entries.take(1) : queue.entries,
        ),
        stopsAtQueueEnd: mode == PlaybackMode.sequential,
      );
    }

    final step = direction == PlaybackTransitionDirection.forward ? 1 : -1;
    final wraps = mode != PlaybackMode.sequential;
    final candidates = <PlaybackQueueEntry>[];
    var index = activeIndex + step;
    // Never turn a failed navigation into apparent success by selecting the
    // active entry again. A one-item automatic loop is the only exception.
    final candidateLimit = manual
        ? (queue.entries.length > 1 ? 1 : 0)
        : (wraps && queue.entries.length == 1 ? 1 : queue.entries.length - 1);
    while (candidates.length < candidateLimit) {
      if (index < 0 || index >= queue.entries.length) {
        if (!wraps) break;
        index = index < 0 ? queue.entries.length - 1 : 0;
      }
      candidates.add(queue.entries[index]);
      if (index == activeIndex) break;
      index += step;
    }
    return PlaybackCandidatePlan(
      candidates: List.unmodifiable(candidates),
      stopsAtQueueEnd: !wraps,
    );
  }

  bool _shouldScan(PlaybackTransitionIntent intent) => switch (intent) {
    PlaybackTransitionIntent.manualAdvance ||
    PlaybackTransitionIntent.automaticAdvance ||
    PlaybackTransitionIntent.removeCurrent => true,
    PlaybackTransitionIntent.directSelection ||
    PlaybackTransitionIntent.retry ||
    PlaybackTransitionIntent.restore => false,
  };

  PlaybackCandidatePlan _planShuffle(
    PlaybackQueueSnapshot queue,
    List<int> shuffleEntryOrder,
  ) {
    final byId = <int, PlaybackQueueEntry>{
      for (final entry in queue.entries) entry.entryId: entry,
    };
    final activeId = queue.activeEntryId;
    final ordered = <PlaybackQueueEntry>[];
    final seen = <int>{?activeId};
    for (final entryId in shuffleEntryOrder) {
      final entry = byId[entryId];
      if (entry != null && seen.add(entryId)) ordered.add(entry);
    }
    for (final entry in queue.entries) {
      if (seen.add(entry.entryId)) ordered.add(entry);
    }
    if (activeId != null && queue.entries.length == 1) {
      final active = byId[activeId];
      if (active != null) ordered.add(active);
    }
    return PlaybackCandidatePlan(
      candidates: List.unmodifiable(ordered),
      stopsAtQueueEnd: false,
    );
  }
}
