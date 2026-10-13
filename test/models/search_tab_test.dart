import 'package:cyrene_music/models/search_tab.dart';
import 'package:cyrene_music/models/track.dart';
import 'package:cyrene_music/services/search_provider_catalog.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('headers and content use the supported catalog in the same order', () {
    final tabs = SearchTab.tabs(merged: false);
    expect(tabs.map((tab) => tab.key), [
      'netease',
      'qq',
      'kugou',
      'kuwo',
      'artists',
    ]);
    expect(tabs.map((tab) => tab.label), ['网易云', 'QQ音乐', '酷狗', '酷我', '歌手']);
    expect(
      tabs.where((tab) => tab.platform != null).map((tab) => tab.platform),
      SearchProviderCatalog.defaultPlatforms,
    );
  });

  test('all platform selections restore their identity after merging', () {
    for (
      var index = 0;
      index < SearchProviderCatalog.defaultPlatforms.length;
      index++
    ) {
      final selection = SearchTabSelection()..select(index, merged: false);
      expect(
        selection.active(merged: false).platform,
        SearchProviderCatalog.defaultPlatforms[index],
      );
      expect(selection.index(merged: true), 0);
      expect(selection.active(merged: true).kind, SearchTabKind.songs);
      selection.select(0, merged: true);
      expect(selection.index(merged: false), index);
    }
  });

  test('artist identity survives both modes and returning to songs', () {
    final selection = SearchTabSelection()..select(1, merged: false);
    selection.select(4, merged: false);
    expect(selection.index(merged: true), 1);
    expect(selection.active(merged: true).kind, SearchTabKind.artists);
    expect(selection.index(merged: false), 4);
    selection.select(0, merged: true);
    expect(selection.active(merged: false).platform, MusicSource.qq);
  });

  test('invalid indices leave selection unchanged', () {
    final selection = SearchTabSelection()..select(2, merged: false);
    selection.select(-1, merged: false);
    selection.select(5, merged: false);
    selection.select(2, merged: true);
    expect(selection.active(merged: false).platform, MusicSource.kugou);
  });
}
