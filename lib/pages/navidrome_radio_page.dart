import 'package:flutter/material.dart';
import '../models/navidrome_models.dart';
import '../services/navidrome_session_service.dart';
import '../services/navidrome_api.dart';
import '../services/player_service.dart';
import '../models/track.dart';
import '../widgets/navidrome_ui.dart';

/// 网络电台页面
class NavidromeRadioPage extends StatefulWidget {
  const NavidromeRadioPage({super.key});

  @override
  State<NavidromeRadioPage> createState() => _NavidromeRadioPageState();
}

class _NavidromeRadioPageState extends State<NavidromeRadioPage> {
  List<NavidromeRadioStation> _stations = [];
  bool _loading = true;
  String? _error;
  String? _playingStationId;

  NavidromeApi? get _api => NavidromeSessionService().api;

  @override
  void initState() {
    super.initState();
    _loadStations();
  }

  Future<void> _loadStations() async {
    final api = _api;
    if (api == null) {
      setState(() {
        _loading = false;
        _error = '未配置服务器';
      });
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final stations = await api.getInternetRadioStations();
      if (!mounted) return;
      setState(() {
        _stations = stations;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = '加载失败：$e';
      });
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
        });
      }
    }
  }

  void _playStation(NavidromeRadioStation station) {
    setState(() {
      _playingStationId = station.id;
    });

    // 创建一个 Track 表示电台
    final track = Track(
      id: 'radio_${station.id}',
      name: station.name,
      artists: '网络电台',
      album: '',
      picUrl: '', // 电台没有封面
      source: MusicSource.navidrome,
      // 直接使用 streamUrl
    );

    // 使用 PlayerService 播放电台流
    PlayerService().playRadioStream(station.streamUrl, track);
  }

  void _stopStation() {
    setState(() {
      _playingStationId = null;
    });
    PlayerService().stop();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_error != null) {
      return NavidromeErrorState(
        message: _error!,
        onRetry: _loadStations,
      );
    }

    if (_stations.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.radio, size: 64, color: colorScheme.outline),
            const SizedBox(height: 16),
            Text(
              '暂无电台',
              style: theme.textTheme.titleMedium?.copyWith(
                color: colorScheme.outline,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              '请在 Navidrome 中添加网络电台',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: colorScheme.outline,
              ),
            ),
          ],
        ),
      );
    }

    return SafeArea(
      child: LayoutBuilder(
        builder: (context, constraints) {
          final width = constraints.maxWidth;
          final padding = NavidromeLayout.pagePadding(width);
          final bottomPadding = NavidromeLayout.bottomPadding(context);

          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: EdgeInsets.fromLTRB(
                  padding.left,
                  12,
                  padding.right,
                  4,
                ),
                child: Text(
                  '电台',
                  style: theme.textTheme.headlineMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              Expanded(
                child: RefreshIndicator(
                  onRefresh: _loadStations,
                  child: ListView.separated(
                    padding: EdgeInsets.fromLTRB(
                      padding.left,
                      8,
                      padding.right,
                      bottomPadding,
                    ),
                    itemCount: _stations.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 10),
                    itemBuilder: (context, index) {
                      final station = _stations[index];
                      final isPlaying = _playingStationId == station.id;

                      return _RadioStationTile(
                        station: station,
                        isPlaying: isPlaying,
                        onPlay: () => _playStation(station),
                        onStop: _stopStation,
                      );
                    },
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _RadioStationTile extends StatelessWidget {
  final NavidromeRadioStation station;
  final bool isPlaying;
  final VoidCallback onPlay;
  final VoidCallback onStop;

  const _RadioStationTile({
    required this.station,
    required this.isPlaying,
    required this.onPlay,
    required this.onStop,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return NavidromeCard(
      onTap: isPlaying ? onStop : onPlay,
      padding: const EdgeInsets.all(12),
      child: Row(
        children: [
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              color: isPlaying
                  ? colorScheme.primaryContainer
                  : colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(
              isPlaying ? Icons.radio : Icons.radio_outlined,
              color: isPlaying
                  ? colorScheme.onPrimaryContainer
                  : colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  station.name,
                  style: theme.textTheme.bodyLarge?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: isPlaying ? colorScheme.primary : null,
                  ),
                ),
                if (station.homePageUrl != null) ...[
                  const SizedBox(height: 4),
                  Text(
                    station.homePageUrl!,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: colorScheme.outline,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ],
            ),
          ),
          isPlaying
              ? IconButton.filled(
                  onPressed: onStop,
                  icon: const Icon(Icons.stop),
                )
              : IconButton.filledTonal(
                  onPressed: onPlay,
                  icon: const Icon(Icons.play_arrow),
                ),
        ],
      ),
    );
  }
}
