import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../services/player_service.dart';
import '../../services/playlist_queue_service.dart';
import 'hero_section.dart'; // 复用 convertToTrack 函数

/// 新歌卡片网格
class NewsongCards extends StatelessWidget {
  final List<Map<String, dynamic>> list;
  const NewsongCards({super.key, required this.list});

  @override
  Widget build(BuildContext context) {
    if (list.isEmpty) return Text('暂无数据', style: Theme.of(context).textTheme.bodySmall);

    return LayoutBuilder(
      builder: (context, constraints) {
        return SizedBox(
          height: 180,
          width: constraints.maxWidth,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            clipBehavior: Clip.none,
            itemCount: list.length,
            separatorBuilder: (_, __) => const SizedBox(width: 12),
            itemBuilder: (context, i) => NewsongCard(song: list[i]),
          ),
        );
      },
    );
  }
}

/// 新歌卡片
class NewsongCard extends StatefulWidget {
  final Map<String, dynamic> song;
  const NewsongCard({super.key, required this.song});

  @override
  State<NewsongCard> createState() => _NewsongCardState();
}

class _NewsongCardState extends State<NewsongCard> {
  bool _hovering = false;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final songData = widget.song['song'] ?? widget.song;
    final al = (songData['al'] ?? songData['album'] ?? {}) as Map<String, dynamic>;
    final ar = (songData['ar'] ?? songData['artists'] ?? []) as List<dynamic>;
    final pic = (al['picUrl'] ?? '').toString();
    final name = songData['name']?.toString() ?? '';
    final artists = ar.map((e) => (e as Map<String, dynamic>)['name']?.toString() ?? '').where((e) => e.isNotEmpty).join('/');

    return MouseRegion(
      onEnter: (_) => setState(() => _hovering = true),
      onExit: (_) => setState(() => _hovering = false),
      child: GestureDetector(
        onTap: () async {
          final track = convertToTrack(songData);
          PlaylistQueueService().setQueue([track], 0, QueueSource.search);
          await PlayerService().playTrack(track);
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          width: 140,
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            color: isDark ? const Color(0xFF1E1E2E) : Colors.white,
            boxShadow: _hovering ? [
              BoxShadow(color: cs.shadow.withOpacity(0.12), blurRadius: 12, offset: const Offset(0, 4)),
            ] : [
              BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 6, offset: const Offset(0, 2)),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 封面
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: Stack(
                    children: [
                      AnimatedScale(
                        scale: _hovering ? 1.05 : 1.0,
                        duration: const Duration(milliseconds: 200),
                        child: SizedBox.expand(
                          child: CachedNetworkImage(imageUrl: pic, fit: BoxFit.cover, memCacheWidth: 280, memCacheHeight: 280),
                        ),
                      ),
                      if (_hovering)
                        Positioned.fill(
                          child: Container(
                            color: Colors.black.withOpacity(0.3),
                            child: Center(
                              child: Container(
                                width: 36, height: 36,
                                decoration: BoxDecoration(
                                  color: Colors.white.withOpacity(0.9),
                                  shape: BoxShape.circle,
                                ),
                                child: Icon(Icons.play_arrow_rounded, color: cs.primary, size: 22),
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Text(name, maxLines: 1, overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12)),
              const SizedBox(height: 2),
              Text(artists, maxLines: 1, overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 10, color: cs.onSurface.withOpacity(0.6))),
            ],
          ),
        ),
      ),
    );
  }
}
