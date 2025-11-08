import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:fluent_ui/fluent_ui.dart' as fluent;
import '../services/netease_discover_service.dart';
import '../models/netease_discover.dart';
import '../models/track.dart';
import '../widgets/track_list_tile.dart';
import '../services/playlist_queue_service.dart';
import '../services/player_service.dart';
import '../services/auth_service.dart';
import '../pages/auth/auth_page.dart';
import '../utils/theme_manager.dart';

class DiscoverPlaylistDetailPage extends StatelessWidget {
  final int playlistId;
  const DiscoverPlaylistDetailPage({super.key, required this.playlistId});

  @override
  Widget build(BuildContext context) {
    final baseTheme = Theme.of(context);

    return Theme(
      data: _discoverPlaylistFontTheme(baseTheme),
      child: Builder(
        builder: (context) {
          return Scaffold(
            backgroundColor: Colors.transparent,
            appBar: AppBar(
              backgroundColor: Colors.transparent,
              surfaceTintColor: Colors.transparent,
              elevation: 0,
              scrolledUnderElevation: 0,
              title: const Text('歌单详情'),
            ),
            body: DiscoverPlaylistDetailContent(playlistId: playlistId),
          );
        },
      ),
    );
  }
}

ThemeData _discoverPlaylistFontTheme(ThemeData base) {
  const fontFamily = 'Microsoft YaHei';
  final textTheme = base.textTheme.apply(fontFamily: fontFamily);
  final primaryTextTheme = base.primaryTextTheme.apply(fontFamily: fontFamily);
  final appBarTheme = base.appBarTheme.copyWith(
    titleTextStyle: (base.appBarTheme.titleTextStyle ?? textTheme.titleLarge)
        ?.copyWith(fontFamily: fontFamily),
    toolbarTextStyle:
        (base.appBarTheme.toolbarTextStyle ?? textTheme.titleMedium)?.copyWith(
          fontFamily: fontFamily,
        ),
  );

  return base.copyWith(
    textTheme: textTheme,
    primaryTextTheme: primaryTextTheme,
    appBarTheme: appBarTheme,
  );
}

class DiscoverPlaylistDetailContent extends StatefulWidget {
  final int playlistId;
  const DiscoverPlaylistDetailContent({super.key, required this.playlistId});

  @override
  State<DiscoverPlaylistDetailContent> createState() =>
      _DiscoverPlaylistDetailContentState();
}

class _DiscoverPlaylistDetailContentState
    extends State<DiscoverPlaylistDetailContent> {
  NeteasePlaylistDetail? _detail;
  bool _loading = true;
  String? _error;
  final ScrollController _scrollController = ScrollController();
  final Map<String, ImageProvider> _coverProviderCache = {};

  String _coverKey(Track track) => '${track.source.name}_${track.id}';

  @override
  void initState() {
    super.initState();
    _scrollToTop();
    _load();
  }

  @override
  void didUpdateWidget(covariant DiscoverPlaylistDetailContent oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.playlistId != oldWidget.playlistId) {
      _scrollToTop();
      _load();
    }
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    _coverProviderCache.clear();
    final detail = await NeteaseDiscoverService().fetchPlaylistDetail(
      widget.playlistId,
    );
    if (!mounted) return;
    setState(() {
      _detail = detail;
      _loading = false;
      if (detail == null) {
        _error = NeteaseDiscoverService().errorMessage ?? '加载失败';
      }
    });
    _scrollToTop();
  }

  @override
  Widget build(BuildContext context) {
    final themeManager = ThemeManager();
    if (themeManager.isFluentFramework) {
      return _buildFluentDetail(context);
    }

    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return Center(child: Text(_error!));
    }

    final detail = _detail!;
    final List<Track> allTracks = detail.tracks
        .map(
          (t) => Track(
            id: t.id,
            name: t.name,
            artists: t.artists,
            album: t.album,
            picUrl: t.picUrl,
            source: MusicSource.netease,
          ),
        )
        .toList();

    return CustomScrollView(
      controller: _scrollController,
      physics: const AlwaysScrollableScrollPhysics(),
      slivers: [
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: CachedNetworkImage(
                    imageUrl: detail.coverImgUrl,
                    width: 120,
                    height: 120,
                    fit: BoxFit.cover,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        detail.name,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'by ${detail.creator}',
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                      const SizedBox(height: 6),
                      Wrap(
                        spacing: 6,
                        runSpacing: -6,
                        children: detail.tags
                            .map((t) => Chip(label: Text(t)))
                            .toList(),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        if (detail.description.isNotEmpty)
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16.0),
              child: Text(
                detail.description,
                maxLines: 4,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.start,
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ),
          ),
        const SliverToBoxAdapter(child: SizedBox(height: 8)),
        SliverList(
          delegate: SliverChildBuilderDelegate((context, index) {
            final track = allTracks[index];
            return TrackListTile(
              track: track,
              index: index,
              onCoverReady: (provider) {
                final key = _coverKey(track);
                _coverProviderCache[key] = provider;
                PlaylistQueueService().updateCoverProvider(track, provider);
              },
              onTap: () async {
                final ok = await _checkLoginStatus();
                if (!ok) return;
                // 替换播放队列为当前歌单
                PlaylistQueueService().setQueue(
                  allTracks,
                  index,
                  QueueSource.playlist,
                  coverProviders: _coverProviderCache,
                );
                // 播放所点歌曲
                final coverProvider = _coverProviderCache[_coverKey(track)];
                await PlayerService().playTrack(
                  track,
                  coverProvider: coverProvider,
                );
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('正在加载：${track.name}'),
                      duration: const Duration(seconds: 1),
                    ),
                  );
                }
              },
            );
          }, childCount: detail.tracks.length),
        ),
      ],
    );
  }

  Widget _buildFluentDetail(BuildContext context) {
    if (_loading) {
      return const Center(child: fluent.ProgressRing());
    }
    if (_error != null) {
      return Center(
        child: fluent.InfoBar(
          title: const Text('加载失败'),
          content: Text(_error!),
          severity: fluent.InfoBarSeverity.error,
        ),
      );
    }

    final detail = _detail!;
    final tracks = detail.tracks
        .map(
          (t) => Track(
            id: t.id,
            name: t.name,
            artists: t.artists,
            album: t.album,
            picUrl: t.picUrl,
            source: MusicSource.netease,
          ),
        )
        .toList();

    return fluent.ScrollConfiguration(
      behavior: const fluent.FluentScrollBehavior(),
      child: ListView(
        controller: _scrollController,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        children: [
          _buildFluentHeader(detail, context),
          if (detail.description.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text(
              detail.description,
              maxLines: 4,
              overflow: TextOverflow.ellipsis,
              style: fluent.FluentTheme.of(context)
                  .typography
                  ?.body
                  ?.copyWith(color: fluent.FluentTheme.of(context)
                      .resources
                      .textFillColorSecondary),
            ),
          ],
          const SizedBox(height: 16),
          ...tracks.asMap().entries.map(
                (entry) => _FluentTrackTile(
                  track: entry.value,
                  index: entry.key,
                  onTap: () => _handleTrackTap(
                    context,
                    entry.key,
                    tracks,
                  ),
                  onCoverReady: (provider) {
                    final key = _coverKey(entry.value);
                    _coverProviderCache[key] = provider;
                    PlaylistQueueService().updateCoverProvider(
                      entry.value,
                      provider,
                    );
                  },
                ),
              ),
        ],
      ),
    );
  }

  Widget _buildFluentHeader(
    NeteasePlaylistDetail detail,
    BuildContext context,
  ) {
    final theme = fluent.FluentTheme.of(context);
    final resources = theme.resources;
    final typography = theme.typography;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: CachedNetworkImage(
            imageUrl: detail.coverImgUrl,
            width: 120,
            height: 120,
            fit: BoxFit.cover,
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                detail.name,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: (typography?.subtitle ??
                        const TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w600,
                        ))
                    .copyWith(color: resources.textFillColorPrimary),
              ),
              const SizedBox(height: 6),
              Text(
                'by ${detail.creator}',
                style: (typography?.body ?? const TextStyle(fontSize: 14))
                    .copyWith(color: resources.textFillColorSecondary),
              ),
              const SizedBox(height: 6),
              Wrap(
                spacing: 6,
                runSpacing: -6,
                children: detail.tags
                    .map(
                      (t) => Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 6,
                        ),
                        margin: const EdgeInsets.only(bottom: 4),
                        decoration: BoxDecoration(
                          color: theme.resources.controlFillColorDefault,
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Text(
                          t,
                          style: TextStyle(
                            color: theme.resources.textFillColorSecondary,
                            fontSize: 12,
                          ),
                        ),
                      ),
                    )
                    .cast<Widget>()
                    .toList(),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Future<void> _handleTrackTap(
    BuildContext context,
    int index,
    List<Track> allTracks,
  ) async {
    final ok = await _checkLoginStatus();
    if (!ok) return;

    PlaylistQueueService().setQueue(
      allTracks,
      index,
      QueueSource.playlist,
      coverProviders: _coverProviderCache,
    );

    final track = allTracks[index];
    final coverProvider = _coverProviderCache[_coverKey(track)];
    await PlayerService().playTrack(
      track,
      coverProvider: coverProvider,
    );

    if (mounted) {
      fluent.displayInfoBar(
        context,
        builder: (context, close) => fluent.InfoBar(
          title: const Text('播放提示'),
          content: Text('正在加载：${track.name}'),
          action: fluent.IconButton(
            icon: const Icon(fluent.FluentIcons.clear),
            onPressed: close,
          ),
        ),
      );
    }
  }

  // Fluent UI 单曲列表项
  Widget _FluentTrackTile({
    required Track track,
    required int index,
    required VoidCallback onTap,
    required ValueChanged<ImageProvider> onCoverReady,
  }) {
    final theme = fluent.FluentTheme.of(context);
    final resources = theme.resources;

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: fluent.Card(
        borderRadius: BorderRadius.circular(12),
        padding: EdgeInsets.zero,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                SizedBox(
                  width: 32,
                  child: Text(
                    '${index + 1}',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      color: resources.textFillColorSecondary,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: CachedNetworkImage(
                    imageUrl: track.picUrl,
                    width: 64,
                    height: 64,
                    fit: BoxFit.cover,
                    imageBuilder: (context, provider) {
                      onCoverReady(provider);
                      return Image(
                        image: provider,
                        width: 64,
                        height: 64,
                        fit: BoxFit.cover,
                      );
                    },
                    placeholder: (context, url) => Container(
                      width: 64,
                      height: 64,
                      color: theme.resources.controlAltFillColorSecondary,
                      alignment: Alignment.center,
                      child: const fluent.ProgressRing(strokeWidth: 2),
                    ),
                    errorWidget: (context, url, error) => Container(
                      width: 64,
                      height: 64,
                      color: theme.resources.controlAltFillColorSecondary,
                      alignment: Alignment.center,
                      child: fluent.Icon(
                        fluent.FluentIcons.music_in_collection,
                        size: 24,
                        color: resources.textFillColorTertiary,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        track.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 15,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        track.artists,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 13,
                          color: resources.textFillColorSecondary,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        track.album,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12,
                          color: resources.textFillColorTertiary,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                fluent.IconButton(
                  icon: const Icon(fluent.FluentIcons.play),
                  onPressed: onTap,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _scrollToTop() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (_scrollController.hasClients) {
        _scrollController.jumpTo(0);
      }
    });
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  Future<bool> _checkLoginStatus() async {
    if (AuthService().isLoggedIn) return true;
    final themeManager = ThemeManager();
    if (themeManager.isFluentFramework) {
      final shouldLogin = await fluent.showDialog<bool>(
        context: context,
        builder: (context) => fluent.ContentDialog(
          title: const Text('需要登录'),
          content: const Text('此功能需要登录后才能使用，是否前往登录？'),
          actions: [
            fluent.Button(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('取消'),
            ),
            fluent.FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('去登录'),
            ),
          ],
        ),
      );
      if (shouldLogin == true && mounted) {
        final result = await showAuthDialog(context);
        return result == true && AuthService().isLoggedIn;
      }
      return false;
    } else {
      final shouldLogin = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Row(
            children: [
              Icon(Icons.lock_outline, color: Colors.orange),
              SizedBox(width: 8),
              Text('需要登录'),
            ],
          ),
          content: const Text('此功能需要登录后才能使用，是否前往登录？'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('去登录'),
            ),
          ],
        ),
      );
      if (shouldLogin == true && mounted) {
        final result = await showAuthDialog(context);
        return result == true && AuthService().isLoggedIn;
      }
      return false;
    }
  }
}
