import 'package:cyrene_music/models/search_tab.dart';
import 'package:cyrene_music/models/track.dart';
import 'package:cyrene_music/services/search_provider_catalog.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('headers and content use the supported catalog in the same order', () {
    final tabs = SearchTab.tabs();
    expect(tabs.map((tab) => tab.key), ['netease', 'qq', 'kugou', 'artists']);
    expect(tabs.map((tab) => tab.label), ['网易云', 'QQ音乐', '酷狗', '歌手']);
    expect(
      tabs.where((tab) => tab.platform != null).map((tab) => tab.platform),
      SearchProviderCatalog.defaultPlatforms,
    );
  });

  test('all platform selections keep matching content identity', () {
    for (
      var index = 0;
      index < SearchProviderCatalog.defaultPlatforms.length;
      index++
    ) {
      final selection = SearchTabSelection()..select(index);
      expect(
        selection.active().platform,
        SearchProviderCatalog.defaultPlatforms[index],
      );
      expect(selection.index(), index);
    }
  });

  test('artist selection and returning to a platform route correctly', () {
    final selection = SearchTabSelection()..select(1);
    selection.select(3);
    expect(selection.active().kind, SearchTabKind.artists);
    expect(selection.index(), 3);
    selection.select(1);
    expect(selection.active().platform, MusicSource.qq);
  });

  test('invalid indices leave selection unchanged', () {
    final selection = SearchTabSelection()..select(2);
    selection.select(-1);
    selection.select(5);
    expect(selection.active().platform, MusicSource.kugou);
  });
}
