import 'package:flutter/material.dart';
import '../models/navidrome_models.dart';
import '../models/track.dart';
import '../services/navidrome_api.dart';
import '../services/navidrome_session_service.dart';
import '../services/player_service.dart';
import '../services/playlist_queue_service.dart';
import '../widgets/navidrome_ui.dart';
import 'navidrome_search_page.dart';
import 'navidrome_artists_page.dart';

/// Navidrome 音乐库页面
///
/// 支持 Chip 筛选导航：歌单/艺术家/专辑/电台/歌曲
class NavidromeLibraryPage extends StatefulWidget {
  final VoidCallback? onSearchTap;

  const NavidromeLibraryPage({
    super.key,
    this.onSearchTap,
  });

  @override
  State<NavidromeLibraryPage> createState() => _NavidromeLibraryPageState();
}

enum _LibraryTab { playlists, artists, albums, radio, songs }

class _NavidromeLibraryPageState extends State<NavidromeLibraryPage>
    with AutomaticKeepAliveClientMixin {
  _LibraryTab _currentTab = _LibraryTab.albums;
  bool _tabRestored = false;
  static const String _tabStorageKey = 'navidrome_library_tab';

  // 数据缓存
  List<NavidromePlaylist> _playlists = [];
  List<NavidromeArtist> _artists = [];
  List<NavidromeAlbum> _albums = [];
  List<NavidromeRadioStation> _radioStations = [];
  List<NavidromeSong> _songs = [];

  // 加载状态
  final Map<_LibraryTab, bool> _loading = {};
  final Map<_LibraryTab, String?> _errors = {};

  NavidromeApi? get _api => NavidromeSessionService().api;

  @override
  void initState() {
    super.initState();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_tabRestored) return;
    final storage = PageStorage.maybeOf(context);
    final storedIndex =
        storage?.readState(context, identifier: _tabStorageKey);
    if (storedIndex is int &&
        storedIndex >= 0 &&
        storedIndex < _LibraryTab.values.length) {
      _currentTab = _LibraryTab.values[storedIndex];
    }
    _tabRestored = true;
    _loadCurrentTab();
  }

  Future<void> _loadCurrentTab() async {
    switch (_currentTab) {
      case _LibraryTab.playlists:
        await _loadPlaylists();
        break;
      case _LibraryTab.artists:
        await _loadArtists();
        break;
      case _LibraryTab.albums:
        await _loadAlbums();
        break;
      case _LibraryTab.radio:
        await _loadRadioStations();
        break;
      case _LibraryTab.songs:
        await _loadSongs();
        break;
    }
  }

  Future<void> _loadPlaylists() async {
    if (_playlists.isNotEmpty) return;
    await _loadData(
      tab: _LibraryTab.playlists,
      loader: () async {
        final api = _api;
        if (api == null) throw Exception('未配置服务器');
        return api.getPlaylists();
      },
      onSuccess: (data) => _playlists = data,
    );
  }

  Future<void> _loadArtists() async {
    if (_artists.isNotEmpty) return;
    await _loadData(
      tab: _LibraryTab.artists,
      loader: () async {
        final api = _api;
        if (api == null) throw Exception('未配置服务器');
        return api.getArtists();
      },
      onSuccess: (data) => _artists = data,
    );
  }

  Future<void> _loadAlbums() async {
    if (_albums.isNotEmpty) return;
    await _loadData(
      tab: _LibraryTab.albums,
      loader: () async {
        final api = _api;
        if (api == null) throw Exception('未配置服务器');
        return api.getAlbumList();
      },
      onSuccess: (data) => _albums = data,
    );
  }

  Future<void> _loadRadioStations() async {
    if (_radioStations.isNotEmpty) return;
    await _loadData(
      tab: _LibraryTab.radio,
      loader: () async {
        final api = _api;
        if (api == null) throw Exception('未配置服务器');
        return api.getInternetRadioStations();
      },
      onSuccess: (data) => _radioStations = data,
    );
  }

  Future<void> _loadSongs() async {
    if (_songs.isNotEmpty) return;
    await _loadData(
      tab: _LibraryTab.songs,
      loader: () async {
        final api = _api;
        if (api == null) throw Exception('未配置服务器');
        return api.getRandomSongs(size: 100);
      },
      onSuccess: (data) => _songs = data,
    );
  }

  Future<void> _loadData<T>({
    required _LibraryTab tab,
    required Future<T> Function() loader,
    required void Function(T data) onSuccess,
  }) async {
    setState(() {
      _loading[tab] = true;
      _errors[tab] = null;
    });

    try {
      final data = await loader();
      if (!mounted) return;
      setState(() {
        onSuccess(data);
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _errors[tab] = '加载失败：$e';
      });
    } finally {
      if (mounted) {
        setState(() {
          _loading[tab] = false;
        });
      }
    }
  }

  Future<void> _refresh() async {
    // 清除当前 Tab 的缓存数据
    switch (_currentTab) {
      case _LibraryTab.playlists:
        _playlists = [];
        break;
      case _LibraryTab.artists:
        _artists = [];
        break;
      case _LibraryTab.albums:
        _albums = [];
        break;
      case _LibraryTab.radio:
        _radioStations = [];
        break;
      case _LibraryTab.songs:
        _songs = [];
        break;
    }
    await _loadCurrentTab();
  }

  void _switchTab(_LibraryTab tab) {
    if (_currentTab == tab) return;
    setState(() => _currentTab = tab);
    PageStorage.maybeOf(context)
        ?.writeState(context, _currentTab.index, identifier: _tabStorageKey);
    _loadCurrentTab();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final navTheme = NavidromeTheme.of(context);

    return Scaffold(
      backgroundColor: navTheme.background,
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final width = constraints.maxWidth;
            final padding = NavidromeLayout.pagePadding(width);

            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: EdgeInsets.fromLTRB(
                    padding.left,
                    8,
                    padding.right,
                    4,
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          '音乐库',
                          style: theme.textTheme.headlineLarge?.copyWith(
                            fontSize: 34,
                            fontWeight: FontWeight.w700,
                            color: navTheme.textPrimary,
                          ),
                        ),
                      ),
                      InkWell(
                        onTap: () {
                          if (widget.onSearchTap != null) {
                            widget.onSearchTap!();
                            return;
                          }
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => const NavidromeSearchPage(),
                            ),
                          );
                        },
                        borderRadius: BorderRadius.circular(22),
                        child: Container(
                          width: 44,
                          height: 44,
                          decoration: BoxDecoration(
                            color: navTheme.card,
                            shape: BoxShape.circle,
                            boxShadow: navTheme.cardShadow,
                          ),
                          child: const Icon(
                            Icons.search,
                            color: NavidromeColors.activeBlue,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  padding: EdgeInsets.fromLTRB(
                    padding.left,
                    8,
                    padding.right,
                    8,
                  ),
                  child: Row(
                    children: [
                      NavidromePill(
                        label: '歌单',
                        selected: _currentTab == _LibraryTab.playlists,
                        onTap: () => _switchTab(_LibraryTab.playlists),
                      ),
                      const SizedBox(width: 8),
                      NavidromePill(
                        label: '艺术家',
                        selected: _currentTab == _LibraryTab.artists,
                        onTap: () => _switchTab(_LibraryTab.artists),
                      ),
                      const SizedBox(width: 8),
                      NavidromePill(
                        label: '专辑',
                        selected: _currentTab == _LibraryTab.albums,
                        onTap: () => _switchTab(_LibraryTab.albums),
                      ),
                      const SizedBox(width: 8),
                      NavidromePill(
                        label: '电台',
                        selected: _currentTab == _LibraryTab.radio,
                        onTap: () => _switchTab(_LibraryTab.radio),
                      ),
                      const SizedBox(width: 8),
                      NavidromePill(
                        label: '歌曲',
                        selected: _currentTab == _LibraryTab.songs,
                        onTap: () => _switchTab(_LibraryTab.songs),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: _buildContent(theme, colorScheme, width),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _buildContent(
    ThemeData theme,
    ColorScheme colorScheme,
    double width,
  ) {
    final isLoading = _loading[_currentTab] ?? false;
    final error = _errors[_currentTab];

    if (isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (error != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.error_outline, size: 48, color: colorScheme.error),
            const SizedBox(height: 16),
            Text(error, style: TextStyle(color: colorScheme.error)),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: _refresh,
              icon: const Icon(Icons.refresh),
              label: const Text('重试'),
            ),
          ],
        ),
      );
    }

    switch (_currentTab) {
      case _LibraryTab.playlists:
        return _buildPlaylistsView(theme, colorScheme, width);
      case _LibraryTab.artists:
        return _buildArtistsView(theme, colorScheme, width);
      case _LibraryTab.albums:
        return _buildAlbumsView(theme, colorScheme, width);
      case _LibraryTab.radio:
        return _buildRadioView(theme, colorScheme, width);
      case _LibraryTab.songs:
        return _buildSongsView(theme, colorScheme, width);
    }
  }

  Widget _buildPlaylistsView(
    ThemeData theme,
    ColorScheme colorScheme,
    double width,
  ) {
    if (_playlists.isEmpty) {
      return _buildEmptyState('暂无歌单', Icons.queue_music);
    }

    final navTheme = NavidromeTheme.of(context);
    final padding = NavidromeLayout.pagePadding(width);
    final bottomPadding = 24 + MediaQuery.of(context).padding.bottom;

    return RefreshIndicator(
      onRefresh: _refresh,
      child: ListView.separated(
        padding: EdgeInsets.fromLTRB(
          padding.left,
          8,
          padding.right,
          bottomPadding,
        ),
        itemCount: _playlists.length,
        separatorBuilder: (_, __) => const SizedBox(height: 10),
        itemBuilder: (context, index) {
          final playlist = _playlists[index];
          final coverUrl = _api?.buildCoverUrl(playlist.coverArt) ?? '';

          return NavidromeCard(
            onTap: () => _navigateToPlaylist(playlist),
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                _CoverImage(
                  coverUrl: coverUrl,
                  size: 52,
                  icon: Icons.queue_music,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        playlist.name,
                        style: theme.textTheme.bodyLarge?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '${playlist.songCount} 首歌曲',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: navTheme.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(Icons.chevron_right, color: navTheme.textSecondary),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildArtistsView(
    ThemeData theme,
    ColorScheme colorScheme,
    double width,
  ) {
    if (_artists.isEmpty) {
      return _buildEmptyState('暂无艺术家', Icons.person);
    }

    final navTheme = NavidromeTheme.of(context);
    final padding = NavidromeLayout.pagePadding(width);
    final bottomPadding = 24 + MediaQuery.of(context).padding.bottom;

    return RefreshIndicator(
      onRefresh: _refresh,
      child: ListView.separated(
        padding: EdgeInsets.fromLTRB(
          padding.left,
          8,
          padding.right,
          bottomPadding,
        ),
        itemCount: _artists.length,
        separatorBuilder: (_, __) => const SizedBox(height: 10),
        itemBuilder: (context, index) {
          final artist = _artists[index];
          final coverUrl = artist.coverArt != null
              ? _api?.buildCoverUrl(artist.coverArt!, size: 100) ?? ''
              : '';

          return NavidromeCard(
            onTap: () => _navigateToArtist(artist),
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 26,
                  backgroundColor: colorScheme.primaryContainer,
                  backgroundImage:
                      coverUrl.isNotEmpty ? NetworkImage(coverUrl) : null,
                  child: coverUrl.isEmpty
                      ? Icon(Icons.person, color: colorScheme.onPrimaryContainer)
                      : null,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        artist.name,
                        style: theme.textTheme.bodyLarge?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '${artist.albumCount} 张专辑',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: navTheme.textSecondary,
                  ),
                      ),
                    ],
                  ),
                ),
                Icon(Icons.chevron_right, color: navTheme.textSecondary),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildAlbumsView(
    ThemeData theme,
    ColorScheme colorScheme,
    double width,
  ) {
    if (_albums.isEmpty) {
      return _buildEmptyState('暂无专辑', Icons.album);
    }

    final padding = NavidromeLayout.pagePadding(width);
    final bottomPadding = 24 + MediaQuery.of(context).padding.bottom;

    return RefreshIndicator(
      onRefresh: _refresh,
      child: GridView.builder(
        padding: EdgeInsets.fromLTRB(
          padding.left,
          8,
          padding.right,
          bottomPadding,
        ),
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: NavidromeLayout.gridColumns(width),
          mainAxisSpacing: 12,
          crossAxisSpacing: 12,
          childAspectRatio: NavidromeLayout.gridAspectRatio(width),
        ),
        itemCount: _albums.length,
        itemBuilder: (context, index) {
          final album = _albums[index];
          return _AlbumGridItem(
            album: album,
            api: _api,
            onTap: () => _navigateToAlbum(album),
            onQuickPlay: () => _playAlbumQuick(album),
            onLongPress: () => _showAlbumActions(album),
          );
        },
      ),
    );
  }

  Widget _buildRadioView(
    ThemeData theme,
    ColorScheme colorScheme,
    double width,
  ) {
    if (_radioStations.isEmpty) {
      return _buildEmptyState('暂无电台\n请在 Navidrome 中添加网络电台', Icons.radio);
    }

    final navTheme = NavidromeTheme.of(context);
    final padding = NavidromeLayout.pagePadding(width);
    final bottomPadding = 24 + MediaQuery.of(context).padding.bottom;

    return RefreshIndicator(
      onRefresh: _refresh,
      child: ListView.separated(
        padding: EdgeInsets.fromLTRB(
          padding.left,
          8,
          padding.right,
          bottomPadding,
        ),
        itemCount: _radioStations.length,
        separatorBuilder: (_, __) => const SizedBox(height: 10),
        itemBuilder: (context, index) {
          final station = _radioStations[index];

          return NavidromeCard(
            onTap: () => _playRadioStation(station),
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                Container(
                  width: 52,
                  height: 52,
                  decoration: BoxDecoration(
                    color: colorScheme.primaryContainer,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(Icons.radio, color: colorScheme.onPrimaryContainer),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        station.name,
                        style: theme.textTheme.bodyLarge?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      if (station.homePageUrl != null) ...[
                        const SizedBox(height: 4),
                        Text(
                          station.homePageUrl!,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: navTheme.textSecondary,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                IconButton.filledTonal(
                  onPressed: () => _playRadioStation(station),
                  icon: const Icon(Icons.play_arrow),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildSongsView(
    ThemeData theme,
    ColorScheme colorScheme,
    double width,
  ) {
    if (_songs.isEmpty) {
      return _buildEmptyState('暂无歌曲', Icons.music_note);
    }

    final padding = NavidromeLayout.pagePadding(width);
    final bottomPadding = 24 + MediaQuery.of(context).padding.bottom;

    return RefreshIndicator(
      onRefresh: _refresh,
      child: NavidromeSongList(
        songs: _songs,
        api: _api,
        padding: EdgeInsets.fromLTRB(
          padding.left,
          8,
          padding.right,
          bottomPadding,
        ),
        onTap: _playSong,
      ),
    );
  }

  Widget _buildEmptyState(String message, IconData icon) {
    final theme = Theme.of(context);
    final navTheme = NavidromeTheme.of(context);

    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 64, color: navTheme.textSecondary),
          const SizedBox(height: 16),
          Text(
            message,
            style: theme.textTheme.bodyLarge?.copyWith(
              color: navTheme.textSecondary,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  @override
  bool get wantKeepAlive => true;

  void _navigateToPlaylist(NavidromePlaylist playlist) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => _PlaylistDetailPage(playlist: playlist),
      ),
    );
  }

  void _navigateToArtist(NavidromeArtist artist) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => NavidromeArtistDetailPage(artist: artist),
      ),
    );
  }

  void _navigateToAlbum(NavidromeAlbum album) {
    showNavidromeAlbumSheet(
      context: context,
      album: album,
      api: _api,
    );
  }

  void _playRadioStation(NavidromeRadioStation station) {
    final track = Track(
      id: 'radio_${station.id}',
      name: station.name,
      artists: '网络电台',
      album: '',
      picUrl: '',
      source: MusicSource.navidrome,
    );
    PlayerService().playRadioStream(station.streamUrl, track);
  }

  void _playSong(int index) {
    if (_songs.isEmpty) return;
    final api = _api;
    if (api == null) return;

    final tracks = _songs
        .map(
          (song) => Track(
            id: song.id,
            name: song.title,
            artists: song.artist,
            album: song.album,
            picUrl: api.buildCoverUrl(song.coverArt),
            source: MusicSource.navidrome,
          ),
        )
        .toList();

    PlaylistQueueService().setQueue(tracks, index, QueueSource.search);
    PlayerService().playTrack(tracks[index]);
  }

  Future<List<Track>> _buildAlbumTracks(NavidromeAlbum album) async {
    final api = _api;
    if (api == null) return [];
    try {
      final songs = await api.getAlbumSongs(album.id);
      return songs
          .map(
            (song) => Track(
              id: song.id,
              name: song.title,
              artists: song.artist,
              album: song.album,
              picUrl: api.buildCoverUrl(song.coverArt),
              source: MusicSource.navidrome,
            ),
          )
          .toList();
    } catch (_) {
      return [];
    }
  }

  Future<void> _playAlbumQuick(NavidromeAlbum album) async {
    final tracks = await _buildAlbumTracks(album);
    if (tracks.isEmpty) return;
    PlaylistQueueService().setQueue(tracks, 0, QueueSource.album);
    PlayerService().playTrack(tracks[0]);
  }

  Future<void> _addAlbumToQueue(NavidromeAlbum album) async {
    final tracks = await _buildAlbumTracks(album);
    if (tracks.isEmpty) return;
    PlaylistQueueService().appendToQueue(tracks);
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('已加入播放队列')),
      );
    }
  }

  Future<void> _toggleAlbumStar(NavidromeAlbum album) async {
    final api = _api;
    if (api == null) return;

    try {
      if (album.starred) {
        await api.unstar(albumId: album.id);
      } else {
        await api.star(albumId: album.id);
      }

      if (!mounted) return;
      setState(() {
        final index = _albums.indexWhere((a) => a.id == album.id);
        if (index != -1) {
          final current = _albums[index];
          _albums[index] = NavidromeAlbum(
            id: current.id,
            name: current.name,
            artist: current.artist,
            artistId: current.artistId,
            coverArt: current.coverArt,
            songCount: current.songCount,
            year: current.year,
            genre: current.genre,
            duration: current.duration,
            starred: !current.starred,
          );
        }
      });
    } catch (_) {
      // ignore toggle failures
    }
  }

  void _showAlbumActions(NavidromeAlbum album) {
    final navTheme = NavidromeTheme.of(context);

    showModalBottomSheet(
      context: context,
      backgroundColor: navTheme.background,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.play_arrow),
                title: const Text('播放专辑'),
                onTap: () {
                  Navigator.pop(context);
                  _playAlbumQuick(album);
                },
              ),
              ListTile(
                leading: const Icon(Icons.queue_music),
                title: const Text('加入队列'),
                onTap: () {
                  Navigator.pop(context);
                  _addAlbumToQueue(album);
                },
              ),
              ListTile(
                leading: Icon(album.starred ? Icons.star : Icons.star_border),
                title: Text(album.starred ? '取消收藏' : '收藏专辑'),
                onTap: () {
                  Navigator.pop(context);
                  _toggleAlbumStar(album);
                },
              ),
              const SizedBox(height: 8),
            ],
          ),
        );
      },
    );
  }
}

class _CoverImage extends StatelessWidget {
  final String coverUrl;
  final double size;
  final IconData icon;

  const _CoverImage({
    required this.coverUrl,
    required this.size,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    if (coverUrl.isEmpty) {
      return Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Icon(icon, size: size * 0.5, color: colorScheme.onSurfaceVariant),
      );
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: Image.network(
        coverUrl,
        width: size,
        height: size,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => Container(
          width: size,
          height: size,
          color: colorScheme.surfaceContainerHighest,
          child: Icon(icon, size: size * 0.5, color: colorScheme.onSurfaceVariant),
        ),
      ),
    );
  }
}

class _AlbumGridItem extends StatelessWidget {
  final NavidromeAlbum album;
  final NavidromeApi? api;
  final VoidCallback onTap;
  final VoidCallback? onQuickPlay;
  final VoidCallback? onLongPress;

  const _AlbumGridItem({
    required this.album,
    required this.api,
    required this.onTap,
    this.onQuickPlay,
    this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    final coverUrl = api?.buildCoverUrl(album.coverArt) ?? '';
    final navTheme = NavidromeTheme.of(context);

    return GestureDetector(
      onLongPress: onLongPress,
      child: Stack(
        children: [
          Positioned.fill(
            child: NavidromeAlbumCard(
              coverUrl: coverUrl,
              title: album.name,
              subtitle: album.artist,
              onTap: onTap,
              showColorBackground: true,
            ),
          ),
          if (onQuickPlay != null)
            Positioned(
              right: 6,
              top: 6,
              child: InkWell(
                onTap: onQuickPlay,
                borderRadius: BorderRadius.circular(18),
                child: Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: NavidromeColors.activeBlue,
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: navTheme.cardShadow,
                  ),
                  child: const Icon(
                    Icons.play_arrow,
                    size: 18,
                    color: Colors.white,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

// ==================== 详情页 ====================

/// 专辑详情页
class NavidromeAlbumPage extends StatefulWidget {
  final NavidromeAlbum album;

  const NavidromeAlbumPage({super.key, required this.album});

  @override
  State<NavidromeAlbumPage> createState() => _NavidromeAlbumPageState();
}

class _NavidromeAlbumPageState extends State<NavidromeAlbumPage> {
  List<NavidromeSong> _songs = [];
  bool _loading = true;
  String? _error;

  NavidromeApi? get _api => NavidromeSessionService().api;

  @override
  void initState() {
    super.initState();
    _loadSongs();
  }

  Future<void> _loadSongs() async {
    final api = _api;
    if (api == null) {
      setState(() {
        _loading = false;
        _error = '未配置服务器';
      });
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final songs = await api.getAlbumSongs(widget.album.id);
      if (!mounted) return;
      setState(() => _songs = songs);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = '加载失败：$e');
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  void _playSongs(int index) {
    if (_songs.isEmpty) return;
    final api = _api;
    if (api == null) return;

    final tracks = _songs
        .map(
          (song) => Track(
            id: song.id,
            name: song.title,
            artists: song.artist,
            album: song.album,
            picUrl: api.buildCoverUrl(song.coverArt),
            source: MusicSource.navidrome,
          ),
        )
        .toList();

    PlaylistQueueService().setQueue(tracks, index, QueueSource.album);
    PlayerService().playTrack(tracks[index]);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final navTheme = NavidromeTheme.of(context);
    final coverUrl = _api?.buildCoverUrl(widget.album.coverArt) ?? '';

    return Scaffold(
      backgroundColor: navTheme.background,
      appBar: AppBar(
        title: Text(widget.album.name),
        backgroundColor: navTheme.background,
        foregroundColor: navTheme.textPrimary,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Text(_error!))
              : LayoutBuilder(
                  builder: (context, constraints) {
                    final width = constraints.maxWidth;
                    final padding = NavidromeLayout.pagePadding(width);
                    final coverSize =
                        width < NavidromeLayout.compactWidth ? 160.0 : 200.0;
                    final bottomPadding =
                        24 + MediaQuery.of(context).padding.bottom;

                    return CustomScrollView(
                      slivers: [
                        SliverToBoxAdapter(
                          child: Container(
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                colors: [
                                  navTheme.isDark
                                      ? colorScheme.primaryContainer.withOpacity(0.45)
                                      : NavidromeColors.lightBackground,
                                  navTheme.isDark
                                      ? colorScheme.surface
                                      : NavidromeColors.lightCardBackground,
                                ],
                                begin: Alignment.topCenter,
                                end: Alignment.bottomCenter,
                              ),
                            ),
                            child: Padding(
                              padding: EdgeInsets.fromLTRB(
                                padding.left,
                                20,
                                padding.right,
                                20,
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.center,
                                children: [
                                  ClipRRect(
                                    borderRadius: BorderRadius.circular(16),
                                    child: _CoverImage(
                                      coverUrl: coverUrl,
                                      size: coverSize,
                                      icon: Icons.album,
                                    ),
                                  ),
                                  const SizedBox(height: 16),
                                  Text(
                                    widget.album.name,
                                    style: theme.textTheme.headlineSmall?.copyWith(
                                      fontWeight: FontWeight.w700,
                                    ),
                                    textAlign: TextAlign.center,
                                  ),
                                  const SizedBox(height: 6),
                                  Text(
                                    widget.album.artist,
                                    style: theme.textTheme.bodyMedium?.copyWith(
                                      color: NavidromeColors.activeBlue,
                                      fontWeight: FontWeight.w600,
                                    ),
                                    textAlign: TextAlign.center,
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    '${widget.album.songCount} 首歌曲${widget.album.year != null ? ' · ${widget.album.year}' : ''}',
                                    style: theme.textTheme.bodySmall?.copyWith(
                                      color: navTheme.textSecondary,
                                    ),
                                    textAlign: TextAlign.center,
                                  ),
                                  const SizedBox(height: 16),
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      FilledButton.icon(
                                        onPressed: _songs.isNotEmpty
                                            ? () => _playSongs(0)
                                            : null,
                                        icon: const Icon(Icons.play_arrow),
                                        label: const Text('播放'),
                                        style: FilledButton.styleFrom(
                                          shape: const StadiumBorder(),
                                        ),
                                      ),
                                      const SizedBox(width: 12),
                                      FilledButton.tonalIcon(
                                        onPressed: _songs.isNotEmpty
                                            ? () => _playShuffled()
                                            : null,
                                        icon: const Icon(Icons.shuffle),
                                        label: const Text('随机'),
                                        style: FilledButton.styleFrom(
                                          shape: const StadiumBorder(),
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                        SliverToBoxAdapter(
                          child: NavidromeSectionHeader(
                            title: '歌曲',
                            padding: EdgeInsets.fromLTRB(
                              padding.left,
                              8,
                              padding.right,
                              4,
                            ),
                          ),
                        ),
                        SliverPadding(
                          padding: EdgeInsets.fromLTRB(
                            padding.left,
                            0,
                            padding.right,
                            bottomPadding,
                          ),
                          sliver: SliverList(
                            delegate: SliverChildBuilderDelegate(
                              (context, index) {
                                final song = _songs[index];

                                // 监听播放状态
                                return AnimatedBuilder(
                                  animation: PlayerService(),
                                  builder: (context, _) {
                                    final currentTrack = PlayerService().currentTrack;
                                    final isPlaying = currentTrack?.id == song.id;

                                    return Padding(
                                      padding: const EdgeInsets.only(bottom: 10),
                                      child: NavidromeSongTile(
                                        title: song.title,
                                        subtitle: '${song.artist} · ${song.album}',
                                        coverUrl:
                                            _api?.buildCoverUrl(song.coverArt) ?? '',
                                        duration: song.durationFormatted,
                                        isPlaying: isPlaying,
                                        onTap: () => _playSongs(index),
                                      ),
                                    );
                                  },
                                );
                              },
                              childCount: _songs.length,
                            ),
                          ),
                        ),
                      ],
                    );
                  },
                ),
    );
  }

  void _playShuffled() {
    if (_songs.isEmpty) return;
    final api = _api;
    if (api == null) return;

    final tracks = _songs
        .map(
          (song) => Track(
            id: song.id,
            name: song.title,
            artists: song.artist,
            album: song.album,
            picUrl: api.buildCoverUrl(song.coverArt),
            source: MusicSource.navidrome,
          ),
        )
        .toList();

    tracks.shuffle();
    PlaylistQueueService().setQueue(tracks, 0, QueueSource.album);
    PlayerService().playTrack(tracks[0]);
  }
}

/// 歌单详情页
class _PlaylistDetailPage extends StatefulWidget {
  final NavidromePlaylist playlist;

  const _PlaylistDetailPage({required this.playlist});

  @override
  State<_PlaylistDetailPage> createState() => _PlaylistDetailPageState();
}

class _PlaylistDetailPageState extends State<_PlaylistDetailPage> {
  List<NavidromeSong> _songs = [];
  bool _loading = true;
  String? _error;

  NavidromeApi? get _api => NavidromeSessionService().api;

  @override
  void initState() {
    super.initState();
    _loadSongs();
  }

  Future<void> _loadSongs() async {
    final api = _api;
    if (api == null) {
      setState(() {
        _loading = false;
        _error = '未配置服务器';
      });
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final songs = await api.getPlaylistSongs(widget.playlist.id);
      if (!mounted) return;
      setState(() => _songs = songs);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = '加载失败：$e');
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  void _playSongs(int index) {
    if (_songs.isEmpty) return;
    final api = _api;
    if (api == null) return;

    final tracks = _songs
        .map(
          (song) => Track(
            id: song.id,
            name: song.title,
            artists: song.artist,
            album: song.album,
            picUrl: api.buildCoverUrl(song.coverArt),
            source: MusicSource.navidrome,
          ),
        )
        .toList();

    PlaylistQueueService().setQueue(tracks, index, QueueSource.playlist);
    PlayerService().playTrack(tracks[index]);
  }

  @override
  Widget build(BuildContext context) {
    final navTheme = NavidromeTheme.of(context);
    final bottomPadding = 24 + MediaQuery.of(context).padding.bottom;

    return Scaffold(
      backgroundColor: navTheme.background,
      appBar: AppBar(
        title: Text(widget.playlist.name),
        backgroundColor: navTheme.background,
        foregroundColor: navTheme.textPrimary,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Text(_error!))
              : NavidromeSongList(
                  songs: _songs,
                  api: _api,
                  padding: EdgeInsets.fromLTRB(16, 8, 16, bottomPadding),
                  onTap: _playSongs,
                ),
    );
  }
}
