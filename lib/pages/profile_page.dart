import '../utils/app_feedback.dart';
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../features/auth/auth_feature.dart';
import '../services/listening_stats_service.dart';
import '../services/player_service.dart';
import '../widgets/track_action_menu.dart';

/// 个人中心页面
class ProfilePage extends StatefulWidget {
  const ProfilePage({super.key});

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  final AuthFacade _authFacade = AuthFacade();
  bool _isLoading = true;
  ListeningStatsData? _statsData;
  String? _errorMessage;
  final List<PlayCountItem> _records = [];
  int _recordsPage = 0;
  bool _hasMoreRecords = true;
  bool _loadingRecords = false;
  String? _recordsError;
  bool _recordsNeedRefresh = false;
  String? _session;
  int _generation = 0;

  @override
  void initState() {
    super.initState();
    _session = ListeningStatsService().contextIdentity;
    ListeningStatsService().addListener(_onAuthChanged);
    _loadStats();
  }

  @override
  void dispose() {
    ListeningStatsService().removeListener(_onAuthChanged);
    super.dispose();
  }

  void _onAuthChanged() {
    if (!mounted || _session == ListeningStatsService().contextIdentity) return;
    _session = ListeningStatsService().contextIdentity;
    _generation++;
    _statsData = null;
    _records.clear();
    _recordsPage = 0;
    _hasMoreRecords = true;
    _loadStats();
  }

  /// 加载统计数据
  Future<void> _loadStats({bool forceRefresh = false}) async {
    final generation = ++_generation;
    final session = ListeningStatsService().contextIdentity;
    if (!_authFacade.isLoggedIn) {
      setState(() {
        _isLoading = false;
        _errorMessage = '请先登录';
      });
      return;
    }

    setState(() {
      _statsData = ListeningStatsService().statsData;
      _isLoading = _statsData == null;
      _errorMessage = null;
      _loadingRecords = true;
      _recordsError = null;
    });

    try {
      final service = ListeningStatsService();
      final results = await Future.wait<Object?>([
        service.fetchStats(forceRefresh: forceRefresh),
        service.fetchRecords().then<PlayCountPage?>((page) => page,
          onError: (Object _) => null,
        ),
      ]);
      if (!mounted || generation != _generation ||
          session != ListeningStatsService().contextIdentity) {
        return;
      }
      final stats = results[0] as ListeningStatsData?;
      final records = results[1] as PlayCountPage?;
      setState(() {
        _statsData = stats ?? service.statsData;
        _errorMessage = service.lastError;
        if (records != null) {
          _records..clear()..addAll(records.records);
          _recordsPage = records.page;
          _hasMoreRecords = records.hasMore;
          _recordsNeedRefresh = false;
        } else {
          _recordsError = '播放记录加载失败';
          _recordsNeedRefresh = true;
        }
        _loadingRecords = false;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted || generation != _generation ||
          session != ListeningStatsService().contextIdentity) {
        return;
      }
      setState(() {
        _errorMessage = '加载统计数据失败，请重试';
        _loadingRecords = false;
        _isLoading = false;
      });
    }
  }

  Future<void> _loadMoreRecords() async {
    if (_loadingRecords || !_hasMoreRecords) return;
    final generation = _generation;
    final session = ListeningStatsService().contextIdentity;
    setState(() { _loadingRecords = true; _recordsError = null; });
    try {
      final page = await ListeningStatsService().fetchRecords(page: _recordsPage + 1,
      );
      if (!mounted || generation != _generation || session != ListeningStatsService().contextIdentity) {
        return;
      }
      setState(() {
        final keys = _records.map((r) => (r.source, r.trackId)).toSet();
        final added = page.records.where((r) => keys.add((r.source, r.trackId))).toList();
        _records.addAll(added);
        _recordsPage = page.page;
        _hasMoreRecords = page.hasMore && added.isNotEmpty;
        _loadingRecords = false;
      });
    } catch (_) {
      if (!mounted || generation != _generation || session != ListeningStatsService().contextIdentity) {
        return;
      }
      setState(() { _loadingRecords = false; _recordsError = '播放记录加载失败，请重试'; });
    }
  }

  /// 播放歌曲
  Future<void> _playTrack(PlayCountItem item) async {
    try {
      final track = item.toTrack();
      await PlayerService().playTrack(track);
    } catch (e) {
      if (mounted) {
        AppFeedback.of(context).showSnackBar(
          SnackBar(
            content: Text('播放失败: $e'),
            backgroundColor: Colors.red),
          kind: FeedbackKind.error,
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final user = _authFacade.currentUser;

    return Scaffold(
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _errorMessage != null && _statsData == null
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.error_outline,
                        size: 64,
                        color: colorScheme.error),
                      const SizedBox(height: 16),
                      Text(
                        _errorMessage!,
                        style: TextStyle(color: colorScheme.error),
                      ),
                      const SizedBox(height: 16),
                      FilledButton.icon(
                        onPressed: () => _loadStats(forceRefresh: true),
                        icon: const Icon(Icons.refresh),
                        label: const Text('重试'),
                      ),
                    ],
                  ),
                )
              : RefreshIndicator(
                  onRefresh: () => _loadStats(forceRefresh: true),
                  child: ListView(
                    padding: const EdgeInsets.all(16),
                    children: [
                      // 用户信息卡片
                      _buildUserCard(user, colorScheme),

                      const SizedBox(height: 16),

                      // 统计卡片
                      _buildStatsCard(colorScheme),
                      if (_errorMessage != null)
                        TextButton(onPressed: () => _loadStats(forceRefresh: true),
                          child: const Text('统计更新失败，点击重试'),
                    ),

                      const SizedBox(height: 16),

                      // 播放排行榜
                      _buildPlayCountsSection(colorScheme),
                    ],
                  ),
                ),
    );
  }

  /// 构建用户信息卡片
  Widget _buildUserCard(User? user, ColorScheme colorScheme) {
    if (user == null) return const SizedBox.shrink();

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            // 头像
            CircleAvatar(
              radius: 32,
              backgroundImage: user.avatarUrl != null
                  ? CachedNetworkImageProvider(user.avatarUrl!)
                  : null,
              child: user.avatarUrl == null
                  ? Text(
                      user.username[0].toUpperCase(),
                      style: const TextStyle(fontSize: 24),
                    )
                  : null,
            ),

            const SizedBox(width: 16),

            // 用户信息
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    user.username,
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    user.email,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: colorScheme.onSurface.withValues(alpha: 0.6),
                        ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 构建统计卡片
  Widget _buildStatsCard(ColorScheme colorScheme) {
    if (_statsData == null) return const SizedBox.shrink();

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '听歌统计',
              style: Theme.of(context).textTheme.titleMedium),

            const SizedBox(height: 16),

            // 统计数据行
            Row(
              children: [
                Expanded(
                  child: _buildStatItem(
                    icon: Icons.access_time,
                    label: '累计时长',
                    value: ListeningStatsService.formatDuration(
                      _statsData!.totalListeningTime,
                    ),
                    colorScheme: colorScheme,
                  ),
                ),

                const SizedBox(width: 16),

                Expanded(
                  child: _buildStatItem(
                    icon: Icons.play_circle_outline,
                    label: '播放次数',
                    value: '${_statsData!.totalPlayCount} 次',
                    colorScheme: colorScheme,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  /// 构建统计项
  Widget _buildStatItem({
    required IconData icon,
    required String label,
    required String value,
    required ColorScheme colorScheme,
  }) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 20, color: colorScheme.primary),
          const SizedBox(height: 8),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              color: colorScheme.onSurface.withValues(alpha: 0.6),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold),
          ),
        ],
      ),
    );
  }

  /// 构建播放排行榜
  Widget _buildPlayCountsSection(ColorScheme colorScheme) {
    if (_records.isEmpty && _recordsError == null && !_loadingRecords) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Center(
            child: Column(
              children: [
                Icon(
                  Icons.music_note,
                  size: 64,
                  color: colorScheme.onSurface.withValues(alpha: 0.3),
                ),
                const SizedBox(height: 16),
                Text(
                  '暂无播放记录',
                  style: TextStyle(
                    color: colorScheme.onSurface.withValues(alpha: 0.6),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Text(
            '播放排行榜',
            style: Theme.of(context).textTheme.titleMedium),
        ),

        const SizedBox(height: 8),

        Card(
          child: ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: _records.length,
            separatorBuilder: (context, index) => const Divider(height: 1),
            itemBuilder: (context, index) {
              final item = _records[index];
              return _buildPlayCountItem(item, index + 1, colorScheme);
            },
          ),
        ),
        if (_recordsError != null) Text(_recordsError!),
        if (_loadingRecords)
          const Padding(padding: EdgeInsets.all(12), child: CircularProgressIndicator(),
          )
        else if (_hasMoreRecords || _recordsError != null)
          TextButton(onPressed: _recordsNeedRefresh
              ? () => _loadStats(forceRefresh: true) : _loadMoreRecords,
            child: Text(_recordsError == null ? '加载更多' : '重试'),
          ),
      ],
    );
  }

  /// 构建播放次数列表项
  Widget _buildPlayCountItem(
    PlayCountItem item,
    int rank,
    ColorScheme colorScheme,
  ) {
    // 前三名使用特殊颜色
    Color? rankColor;
    if (rank == 1) {
      rankColor = Colors.amber;
    } else if (rank == 2) {
      rankColor = Colors.grey.shade400;
    } else if (rank == 3) {
      rankColor = Colors.brown.shade300;
    }

    return ListTile(
      leading: Stack(
        children: [
          // 封面
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: CachedNetworkImage(
              imageUrl: item.picUrl,
              width: 48,
              height: 48,
              fit: BoxFit.cover,
              memCacheWidth: 128,
              memCacheHeight: 128,
              placeholder: (context, url) => Container(
                width: 48,
                height: 48,
                color: colorScheme.surfaceContainerHighest,
                child: const Icon(Icons.music_note, size: 24),
              ),
              errorWidget: (context, url, error) => Container(
                width: 48,
                height: 48,
                color: colorScheme.surfaceContainerHighest,
                child: const Icon(Icons.music_note, size: 24),
              ),
            ),
          ),

          // 排名徽章
          Positioned(
            left: 0,
            top: 0,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: rankColor ?? colorScheme.primaryContainer,
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(4),
                  bottomRight: Radius.circular(4),
                ),
              ),
              child: Text(
                '$rank',
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                  color: rankColor != null ? Colors.white : colorScheme.onPrimaryContainer,
                ),
              ),
            ),
          ),
        ],
      ),
      title: Text(
        item.trackName,
        maxLines: 1,
        overflow: TextOverflow.ellipsis),
      subtitle: Text(
        item.artists.isNotEmpty ? item.artists : '未知艺术家',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          color: colorScheme.onSurface.withValues(alpha: 0.6)),
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                '${item.playCount} 次',
                style: const TextStyle(
                  fontWeight: FontWeight.bold),
              ),
              Text(
                item.toTrack().getSourceName(),
                style: TextStyle(
                  fontSize: 10,
                  color: colorScheme.onSurface.withValues(alpha: 0.5),
                ),
              ),
            ],
          ),
          TrackMoreButton(
            track: item.toTrack(),
            onPlay: () => _playTrack(item),
            size: 32,
          ),
        ],
      ),
      onTap: () => _playTrack(item),
    );
  }
}
