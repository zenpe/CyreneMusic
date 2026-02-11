import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:fluent_ui/fluent_ui.dart' as fluent;
import '../../utils/theme_manager.dart';
import 'daily_recommend_detail_page.dart';

/// 每日推荐卡片（移动端）
class MobileDailyRecommendCard extends StatelessWidget {
  final List<Map<String, dynamic>> tracks;
  final VoidCallback? onOpenDetail;
  const MobileDailyRecommendCard({super.key, required this.tracks, this.onOpenDetail});
  
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final themeManager = ThemeManager();
    final isCupertino = (Platform.isIOS || Platform.isAndroid) && themeManager.isCupertinoFramework;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    
    // 获取前4首歌曲的封面
    final coverImages = tracks.take(4).map((s) {
      final al = (s['al'] ?? s['album'] ?? {}) as Map<String, dynamic>;
      return (al['picUrl'] ?? '').toString();
    }).where((url) => url.isNotEmpty).toList();
    
    // iOS Cupertino 风格
    if (isCupertino) {
      return _buildCupertinoCard(context, coverImages, isDark);
    }
    
    final cardContent = _buildMaterialCardContent(context, coverImages, cs);

    if (themeManager.isFluentFramework) {
      return fluent.Card(
        padding: EdgeInsets.zero,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(6.0),
          child: cardContent,
        ),
      );
    }
    
    // Android 16 Expressive Style Card
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(32),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            cs.surfaceContainerHigh,
            cs.surfaceContainerHighest.withOpacity(0.8),
          ],
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(isDark ? 0.3 : 0.05),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () {
            if (onOpenDetail != null) {
              onOpenDetail!();
            } else {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (context) => DailyRecommendDetailPage(tracks: tracks),
                ),
              );
            }
          },
          borderRadius: BorderRadius.circular(32),
          child: cardContent,
        ),
      ),
    );
  }
  
  /// iOS 风格的卡片
  Widget _buildCupertinoCard(BuildContext context, List<String> coverImages, bool isDark) {
    final now = DateTime.now();
    final dayOfMonth = now.day;
    final weekday = ['周日', '周一', '周二', '周三', '周四', '周五', '周六'][now.weekday % 7];
    
    return GestureDetector(
      onTap: () {
        if (onOpenDetail != null) {
          onOpenDetail!();
        } else {
          Navigator.of(context).push(
            CupertinoPageRoute(
              builder: (context) => DailyRecommendDetailPage(tracks: tracks),
            ),
          );
        }
      },
      child: Container(
        height: 180,
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
        child: ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '每日推荐',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: isDark ? Colors.white : Colors.black,
                    letterSpacing: -0.5,
                  ),
                ),
                const Spacer(),
                Row(
                  children: [
                    _buildDateBadge(context, dayOfMonth, weekday, isDark),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            '根据你的品味生成',
                            style: TextStyle(
                              fontSize: 14,
                              color: isDark
                                  ? Colors.white.withOpacity(0.7)
                                  : Colors.black.withOpacity(0.6),
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '${tracks.length} 首歌曲',
                            style: TextStyle(
                              fontSize: 13,
                              color: isDark
                                  ? Colors.white.withOpacity(0.5)
                                  : Colors.black.withOpacity(0.45),
                            ),
                          ),
                          const SizedBox(height: 10),
                          _buildCoverThumbnails(context, coverImages, isDark),
                        ],
                      ),
                    ),
                    _buildPlayButton(context, isDark),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
  
  /// 日期徽章
  Widget _buildDateBadge(BuildContext context, int day, String weekday, bool isDark) {
    return Container(
      width: 72,
      height: 72,
      decoration: BoxDecoration(
        color: isDark
            ? Colors.white.withOpacity(0.1)
            : Colors.black.withOpacity(0.05),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isDark
              ? Colors.white.withOpacity(0.15)
              : Colors.black.withOpacity(0.08),
          width: 1,
        ),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            day.toString().padLeft(2, '0'),
            style: TextStyle(
              fontSize: 32,
              fontWeight: FontWeight.w700,
              color: ThemeManager.iosBlue,
              height: 1,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            weekday,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w500,
              color: isDark
                  ? Colors.white.withOpacity(0.6)
                  : Colors.black.withOpacity(0.5),
            ),
          ),
        ],
      ),
    );
  }
  
  /// 封面缩略图
  Widget _buildCoverThumbnails(BuildContext context, List<String> coverImages, bool isDark) {
    final displayCovers = coverImages.take(4).toList();
    
    return SizedBox(
      height: 36,
      child: Row(
        children: [
          ...List.generate(displayCovers.length, (index) {
            return Transform.translate(
              offset: Offset(-index * 12.0, 0),
              child: Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: isDark
                        ? Colors.black.withOpacity(0.3)
                        : Colors.white,
                    width: 2,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.15),
                      blurRadius: 4,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: displayCovers[index].isNotEmpty
                      ? CachedNetworkImage(
                          imageUrl: displayCovers[index],
                          fit: BoxFit.cover,
                          memCacheWidth: 280,
                          memCacheHeight: 280,
                        )
                      : Container(
                          color: isDark
                              ? const Color(0xFF3A3A3C)
                              : const Color(0xFFE5E5EA),
                          child: Icon(
                            CupertinoIcons.music_note,
                            size: 16,
                            color: isDark
                                ? Colors.white.withOpacity(0.5)
                                : Colors.black.withOpacity(0.3),
                          ),
                        ),
                ),
              ),
            );
          }),
          if (tracks.length > 4)
            Transform.translate(
              offset: Offset(-displayCovers.length * 12.0, 0),
              child: Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: isDark
                      ? Colors.white.withOpacity(0.15)
                      : Colors.black.withOpacity(0.08),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Center(
                  child: Text(
                    '+${tracks.length - 4}',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: isDark
                          ? Colors.white.withOpacity(0.8)
                          : Colors.black.withOpacity(0.6),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
  
  /// 播放按钮
  Widget _buildPlayButton(BuildContext context, bool isDark) {
    return Container(
      width: 52,
      height: 52,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            ThemeManager.iosBlue,
            ThemeManager.iosBlue.withBlue(230),
          ],
        ),
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(
            color: ThemeManager.iosBlue.withOpacity(0.4),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: const Icon(
        CupertinoIcons.play_fill,
        color: Colors.white,
        size: 24,
      ),
    );
  }
  
  /// Material 风格卡片内容 - Android 16 Expressive Refactor
  Widget _buildMaterialCardContent(BuildContext context, List<String> coverImages, ColorScheme cs) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final bool isNarrow = constraints.maxWidth < 480;
        final EdgeInsets contentPadding = const EdgeInsets.symmetric(horizontal: 20, vertical: 24);
        
        if (isNarrow) {
          return Padding(
            padding: contentPadding,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '每日推荐',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 26,
                          fontWeight: FontWeight.w900,
                          color: cs.onSurface,
                          letterSpacing: -1,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Icon(Icons.auto_awesome, size: 14, color: cs.primary),
                          const SizedBox(width: 4),
                          Expanded(
                            child: Text(
                              '为您精选 ${tracks.length} 首',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w500,
                                color: cs.primary,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Text(
                        '每日凌晨更新，遇见你的心头好',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12,
                          color: cs.onSurface.withOpacity(0.6),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 20),
                SizedBox(
                  width: 100,
                  height: 120,
                  child: _buildTiltedCovers(context, coverImages, isNarrow: true),
                ),
              ],
            ),
          );
        }

        return Container(
          height: 200,
          padding: contentPadding,
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Row(
                      children: [
                        Text(
                          '每日推荐',
                          style: TextStyle(
                            fontSize: 34,
                            fontWeight: FontWeight.w900,
                            color: cs.onSurface,
                            letterSpacing: -1.5,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Icon(
                          Icons.auto_awesome,
                          size: 28,
                          color: cs.primary,
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '专属你的私人音乐品味，${tracks.length} 首好歌每日准时送达',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w500,
                        color: cs.onSurface.withOpacity(0.7),
                        height: 1.3,
                      ),
                    ),
                    const Spacer(),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      decoration: BoxDecoration(
                        color: cs.primary.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            '查看全部',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.bold,
                              color: cs.primary,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Icon(Icons.arrow_forward_ios, size: 12, color: cs.primary),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 32),
              SizedBox(
                width: 160,
                height: 160,
                child: _buildTiltedCovers(context, coverImages),
              ),
            ],
          ),
        );
      },
    );
  }
  
  /// 构建倾斜堆叠封面 (Fluent UI Inspired)
  Widget _buildTiltedCovers(BuildContext context, List<String> coverImages, {bool isNarrow = false}) {
    final cs = Theme.of(context).colorScheme;
    final displayCovers = coverImages.take(3).toList();
    while (displayCovers.length < 3) {
      displayCovers.add('');
    }

    final double size = isNarrow ? 80 : 120;
    
    return Stack(
      alignment: Alignment.center,
      children: [
        // 最底层封面 (向左倾斜)
        _buildSingleTiltedCover(
          displayCovers[2], 
          cs, 
          size: size * 0.85, 
          angle: -0.2, 
          offset: const Offset(-20, -10),
          opacity: 0.5,
        ),
        // 中间层封面 (向右倾斜)
        _buildSingleTiltedCover(
          displayCovers[1], 
          cs, 
          size: size * 0.92, 
          angle: 0.15, 
          offset: const Offset(15, 0),
          opacity: 0.8,
        ),
        // 最上层封面 (正面)
        _buildSingleTiltedCover(
          displayCovers[0], 
          cs, 
          size: size, 
          angle: 0, 
          offset: Offset.zero,
          opacity: 1.0,
          hasShadow: true,
        ),
      ],
    );
  }

  Widget _buildSingleTiltedCover(
    String url, 
    ColorScheme cs, {
    required double size, 
    required double angle, 
    required Offset offset,
    required double opacity,
    bool hasShadow = false,
  }) {
    return Transform.translate(
      offset: offset,
      child: Transform.rotate(
        angle: angle,
        child: Opacity(
          opacity: opacity,
          child: Container(
            width: size,
            height: size,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(isNarrow ? 12 : 16),
              boxShadow: hasShadow ? [
                BoxShadow(
                  color: Colors.black.withOpacity(0.2),
                  blurRadius: 15,
                  offset: const Offset(0, 8),
                ),
              ] : [],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(isNarrow ? 12 : 16),
              child: url.isEmpty
                  ? Container(
                      color: cs.surfaceContainerHighest,
                      child: Icon(
                        Icons.music_note,
                        size: size * 0.4,
                        color: cs.onSurface.withOpacity(0.3),
                      ),
                    )
                  : CachedNetworkImage(
                      imageUrl: url,
                      fit: BoxFit.cover,
                      memCacheWidth: 280,
                      memCacheHeight: 280,
                      placeholder: (context, url) => Container(
                        color: cs.surfaceContainerHighest,
                      ),
                    ),
            ),
          ),
        ),
      ),
    );
  }

  bool get isNarrow => false; // Dummy getter for the helper method if needed, but actually passed as params
}
