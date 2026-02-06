import 'package:flutter/material.dart';
import '../models/navidrome_models.dart';
import '../models/track.dart';
import '../services/navidrome_session_service.dart';
import '../services/navidrome_api.dart';
import '../services/player_service.dart';
import '../services/playlist_queue_service.dart';
import '../widgets/navidrome_ui.dart';
import '../widgets/sheet_stack_navigator.dart';

/// 艺术家列表页面
class NavidromeArtistsPage extends StatefulWidget {
  const NavidromeArtistsPage({super.key});

  @override
  State<NavidromeArtistsPage> createState() => _NavidromeArtistsPageState();
}

class _NavidromeArtistsPageState extends State<NavidromeArtistsPage> {
  List<NavidromeArtist> _artists = [];
  bool _loading = true;
  String? _error;

  NavidromeApi? get _api => NavidromeSessionService().api;

  @override
  void initState() {
    super.initState();
    _loadArtists();
  }

  Future<void> _loadArtists() async {
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
      final artists = await api.getArtists();
      if (!mounted) return;
      setState(() {
        _artists = artists;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = '加载失败：$e';
      });
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final navTheme = NavidromeTheme.of(context);

    if (_loading) {
      return Scaffold(
        backgroundColor: navTheme.background,
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    if (_error != null) {
      return Scaffold(
        backgroundColor: navTheme.background,
        body: NavidromeErrorState(
          message: _error!,
          onRetry: _loadArtists,
        ),
      );
    }

    if (_artists.isEmpty) {
      return Scaffold(
        backgroundColor: navTheme.background,
        body: const Center(child: Text('暂无艺术家')),
      );
    }

    return Scaffold(
      backgroundColor: navTheme.background,
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final width = constraints.maxWidth;
            final padding = NavidromeLayout.pagePadding(width);
            final bottomPadding = NavidromeLayout.bottomPadding(context);

            return Column(
              children: [
                Padding(
                  padding: EdgeInsets.fromLTRB(
                    padding.left,
                    6,
                    padding.right,
                    0,
                  ),
                  child: Align(
                    alignment: Alignment.centerRight,
                    child: InkWell(
                      onTap: _loadArtists,
                      borderRadius: BorderRadius.circular(18),
                      child: Container(
                        width: 36,
                        height: 36,
                        decoration: BoxDecoration(
                          color: navTheme.card,
                          shape: BoxShape.circle,
                          boxShadow: navTheme.cardShadow,
                        ),
                        child: Icon(
                          Icons.refresh,
                          color: navTheme.textSecondary,
                          size: 18,
                        ),
                      ),
                    ),
                  ),
                ),
                Expanded(
                  child: RefreshIndicator(
                    onRefresh: _loadArtists,
                    child: ListView.separated(
                      padding: EdgeInsets.fromLTRB(
                        padding.left,
                        6,
                        padding.right,
                        bottomPadding,
                      ),
                      itemCount: _artists.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 10),
                      itemBuilder: (context, index) {
                        final artist = _artists[index];
                        return _ArtistTile(
                          artist: artist,
                          api: _api,
                          onTap: () {
                            _openArtist(context, artist);
                          },
                        );
                      },
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

bool _useArtistSheet(BuildContext context) {
  return NavidromeLayout.useSheetNavigation(context);
}

void _openArtist(BuildContext context, NavidromeArtist artist) {
  if (_useArtistSheet(context)) {
    showNavidromeArtistSheet(context: context, artist: artist);
    return;
  }
  Navigator.push(
    context,
    MaterialPageRoute(
      builder: (_) => NavidromeArtistDetailPage(artist: artist),
    ),
  );
}

Future<void> showNavidromeArtistSheet({
  required BuildContext context,
  required NavidromeArtist artist,
}) {
  final navTheme = NavidromeTheme.of(context);
  final media = MediaQuery.of(context);
  final isLandscape = media.orientation == Orientation.landscape;
  final sheetHeight = media.size.height * (isLandscape ? 0.9 : 0.65);
  final stack = SheetStackController(
    initialPage: SheetStackPage(
      title: artist.name,
      builder: (context, controller, stack) {
        return NavidromeArtistDetailPage(
          artist: artist,
          asSheet: true,
          showHandle: false,
          controller: controller,
          onOpenAlbum: (album) {
            stack.push(
              SheetStackPage(
                title: album.name,
                builder: (context, controller, stack) {
                  return NavidromeAlbumSheet(
                    album: album,
                    api: NavidromeSessionService().api,
                    controller: controller,
                    showHandle: false,
                  );
                },
              ),
            );
          },
        );
      },
    ),
  );

  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: navTheme.background,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (context) {
      return SafeArea(
        child: SizedBox(
          height: sheetHeight,
          child: SheetStackNavigator(
            controller: stack,
            backgroundColor: navTheme.background,
            dividerColor: navTheme.divider,
            useDraggableSheet: false,
            showHandle: true,
            onClose: () => Navigator.of(context).maybePop(),
            titleTextStyle: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                  color: navTheme.textPrimary,
                ),
          ),
        ),
      );
    },
  );
}

class _ArtistTile extends StatelessWidget {
  final NavidromeArtist artist;
  final NavidromeApi? api;
  final VoidCallback onTap;

  const _ArtistTile({
    required this.artist,
    required this.api,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final navTheme = NavidromeTheme.of(context);

    final coverUrl = artist.coverArt != null && api != null
        ? api!.buildCoverUrl(artist.coverArt!, size: 120)
        : '';

    return NavidromeCard(
      onTap: onTap,
      padding: const EdgeInsets.all(12),
      child: Row(
        children: [
          CircleAvatar(
            radius: 26,
            backgroundColor: colorScheme.primaryContainer,
            backgroundImage: coverUrl.isNotEmpty ? NetworkImage(coverUrl) : null,
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
  }
}

/// 艺术家详情页面
class NavidromeArtistDetailPage extends StatefulWidget {
  final NavidromeArtist artist;
  final bool asSheet;
  final bool showHandle;
  final ScrollController? controller;
  final ValueChanged<NavidromeAlbum>? onOpenAlbum;

  const NavidromeArtistDetailPage({
    super.key,
    required this.artist,
    this.asSheet = false,
    this.showHandle = true,
    this.controller,
    this.onOpenAlbum,
  });

  @override
  State<NavidromeArtistDetailPage> createState() =>
      _NavidromeArtistDetailPageState();
}

class _NavidromeArtistDetailPageState extends State<NavidromeArtistDetailPage> {
  NavidromeArtistInfo? _artistInfo;
  List<NavidromeSong> _topSongs = [];
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
      setState(() {
        _artistInfo = info;
      });
      await _loadTopSongs();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = '加载失败：$e';
      });
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
        });
      }
    }
  }

  Future<void> _loadTopSongs() async {
    final api = _api;
    if (api == null) return;

    try {
      final songs = await api.getTopSongs(count: 100);
      if (!mounted) return;

      final matched = songs
          .where((song) =>
              song.artistId == widget.artist.id ||
              song.artist == widget.artist.name)
          .toList();

      setState(() {
        _topSongs = matched;
      });
    } catch (_) {
      // ignore song load failures to avoid blocking the page
    }
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

  Future<void> _playAlbumQuick(NavidromeAlbum album) async {
    final api = _api;
    if (api == null) return;

    try {
      final songs = await api.getAlbumSongs(album.id);
      if (!mounted || songs.isEmpty) return;

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

      PlaylistQueueService().setQueue(tracks, 0, QueueSource.album);
      PlayerService().playTrack(tracks[0]);
    } catch (_) {
      // ignore play errors
    }
  }

  Future<void> _addAlbumToQueue(NavidromeAlbum album) async {
    final api = _api;
    if (api == null) return;

    try {
      final songs = await api.getAlbumSongs(album.id);
      if (!mounted || songs.isEmpty) return;

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

      PlaylistQueueService().appendToQueue(tracks);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('已加入播放队列')),
        );
      }
    } catch (_) {
      // ignore add failures
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

      if (!mounted || _artistInfo == null) return;
      final info = _artistInfo!;
      final updatedAlbums = info.albums.map((a) {
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
        _artistInfo = NavidromeArtistInfo(
          artist: info.artist,
          albums: updatedAlbums,
          biography: info.biography,
          musicBrainzId: info.musicBrainzId,
          lastFmUrl: info.lastFmUrl,
          similarArtistIds: info.similarArtistIds,
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

  void _showAllSongsSheet(List<NavidromeSong> songs) {
    if (songs.isEmpty) return;
    final navTheme = NavidromeTheme.of(context);

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: navTheme.background,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) {
        return SafeArea(
          child: DraggableScrollableSheet(
            expand: false,
            initialChildSize: 0.6,
            minChildSize: 0.4,
            maxChildSize: 0.9,
            builder: (context, controller) {
              return NavidromeSongList(
                songs: songs,
                api: _api,
                controller: controller,
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                onTap: (index) => _playSongs(songs, index),
              );
            },
          ),
        );
      },
    );
  }

  void _showAlbumSheet(NavidromeAlbum album) {
    if (widget.onOpenAlbum != null) {
      widget.onOpenAlbum!(album);
      return;
    }
    showNavidromeAlbumSheet(
      context: context,
      album: album,
      api: _api,
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final navTheme = NavidromeTheme.of(context);
    final body = _loading
        ? const Center(child: CircularProgressIndicator())
        : _error != null
            ? Center(child: Text(_error!))
            : LayoutBuilder(
                builder: (context, constraints) {
                  return _buildContent(
                    theme,
                    colorScheme,
                    constraints.maxWidth,
                    scrollController: widget.controller,
                  );
                },
              );

    if (widget.asSheet) {
      return Container(
        decoration: BoxDecoration(
          color: navTheme.background,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(
          children: [
            if (widget.showHandle) ...[
              const SizedBox(height: 8),
              Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: navTheme.divider,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 8),
            ],
            Expanded(child: body),
          ],
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.artist.name),
        backgroundColor: navTheme.background,
        foregroundColor: navTheme.textPrimary,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
      ),
      backgroundColor: navTheme.background,
      body: body,
    );
  }

  Widget _buildContent(
    ThemeData theme,
    ColorScheme colorScheme,
    double width,
    {ScrollController? scrollController}
  ) {
    final albums = _artistInfo?.albums ?? [];
    final padding = NavidromeLayout.pagePadding(width);
    final navTheme = NavidromeTheme.of(context);

    return CustomScrollView(
      controller: scrollController,
      slivers: [
        // 艺术家头部信息
        SliverToBoxAdapter(
          child: Padding(
            padding: EdgeInsets.fromLTRB(
              padding.left,
              widget.asSheet ? 6 : 16,
              padding.right,
              12,
            ),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 40,
                  backgroundColor: colorScheme.primaryContainer,
                  backgroundImage: widget.artist.coverArt != null && _api != null
                      ? NetworkImage(
                          _api!.buildCoverUrl(widget.artist.coverArt!, size: 200),
                        )
                      : null,
                  child: widget.artist.coverArt == null
                      ? Icon(
                          Icons.person,
                          size: 40,
                          color: colorScheme.onPrimaryContainer,
                        )
                      : null,
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.artist.name,
                        style: theme.textTheme.headlineSmall,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '${albums.length} 张专辑',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: navTheme.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        if (_topSongs.isNotEmpty) ...[
          SliverToBoxAdapter(
            child: NavidromeSectionHeader(
              title: '热门歌曲',
              actionLabel: '查看全部',
              onAction: () => _showAllSongsSheet(_topSongs),
              padding: EdgeInsets.fromLTRB(
                padding.left,
                8,
                padding.right,
                4,
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.fromLTRB(
                padding.left,
                0,
                padding.right,
                12,
              ),
              child: Column(
                children: _topSongs.take(5).map((song) {
                  final index = _topSongs.indexOf(song);
                  final coverUrl = _api?.buildCoverUrl(song.coverArt) ?? '';
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: NavidromeSongTile(
                      title: song.title,
                      subtitle: '${song.artist} · ${song.album}',
                      coverUrl: coverUrl,
                      duration: song.durationFormatted,
                      onTap: () => _playSongs(_topSongs, index),
                    ),
                  );
                }).toList(),
              ),
            ),
          ),
        ],
        SliverToBoxAdapter(
          child: NavidromeSectionHeader(
            title: '专辑',
            padding: EdgeInsets.fromLTRB(
              padding.left,
              8,
              padding.right,
              4,
            ),
          ),
        ),
        if (albums.isEmpty)
          SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.fromLTRB(
                padding.left,
                8,
                padding.right,
                24,
              ),
              child: Text(
                '暂无专辑',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: navTheme.textSecondary,
                ),
              ),
            ),
          )
        else
          SliverPadding(
            padding: EdgeInsets.symmetric(horizontal: padding.left),
            sliver: SliverGrid(
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount:
                    width < NavidromeLayout.compactWidth ? 2 : 3,
                mainAxisSpacing: 12,
                crossAxisSpacing: 12,
                childAspectRatio: NavidromeLayout.gridAspectRatio(width),
              ),
              delegate: SliverChildBuilderDelegate(
                (context, index) {
                  final album = albums[index];
                  return GestureDetector(
                    onLongPress: () => _showAlbumActions(album),
                    child: Stack(
                      children: [
                        Positioned.fill(
                          child: _AlbumGridItem(
                            album: album,
                            api: _api,
                            onTap: () {
                              _showAlbumSheet(album);
                            },
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
                childCount: albums.length,
              ),
            ),
          ),
        const SliverPadding(padding: EdgeInsets.only(bottom: 16)),
      ],
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
                          errorBuilder: (_, __, ___) => NavidromeCoverPlaceholder(
                            baseColor: colorScheme.surfaceContainerHighest,
                            iconSize: 32,
                            borderRadius: 12,
                          ),
                        )
                      : NavidromeCoverPlaceholder(
                          baseColor: colorScheme.surfaceContainerHighest,
                          iconSize: 32,
                          borderRadius: 12,
                        ),
                ),
          ),
          const SizedBox(height: 6),
          Text(
            album.name,
            style: theme.textTheme.bodyMedium?.copyWith(
              fontWeight: FontWeight.w600,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          if (album.year != null)
            Text(
              '${album.year}',
              style: theme.textTheme.bodySmall?.copyWith(
                color: colorScheme.outline,
              ),
            ),
        ],
      ),
    );
  }
}
