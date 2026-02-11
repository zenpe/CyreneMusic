import 'package:cached_network_image/cached_network_image.dart';
import 'package:cyrene_music/models/toplist.dart';
import 'package:cyrene_music/models/track.dart';
import 'package:cyrene_music/services/music_service.dart';
import 'package:cyrene_music/services/play_history_service.dart';
import 'package:cyrene_music/services/player_service.dart';
import 'package:fluent_ui/fluent_ui.dart' as fluent;
import 'package:flutter/material.dart';
import '../../utils/page_visibility_notifier.dart';
import '../../utils/theme_manager.dart';

/// 首页顶部胶囊 Tabs
class HomeCapsuleTabs extends StatelessWidget {
  final List<String> tabs;
  final int currentIndex;
  final ValueChanged<int> onChanged;
  const HomeCapsuleTabs({
    super.key,
    required this.tabs,
    required this.currentIndex,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final bg = cs.surfaceContainerHighest;
    final pillColor = cs.primary;
    final selFg = cs.onPrimary;
    final unSelFg = cs.onSurfaceVariant;

    return LayoutBuilder(
      builder: (context, constraints) {
        final height = 48.0;
        final padding = 5.0;
        final radius = height / 2;
        final totalWidth = constraints.maxWidth;
        final count = tabs.length;
        final tabWidth = totalWidth / count;

        return SizedBox(
          height: height,
          child: Stack(
            children: [
              // 背景容器
              Positioned.fill(
                child: Container(
                  decoration: BoxDecoration(
                    color: bg,
                    borderRadius: BorderRadius.circular(radius),
                  ),
                ),
              ),
              // 滑动胶囊指示器
              AnimatedPositioned(
                duration: const Duration(milliseconds: 280),
                curve: Curves.easeInOutCubic,
                top: padding,
                bottom: padding,
                left: padding + currentIndex * (tabWidth - padding * 2),
                width: tabWidth - padding * 2,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 280),
                  curve: Curves.easeInOutCubic,
                  decoration: BoxDecoration(
                    color: pillColor,
                    borderRadius: BorderRadius.circular(radius - padding),
                    boxShadow: [
                      BoxShadow(
                        color: pillColor.withOpacity(0.25),
                        blurRadius: 10,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                ),
              ),
              // 标签点击与文字
              Row(
                children: List.generate(count, (i) {
                  final selected = i == currentIndex;
                  return SizedBox(
                    width: tabWidth,
                    height: height,
                    child: InkWell(
                      borderRadius: BorderRadius.circular(radius),
                      onTap: () => onChanged(i),
                      child: Center(
                        child: AnimatedDefaultTextStyle(
                          duration: const Duration(milliseconds: 180),
                          curve: Curves.easeInOut,
                          style: TextStyle(
                            color: selected ? selFg : unSelFg,
                            fontWeight: FontWeight.w600,
                          ),
                          child: Text(tabs[i]),
                        ),
                      ),
                    ),
                  );
                }),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// 歌曲轮播图卡片
class TrackBannerCard extends StatelessWidget {
  final Track track;
  final VoidCallback? onTap;

  const TrackBannerCard({super.key, required this.track, this.onTap});

  @override
  Widget build(BuildContext context) {
    final themeManager = ThemeManager();
    final borderRadius = BorderRadius.circular(24);

    final cardContent = Material(
      type: MaterialType.transparency,
      child: InkWell(
        onTap: onTap,
        child: Stack(
          fit: StackFit.expand,
          children: [
            // 封面图片
            CachedNetworkImage(
              imageUrl: track.picUrl,
              fit: BoxFit.cover,
              memCacheWidth: 280,
              memCacheHeight: 280,
              placeholder: (context, url) => Container(
                color: Theme.of(context).colorScheme.surfaceContainerHighest,
                child: const Center(
                  child: SizedBox(
                    width: 32,
                    height: 32,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                ),
              ),
              errorWidget: (context, url, error) => Container(
                color: Theme.of(context).colorScheme.surfaceContainerHighest,
                child: Icon(
                  Icons.music_note,
                  size: 64,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ),
            // 渐变遮罩
            Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Colors.transparent, Colors.black.withOpacity(0.8)],
                ),
              ),
            ),
            // 歌曲信息
            Positioned(
              bottom: 16,
              left: 16,
              right: 16,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 歌曲名称
                  Text(
                    track.name,
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      shadows: [
                        Shadow(
                          offset: const Offset(0, 1),
                          blurRadius: 3.0,
                          color: Colors.black.withOpacity(0.5),
                        ),
                      ],
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),
                  // 艺术家
                  Text(
                    track.artists,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: Colors.white.withOpacity(0.9),
                      shadows: [
                        Shadow(
                          offset: const Offset(0, 1),
                          blurRadius: 3.0,
                          color: Colors.black.withOpacity(0.5),
                        ),
                      ],
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),
                  // 专辑和音乐来源
                  Row(
                    children: [
                      Text(
                        track.getSourceIcon(),
                        style: const TextStyle(
                          fontSize: 12,
                          shadows: [
                            Shadow(
                              offset: Offset(0, 1),
                              blurRadius: 3.0,
                              color: Colors.black54,
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          track.album,
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(
                                color: Colors.white.withOpacity(0.8),
                                shadows: [
                                  Shadow(
                                    offset: const Offset(0, 1),
                                    blurRadius: 3.0,
                                    color: Colors.black.withOpacity(0.5),
                                  ),
                                ],
                              ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            // 播放按钮
            Positioned(
              top: 16,
              right: 16,
              child: Container(
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.primary,
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.3),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: IconButton(
                  icon: const Icon(Icons.play_arrow, color: Colors.white),
                  onPressed: onTap,
                  tooltip: '播放',
                ),
              ),
            ),
          ],
        ),
      ),
    );

    final card = themeManager.isFluentFramework
        ? fluent.Card(
            padding: EdgeInsets.zero,
            borderRadius: borderRadius,
            child: ClipRRect(borderRadius: borderRadius, child: cardContent),
          )
        : Card(clipBehavior: Clip.antiAlias, elevation: 4, child: cardContent);

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 8),
      child: card,
    );
  }
}

class BannerSection extends StatelessWidget {
  final List<Track> cachedRandomTracks;
  final PageController bannerController;
  final int currentBannerIndex;
  final Function(int) onPageChanged;
  final Future<bool> Function() checkLoginStatus;

  const BannerSection({
    super.key,
    required this.cachedRandomTracks,
    required this.bannerController,
    required this.currentBannerIndex,
    required this.onPageChanged,
    required this.checkLoginStatus,
  });

  @override
  Widget build(BuildContext context) {
    if (cachedRandomTracks.isEmpty) return const SizedBox.shrink();

    return LayoutBuilder(
      builder: (context, constraints) {
        // 根据屏幕宽度自适应轮播图高度
        final screenWidth = MediaQuery.of(context).size.width;
        final bannerHeight = (screenWidth * 0.5).clamp(160.0, 220.0);

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '推荐歌曲',
              style: Theme.of(
                context,
              ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            SizedBox(
              height: bannerHeight,
              child: Stack(
                alignment: Alignment.bottomCenter,
                children: [
                  PageView.builder(
                    controller: bannerController,
                    itemCount: cachedRandomTracks.length,
                    onPageChanged: onPageChanged,
                    itemBuilder: (context, index) {
                      final track = cachedRandomTracks[index];
                      return TrackBannerCard(
                        track: track,
                        onTap: () async {
                          // 检查登录状态
                          final isLoggedIn = await checkLoginStatus();
                          if (isLoggedIn && context.mounted) {
                            // 播放歌曲
                            PlayerService().playTrack(track);
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text('正在加载：${track.name}'),
                                duration: const Duration(seconds: 1),
                              ),
                            );
                          }
                        },
                      );
                    },
                  ),
                  // 指示器
                  Positioned(
                    bottom: 12,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: List.generate(
                        cachedRandomTracks.length,
                        (index) => Container(
                          width: 8,
                          height: 8,
                          margin: const EdgeInsets.symmetric(horizontal: 4),
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: currentBannerIndex == index
                                ? Colors.white
                                : Colors.white.withOpacity(0.5),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}

class HistorySection extends StatelessWidget {
  const HistorySection({super.key});

  @override
  Widget build(BuildContext context) {
    final history = PlayHistoryService().history.take(3).toList(); // 只取最近3条
    final themeManager = ThemeManager();

    if (history.isEmpty) {
      return const SizedBox.shrink(); // 如果没有历史，不显示任何东西
    }

    // Material Design Expressive 风格实现
    if (!themeManager.isFluentFramework && !themeManager.isCupertinoFramework) {
      return Card(
        elevation: 0,
        margin: EdgeInsets.zero,
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
        color: Theme.of(context).colorScheme.surfaceContainerHighest.withOpacity(0.6),
        child: Column(
          children: [
            // Header Area - View All
            InkWell(
              onTap: () {
                PageVisibilityNotifier().setCurrentPage(2);
              },
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 10),
                child: Row(
                  children: [
                    Icon(
                      Icons.history_rounded, 
                      size: 20, 
                      color: Theme.of(context).colorScheme.primary
                    ),
                    const SizedBox(width: 8),
                    Text(
                      '最近播放',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: Theme.of(context).colorScheme.onSurface,
                      ),
                    ),
                    const Spacer(),
                    Icon(
                      Icons.arrow_forward_ios_rounded,
                      size: 14,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    )
                  ],
                ),
              ),
            ),
            // Content Area
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 10, 20, 20),
              child: Row(
                children: [
                  // 大封面 - View All
                  InkWell(
                    onTap: () {
                       PageVisibilityNotifier().setCurrentPage(2);
                    },
                    borderRadius: BorderRadius.circular(16),
                    child: Hero(
                      tag: 'history_cover_${history.first.id}',
                      child: Container(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(16),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.1),
                              blurRadius: 10,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(16),
                          child: CachedNetworkImage(
                            imageUrl: history.first.picUrl,
                            width: 88,
                            height: 88,
                            fit: BoxFit.cover,
                            memCacheWidth: 280,
                            memCacheHeight: 280,
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 20),
                  // 歌曲列表 - Play Individual
                  Expanded(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: List.generate(history.length, (index) {
                        final item = history[index];
                        return InkWell(
                          onTap: () async {
                              PlayerService().playTrack(item.toTrack());
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text('正在加载：${item.name}'),
                                  duration: const Duration(seconds: 1),
                                ),
                              );
                          },
                          borderRadius: BorderRadius.circular(8),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(vertical: 6.0, horizontal: 4.0),
                            child: Row(
                              children: [
                                Text(
                                  '${index + 1}',
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 14,
                                    color: index == 0 
                                      ? Theme.of(context).colorScheme.primary 
                                      : Theme.of(context).colorScheme.onSurfaceVariant,
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Text(
                                    item.name,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                      fontWeight: FontWeight.w600,
                                      color: Theme.of(context).colorScheme.onSurface,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 4),
                                ConstrainedBox(
                                  constraints: const BoxConstraints(maxWidth: 60),
                                  child: Text(
                                    item.artists,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      }),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    }

    // 兼容旧版布局 (Cupertino / Fluent)
    final borderRadius = BorderRadius.circular(24);
    final cardContent = Material(
      type: MaterialType.transparency,
      child: InkWell(
        onTap: () {
          PageVisibilityNotifier().setCurrentPage(2);
        },
        child: Padding(
          padding: const EdgeInsets.all(12.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '最近播放',
                style: Theme.of(
                  context,
                ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  // 封面
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: CachedNetworkImage(
                      imageUrl: history.first.picUrl,
                      width: 64,
                      height: 64,
                      fit: BoxFit.cover,
                      memCacheWidth: 280,
                      memCacheHeight: 280,
                    ),
                  ),
                  const SizedBox(width: 12),
                  // 歌曲列表
                  Expanded(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: List.generate(history.length, (index) {
                        final item = history[index];
                        return Padding(
                          padding: const EdgeInsets.symmetric(vertical: 2.0),
                          child: Text.rich(
                            TextSpan(
                              style: Theme.of(context).textTheme.bodySmall,
                              children: [
                                TextSpan(
                                  text: '${index + 1}  ',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                TextSpan(
                                  text: '${item.name} - ${item.artists}',
                                ),
                              ],
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        );
                      }),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );

    if (themeManager.isFluentFramework) {
      return fluent.Card(
        padding: EdgeInsets.zero,
        borderRadius: borderRadius,
        child: ClipRRect(borderRadius: borderRadius, child: cardContent),
      );
    }

    // Cupertino 或者是其他 fallback 情况保持原样
    return Card(
      elevation: 0,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(borderRadius: borderRadius),
      color: Theme.of(context).colorScheme.surfaceContainer,
      child: cardContent,
    );
  }
}

class GuessYouLikeSection extends StatelessWidget {
  final Future<List<Track>>? guessYouLikeFuture;

  const GuessYouLikeSection({super.key, this.guessYouLikeFuture});

  @override
  Widget build(BuildContext context) {
    final themeManager = ThemeManager();
    
    // Material Design Expressive 风格实现
    if (!themeManager.isFluentFramework && !themeManager.isCupertinoFramework) {
       return Card(
        elevation: 0,
        margin: EdgeInsets.zero,
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
        color: Theme.of(context).colorScheme.surfaceContainerHighest.withOpacity(0.6),
        child: Column(
          children: [
            InkWell(
              onTap: () {
                // TODO: 跳转到推荐页面
                print('跳转到推荐页面');
              },
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 10),
                child: Row(
                  children: [
                    Icon(
                      Icons.auto_awesome_rounded, 
                      size: 20, 
                      color: Theme.of(context).colorScheme.primary
                    ),
                    const SizedBox(width: 8),
                    Text(
                      '猜你喜欢',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: Theme.of(context).colorScheme.onSurface,
                      ),
                    ),
                    const Spacer(),
                    Icon(
                      Icons.arrow_forward_ios_rounded,
                      size: 14,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    )
                  ],
                ),
              ),
            ),
            Padding(
               padding: const EdgeInsets.fromLTRB(20, 10, 20, 20),
               child: SizedBox(
                  child: guessYouLikeFuture != null
                      ? _buildExpressiveContent(context)
                      : _buildGuessYouLikePlaceholder(context),
               ),
            )
          ],
        ),
      );
    }

    // 兼容旧版布局 (Cupertino / Fluent)
    final borderRadius = BorderRadius.circular(24);
    final cardContent = Material(
      type: MaterialType.transparency,
      child: InkWell(
        onTap: () {
          print('跳转到推荐页面');
        },
        child: Padding(
          padding: const EdgeInsets.all(12.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '猜你喜欢',
                style: Theme.of(
                  context,
                ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              SizedBox(
                height: 64, // 固定高度防止布局跳动
                child: guessYouLikeFuture != null
                    ? _buildGuessYouLikeContent(context)
                    : _buildGuessYouLikePlaceholder(context, isLegacy: true),
              ),
            ],
          ),
        ),
      ),
    );

    if (themeManager.isFluentFramework) {
      return fluent.Card(
        padding: EdgeInsets.zero,
        borderRadius: borderRadius,
        child: ClipRRect(borderRadius: borderRadius, child: cardContent),
      );
    }

    return Card(
      elevation: 0,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(borderRadius: borderRadius),
      color: Theme.of(context).colorScheme.surfaceContainer,
      child: cardContent,
    );
  }

  Widget _buildExpressiveContent(BuildContext context) {
    return FutureBuilder<List<Track>>(
      future: guessYouLikeFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: Padding(
            padding: EdgeInsets.all(16.0),
            child: CircularProgressIndicator(),
          ));
        }

        if (snapshot.hasError || !snapshot.hasData || snapshot.data!.isEmpty) {
          return _buildGuessYouLikePlaceholder(context, isError: true);
        }

        final sampleTracks = snapshot.data!;

        return Row(
          children: [
            // 大封面
            InkWell(
              onTap: () {
                 // TODO: 跳转到推荐页面
                 print('跳转到推荐页面');
              },
              borderRadius: BorderRadius.circular(16),
              child: Hero(
                tag: 'guess_you_like_cover',
                child: Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.1),
                        blurRadius: 10,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(16),
                    child: CachedNetworkImage(
                      imageUrl: sampleTracks.first.picUrl,
                      width: 88,
                      height: 88,
                      fit: BoxFit.cover,
                      memCacheWidth: 280,
                      memCacheHeight: 280,
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 20),
            // 歌曲列表
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: List.generate(sampleTracks.length, (index) {
                  final track = sampleTracks[index];
                  return InkWell(
                    onTap: () async {
                       PlayerService().playTrack(track);
                       ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text('正在加载：${track.name}'),
                            duration: const Duration(seconds: 1),
                          ),
                       );
                    },
                    borderRadius: BorderRadius.circular(8),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 6.0, horizontal: 4.0),
                      child: Row(
                        children: [
                          Text(
                            '${index + 1}',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 14,
                              color: index == 0 
                                ? Theme.of(context).colorScheme.primary 
                                : Theme.of(context).colorScheme.onSurfaceVariant,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              track.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                fontWeight: FontWeight.w600,
                                color: Theme.of(context).colorScheme.onSurface,
                              ),
                            ),
                          ),
                           const SizedBox(width: 4),
                           ConstrainedBox(
                             constraints: const BoxConstraints(maxWidth: 60),
                             child: Text(
                              track.artists,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                                 style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                color: Theme.of(context).colorScheme.onSurfaceVariant,
                              ),
                             ),
                           ),
                        ],
                      ),
                    ),
                  );
                }),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildGuessYouLikeContent(BuildContext context) {
    return FutureBuilder<List<Track>>(
      future: guessYouLikeFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        if (snapshot.hasError || !snapshot.hasData || snapshot.data!.isEmpty) {
          return _buildGuessYouLikePlaceholder(context, isLegacy: true, isError: true);
        }

        final sampleTracks = snapshot.data!;

        return Row(
          children: [
            // 封面
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: CachedNetworkImage(
                imageUrl: sampleTracks.first.picUrl,
                width: 64,
                height: 64,
                fit: BoxFit.cover,
                memCacheWidth: 280,
                memCacheHeight: 280,
              ),
            ),
            const SizedBox(width: 12),
            // 歌曲列表
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: List.generate(sampleTracks.length, (index) {
                  final track = sampleTracks[index];
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 2.0),
                    child: Text.rich(
                      TextSpan(
                        style: Theme.of(context).textTheme.bodySmall,
                        children: [
                          TextSpan(
                            text: '${index + 1}  ',
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                          TextSpan(text: '${track.name} - ${track.artists}'),
                        ],
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  );
                }),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildGuessYouLikePlaceholder(BuildContext context, {bool isError = false, bool isLegacy = false}) {
    final message = isError ? '加载推荐失败' : '导入歌单查看更多';
    
    // Legacy 风格
    if (isLegacy) {
      return InkWell(
        onTap: () {
          print('引导用户导入歌单');
        },
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(8.0),
            child: Text(
              message,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ),
      );
    }

    // Expressive 风格
    return InkWell(
      onTap: () {
        print('引导用户导入歌单');
      },
      child: Container(
        height: 88,
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainer,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: Theme.of(context).colorScheme.outline.withOpacity(0.1),
          ),
        ),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                isError ? Icons.error_outline : Icons.add_circle_outline,
                color: Theme.of(context).colorScheme.primary,
              ),
              const SizedBox(height: 8),
              Text(
                message,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Theme.of(context).colorScheme.onSurface,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class ToplistsGrid extends StatelessWidget {
  final Future<bool> Function() checkLoginStatus;
  final void Function(Toplist) showToplistDetail;
  const ToplistsGrid({
    super.key,
    required this.checkLoginStatus,
    required this.showToplistDetail,
  });

  @override
  Widget build(BuildContext context) {
    final toplists = MusicService().toplists;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 遍历每个榜单
        for (int i = 0; i < toplists.length; i++) ...[
          _buildToplistSection(context, toplists[i]),
          if (i < toplists.length - 1) const SizedBox(height: 32),
        ],
      ],
    );
  }

  /// 构建单个榜单区域
  Widget _buildToplistSection(BuildContext context, Toplist toplist) {
    return LayoutBuilder(
      builder: (context, constraints) {
        // 根据屏幕宽度自适应卡片高度
        final screenWidth = MediaQuery.of(context).size.width;
        final cardHeight = (screenWidth * 0.55).clamp(200.0, 240.0);

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 榜单标题行
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Text(
                    toplist.name,
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                TextButton(
                  onPressed: () => showToplistDetail(toplist),
                  child: const Text('查看全部'),
                ),
              ],
            ),
            const SizedBox(height: 12),
            // 横向滚动的歌曲卡片
            SizedBox(
              height: cardHeight,
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                itemCount: toplist.tracks.take(10).length, // 只显示前10首
                itemBuilder: (context, index) {
                  final track = toplist.tracks[index];
                  return _buildTrackCard(context, track, index);
                },
              ),
            ),
          ],
        );
      },
    );
  }

  /// 构建歌曲卡片
  Widget _buildTrackCard(BuildContext context, Track track, int rank) {
    final colorScheme = Theme.of(context).colorScheme;
    final themeManager = ThemeManager();

    return LayoutBuilder(
      builder: (context, constraints) {
        // 根据可用高度自适应卡片宽度和封面大小
        final cardHeight = constraints.maxHeight;
        final coverSize = (cardHeight * 0.65).clamp(120.0, 160.0);
        final cardWidth = coverSize;
        var isHovering = false;
        final borderRadius = BorderRadius.circular(12);

        final cardContent = Material(
          type: MaterialType.transparency,
          child: InkWell(
            onTap: () async {
              // 检查登录状态
              final isLoggedIn = await checkLoginStatus();
              if (isLoggedIn && context.mounted) {
                PlayerService().playTrack(track);
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('正在加载：${track.name}'),
                    duration: const Duration(seconds: 1),
                  ),
                );
              }
            },
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 专辑封面
                StatefulBuilder(
                  builder: (context, setHoverState) {
                    return MouseRegion(
                      onEnter: (_) => setHoverState(() => isHovering = true),
                      onExit: (_) => setHoverState(() => isHovering = false),
                      child: Stack(
                        children: [
                          AnimatedScale(
                            scale: isHovering ? 1.1 : 1.0,
                            duration: const Duration(milliseconds: 180),
                            curve: Curves.easeOut,
                            child: CachedNetworkImage(
                              imageUrl: track.picUrl,
                              width: coverSize,
                              height: coverSize,
                              fit: BoxFit.cover,
                              memCacheWidth: 280,
                              memCacheHeight: 280,
                              placeholder: (context, url) => Container(
                                width: coverSize,
                                height: coverSize,
                                color: colorScheme.surfaceContainerHighest,
                                child: const Center(
                                  child: SizedBox(
                                    width: 24,
                                    height: 24,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  ),
                                ),
                              ),
                              errorWidget: (context, url, error) => Container(
                                width: coverSize,
                                height: coverSize,
                                color: colorScheme.surfaceContainerHighest,
                                child: Icon(
                                  Icons.music_note,
                                  size: coverSize * 0.3,
                                  color: colorScheme.onSurfaceVariant,
                                ),
                              ),
                            ),
                          ),
                          // 排名标签
                          Positioned(
                            top: 4,
                            left: 4,
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: rank < 3
                                    ? colorScheme.primary
                                    : colorScheme.secondaryContainer,
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                '${rank + 1}',
                                style: TextStyle(
                                  color: rank < 3
                                      ? colorScheme.onPrimary
                                      : colorScheme.onSecondaryContainer,
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ),
                          // 播放按钮覆盖层（悬停时显示）
                          Positioned.fill(
                            child: IgnorePointer(
                              ignoring: true,
                              child: AnimatedOpacity(
                                opacity: isHovering ? 1.0 : 0.0,
                                duration: const Duration(milliseconds: 150),
                                child: Container(
                                  color: Colors.black.withOpacity(0),
                                  child: Center(
                                    child: Icon(
                                      Icons.play_arrow,
                                      size: coverSize * 0.28,
                                      color: Colors.white.withOpacity(0.95),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
                // 歌曲信息 - 使用 Expanded 而不是固定高度，避免溢出
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.all(8.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          track.name,
                          style: Theme.of(context).textTheme.bodyMedium
                              ?.copyWith(fontWeight: FontWeight.w500),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 2),
                        Text(
                          track.artists,
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(color: colorScheme.onSurfaceVariant),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        );

        final card = themeManager.isFluentFramework
            ? fluent.Card(
                padding: EdgeInsets.zero,
                borderRadius: borderRadius,
                child: ClipRRect(
                  borderRadius: borderRadius,
                  child: cardContent,
                ),
              )
            : Card(
                clipBehavior: Clip.antiAlias,
                color: colorScheme.surfaceContainer,
                child: cardContent,
              );

        return Container(
          width: cardWidth,
          margin: const EdgeInsets.only(right: 12),
          child: card,
        );
      },
    );
  }
}

class LoadingSection extends StatelessWidget {
  const LoadingSection({super.key});

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Padding(
        padding: EdgeInsets.all(64.0),
        child: Column(
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text('正在加载榜单...'),
          ],
        ),
      ),
    );
  }
}

class ErrorSection extends StatelessWidget {
  const ErrorSection({super.key});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final themeManager = ThemeManager();

    final cardContent = Padding(
      padding: const EdgeInsets.all(48.0),
      child: Column(
        children: [
          Icon(Icons.error_outline, size: 64, color: colorScheme.error),
          const SizedBox(height: 16),
          Text('加载失败', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 8),
          Text(
            MusicService().errorMessage ?? '未知错误',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: colorScheme.onSurfaceVariant,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 24),
          FilledButton.icon(
            onPressed: () {
              MusicService().refreshToplists();
            },
            icon: const Icon(Icons.refresh),
            label: const Text('重试'),
          ),
        ],
      ),
    );

    if (themeManager.isFluentFramework) {
      return fluent.Card(padding: EdgeInsets.zero, child: cardContent);
    }

    return Card(color: colorScheme.surfaceContainer, child: cardContent);
  }
}

class EmptySection extends StatelessWidget {
  const EmptySection({super.key});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final themeManager = ThemeManager();

    final cardContent = Padding(
      padding: const EdgeInsets.all(48.0),
      child: Column(
        children: [
          Icon(Icons.music_note, size: 64, color: colorScheme.onSurfaceVariant),
          const SizedBox(height: 16),
          Text('暂无榜单', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 8),
          Text(
            '请检查后端服务是否正常',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 24),
          FilledButton.icon(
            onPressed: () {
              MusicService().fetchToplists();
            },
            icon: const Icon(Icons.refresh),
            label: const Text('刷新'),
          ),
        ],
      ),
    );

    if (themeManager.isFluentFramework) {
      return fluent.Card(padding: EdgeInsets.zero, child: cardContent);
    }

    return Card(color: colorScheme.surfaceContainer, child: cardContent);
  }
}
