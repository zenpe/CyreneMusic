import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:fluent_ui/fluent_ui.dart' as fluent;
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter_acrylic/flutter_acrylic.dart';
import '../../services/player_service.dart';
import '../../services/playlist_queue_service.dart';
import '../../models/track.dart';
import '../../utils/theme_manager.dart';

/// 每日推荐详情页
class DailyRecommendDetailPage extends StatelessWidget {
  final List<Map<String, dynamic>> tracks;
  final bool embedded;
  final VoidCallback? onClose;
  final bool showHeader;

  const DailyRecommendDetailPage({
    super.key,
    required this.tracks,
    this.embedded = false,
    this.onClose,
    this.showHeader = true,
  });

  @override
  Widget build(BuildContext context) {
    final themeManager = ThemeManager();

    if (themeManager.isFluentFramework) {
      return _FluentDailyRecommendPage(
        tracks: tracks,
        embedded: embedded,
        onClose: onClose,
        showHeader: showHeader,
      );
    }

    final baseTheme = Theme.of(context);

    return Theme(
      data: _dailyRecommendFontTheme(baseTheme),
      child: Builder(
        builder: (context) {
          final colorScheme = Theme.of(context).colorScheme;

          if (embedded) {
            // 覆盖层嵌入模式：Material Expressive 风格
            return Container(
              color: colorScheme.surfaceContainerLow,
              child: SafeArea(
                bottom: false,
                child: Column(
                  children: [
                    if (showHeader) ...[
                      // Expressive 风格的顶部栏
                      Container(
                        margin: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 8,
                        ),
                        decoration: BoxDecoration(
                          color: colorScheme.surfaceContainerHigh,
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Row(
                          children: [
                            IconButton(
                              icon: Container(
                                padding: const EdgeInsets.all(8),
                                decoration: BoxDecoration(
                                  color: colorScheme.surfaceContainerHighest,
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Icon(
                                  Icons.arrow_back_rounded,
                                  size: 20,
                                  color: colorScheme.onSurfaceVariant,
                                ),
                              ),
                              onPressed: () {
                                if (onClose != null) {
                                  onClose!();
                                } else {
                                  Navigator.of(context).pop();
                                }
                              },
                              tooltip: '返回',
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    '每日推荐',
                                    style: TextStyle(
                                      fontSize: 18,
                                      fontWeight: FontWeight.w800,
                                      color: colorScheme.onSurface,
                                      letterSpacing: -0.3,
                                    ),
                                  ),
                                  Text(
                                    '为您精选 ${tracks.length} 首',
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: colorScheme.onSurfaceVariant,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            if (tracks.isNotEmpty)
                              FilledButton.icon(
                                onPressed: () => _playAll(context),
                                icon: const Icon(Icons.play_arrow_rounded, size: 18),
                                label: const Text('播放'),
                                style: FilledButton.styleFrom(
                                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(14),
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ],
                    Expanded(
                      child: PrimaryScrollController.none(
                        child: tracks.isEmpty
                            ? _buildEmptyState(colorScheme)
                            : ListView.builder(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 16.0,
                                  vertical: 8.0,
                                ),
                                itemCount: tracks.length,
                                itemBuilder: (context, index) => _buildExpressiveTrackTile(
                                  context,
                                  tracks[index],
                                  index,
                                  colorScheme,
                                ),
                              ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          }

          // 独立页面模式 - Material Expressive 风格
          return Scaffold(
            backgroundColor: colorScheme.surfaceContainerLow,
            body: CustomScrollView(
              physics: const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics()),
              slivers: [
                // Expressive 风格的 SliverAppBar
                SliverAppBar(
                  pinned: true,
                  expandedHeight: 220,
                  collapsedHeight: 72,
                  backgroundColor: colorScheme.surfaceContainerLow,
                  surfaceTintColor: colorScheme.surfaceContainerLow,
                  systemOverlayStyle: SystemUiOverlayStyle(
                    statusBarColor: Colors.transparent,
                    statusBarIconBrightness:
                        Theme.of(context).brightness == Brightness.dark
                            ? Brightness.light
                            : Brightness.dark,
                    statusBarBrightness: Theme.of(context).brightness,
                  ),
                  leading: Padding(
                    padding: const EdgeInsets.only(left: 8),
                    child: IconButton(
                      icon: Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: colorScheme.surfaceContainerHighest,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Icon(Icons.arrow_back_rounded, color: colorScheme.onSurfaceVariant),
                      ),
                      onPressed: () {
                        if (onClose != null) {
                          onClose!();
                        } else {
                          Navigator.of(context).pop();
                        }
                      },
                    ),
                  ),
                  flexibleSpace: FlexibleSpaceBar(
                    title: _buildExpressivePinnedTitle(colorScheme),
                    titlePadding: EdgeInsets.zero,
                    background: Stack(
                      fit: StackFit.expand,
                      children: [
                        Padding(
                          padding: const EdgeInsets.fromLTRB(16, 90, 16, 16),
                          child: _buildExpressiveHeader(colorScheme),
                        ),
                      ],
                    ),
                  ),
                ),
                // 统计栏
                if (tracks.isNotEmpty)
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: _buildExpressiveStatsBar(context, colorScheme),
                    ),
                  ),
                // 歌曲列表
                tracks.isEmpty
                    ? SliverFillRemaining(child: _buildEmptyState(colorScheme))
                    : SliverPadding(
                        padding: const EdgeInsets.symmetric(horizontal: 16.0),
                        sliver: SliverList(
                          delegate: SliverChildBuilderDelegate(
                            (context, index) => _buildExpressiveTrackTile(
                              context,
                              tracks[index],
                              index,
                              colorScheme,
                            ),
                            childCount: tracks.length,
                          ),
                        ),
                      ),
                // 底部留白
                const SliverToBoxAdapter(child: SizedBox(height: 100)),
              ],
            ),
          );
        },
      ),
    );
  }

  // ============ Material Expressive 风格辅助方法 ============


  /// 空状态
  Widget _buildEmptyState(ColorScheme cs) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(28),
            decoration: BoxDecoration(
              color: cs.surfaceContainerHighest.withOpacity(0.5),
              borderRadius: BorderRadius.circular(32),
            ),
            child: Icon(Icons.music_off_rounded, size: 64, color: cs.onSurface.withOpacity(0.4)),
          ),
          const SizedBox(height: 24),
          Text(
            '暂无推荐',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w800,
              color: cs.onSurface.withOpacity(0.7),
              letterSpacing: -0.3,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '稍后再来看看吧',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w500,
              color: cs.onSurface.withOpacity(0.5),
            ),
          ),
        ],
      ),
    );
  }

  /// 独立页面模式的固定标题
  Widget _buildExpressivePinnedTitle(ColorScheme cs) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final bool isCollapsed = constraints.maxHeight <= 100;
        return Container(
          padding: const EdgeInsets.only(left: 56, bottom: 16),
          alignment: Alignment.bottomLeft,
          child: AnimatedOpacity(
            duration: const Duration(milliseconds: 200),
            opacity: isCollapsed ? 1.0 : 0.0,
            child: Text(
              '每日推荐',
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

  /// 独立页面模式的头部卡片
  Widget _buildExpressiveHeader(ColorScheme cs) {
    final isDark = cs.brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHigh.withOpacity(0.8),
        borderRadius: BorderRadius.circular(32),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(isDark ? 0.3 : 0.05),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Row(
        children: [
          _buildExpressiveDateCard(cs),
          const SizedBox(width: 20),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '每日推荐',
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.w900,
                    color: cs.onSurface,
                    letterSpacing: -0.5,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '根据你的口味生成，每日6:00更新',
                  style: TextStyle(
                    fontSize: 12,
                    color: cs.onSurface.withOpacity(0.6),
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// 构建日期卡片
  Widget _buildExpressiveDateCard(ColorScheme cs) {
    return Container(
      width: 80,
      height: 80,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [cs.primary, cs.primary.withOpacity(0.7)],
        ),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: cs.primary.withOpacity(0.3),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              '${DateTime.now().day}',
              style: TextStyle(
                fontSize: 32,
                fontWeight: FontWeight.w900,
                color: cs.onPrimary,
                height: 1,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              _getWeekdayName(DateTime.now().weekday),
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: cs.onPrimary.withOpacity(0.9),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 获取星期名称
  String _getWeekdayName(int weekday) {
    const weekdays = ['周一', '周二', '周三', '周四', '周五', '周六', '周日'];
    return weekdays[weekday - 1];
  }

  /// 统计栏
  Widget _buildExpressiveStatsBar(BuildContext context, ColorScheme cs) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            cs.surfaceContainerHigh,
            cs.surfaceContainerHighest.withOpacity(0.8),
          ],
        ),
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: cs.primaryContainer,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(Icons.music_note_rounded, size: 22, color: cs.onPrimaryContainer),
          ),
          const SizedBox(width: 16),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '共 ${tracks.length} 首歌曲',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: cs.onSurface,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                '点击歌曲开始播放',
                style: TextStyle(
                  fontSize: 12,
                  color: cs.onSurface.withOpacity(0.6),
                ),
              ),
            ],
          ),
          const Spacer(),
          FilledButton.icon(
            onPressed: () => _playAll(context),
            icon: const Icon(Icons.play_arrow_rounded, size: 20),
            label: const Text('播放全部', style: TextStyle(fontWeight: FontWeight.w700)),
            style: FilledButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            ),
          ),
        ],
      ),
    );
  }


  /// Expressive 风格歌曲列表项
  Widget _buildExpressiveTrackTile(
    BuildContext context,
    Map<String, dynamic> song,
    int index,
    ColorScheme cs,
  ) {
    final album = (song['al'] ?? song['album'] ?? {}) as Map<String, dynamic>;
    final artists = (song['ar'] ?? song['artists'] ?? []) as List<dynamic>;
    final picUrl = (album['picUrl'] ?? '').toString();
    final artistsText = artists
        .map((e) => (e as Map<String, dynamic>)['name']?.toString() ?? '')
        .where((e) => e.isNotEmpty)
        .join(' / ');
    final songName = song['name']?.toString() ?? '';
    final albumName = album['name']?.toString() ?? '';

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () => _playSong(context, song, index),
          borderRadius: BorderRadius.circular(20),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                // 封面 + 序号角标
                Stack(
                  children: [
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
                          imageUrl: picUrl,
                          width: 56,
                          height: 56,
                          memCacheWidth: 128,
                          memCacheHeight: 128,
                          fit: BoxFit.cover,
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
                            child: Icon(Icons.music_note, size: 24, color: cs.onSurface.withOpacity(0.3)),
                          ),
                        ),
                      ),
                    ),
                    // 序号角标
                    Positioned(
                      bottom: 0,
                      right: 0,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: cs.primary,
                          borderRadius: const BorderRadius.only(
                            topLeft: Radius.circular(8),
                            bottomRight: Radius.circular(14),
                          ),
                        ),
                        child: Text(
                          '#${index + 1}',
                          style: TextStyle(
                            color: cs.onPrimary,
                            fontSize: 10,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(width: 16),
                // 歌曲信息
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        songName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                          color: cs.onSurface,
                          letterSpacing: -0.3,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '$artistsText${albumName.isNotEmpty ? ' • $albumName' : ''}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 13,
                          color: cs.onSurfaceVariant.withOpacity(0.8),
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
                // 更多按钮
                IconButton(
                  icon: Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: cs.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(Icons.more_horiz, size: 18, color: cs.onSurfaceVariant),
                  ),
                  onPressed: () => _showTrackMenu(context, song),
                  tooltip: '更多',
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// 构建歌曲列表项
  Widget _buildTrackTile(
    BuildContext context,
    Map<String, dynamic> song,
    int index,
  ) {
    final colorScheme = Theme.of(context).colorScheme;
    final album = (song['al'] ?? song['album'] ?? {}) as Map<String, dynamic>;
    final artists = (song['ar'] ?? song['artists'] ?? []) as List<dynamic>;
    final picUrl = (album['picUrl'] ?? '').toString();
    final artistsText = artists
        .map((e) => (e as Map<String, dynamic>)['name']?.toString() ?? '')
        .where((e) => e.isNotEmpty)
        .join(' / ');
    final songName = song['name']?.toString() ?? '';
    final songId = song['id'];

    return Card(
      margin: const EdgeInsets.only(bottom: 8.0),
      color: colorScheme.surfaceContainerHighest.withOpacity(0.3),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => _playSong(context, song, index),
        child: Padding(
          padding: const EdgeInsets.all(12.0),
          child: Row(
            children: [
              // 序号
              SizedBox(
                width: 32,
                child: Text(
                  '${index + 1}',
                  style: TextStyle(
                    color: colorScheme.onSurface.withOpacity(0.6),
                    fontWeight: FontWeight.w600,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
              const SizedBox(width: 12),
              // 封面
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: CachedNetworkImage(
                  imageUrl: picUrl,
                  width: 56,
                  height: 56,
                  memCacheWidth: 128,
                  memCacheHeight: 128,
                  fit: BoxFit.cover,
                  placeholder: (context, url) => Container(
                    color: colorScheme.surfaceContainerHighest,
                    child: Icon(
                      Icons.music_note,
                      color: colorScheme.onSurface.withOpacity(0.3),
                    ),
                  ),
                  errorWidget: (context, url, error) => Container(
                    color: colorScheme.surfaceContainerHighest,
                    child: Icon(
                      Icons.broken_image,
                      color: colorScheme.onSurface.withOpacity(0.3),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 16),
              // 歌曲信息
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      songName,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: colorScheme.onSurface,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      artistsText,
                      style: TextStyle(
                        fontSize: 13,
                        color: colorScheme.onSurface.withOpacity(0.6),
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              // 操作按钮
              IconButton(
                icon: const Icon(Icons.more_vert),
                onPressed: () => _showTrackMenu(context, song),
                tooltip: '更多',
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 播放单曲
  void _playSong(
    BuildContext context,
    Map<String, dynamic> song,
    int index,
  ) async {
    try {
      final track = _convertToTrack(song);
      final allTracks = tracks.map((s) => _convertToTrack(s)).toList();

      // 设置播放队列
      PlaylistQueueService().setQueue(allTracks, index, QueueSource.playlist);

      // 播放歌曲
      await PlayerService().playTrack(track);

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('开始播放: ${track.name}'),
            duration: const Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('播放失败: $e'),
            duration: const Duration(seconds: 2),
          ),
        );
      }
    }
  }

  /// 播放全部
  void _playAll(BuildContext context) async {
    if (tracks.isEmpty) return;

    try {
      final allTracks = tracks.map((s) => _convertToTrack(s)).toList();

      // 设置播放队列
      PlaylistQueueService().setQueue(allTracks, 0, QueueSource.playlist);

      // 播放第一首
      await PlayerService().playTrack(allTracks.first);

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('开始播放全部'),
            duration: Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('播放失败: $e'),
            duration: const Duration(seconds: 2),
          ),
        );
      }
    }
  }

  /// 显示歌曲菜单
  void _showTrackMenu(BuildContext context, Map<String, dynamic> song) {
    showModalBottomSheet(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.playlist_add),
              title: const Text('添加到播放队列'),
              onTap: () {
                Navigator.pop(context);
                try {
                  final track = _convertToTrack(song);
                  final currentQueue = PlaylistQueueService().queue;
                  final newQueue = [...currentQueue, track];
                  PlaylistQueueService().setQueue(
                    newQueue,
                    PlaylistQueueService().currentIndex,
                    QueueSource.playlist,
                  );
                  ScaffoldMessenger.of(
                    context,
                  ).showSnackBar(const SnackBar(content: Text('已添加到播放队列')));
                } catch (e) {
                  ScaffoldMessenger.of(
                    context,
                  ).showSnackBar(SnackBar(content: Text('添加失败: $e')));
                }
              },
            ),
            ListTile(
              leading: const Icon(Icons.favorite_border),
              title: const Text('收藏'),
              onTap: () {
                Navigator.pop(context);
                ScaffoldMessenger.of(
                  context,
                ).showSnackBar(const SnackBar(content: Text('收藏功能开发中...')));
              },
            ),
          ],
        ),
      ),
    );
  }

  /// 转换为 Track 对象
  Track _convertToTrack(Map<String, dynamic> song) {
    final album = (song['al'] ?? song['album'] ?? {}) as Map<String, dynamic>;
    final artists = (song['ar'] ?? song['artists'] ?? []) as List<dynamic>;

    return Track(
      id: song['id'] ?? 0,
      name: song['name']?.toString() ?? '',
      artists: artists
          .map((e) => (e as Map<String, dynamic>)['name']?.toString() ?? '')
          .where((e) => e.isNotEmpty)
          .join(' / '),
      album: album['name']?.toString() ?? '',
      picUrl: album['picUrl']?.toString() ?? '',
      source: MusicSource.netease,
    );
  }
}

class _FluentBreadcrumbNode {
  final int index;
  final String label;

  const _FluentBreadcrumbNode(this.index, this.label);
}

class _FluentDailyRecommendPage extends StatelessWidget {
  final List<Map<String, dynamic>> tracks;
  final bool embedded;
  final VoidCallback? onClose;
  final bool showHeader;

  const _FluentDailyRecommendPage({
    required this.tracks,
    this.embedded = false,
    this.onClose,
    this.showHeader = true,
  });

  @override
  Widget build(BuildContext context) {
    final fluentTheme = fluent.FluentTheme.of(context);
    final useWindowEffect =
        Platform.isWindows && ThemeManager().windowEffect != WindowEffect.disabled;
    return fluent.ScaffoldPage(
      header: showHeader
          ? fluent.PageHeader(
              leading: embedded
                  ? fluent.IconButton(
                      icon: const Icon(fluent.FluentIcons.back, size: 20),
                      onPressed: () {
                        if (onClose != null) {
                          onClose!();
                        } else {
                          Navigator.of(context).pop();
                        }
                      },
                    )
                  : null,
              title: _buildHeaderTitle(context),
              commandBar: fluent.CommandBar(
                mainAxisAlignment: fluent.MainAxisAlignment.end,
                primaryItems: [
                  fluent.CommandBarButton(
                    icon: const Icon(fluent.FluentIcons.play),
                    label: const Text('播放全部'),
                    onPressed: () => _playAll(context),
                  ),
                ],
              ),
            )
          : null,
      content: Container(
        color: useWindowEffect
            ? Colors.transparent
            : fluentTheme.micaBackgroundColor,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 12),
            Expanded(
              child: tracks.isEmpty
                  ? const Center(child: Text('暂无推荐歌曲'))
                  : fluent.ListView.builder(
                      itemCount: tracks.length,
                      itemBuilder: (context, index) {
                        return _buildFluentTrackTile(
                          context,
                          tracks[index],
                          index,
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeaderTitle(BuildContext context) {
    const breadcrumbNodes = [
      _FluentBreadcrumbNode(0, '首页'),
      _FluentBreadcrumbNode(1, '每日推荐'),
    ];

    final theme = fluent.FluentTheme.of(context);
    final typography = theme.typography;
    final resources = theme.resources;

    final homeStyle =
        (typography?.subtitle ??
                const TextStyle(fontSize: 26, fontWeight: FontWeight.w600))
            .copyWith(
              fontSize: 26,
              fontWeight: FontWeight.w600,
              color: resources.textFillColorPrimary,
            );

    final crumbBaseStyle =
        (typography?.body ??
                const TextStyle(fontSize: 16, fontWeight: FontWeight.w500))
            .copyWith(
              fontSize: 16,
              fontWeight: FontWeight.w500,
              color: resources.textFillColorSecondary,
            );

    final crumbCurrentStyle = homeStyle;

    final trailingCrumbs = <Widget>[];
    for (var i = 1; i < breadcrumbNodes.length; i++) {
      final node = breadcrumbNodes[i];
      final isLast = i == breadcrumbNodes.length - 1;

      trailingCrumbs.add(_buildChevronIcon(theme));
      trailingCrumbs.add(
        _buildBreadcrumbButton(
          context,
          node,
          style: isLast ? crumbCurrentStyle : crumbBaseStyle,
          isCurrent: isLast,
        ),
      );
    }

    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        _buildBreadcrumbButton(
          context,
          breadcrumbNodes.first,
          style: homeStyle,
          isCurrent: false,
          isEmphasized: true,
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Wrap(
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 6,
            runSpacing: 6,
            children: trailingCrumbs,
          ),
        ),
      ],
    );
  }

  Widget _buildBreadcrumbButton(
    BuildContext context,
    _FluentBreadcrumbNode node, {
    required TextStyle style,
    required bool isCurrent,
    bool isEmphasized = false,
  }) {
    if (isCurrent) {
      return Text(node.label, style: style);
    }

    return fluent.HyperlinkButton(
      onPressed: () => _handleBreadcrumbTap(context, node.index),
      child: Text(
        node.label,
        style: style.copyWith(
          decoration: isEmphasized
              ? TextDecoration.none
              : TextDecoration.underline,
        ),
      ),
    );
  }

  Widget _buildChevronIcon(fluent.FluentThemeData theme) {
    return Icon(
      fluent.FluentIcons.chevron_right,
      size: 10,
      color: theme.resources.textFillColorTertiary,
    );
  }

  void _handleBreadcrumbTap(BuildContext context, int index) {
    if (index == 0) {
      if (onClose != null) {
        onClose!();
      } else if (Navigator.canPop(context)) {
        Navigator.pop(context);
      }
    }
  }

  Widget _buildFluentTrackTile(
    BuildContext context,
    Map<String, dynamic> song,
    int index,
  ) {
    final theme = fluent.FluentTheme.of(context);
    final album = (song['al'] ?? song['album'] ?? {}) as Map<String, dynamic>;
    final artists = (song['ar'] ?? song['artists'] ?? []) as List<dynamic>;
    final picUrl = (album['picUrl'] ?? '').toString();
    final artistsText = artists
        .map((e) => (e as Map<String, dynamic>)['name']?.toString() ?? '')
        .where((e) => e.isNotEmpty)
        .join(' / ');
    final songName = song['name']?.toString() ?? '';

    final cover = ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: picUrl.isEmpty
          ? Container(
              width: 48,
              height: 48,
              color: theme.resources.controlAltFillColorSecondary,
              alignment: Alignment.center,
              child: fluent.Icon(
                fluent.FluentIcons.music_in_collection,
                size: 20,
                color: theme.resources.textFillColorTertiary,
              ),
            )
          : CachedNetworkImage(
              imageUrl: picUrl,
              width: 48,
              height: 48,
              memCacheWidth: 128,
              memCacheHeight: 128,
              fit: BoxFit.cover,
              placeholder: (context, url) => Container(
                width: 48,
                height: 48,
                color: theme.resources.controlAltFillColorSecondary,
                alignment: Alignment.center,
                child: const SizedBox(
                  width: 18,
                  height: 18,
                  child: fluent.ProgressRing(strokeWidth: 2),
                ),
              ),
              errorWidget: (context, url, error) => Container(
                width: 48,
                height: 48,
                color: theme.resources.controlAltFillColorSecondary,
                alignment: Alignment.center,
                child: fluent.Icon(
                  fluent.FluentIcons.music_in_collection,
                  size: 20,
                  color: theme.resources.textFillColorTertiary,
                ),
              ),
            ),
    );

    return fluent.ListTile(
      leading: SizedBox(
        width: 120,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 32,
              child: Text(
                '${index + 1}',
                textAlign: fluent.TextAlign.center,
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
            ),
            const SizedBox(width: 8),
            cover,
          ],
        ),
      ),
      title: Text(
        songName,
        style: const TextStyle(fontWeight: FontWeight.w600),
      ),
      subtitle: Text(artistsText),
      trailing: fluent.Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          fluent.IconButton(
            icon: const Icon(fluent.FluentIcons.play),
            onPressed: () => _playSong(context, song, index),
          ),
          fluent.IconButton(
            icon: const Icon(fluent.FluentIcons.more),
            onPressed: () => _showTrackMenu(context, song),
          ),
        ],
      ),
      onPressed: () => _playSong(context, song, index),
    );
  }

  /// 播放单曲
  void _playSong(
    BuildContext context,
    Map<String, dynamic> song,
    int index,
  ) async {
    try {
      final track = _convertToTrack(song);
      final allTracks = tracks.map((s) => _convertToTrack(s)).toList();

      // 设置播放队列
      PlaylistQueueService().setQueue(allTracks, index, QueueSource.playlist);

      // 播放歌曲
      await PlayerService().playTrack(track);
    } catch (e) {
      // Handle error
    }
  }

  /// 播放全部
  void _playAll(BuildContext context) async {
    if (tracks.isEmpty) return;

    try {
      final allTracks = tracks.map((s) => _convertToTrack(s)).toList();

      // 设置播放队列
      PlaylistQueueService().setQueue(allTracks, 0, QueueSource.playlist);

      // 播放第一首
      await PlayerService().playTrack(allTracks.first);
    } catch (e) {
      // Handle error
    }
  }

  /// 显示歌曲菜单
  void _showTrackMenu(BuildContext context, Map<String, dynamic> song) {
    fluent.showDialog(
      context: context,
      builder: (dialogContext) {
        return fluent.ContentDialog(
          title: const Text('更多操作'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              fluent.Button(
                onPressed: () {
                  Navigator.of(dialogContext).pop();
                  try {
                    final track = _convertToTrack(song);
                    final currentQueue = PlaylistQueueService().queue;
                    final newQueue = [...currentQueue, track];
                    PlaylistQueueService().setQueue(
                      newQueue,
                      PlaylistQueueService().currentIndex,
                      QueueSource.playlist,
                    );
                  } catch (e) {
                    // handle error
                  }
                },
                child: const Align(
                  alignment: Alignment.centerLeft,
                  child: Text('添加到播放队列'),
                ),
              ),
              const SizedBox(height: 8),
              fluent.Button(
                onPressed: () {
                  Navigator.of(dialogContext).pop();
                  // TODO: 收藏功能
                },
                child: const Align(
                  alignment: Alignment.centerLeft,
                  child: Text('收藏'),
                ),
              ),
            ],
          ),
          actions: [
            fluent.Button(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('关闭'),
            ),
          ],
        );
      },
    );
  }

  /// 转换为 Track 对象
  Track _convertToTrack(Map<String, dynamic> song) {
    final album = (song['al'] ?? song['album'] ?? {}) as Map<String, dynamic>;
    final artists = (song['ar'] ?? song['artists'] ?? []) as List<dynamic>;

    return Track(
      id: song['id'] ?? 0,
      name: song['name']?.toString() ?? '',
      artists: artists
          .map((e) => (e as Map<String, dynamic>)['name']?.toString() ?? '')
          .where((e) => e.isNotEmpty)
          .join(' / '),
      album: album['name']?.toString() ?? '',
      picUrl: album['picUrl']?.toString() ?? '',
      source: MusicSource.netease,
    );
  }
}

ThemeData _dailyRecommendFontTheme(ThemeData base) {
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
