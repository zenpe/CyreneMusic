import 'dart:io';
import 'package:flutter/material.dart';
import 'package:fluent_ui/fluent_ui.dart' as fluent;
import 'package:cached_network_image/cached_network_image.dart';
import '../../models/track.dart';
import '../../models/toplist.dart';
import '../../services/player_service.dart';
import '../../services/music_service.dart';
import '../../utils/theme_manager.dart';
import 'home_widgets.dart';
import 'toplist_detail.dart';
import '../../widgets/skeleton_loader.dart';

class ChartsTab extends StatelessWidget {
  final List<Track> cachedRandomTracks;
  final Future<void> Function() checkLoginStatus;
  final Future<List<Track>>? guessYouLikeFuture;
  final VoidCallback onRefresh;

  const ChartsTab({
    super.key,
    required this.cachedRandomTracks,
    required this.checkLoginStatus,
    this.guessYouLikeFuture,
    required this.onRefresh,
  });

  @override
  Widget build(BuildContext context) {
    final isMobile = Platform.isIOS || Platform.isAndroid;
    
    if (MusicService().isLoading) {
      // 移动端使用移动端专用骨架屏
      if (isMobile) {
        return const MobileChartsTabSkeleton();
      }
      // Fluent UI 桌面端使用桌面端骨架屏
      if (ThemeManager().isFluentFramework) {
        return const ChartsTabSkeleton();
      }
      // 其他桌面端也使用桌面端骨架屏
      return const ChartsTabSkeleton();
    }

    if (MusicService().errorMessage != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text('加载失败\n${MusicService().errorMessage}'),
              const SizedBox(height: 16),
              if (ThemeManager().isFluentFramework)
                fluent.Button(
                  onPressed: onRefresh,
                  child: const Text('重试'),
                )
              else
                ElevatedButton(
                  onPressed: onRefresh,
                  child: const Text('重试'),
                ),
            ],
          ),
        ),
      );
    }

    if (MusicService().toplists.isEmpty) {
      return const Center(child: Padding(padding: EdgeInsets.all(32), child: Text('暂无榜单数据')));
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final isWide = constraints.maxWidth > 800;
        
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 0. Expressive Page Title
            Padding(
              padding: const EdgeInsets.only(top: 16, bottom: 40),
              child: Text(
                '音乐榜单',
                style: Theme.of(context).textTheme.displaySmall?.copyWith(
                  fontWeight: FontWeight.w900,
                  letterSpacing: -1.0,
                  color: Theme.of(context).colorScheme.onSurface,
                ),
              ),
            ),

            // 1. 顶部 BENTO GRID
            Padding(
              padding: const EdgeInsets.only(bottom: 56),
              child: _buildFeaturedSection(context, constraints),
            ),

            // 2. 历史与推荐 (Quick Access)
            Padding(
              padding: const EdgeInsets.only(bottom: 56),
              child: _buildQuickAccessSection(context, isWide),
            ),

            // 3. 榜单列表 (更具表现力的间距)
            ...MusicService().toplists.map((toplist) {
              return Padding(
                padding: const EdgeInsets.only(bottom: 64.0),
                child: _ToplistSection(
                  toplist: toplist,
                  checkLoginStatus: checkLoginStatus,
                ),
              );
            }),
            
             SizedBox(height: MediaQuery.of(context).padding.bottom + 80),
          ],
        );
      },
    );
  }

  Widget _buildFeaturedSection(BuildContext context, BoxConstraints constraints) {
    if (cachedRandomTracks.isEmpty) return const SizedBox.shrink();

    // 如果宽度足够，使用 Bento Grid 布局
    final isDesktop = constraints.maxWidth > 900;
    
    if (isDesktop && cachedRandomTracks.length >= 3) {
      final height = 320.0;
      
      return SizedBox(
        height: height,
        child: Row(
          children: [
            // 主推荐位
            Expanded(
              flex: 2,
              child: _FeaturedCard(
                track: cachedRandomTracks[0],
                checkLoginStatus: checkLoginStatus,
                isLarge: true,
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              flex: 1,
              child: Column(
                children: [
                  Expanded(
                    child: _FeaturedCard(
                      track: cachedRandomTracks[1],
                      checkLoginStatus: checkLoginStatus,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Expanded(
                    child: _FeaturedCard(
                      track: cachedRandomTracks[2],
                      checkLoginStatus: checkLoginStatus,
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
        Padding(
          padding: const EdgeInsets.only(bottom: 24.0),
          child: Text(
            '今日推荐',
            style: Theme.of(context).textTheme.headlineMedium?.copyWith(
              fontWeight: FontWeight.w800,
              letterSpacing: -0.5,
            ),
          ),
        ),
        SizedBox(
          height: 240,
          child: CarouselView.weighted(
            flexWeights: const [7, 2, 1], // 强制比例：一大(70%), 一中(20%), 一小(10%)
            padding: const EdgeInsets.symmetric(horizontal: 4),
            children: cachedRandomTracks.map((track) {
              return _FeaturedCard(
                track: track,
                checkLoginStatus: checkLoginStatus,
                showDetails: true,
              );
            }).toList(),
          ),
        ),
      ],
    );
  }

  Widget _buildQuickAccessSection(BuildContext context, bool isWide) {
    if (isWide) {
      return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Expanded(child: HistorySection()),
          const SizedBox(width: 24),
          Expanded(
            child: GuessYouLikeSection(
              guessYouLikeFuture: guessYouLikeFuture,
            ),
          ),
        ],
      );
    } else {
      return Column(
        children: [
          const HistorySection(),
          const SizedBox(height: 16),
          GuessYouLikeSection(
            guessYouLikeFuture: guessYouLikeFuture,
          ),
        ],
      );
    }
  }
}

class _FeaturedCard extends StatefulWidget {
  final Track track;
  final Future<void> Function() checkLoginStatus;
  final bool isLarge;
  final bool showDetails;

  const _FeaturedCard({
    required this.track,
    required this.checkLoginStatus,
    this.isLarge = false,
    this.showDetails = true,
  });

  @override
  State<_FeaturedCard> createState() => _FeaturedCardState();
}

class _FeaturedCardState extends State<_FeaturedCard> {
  bool _isHovering = false;

  @override
  Widget build(BuildContext context) {
    final borderRadius = BorderRadius.circular(28); // Material Expressive 大圆角

    return MouseRegion(
      onEnter: (_) => setState(() => _isHovering = true),
      onExit: (_) => setState(() => _isHovering = false),
      child: GestureDetector(
        onTap: () async {
          await widget.checkLoginStatus();
          PlayerService().playTrack(widget.track);
        },
        child: Container(
          decoration: BoxDecoration(
            borderRadius: borderRadius,
            boxShadow: _isHovering
                ? [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.2),
                      blurRadius: 16,
                      offset: const Offset(0, 8),
                    )
                  ]
                : [],
          ),
          child: ClipRRect(
            borderRadius: borderRadius,
            child: Stack(
              fit: StackFit.expand,
              children: [
                // Background Image with Scale Animation
                AnimatedScale(
                  scale: _isHovering ? 1.1 : 1.0,
                  duration: const Duration(milliseconds: 700),
                  curve: Curves.easeOutCubic,
                  child: CachedNetworkImage(
                    imageUrl: widget.track.picUrl,
                    fit: BoxFit.cover,
                    memCacheWidth: 280,
                    memCacheHeight: 280,
                    placeholder: (context, url) => Container(
                      color: Colors.grey[800],
                    ),
                  ),
                ),
                Container(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Colors.transparent,
                        Colors.black.withOpacity(0.35),
                        Colors.black.withOpacity(0.85),
                      ],
                      stops: const [0.4, 0.7, 1.0],
                    ),
                  ),
                ),
                if (widget.showDetails)
                  Positioned(
                    left: 24,
                    right: 24,
                    bottom: 24,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (widget.isLarge)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: Theme.of(context).colorScheme.primary,
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: const Text(
                              'Featured',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        SizedBox(height: widget.isLarge ? 8 : 4),
                        Text(
                          widget.track.name,
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: widget.isLarge ? 28 : 18,
                            fontWeight: FontWeight.bold,
                            shadows: const [Shadow(blurRadius: 4, color: Colors.black26)],
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        SizedBox(height: widget.isLarge ? 4 : 2),
                        Text(
                          '${widget.track.artists} • ${widget.track.album}',
                          style: TextStyle(
                            color: Colors.white.withOpacity(0.85),
                            fontSize: widget.isLarge ? 16 : 14,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                if (_isHovering || widget.isLarge)
                  Positioned(
                    right: 20,
                    bottom: 20,
                    child: Container(
                      padding: EdgeInsets.all(widget.isLarge ? 12 : 8),
                      decoration: const BoxDecoration(
                        color: Colors.white,
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black26,
                            blurRadius: 8,
                            offset: Offset(0, 4),
                          )
                        ],
                      ),
                      child: Icon(
                        Icons.play_arrow_rounded,
                        color: Colors.black,
                        size: widget.isLarge ? 32 : 24,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ToplistSection extends StatelessWidget {
  final Toplist toplist;
  final Future<void> Function() checkLoginStatus;

  const _ToplistSection({
    required this.toplist,
    required this.checkLoginStatus,
  });

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
                Container(
                  width: 4,
                  height: 18,
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.primary,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  toplist.name,
                  style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.5,
                  ),
                ),
              ],
            ),
            
            if (ThemeManager().isFluentFramework)
              fluent.HyperlinkButton(
                onPressed: () => showToplistDetail(context, toplist),
                child: const Text('查看全部'),
              )
            else
              TextButton(
                onPressed: () => showToplistDetail(context, toplist),
                child: const Text('查看全部'),
              ),
          ],
        ),
        const SizedBox(height: 24),
        SizedBox(
          height: 220, // 增加高度以容纳更美观的卡片
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: toplist.tracks.take(12).length,
            separatorBuilder: (c, i) => const SizedBox(width: 16),
            itemBuilder: (context, index) {
              return _ToplistTrackCard(
                track: toplist.tracks[index], 
                rank: index,
                checkLoginStatus: checkLoginStatus,
              );
            },
          ),
        ),
      ],
    );
  }
}

class _ToplistTrackCard extends StatefulWidget {
  final Track track;
  final int rank;
  final Future<void> Function() checkLoginStatus;

  const _ToplistTrackCard({
    required this.track,
    required this.rank,
    required this.checkLoginStatus,
  });

  @override
  State<_ToplistTrackCard> createState() => _ToplistTrackCardState();
}

class _ToplistTrackCardState extends State<_ToplistTrackCard> {
  bool _isHovering = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final width = 160.0; // 宽度略微增加
    final borderRadius = BorderRadius.circular(24); // 圆角增加

    return MouseRegion(
      onEnter: (_) => setState(() => _isHovering = true),
      onExit: (_) => setState(() => _isHovering = false),
      child: GestureDetector(
        onTap: () async {
          await widget.checkLoginStatus();
          PlayerService().playTrack(widget.track);
        },
        child: Container(
          width: width,
          color: Colors.transparent,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    ClipRRect(
                      borderRadius: borderRadius,
                      child: AnimatedScale(
                        scale: _isHovering ? 1.05 : 1.0,
                        duration: const Duration(milliseconds: 200),
                        child: CachedNetworkImage(
                          imageUrl: widget.track.picUrl,
                          fit: BoxFit.cover,
                          memCacheWidth: 280,
                          memCacheHeight: 280,
                        ),
                      ),
                    ),
                    Positioned(
                      top: 4,
                      left: 4,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: Colors.black.withOpacity(0.7),
                          borderRadius: BorderRadius.circular(12),
                          border: widget.rank < 3 
                              ? Border.all(color: theme.colorScheme.primary.withOpacity(0.5), width: 1.5)
                              : Border.all(color: Colors.white10, width: 1),
                        ),
                        child: Text(
                          '#${widget.rank + 1}',
                          style: TextStyle(
                            color: widget.rank < 3 ? theme.colorScheme.primary : Colors.white.withOpacity(0.9),
                            fontSize: 14,
                            fontWeight: FontWeight.w900,
                            letterSpacing: -0.5,
                          ),
                        ),
                      ),
                    ),
                     if (_isHovering)
                      Center(
                        child: Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.9),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            Icons.play_arrow_rounded,
                            size: 24,
                            color: Colors.black,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4.0),
                child: Text(
                  widget.track.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.2,
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4.0),
                child: Text(
                  widget.track.artists,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.textTheme.bodySmall?.color?.withOpacity(0.6),
                    fontWeight: FontWeight.w500,
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
