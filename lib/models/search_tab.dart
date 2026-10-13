import 'track.dart';
import '../services/search_provider_catalog.dart';

enum SearchTabKind { platform, songs, artists }

/// Shared identity for tab headers, selected content and search routing.
class SearchTab {
  final SearchTabKind kind;
  final MusicSource? platform;

  const SearchTab.platform(MusicSource source)
    : kind = SearchTabKind.platform,
      platform = source;
  const SearchTab.songs() : kind = SearchTabKind.songs, platform = null;
  const SearchTab.artists() : kind = SearchTabKind.artists, platform = null;

  String get label => switch (kind) {
    SearchTabKind.songs => '歌曲',
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

  static List<SearchTab> tabs({required bool merged}) => merged
      ? const [SearchTab.songs(), SearchTab.artists()]
      : [
          ...SearchProviderCatalog.defaultPlatforms.map(SearchTab.platform),
          const SearchTab.artists(),
        ];
}

/// Page-local selection survives theme and merged-mode changes by identity.
class SearchTabSelection {
  MusicSource _lastPlatform = SearchProviderCatalog.defaultPlatforms.first;
  bool _artistsSelected = false;

  SearchTab active({required bool merged}) => _artistsSelected
      ? const SearchTab.artists()
      : merged
      ? const SearchTab.songs()
      : SearchTab.platform(_lastPlatform);

  int index({required bool merged}) {
    final key = active(merged: merged).key;
    return SearchTab.tabs(merged: merged).indexWhere((tab) => tab.key == key);
  }

  void select(int index, {required bool merged}) {
    final tabs = SearchTab.tabs(merged: merged);
    if (index < 0 || index >= tabs.length) return;
    final tab = tabs[index];
    _artistsSelected = tab.kind == SearchTabKind.artists;
    if (tab.platform != null) _lastPlatform = tab.platform!;
  }
}
