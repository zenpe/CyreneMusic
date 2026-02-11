import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';

/// 雷达歌单网格 - 统一尺寸
class MixedSizePlaylistGrid extends StatelessWidget {
  final List<Map<String, dynamic>> list;
  final void Function(int id)? onTap;
  const MixedSizePlaylistGrid({super.key, required this.list, this.onTap});

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
            separatorBuilder: (_, __) => const SizedBox(width: 12),
            itemBuilder: (context, i) {
              return SizedBox(
                width: 150,
                child: MixedPlaylistCard(playlist: list[i], isLarge: false, onTap: onTap),
              );
            },
          ),
        );
      },
    );
  }
}

/// 混合歌单卡片
class MixedPlaylistCard extends StatefulWidget {
  final Map<String, dynamic> playlist;
  final bool isLarge;
  final void Function(int id)? onTap;
  const MixedPlaylistCard({super.key, required this.playlist, this.isLarge = false, this.onTap});

  @override
  State<MixedPlaylistCard> createState() => _MixedPlaylistCardState();
}

class _MixedPlaylistCardState extends State<MixedPlaylistCard> {
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
        child: Column(
          children: [
            Expanded(
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(widget.isLarge ? 16 : 12),
                  boxShadow: _hovering ? [
                    BoxShadow(color: cs.shadow.withOpacity(0.15), blurRadius: 12, offset: const Offset(0, 4)),
                  ] : [],
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(widget.isLarge ? 16 : 12),
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      AnimatedScale(
                        scale: _hovering ? 1.08 : 1.0,
                        duration: const Duration(milliseconds: 200),
                        child: CachedNetworkImage(imageUrl: pic, fit: BoxFit.cover, memCacheWidth: 280, memCacheHeight: 280),
                      ),
                      AnimatedOpacity(
                        opacity: _hovering ? 1.0 : 0.0,
                        duration: const Duration(milliseconds: 200),
                        child: Container(
                          color: Colors.black.withOpacity(0.3),
                          child: Center(
                            child: Container(
                              width: 40, height: 40,
                              decoration: BoxDecoration(
                                color: Colors.white.withOpacity(0.9),
                                shape: BoxShape.circle,
                              ),
                              child: Icon(Icons.play_arrow_rounded, color: cs.primary, size: 24),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 8),
            Text(name, maxLines: 1, overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: widget.isLarge ? 14 : 12, fontWeight: FontWeight.w600)),
          ],
        ),
      ),
    );
  }
}
