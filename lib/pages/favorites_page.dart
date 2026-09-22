import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../features/auth/auth_feature.dart';
import '../services/favorite_service.dart';
import '../services/player_service.dart';
import '../services/playlist_queue_service.dart';
import '../models/track.dart';

/// 我的收藏页面
class FavoritesPage extends StatefulWidget {
  const FavoritesPage({super.key});

  @override
  State<FavoritesPage> createState() => _FavoritesPageState();
}

class _FavoritesPageState extends State<FavoritesPage>
    with AutomaticKeepAliveClientMixin {
  final AuthFacade _authFacade = AuthFacade();
  final FavoriteService _favoriteService = FavoriteService();

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _favoriteService.addListener(_onFavoritesChanged);

    // 加载收藏列表
    if (_authFacade.isLoggedIn) {
      _favoriteService.loadFavorites();
    }
  }

  @override
  void dispose() {
    _favoriteService.removeListener(_onFavoritesChanged);
    super.dispose();
  }

  void _onFavoritesChanged() {
    if (mounted) {
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final colorScheme = Theme.of(context).colorScheme;

    // 检查登录状态
    if (!_authFacade.isLoggedIn) {
      return Scaffold(
        backgroundColor: colorScheme.surface,
        body: CustomScrollView(
          slivers: [
            _buildAppBar(colorScheme),
            SliverFillRemaining(
              child: _buildLoginPrompt(colorScheme),
            ),
          ],
        ),
      );
    }

    final favorites = _favoriteService.favorites;
    final isLoading = _favoriteService.isLoading;

    return Scaffold(
      backgroundColor: colorScheme.surface,
      body: CustomScrollView(
        slivers: [
          // 顶部标题栏
          _buildAppBar(colorScheme),

          // 加载状态
          if (isLoading && favorites.isEmpty)
            const SliverFillRemaining(
              child: Center(
                child: CircularProgressIndicator(),
              ),
            )
          // 收藏列表
          else if (favorites.isEmpty)
            SliverFillRemaining(
              child: _buildEmptyState(colorScheme),
            )
          else ...[
            // 统计信息
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: _buildStatisticsCard(colorScheme, favorites.length),
              ),
            ),

            // 收藏列表
            SliverPadding(
              padding: const EdgeInsets.symmetric(horizontal: 16.0),
              sliver: SliverList(
                delegate: SliverChildBuilderDelegate(
                  (context, index) {
                    final item = favorites[index];
                    return _buildFavoriteItem(item, index, colorScheme);
                  },
                  childCount: favorites.length,
                ),
              ),
            ),

            // 底部留白
            const SliverToBoxAdapter(
              child: SizedBox(height: 16),
            ),
          ],
        ],
      ),
    );
  }

  /// 构建顶部栏
  Widget _buildAppBar(ColorScheme colorScheme) {
    return SliverAppBar(
      floating: true,
      snap: true,
      backgroundColor: colorScheme.surface,
      title: Text(
        '我的收藏',
        style: TextStyle(
          color: colorScheme.onSurface,
          fontSize: 24,
          fontWeight: FontWeight.bold,
        ),
      ),
      actions: [
        IconButton(
          icon: const Icon(Icons.refresh),
          onPressed: () {
            if (_authFacade.isLoggedIn) {
              _favoriteService.loadFavorites();
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('正在刷新...'),
                  duration: Duration(seconds: 1),
                ),
              );
            }
          },
          tooltip: '刷新',
        ),
      ],
    );
  }

  /// 构建统计信息卡片
  Widget _buildStatisticsCard(ColorScheme colorScheme, int count) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Row(
          children: [
            Icon(
              Icons.favorite,
              size: 24,
              color: colorScheme.primary,
            ),
            const SizedBox(width: 12),
            Text(
              '共收藏 $count 首歌曲',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
            ),
          ],
        ),
      ),
    );
  }

  /// 构建收藏项
  Widget _buildFavoriteItem(
      FavoriteTrack item, int index, ColorScheme colorScheme) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: Stack(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: CachedNetworkImage(
                imageUrl: item.picUrl,
                memCacheWidth: 128,
                memCacheHeight: 128,
                width: 50,
                height: 50,
                fit: BoxFit.cover,
                placeholder: (context, url) => Container(
                  width: 50,
                  height: 50,
                  color: colorScheme.surfaceContainerHighest,
                  child: const Center(
                    child: SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  ),
                ),
                errorWidget: (context, url, error) => Container(
                  width: 50,
                  height: 50,
                  color: colorScheme.surfaceContainerHighest,
                  child: Icon(
                    Icons.music_note,
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            ),
            // 序号标记
            Positioned(
              bottom: 0,
              right: 0,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                decoration: BoxDecoration(
                  color: colorScheme.primaryContainer,
                  borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(4),
                  ),
                ),
                child: Text(
                  '#${index + 1}',
                  style: TextStyle(
                    color: colorScheme.onPrimaryContainer,
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
          ],
        ),
        title: Text(
          item.name,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: Row(
          children: [
            Expanded(
              child: Text(
                '${item.artists} • ${item.album}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
            const SizedBox(width: 8),
            Text(
              _getSourceIcon(item.source),
              style: const TextStyle(fontSize: 12),
            ),
          ],
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              icon: const Icon(Icons.play_arrow),
              onPressed: () {
                _playFromFavorites(index);
              },
              tooltip: '播放',
            ),
            IconButton(
              icon: const Icon(Icons.favorite, size: 20),
              color: Colors.redAccent,
              onPressed: () async {
                await _favoriteService.removeFavorite(item.toTrack());
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('已取消收藏'),
                      duration: Duration(seconds: 1),
                    ),
                  );
                }
              },
              tooltip: '取消收藏',
            ),
          ],
        ),
        onTap: () {
          _playFromFavorites(index);
        },
      ),
    );
  }

  /// 从收藏列表播放
  void _playFromFavorites(int index) {
    final favorites = _favoriteService.favorites;
    if (favorites.isEmpty) return;

    // 将收藏列表转换为 Track 列表
    final trackList = favorites.map((f) => f.toTrack()).toList();

    // 设置播放队列
    PlaylistQueueService().setQueue(
      trackList,
      index,
      QueueSource.favorites,
    );

    // 播放选中的歌曲
    PlayerService().playTrack(trackList[index]);
  }

  /// 获取音乐平台图标
  String _getSourceIcon(MusicSource source) {
    switch (source) {
      case MusicSource.netease:
        return '🎵';
      case MusicSource.apple:
        return '🍎';
      case MusicSource.qq:
        return '🎶';
      case MusicSource.kugou:
        return '🎼';
      case MusicSource.kuwo:
        return '🎸';
      case MusicSource.navidrome:
        return '🎧';
      case MusicSource.spotify:
        return '🟢';
      case MusicSource.local:
        return '📁';
    }
  }

  /// 构建空状态
  Widget _buildEmptyState(ColorScheme colorScheme) {
    final theme = Theme.of(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.hasBoundedHeight && constraints.maxHeight < 180;
        final minHeight = constraints.hasBoundedHeight ? constraints.maxHeight : 0.0;
        return SingleChildScrollView(
          physics: const ClampingScrollPhysics(),
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: minHeight),
            child: Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.favorite_border,
                      size: compact ? 56 : 80,
                      color: colorScheme.onSurfaceVariant.withValues(alpha: 0.3),
                    ),
                    SizedBox(height: compact ? 10 : 16),
                    Text(
                      '暂无收藏',
                      textAlign: TextAlign.center,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleLarge?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '在播放器中点击爱心即可收藏歌曲',
                      textAlign: TextAlign.center,
                      maxLines: compact ? 1 : 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: colorScheme.onSurfaceVariant.withValues(alpha: 0.7),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  /// 构建登录提示
  Widget _buildLoginPrompt(ColorScheme colorScheme) {
    final theme = Theme.of(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.hasBoundedHeight && constraints.maxHeight < 180;
        final minHeight = constraints.hasBoundedHeight ? constraints.maxHeight : 0.0;
        return SingleChildScrollView(
          physics: const ClampingScrollPhysics(),
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: minHeight),
            child: Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.login,
                      size: compact ? 56 : 80,
                      color: colorScheme.onSurfaceVariant.withValues(alpha: 0.3),
                    ),
                    SizedBox(height: compact ? 10 : 16),
                    Text(
                      '请先登录',
                      textAlign: TextAlign.center,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleLarge?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '登录后即可使用收藏功能',
                      textAlign: TextAlign.center,
                      maxLines: compact ? 1 : 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: colorScheme.onSurfaceVariant.withValues(alpha: 0.7),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

