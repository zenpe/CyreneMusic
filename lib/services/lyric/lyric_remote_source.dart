import 'package:dio/dio.dart';
import '../../models/track.dart';
import '../api/api_client.dart';
import '../navidrome_api.dart';
import '../navidrome_session_service.dart';
import 'lyric_fetch_result.dart';

class LyricRemoteSource {
  Future<LyricFetchResult> fetch(
    Track track,
    CancelToken cancel,
    Duration timeout,
    bool bypassCache,
  ) async {
    if (cancel.isCancelled) {
      return const LyricFetchResult(LyricFetchKind.cancelled);
    }
    if (track.source == MusicSource.navidrome) {
      final api = NavidromeSessionService().api;
      if (api == null) {
        return const LyricFetchResult(LyricFetchKind.unsupported);
      }
      try {
        final lyrics = await api.fetchLyrics(
          track.id.toString(),
          cancel.whenCancel.then((_) {}),
        );
        if (cancel.isCancelled) {
          return const LyricFetchResult(LyricFetchKind.cancelled);
        }
        if (lyrics == null || lyrics.isEmpty) {
          return const LyricFetchResult(LyricFetchKind.empty);
        }
        return LyricFetchResult(
          LyricFetchKind.ready,
          payload: LyricPayload(lyric: lyrics.lyric, tlyric: lyrics.tlyric),
        );
      } on NavidromeApiException catch (e) {
        if (cancel.isCancelled) {
          return const LyricFetchResult(LyricFetchKind.cancelled);
        }
        return LyricFetchResult(
          LyricFetchKind.unavailable,
          retryable:
              e.code == null && (e.statusCode == null || e.statusCode! >= 500),
        );
      }
    }
    String path;
    Map<String, dynamic> query;
    switch (track.source) {
      case MusicSource.qq:
      case MusicSource.netease:
        path = '/lyrics/${track.source.name}';
        query = {'id': track.id.toString()};
        break;
      case MusicSource.kugou:
        final id = track.sourceIds.emixSongId;
        if (id == null || id.isEmpty) {
          return const LyricFetchResult(LyricFetchKind.unsupported);
        }
        path = '/lyrics/kugou';
        query = {'emixsongid': id};
        break;
      default:
        return const LyricFetchResult(LyricFetchKind.unsupported);
    }
    final response = await ApiClient().getJson(
      path,
      queryParameters: query,
      timeout: timeout,
      cancelToken: cancel,
      // Dedupe and cancellation ownership belong to LyricRequestCoordinator.
      headers: bypassCache ? {'Cache-Control': 'no-cache'} : null,
    );
    if (cancel.isCancelled) {
      return const LyricFetchResult(LyricFetchKind.cancelled);
    }
    final data = response.bodyData;
    if (!response.ok) {
      final restricted = [401, 403, 429].contains(response.statusCode);
      return LyricFetchResult(
        LyricFetchKind.unavailable,
        retryable:
            !restricted &&
            (response.isNetworkError ||
                (data is Map && data['retryable'] == true)),
        retryAfter: response.statusCode == 429
            ? Duration(seconds: response.retryAfterSeconds ?? 30)
            : null,
      );
    }
    if (data is! Map) return const LyricFetchResult(LyricFetchKind.unavailable);
    final payload = LyricPayload.fromMap(data);
    if (payload.hasPrimary) {
      return LyricFetchResult(LyricFetchKind.ready, payload: payload);
    }
    if (data['state'] == 'empty') {
      return const LyricFetchResult(LyricFetchKind.empty);
    }
    if (data['state'] == 'unsupported') {
      return const LyricFetchResult(LyricFetchKind.unsupported);
    }
    // Legacy empty-success responses are ambiguous, never authoritative absence.
    return LyricFetchResult(
      LyricFetchKind.unavailable,
      retryable: data['retryable'] != false,
    );
  }
}
