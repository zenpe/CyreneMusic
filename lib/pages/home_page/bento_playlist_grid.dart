import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';

/// Bento 网格歌单 - 1大+4小布局
class BentoPlaylistGrid extends StatelessWidget {
  final List<Map<String, dynamic>> list;
  final void Function(int id)? onTap;
  const BentoPlaylistGrid({super.key, required this.list, this.onTap});

  @override
  Widget build(BuildContext context) {
    if (list.isEmpty) return Text('暂无数据', style: Theme.of(context).textTheme.bodySmall);
    
    return LayoutBuilder(
      builder: (context, constraints) {
        final isWide = constraints.maxWidth >= 600;
        
        if (isWide && list.length >= 5) {
          // Bento 布局：左边大卡+右边 2x2
          return SizedBox(
            height: 320,
            child: Row(
              children: [
                Expanded(flex: 3, child: LargePlaylistCard(playlist: list[0], onTap: onTap)),
                const SizedBox(width: 12),
                Expanded(
                  flex: 4,
                  child: Column(
                    children: [
                      Expanded(
                        child: Row(
                          children: [
                            Expanded(child: SmallPlaylistCard(playlist: list[1], onTap: onTap)),
                            const SizedBox(width: 12),
                            Expanded(child: SmallPlaylistCard(playlist: list[2], onTap: onTap)),
                          ],
                        ),
                      ),
                      const SizedBox(height: 12),
                      Expanded(
                        child: Row(
                          children: [
                            Expanded(child: SmallPlaylistCard(playlist: list[3], onTap: onTap)),
                            const SizedBox(width: 12),
                            Expanded(child: SmallPlaylistCard(playlist: list[4], onTap: onTap)),
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
        
        // 默认网格
        return GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
            maxCrossAxisExtent: 200, childAspectRatio: 0.75, crossAxisSpacing: 12, mainAxisSpacing: 12,
          ),
          itemCount: list.length.clamp(0, 6),
          itemBuilder: (context, i) => SmallPlaylistCard(playlist: list[i], onTap: onTap),
        );
      },
    );
  }
}

/// 大型歌单卡片
class LargePlaylistCard extends StatefulWidget {
  final Map<String, dynamic> playlist;
  final void Function(int id)? onTap;
  const LargePlaylistCard({super.key, required this.playlist, this.onTap});

  @override
  State<LargePlaylistCard> createState() => _LargePlaylistCardState();
}

class _LargePlaylistCardState extends State<LargePlaylistCard> {
  bool _hovering = false;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final pic = (widget.playlist['picUrl'] ?? widget.playlist['coverImgUrl'] ?? '').toString();
    final name = widget.playlist['name']?.toString() ?? '';
    final id = int.tryParse(widget.playlist['id']?.toString() ?? '');

    return MouseRegion(
      onEnter: (_) => setState(() => _hovering = true),
      onExit: (_) => setState(() => _hovering = false),
      child: GestureDetector(
        onTap: id != null && widget.onTap != null ? () => widget.onTap!(id) : null,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            boxShadow: _hovering ? [
              BoxShadow(color: cs.primary.withOpacity(0.2), blurRadius: 20, offset: const Offset(0, 8)),
            ] : [
              BoxShadow(color: Colors.black.withOpacity(0.1), blurRadius: 10, offset: const Offset(0, 4)),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: Stack(
              fit: StackFit.expand,
              children: [
                AnimatedScale(
                  scale: _hovering ? 1.05 : 1.0,
                  duration: const Duration(milliseconds: 200),
                  child: CachedNetworkImage(imageUrl: pic, fit: BoxFit.cover, memCacheWidth: 280, memCacheHeight: 280),
                ),
                // 渐变遮罩
                Container(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter, end: Alignment.bottomCenter,
                      colors: [Colors.transparent, Colors.black.withOpacity(0.7)],
                    ),
                  ),
                ),
                // 播放按钮
                Positioned(
                  right: 16, bottom: 60,
                  child: AnimatedOpacity(
                    opacity: _hovering ? 1.0 : 0.0,
                    duration: const Duration(milliseconds: 200),
                    child: Container(
                      width: 48, height: 48,
                      decoration: BoxDecoration(
                        color: cs.primary,
                        shape: BoxShape.circle,
                        boxShadow: [BoxShadow(color: cs.primary.withOpacity(0.4), blurRadius: 12)],
                      ),
                      child: Icon(Icons.play_arrow_rounded, color: cs.onPrimary, size: 28),
                    ),
                  ),
                ),
                // 标题
                Positioned(
                  left: 16, right: 16, bottom: 16,
                  child: Text(name, maxLines: 2, overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// 小型歌单卡片
class SmallPlaylistCard extends StatefulWidget {
  final Map<String, dynamic> playlist;
  final void Function(int id)? onTap;
  const SmallPlaylistCard({super.key, required this.playlist, this.onTap});

  @override
  State<SmallPlaylistCard> createState() => _SmallPlaylistCardState();
}

class _SmallPlaylistCardState extends State<SmallPlaylistCard> {
  bool _hovering = false;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final pic = (widget.playlist['picUrl'] ?? widget.playlist['coverImgUrl'] ?? '').toString();
    final name = widget.playlist['name']?.toString() ?? '';
    final id = int.tryParse(widget.playlist['id']?.toString() ?? '');

    return MouseRegion(
      onEnter: (_) => setState(() => _hovering = true),
      onExit: (_) => setState(() => _hovering = false),
      child: GestureDetector(
        onTap: id != null && widget.onTap != null ? () => widget.onTap!(id) : null,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            boxShadow: _hovering ? [
              BoxShadow(color: cs.shadow.withOpacity(0.15), blurRadius: 12, offset: const Offset(0, 4)),
            ] : [],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: Stack(
              fit: StackFit.expand,
              children: [
                AnimatedScale(
                  scale: _hovering ? 1.05 : 1.0,
                  duration: const Duration(milliseconds: 200),
                  child: CachedNetworkImage(imageUrl: pic, fit: BoxFit.cover, memCacheWidth: 280, memCacheHeight: 280),
                ),
                Container(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter, end: Alignment.bottomCenter,
                      colors: [Colors.transparent, Colors.black.withOpacity(0.6)],
                    ),
                  ),
                ),
                Positioned(
                  left: 8, right: 8, bottom: 8,
                  child: Text(name, maxLines: 2, overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600)),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
