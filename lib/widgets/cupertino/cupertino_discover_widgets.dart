import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../models/netease_discover.dart';
import '../../utils/theme_manager.dart';

/// iOS 风格的歌单卡片
class CupertinoDiscoverPlaylistCard extends StatelessWidget {
  final NeteasePlaylistSummary summary;
  final VoidCallback? onTap;

  const CupertinoDiscoverPlaylistCard({
    super.key,
    required this.summary,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = CupertinoTheme.of(context).brightness == Brightness.dark;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF1C1C1E) : CupertinoColors.white,
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            BoxShadow(
              color: CupertinoColors.black.withOpacity(isDark ? 0.3 : 0.05),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 封面图
            AspectRatio(
              aspectRatio: 1,
              child: ClipRRect(
                borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    CachedNetworkImage(
                      imageUrl: summary.coverImgUrl,
                      fit: BoxFit.cover,
                      memCacheWidth: 280,
                      memCacheHeight: 280,
                      placeholder: (context, url) => Container(
                        color: isDark ? const Color(0xFF2C2C2E) : CupertinoColors.systemGrey6,
                        child: const CupertinoActivityIndicator(),
                      ),
                      errorWidget: (context, url, error) => Container(
                        color: isDark ? const Color(0xFF2C2C2E) : CupertinoColors.systemGrey6,
                        child: const Icon(CupertinoIcons.music_note_2, color: CupertinoColors.systemGrey),
                      ),
                    ),
                    // 播放量遮罩
                    Positioned(
                      top: 6,
                      right: 6,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: CupertinoColors.black.withOpacity(0.6),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(CupertinoIcons.play_fill, color: Colors.white, size: 10),
                            const SizedBox(width: 2),
                            Text(
                              _formatPlayCount(summary.playCount),
                              style: const TextStyle(color: Colors.white, fontSize: 10),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            // 信息区域
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      summary.name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: isDark ? CupertinoColors.white : CupertinoColors.black,
                        height: 1.2,
                      ),
                    ),
                    const Spacer(),
                    Text(
                      summary.creatorNickname,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 11,
                        color: CupertinoColors.systemGrey,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _formatPlayCount(int count) {
    if (count > 100000000) {
      return '${(count / 100000000).toStringAsFixed(1)}亿';
    }
    if (count > 10000) {
      return '${(count / 10000).toStringAsFixed(1)}万';
    }
    return count.toString();
  }
}

/// iOS 风格的标签选择器 (Capsule Style)
class CupertinoTagSelector extends StatelessWidget {
  final String currentTag;
  final VoidCallback onTap;

  const CupertinoTagSelector({
    super.key,
    required this.currentTag,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = CupertinoTheme.of(context).brightness == Brightness.dark;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: ThemeManager.iosBlue.withOpacity(0.1),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: ThemeManager.iosBlue.withOpacity(0.3),
            width: 1,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              currentTag.isEmpty ? '全部歌单' : currentTag,
              style: TextStyle(
                color: ThemeManager.iosBlue,
                fontSize: 15,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(width: 4),
            Icon(
              CupertinoIcons.chevron_down,
              size: 14,
              color: ThemeManager.iosBlue,
            ),
          ],
        ),
      ),
    );
  }
}
