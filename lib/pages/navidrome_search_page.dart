import 'package:flutter/material.dart';
import '../models/navidrome_models.dart';
import '../models/track.dart';
import '../services/navidrome_api.dart';
import '../services/navidrome_session_service.dart';
import '../services/player_service.dart';
import '../services/playlist_queue_service.dart';
import 'navidrome_library_page.dart';
import 'navidrome_artists_page.dart';
import '../widgets/navidrome_ui.dart';

/// Navidrome 搜索页面
///
/// 支持 Tab 分类筛选：全部/艺术家/专辑/歌曲
class NavidromeSearchPage extends StatefulWidget {
  const NavidromeSearchPage({super.key});

  @override
  State<NavidromeSearchPage> createState() => _NavidromeSearchPageState();
}

class _NavidromeSearchPageState extends State<NavidromeSearchPage>
    with SingleTickerProviderStateMixin {
  final TextEditingController _controller = TextEditingController();
  final FocusNode _focusNode = FocusNode();
  late TabController _tabController;

  bool _isLoading = false;
  String? _error;
  NavidromeSearchResult? _result;

  NavidromeApi? get _api => NavidromeSessionService().api;

  static const _tabs = ['全部', '艺术家', '专辑', '歌曲'];

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
      final result = await api.search3(
        query,
        artistCount: 50,
        albumCount: 50,
        songCount: 100,
      );
      if (!mounted) return;
      setState(() => _result = result);
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

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Scaffold(
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
                  child: _buildSearchField(colorScheme),
                ),
                if (_result != null && !_result!.isEmpty)
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

  Widget _buildSearchField(ColorScheme colorScheme) {
    return TextField(
      controller: _controller,
      focusNode: _focusNode,
      textInputAction: TextInputAction.search,
      onSubmitted: (_) => _search(),
      decoration: InputDecoration(
        hintText: '搜索歌曲、专辑、艺术家',
        prefixIcon: const Icon(Icons.search),
        suffixIcon: _controller.text.isNotEmpty
            ? IconButton(
                icon: const Icon(Icons.clear),
                onPressed: _clearSearch,
              )
            : null,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide.none,
        ),
        filled: true,
        fillColor: colorScheme.surfaceContainerHighest,
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
            Icon(Icons.search, size: 64, color: colorScheme.outline),
            const SizedBox(height: 16),
            Text(
              '输入关键词开始搜索',
              style: theme.textTheme.bodyLarge?.copyWith(
                color: colorScheme.outline,
              ),
            ),
          ],
        ),
      );
    }

    if (_result!.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.search_off, size: 64, color: colorScheme.outline),
            const SizedBox(height: 16),
            Text(
              '未找到相关结果',
              style: theme.textTheme.bodyLarge?.copyWith(
                color: colorScheme.outline,
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
      ],
    );
  }

  Widget _buildAllTab(ThemeData theme, ColorScheme colorScheme) {
    final artists = _result?.artists ?? [];
    final albums = _result?.albums ?? [];
    final songs = _result?.songs ?? [];
    final width = MediaQuery.of(context).size.width;
    final padding = NavidromeLayout.pagePadding(width);
    final bottomPadding = 24 + MediaQuery.of(context).padding.bottom;

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
            height: 210,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              padding: EdgeInsets.symmetric(horizontal: padding.left),
              itemCount: albums.take(10).length,
              itemBuilder: (context, index) {
                final album = albums[index];
                return _AlbumCard(
                  album: album,
                  api: _api,
                  onTap: () => _navigateToAlbum(album),
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
            return Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: _SongTile(
                song: song,
                api: _api,
                onTap: () => _playSongs(songs, songIndex),
              ),
            );
          }),
        ],
      ],
    );
  }

  Widget _buildArtistsTab(ThemeData theme, ColorScheme colorScheme) {
    final artists = _result?.artists ?? [];
    if (artists.isEmpty) {
      return const Center(child: Text('没有找到艺术家'));
    }

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

        return InkWell(
          onTap: () => _navigateToAlbum(album),
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
                          errorBuilder: (_, __, ___) => _albumPlaceholder(colorScheme),
                        )
                      : _albumPlaceholder(colorScheme),
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
      },
    );
  }

  Widget _albumPlaceholder(ColorScheme colorScheme) {
    return Container(
      color: colorScheme.surfaceContainerHighest,
      child: Icon(Icons.album, size: 48, color: colorScheme.onSurfaceVariant),
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

    return ListView.separated(
      padding: EdgeInsets.fromLTRB(
        padding.left,
        8,
        padding.right,
        bottomPadding,
      ),
      itemCount: songs.length,
      separatorBuilder: (_, __) => const SizedBox(height: 10),
      itemBuilder: (context, index) {
        final song = songs[index];
        return _SongTile(
          song: song,
          api: _api,
          onTap: () => _playSongs(songs, index),
        );
      },
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
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => NavidromeAlbumPage(album: album),
      ),
    );
  }
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

class _AlbumCard extends StatelessWidget {
  final NavidromeAlbum album;
  final NavidromeApi? api;
  final VoidCallback onTap;

  const _AlbumCard({
    required this.album,
    required this.api,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final coverUrl = api?.buildCoverUrl(album.coverArt) ?? '';

    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: SizedBox(
          width: 140,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: SizedBox(
                  width: 140,
                  height: 140,
                  child: coverUrl.isNotEmpty
                      ? Image.network(
                          coverUrl,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => Container(
                            color: colorScheme.surfaceContainerHighest,
                            child: Icon(
                              Icons.album,
                              color: colorScheme.onSurfaceVariant,
                            ),
                          ),
                        )
                      : Container(
                          color: colorScheme.surfaceContainerHighest,
                          child: Icon(
                            Icons.album,
                            color: colorScheme.onSurfaceVariant,
                          ),
                        ),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                album.name,
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w600,
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
        ),
      ),
    );
  }
}

class _SongTile extends StatelessWidget {
  final NavidromeSong song;
  final NavidromeApi? api;
  final VoidCallback onTap;

  const _SongTile({
    required this.song,
    required this.api,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final coverUrl = api?.buildCoverUrl(song.coverArt) ?? '';

    return NavidromeCard(
      onTap: onTap,
      padding: const EdgeInsets.all(12),
      child: Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: SizedBox(
              width: 52,
              height: 52,
              child: coverUrl.isNotEmpty
                  ? Image.network(
                      coverUrl,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => Container(
                        color: colorScheme.surfaceContainerHighest,
                        child: Icon(
                          Icons.music_note,
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                    )
                  : Container(
                      color: colorScheme.surfaceContainerHighest,
                      child: Icon(
                        Icons.music_note,
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
            ),
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
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colorScheme.outline,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
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
  }
}
