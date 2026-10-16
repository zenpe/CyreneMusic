import 'track.dart';
import '../services/search_provider_catalog.dart';

enum SearchTabKind { platform, artists }

/// Shared identity for tab headers, selected content and search routing.
class SearchTab {
  final SearchTabKind kind;
  final MusicSource? platform;

  const SearchTab.platform(MusicSource source)
    : kind = SearchTabKind.platform,
      platform = source;
  const SearchTab.artists() : kind = SearchTabKind.artists, platform = null;

  String get label => switch (kind) {
    SearchTabKind.artists => '歌手',
    SearchTabKind.platform => switch (platform!) {
      MusicSource.netease => '网易云',
      MusicSource.qq => 'QQ音乐',
      MusicSource.kugou => '酷狗',
      MusicSource.kuwo => '酷我',
      _ => platform!.name,
    },
  };

  String get key => platform?.name ?? kind.name;

  static List<SearchTab> tabs() => [
    ...SearchProviderCatalog.defaultPlatforms.map(SearchTab.platform),
    const SearchTab.artists(),
  ];
}

/// Page-local selection keeps platform identity across theme changes.
class SearchTabSelection {
  MusicSource _lastPlatform = SearchProviderCatalog.defaultPlatforms.first;
  bool _artistsSelected = false;

  SearchTab active() => _artistsSelected
      ? const SearchTab.artists()
      : SearchTab.platform(_lastPlatform);

  int index() {
    final key = active().key;
    return SearchTab.tabs().indexWhere((tab) => tab.key == key);
  }

  void select(int index) {
    final tabs = SearchTab.tabs();
    if (index < 0 || index >= tabs.length) return;
    final tab = tabs[index];
    _artistsSelected = tab.kind == SearchTabKind.artists;
    if (tab.platform != null) _lastPlatform = tab.platform!;
  }
}
