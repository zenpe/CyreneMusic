import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';

/// 横向滚动歌单 - Microsoft Store 风格
class HorizontalPlaylistCarousel extends StatelessWidget {
  final List<Map<String, dynamic>> list;
  final void Function(int id)? onTap;
  const HorizontalPlaylistCarousel({super.key, required this.list, this.onTap});

  @override
  Widget build(BuildContext context) {
    if (list.isEmpty) return Text('暂无数据', style: Theme.of(context).textTheme.bodySmall);

    return LayoutBuilder(
      builder: (context, constraints) {
        return SizedBox(
          height: 200,
          width: constraints.maxWidth,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            clipBehavior: Clip.none,
            itemCount: list.length,
            separatorBuilder: (_, __) => const SizedBox(width: 16),
            itemBuilder: (context, i) => CarouselPlaylistCard(playlist: list[i], onTap: onTap),
          ),
        );
      },
    );
  }
}

/// 轮播歌单卡片
class CarouselPlaylistCard extends StatefulWidget {
  final Map<String, dynamic> playlist;
  final void Function(int id)? onTap;
  const CarouselPlaylistCard({super.key, required this.playlist, this.onTap});

  @override
  State<CarouselPlaylistCard> createState() => _CarouselPlaylistCardState();
}

class _CarouselPlaylistCardState extends State<CarouselPlaylistCard> {
  bool _hovering = false;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final pic = (widget.playlist['picUrl'] ?? widget.playlist['coverImgUrl'] ?? '').toString();
    final name = widget.playlist['name']?.toString() ?? '';
    final desc = (widget.playlist['description'] ?? widget.playlist['copywriter'] ?? '').toString();
    final id = int.tryParse(widget.playlist['id']?.toString() ?? '');

    return MouseRegion(
      onEnter: (_) => setState(() => _hovering = true),
      onExit: (_) => setState(() => _hovering = false),
      child: GestureDetector(
        onTap: id != null && widget.onTap != null ? () => widget.onTap!(id) : null,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          width: 320,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            color: isDark ? const Color(0xFF1E1E2E) : Colors.white,
            boxShadow: _hovering ? [
              BoxShadow(color: cs.primary.withOpacity(0.15), blurRadius: 20, offset: const Offset(0, 8)),
            ] : [
              BoxShadow(color: Colors.black.withOpacity(0.08), blurRadius: 10, offset: const Offset(0, 4)),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: Row(
              children: [
                // 封面
                SizedBox(
                  width: 160, height: 200,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      AnimatedScale(
                        scale: _hovering ? 1.05 : 1.0,
                        duration: const Duration(milliseconds: 200),
                        child: CachedNetworkImage(imageUrl: pic, fit: BoxFit.cover, memCacheWidth: 280, memCacheHeight: 280),
                      ),
                      // 播放按钮
                      Center(
                        child: AnimatedOpacity(
                          opacity: _hovering ? 1.0 : 0.0,
                          duration: const Duration(milliseconds: 200),
                          child: Container(
                            width: 48, height: 48,
                            decoration: BoxDecoration(
                              color: Colors.white.withOpacity(0.9),
                              shape: BoxShape.circle,
                            ),
                            child: Icon(Icons.play_arrow_rounded, color: cs.primary, size: 28),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                // 信息
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(name, maxLines: 2, overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                        const SizedBox(height: 8),
                        Expanded(
                          child: Text(desc.isNotEmpty ? desc : '精选歌单', maxLines: 4, overflow: TextOverflow.ellipsis,
                            style: TextStyle(fontSize: 12, color: cs.onSurface.withOpacity(0.6))),
                        ),
                      ],
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
