import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../services/player_service.dart';
import '../../services/playlist_queue_service.dart';
import '../../services/play_history_service.dart';
import '../../models/track.dart';

/// 播放器播放列表面板
/// 显示播放队列或播放历史，支持搜索功能
class PlayerPlaylistPanel extends StatefulWidget {
  final bool isVisible;
  final Animation<Offset>? slideAnimation;
  final VoidCallback onClose;

  const PlayerPlaylistPanel({
    super.key,
    required this.isVisible,
    this.slideAnimation,
    required this.onClose,
  });

  @override
  State<PlayerPlaylistPanel> createState() => _PlayerPlaylistPanelState();
}

class _PlayerPlaylistPanelState extends State<PlayerPlaylistPanel> {
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';
  bool _isSearchExpanded = false;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.isVisible) return const SizedBox.shrink();
    
    if (widget.slideAnimation != null) {
      return SlideTransition(
        position: widget.slideAnimation!,
        child: Align(
          alignment: Alignment.centerRight,
          child: _buildPanel(context),
        ),
      );
    }
    
    return Align(
      alignment: Alignment.centerRight,
      child: _buildPanel(context),
    );
  }

  Widget _buildPanel(BuildContext context) {
    final queueService = PlaylistQueueService();
    final history = PlayHistoryService().history;
    final currentTrack = PlayerService().currentTrack;
    
    // 优先使用播放队列，如果没有队列则使用播放历史
    final bool hasQueue = queueService.hasQueue;
    final List<dynamic> fullList = hasQueue 
        ? queueService.queue 
        : history.map((h) => h.toTrack()).toList();
    final String listTitle = hasQueue 
        ? '播放队列 (${queueService.source.name})' 
        : '播放历史';

    // 根据搜索关键词过滤列表
    final List<dynamic> displayList = _searchQuery.isEmpty
        ? fullList
        : fullList.where((item) {
            final track = item is Track ? item : (item as PlayHistoryItem).toTrack();
            final query = _searchQuery.toLowerCase();
            return track.name.toLowerCase().contains(query) ||
                   track.artists.toLowerCase().contains(query);
          }).toList();

    return ClipRRect(
      borderRadius: const BorderRadius.only(
        topLeft: Radius.circular(16),
        bottomLeft: Radius.circular(16),
      ),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 40, sigmaY: 40),
        child: Container(
          width: 400,
          height: double.infinity,
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.1),
            borderRadius: const BorderRadius.only(
              topLeft: Radius.circular(16),
              bottomLeft: Radius.circular(16),
            ),
            border: Border.all(
              color: Colors.white.withOpacity(0.15),
              width: 1,
            ),
          ),
          child: Column(
            children: [
              // 标题栏
              Container(
                padding: const EdgeInsets.fromLTRB(20, 20, 12, 12),
                child: Row(
                  children: [
                    const Icon(
                      Icons.queue_music,
                      color: Colors.white,
                      size: 24,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        listTitle,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          fontFamily: 'Microsoft YaHei',
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    Text(
                      _searchQuery.isEmpty 
                          ? '${fullList.length} 首' 
                          : '${displayList.length}/${fullList.length}',
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.6),
                        fontSize: 14,
                        fontFamily: 'Microsoft YaHei',
                      ),
                    ),
                    const SizedBox(width: 4),
                    // 搜索按钮
                    IconButton(
                      icon: Icon(
                        _isSearchExpanded ? Icons.search_off : Icons.search,
                        color: Colors.white.withOpacity(0.8),
                      ),
                      onPressed: () {
                        setState(() {
                          _isSearchExpanded = !_isSearchExpanded;
                          if (!_isSearchExpanded) {
                            _searchController.clear();
                            _searchQuery = '';
                          }
                        });
                      },
                      tooltip: _isSearchExpanded ? '关闭搜索' : '搜索',
                    ),
                    IconButton(
                      icon: const Icon(Icons.close_rounded, color: Colors.white),
                      onPressed: widget.onClose,
                      tooltip: '关闭',
                    ),
                  ],
                ),
              ),

              // 搜索框（可展开）
              AnimatedSize(
                duration: const Duration(milliseconds: 200),
                curve: Curves.easeInOut,
                child: _isSearchExpanded
                    ? Padding(
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                        child: _buildSearchField(),
                      )
                    : const SizedBox.shrink(),
              ),

              const Divider(color: Colors.white24, height: 1),

              // 播放列表
              Expanded(
                child: displayList.isEmpty
                    ? _buildEmptyState()
                    : ListView.builder(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        itemCount: displayList.length,
                        // 固定高度优化：避免每次都计算子项高度
                        itemExtent: 74,
                        // 增加缓存范围，减少重建频率
                        cacheExtent: 500,
                        // 保持子项状态，减少不必要的重建
                        addAutomaticKeepAlives: true,
                        addRepaintBoundaries: true,
                        itemBuilder: (context, index) {
                          final item = displayList[index];
                          // 转换为 Track
                          final track = item is Track ? item : (item as PlayHistoryItem).toTrack();
                          // 获取在原始列表中的索引（用于显示序号）
                          final originalIndex = fullList.indexOf(item);
                          final isCurrentTrack = currentTrack != null &&
                              track.id.toString() == currentTrack.id.toString() &&
                              track.source == currentTrack.source;

                          return _buildPlaylistItem(context, track, originalIndex, isCurrentTrack);
                        },
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 构建搜索框
  Widget _buildSearchField() {
    return Container(
      height: 40,
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.1),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: Colors.white.withOpacity(0.2),
          width: 1,
        ),
      ),
      child: TextField(
        controller: _searchController,
        onChanged: (value) {
          setState(() {
            _searchQuery = value;
          });
        },
        style: const TextStyle(
          color: Colors.white,
          fontSize: 14,
          fontFamily: 'Microsoft YaHei',
        ),
        decoration: InputDecoration(
          hintText: '搜索歌曲或歌手...',
          hintStyle: TextStyle(
            color: Colors.white.withOpacity(0.4),
            fontSize: 14,
            fontFamily: 'Microsoft YaHei',
          ),
          prefixIcon: Icon(
            Icons.search,
            color: Colors.white.withOpacity(0.5),
            size: 20,
          ),
          suffixIcon: _searchQuery.isNotEmpty
              ? IconButton(
                  icon: Icon(
                    Icons.clear,
                    color: Colors.white.withOpacity(0.5),
                    size: 18,
                  ),
                  onPressed: () {
                    _searchController.clear();
                    setState(() {
                      _searchQuery = '';
                    });
                  },
                )
              : null,
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        ),
        cursorColor: Colors.white,
      ),
    );
  }

  /// 构建空状态
  Widget _buildEmptyState() {
    final isSearching = _searchQuery.isNotEmpty;
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.hasBoundedHeight && constraints.maxHeight < 180;
        final minHeight = constraints.hasBoundedHeight ? constraints.maxHeight : 0.0;
        return SingleChildScrollView(
          physics: const ClampingScrollPhysics(),
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: minHeight),
            child: Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      isSearching ? Icons.search_off : Icons.music_off,
                      size: compact ? 52 : 64,
                      color: Colors.white.withOpacity(0.3),
                    ),
                    SizedBox(height: compact ? 10 : 16),
                    Text(
                      isSearching ? '未找到匹配的歌曲' : '播放列表为空',
                      textAlign: TextAlign.center,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.6),
                        fontSize: 16,
                        fontFamily: 'Microsoft YaHei',
                      ),
                    ),
                    if (isSearching) ...[
                      const SizedBox(height: 8),
                      TextButton(
                        onPressed: () {
                          _searchController.clear();
                          setState(() {
                            _searchQuery = '';
                          });
                        },
                        child: Text(
                          '清除搜索',
                          style: TextStyle(
                            color: Colors.white.withOpacity(0.8),
                            fontSize: 14,
                            fontFamily: 'Microsoft YaHei',
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  /// 构建播放列表项
  Widget _buildPlaylistItem(BuildContext context, Track track, int index, bool isCurrentTrack) {
    // 使用 RepaintBoundary 隔离每个列表项的重绘
    return RepaintBoundary(
      child: GestureDetector(
        onTap: () {
          final coverProvider = PlaylistQueueService().getCoverProvider(track);
          PlayerService().playTrack(track, coverProvider: coverProvider);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('正在播放: ${track.name}'),
              duration: const Duration(seconds: 1),
            ),
          );
        },
        child: Container(
          color: isCurrentTrack 
              ? Colors.white.withOpacity(0.1) 
              : Colors.transparent,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            children: [
              // 序号或正在播放图标
              SizedBox(
                width: 40,
                child: isCurrentTrack
                    ? const Icon(
                        Icons.play_arrow_rounded,
                        color: Colors.white,
                        size: 20,
                      )
                    : Text(
                        '${index + 1}',
                        style: TextStyle(
                          color: Colors.white.withOpacity(0.5),
                          fontSize: 14,
                          fontFamily: 'Microsoft YaHei',
                        ),
                        textAlign: TextAlign.center,
                      ),
              ),

              // 封面 - 简化配置，减少回调开销
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: CachedNetworkImage(
                  imageUrl: track.picUrl,
                  width: 50,
                  height: 50,
                  fit: BoxFit.cover,
                  // 使用简单的占位符，避免复杂的 builder 回调
                  placeholder: (context, url) => Container(
                    width: 50,
                    height: 50,
                    color: Colors.white12,
                  ),
                  errorWidget: (context, url, error) => Container(
                    width: 50,
                    height: 50,
                    color: Colors.white12,
                    child: const Icon(
                      Icons.music_note,
                      color: Colors.white38,
                      size: 24,
                    ),
                  ),
                  // 启用内存缓存，减少重复加载
                  memCacheWidth: 100,
                  memCacheHeight: 100,
                  fadeInDuration: const Duration(milliseconds: 150),
                  fadeOutDuration: const Duration(milliseconds: 150),
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
                        color: isCurrentTrack ? Colors.white : Colors.white.withOpacity(0.9),
                        fontSize: 15,
                        fontWeight: isCurrentTrack ? FontWeight.bold : FontWeight.normal,
                        fontFamily: 'Microsoft YaHei',
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      track.artists,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.5),
                        fontSize: 13,
                        fontFamily: 'Microsoft YaHei',
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
