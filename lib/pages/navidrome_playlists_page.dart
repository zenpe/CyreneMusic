import 'dart:io';
import 'package:flutter/material.dart';
import '../models/navidrome_models.dart';
import '../models/track.dart';
import '../services/navidrome_api.dart';
import '../services/navidrome_session_service.dart';
import '../services/player_service.dart';
import '../services/playlist_queue_service.dart';
import '../widgets/navidrome_ui.dart';
import '../widgets/sheet_stack_navigator.dart';

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
          onRetry: _loadPlaylists,
        ),
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
              crossAxisAlignment: CrossAxisAlignment.start,
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
                      onTap: _loadPlaylists,
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
                            if (Platform.isAndroid || Platform.isIOS) {
                              showNavidromePlaylistSheet(
                                context: context,
                                playlist: playlist,
                              );
                              return;
                            }
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => NavidromePlaylistDetailPage(
                                  playlist: playlist,
                                ),
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
                                            color: navTheme.textSecondary,
                                          ),
                                    ),
                                  ],
                                ),
                              ),
                              Icon(Icons.chevron_right,
                                  color: navTheme.textSecondary),
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
      ),
    );
  }
}

class NavidromePlaylistDetailPage extends StatefulWidget {
  final NavidromePlaylist playlist;
  final bool asSheet;
  final bool showHandle;
  final ScrollController? controller;

  const NavidromePlaylistDetailPage({
    super.key,
    required this.playlist,
    this.asSheet = false,
    this.showHandle = true,
    this.controller,
  });

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
    final navTheme = NavidromeTheme.of(context);
    final body = _loading
        ? const Center(child: CircularProgressIndicator())
        : _error != null
            ? NavidromeErrorState(
                message: _error!,
                onRetry: _loadSongs,
              )
            : LayoutBuilder(
                builder: (context, constraints) {
                    final width = constraints.maxWidth;
                    final padding = NavidromeLayout.pagePadding(width);
                    final bottomPadding = NavidromeLayout.bottomPadding(context);

                  return ListView.separated(
                    controller: widget.controller,
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
                                    style:
                                        theme.textTheme.bodyLarge?.copyWith(
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    song.artist,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style:
                                        theme.textTheme.bodySmall?.copyWith(
                                      color: navTheme.textSecondary,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            Text(
                              song.durationFormatted,
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: navTheme.textSecondary,
                              ),
                            ),
                          ],
                        ),
                      );
                    },
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
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  widget.playlist.name,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: navTheme.textPrimary,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 4),
            Expanded(child: body),
          ],
        ),
      );
    }

    return Scaffold(
      backgroundColor: navTheme.background,
      appBar: AppBar(
        title: Text(widget.playlist.name),
        backgroundColor: navTheme.background,
        foregroundColor: navTheme.textPrimary,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
      ),
      body: body,
    );
  }
}

Future<void> showNavidromePlaylistSheet({
  required BuildContext context,
  required NavidromePlaylist playlist,
}) {
  final navTheme = NavidromeTheme.of(context);

  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: navTheme.background,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (context) {
      return SafeArea(
        child: SheetStackNavigator(
          controller: SheetStackController(
            initialPage: SheetStackPage(
              title: playlist.name,
              builder: (context, controller, stack) {
                return NavidromePlaylistDetailPage(
                  playlist: playlist,
                  asSheet: true,
                  controller: controller,
                );
              },
            ),
          ),
          backgroundColor: navTheme.background,
          dividerColor: navTheme.divider,
          showHandle: true,
          onClose: () => Navigator.of(context).maybePop(),
          titleTextStyle: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w600,
                color: navTheme.textPrimary,
              ),
        ),
      );
    },
  );
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
