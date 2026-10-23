import 'package:cyrene_music/models/track.dart';
import 'package:cyrene_music/services/search_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('suggestion notice belongs to QQ and survives other completions', () {
    var result = SearchResult(qqSuggestions: true);
    result = result.copyWith(neteaseLoading: false, neteaseResults: []);
    expect(result.noticeFor(MusicSource.qq), contains('联想结果'));
    expect(result.noticeFor(MusicSource.kugou), isNull);
    expect(
      result.copyWith(qqSuggestions: false).noticeFor(MusicSource.qq),
      isNull,
    );
    expect(SearchResult().noticeFor(MusicSource.qq), isNull);
  });

  test('platform identity selects matching results, loading and error', () {
    Track track(MusicSource source) => Track(
      id: source.name,
      name: source.name,
      artists: '',
      album: '',
      picUrl: '',
      source: source,
    );
    final result = SearchResult(
      neteaseResults: [track(MusicSource.netease)],
      qqResults: [track(MusicSource.qq)],
      kugouResults: [track(MusicSource.kugou)],
      kuwoResults: [track(MusicSource.kuwo)],
      qqLoading: true,
      kuwoError: 'offline',
    );
    for (final source in [
      MusicSource.netease,
      MusicSource.qq,
      MusicSource.kugou,
      MusicSource.kuwo,
    ]) {
      expect(result.resultsFor(source).single.source, source);
      expect(result.loadingFor(source), source == MusicSource.qq);
      expect(
        result.errorFor(source),
        source == MusicSource.kuwo ? 'offline' : null,
      );
    }
  });

  test(
    'other platform completions preserve errors in either arrival order',
    () {
      var result = SearchResult(qqLoading: true, neteaseLoading: true);
      result = result.copyWith(qqLoading: false, qqError: 'timeout');
      result = result.copyWith(neteaseLoading: false, neteaseResults: []);
      expect(result.qqError, 'timeout');
      expect(result.hasError, true);
      expect(result.allCompleted, true);

      result = SearchResult().copyWith(neteaseError: 'offline');
      result = result.copyWith(qqError: 'timeout');
      expect(result.errorFor(MusicSource.netease), 'offline');
      expect(result.errorFor(MusicSource.qq), 'timeout');
    },
  );

  test('explicit clearing affects only the requested platform', () {
    final result = SearchResult(
      qqError: 'timeout',
      kuwoError: 'offline',
    ).copyWith(qqError: null);
    expect(result.qqError, isNull);
    expect(result.kuwoError, 'offline');
    expect(SearchResult().hasError, false);
  });
}
