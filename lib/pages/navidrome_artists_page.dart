import 'package:flutter/material.dart';
import '../models/navidrome_models.dart';
import '../services/navidrome_session_service.dart';
import '../services/navidrome_api.dart';
import 'navidrome_library_page.dart';
import '../widgets/navidrome_ui.dart';

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
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_error != null) {
      return Center(child: Text(_error!));
    }

    if (_artists.isEmpty) {
      return const Center(child: Text('暂无艺术家'));
    }

    return SafeArea(
      child: LayoutBuilder(
        builder: (context, constraints) {
          final width = constraints.maxWidth;
          final padding = NavidromeLayout.pagePadding(width);
          final bottomPadding = 24 + MediaQuery.of(context).padding.bottom;

          return RefreshIndicator(
            onRefresh: _loadArtists,
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
                return _ArtistTile(
                  artist: artist,
                  api: _api,
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => NavidromeArtistDetailPage(artist: artist),
                      ),
                    );
                  },
                );
              },
            ),
          );
        },
      ),
    );
  }
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
  }
}

/// 艺术家详情页面
class NavidromeArtistDetailPage extends StatefulWidget {
  final NavidromeArtist artist;

  const NavidromeArtistDetailPage({super.key, required this.artist});

  @override
  State<NavidromeArtistDetailPage> createState() =>
      _NavidromeArtistDetailPageState();
}

class _NavidromeArtistDetailPageState extends State<NavidromeArtistDetailPage> {
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
      setState(() {
        _artistInfo = info;
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
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.artist.name),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Text(_error!))
              : LayoutBuilder(
                  builder: (context, constraints) {
                    return _buildContent(theme, colorScheme, constraints.maxWidth);
                  },
                ),
    );
  }

  Widget _buildContent(
    ThemeData theme,
    ColorScheme colorScheme,
    double width,
  ) {
    final albums = _artistInfo?.albums ?? [];
    final padding = NavidromeLayout.pagePadding(width);

    if (albums.isEmpty) {
      return const Center(child: Text('暂无专辑'));
    }

    return CustomScrollView(
      slivers: [
        // 艺术家头部信息
        SliverToBoxAdapter(
          child: Padding(
            padding: EdgeInsets.fromLTRB(
              padding.left,
              16,
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
                          color: colorScheme.outline,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        // 专辑分隔标题
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
        // 专辑网格
        SliverPadding(
          padding: EdgeInsets.symmetric(horizontal: padding.left),
          sliver: SliverGrid(
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: NavidromeLayout.gridColumns(width),
              mainAxisSpacing: 12,
              crossAxisSpacing: 12,
              childAspectRatio: NavidromeLayout.gridAspectRatio(width),
            ),
            delegate: SliverChildBuilderDelegate(
              (context, index) {
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
