import 'dart:io';
import 'package:flutter/material.dart';

/// 骨架屏加载器 - 通用闪烁动画组件
/// 用于在数据加载时显示占位符动画
class SkeletonLoader extends StatefulWidget {
  final double? width;
  final double? height;
  final BorderRadius? borderRadius;
  final EdgeInsetsGeometry? margin;

  const SkeletonLoader({
    super.key,
    this.width,
    this.height,
    this.borderRadius,
    this.margin,
  });

  @override
  State<SkeletonLoader> createState() => _SkeletonLoaderState();
}

class _SkeletonLoaderState extends State<SkeletonLoader>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat();

    _animation = Tween<double>(begin: -1.0, end: 2.0).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final baseColor = isDark ? const Color(0xFF2A2A3A) : const Color(0xFFE0E0E0);
    final highlightColor = isDark ? const Color(0xFF3A3A4A) : const Color(0xFFF5F5F5);

    return AnimatedBuilder(
      animation: _animation,
      builder: (context, child) {
        return Container(
          width: widget.width,
          height: widget.height,
          margin: widget.margin,
          decoration: BoxDecoration(
            borderRadius: widget.borderRadius ?? BorderRadius.circular(8),
            gradient: LinearGradient(
              begin: Alignment.centerLeft,
              end: Alignment.centerRight,
              colors: [baseColor, highlightColor, baseColor],
              stops: [
                (_animation.value - 0.3).clamp(0.0, 1.0),
                _animation.value.clamp(0.0, 1.0),
                (_animation.value + 0.3).clamp(0.0, 1.0),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// 为你推荐页骨架屏
class ForYouSkeleton extends StatelessWidget {
  const ForYouSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    final isMobile = Platform.isIOS || Platform.isAndroid;
    
    if (isMobile) {
      return _buildMobileSkeleton(context);
    }
    return _buildDesktopSkeleton(context);
  }

  Widget _buildMobileSkeleton(BuildContext context) {
    return SingleChildScrollView(
      physics: const NeverScrollableScrollPhysics(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 问候语骨架
          const _GreetingHeaderSkeleton(),
          const SizedBox(height: 16),
          // 每日推荐卡片骨架
          SkeletonLoader(
            width: double.infinity,
            height: 180,
            borderRadius: BorderRadius.circular(16),
          ),
          const SizedBox(height: 24),
          // 私人FM 区域标题骨架
          const _SectionTitleSkeleton(),
          const SizedBox(height: 12),
          // 私人FM 列表骨架
          SizedBox(
            height: 120,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: 3,
              separatorBuilder: (_, __) => const SizedBox(width: 12),
              itemBuilder: (context, index) => SkeletonLoader(
                width: 100,
                height: 120,
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
          const SizedBox(height: 24),
          // 歌单网格骨架
          const _SectionTitleSkeleton(),
          const SizedBox(height: 12),
          const _PlaylistGridSkeleton(itemCount: 4),
        ],
      ),
    );
  }

  Widget _buildDesktopSkeleton(BuildContext context) {
    return SingleChildScrollView(
      physics: const NeverScrollableScrollPhysics(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 问候语骨架
          const _GreetingHeaderSkeleton(),
          const SizedBox(height: 16),
          // Hero 双卡区域骨架
          const _HeroSectionSkeleton(),
          const SizedBox(height: 28),
          // 每日推荐歌单骨架
          const _SectionTitleSkeleton(),
          const SizedBox(height: 12),
          const _BentoPlaylistGridSkeleton(),
          const SizedBox(height: 28),
          // 专属歌单骨架
          const _SectionTitleSkeleton(),
          const SizedBox(height: 12),
          const _HorizontalCarouselSkeleton(),
          const SizedBox(height: 28),
          // 雷达歌单骨架
          const _SectionTitleSkeleton(),
          const SizedBox(height: 12),
          const _MixedSizeGridSkeleton(),
          const SizedBox(height: 28),
          // 发现新歌骨架
          const _SectionTitleSkeleton(),
          const SizedBox(height: 12),
          const _NewsongCardsSkeleton(),
        ],
      ),
    );
  }
}

/// 发现页骨架屏
class DiscoverPageSkeleton extends StatelessWidget {
  const DiscoverPageSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        int crossAxisCount = 2;
        if (width >= 1200) crossAxisCount = 6;
        else if (width >= 1000) crossAxisCount = 5;
        else if (width >= 800) crossAxisCount = 4;
        else if (width >= 600) crossAxisCount = 3;

        return SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 分类选择器骨架
              SkeletonLoader(
                width: 120,
                height: 32,
                borderRadius: BorderRadius.circular(6),
              ),
              const SizedBox(height: 16),
              // 歌单网格骨架
              GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: crossAxisCount,
                  mainAxisSpacing: 16,
                  crossAxisSpacing: 16,
                  childAspectRatio: 0.72,
                ),
                itemCount: crossAxisCount * 3, // 3行
                itemBuilder: (context, index) => const _DiscoverPlaylistCardSkeleton(),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// 发现页歌单卡片骨架
class _DiscoverPlaylistCardSkeleton extends StatelessWidget {
  const _DiscoverPlaylistCardSkeleton();

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 封面骨架
        AspectRatio(
          aspectRatio: 1,
          child: SkeletonLoader(
            borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
          ),
        ),
        // 信息区域骨架
        Expanded(
          child: Padding(
            padding: const EdgeInsets.all(10.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                SkeletonLoader(
                  width: double.infinity,
                  height: 16,
                  borderRadius: BorderRadius.circular(4),
                ),
                const SizedBox(height: 6),
                SkeletonLoader(
                  width: 80,
                  height: 12,
                  borderRadius: BorderRadius.circular(4),
                ),
                const SizedBox(height: 4),
                SkeletonLoader(
                  width: 100,
                  height: 11,
                  borderRadius: BorderRadius.circular(4),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// 移动端发现页骨架屏
/// 适配 iOS Cupertino 和 Material Design 3 主题
class MobileDiscoverPageSkeleton extends StatelessWidget {
  const MobileDiscoverPageSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 分类选择器骨架
        SkeletonLoader(
          width: 100,
          height: 32,
          borderRadius: BorderRadius.circular(16),
        ),
        const SizedBox(height: 16),
        // 歌单网格骨架（2列布局适配移动端）
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 2,
            mainAxisSpacing: 16,
            crossAxisSpacing: 16,
            childAspectRatio: 0.75,
          ),
          itemCount: 6,
          itemBuilder: (context, index) => const _MobileDiscoverPlaylistCardSkeleton(),
        ),
      ],
    );
  }
}

/// 移动端发现页 Sliver 骨架屏（用于 CustomScrollView）
class MobileDiscoverPageSliverSkeleton extends StatelessWidget {
  const MobileDiscoverPageSliverSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return SliverPadding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      sliver: SliverLayoutBuilder(
        builder: (context, constraints) {
          final width = constraints.crossAxisExtent;
          int crossAxisCount = 2;
          if (width >= 600) crossAxisCount = 3;
          if (width >= 800) crossAxisCount = 4;

          return SliverGrid(
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: crossAxisCount,
              mainAxisSpacing: 16,
              crossAxisSpacing: 16,
              childAspectRatio: 0.75,
            ),
            delegate: SliverChildBuilderDelegate(
              (context, index) => const _MobileDiscoverPlaylistCardSkeleton(),
              childCount: crossAxisCount * 3,
            ),
          );
        },
      ),
    );
  }
}

/// 移动端发现页歌单卡片骨架
class _MobileDiscoverPlaylistCardSkeleton extends StatelessWidget {
  const _MobileDiscoverPlaylistCardSkeleton();

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 封面骨架
        AspectRatio(
          aspectRatio: 1,
          child: SkeletonLoader(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
        const SizedBox(height: 8),
        // 标题骨架
        SkeletonLoader(
          width: double.infinity,
          height: 14,
          borderRadius: BorderRadius.circular(4),
        ),
        const SizedBox(height: 4),
        // 副标题骨架
        SkeletonLoader(
          width: 80,
          height: 12,
          borderRadius: BorderRadius.circular(4),
        ),
        const SizedBox(height: 2),
        // 播放数骨架
        SkeletonLoader(
          width: 60,
          height: 10,
          borderRadius: BorderRadius.circular(4),
        ),
      ],
    );
  }
}

/// 榜单页骨架屏
class ChartsTabSkeleton extends StatelessWidget {
  const ChartsTabSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isDesktop = constraints.maxWidth > 900;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Featured 区域骨架
            _buildFeaturedSkeleton(isDesktop),
            const SizedBox(height: 32),
            // Quick Access 区域骨架
            _buildQuickAccessSkeleton(constraints.maxWidth > 800),
            const SizedBox(height: 32),
            // 榜单列表骨架
            ..._buildToplistSkeletons(),
          ],
        );
      },
    );
  }

  Widget _buildFeaturedSkeleton(bool isDesktop) {
    if (isDesktop) {
      return SizedBox(
        height: 320,
        child: Row(
          children: [
            // 主推荐位
            Expanded(
              flex: 2,
              child: SkeletonLoader(
                height: 320,
                borderRadius: BorderRadius.circular(16),
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              flex: 1,
              child: Column(
                children: [
                  Expanded(
                    child: SkeletonLoader(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Expanded(
                    child: SkeletonLoader(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    }

    // 窄屏布局
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SkeletonLoader(
          width: 100,
          height: 28,
          borderRadius: BorderRadius.circular(8),
        ),
        const SizedBox(height: 16),
        SizedBox(
          height: 220,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: 3,
            separatorBuilder: (_, __) => const SizedBox(width: 16),
            itemBuilder: (context, index) => SkeletonLoader(
              width: 300,
              height: 220,
              borderRadius: BorderRadius.circular(16),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildQuickAccessSkeleton(bool isWide) {
    final section = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SkeletonLoader(
          width: 120,
          height: 24,
          borderRadius: BorderRadius.circular(8),
        ),
        const SizedBox(height: 16),
        SizedBox(
          height: 80,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: 4,
            separatorBuilder: (_, __) => const SizedBox(width: 12),
            itemBuilder: (context, index) => SkeletonLoader(
              width: 160,
              height: 80,
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        ),
      ],
    );

    if (isWide) {
      return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(child: section),
          const SizedBox(width: 24),
          Expanded(child: section),
        ],
      );
    }

    return Column(
      children: [
        section,
        const SizedBox(height: 16),
        section,
      ],
    );
  }

  List<Widget> _buildToplistSkeletons() {
    return List.generate(3, (index) => Padding(
      padding: const EdgeInsets.only(bottom: 32.0),
      child: _ToplistSectionSkeleton(),
    ));
  }
}

/// 问候语区域骨架
class _GreetingHeaderSkeleton extends StatelessWidget {
  const _GreetingHeaderSkeleton();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 8.0, bottom: 8.0),
      child: Row(
        children: [
          SkeletonLoader(
            width: 24,
            height: 24,
            borderRadius: BorderRadius.circular(12),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SkeletonLoader(
                  width: 120,
                  height: 24,
                  borderRadius: BorderRadius.circular(8),
                ),
                const SizedBox(height: 4),
                SkeletonLoader(
                  width: 200,
                  height: 16,
                  borderRadius: BorderRadius.circular(6),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// 区域标题骨架
class _SectionTitleSkeleton extends StatelessWidget {
  const _SectionTitleSkeleton();

  @override
  Widget build(BuildContext context) {
    return SkeletonLoader(
      width: 140,
      height: 24,
      borderRadius: BorderRadius.circular(8),
    );
  }
}

/// Hero 双卡区域骨架
class _HeroSectionSkeleton extends StatelessWidget {
  const _HeroSectionSkeleton();

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isWide = constraints.maxWidth >= 600;

        if (isWide) {
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                flex: 3,
                child: SkeletonLoader(
                  height: 220,
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                flex: 2,
                child: SkeletonLoader(
                  height: 220,
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
            ],
          );
        }

        return Column(
          children: [
            SkeletonLoader(
              height: 180,
              borderRadius: BorderRadius.circular(16),
            ),
            const SizedBox(height: 12),
            SkeletonLoader(
              height: 160,
              borderRadius: BorderRadius.circular(16),
            ),
          ],
        );
      },
    );
  }
}

/// Bento 歌单网格骨架
class _BentoPlaylistGridSkeleton extends StatelessWidget {
  const _BentoPlaylistGridSkeleton();

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isWide = constraints.maxWidth >= 600;

        if (isWide) {
          return SizedBox(
            height: 320,
            child: Row(
              children: [
                Expanded(
                  flex: 3,
                  child: SkeletonLoader(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  flex: 4,
                  child: Column(
                    children: [
                      Expanded(
                        child: Row(
                          children: [
                            Expanded(child: SkeletonLoader(borderRadius: BorderRadius.circular(12))),
                            const SizedBox(width: 12),
                            Expanded(child: SkeletonLoader(borderRadius: BorderRadius.circular(12))),
                          ],
                        ),
                      ),
                      const SizedBox(height: 12),
                      Expanded(
                        child: Row(
                          children: [
                            Expanded(child: SkeletonLoader(borderRadius: BorderRadius.circular(12))),
                            const SizedBox(width: 12),
                            Expanded(child: SkeletonLoader(borderRadius: BorderRadius.circular(12))),
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

        return const _PlaylistGridSkeleton(itemCount: 6);
      },
    );
  }
}

/// 歌单网格骨架
class _PlaylistGridSkeleton extends StatelessWidget {
  final int itemCount;
  const _PlaylistGridSkeleton({this.itemCount = 6});

  @override
  Widget build(BuildContext context) {
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 200,
        childAspectRatio: 0.75,
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
      ),
      itemCount: itemCount,
      itemBuilder: (context, index) => SkeletonLoader(
        borderRadius: BorderRadius.circular(12),
      ),
    );
  }
}

/// 横向轮播骨架
class _HorizontalCarouselSkeleton extends StatelessWidget {
  const _HorizontalCarouselSkeleton();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 200,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        physics: const NeverScrollableScrollPhysics(),
        itemCount: 4,
        separatorBuilder: (_, __) => const SizedBox(width: 16),
        itemBuilder: (context, index) => SkeletonLoader(
          width: 320,
          height: 200,
          borderRadius: BorderRadius.circular(16),
        ),
      ),
    );
  }
}

/// 混合尺寸网格骨架
class _MixedSizeGridSkeleton extends StatelessWidget {
  const _MixedSizeGridSkeleton();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 240,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        physics: const NeverScrollableScrollPhysics(),
        itemCount: 5,
        separatorBuilder: (_, __) => const SizedBox(width: 12),
        itemBuilder: (context, index) {
          final isLarge = index == 0;
          return SkeletonLoader(
            width: isLarge ? 200 : 160,
            height: 240,
            borderRadius: BorderRadius.circular(16),
          );
        },
      ),
    );
  }
}

/// 新歌卡片骨架
class _NewsongCardsSkeleton extends StatelessWidget {
  const _NewsongCardsSkeleton();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 160,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        physics: const NeverScrollableScrollPhysics(),
        itemCount: 5,
        separatorBuilder: (_, __) => const SizedBox(width: 12),
        itemBuilder: (context, index) => SkeletonLoader(
          width: 280,
          height: 160,
          borderRadius: BorderRadius.circular(12),
        ),
      ),
    );
  }
}

/// 榜单区域骨架
class _ToplistSectionSkeleton extends StatelessWidget {
  const _ToplistSectionSkeleton();

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              children: [
                SkeletonLoader(
                  width: 4,
                  height: 18,
                  borderRadius: BorderRadius.circular(2),
                ),
                const SizedBox(width: 8),
                SkeletonLoader(
                  width: 120,
                  height: 24,
                  borderRadius: BorderRadius.circular(8),
                ),
              ],
            ),
            SkeletonLoader(
              width: 60,
              height: 20,
              borderRadius: BorderRadius.circular(6),
            ),
          ],
        ),
        const SizedBox(height: 16),
        SizedBox(
          height: 180,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: 6,
            separatorBuilder: (_, __) => const SizedBox(width: 16),
            itemBuilder: (context, index) => Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: SkeletonLoader(
                    width: 140,
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                const SizedBox(height: 8),
                SkeletonLoader(
                  width: 120,
                  height: 16,
                  borderRadius: BorderRadius.circular(4),
                ),
                const SizedBox(height: 4),
                SkeletonLoader(
                  width: 80,
                  height: 14,
                  borderRadius: BorderRadius.circular(4),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// 移动端榜单页骨架屏
/// 适配 iOS Cupertino 和 Material Design 3 主题
class MobileChartsTabSkeleton extends StatelessWidget {
  const MobileChartsTabSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 轮播图骨架
        SkeletonLoader(
          width: double.infinity,
          height: 180,
          borderRadius: BorderRadius.circular(16),
        ),
        const SizedBox(height: 24),
        // 历史记录区域骨架
        const _MobileSectionHeaderSkeleton(),
        const SizedBox(height: 12),
        SizedBox(
          height: 100,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: 4,
            separatorBuilder: (_, __) => const SizedBox(width: 12),
            itemBuilder: (context, index) => const _MobileHistoryCardSkeleton(),
          ),
        ),
        const SizedBox(height: 24),
        // 猜你喜欢区域骨架
        const _MobileSectionHeaderSkeleton(),
        const SizedBox(height: 12),
        SizedBox(
          height: 100,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: 4,
            separatorBuilder: (_, __) => const SizedBox(width: 12),
            itemBuilder: (context, index) => const _MobileHistoryCardSkeleton(),
          ),
        ),
        const SizedBox(height: 24),
        // 榜单列表骨架
        ...List.generate(2, (index) => Padding(
          padding: const EdgeInsets.only(bottom: 24.0),
          child: const _MobileToplistSectionSkeleton(),
        )),
      ],
    );
  }
}

/// 移动端区域标题骨架
class _MobileSectionHeaderSkeleton extends StatelessWidget {
  const _MobileSectionHeaderSkeleton();

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        SkeletonLoader(
          width: 100,
          height: 20,
          borderRadius: BorderRadius.circular(6),
        ),
        const Spacer(),
        SkeletonLoader(
          width: 60,
          height: 16,
          borderRadius: BorderRadius.circular(4),
        ),
      ],
    );
  }
}

/// 移动端历史记录卡片骨架
class _MobileHistoryCardSkeleton extends StatelessWidget {
  const _MobileHistoryCardSkeleton();

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        SkeletonLoader(
          width: 70,
          height: 70,
          borderRadius: BorderRadius.circular(8),
        ),
        const SizedBox(height: 6),
        SkeletonLoader(
          width: 60,
          height: 12,
          borderRadius: BorderRadius.circular(4),
        ),
      ],
    );
  }
}

/// 移动端榜单区域骨架
class _MobileToplistSectionSkeleton extends StatelessWidget {
  const _MobileToplistSectionSkeleton();

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 榜单标题
        Row(
          children: [
            SkeletonLoader(
              width: 4,
              height: 16,
              borderRadius: BorderRadius.circular(2),
            ),
            const SizedBox(width: 8),
            SkeletonLoader(
              width: 80,
              height: 18,
              borderRadius: BorderRadius.circular(6),
            ),
            const Spacer(),
            SkeletonLoader(
              width: 50,
              height: 14,
              borderRadius: BorderRadius.circular(4),
            ),
          ],
        ),
        const SizedBox(height: 12),
        // 歌曲卡片列表
        SizedBox(
          height: 140,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: 4,
            separatorBuilder: (_, __) => const SizedBox(width: 12),
            itemBuilder: (context, index) => const _MobileTrackCardSkeleton(),
          ),
        ),
      ],
    );
  }
}

/// 移动端歌曲卡片骨架
class _MobileTrackCardSkeleton extends StatelessWidget {
  const _MobileTrackCardSkeleton();

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SkeletonLoader(
          width: 100,
          height: 100,
          borderRadius: BorderRadius.circular(10),
        ),
        const SizedBox(height: 8),
        SkeletonLoader(
          width: 80,
          height: 14,
          borderRadius: BorderRadius.circular(4),
        ),
        const SizedBox(height: 4),
        SkeletonLoader(
          width: 60,
          height: 12,
          borderRadius: BorderRadius.circular(4),
        ),
      ],
    );
  }
}

/// 移动端"为你推荐"页骨架屏
/// 专门为移动端布局设计，支持 iOS Cupertino 和 Material Design 3
class MobileForYouSkeleton extends StatelessWidget {
  const MobileForYouSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 问候语骨架
        const _GreetingHeaderSkeleton(),
        const SizedBox(height: 16),
        // 每日推荐卡片骨架
        SkeletonLoader(
          width: double.infinity,
          height: 160,
          borderRadius: BorderRadius.circular(16),
        ),
        const SizedBox(height: 24),
        // 私人FM 区域
        const _SectionTitleSkeleton(),
        const SizedBox(height: 12),
        SizedBox(
          height: 90,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: 4,
            separatorBuilder: (_, __) => const SizedBox(width: 12),
            itemBuilder: (context, index) => SkeletonLoader(
              width: 70,
              height: 90,
              borderRadius: BorderRadius.circular(10),
            ),
          ),
        ),
        const SizedBox(height: 24),
        // 每日推荐歌单
        const _SectionTitleSkeleton(),
        const SizedBox(height: 12),
        _buildMobilePlaylistGrid(),
        const SizedBox(height: 24),
        // 专属歌单
        const _SectionTitleSkeleton(),
        const SizedBox(height: 12),
        _buildMobilePlaylistGrid(),
      ],
    );
  }

  Widget _buildMobilePlaylistGrid() {
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        mainAxisSpacing: 12,
        crossAxisSpacing: 12,
        childAspectRatio: 0.85,
      ),
      itemCount: 4,
      itemBuilder: (context, index) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: SkeletonLoader(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
          const SizedBox(height: 8),
          SkeletonLoader(
            width: double.infinity,
            height: 14,
            borderRadius: BorderRadius.circular(4),
          ),
        ],
      ),
    );
  }
}
