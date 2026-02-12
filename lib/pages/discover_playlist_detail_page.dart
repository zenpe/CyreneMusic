import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:fluent_ui/fluent_ui.dart' as fluent;
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter_acrylic/flutter_acrylic.dart';
import '../services/netease_discover_service.dart';
import '../models/netease_discover.dart';
import '../models/track.dart';
import '../models/playlist.dart';
import '../widgets/track_list_tile.dart';
import '../services/playlist_queue_service.dart';
import '../services/player_service.dart';
import '../services/auth_service.dart';
import '../pages/auth/auth_page.dart';
import '../utils/theme_manager.dart';
import '../services/api/api_client.dart';
import '../services/playlist_service.dart';

class DiscoverPlaylistDetailPage extends StatelessWidget {
  final int playlistId;
  final GlobalKey<_DiscoverPlaylistDetailContentState> _contentKey =
      GlobalKey<_DiscoverPlaylistDetailContentState>();
  DiscoverPlaylistDetailPage({super.key, required this.playlistId});

  @override
  Widget build(BuildContext context) {
    final baseTheme = Theme.of(context);

    return Theme(
      data: _discoverPlaylistFontTheme(baseTheme),
      child: Builder(
        builder: (context) {
          final isExpressive = !ThemeManager().isFluentFramework && 
                              !ThemeManager().isCupertinoFramework && 
                              (Platform.isAndroid || Platform.isIOS);
          return Scaffold(
            backgroundColor: isExpressive ? Theme.of(context).colorScheme.surfaceContainerLow : Theme.of(context).colorScheme.surface,
            appBar: isExpressive ? null : AppBar(
              backgroundColor: Colors.transparent,
              surfaceTintColor: Colors.transparent,
              elevation: 0,
              scrolledUnderElevation: 0,
              systemOverlayStyle: SystemUiOverlayStyle(
                statusBarColor: Colors.transparent,
                statusBarIconBrightness:
                    Theme.of(context).brightness == Brightness.dark
                        ? Brightness.light
                        : Brightness.dark,
                statusBarBrightness: Theme.of(context).brightness,
              ),
              title: const Text('歌单详情'),
              actions: [
                IconButton(
                  icon: const Icon(Icons.sync),
                  tooltip: '同步到本地歌单',
                  onPressed: () =>
                      _contentKey.currentState?._syncToLocal(context, playlistId),
                ),
              ],
            ),

            body: DiscoverPlaylistDetailContent(
              key: _contentKey,
              playlistId: playlistId,
            ),
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
  bool _descExpanded = false;

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

    // iOS / Cupertino 风格
    if ((Platform.isIOS || Platform.isAndroid) && themeManager.isCupertinoFramework) {
      return _buildCupertinoDetail(context);
    }

    // 移动端 Material Design Expressive 风格
    if (Platform.isIOS || Platform.isAndroid) {
      return _buildMaterialExpressiveDetail(context);
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
                Hero(
                  tag: 'playlist_cover_${widget.playlistId}',
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: CachedNetworkImage(
                      imageUrl: detail.coverImgUrl,
                      width: 120,
                      height: 120,
                      fit: BoxFit.cover,
                    ),
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
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          FilledButton.icon(
                            onPressed: () => _syncToLocal(context, widget.playlistId),
                            icon: const Icon(Icons.sync),
                            label: const Text('同步到本地歌单'),
                          ),
                        ],
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

  Future<void> _syncToLocal(BuildContext context, int neteasePlaylistId) async {
    if (!await _checkLoginStatus()) return;
    final playlistService = PlaylistService();
    if (playlistService.playlists.isEmpty) {
      await playlistService.loadPlaylists();
    }
    if (!mounted) return;
    final target = await showDialog<Playlist>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('选择目标歌单'),
        content: SizedBox(
          width: 420,
          height: 360,
          child: ListView.builder(
            itemCount: playlistService.playlists.length,
            itemBuilder: (context, index) {
              final p = playlistService.playlists[index];
              return ListTile(
                leading: Icon(p.isDefault ? Icons.favorite : Icons.queue_music),
                title: Text(p.name),
                subtitle: Text('${p.trackCount} 首'),
                onTap: () => Navigator.pop(context, p),
              );
            },
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('取消')),
        ],
      ),
    );
    if (target == null) return;
    try {
      final api = ApiClient();
      final putResp = await api.putJson(
        '/playlists/${target.id}/import-config',
        data: {'source': 'netease', 'sourcePlaylistId': '$neteasePlaylistId'},
        timeout: const Duration(seconds: 20),
      );
      if (!putResp.ok) {
        throw Exception('绑定来源失败: HTTP ${putResp.statusCode}');
      }
      final postResp = await api.postJson(
        '/playlists/${target.id}/sync',
        timeout: const Duration(minutes: 2),
      );
      if (!postResp.ok) {
        throw Exception('同步失败: HTTP ${postResp.statusCode}');
      }
      if (!mounted) return;
      fluent.displayInfoBar(
        context,
        builder: (context, close) => fluent.InfoBar(
          title: const Text('已开始同步'),
          content: Text('目标歌单：${target.name}'),
          action: fluent.IconButton(icon: const Icon(fluent.FluentIcons.clear), onPressed: close),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      final themeManager = ThemeManager();
      if (themeManager.isFluentFramework) {
        await fluent.showDialog(
          context: context,
          builder: (context) => fluent.ContentDialog(
            title: const Text('同步失败'),
            content: Text('$e'),
            actions: [
              fluent.FilledButton(onPressed: () => Navigator.pop(context), child: const Text('确定')),
            ],
          ),
        );
      } else {
        await showDialog(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('同步失败'),
            content: Text('$e'),
            actions: [
              TextButton(onPressed: () => Navigator.pop(context), child: const Text('确定')),
            ],
          ),
        );
      }
    }
  }

  // ============ Cupertino (iOS 26) 风格实现 ============

  Widget _buildCupertinoDetail(BuildContext context) {
    final isDark = CupertinoTheme.brightnessOf(context) == Brightness.dark;

    if (_loading) {
      return Container(
        color: isDark ? const Color(0xFF000000) : CupertinoColors.systemGroupedBackground,
        child: const Center(child: CupertinoActivityIndicator(radius: 16)),
      );
    }

    if (_error != null) {
      return Container(
        color: isDark ? const Color(0xFF000000) : CupertinoColors.systemGroupedBackground,
        padding: const EdgeInsets.all(24),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(CupertinoIcons.exclamationmark_circle,
                  size: 48, color: CupertinoColors.systemRed),
              const SizedBox(height: 16),
              Text(
                _error!,
                style: TextStyle(
                  color: isDark ? CupertinoColors.white : CupertinoColors.black,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              CupertinoButton(
                child: const Text('重试'),
                onPressed: _load,
              ),
            ],
          ),
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

    return Container(
      color: isDark ? const Color(0xFF000000) : CupertinoColors.systemGroupedBackground,
      child: CustomScrollView(
        controller: _scrollController,
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          // iOS 风格的下拉刷新
          CupertinoSliverRefreshControl(
            onRefresh: _load,
          ),
          // 歌单头部信息
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: _buildCupertinoHeader(detail, isDark),
            ),
          ),
          // 歌单描述
          if (detail.description.isNotEmpty)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: isDark ? const Color(0xFF1C1C1E) : CupertinoColors.white,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    detail.description,
                    maxLines: 4,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 14,
                      color: CupertinoColors.systemGrey,
                      height: 1.5,
                    ),
                  ),
                ),
              ),
            ),
          // 歌曲统计和播放按钮
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: _buildCupertinoStatsBar(tracks.length, isDark),
            ),
          ),
          // 歌曲列表
          SliverPadding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            sliver: SliverList(
              delegate: SliverChildBuilderDelegate(
                (context, index) {
                  final track = tracks[index];
                  return _buildCupertinoTrackTile(
                    track: track,
                    index: index,
                    isDark: isDark,
                    onTap: () => _handleCupertinoTrackTap(context, index, tracks),
                    onCoverReady: (provider) {
                      final key = _coverKey(track);
                      _coverProviderCache[key] = provider;
                      PlaylistQueueService().updateCoverProvider(track, provider);
                    },
                  );
                },
                childCount: tracks.length,
              ),
            ),
          ),
          // 底部留白
          const SliverToBoxAdapter(
            child: SizedBox(height: 100),
          ),
        ],
      ),
    );
  }

  Widget _buildCupertinoHeader(NeteasePlaylistDetail detail, bool isDark) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1C1C1E) : CupertinoColors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: CupertinoColors.black.withOpacity(isDark ? 0.3 : 0.05),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 歌单封面
          Hero(
            tag: 'playlist_cover_${detail.id}', // Use detail.id or widget.playlistId, ensuring they match
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: CachedNetworkImage(
                imageUrl: detail.coverImgUrl,
                width: 120,
                height: 120,
                memCacheWidth: 280,
                memCacheHeight: 280,
                fit: BoxFit.cover,
                placeholder: (context, url) => Container(
                  width: 120,
                  height: 120,
                  color: isDark ? const Color(0xFF2C2C2E) : CupertinoColors.systemGrey6,
                  child: const CupertinoActivityIndicator(),
                ),
                errorWidget: (context, url, error) => Container(
                  width: 120,
                  height: 120,
                  color: isDark ? const Color(0xFF2C2C2E) : CupertinoColors.systemGrey6,
                  child: const Icon(CupertinoIcons.music_note_2,
                      size: 40, color: CupertinoColors.systemGrey),
                ),
              ),
            ),
          ),
          const SizedBox(width: 16),
          // 歌单信息
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  detail.name,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: isDark ? CupertinoColors.white : CupertinoColors.black,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'by ${detail.creator}',
                  style: const TextStyle(
                    fontSize: 14,
                    color: CupertinoColors.systemGrey,
                  ),
                ),
                const SizedBox(height: 8),
                // 标签
                if (detail.tags.isNotEmpty)
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: detail.tags
                        .map(
                          (t) => Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(
                              color: CupertinoColors.systemBlue.withOpacity(0.1),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Text(
                              t,
                              style: const TextStyle(
                                color: CupertinoColors.systemBlue,
                                fontSize: 12,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                        )
                        .toList(),
                  ),
                const SizedBox(height: 12),
                // 同步按钮
                CupertinoButton(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  color: CupertinoColors.systemBlue,
                  borderRadius: BorderRadius.circular(18),
                  onPressed: () => _syncToLocalCupertino(context, widget.playlistId),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(CupertinoIcons.arrow_2_circlepath, size: 16, color: CupertinoColors.white),
                      SizedBox(width: 6),
                      Text('同步到本地', style: TextStyle(fontSize: 14, color: CupertinoColors.white)),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCupertinoStatsBar(int trackCount, bool isDark) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1C1C1E) : CupertinoColors.white,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          const Icon(CupertinoIcons.music_note, size: 22, color: CupertinoColors.systemBlue),
          const SizedBox(width: 12),
          Text(
            '共 $trackCount 首歌曲',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: isDark ? CupertinoColors.white : CupertinoColors.black,
            ),
          ),
          const Spacer(),
          if (trackCount > 0)
            CupertinoButton(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              color: CupertinoColors.systemBlue,
              borderRadius: BorderRadius.circular(18),
              onPressed: () => _playCupertinoAll(context),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(CupertinoIcons.play_fill, size: 16, color: CupertinoColors.white),
                  SizedBox(width: 6),
                  Text('播放全部', style: TextStyle(fontSize: 14, color: CupertinoColors.white)),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildCupertinoTrackTile({
    required Track track,
    required int index,
    required bool isDark,
    required VoidCallback onTap,
    required ValueChanged<ImageProvider> onCoverReady,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1C1C1E) : CupertinoColors.white,
        borderRadius: BorderRadius.circular(12),
      ),
      child: CupertinoButton(
        padding: EdgeInsets.zero,
        onPressed: onTap,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              // 专辑封面
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: CachedNetworkImage(
                  imageUrl: track.picUrl,
                  memCacheWidth: 128,
                  memCacheHeight: 128,
                  width: 56,
                  height: 56,
                  fit: BoxFit.cover,
                  imageBuilder: (context, provider) {
                    onCoverReady(provider);
                    return Image(
                      image: provider,
                      width: 56,
                      height: 56,
                      fit: BoxFit.cover,
                    );
                  },
                  placeholder: (context, url) => Container(
                    width: 56,
                    height: 56,
                    color: isDark ? const Color(0xFF2C2C2E) : CupertinoColors.systemGrey6,
                    child: const Center(child: CupertinoActivityIndicator(radius: 10)),
                  ),
                  errorWidget: (context, url, error) => Container(
                    width: 56,
                    height: 56,
                    color: isDark ? const Color(0xFF2C2C2E) : CupertinoColors.systemGrey6,
                    child: const Icon(CupertinoIcons.music_note, size: 24, color: CupertinoColors.systemGrey),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              // 歌曲信息
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      track.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w500,
                        color: isDark ? CupertinoColors.white : CupertinoColors.black,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      track.artists,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 14,
                        color: CupertinoColors.systemGrey,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      track.album,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12,
                        color: CupertinoColors.systemGrey.withOpacity(0.8),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _handleCupertinoTrackTap(
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
      // iOS 风格的提示
      showCupertinoModalPopup(
        context: context,
        builder: (context) => Container(
          margin: const EdgeInsets.all(16),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          decoration: BoxDecoration(
            color: CupertinoColors.systemGrey6.darkColor,
            borderRadius: BorderRadius.circular(14),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(CupertinoIcons.music_note, color: CupertinoColors.white, size: 18),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  '正在加载：${track.name}',
                  style: const TextStyle(color: CupertinoColors.white, fontSize: 14),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
      );
      // 自动关闭提示
      Future.delayed(const Duration(seconds: 2), () {
        if (mounted && Navigator.of(context).canPop()) {
          Navigator.of(context).pop();
        }
      });
    }
  }

  Future<void> _playCupertinoAll(BuildContext context) async {
    final ok = await _checkLoginStatus();
    if (!ok) return;

    if (_detail == null || _detail!.tracks.isEmpty) return;

    final tracks = _detail!.tracks
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

    PlaylistQueueService().setQueue(
      tracks,
      0,
      QueueSource.playlist,
      coverProviders: _coverProviderCache,
    );

    final track = tracks.first;
    final coverProvider = _coverProviderCache[_coverKey(track)];
    await PlayerService().playTrack(
      track,
      coverProvider: coverProvider,
    );
  }

  Future<void> _syncToLocalCupertino(BuildContext context, int neteasePlaylistId) async {
    if (!await _checkLoginStatus()) return;

    final playlistService = PlaylistService();
    if (playlistService.playlists.isEmpty) {
      await playlistService.loadPlaylists();
    }
    if (!mounted) return;

    // iOS 风格的歌单选择对话框
    final target = await showCupertinoModalPopup<Playlist>(
      context: context,
      builder: (context) => Material(
        type: MaterialType.transparency,
        child: Container(
          height: MediaQuery.of(context).size.height * 0.6,
          decoration: BoxDecoration(
            color: CupertinoTheme.brightnessOf(context) == Brightness.dark
                ? const Color(0xFF1C1C1E)
                : CupertinoColors.white,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
          ),
          child: Column(
            children: [
              // 标题栏
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                decoration: BoxDecoration(
                  border: Border(
                    bottom: BorderSide(
                      color: CupertinoColors.systemGrey4,
                      width: 0.5,
                    ),
                  ),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    CupertinoButton(
                      padding: EdgeInsets.zero,
                      onPressed: () => Navigator.pop(context),
                      child: const Text('取消'),
                    ),
                    Text(
                      '选择目标歌单',
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w600,
                        color: CupertinoTheme.brightnessOf(context) == Brightness.dark
                            ? CupertinoColors.white
                            : CupertinoColors.black,
                      ),
                    ),
                    const SizedBox(width: 50),
                  ],
                ),
              ),
              // 歌单列表
              Expanded(
                child: ListView.separated(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  itemCount: playlistService.playlists.length,
                  separatorBuilder: (_, __) => Padding(
                    padding: const EdgeInsets.only(left: 72),
                    child: Container(height: 0.5, color: CupertinoColors.systemGrey4),
                  ),
                  itemBuilder: (context, index) {
                    final p = playlistService.playlists[index];
                    final isDark = CupertinoTheme.brightnessOf(context) == Brightness.dark;
                    return CupertinoButton(
                      padding: EdgeInsets.zero,
                      onPressed: () => Navigator.pop(context, p),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                        child: Row(
                          children: [
                            Container(
                              width: 48,
                              height: 48,
                              decoration: BoxDecoration(
                                color: isDark ? const Color(0xFF2C2C2E) : CupertinoColors.systemGrey5,
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Icon(
                                p.isDefault ? CupertinoIcons.heart_fill : CupertinoIcons.music_albums,
                                color: p.isDefault ? CupertinoColors.systemRed : CupertinoColors.systemBlue,
                                size: 22,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    p.name,
                                    style: TextStyle(
                                      fontSize: 16,
                                      color: isDark ? CupertinoColors.white : CupertinoColors.black,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    '${p.trackCount} 首',
                                    style: const TextStyle(
                                      fontSize: 14,
                                      color: CupertinoColors.systemGrey,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const Icon(CupertinoIcons.chevron_forward,
                                size: 18, color: CupertinoColors.systemGrey3),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );

    if (target == null) return;

    try {
      final api = ApiClient();
      final putResp = await api.putJson(
        '/playlists/${target.id}/import-config',
        data: {'source': 'netease', 'sourcePlaylistId': '$neteasePlaylistId'},
        timeout: const Duration(seconds: 20),
      );
      if (!putResp.ok) {
        throw Exception('绑定来源失败: HTTP ${putResp.statusCode}');
      }
      final postResp = await api.postJson(
        '/playlists/${target.id}/sync',
        timeout: const Duration(minutes: 2),
      );
      if (!postResp.ok) {
        throw Exception('同步失败: HTTP ${postResp.statusCode}');
      }
      if (!mounted) return;

      // iOS 风格的成功提示
      showCupertinoDialog(
        context: context,
        builder: (context) => CupertinoAlertDialog(
          title: const Text('同步成功'),
          content: Text('已开始同步到「${target.name}」'),
          actions: [
            CupertinoDialogAction(
              isDefaultAction: true,
              onPressed: () => Navigator.pop(context),
              child: const Text('好的'),
            ),
          ],
        ),
      );
    } catch (e) {
      if (!mounted) return;

      // iOS 风格的错误提示
      showCupertinoDialog(
        context: context,
        builder: (context) => CupertinoAlertDialog(
          title: const Text('同步失败'),
          content: Text('$e'),
          actions: [
            CupertinoDialogAction(
              isDefaultAction: true,
              onPressed: () => Navigator.pop(context),
              child: const Text('确定'),
            ),
          ],
        ),
      );
    }
  }

  // ============ Material Design Expressive 风格实现 ============

  Widget _buildMaterialExpressiveDetail(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    if (_loading) {
      return Container(
        color: cs.surface,
        child: const Center(child: CircularProgressIndicator()),
      );
    }

    if (_error != null) {
      return Container(
        color: cs.surface,
        padding: const EdgeInsets.all(24),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.error_outline, size: 48, color: cs.error),
              const SizedBox(height: 16),
              Text(
                _error!,
                style: TextStyle(color: cs.onSurface),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: _load,
                icon: const Icon(Icons.refresh),
                label: const Text('重试'),
              ),
            ],
          ),
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

    return Container(
      color: cs.surfaceContainerLow,
      child: RefreshIndicator(
        onRefresh: _load,
        child: CustomScrollView(
          controller: _scrollController,
          physics: const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics()),
          slivers: [
            // Pinned SliverAppBar (Expressive)
            SliverAppBar(
              pinned: true,
              expandedHeight: 300,
              collapsedHeight: 72,
              backgroundColor: cs.surfaceContainerLow,
              surfaceTintColor: cs.surfaceContainerLow,
              leading: IconButton(
                icon: const Icon(Icons.arrow_back_rounded),
                onPressed: () => Navigator.pop(context),
              ),
              actions: [
                IconButton(
                  icon: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: cs.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(Icons.sync_rounded),
                  ),
                  tooltip: '同步到本地歌单',
                  onPressed: () => _syncToLocal(context, widget.playlistId),
                ),
                const SizedBox(width: 8),
              ],
              flexibleSpace: FlexibleSpaceBar(
                title: _buildMaterialExpressivePinnedTitle(detail, cs, isDark),
                titlePadding: EdgeInsets.zero,
                background: Stack(
                  fit: StackFit.expand,
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 90, 16, 16),
                      child: _buildMaterialExpressiveHeader(detail, cs, isDark),
                    ),
                  ],
                ),
              ),
            ),
            // 歌单描述与标签 (修复溢出)
            _buildMaterialExpressiveDescriptionSliver(detail, cs, isDark),

            // 歌曲统计栏
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                child: _buildMaterialExpressiveStatsBar(context, tracks.length, tracks, cs),
              ),
            ),
            // 歌曲列表
            SliverPadding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              sliver: SliverList(
                delegate: SliverChildBuilderDelegate(
                  (context, index) {
                    final track = tracks[index];
                    return _buildMaterialExpressiveTrackTile(
                      track: track,
                      index: index,
                      cs: cs,
                      isDark: isDark,
                      onTap: () => _handleMaterialTrackTap(context, index, tracks),
                      onCoverReady: (provider) {
                        final key = _coverKey(track);
                        _coverProviderCache[key] = provider;
                        PlaylistQueueService().updateCoverProvider(track, provider);
                      },
                    );
                  },
                  childCount: tracks.length,
                ),
              ),
            ),
            // 底部留白
            const SliverToBoxAdapter(
              child: SizedBox(height: 100),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMaterialExpressivePinnedTitle(
    NeteasePlaylistDetail detail,
    ColorScheme cs,
    bool isDark,
  ) {
    return LayoutBuilder(
      builder: (context, constraints) {
        // 当收缩到一定程度 (72 左右) 时显示标题
        final bool isCollapsed = constraints.maxHeight <= 100;

        return Container(
          padding: const EdgeInsets.only(left: 56, bottom: 16),
          alignment: Alignment.bottomLeft,
          child: AnimatedOpacity(
            duration: const Duration(milliseconds: 200),
            opacity: isCollapsed ? 1.0 : 0.0,
            child: Text(
              detail.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: cs.onSurface,
                fontSize: 18,
                fontWeight: FontWeight.w900,
                letterSpacing: -0.5,
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildMaterialExpressiveHeader(
    NeteasePlaylistDetail detail,
    ColorScheme cs,
    bool isDark,
  ) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            cs.surfaceContainerHigh,
            cs.surfaceContainerHighest.withOpacity(0.8),
          ],
        ),
        borderRadius: BorderRadius.circular(32),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(isDark ? 0.3 : 0.08),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 歌单封面
          Hero(
            tag: 'playlist_cover_${detail.id}',
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(24),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.15),
                    blurRadius: 12,
                    offset: const Offset(0, 6),
                  ),
                ],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(24),
                child: CachedNetworkImage(
                  imageUrl: detail.coverImgUrl,
                  width: 140,
                  height: 140,
                  memCacheWidth: 280,
                  memCacheHeight: 280,
                  fit: BoxFit.cover,
                  placeholder: (context, url) => Container(
                    width: 140,
                    height: 140,
                    color: cs.surfaceContainerHighest,
                    child: const Center(child: CircularProgressIndicator()),
                  ),
                  errorWidget: (context, url, error) => Container(
                    width: 140,
                    height: 140,
                    color: cs.surfaceContainerHighest,
                    child: Icon(
                      Icons.music_note,
                      size: 48,
                      color: cs.onSurface.withOpacity(0.3),
                    ),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 20),
          // 歌单信息
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  detail.name,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.w900,
                    color: cs.onSurface,
                    letterSpacing: -0.5,
                    height: 1.2,
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Icon(Icons.person_outline, size: 16, color: cs.primary),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        detail.creator,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                          color: cs.primary,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                // 同步按钮
                FilledButton.icon(
                  onPressed: () => _syncToLocal(context, widget.playlistId),
                  icon: const Icon(Icons.sync, size: 16),
                  label: const Text('同步到本地'),
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 8,
                    ),
                    minimumSize: const Size(0, 36),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// 详情描述（解决溢出的关键：将不确定长度的内容移出固定高度的 AppBar）
  Widget _buildMaterialExpressiveDescriptionSliver(
    NeteasePlaylistDetail detail,
    ColorScheme cs,
    bool isDark,
  ) {
    if (detail.tags.isEmpty && detail.description.isEmpty) {
      return const SliverToBoxAdapter(child: SizedBox.shrink());
    }

    return SliverToBoxAdapter(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: cs.surfaceContainerHigh.withOpacity(0.5),
            borderRadius: BorderRadius.circular(24),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (detail.tags.isNotEmpty) ...[
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: detail.tags
                      .map(
                        (t) => Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 5,
                          ),
                          decoration: BoxDecoration(
                            color: cs.primaryContainer.withOpacity(0.6),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                            t,
                            style: TextStyle(
                              color: cs.onPrimaryContainer,
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      )
                      .toList(),
                ),
                if (detail.description.isNotEmpty) const SizedBox(height: 12),
              ],
              if (detail.description.isNotEmpty) ...[
                Text(
                  detail.description,
                  maxLines: _descExpanded ? null : 2,
                  overflow: _descExpanded ? TextOverflow.visible : TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 14,
                    color: cs.onSurface.withOpacity(0.7),
                    height: 1.5,
                  ),
                ),
                const SizedBox(height: 4),
                Align(
                  alignment: Alignment.centerRight,
                  child: InkWell(
                    onTap: () {
                      setState(() {
                        _descExpanded = !_descExpanded;
                      });
                    },
                    borderRadius: BorderRadius.circular(8),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      child: Text(
                        _descExpanded ? '收起' : '更多',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: cs.primary,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  /// 歌曲统计栏（包含快捷播放）
  Widget _buildMaterialExpressiveStatsBar(
    BuildContext context,
    int trackCount,
    List<Track> allTracks,
    ColorScheme cs,
  ) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(24),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: cs.primaryContainer,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(
              Icons.music_note,
              size: 20,
              color: cs.onPrimaryContainer,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '共 $trackCount 首',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    color: cs.onSurface,
                  ),
                ),
                Text(
                  '点击即刻聆听',
                  style: TextStyle(
                    fontSize: 11,
                    color: cs.onSurface.withOpacity(0.5),
                  ),
                ),
              ],
            ),
          ),
          if (trackCount > 0)
            FilledButton.icon(
              onPressed: () async {
                final ok = await _checkLoginStatus();
                if (!ok) return;
                PlaylistQueueService().setQueue(
                  allTracks,
                  0,
                  QueueSource.playlist,
                  coverProviders: _coverProviderCache,
                );
                await PlayerService().playTrack(allTracks.first);
              },
              icon: const Icon(Icons.play_arrow_rounded, size: 20),
              label: const Text('播放全部'),
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildMaterialExpressiveTrackTile({
    required Track track,
    required int index,
    required ColorScheme cs,
    required bool isDark,
    required VoidCallback onTap,
    required ValueChanged<ImageProvider> onCoverReady,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(20),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                // 专辑封面
                Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(14),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.1),
                        blurRadius: 6,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(14),
                    child: CachedNetworkImage(
                      imageUrl: track.picUrl,
                      memCacheWidth: 128,
                      memCacheHeight: 128,
                      width: 56,
                      height: 56,
                      fit: BoxFit.cover,
                      imageBuilder: (context, provider) {
                        onCoverReady(provider);
                        return Image(
                          image: provider,
                          width: 56,
                          height: 56,
                          fit: BoxFit.cover,
                        );
                      },
                      placeholder: (context, url) => Container(
                        width: 56,
                        height: 56,
                        color: cs.surfaceContainerHighest,
                        child: const Center(
                          child: SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                        ),
                      ),
                      errorWidget: (context, url, error) => Container(
                        width: 56,
                        height: 56,
                        color: cs.surfaceContainerHighest,
                        child: Icon(
                          Icons.music_note,
                          size: 24,
                          color: cs.onSurface.withOpacity(0.3),
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 14),
                // 歌曲信息
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        track.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: cs.onSurface,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        track.artists,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 14,
                          color: cs.onSurface.withOpacity(0.7),
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        track.album,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12,
                          color: cs.onSurface.withOpacity(0.5),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _handleMaterialTrackTap(
    BuildContext context,
    int index,
    List<Track> allTracks,
  ) async {
    final ok = await _checkLoginStatus();
    if (!ok) return;

    final track = allTracks[index];
    PlaylistQueueService().setQueue(
      allTracks,
      index,
      QueueSource.playlist,
      coverProviders: _coverProviderCache,
    );

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
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      );
    }
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

    final useWindowEffect =
        Platform.isWindows && ThemeManager().windowEffect != WindowEffect.disabled;

    final listView = fluent.ScrollConfiguration(
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

    return Container(
      color: useWindowEffect
          ? Colors.transparent
          : fluent.FluentTheme.of(context).micaBackgroundColor,
      child: listView,
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
              const SizedBox(height: 12),
              Row(
                children: [
                  fluent.FilledButton(
                    onPressed: () => _syncToLocal(context, widget.playlistId),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(fluent.FluentIcons.sync),
                        SizedBox(width: 6),
                        Text('同步到本地歌单'),
                      ],
                    ),
                  ),
                ],
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
                    memCacheWidth: 128,
                    memCacheHeight: 128,
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

    // Fluent UI 风格
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
    }

    // Cupertino (iOS) 风格
    if ((Platform.isIOS || Platform.isAndroid) && themeManager.isCupertinoFramework) {
      final shouldLogin = await showCupertinoDialog<bool>(
        context: context,
        builder: (context) => CupertinoAlertDialog(
          title: const Text('需要登录'),
          content: const Text('此功能需要登录后才能使用，是否前往登录？'),
          actions: [
            CupertinoDialogAction(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('取消'),
            ),
            CupertinoDialogAction(
              isDefaultAction: true,
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

    // Material 风格 (默认)
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
