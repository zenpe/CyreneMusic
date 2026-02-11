import 'dart:io';
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../models/track.dart';
import '../../services/player_service.dart';
import '../../services/playlist_queue_service.dart';
import '../../utils/theme_manager.dart';

/// 转换为 Track 对象
Track convertToTrack(Map<String, dynamic> song) {
  final album = (song['al'] ?? song['album'] ?? {}) as Map<String, dynamic>;
  final artists = (song['ar'] ?? song['artists'] ?? []) as List<dynamic>;
  return Track(
    id: song['id'] ?? 0,
    name: song['name']?.toString() ?? '',
    artists: artists.map((e) => (e as Map<String, dynamic>)['name']?.toString() ?? '').where((e) => e.isNotEmpty).join(' / '),
    album: album['name']?.toString() ?? '',
    picUrl: album['picUrl']?.toString() ?? '',
    source: MusicSource.netease,
  );
}

/// Hero 双卡区域 - 每日推荐 + 私人FM 并排
class HeroSection extends StatelessWidget {
  final List<Map<String, dynamic>> dailySongs;
  final List<Map<String, dynamic>> fmList;
  final VoidCallback? onOpenDailyDetail;
  
  const HeroSection({
    super.key,
    required this.dailySongs,
    required this.fmList,
    this.onOpenDailyDetail,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isWide = constraints.maxWidth >= 600;
        if (isWide) {
          // 宽屏：左右并排，左边大右边小
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(flex: 3, child: DailyRecommendHeroCard(tracks: dailySongs, onOpenDetail: onOpenDailyDetail)),
              const SizedBox(width: 16),
              Expanded(flex: 2, child: PersonalFmCompactCard(list: fmList)),
            ],
          );
        } else {
          // 窄屏：上下堆叠
          return Column(
            children: [
              DailyRecommendHeroCard(tracks: dailySongs, onOpenDetail: onOpenDailyDetail),
              const SizedBox(height: 12),
              PersonalFmCompactCard(list: fmList),
            ],
          );
        }
      },
    );
  }
}

/// 每日推荐 Hero 大卡片
class DailyRecommendHeroCard extends StatefulWidget {
  final List<Map<String, dynamic>> tracks;
  final VoidCallback? onOpenDetail;
  const DailyRecommendHeroCard({super.key, required this.tracks, this.onOpenDetail});

  @override
  State<DailyRecommendHeroCard> createState() => _DailyRecommendHeroCardState();
}

class _DailyRecommendHeroCardState extends State<DailyRecommendHeroCard> {
  bool _hovering = false;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final themeManager = ThemeManager();
    final isCupertino = (Platform.isIOS || Platform.isAndroid) && themeManager.isCupertinoFramework;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final now = DateTime.now();
    
    final coverImages = widget.tracks.take(6).map((s) {
      final al = (s['al'] ?? s['album'] ?? {}) as Map<String, dynamic>;
      return (al['picUrl'] ?? '').toString();
    }).where((url) => url.isNotEmpty).toList();

    return MouseRegion(
      onEnter: (_) => setState(() => _hovering = true),
      onExit: (_) => setState(() => _hovering = false),
      child: GestureDetector(
        onTap: widget.onOpenDetail,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
          height: 220,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: isDark 
                  ? [cs.primary.withOpacity(0.3), cs.primaryContainer.withOpacity(0.2)]
                  : [cs.primary.withOpacity(0.15), cs.primaryContainer.withOpacity(0.3)],
            ),
            boxShadow: _hovering ? [
              BoxShadow(color: cs.primary.withOpacity(0.2), blurRadius: 20, offset: const Offset(0, 8)),
            ] : [
              BoxShadow(color: Colors.black.withOpacity(0.1), blurRadius: 10, offset: const Offset(0, 4)),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: Stack(
              children: [
                // 背景封面拼贴
                Positioned(
                  right: -20, top: -20, bottom: -20,
                  child: SizedBox(
                    width: 280,
                    child: Transform.rotate(
                      angle: 0.1,
                      child: Opacity(
                        opacity: 0.4,
                        child: _buildCoverMosaic(coverImages),
                      ),
                    ),
                  ),
                ),
                // 渐变遮罩
                Container(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.centerLeft,
                      end: Alignment.centerRight,
                      colors: [
                        isDark ? Colors.black.withOpacity(0.8) : Colors.white.withOpacity(0.9),
                        Colors.transparent,
                      ],
                    ),
                  ),
                ),
                // 内容
                Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // 日期徽章
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(
                          color: cs.primary,
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.calendar_today, size: 14, color: cs.onPrimary),
                            const SizedBox(width: 6),
                            Text('${now.month}月${now.day}日', 
                              style: TextStyle(color: cs.onPrimary, fontWeight: FontWeight.w600, fontSize: 13)),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),
                      Text('每日推荐', style: TextStyle(
                        fontSize: 28, fontWeight: FontWeight.bold,
                        color: isDark ? Colors.white : Colors.black87,
                      )),
                      const SizedBox(height: 8),
                      Text('根据你的音乐品味精选 ${widget.tracks.length} 首',
                        style: TextStyle(fontSize: 14, color: isDark ? Colors.white70 : Colors.black54)),
                      const Spacer(),
                      // 播放按钮
                      Row(
                        children: [
                          GradientPlayButton(
                            onPressed: () async {
                              final tracks = widget.tracks.map((m) => convertToTrack(m)).toList();
                              if (tracks.isEmpty) return;
                              PlaylistQueueService().setQueue(tracks, 0, QueueSource.playlist);
                              await PlayerService().playTrack(tracks.first);
                            },
                          ),
                          const SizedBox(width: 12),
                          AnimatedOpacity(
                            opacity: _hovering ? 1.0 : 0.0,
                            duration: const Duration(milliseconds: 200),
                            child: Text('立即播放', style: TextStyle(
                              color: cs.primary, fontWeight: FontWeight.w600)),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildCoverMosaic(List<String> covers) {
    return GridView.builder(
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2, crossAxisSpacing: 4, mainAxisSpacing: 4,
      ),
      itemCount: covers.length.clamp(0, 6),
      itemBuilder: (context, i) {
        return ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: CachedNetworkImage(imageUrl: covers[i], fit: BoxFit.cover, memCacheWidth: 280, memCacheHeight: 280),
        );
      },
    );
  }
}

/// 私人FM 紧凑卡片
class PersonalFmCompactCard extends StatelessWidget {
  final List<Map<String, dynamic>> list;
  const PersonalFmCompactCard({super.key, required this.list});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final themeManager = ThemeManager();
    final isDark = Theme.of(context).brightness == Brightness.dark;
    
    if (list.isEmpty) return const SizedBox.shrink();
    
    return AnimatedBuilder(
      animation: PlayerService(),
      builder: (context, _) {
        Map<String, dynamic> display = list.first;
        final current = PlayerService().currentTrack;
        if (current != null && current.source == MusicSource.netease) {
          for (final m in list) {
            final id = (m['id'] ?? (m['song'] != null ? (m['song'] as Map<String, dynamic>)['id'] : null));
            if (id != null && id.toString() == current.id.toString()) {
              display = m;
              break;
            }
          }
        }

        final album = (display['album'] ?? display['al'] ?? {}) as Map<String, dynamic>;
        final artists = (display['artists'] ?? display['ar'] ?? []) as List<dynamic>;
        final artistsText = artists.map((e) => (e as Map<String, dynamic>)['name']?.toString() ?? '').where((e) => e.isNotEmpty).join('/');
        final pic = (album['picUrl'] ?? '').toString();
        final fmTracks = list.map((m) => convertToTrack(m)).toList();
        final isFmPlaying = PlayerService().isPlaying && _currentTrackInList(fmTracks);

        return Container(
          height: 220,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            color: isDark ? const Color(0xFF1E1E2E) : Colors.white,
            boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.08), blurRadius: 10, offset: const Offset(0, 4))],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: Stack(
              children: [
                // 背景封面模糊
                if (pic.isNotEmpty)
                  Positioned.fill(
                    child: Opacity(
                      opacity: 0.15,
                      child: CachedNetworkImage(imageUrl: pic, fit: BoxFit.cover, memCacheWidth: 200, memCacheHeight: 200),
                    ),
                  ),
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.radio, size: 18, color: cs.primary),
                          const SizedBox(width: 6),
                          Text('私人FM', style: TextStyle(fontWeight: FontWeight.bold, color: cs.primary)),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Expanded(
                        child: Row(
                          children: [
                            // 封面
                            ClipRRect(
                              borderRadius: BorderRadius.circular(12),
                              child: SizedBox(
                                width: 100, height: 100,
                                child: pic.isNotEmpty 
                                    ? CachedNetworkImage(imageUrl: pic, fit: BoxFit.cover, memCacheWidth: 200, memCacheHeight: 200)
                                    : Container(color: cs.surfaceContainerHighest, child: Icon(Icons.music_note, color: cs.onSurface.withOpacity(0.3))),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Text(display['name']?.toString() ?? '', maxLines: 2, overflow: TextOverflow.ellipsis,
                                    style: TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
                                  const SizedBox(height: 4),
                                  Text(artistsText, maxLines: 1, overflow: TextOverflow.ellipsis,
                                    style: TextStyle(fontSize: 13, color: cs.onSurface.withOpacity(0.6))),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 12),
                      // 控制按钮
                      Row(
                        children: [
                          Expanded(
                            child: FmControlButton(
                              icon: isFmPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
                              label: isFmPlaying ? '暂停' : '播放',
                              onPressed: () async {
                                if (fmTracks.isEmpty) return;
                                final ps = PlayerService();
                                if (isFmPlaying) {
                                  await ps.pause();
                                } else if (ps.isPaused && _currentTrackInList(fmTracks)) {
                                  await ps.resume();
                                } else {
                                  PlaylistQueueService().setQueue(fmTracks, 0, QueueSource.playlist);
                                  await ps.playTrack(fmTracks.first);
                                }
                              },
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: FmControlButton(
                              icon: Icons.skip_next_rounded,
                              label: '下一首',
                              onPressed: () async {
                                if (fmTracks.isEmpty) return;
                                if (_isSameQueueAs(fmTracks)) {
                                  await PlayerService().playNext();
                                } else {
                                  final startIndex = fmTracks.length > 1 ? 1 : 0;
                                  PlaylistQueueService().setQueue(fmTracks, startIndex, QueueSource.playlist);
                                  await PlayerService().playTrack(fmTracks[startIndex]);
                                }
                              },
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  bool _currentTrackInList(List<Track> tracks) {
    final ct = PlayerService().currentTrack;
    if (ct == null) return false;
    return tracks.any((t) => t.id.toString() == ct.id.toString() && t.source == ct.source);
  }

  bool _isSameQueueAs(List<Track> tracks) {
    final q = PlaylistQueueService().queue;
    if (q.length != tracks.length) return false;
    for (var i = 0; i < q.length; i++) {
      if (q[i].id.toString() != tracks[i].id.toString() || q[i].source != tracks[i].source) return false;
    }
    return true;
  }
}

/// FM 控制按钮
class FmControlButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onPressed;
  const FmControlButton({super.key, required this.icon, required this.label, required this.onPressed});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Material(
      color: cs.primaryContainer.withOpacity(0.5),
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: onPressed,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 10),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 20, color: cs.primary),
              const SizedBox(width: 6),
              Text(label, style: TextStyle(color: cs.primary, fontWeight: FontWeight.w600, fontSize: 13)),
            ],
          ),
        ),
      ),
    );
  }
}

/// 渐变播放按钮
class GradientPlayButton extends StatefulWidget {
  final VoidCallback onPressed;
  const GradientPlayButton({super.key, required this.onPressed});

  @override
  State<GradientPlayButton> createState() => _GradientPlayButtonState();
}

class _GradientPlayButtonState extends State<GradientPlayButton> {
  bool _hovering = false;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return MouseRegion(
      onEnter: (_) => setState(() => _hovering = true),
      onExit: (_) => setState(() => _hovering = false),
      child: GestureDetector(
        onTap: widget.onPressed,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [cs.primary, cs.primary.withOpacity(0.7)],
            ),
            boxShadow: _hovering ? [
              BoxShadow(color: cs.primary.withOpacity(0.4), blurRadius: 16, offset: const Offset(0, 4)),
            ] : [],
          ),
          child: Icon(Icons.play_arrow_rounded, color: cs.onPrimary, size: 28),
        ),
      ),
    );
  }
}
