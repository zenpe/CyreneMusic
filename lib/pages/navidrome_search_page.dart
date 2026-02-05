import 'package:flutter/material.dart';
import '../models/navidrome_models.dart';
import '../models/track.dart';
import '../services/navidrome_api.dart';
import '../services/navidrome_session_service.dart';
import '../services/player_service.dart';
import '../services/playlist_queue_service.dart';
import 'navidrome_artists_page.dart';
import '../widgets/navidrome_ui.dart';

/// Navidrome 搜索页面
///
/// 支持 Tab 分类筛选：全部/艺术家/专辑/歌曲/电台
class NavidromeSearchPage extends StatefulWidget {
  const NavidromeSearchPage({super.key});

  @override
  State<NavidromeSearchPage> createState() => _NavidromeSearchPageState();
}

class _NavidromeSearchPageState extends State<NavidromeSearchPage>
    with SingleTickerProviderStateMixin, AutomaticKeepAliveClientMixin {
  final TextEditingController _controller = TextEditingController();
  final FocusNode _focusNode = FocusNode();
  late TabController _tabController;

  bool _isLoading = false;
  String? _error;
  NavidromeSearchResult? _result;
  List<NavidromeRadioStation> _radioStations = []; // 电台搜索结果

  NavidromeApi? get _api => NavidromeSessionService().api;

  static const _tabs = ['全部', '艺术家', '专辑', '歌曲', '电台'];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: _tabs.length, vsync: this);
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _search() async {
    final query = _controller.text.trim();
    if (query.isEmpty) return;

    final api = _api;
    if (api == null) {
      setState(() => _error = '未配置服务器');
      return;
    }

    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      // 并行搜索：常规搜索 + 电台搜索
      final results = await Future.wait([
        api.search3(
          query,
          artistCount: 50,
          albumCount: 50,
          songCount: 100,
        ),
        api.getInternetRadioStations(),
      ]);

      if (!mounted) return;

      final searchResult = results[0] as NavidromeSearchResult;
      final allRadios = results[1] as List<NavidromeRadioStation>;

      // 本地过滤电台（Subsonic API 不支持电台搜索）
      final queryLower = query.toLowerCase();
      final matchedRadios = allRadios.where((station) {
        return station.name.toLowerCase().contains(queryLower) ||
            (station.homePageUrl?.toLowerCase().contains(queryLower) ?? false);
      }).toList();

      setState(() {
        _result = searchResult;
        _radioStations = matchedRadios;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = '搜索失败：$e');
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  void _clearSearch() {
    _controller.clear();
    setState(() {
      _result = null;
      _radioStations = [];
      _error = null;
    });
    _focusNode.requestFocus();
  }

  void _playSongs(List<NavidromeSong> songs, int index) {
    if (songs.isEmpty) return;
    final api = _api;
    if (api == null) return;

    final tracks = songs
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

      if (!mounted || _result == null) return;
      final updatedAlbums = _result!.albums.map((a) {
        if (a.id != album.id) return a;
        return NavidromeAlbum(
          id: a.id,
          name: a.name,
          artist: a.artist,
          artistId: a.artistId,
          coverArt: a.coverArt,
          songCount: a.songCount,
          year: a.year,
          genre: a.genre,
          duration: a.duration,
          starred: !a.starred,
        );
      }).toList();

      setState(() {
        _result = NavidromeSearchResult(
          artists: _result!.artists,
          albums: updatedAlbums,
          songs: _result!.songs,
        );
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
                    12,
                    padding.right,
                    4,
                  ),
                  child: Text(
                    '搜索',
                    style: theme.textTheme.headlineMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: navTheme.textPrimary,
                    ),
                  ),
                ),
                Padding(
                  padding: EdgeInsets.fromLTRB(
                    padding.left,
                    8,
                    padding.right,
                    8,
                  ),
                  child: _buildSearchField(navTheme),
                ),
                if (_result != null && (!_result!.isEmpty || _radioStations.isNotEmpty))
                  _buildTabChips(colorScheme, width),
                Expanded(
                  child: _buildBody(theme, colorScheme),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _buildSearchField(NavidromeThemeData navTheme) {
    final borderRadius = BorderRadius.circular(14);
    final borderColor = navTheme.isDark ? NavidromeColors.cardBorder : navTheme.cardBorder;

    return TextField(
      controller: _controller,
      focusNode: _focusNode,
      textInputAction: TextInputAction.search,
      onSubmitted: (_) => _search(),
      decoration: InputDecoration(
        hintText: '搜索歌曲、专辑、艺术家',
        hintStyle: TextStyle(color: navTheme.textSecondary),
        prefixIcon: Icon(Icons.search, color: navTheme.textSecondary),
        suffixIcon: _controller.text.isNotEmpty
            ? IconButton(
                icon: const Icon(Icons.clear),
                onPressed: _clearSearch,
              )
            : null,
        border: OutlineInputBorder(
          borderRadius: borderRadius,
          borderSide: BorderSide(color: borderColor, width: 1),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: borderRadius,
          borderSide: BorderSide(color: borderColor, width: 1),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: borderRadius,
          borderSide: const BorderSide(color: NavidromeColors.activeBlue, width: 2),
        ),
        filled: true,
        fillColor: navTheme.card,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 12,
        ),
      ),
      onChanged: (_) => setState(() {}),
    );
  }

  Widget _buildTabChips(ColorScheme colorScheme, double width) {
    final padding = NavidromeLayout.pagePadding(width);

    return AnimatedBuilder(
      animation: _tabController,
      builder: (context, _) {
        return SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: EdgeInsets.fromLTRB(
            padding.left,
            0,
            padding.right,
            8,
          ),
          child: Row(
            children: List.generate(_tabs.length, (index) {
              final selected = _tabController.index == index;
              return Padding(
                padding: const EdgeInsets.only(right: 8),
                child: NavidromePill(
                  label: _tabs[index],
                  selected: selected,
                  onTap: () => _tabController.animateTo(index),
                ),
              );
            }),
          ),
        );
      },
    );
  }

  Widget _buildBody(ThemeData theme, ColorScheme colorScheme) {
    final navTheme = NavidromeTheme.of(context);

    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_error != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.error_outline, size: 48, color: colorScheme.error),
            const SizedBox(height: 16),
            Text(_error!, style: TextStyle(color: colorScheme.error)),
          ],
        ),
      );
    }

    if (_result == null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.search, size: 64, color: navTheme.textSecondary),
            const SizedBox(height: 16),
            Text(
              '输入关键词开始搜索',
              style: theme.textTheme.bodyLarge?.copyWith(
                color: navTheme.textSecondary,
              ),
            ),
          ],
        ),
      );
    }

    if (_result!.isEmpty && _radioStations.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.search_off, size: 64, color: navTheme.textSecondary),
            const SizedBox(height: 16),
            Text(
              '未找到相关结果',
              style: theme.textTheme.bodyLarge?.copyWith(
                color: navTheme.textSecondary,
              ),
            ),
          ],
        ),
      );
    }

    return TabBarView(
      controller: _tabController,
      children: [
        _buildAllTab(theme, colorScheme),
        _buildArtistsTab(theme, colorScheme),
        _buildAlbumsTab(theme, colorScheme),
        _buildSongsTab(theme, colorScheme),
        _buildRadioTab(theme, colorScheme),
      ],
    );
  }

  Widget _buildAllTab(ThemeData theme, ColorScheme colorScheme) {
    final artists = _result?.artists ?? [];
    final albums = _result?.albums ?? [];
    final songs = _result?.songs ?? [];
    final radios = _radioStations;
    final width = MediaQuery.of(context).size.width;
    final padding = NavidromeLayout.pagePadding(width);
    final bottomPadding = 24 + MediaQuery.of(context).padding.bottom;

    return AnimatedBuilder(
      animation: PlayerService(),
      builder: (context, _) {
        final currentTrack = PlayerService().currentTrack;

        return ListView(
          padding: EdgeInsets.fromLTRB(
            padding.left,
            4,
            padding.right,
            bottomPadding,
          ),
          children: [
            // 艺术家区域
            if (artists.isNotEmpty) ...[
              NavidromeSectionHeader(
                title: '艺术家',
                actionLabel: '查看全部',
                onAction: () => _tabController.animateTo(1),
                padding: EdgeInsets.fromLTRB(
                  padding.left,
                  8,
                  padding.right,
                  4,
                ),
              ),
              SizedBox(
                height: 100,
                child: ListView.builder(
                  scrollDirection: Axis.horizontal,
                  padding: EdgeInsets.symmetric(horizontal: padding.left),
                  itemCount: artists.take(10).length,
                  itemBuilder: (context, index) {
                    final artist = artists[index];
                    return _ArtistChip(
                      artist: artist,
                      api: _api,
                      onTap: () => _navigateToArtist(artist),
                    );
                  },
                ),
              ),
              const SizedBox(height: 16),
            ],
            // 专辑区域
            if (albums.isNotEmpty) ...[
              NavidromeSectionHeader(
                title: '专辑',
                actionLabel: '查看全部',
                onAction: () => _tabController.animateTo(2),
                padding: EdgeInsets.fromLTRB(
                  padding.left,
                  8,
                  padding.right,
                  4,
                ),
              ),
              SizedBox(
                height: 184,
                child: ListView.builder(
                  scrollDirection: Axis.horizontal,
                  padding: EdgeInsets.symmetric(horizontal: padding.left),
                  itemCount: albums.length > 10 ? 10 : albums.length,
                  itemBuilder: (context, index) {
                    final album = albums[index];
                    final coverUrl = _api?.buildCoverUrl(album.coverArt) ?? '';
                    return Padding(
                      padding: const EdgeInsets.only(right: 12),
                      child: NavidromeAlbumCard(
                        coverUrl: coverUrl,
                        title: album.name,
                        subtitle: album.artist,
                        width: 120,
                        height: 168,
                        showColorBackground: true,
                        onTap: () => _navigateToAlbum(album),
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(height: 16),
            ],
            // 歌曲区域
            if (songs.isNotEmpty) ...[
              NavidromeSectionHeader(
                title: '歌曲',
                actionLabel: '查看全部',
                onAction: () => _tabController.animateTo(3),
                padding: EdgeInsets.fromLTRB(
                  padding.left,
                  8,
                  padding.right,
                  4,
                ),
              ),
              ...songs.take(5).map((song) {
                final songIndex = songs.indexOf(song);
                final isPlaying = currentTrack?.id == song.id;
                final coverUrl = _api?.buildCoverUrl(song.coverArt) ?? '';

                return Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: NavidromeSongTile(
                    title: song.title,
                    subtitle: '${song.artist} · ${song.album}',
                    coverUrl: coverUrl,
                    duration: song.durationFormatted,
                    isPlaying: isPlaying,
                    onTap: () => _playSongs(songs, songIndex),
                  ),
                );
              }),
            ],
            // 电台区域
            if (radios.isNotEmpty) ...[
              NavidromeSectionHeader(
                title: '网络电台',
                actionLabel: '查看全部',
                onAction: () => _tabController.animateTo(4),
                padding: EdgeInsets.fromLTRB(
                  padding.left,
                  8,
                  padding.right,
                  4,
                ),
              ),
              ...radios.take(3).map((station) {
                return Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: _RadioStationTile(
                    station: station,
                    onTap: () => _playRadioStation(station),
                  ),
                );
              }),
            ],
          ],
        );
      },
    );
  }

  Widget _buildArtistsTab(ThemeData theme, ColorScheme colorScheme) {
    final artists = _result?.artists ?? [];
    if (artists.isEmpty) {
      return const Center(child: Text('没有找到艺术家'));
    }

    final navTheme = NavidromeTheme.of(context);
    final width = MediaQuery.of(context).size.width;
    final padding = NavidromeLayout.pagePadding(width);
    final bottomPadding = 24 + MediaQuery.of(context).padding.bottom;

    return ListView.separated(
      padding: EdgeInsets.fromLTRB(
        padding.left,
        8,
        padding.right,
        bottomPadding,
      ),
      itemCount: artists.length,
      separatorBuilder: (_, __) => const SizedBox(height: 10),
      itemBuilder: (context, index) {
        final artist = artists[index];
        final coverUrl = artist.coverArt != null && _api != null
            ? _api!.buildCoverUrl(artist.coverArt!, size: 100)
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
    );
  }

  Widget _buildAlbumsTab(ThemeData theme, ColorScheme colorScheme) {
    final albums = _result?.albums ?? [];
    if (albums.isEmpty) {
      return const Center(child: Text('没有找到专辑'));
    }

    final width = MediaQuery.of(context).size.width;
    final padding = NavidromeLayout.pagePadding(width);
    final bottomPadding = 24 + MediaQuery.of(context).padding.bottom;

    return GridView.builder(
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
      itemCount: albums.length,
      itemBuilder: (context, index) {
        final album = albums[index];
        final coverUrl = _api?.buildCoverUrl(album.coverArt) ?? '';

        final navTheme = NavidromeTheme.of(context);

        return GestureDetector(
          onLongPress: () => _showAlbumActions(album),
          child: Stack(
            children: [
              Positioned.fill(
                child: NavidromeAlbumCard(
                  coverUrl: coverUrl,
                  title: album.name,
                  subtitle: album.artist,
                  showColorBackground: true,
                  onTap: () => _navigateToAlbum(album),
                ),
              ),
              Positioned(
                right: 6,
                top: 6,
                child: InkWell(
                  onTap: () => _playAlbumQuick(album),
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
      },
    );
  }

  Widget _buildSongsTab(ThemeData theme, ColorScheme colorScheme) {
    final songs = _result?.songs ?? [];
    if (songs.isEmpty) {
      return const Center(child: Text('没有找到歌曲'));
    }

    final width = MediaQuery.of(context).size.width;
    final padding = NavidromeLayout.pagePadding(width);
    final bottomPadding = 24 + MediaQuery.of(context).padding.bottom;

    return NavidromeSongList(
      songs: songs,
      api: _api,
      padding: EdgeInsets.fromLTRB(
        padding.left,
        8,
        padding.right,
        bottomPadding,
      ),
      onTap: (index) => _playSongs(songs, index),
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

  Widget _buildRadioTab(ThemeData theme, ColorScheme colorScheme) {
    if (_radioStations.isEmpty) {
      return const Center(child: Text('没有找到电台'));
    }

    final navTheme = NavidromeTheme.of(context);
    final width = MediaQuery.of(context).size.width;
    final padding = NavidromeLayout.pagePadding(width);
    final bottomPadding = 24 + MediaQuery.of(context).padding.bottom;

    return ListView.separated(
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
        return _RadioStationTile(
          station: station,
          onTap: () => _playRadioStation(station),
        );
      },
    );
  }

  void _playRadioStation(NavidromeRadioStation station) {
    // 创建电台 Track 并播放
    final track = Track(
      id: 'radio_${station.id}',
      name: station.name,
      artists: '网络电台',
      album: station.homePageUrl ?? '',
      picUrl: '', // 电台没有封面
      source: MusicSource.navidrome,
    );

    // 设置单曲队列并播放
    PlaylistQueueService().setQueue([track], 0, QueueSource.radio);

    // 直接播放电台流
    PlayerService().playRadioStream(station.streamUrl, track);
  }

  @override
  bool get wantKeepAlive => true;
}

class _ArtistChip extends StatelessWidget {
  final NavidromeArtist artist;
  final NavidromeApi? api;
  final VoidCallback onTap;

  const _ArtistChip({
    required this.artist,
    required this.api,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: NavidromeCard(
        onTap: onTap,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        borderRadius: BorderRadius.circular(16),
        child: SizedBox(
          width: 84,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              CircleAvatar(
                radius: 26,
                backgroundColor: colorScheme.primaryContainer,
                backgroundImage: artist.coverArt != null && api != null
                    ? NetworkImage(api!.buildCoverUrl(artist.coverArt!, size: 100))
                    : null,
                child: artist.coverArt == null
                    ? Icon(Icons.person, color: colorScheme.onPrimaryContainer)
                    : null,
              ),
              const SizedBox(height: 8),
              Text(
                artist.name,
                style: theme.textTheme.bodySmall?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 电台列表项组件
class _RadioStationTile extends StatelessWidget {
  final NavidromeRadioStation station;
  final VoidCallback onTap;

  const _RadioStationTile({
    required this.station,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final navTheme = NavidromeTheme.of(context);

    return NavidromeCard(
      onTap: onTap,
      padding: const EdgeInsets.all(12),
      child: Row(
        children: [
          // 电台图标（橙色）
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              color: NavidromeColors.radioOrange.withOpacity(0.15),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(
              Icons.radio,
              color: NavidromeColors.radioOrange,
              size: 28,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  station.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodyLarge?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  station.homePageUrl ?? '网络电台',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: navTheme.textSecondary,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          // 播放按钮
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: NavidromeColors.radioOrange,
              borderRadius: BorderRadius.circular(18),
            ),
            child: const Icon(
              Icons.play_arrow,
              color: Colors.white,
              size: 22,
            ),
          ),
        ],
      ),
    );
  }
}
