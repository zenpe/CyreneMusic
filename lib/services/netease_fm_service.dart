import '../models/track.dart';
import 'dart:async';
import 'package:flutter/foundation.dart';
import 'netease_login_service.dart';
import 'netease_recommend_service.dart';
import 'playlist_queue_service.dart';
import 'player_service.dart';
import '../utils/netease_track.dart';

/// Runs only while this FM owns the radio queue. No periodic network polling.
class NeteaseFmService extends ChangeNotifier {
  static final NeteaseFmService _instance = NeteaseFmService._();
  factory NeteaseFmService() => _instance;
  NeteaseFmService._() {
    PlaylistQueueService().addListener(_queueChanged);
    NeteaseLoginService().addListener(_identityChanged);
  }
  bool active = false;
  bool loading = false;
  String? error;
  String? identity;
  int generation = 0;
  int lastAttempt = 0;
  final Set<String> seen = {};
  int? tailEntry;
  String get scope =>
      '${NeteaseLoginService().scope}:${NeteaseLoginService().bindingRevision}';
  void _identityChanged() {
    if (identity != scope) {
      generation++;
      active = false;
      seen.clear();
      notifyListeners();
    }
  }

  void _queueChanged() {
    if (!active || loading) return;
    final q = PlaylistQueueService();
    if (q.source != QueueSource.neteaseFm ||
        q.queue.isEmpty ||
        q.entryIdAt(q.queue.length - 1) != tailEntry) {
      active = false;
      notifyListeners();
      return;
    }
    if (q.currentIndex >= q.queue.length - 2 &&
        DateTime.now().millisecondsSinceEpoch - lastAttempt > 10000) {
      unawaited(_fetch(false));
    }
  }

  Future<void> start({List<Map<String, dynamic>>? initialSongs}) async {
    if (loading) return;
    generation++;
    identity = scope;
    active = true;
    seen.clear();
    error = null;
    await _fetch(true, initialSongs: initialSongs);
  }

  /// Reattach to a restored FM queue without changing its song or ordinary mode.
  Future<void> resumeRestoredQueue() async {
    final queue = PlaylistQueueService();
    if (active ||
        loading ||
        queue.source != QueueSource.neteaseFm ||
        queue.queue.isEmpty) {
      return;
    }
    final tail = queue.entryIdAt(queue.queue.length - 1);
    final accountScope = NeteaseLoginService().scope;
    try {
      final bound = await NeteaseLoginService().isNeteaseBound();
      if (!bound ||
          accountScope != NeteaseLoginService().scope ||
          active ||
          loading ||
          queue.source != QueueSource.neteaseFm ||
          queue.entryIdAt(queue.queue.length - 1) != tail) {
        return;
      }
      generation++;
      identity = scope;
      active = true;
      tailEntry = tail;
      seen.addAll(queue.queue.map((t) => t.id.toString()));
      _queueChanged();
      notifyListeners();
    } catch (e) {
      error = e.toString();
      notifyListeners();
    }
  }

  Future<void> startTracks(List<Track> tracks, {int index = 0}) async {
    if (loading || tracks.isEmpty || index < 0 || index >= tracks.length) {
      return;
    }
    final mine = ++generation;
    identity = scope;
    active = true;
    loading = true;
    seen
      ..clear()
      ..addAll(tracks.map((t) => t.id.toString()));
    error = null;
    notifyListeners();
    try {
      await PlayerService().playCollection(
        tracks,
        index: index,
        source: QueueSource.neteaseFm,
      );
      if (mine != generation || identity != scope) return;
      final queue = PlaylistQueueService();
      active = queue.source == QueueSource.neteaseFm;
      tailEntry = queue.entryIdAt(queue.queue.length - 1);
    } finally {
      loading = false;
      notifyListeners();
    }
  }

  Future<void> _refreshBinding() async {
    try {
      await NeteaseLoginService().fetchBindings();
    } catch (_) {}
  }

  Future<void> _fetch(
    bool replace, {
    List<Map<String, dynamic>>? initialSongs,
  }) async {
    final mine = generation;
    final originalQueue = PlaylistQueueService();
    final originalSource = originalQueue.source;
    final originalTail = originalQueue.entryIdAt(
      originalQueue.queue.length - 1,
    );
    final originalIndex = originalQueue.currentIndex;
    final originalIntent = PlayerService().requestIdentity;
    loading = true;
    lastAttempt = DateTime.now().millisecondsSinceEpoch;
    notifyListeners();
    try {
      final songs =
          initialSongs ?? await NeteaseRecommendService().fetchPersonalFm();
      if (mine != generation || identity != scope || !active) return;
      if (replace &&
          (PlayerService().requestIdentity != originalIntent ||
              originalQueue.source != originalSource ||
              originalQueue.entryIdAt(originalQueue.queue.length - 1) !=
                  originalTail ||
              originalQueue.currentIndex != originalIndex)) {
        active = false;
        return;
      }
      final tracks = songs
          .where((s) => seen.add('${s['id']}'))
          .map(neteaseSongToTrack)
          .toList();
      if (tracks.isEmpty) {
        throw const NeteaseAccountException('FM_EMPTY', '暂时没有新的 FM 歌曲，请稍后换一批');
      }
      final queue = PlaylistQueueService();
      if (!replace &&
          (queue.source != QueueSource.neteaseFm ||
              queue.queue.isEmpty ||
              queue.entryIdAt(queue.queue.length - 1) != tailEntry)) {
        active = false;
        return;
      }

      if (replace) {
        await PlayerService().playCollection(
          tracks,
          source: QueueSource.neteaseFm,
        );
      } else {
        await queue.appendToQueue(
          tracks,
          expectedSource: QueueSource.neteaseFm,
          expectedTail: tailEntry,
        );
        if (mine != generation ||
            identity != scope ||
            queue.source != QueueSource.neteaseFm) {
          return;
        }
        final appendedTail = queue.entryIdAt(queue.queue.length - 1);
        while (queue.queue.length > 200 &&
            queue.currentIndex > 50 &&
            mine == generation &&
            identity == scope &&
            queue.source == QueueSource.neteaseFm &&
            queue.entryIdAt(queue.queue.length - 1) == appendedTail) {
          await queue.removeAt(0);
        }
      }
      if (mine != generation || identity != scope) return;
      if (queue.source != QueueSource.neteaseFm || queue.queue.isEmpty) {
        active = false;
        return;
      }
      tailEntry = queue.entryIdAt(queue.queue.length - 1);
      // Bound deduplication memory for long-running sessions.
      if (seen.length > 1000) {
        final keep = seen.skip(seen.length - 500).toList();
        seen
          ..clear()
          ..addAll(keep);
      }
      error = null;
    } catch (e) {
      if (mine == generation) {
        error = e.toString();
        if (replace ||
            e is NeteaseAccountException &&
                [
                  'NETEASE_LOGIN_EXPIRED',
                  'NETEASE_NOT_BOUND',
                  'BINDING_CHANGED',
                ].contains(e.code)) {
          active = false;
          unawaited(_refreshBinding());
        }
      }
    } finally {
      loading = false;
      notifyListeners();
    }
  }
}
