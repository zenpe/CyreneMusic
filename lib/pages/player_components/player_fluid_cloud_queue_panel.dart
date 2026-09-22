import '../../services/structured_log_service.dart';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../services/player_service.dart';
import '../../services/playlist_queue_service.dart';
import '../../services/playback/playback_service.dart';
import '../../services/netease_artist_service.dart';
import '../../utils/image_utils.dart';
import '../../models/track.dart';
import '../../widgets/track_action_menu.dart';

/// 流体云专用播放队列面板
/// 对标 Apple Music 设计：无边框、半透明、大封面、沉浸式体验
/// 对于网易云音源，额外显示同一歌手的其他音乐推荐
class PlayerFluidCloudQueuePanel extends StatefulWidget {
  const PlayerFluidCloudQueuePanel({super.key});

  @override
  State<PlayerFluidCloudQueuePanel> createState() => _PlayerFluidCloudQueuePanelState();
}

class _PlayerFluidCloudQueuePanelState extends State<PlayerFluidCloudQueuePanel> {
  final ScrollController _scrollController = ScrollController();

  // 歌手相关歌曲推荐
  List<Track> _artistSongs = [];
  bool _artistSongsLoading = false;
  String? _lastArtistName; // 用于判断歌手是否变化
  int? _lastArtistId; // 缓存歌手ID

  @override
  void initState() {
    super.initState();
    PlayerService().addListener(_onPlayerChanged);
    _loadArtistSongs();
  }

  @override
  void dispose() {
    PlayerService().removeListener(_onPlayerChanged);
    _scrollController.dispose();
    super.dispose();
  }

  void _onPlayerChanged() {
    _loadArtistSongs();
  }

  /// 加载当前歌手的其他歌曲
  Future<void> _loadArtistSongs() async {
    final currentTrack = PlayerService().currentTrack;

    // 仅对网易云音源生效
    if (currentTrack == null || currentTrack.source != MusicSource.netease) {
      if (_artistSongs.isNotEmpty) {
        setState(() {
          _artistSongs = [];
          _lastArtistName = null;
          _lastArtistId = null;
        });
      }
      return;
    }

    // 提取第一个歌手名（通常格式为 "歌手1/歌手2" 或 "歌手1、歌手2"）
    final artistName = _extractFirstArtist(currentTrack.artists);
    if (artistName.isEmpty) return;

    // 如果歌手名没有变化，不重复加载
    if (artistName == _lastArtistName && _artistSongs.isNotEmpty) {
      return;
    }

    setState(() {
      _artistSongsLoading = true;
    });

    try {
      // 1. 先通过歌手名获取歌手ID
      int? artistId = _lastArtistId;
      if (artistName != _lastArtistName) {
        artistId = await NeteaseArtistDetailService().resolveArtistIdByName(artistName);
        StructuredLogService.log('🎤 [QueuePanel] 搜索歌手 "$artistName" -> ID: $artistId');
      }

      if (artistId == null) {
        setState(() {
          _artistSongs = [];
          _artistSongsLoading = false;
          _lastArtistName = artistName;
          _lastArtistId = null;
        });
        return;
      }

      // 2. 获取歌手详情（包含歌曲列表）
      final artistDetail = await NeteaseArtistDetailService().fetchArtistDetail(artistId);
      if (artistDetail == null) {
        setState(() {
          _artistSongs = [];
          _artistSongsLoading = false;
          _lastArtistName = artistName;
          _lastArtistId = artistId;
        });
        return;
      }

      // 3. 提取歌曲列表
      final songsData = (artistDetail['songs'] as List<dynamic>?) ?? [];
      final currentTrackId = currentTrack.id.toString();
      final queueTrackIds = PlaylistQueueService().queue.map((t) => t.id.toString()).toSet();

      final tracks = songsData
          .map((s) {
            final m = s as Map<String, dynamic>;
            return Track(
              id: m['id'],
              name: m['name']?.toString() ?? '',
              artists: m['artists']?.toString() ?? '',
              album: m['album']?.toString() ?? '',
              picUrl: m['picUrl']?.toString() ?? '',
              source: MusicSource.netease,
            );
          })
          // 过滤掉当前播放的歌曲和已在队列中的歌曲
          .where((t) =>
              t.id.toString() != currentTrackId &&
              !queueTrackIds.contains(t.id.toString()))
          .take(20) // 最多显示20首
          .toList();

      StructuredLogService.log('🎵 [QueuePanel] 获取歌手 "$artistName" 的 ${tracks.length} 首推荐歌曲');

      if (mounted) {
        setState(() {
          _artistSongs = tracks;
          _artistSongsLoading = false;
          _lastArtistName = artistName;
          _lastArtistId = artistId;
        });
      }
    } catch (e) {
      StructuredLogService.log('❌ [QueuePanel] 加载歌手歌曲失败: $e');
      if (mounted) {
        setState(() {
          _artistSongs = [];
          _artistSongsLoading = false;
        });
      }
    }
  }

  /// 提取第一个歌手名
  String _extractFirstArtist(String artists) {
    if (artists.isEmpty) return '';
    // 常见的分隔符：/、\、、、&、,
    final separators = RegExp(r'[/\\、&,，]');
    final parts = artists.split(separators);
    return parts.first.trim();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge([
        PlaylistQueueService(),
        PlayerService(),
      ]),
      builder: (context, _) {
        final queueService = PlaylistQueueService();
        final queue = queueService.queue;
        final currentTrack = PlayerService().currentTrack;

        if (queue.isEmpty) {
          return const Center(
            child: Text(
              '队列中暂无歌曲',
              style: TextStyle(color: Colors.white54, fontSize: 18),
            ),
          );
        }

        // 计算总项目数：队列 + 分隔标题(如果有推荐) + 推荐歌曲
        final hasArtistSection = _artistSongs.isNotEmpty || _artistSongsLoading;
        final totalItemCount = queue.length +
            (hasArtistSection ? 1 : 0) + // 分隔标题
            _artistSongs.length;

        return Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 600),
            child: ListView.builder(
              controller: _scrollController,
              padding: const EdgeInsets.symmetric(vertical: 60),
              itemCount: totalItemCount,
              itemBuilder: (context, index) {
                // 播放队列部分
                if (index < queue.length) {
                  final track = queue[index];
                  final isCurrent = currentTrack != null &&
                      track.id.toString() == currentTrack.id.toString() &&
                      track.source == currentTrack.source;
                  return _buildQueueItem(track, isCurrent, index, height: 76);
                }

                // 分隔标题
                if (index == queue.length && hasArtistSection) {
                  return _buildSectionHeader();
                }

                // 推荐歌曲部分
                final artistSongIndex = index - queue.length - 1;
                if (artistSongIndex >= 0 && artistSongIndex < _artistSongs.length) {
                  return _buildArtistSongItem(_artistSongs[artistSongIndex], artistSongIndex);
                }

                return const SizedBox.shrink();
              },
            ),
          ),
        );
      },
    );
  }

  /// 构建分隔标题
  Widget _buildSectionHeader() {
    final currentTrack = PlayerService().currentTrack;
    final artistName = currentTrack != null
        ? _extractFirstArtist(currentTrack.artists)
        : '';

    return Container(
      margin: const EdgeInsets.only(top: 24, bottom: 8, left: 8, right: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 分隔线
          Container(
            height: 1,
            margin: const EdgeInsets.only(bottom: 16),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  Colors.white.withValues(alpha: 0.0),
                  Colors.white.withValues(alpha: 0.2),
                  Colors.white.withValues(alpha: 0.0),
                ],
              ),
            ),
          ),
          // 标题
          Row(
            children: [
              const Icon(
                Icons.person_outline_rounded,
                color: Colors.white70,
                size: 18,
              ),
              const SizedBox(width: 8),
              Text(
                artistName.isNotEmpty ? '$artistName 的更多作品' : '更多推荐',
                style: const TextStyle(
                  color: Colors.white70,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  fontFamily: 'Microsoft YaHei',
                ),
              ),
              if (_artistSongsLoading) ...[
                const SizedBox(width: 12),
                const SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    valueColor: AlwaysStoppedAnimation<Color>(Colors.white54),
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildQueueItem(Track track, bool isCurrent, int index, {double height = 76}) {
    return SizedBox(
      key: ValueKey('${track.source.name}_${track.id}'),
      height: height,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
        decoration: BoxDecoration(
          color: isCurrent ? Colors.white.withValues(alpha: 0.12) : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: () {
              final coverProvider = PlaylistQueueService().getCoverProvider(track);
              PlayerService().playTrack(track, coverProvider: coverProvider);
            },
            hoverColor: Colors.white.withValues(alpha: 0.06),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Row(
                children: [
                  // 封面
                  ClipRRect(
                    borderRadius: BorderRadius.circular(6),
                    child: CachedNetworkImage(
                      imageUrl: track.picUrl,
                      httpHeaders: getImageHeaders(track.picUrl),
                      width: 44,
                      height: 44,
                      fit: BoxFit.cover,
                      memCacheWidth: 128,
                      memCacheHeight: 128,
                      fadeOutDuration: Duration.zero,
                      fadeInDuration: const Duration(milliseconds: 200),
                    ),
                  ),
                  const SizedBox(width: 16),
                  // 歌曲信息
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          track.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: isCurrent ? Colors.white : Colors.white.withValues(alpha: 0.9),
                            fontSize: 16,
                            fontWeight: isCurrent ? FontWeight.bold : FontWeight.w500,
                            fontFamily: 'Microsoft YaHei',
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          track.artists,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: isCurrent ? Colors.white70 : Colors.white54,
                            fontSize: 13,
                            fontFamily: 'Microsoft YaHei',
                          ),
                        ),
                      ],
                    ),
                  ),
                  // 正在播放指示器
                  if (isCurrent)
                    const Padding(
                      padding: EdgeInsets.only(left: 8),
                      child: Icon(
                        Icons.equalizer_rounded,
                        color: Colors.white,
                        size: 20,
                      ),
                    ),
                  // 更多菜单
                  TrackMoreButton(
                    track: track,
                    onPlay: () {
                      final coverProvider = PlaylistQueueService().getCoverProvider(track);
                      PlayerService().playTrack(track, coverProvider: coverProvider);
                    },
                    size: 30,
                  ),
                  // 移除按钮
                  IconButton(
                    icon: Icon(
                      Icons.close_rounded,
                      color: Colors.white.withValues(alpha: 0.4),
                      size: 16,
                    ),
                    constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                    padding: EdgeInsets.zero,
                    onPressed: () {
                      PlaybackService().removeAt(index);
                    },
                    tooltip: '移除',
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// 构建推荐歌曲项
  Widget _buildArtistSongItem(Track track, int index) {
    return SizedBox(
      height: 68, // 推荐歌曲稍微小一点
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 3, horizontal: 8),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: Colors.white.withValues(alpha: 0.08),
            width: 1,
          ),
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(10),
            onTap: () {
              // 播放推荐歌曲
              PlayerService().playTrack(track);
            },
            hoverColor: Colors.white.withValues(alpha: 0.08),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              child: Row(
                children: [
                  // 封面
                  ClipRRect(
                    borderRadius: BorderRadius.circular(5),
                    child: CachedNetworkImage(
                      imageUrl: track.picUrl,
                      httpHeaders: getImageHeaders(track.picUrl),
                      width: 40,
                      height: 40,
                      fit: BoxFit.cover,
                      memCacheWidth: 128,
                      memCacheHeight: 128,
                      fadeOutDuration: Duration.zero,
                      fadeInDuration: const Duration(milliseconds: 200),
                      placeholder: (context, url) => Container(
                        width: 40,
                        height: 40,
                        color: Colors.white.withValues(alpha: 0.1),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  // 歌曲信息
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          track.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.85),
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                            fontFamily: 'Microsoft YaHei',
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          track.album.isNotEmpty ? track.album : track.artists,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.45),
                            fontSize: 12,
                            fontFamily: 'Microsoft YaHei',
                          ),
                        ),
                      ],
                    ),
                  ),
                  // 更多菜单
                  TrackMoreButton(
                    track: track,
                    onPlay: () {
                      PlayerService().playTrack(track);
                    },
                    size: 28,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
