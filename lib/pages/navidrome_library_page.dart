import 'package:flutter/material.dart';
import '../models/navidrome_models.dart';
import '../models/track.dart';
import '../services/navidrome_api.dart';
import '../services/navidrome_session_service.dart';
import '../services/player_service.dart';
import '../services/playlist_queue_service.dart';
import '../widgets/navidrome_ui.dart';

/// Navidrome 音乐库页面
///
/// 支持 Chip 筛选导航：歌单/艺术家/专辑/电台/歌曲
class NavidromeLibraryPage extends StatefulWidget {
  const NavidromeLibraryPage({super.key});

  @override
  State<NavidromeLibraryPage> createState() => _NavidromeLibraryPageState();
}

enum _LibraryTab { playlists, artists, albums, radio, songs }

class _NavidromeLibraryPageState extends State<NavidromeLibraryPage> {
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
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return SafeArea(
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
                  12,
                  padding.right,
                  4,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '音乐库',
                      style: theme.textTheme.headlineMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Navidrome',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colorScheme.outline,
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
                      icon: Icons.queue_music,
                      selected: _currentTab == _LibraryTab.playlists,
                      onTap: () => _switchTab(_LibraryTab.playlists),
                    ),
                    const SizedBox(width: 8),
                    NavidromePill(
                      label: '艺术家',
                      icon: Icons.person,
                      selected: _currentTab == _LibraryTab.artists,
                      onTap: () => _switchTab(_LibraryTab.artists),
                    ),
                    const SizedBox(width: 8),
                    NavidromePill(
                      label: '专辑',
                      icon: Icons.album,
                      selected: _currentTab == _LibraryTab.albums,
                      onTap: () => _switchTab(_LibraryTab.albums),
                    ),
                    const SizedBox(width: 8),
                    NavidromePill(
                      label: '电台',
                      icon: Icons.radio,
                      selected: _currentTab == _LibraryTab.radio,
                      onTap: () => _switchTab(_LibraryTab.radio),
                    ),
                    const SizedBox(width: 8),
                    NavidromePill(
                      label: '歌曲',
                      icon: Icons.music_note,
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
                          color: colorScheme.outline,
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(Icons.chevron_right, color: colorScheme.outline),
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
                          color: colorScheme.outline,
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(Icons.chevron_right, color: colorScheme.outline),
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
                            color: colorScheme.outline,
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
      child: ListView.separated(
        padding: EdgeInsets.fromLTRB(
          padding.left,
          8,
          padding.right,
          bottomPadding,
        ),
        itemCount: _songs.length,
        separatorBuilder: (_, __) => const SizedBox(height: 10),
        itemBuilder: (context, index) {
          final song = _songs[index];
          final coverUrl = _api?.buildCoverUrl(song.coverArt) ?? '';

          return NavidromeCard(
            onTap: () => _playSong(index),
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                _CoverImage(
                  coverUrl: coverUrl,
                  size: 52,
                  icon: Icons.music_note,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        song.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodyLarge?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '${song.artist} · ${song.album}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: colorScheme.outline,
                        ),
                      ),
                    ],
                  ),
                ),
                Text(
                  song.durationFormatted,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colorScheme.outline,
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildEmptyState(String message, IconData icon) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 64, color: colorScheme.outline),
          const SizedBox(height: 16),
          Text(
            message,
            style: theme.textTheme.bodyLarge?.copyWith(
              color: colorScheme.outline,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

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
        builder: (_) => _ArtistDetailPage(artist: artist),
      ),
    );
  }

  void _navigateToAlbum(NavidromeAlbum album) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => NavidromeAlbumPage(album: album),
      ),
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

  const _AlbumGridItem({
    required this.album,
    required this.api,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final coverUrl = api?.buildCoverUrl(album.coverArt) ?? '';

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: coverUrl.isNotEmpty
                  ? Image.network(
                      coverUrl,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => Container(
                        color: colorScheme.surfaceContainerHighest,
                        child: Icon(
                          Icons.album,
                          size: 48,
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                    )
                  : Container(
                      color: colorScheme.surfaceContainerHighest,
                      child: Icon(
                        Icons.album,
                        size: 48,
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            album.name,
            style: theme.textTheme.bodyMedium?.copyWith(
              fontWeight: FontWeight.w500,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          Text(
            album.artist,
            style: theme.textTheme.bodySmall?.copyWith(
              color: colorScheme.outline,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
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
    final coverUrl = _api?.buildCoverUrl(widget.album.coverArt) ?? '';

    return Scaffold(
      appBar: AppBar(title: Text(widget.album.name)),
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
                                  colorScheme.primaryContainer.withOpacity(0.45),
                                  colorScheme.surface,
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
                                      color: colorScheme.primary,
                                      fontWeight: FontWeight.w600,
                                    ),
                                    textAlign: TextAlign.center,
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    '${widget.album.songCount} 首歌曲${widget.album.year != null ? ' · ${widget.album.year}' : ''}',
                                    style: theme.textTheme.bodySmall?.copyWith(
                                      color: colorScheme.outline,
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
                                final isLast = index == _songs.length - 1;
                                return Column(
                                  children: [
                                    ListTile(
                                      contentPadding: const EdgeInsets.symmetric(
                                        horizontal: 4,
                                        vertical: 4,
                                      ),
                                      leading: SizedBox(
                                        width: 32,
                                        child: Text(
                                          '${song.track ?? index + 1}',
                                          style:
                                              theme.textTheme.bodyMedium?.copyWith(
                                            color: colorScheme.outline,
                                          ),
                                          textAlign: TextAlign.center,
                                        ),
                                      ),
                                      title: Text(
                                        song.title,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style:
                                            theme.textTheme.bodyLarge?.copyWith(
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                      trailing: Text(
                                        song.durationFormatted,
                                        style: theme.textTheme.bodySmall?.copyWith(
                                          color: colorScheme.outline,
                                        ),
                                      ),
                                      onTap: () => _playSongs(index),
                                    ),
                                    if (!isLast)
                                      Divider(
                                        height: 1,
                                        color: colorScheme.outlineVariant,
                                      ),
                                  ],
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
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Scaffold(
      appBar: AppBar(title: Text(widget.playlist.name)),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Text(_error!))
              : ListView.builder(
                  itemCount: _songs.length,
                  itemBuilder: (context, index) {
                    final song = _songs[index];
                    final coverUrl = _api?.buildCoverUrl(song.coverArt) ?? '';

                    return ListTile(
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 4,
                      ),
                      leading: _CoverImage(
                        coverUrl: coverUrl,
                        size: 48,
                        icon: Icons.music_note,
                      ),
                      title: Text(
                        song.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      subtitle: Text(
                        '${song.artist} · ${song.album}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      trailing: Text(
                        song.durationFormatted,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: colorScheme.outline,
                        ),
                      ),
                      onTap: () => _playSongs(index),
                    );
                  },
                ),
    );
  }
}

/// 艺术家详情页
class _ArtistDetailPage extends StatefulWidget {
  final NavidromeArtist artist;

  const _ArtistDetailPage({required this.artist});

  @override
  State<_ArtistDetailPage> createState() => _ArtistDetailPageState();
}

class _ArtistDetailPageState extends State<_ArtistDetailPage> {
  NavidromeArtistInfo? _artistInfo;
  bool _loading = true;
  String? _error;

  NavidromeApi? get _api => NavidromeSessionService().api;

  @override
  void initState() {
    super.initState();
    _loadArtistInfo();
  }

  Future<void> _loadArtistInfo() async {
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
      final info = await api.getArtist(widget.artist.id);
      if (!mounted) return;
      setState(() => _artistInfo = info);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = '加载失败：$e');
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final albums = _artistInfo?.albums ?? [];

    return Scaffold(
      appBar: AppBar(title: Text(widget.artist.name)),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Text(_error!))
              : albums.isEmpty
                  ? const Center(child: Text('暂无专辑'))
                  : GridView.builder(
                      padding: const EdgeInsets.all(16),
                      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 2,
                        mainAxisSpacing: 12,
                        crossAxisSpacing: 12,
                        childAspectRatio: 0.85,
                      ),
                      itemCount: albums.length,
                      itemBuilder: (context, index) {
                        final album = albums[index];
                        return _AlbumGridItem(
                          album: album,
                          api: _api,
                          onTap: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => NavidromeAlbumPage(album: album),
                              ),
                            );
                          },
                        );
                      },
                    ),
    );
  }
}
