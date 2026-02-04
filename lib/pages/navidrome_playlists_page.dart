import 'package:flutter/material.dart';
import '../models/navidrome_models.dart';
import '../models/track.dart';
import '../services/navidrome_api.dart';
import '../services/navidrome_session_service.dart';
import '../services/player_service.dart';
import '../services/playlist_queue_service.dart';
import '../widgets/navidrome_ui.dart';

class NavidromePlaylistsPage extends StatefulWidget {
  const NavidromePlaylistsPage({super.key});

  @override
  State<NavidromePlaylistsPage> createState() => _NavidromePlaylistsPageState();
}

class _NavidromePlaylistsPageState extends State<NavidromePlaylistsPage> {
  List<NavidromePlaylist> _playlists = [];
  bool _loading = true;
  String? _error;

  NavidromeApi? get _api => NavidromeSessionService().api;

  @override
  void initState() {
    super.initState();
    _loadPlaylists();
  }

  Future<void> _loadPlaylists() async {
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
      final playlists = await api.getPlaylists();
      if (!mounted) return;
      setState(() {
        _playlists = playlists;
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

    return SafeArea(
      child: LayoutBuilder(
        builder: (context, constraints) {
          final width = constraints.maxWidth;
          final padding = NavidromeLayout.pagePadding(width);
          final bottomPadding = 24 + MediaQuery.of(context).padding.bottom;

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
                  '歌单',
                  style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                ),
              ),
              Expanded(
                child: RefreshIndicator(
                  onRefresh: _loadPlaylists,
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
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) =>
                                  NavidromePlaylistDetailPage(playlist: playlist),
                            ),
                          );
                        },
                        padding: const EdgeInsets.all(12),
                        child: Row(
                          children: [
                            _CoverTile(
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
                                    style: Theme.of(context)
                                        .textTheme
                                        .bodyLarge
                                        ?.copyWith(fontWeight: FontWeight.w600),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    '${playlist.songCount} 首歌曲',
                                    style: Theme.of(context)
                                        .textTheme
                                        .bodySmall
                                        ?.copyWith(
                                          color: Theme.of(context)
                                              .colorScheme
                                              .outline,
                                        ),
                                  ),
                                ],
                              ),
                            ),
                            Icon(Icons.chevron_right,
                                color: Theme.of(context).colorScheme.outline),
                          ],
                        ),
                      );
                    },
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class NavidromePlaylistDetailPage extends StatefulWidget {
  final NavidromePlaylist playlist;

  const NavidromePlaylistDetailPage({super.key, required this.playlist});

  @override
  State<NavidromePlaylistDetailPage> createState() =>
      _NavidromePlaylistDetailPageState();
}

class _NavidromePlaylistDetailPageState
    extends State<NavidromePlaylistDetailPage> {
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
      setState(() {
        _songs = songs;
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
              : LayoutBuilder(
                  builder: (context, constraints) {
                    final width = constraints.maxWidth;
                    final padding = NavidromeLayout.pagePadding(width);
                    final bottomPadding =
                        24 + MediaQuery.of(context).padding.bottom;

                    return ListView.separated(
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
                          onTap: () => _playSongs(index),
                          padding: const EdgeInsets.all(12),
                          child: Row(
                            children: [
                              _CoverTile(
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
                                      song.artist,
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
                    );
                  },
                ),
    );
  }
}

class _CoverTile extends StatelessWidget {
  final String coverUrl;
  final double size;
  final IconData icon;

  const _CoverTile({
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
          borderRadius: BorderRadius.circular(12),
        ),
        child: Icon(icon, color: colorScheme.onSurfaceVariant),
      );
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: Image.network(
        coverUrl,
        width: size,
        height: size,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            color: colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(icon, color: colorScheme.onSurfaceVariant),
        ),
      ),
    );
  }
}
