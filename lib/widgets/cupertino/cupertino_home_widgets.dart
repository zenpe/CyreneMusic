import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import '../../models/track.dart';
import '../../models/toplist.dart';
import '../../services/music_service.dart';
import '../../services/play_history_service.dart';
import '../../services/player_service.dart';
import '../../utils/theme_manager.dart';
import '../skeleton_loader.dart';

/// iOS 风格的分段控制器（替代胶囊 Tabs）
/// 采用轻量纯文字样式，更符合 iOS 原生设计
class CupertinoHomeSegmentedControl extends StatelessWidget {
  final List<String> tabs;
  final int currentIndex;
  final ValueChanged<int> onChanged;

  const CupertinoHomeSegmentedControl({
    super.key,
    required this.tabs,
    required this.currentIndex,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = CupertinoTheme.of(context).brightness == Brightness.dark;
    
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(tabs.length, (index) {
        final isSelected = index == currentIndex;
        return GestureDetector(
          onTap: () => onChanged(index),
          behavior: HitTestBehavior.opaque,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOutCubic,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            margin: EdgeInsets.only(right: index < tabs.length - 1 ? 4 : 0),
            decoration: BoxDecoration(
              color: isSelected
                  ? (isDark 
                      ? CupertinoColors.systemGrey5.darkColor
                      : CupertinoColors.systemGrey5)
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(20),
            ),
            child: AnimatedDefaultTextStyle(
              duration: const Duration(milliseconds: 200),
              style: TextStyle(
                fontSize: 15,
                fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
                color: isSelected
                    ? (isDark ? CupertinoColors.white : CupertinoColors.black)
                    : CupertinoColors.systemGrey,
              ),
              child: Text(tabs[index]),
            ),
          ),
        );
      }),
    );
  }
}

/// iOS 风格的顶部切换栏（用于 SliverPersistentHeader）
class CupertinoHomeStickyHeader extends StatelessWidget {
  final List<String> tabs;
  final int currentIndex;
  final ValueChanged<int> onChanged;
  final double shrinkOffset;
  final double maxExtent;

  const CupertinoHomeStickyHeader({
    super.key,
    required this.tabs,
    required this.currentIndex,
    required this.onChanged,
    this.shrinkOffset = 0,
    this.maxExtent = 52,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = CupertinoTheme.of(context).brightness == Brightness.dark;
    // 计算滚动进度（0-1）
    final progress = (shrinkOffset / maxExtent).clamp(0.0, 1.0);
    // 背景透明度随滚动增加
    final bgOpacity = 0.0 + progress * 0.95;
    
    return Container(
      height: maxExtent,
      decoration: BoxDecoration(
        color: (isDark ? const Color(0xFF1C1C1E) : CupertinoColors.systemBackground)
            .withOpacity(bgOpacity),
        border: progress > 0.5
            ? Border(
                bottom: BorderSide(
                  color: isDark
                      ? CupertinoColors.systemGrey.darkColor.withOpacity(0.3)
                      : CupertinoColors.systemGrey4,
                  width: 0.5,
                ),
              )
            : null,
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Align(
          alignment: Alignment.centerLeft,
          child: CupertinoHomeSegmentedControl(
            tabs: tabs,
            currentIndex: currentIndex,
            onChanged: onChanged,
          ),
        ),
      ),
    );
  }
}

/// SliverPersistentHeader 的代理
class CupertinoHomeStickyHeaderDelegate extends SliverPersistentHeaderDelegate {
  final List<String> tabs;
  final int currentIndex;
  final ValueChanged<int> onChanged;

  CupertinoHomeStickyHeaderDelegate({
    required this.tabs,
    required this.currentIndex,
    required this.onChanged,
  });

  @override
  double get minExtent => 52;

  @override
  double get maxExtent => 52;

  @override
  Widget build(BuildContext context, double shrinkOffset, bool overlapsContent) {
    return CupertinoHomeStickyHeader(
      tabs: tabs,
      currentIndex: currentIndex,
      onChanged: onChanged,
      shrinkOffset: shrinkOffset,
      maxExtent: maxExtent,
    );
  }

  @override
  bool shouldRebuild(covariant CupertinoHomeStickyHeaderDelegate oldDelegate) {
    return currentIndex != oldDelegate.currentIndex;
  }
}

/// iOS 风格的轮播图卡片
class CupertinoTrackBannerCard extends StatelessWidget {
  final Track track;
  final VoidCallback? onTap;

  const CupertinoTrackBannerCard({
    super.key,
    required this.track,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = CupertinoTheme.of(context).brightness == Brightness.dark;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 8),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: CupertinoColors.black.withOpacity(isDark ? 0.3 : 0.15),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(16),
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
                  color: isDark
                      ? const Color(0xFF2C2C2E)
                      : CupertinoColors.systemGrey6,
                  child: const Center(
                    child: CupertinoActivityIndicator(),
                  ),
                ),
                errorWidget: (context, url, error) => Container(
                  color: isDark
                      ? const Color(0xFF2C2C2E)
                      : CupertinoColors.systemGrey6,
                  child: Icon(
                    CupertinoIcons.music_note,
                    size: 64,
                    color: CupertinoColors.systemGrey,
                  ),
                ),
              ),
              // 渐变遮罩
              Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.transparent,
                      CupertinoColors.black.withOpacity(0.7),
                    ],
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
                    Text(
                      track.name,
                      style: const TextStyle(
                        color: CupertinoColors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        shadows: [
                          Shadow(
                            offset: Offset(0, 1),
                            blurRadius: 3.0,
                            color: Colors.black54,
                          ),
                        ],
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      track.artists,
                      style: TextStyle(
                        color: CupertinoColors.white.withOpacity(0.9),
                        fontSize: 14,
                        shadows: const [
                          Shadow(
                            offset: Offset(0, 1),
                            blurRadius: 3.0,
                            color: Colors.black54,
                          ),
                        ],
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              // 播放按钮
              Positioned(
                top: 12,
                right: 12,
                child: Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: ThemeManager.iosBlue,
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: CupertinoColors.black.withOpacity(0.3),
                        blurRadius: 8,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: const Icon(
                    CupertinoIcons.play_fill,
                    color: CupertinoColors.white,
                    size: 22,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// iOS 风格的轮播图区域
class CupertinoBannerSection extends StatelessWidget {
  final List<Track> cachedRandomTracks;
  final PageController bannerController;
  final int currentBannerIndex;
  final Function(int) onPageChanged;
  final Future<bool> Function() checkLoginStatus;

  const CupertinoBannerSection({
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
        final screenWidth = MediaQuery.of(context).size.width;
        final bannerHeight = (screenWidth * 0.5).clamp(160.0, 220.0);

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Padding(
              padding: EdgeInsets.only(left: 4, bottom: 12),
              child: Text(
                '推荐歌曲',
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
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
                      return CupertinoTrackBannerCard(
                        track: track,
                        onTap: () async {
                          final isLoggedIn = await checkLoginStatus();
                          if (isLoggedIn && context.mounted) {
                            PlayerService().playTrack(track);
                          }
                        },
                      );
                    },
                  ),
                  // iOS 风格页面指示器
                  Positioned(
                    bottom: 12,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: List.generate(
                        cachedRandomTracks.length,
                        (index) => AnimatedContainer(
                          duration: const Duration(milliseconds: 200),
                          width: currentBannerIndex == index ? 18 : 6,
                          height: 6,
                          margin: const EdgeInsets.symmetric(horizontal: 3),
                          decoration: BoxDecoration(
                            color: currentBannerIndex == index
                                ? CupertinoColors.white
                                : CupertinoColors.white.withOpacity(0.5),
                            borderRadius: BorderRadius.circular(3),
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

/// iOS 风格的历史记录卡片
class CupertinoHistorySection extends StatelessWidget {
  const CupertinoHistorySection({super.key});

  @override
  Widget build(BuildContext context) {
    final history = PlayHistoryService().history.take(3).toList();
    final isDark = CupertinoTheme.of(context).brightness == Brightness.dark;

    if (history.isEmpty) {
      return const SizedBox.shrink();
    }

    return Container(
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1C1C1E) : CupertinoColors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: CupertinoColors.black.withOpacity(isDark ? 0.2 : 0.08),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: CupertinoButton(
        padding: EdgeInsets.zero,
        onPressed: () {
          // TODO: 跳转到历史记录页面
        },
        child: Padding(
          padding: const EdgeInsets.all(12.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    CupertinoIcons.time,
                    size: 18,
                    color: ThemeManager.iosBlue,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    '最近播放',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: isDark
                          ? CupertinoColors.white
                          : CupertinoColors.black,
                    ),
                  ),
                  const Spacer(),
                  Icon(
                    CupertinoIcons.chevron_right,
                    size: 16,
                    color: CupertinoColors.systemGrey,
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: CachedNetworkImage(
                      imageUrl: history.first.picUrl,
                      width: 60,
                      height: 60,
                      fit: BoxFit.cover,
                      memCacheWidth: 128,
                      memCacheHeight: 128,
                      placeholder: (context, url) => Container(
                        width: 60,
                        height: 60,
                        color: CupertinoColors.systemGrey6,
                        child: const CupertinoActivityIndicator(),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: List.generate(history.length, (index) {
                        final item = history[index];
                        return Padding(
                          padding: const EdgeInsets.symmetric(vertical: 2.0),
                          child: Text(
                            '${index + 1}. ${item.name} - ${item.artists}',
                            style: TextStyle(
                              fontSize: 13,
                              color: isDark
                                  ? CupertinoColors.systemGrey
                                  : CupertinoColors.systemGrey,
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
  }
}

/// iOS 风格的猜你喜欢卡片
class CupertinoGuessYouLikeSection extends StatelessWidget {
  final Future<List<Track>>? guessYouLikeFuture;

  const CupertinoGuessYouLikeSection({super.key, this.guessYouLikeFuture});

  @override
  Widget build(BuildContext context) {
    final isDark = CupertinoTheme.of(context).brightness == Brightness.dark;

    return Container(
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1C1C1E) : CupertinoColors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: CupertinoColors.black.withOpacity(isDark ? 0.2 : 0.08),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: CupertinoButton(
        padding: EdgeInsets.zero,
        onPressed: () {
          // TODO: 跳转到推荐页面
        },
        child: Padding(
          padding: const EdgeInsets.all(12.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    CupertinoIcons.heart_fill,
                    size: 18,
                    color: CupertinoColors.systemPink,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    '猜你喜欢',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: isDark
                          ? CupertinoColors.white
                          : CupertinoColors.black,
                    ),
                  ),
                  const Spacer(),
                  Icon(
                    CupertinoIcons.chevron_right,
                    size: 16,
                    color: CupertinoColors.systemGrey,
                  ),
                ],
              ),
              const SizedBox(height: 12),
              SizedBox(
                height: 64,
                child: guessYouLikeFuture != null
                    ? _buildGuessYouLikeContent(context, isDark)
                    : _buildGuessYouLikePlaceholder(context, isDark),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildGuessYouLikeContent(BuildContext context, bool isDark) {
    return FutureBuilder<List<Track>>(
      future: guessYouLikeFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CupertinoActivityIndicator());
        }

        if (snapshot.hasError || !snapshot.hasData || snapshot.data!.isEmpty) {
          return _buildGuessYouLikePlaceholder(context, isDark, isError: true);
        }

        final sampleTracks = snapshot.data!;

        return Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: CachedNetworkImage(
                imageUrl: sampleTracks.first.picUrl,
                width: 60,
                height: 60,
                fit: BoxFit.cover,
                memCacheWidth: 128,
                memCacheHeight: 128,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: List.generate(sampleTracks.length, (index) {
                  final track = sampleTracks[index];
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 2.0),
                    child: Text(
                      '${index + 1}. ${track.name} - ${track.artists}',
                      style: TextStyle(
                        fontSize: 13,
                        color: CupertinoColors.systemGrey,
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

  Widget _buildGuessYouLikePlaceholder(BuildContext context, bool isDark,
      {bool isError = false}) {
    final message = isError ? '加载推荐失败' : '导入歌单查看更多';
    return Center(
      child: Text(
        message,
        style: TextStyle(
          color: CupertinoColors.systemGrey,
          fontSize: 14,
        ),
      ),
    );
  }
}

/// iOS 风格的榜单网格
class CupertinoToplistsGrid extends StatelessWidget {
  final Future<bool> Function() checkLoginStatus;
  final void Function(Toplist) showToplistDetail;

  const CupertinoToplistsGrid({
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
        for (int i = 0; i < toplists.length; i++) ...[
          _buildToplistSection(context, toplists[i]),
          if (i < toplists.length - 1) const SizedBox(height: 32),
        ],
      ],
    );
  }

  Widget _buildToplistSection(BuildContext context, Toplist toplist) {
    final isDark = CupertinoTheme.of(context).brightness == Brightness.dark;

    return LayoutBuilder(
      builder: (context, constraints) {
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
                    style: const TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                CupertinoButton(
                  padding: EdgeInsets.zero,
                  onPressed: () => showToplistDetail(toplist),
                  child: Row(
                    children: [
                      Text(
                        '查看全部',
                        style: TextStyle(
                          color: ThemeManager.iosBlue,
                          fontSize: 15,
                        ),
                      ),
                      const SizedBox(width: 2),
                      Icon(
                        CupertinoIcons.chevron_right,
                        size: 16,
                        color: ThemeManager.iosBlue,
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            // 横向滚动的歌曲卡片
            SizedBox(
              height: cardHeight,
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                itemCount: toplist.tracks.take(10).length,
                itemBuilder: (context, index) {
                  final track = toplist.tracks[index];
                  return _buildTrackCard(context, track, index, isDark);
                },
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildTrackCard(
      BuildContext context, Track track, int rank, bool isDark) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final cardHeight = constraints.maxHeight;
        final coverSize = (cardHeight * 0.65).clamp(120.0, 160.0);
        final cardWidth = coverSize;

        return Container(
          width: cardWidth,
          margin: const EdgeInsets.only(right: 12),
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF1C1C1E) : CupertinoColors.white,
            borderRadius: BorderRadius.circular(12),
            boxShadow: [
              BoxShadow(
                color: CupertinoColors.black.withOpacity(isDark ? 0.2 : 0.08),
                blurRadius: 10,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: CupertinoButton(
            padding: EdgeInsets.zero,
            onPressed: () async {
              final isLoggedIn = await checkLoginStatus();
              if (isLoggedIn && context.mounted) {
                PlayerService().playTrack(track);
              }
            },
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 专辑封面
                Stack(
                  children: [
                    ClipRRect(
                      borderRadius: const BorderRadius.only(
                        topLeft: Radius.circular(12),
                        topRight: Radius.circular(12),
                      ),
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
                          color: CupertinoColors.systemGrey6,
                          child: const Center(
                            child: CupertinoActivityIndicator(),
                          ),
                        ),
                        errorWidget: (context, url, error) => Container(
                          width: coverSize,
                          height: coverSize,
                          color: CupertinoColors.systemGrey6,
                          child: Icon(
                            CupertinoIcons.music_note,
                            size: coverSize * 0.3,
                            color: CupertinoColors.systemGrey,
                          ),
                        ),
                      ),
                    ),
                    // 排名标签
                    Positioned(
                      top: 6,
                      left: 6,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: rank < 3
                              ? ThemeManager.iosBlue
                              : (isDark
                                  ? const Color(0xFF3A3A3C)
                                  : CupertinoColors.systemGrey5),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          '${rank + 1}',
                          style: TextStyle(
                            color: rank < 3
                                ? CupertinoColors.white
                                : (isDark
                                    ? CupertinoColors.white
                                    : CupertinoColors.black),
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                // 歌曲信息
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.all(8.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          track.name,
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                            color: isDark
                                ? CupertinoColors.white
                                : CupertinoColors.black,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 2),
                        Text(
                          track.artists,
                          style: TextStyle(
                            fontSize: 11,
                            color: CupertinoColors.systemGrey,
                          ),
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
      },
    );
  }
}

/// iOS 风格的加载状态
class CupertinoLoadingSection extends StatelessWidget {
  const CupertinoLoadingSection({super.key});

  @override
  Widget build(BuildContext context) {
    // 使用骨架屏替代简单的加载指示器
    return const MobileChartsTabSkeleton();
  }
}

/// iOS 风格的错误状态
class CupertinoErrorSection extends StatelessWidget {
  const CupertinoErrorSection({super.key});

  @override
  Widget build(BuildContext context) {
    final isDark = CupertinoTheme.of(context).brightness == Brightness.dark;

    return Container(
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.all(32),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1C1C1E) : CupertinoColors.white,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        children: [
          Icon(
            CupertinoIcons.exclamationmark_circle,
            size: 64,
            color: CupertinoColors.systemRed,
          ),
          const SizedBox(height: 16),
          const Text(
            '加载失败',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            MusicService().errorMessage ?? '未知错误',
            style: TextStyle(
              color: CupertinoColors.systemGrey,
              fontSize: 14,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 24),
          CupertinoButton.filled(
            onPressed: () {
              MusicService().refreshToplists();
            },
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(CupertinoIcons.refresh, size: 18),
                SizedBox(width: 6),
                Text('重试'),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// iOS 风格的空状态
class CupertinoEmptySection extends StatelessWidget {
  const CupertinoEmptySection({super.key});

  @override
  Widget build(BuildContext context) {
    final isDark = CupertinoTheme.of(context).brightness == Brightness.dark;

    return Container(
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.all(32),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1C1C1E) : CupertinoColors.white,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        children: [
          Icon(
            CupertinoIcons.music_note,
            size: 64,
            color: CupertinoColors.systemGrey,
          ),
          const SizedBox(height: 16),
          const Text(
            '暂无榜单',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '请检查后端服务是否正常',
            style: TextStyle(
              color: CupertinoColors.systemGrey,
              fontSize: 14,
            ),
          ),
          const SizedBox(height: 24),
          CupertinoButton.filled(
            onPressed: () {
              MusicService().fetchToplists();
            },
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(CupertinoIcons.refresh, size: 18),
                SizedBox(width: 6),
                Text('刷新'),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
