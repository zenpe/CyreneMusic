import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'dart:convert';
import 'dart:math' as math;
import 'package:cached_network_image/cached_network_image.dart';
import 'package:fluent_ui/fluent_ui.dart' as fluent;
import '../services/netease_recommend_service.dart';
import '../models/track.dart';
import '../services/player_service.dart';
import '../services/playlist_queue_service.dart';
import 'home_page/daily_recommend_detail_page.dart';
import 'discover_playlist_detail_page.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/auth_service.dart';
import '../utils/theme_manager.dart';
import '../services/weather_service.dart';
import '../widgets/skeleton_loader.dart';
import '../services/auth_overlay_service.dart';
import '../pages/settings_page/user_card.dart';
import '../widgets/login_prompt.dart';
import 'auth/auth_page.dart';

/// 首页 - 为你推荐 Tab 内容 (优化版)
class HomeForYouTab extends StatefulWidget {
  const HomeForYouTab({super.key, this.onOpenPlaylistDetail, this.onOpenDailyDetail});

  final void Function(int playlistId)? onOpenPlaylistDetail;
  final void Function(List<Map<String, dynamic>> tracks)? onOpenDailyDetail;

  @override
  State<HomeForYouTab> createState() => _HomeForYouTabState();
}

class _HomeForYouTabState extends State<HomeForYouTab> {
  late Future<_ForYouData> _future;
  
  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<_ForYouData> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final cacheBase = _cacheBaseKey();
    final dataKey = '${cacheBase}_data';
    final expireKey = '${cacheBase}_expire';
    final now = DateTime.now();
    final expireMs = prefs.getInt(expireKey);
    if (expireMs != null && now.millisecondsSinceEpoch < expireMs) {
      final jsonString = prefs.getString(dataKey);
      if (jsonString != null && jsonString.isNotEmpty) {
        try {
          final data = _ForYouData.fromJsonString(jsonString);
          return data;
        } catch (_) {}
      }
    }

    final svc = NeteaseRecommendService();
    final combined = await svc.fetchForYouCombined(personalizedLimit: 12, newsongLimit: 10);
    final result = _ForYouData(
      dailySongs: combined['dailySongs'] ?? const [],
      fm: combined['fm'] ?? const [],
      dailyPlaylists: combined['dailyPlaylists'] ?? const [],
      personalizedPlaylists: combined['personalizedPlaylists'] ?? const [],
      radarPlaylists: combined['radarPlaylists'] ?? const [],
      personalizedNewsongs: combined['personalizedNewsongs'] ?? const [],
    );

    try {
      final endOfDay = DateTime(now.year, now.month, now.day, 23, 59, 59, 999);
      await prefs.setString(dataKey, result.toJsonString());
      await prefs.setInt(expireKey, endOfDay.millisecondsSinceEpoch);
    } catch (_) {}

    return result;
  }

  String _cacheBaseKey() {
    final userId = AuthService().currentUser?.id?.toString() ?? 'guest';
    return 'home_for_you_$userId';
  }

  @override
  Widget build(BuildContext context) {
    final themeManager = ThemeManager();
    final isCupertino = (Platform.isIOS || Platform.isAndroid) && themeManager.isCupertinoFramework;
    final isMobile = Platform.isIOS || Platform.isAndroid;
    
    // 未登录状态下显示登录提示
    if (!AuthService().isLoggedIn) {
      return LoginPrompt(
        onLoginPressed: () => showAuthDialog(context).then((_) {
          if (mounted && AuthService().isLoggedIn) {
            setState(() {
              _future = _load();
            });
          }
        }),
      );
    }
    
    return FutureBuilder<_ForYouData>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          // 移动端使用移动端专用骨架屏
          if (isMobile) {
            return const MobileForYouSkeleton();
          }
          // Fluent UI 桌面端使用桌面端骨架屏
          if (themeManager.isFluentFramework) {
            return const ForYouSkeleton();
          }
          // 其他情况使用桌面端骨架屏
          return const ForYouSkeleton();
        }
        if (snapshot.hasError || !snapshot.hasData) {
          return Center(child: Padding(padding: const EdgeInsets.all(24.0), child: Text('加载失败：${snapshot.error ?? ''}')));
        }
        final data = snapshot.data!;
        
        // 移动端使用原始布局
        if (isMobile) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const _GreetingHeader(),
              _DailyRecommendCard(
                tracks: data.dailySongs,
                onOpenDetail: () => widget.onOpenDailyDetail?.call(data.dailySongs),
              ),
              const SizedBox(height: 24),
              _SectionTitle(title: '私人FM'),
              _PersonalFm(list: data.fm),
              const SizedBox(height: 24),
              _SectionTitle(title: '每日推荐歌单'),
              _PlaylistGrid(
                list: data.dailyPlaylists,
                onTap: (id) => widget.onOpenPlaylistDetail?.call(id),
              ),
              const SizedBox(height: 24),
              _SectionTitle(title: '专属歌单'),
              _PlaylistGrid(
                list: data.personalizedPlaylists,
                onTap: (id) => widget.onOpenPlaylistDetail?.call(id),
              ),
              const SizedBox(height: 24),
              _SectionTitle(title: '雷达歌单'),
              _PlaylistGrid(
                list: data.radarPlaylists,
                onTap: (id) => widget.onOpenPlaylistDetail?.call(id),
              ),
              const SizedBox(height: 24),
              _SectionTitle(title: '个性化新歌'),
              _NewsongList(list: data.personalizedNewsongs),
              const SizedBox(height: 16),
            ],
          );
        }
        
        // 桌面端使用新布局
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const _GreetingHeader(),
            const SizedBox(height: 16),
            // Hero 双卡区域：每日推荐 + 私人FM
            _HeroSection(
              dailySongs: data.dailySongs,
              fmList: data.fm,
              onOpenDailyDetail: () => widget.onOpenDailyDetail?.call(data.dailySongs),
            ),
            const SizedBox(height: 28),
            // 每日推荐歌单 - Bento 网格
            _SectionTitle(title: '每日推荐歌单'),
            _BentoPlaylistGrid(
              list: data.dailyPlaylists,
              onTap: (id) => widget.onOpenPlaylistDetail?.call(id),
            ),
            const SizedBox(height: 28),
            // 专属歌单 - 横向滚动大卡片
            _SectionTitle(title: '专属歌单'),
            _HorizontalPlaylistCarousel(
              list: data.personalizedPlaylists,
              onTap: (id) => widget.onOpenPlaylistDetail?.call(id),
            ),
            const SizedBox(height: 28),
            // 雷达歌单 - 混合尺寸网格
            _SectionTitle(title: '雷达歌单'),
            _MixedSizePlaylistGrid(
              list: data.radarPlaylists,
              onTap: (id) => widget.onOpenPlaylistDetail?.call(id),
            ),
            const SizedBox(height: 28),
            // 个性化新歌 - 卡片列表
            _SectionTitle(title: '发现新歌'),
            _NewsongCards(list: data.personalizedNewsongs),
            const SizedBox(height: 24),
          ],
        );
      },
    );
  }
}

class _ForYouData {
  final List<Map<String, dynamic>> dailySongs;
  final List<Map<String, dynamic>> fm;
  final List<Map<String, dynamic>> dailyPlaylists;
  final List<Map<String, dynamic>> personalizedPlaylists;
  final List<Map<String, dynamic>> radarPlaylists;
  final List<Map<String, dynamic>> personalizedNewsongs;
  _ForYouData({
    required this.dailySongs,
    required this.fm,
    required this.dailyPlaylists,
    required this.personalizedPlaylists,
    required this.radarPlaylists,
    required this.personalizedNewsongs,
  });

  Map<String, dynamic> toJson() => {
    'dailySongs': dailySongs,
    'fm': fm,
    'dailyPlaylists': dailyPlaylists,
    'personalizedPlaylists': personalizedPlaylists,
    'radarPlaylists': radarPlaylists,
    'personalizedNewsongs': personalizedNewsongs,
  };

  String toJsonString() => jsonEncode(toJson());

  static _ForYouData fromJson(Map<String, dynamic> json) {
    return _ForYouData(
      dailySongs: (json['dailySongs'] as List<dynamic>? ?? []).cast<Map<String, dynamic>>(),
      fm: (json['fm'] as List<dynamic>? ?? []).cast<Map<String, dynamic>>(),
      dailyPlaylists: (json['dailyPlaylists'] as List<dynamic>? ?? []).cast<Map<String, dynamic>>(),
      personalizedPlaylists: (json['personalizedPlaylists'] as List<dynamic>? ?? []).cast<Map<String, dynamic>>(),
      radarPlaylists: (json['radarPlaylists'] as List<dynamic>? ?? []).cast<Map<String, dynamic>>(),
      personalizedNewsongs: (json['personalizedNewsongs'] as List<dynamic>? ?? []).cast<Map<String, dynamic>>(),
    );
  }

  static _ForYouData fromJsonString(String s) {
    final map = jsonDecode(s) as Map<String, dynamic>;
    return fromJson(map);
  }
}

class _SectionTitle extends StatelessWidget {
  final String title;
  final VoidCallback? onViewAll;
  const _SectionTitle({required this.title, this.onViewAll});
  
  @override
  Widget build(BuildContext context) {
    final themeManager = ThemeManager();
    final isCupertino = (Platform.isIOS || Platform.isAndroid) && themeManager.isCupertinoFramework;
    final cs = Theme.of(context).colorScheme;
    
    return Padding(
      padding: const EdgeInsets.only(bottom: 12.0),
      child: Row(
        children: [
          Expanded(
            child: Text(
              title, 
              style: isCupertino
                  ? const TextStyle(fontSize: 22, fontWeight: FontWeight.bold, letterSpacing: -0.5)
                  : Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
            ),
          ),
          if (onViewAll != null)
            TextButton(
              onPressed: onViewAll,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('查看全部', style: TextStyle(color: cs.primary)),
                  const SizedBox(width: 4),
                  Icon(Icons.arrow_forward_ios, size: 12, color: cs.primary),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// 顶部问候语
class _GreetingHeader extends StatelessWidget {
  const _GreetingHeader();

  String _greetText(TimeOfDay now) {
    final minutes = now.hour * 60 + now.minute;
    if (minutes < 6 * 60) return '夜深了';
    if (minutes < 9 * 60) return '早上好';
    if (minutes < 12 * 60) return '上午好';
    if (minutes < 14 * 60) return '中午好';
    if (minutes < 18 * 60) return '下午好';
    return '晚上好';
  }

  String _subGreeting(TimeOfDay now) {
    final h = now.hour;
    if (h < 6) return '注意休息，音乐轻声一点';
    if (h < 9) return '新的一天，从此开始好心情';
    if (h < 12) return '愿音乐伴你高效工作';
    if (h < 14) return '午后小憩，来点轻松的旋律';
    if (h < 18) return '忙碌之余，听听喜欢的歌';
    return '夜色温柔，音乐更动听';
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final themeManager = ThemeManager();
    final isCupertino = (Platform.isIOS || Platform.isAndroid) && themeManager.isCupertinoFramework;
    final now = TimeOfDay.now();

    return Padding(
      padding: const EdgeInsets.only(top: 8.0, bottom: 8.0),
      child: Row(
        children: [
          Icon(
            isCupertino ? CupertinoIcons.sun_max_fill : Icons.wb_twilight_rounded, 
            color: isCupertino ? ThemeManager.iosBlue : cs.primary,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _greetText(now),
                  style: isCupertino 
                      ? const TextStyle(fontSize: 22, fontWeight: FontWeight.bold, letterSpacing: -0.5)
                      : Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 2),
                Text(
                  _subGreeting(now),
                  style: isCupertino 
                      ? TextStyle(fontSize: 14, color: CupertinoColors.systemGrey)
                      : Theme.of(context).textTheme.bodyMedium?.copyWith(color: cs.onSurfaceVariant),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          FutureBuilder<String?>(
            future: WeatherService().fetchWeatherText(),
            builder: (context, snap) {
              final txt = snap.data?.toString();
              if (txt == null || txt.isEmpty) return const SizedBox.shrink();
              return Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(isCupertino ? CupertinoIcons.sun_max : Icons.wb_sunny_rounded, 
                    size: 16, color: isCupertino ? CupertinoColors.systemGrey : cs.onSurfaceVariant),
                  const SizedBox(width: 6),
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 220),
                    child: Text(txt, maxLines: 1, overflow: TextOverflow.ellipsis,
                      style: isCupertino
                          ? TextStyle(fontSize: 14, color: CupertinoColors.systemGrey)
                          : Theme.of(context).textTheme.bodyMedium?.copyWith(color: cs.onSurfaceVariant)),
                  ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

/// Hero 双卡区域 - 每日推荐 + 私人FM 并排
class _HeroSection extends StatelessWidget {
  final List<Map<String, dynamic>> dailySongs;
  final List<Map<String, dynamic>> fmList;
  final VoidCallback? onOpenDailyDetail;
  
  const _HeroSection({
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
              Expanded(flex: 3, child: _DailyRecommendHeroCard(tracks: dailySongs, onOpenDetail: onOpenDailyDetail)),
              const SizedBox(width: 16),
              Expanded(flex: 2, child: _PersonalFmCompactCard(list: fmList)),
            ],
          );
        } else {
          // 窄屏：上下堆叠
          return Column(
            children: [
              _DailyRecommendHeroCard(tracks: dailySongs, onOpenDetail: onOpenDailyDetail),
              const SizedBox(height: 12),
              _PersonalFmCompactCard(list: fmList),
            ],
          );
        }
      },
    );
  }
}

/// 每日推荐 Hero 大卡片
class _DailyRecommendHeroCard extends StatefulWidget {
  final List<Map<String, dynamic>> tracks;
  final VoidCallback? onOpenDetail;
  const _DailyRecommendHeroCard({required this.tracks, this.onOpenDetail});

  @override
  State<_DailyRecommendHeroCard> createState() => _DailyRecommendHeroCardState();
}

class _DailyRecommendHeroCardState extends State<_DailyRecommendHeroCard> {
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
                          _GradientPlayButton(
                            onPressed: () async {
                              final tracks = widget.tracks.map((m) => _convertToTrack(m)).toList();
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
          child: CachedNetworkImage(imageUrl: covers[i], fit: BoxFit.cover),
        );
      },
    );
  }
}

/// 私人FM 紧凑卡片
class _PersonalFmCompactCard extends StatelessWidget {
  final List<Map<String, dynamic>> list;
  const _PersonalFmCompactCard({required this.list});

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
        final fmTracks = list.map((m) => _convertToTrack(m)).toList();
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
                      child: CachedNetworkImage(imageUrl: pic, fit: BoxFit.cover),
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
                                    ? CachedNetworkImage(imageUrl: pic, fit: BoxFit.cover)
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
                            child: _FmControlButton(
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
                            child: _FmControlButton(
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

class _FmControlButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onPressed;
  const _FmControlButton({required this.icon, required this.label, required this.onPressed});

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
class _GradientPlayButton extends StatefulWidget {
  final VoidCallback onPressed;
  const _GradientPlayButton({required this.onPressed});

  @override
  State<_GradientPlayButton> createState() => _GradientPlayButtonState();
}

class _GradientPlayButtonState extends State<_GradientPlayButton> {
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

/// Bento 网格歌单 - 1大+4小布局
class _BentoPlaylistGrid extends StatelessWidget {
  final List<Map<String, dynamic>> list;
  final void Function(int id)? onTap;
  const _BentoPlaylistGrid({required this.list, this.onTap});

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
                Expanded(flex: 3, child: _LargePlaylistCard(playlist: list[0], onTap: onTap)),
                const SizedBox(width: 12),
                Expanded(
                  flex: 4,
                  child: Column(
                    children: [
                      Expanded(
                        child: Row(
                          children: [
                            Expanded(child: _SmallPlaylistCard(playlist: list[1], onTap: onTap)),
                            const SizedBox(width: 12),
                            Expanded(child: _SmallPlaylistCard(playlist: list[2], onTap: onTap)),
                          ],
                        ),
                      ),
                      const SizedBox(height: 12),
                      Expanded(
                        child: Row(
                          children: [
                            Expanded(child: _SmallPlaylistCard(playlist: list[3], onTap: onTap)),
                            const SizedBox(width: 12),
                            Expanded(child: _SmallPlaylistCard(playlist: list[4], onTap: onTap)),
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
          itemBuilder: (context, i) => _SmallPlaylistCard(playlist: list[i], onTap: onTap),
        );
      },
    );
  }
}

class _LargePlaylistCard extends StatefulWidget {
  final Map<String, dynamic> playlist;
  final void Function(int id)? onTap;
  const _LargePlaylistCard({required this.playlist, this.onTap});

  @override
  State<_LargePlaylistCard> createState() => _LargePlaylistCardState();
}

class _LargePlaylistCardState extends State<_LargePlaylistCard> {
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
                  child: CachedNetworkImage(imageUrl: pic, fit: BoxFit.cover),
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

class _SmallPlaylistCard extends StatefulWidget {
  final Map<String, dynamic> playlist;
  final void Function(int id)? onTap;
  const _SmallPlaylistCard({required this.playlist, this.onTap});

  @override
  State<_SmallPlaylistCard> createState() => _SmallPlaylistCardState();
}

class _SmallPlaylistCardState extends State<_SmallPlaylistCard> {
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
                  child: CachedNetworkImage(imageUrl: pic, fit: BoxFit.cover),
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

/// 横向滚动歌单 - Microsoft Store 风格
class _HorizontalPlaylistCarousel extends StatelessWidget {
  final List<Map<String, dynamic>> list;
  final void Function(int id)? onTap;
  const _HorizontalPlaylistCarousel({required this.list, this.onTap});

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
            itemBuilder: (context, i) => _CarouselPlaylistCard(playlist: list[i], onTap: onTap),
          ),
        );
      },
    );
  }
}

class _CarouselPlaylistCard extends StatefulWidget {
  final Map<String, dynamic> playlist;
  final void Function(int id)? onTap;
  const _CarouselPlaylistCard({required this.playlist, this.onTap});

  @override
  State<_CarouselPlaylistCard> createState() => _CarouselPlaylistCardState();
}

class _CarouselPlaylistCardState extends State<_CarouselPlaylistCard> {
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
                        child: CachedNetworkImage(imageUrl: pic, fit: BoxFit.cover),
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

/// 雷达歌单网格 - 统一尺寸
class _MixedSizePlaylistGrid extends StatelessWidget {
  final List<Map<String, dynamic>> list;
  final void Function(int id)? onTap;
  const _MixedSizePlaylistGrid({required this.list, this.onTap});

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
                child: _MixedPlaylistCard(playlist: list[i], isLarge: false, onTap: onTap),
              );
            },
          ),
        );
      },
    );
  }
}

class _MixedPlaylistCard extends StatefulWidget {
  final Map<String, dynamic> playlist;
  final bool isLarge;
  final void Function(int id)? onTap;
  const _MixedPlaylistCard({required this.playlist, this.isLarge = false, this.onTap});

  @override
  State<_MixedPlaylistCard> createState() => _MixedPlaylistCardState();
}

class _MixedPlaylistCardState extends State<_MixedPlaylistCard> {
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
                        child: CachedNetworkImage(imageUrl: pic, fit: BoxFit.cover),
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

/// 新歌卡片网格
class _NewsongCards extends StatelessWidget {
  final List<Map<String, dynamic>> list;
  const _NewsongCards({required this.list});

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
            itemBuilder: (context, i) => _NewsongCard(song: list[i]),
          ),
        );
      },
    );
  }
}

class _NewsongCard extends StatefulWidget {
  final Map<String, dynamic> song;
  const _NewsongCard({required this.song});

  @override
  State<_NewsongCard> createState() => _NewsongCardState();
}

class _NewsongCardState extends State<_NewsongCard> {
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
          final track = _convertToTrack(songData);
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
                          child: CachedNetworkImage(imageUrl: pic, fit: BoxFit.cover),
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

/// 转换为 Track 对象
Track _convertToTrack(Map<String, dynamic> song) {
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

// ============================================================================
// 移动端原始布局组件
// ============================================================================

/// 每日推荐卡片（移动端）
class _DailyRecommendCard extends StatelessWidget {
  final List<Map<String, dynamic>> tracks;
  final VoidCallback? onOpenDetail;
  const _DailyRecommendCard({required this.tracks, this.onOpenDetail});
  
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final themeManager = ThemeManager();
    final isCupertino = (Platform.isIOS || Platform.isAndroid) && themeManager.isCupertinoFramework;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    
    // 获取前4首歌曲的封面
    final coverImages = tracks.take(4).map((s) {
      final al = (s['al'] ?? s['album'] ?? {}) as Map<String, dynamic>;
      return (al['picUrl'] ?? '').toString();
    }).where((url) => url.isNotEmpty).toList();
    
    // iOS Cupertino 风格
    if (isCupertino) {
      return _buildCupertinoCard(context, coverImages, isDark);
    }
    
    final cardContent = _buildMaterialCardContent(context, coverImages, cs);

    if (themeManager.isFluentFramework) {
      return fluent.Card(
        padding: EdgeInsets.zero,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(6.0),
          child: cardContent,
        ),
      );
    }
    
    return Card(
      clipBehavior: Clip.antiAlias,
      color: cs.surfaceContainerHighest,
      child: cardContent,
    );
  }
  
  /// iOS 风格的卡片
  Widget _buildCupertinoCard(BuildContext context, List<String> coverImages, bool isDark) {
    final now = DateTime.now();
    final dayOfMonth = now.day;
    final weekday = ['周日', '周一', '周二', '周三', '周四', '周五', '周六'][now.weekday % 7];
    
    return GestureDetector(
      onTap: () {
        if (onOpenDetail != null) {
          onOpenDetail!();
        } else {
          Navigator.of(context).push(
            CupertinoPageRoute(
              builder: (context) => DailyRecommendDetailPage(tracks: tracks),
            ),
          );
        }
      },
      child: Container(
        height: 180,
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF1C1C1E) : CupertinoColors.white,
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            BoxShadow(
              color: CupertinoColors.black.withOpacity(isDark ? 0.2 : 0.08),
              blurRadius: 10,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '每日推荐',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: isDark ? Colors.white : Colors.black,
                    letterSpacing: -0.5,
                  ),
                ),
                const Spacer(),
                Row(
                  children: [
                    _buildDateBadge(context, dayOfMonth, weekday, isDark),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            '根据你的品味生成',
                            style: TextStyle(
                              fontSize: 14,
                              color: isDark
                                  ? Colors.white.withOpacity(0.7)
                                  : Colors.black.withOpacity(0.6),
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '${tracks.length} 首歌曲',
                            style: TextStyle(
                              fontSize: 13,
                              color: isDark
                                  ? Colors.white.withOpacity(0.5)
                                  : Colors.black.withOpacity(0.45),
                            ),
                          ),
                          const SizedBox(height: 10),
                          _buildCoverThumbnails(context, coverImages, isDark),
                        ],
                      ),
                    ),
                    _buildPlayButton(context, isDark),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
  
  /// 日期徽章
  Widget _buildDateBadge(BuildContext context, int day, String weekday, bool isDark) {
    return Container(
      width: 72,
      height: 72,
      decoration: BoxDecoration(
        color: isDark
            ? Colors.white.withOpacity(0.1)
            : Colors.black.withOpacity(0.05),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isDark
              ? Colors.white.withOpacity(0.15)
              : Colors.black.withOpacity(0.08),
          width: 1,
        ),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            day.toString().padLeft(2, '0'),
            style: TextStyle(
              fontSize: 32,
              fontWeight: FontWeight.w700,
              color: ThemeManager.iosBlue,
              height: 1,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            weekday,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w500,
              color: isDark
                  ? Colors.white.withOpacity(0.6)
                  : Colors.black.withOpacity(0.5),
            ),
          ),
        ],
      ),
    );
  }
  
  /// 封面缩略图
  Widget _buildCoverThumbnails(BuildContext context, List<String> coverImages, bool isDark) {
    final displayCovers = coverImages.take(4).toList();
    
    return SizedBox(
      height: 36,
      child: Row(
        children: [
          ...List.generate(displayCovers.length, (index) {
            return Transform.translate(
              offset: Offset(-index * 12.0, 0),
              child: Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: isDark
                        ? Colors.black.withOpacity(0.3)
                        : Colors.white,
                    width: 2,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.15),
                      blurRadius: 4,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: displayCovers[index].isNotEmpty
                      ? CachedNetworkImage(
                          imageUrl: displayCovers[index],
                          fit: BoxFit.cover,
                        )
                      : Container(
                          color: isDark
                              ? const Color(0xFF3A3A3C)
                              : const Color(0xFFE5E5EA),
                          child: Icon(
                            CupertinoIcons.music_note,
                            size: 16,
                            color: isDark
                                ? Colors.white.withOpacity(0.5)
                                : Colors.black.withOpacity(0.3),
                          ),
                        ),
                ),
              ),
            );
          }),
          if (tracks.length > 4)
            Transform.translate(
              offset: Offset(-displayCovers.length * 12.0, 0),
              child: Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: isDark
                      ? Colors.white.withOpacity(0.15)
                      : Colors.black.withOpacity(0.08),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Center(
                  child: Text(
                    '+${tracks.length - 4}',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: isDark
                          ? Colors.white.withOpacity(0.8)
                          : Colors.black.withOpacity(0.6),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
  
  /// 播放按钮
  Widget _buildPlayButton(BuildContext context, bool isDark) {
    return Container(
      width: 52,
      height: 52,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            ThemeManager.iosBlue,
            ThemeManager.iosBlue.withBlue(230),
          ],
        ),
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(
            color: ThemeManager.iosBlue.withOpacity(0.4),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: const Icon(
        CupertinoIcons.play_fill,
        color: Colors.white,
        size: 24,
      ),
    );
  }
  
  /// Material 风格卡片内容
  Widget _buildMaterialCardContent(BuildContext context, List<String> coverImages, ColorScheme cs) {
    return InkWell(
      onTap: () {
        if (onOpenDetail != null) {
          onOpenDetail!();
        } else {
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (context) => DailyRecommendDetailPage(tracks: tracks),
            ),
          );
        }
      },
      child: LayoutBuilder(
        builder: (context, constraints) {
          final bool isNarrow = constraints.maxWidth < 480;
          final EdgeInsets contentPadding = const EdgeInsets.all(16);
          if (isNarrow) {
            final double gridSize = (constraints.maxWidth * 0.38).clamp(120.0, 180.0);
            return Padding(
              padding: contentPadding,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  SizedBox(
                    width: gridSize,
                    height: gridSize,
                    child: _buildCoverGrid(context, coverImages),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Align(
                          alignment: Alignment.centerLeft,
                          child: Text(
                            '每日推荐',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.bold,
                              color: cs.primary,
                            ),
                          ),
                        ),
                        const SizedBox(height: 6),
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                '${tracks.length} 首歌曲',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 13,
                                  color: cs.onSurface.withOpacity(0.65),
                                ),
                              ),
                            ),
                            const SizedBox(width: 6),
                            Icon(Icons.auto_awesome, size: 18, color: cs.primary),
                            const SizedBox(width: 6),
                            Flexible(
                              child: Text(
                                '根据你的音乐品味每日更新',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                textAlign: TextAlign.right,
                                style: TextStyle(
                                  fontSize: 12,
                                  color: cs.onSurface.withOpacity(0.7),
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        Align(
                          alignment: Alignment.centerRight,
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 140),
                            child: FilledButton.icon(
                              onPressed: () {
                                if (onOpenDetail != null) {
                                  onOpenDetail!();
                                } else {
                                  Navigator.of(context).push(
                                    MaterialPageRoute(
                                      builder: (context) => DailyRecommendDetailPage(tracks: tracks),
                                    ),
                                  );
                                }
                              },
                              icon: const Icon(Icons.chevron_right, size: 20),
                              label: const Text('查看全部'),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            );
          }

          return Container(
            height: 200,
            padding: contentPadding.add(const EdgeInsets.all(4)),
            child: Row(
              children: [
                SizedBox(
                  width: 160,
                  height: 160,
                  child: _buildCoverGrid(context, coverImages),
                ),
                const SizedBox(width: 24),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          '每日推荐',
                          style: TextStyle(
                            fontSize: 28,
                            fontWeight: FontWeight.bold,
                            color: cs.primary,
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Align(
                        alignment: Alignment.centerRight,
                        child: Text(
                          '${tracks.length} 首歌曲',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          textAlign: TextAlign.right,
                          style: TextStyle(
                            fontSize: 16,
                            color: cs.onSurface.withOpacity(0.6),
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      Align(
                        alignment: Alignment.centerRight,
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.auto_awesome,
                              size: 20,
                              color: cs.primary,
                            ),
                            const SizedBox(width: 8),
                            Flexible(
                              child: Text(
                                '根据你的音乐品味每日更新',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                textAlign: TextAlign.right,
                                style: TextStyle(
                                  fontSize: 14,
                                  color: cs.onSurface.withOpacity(0.7),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 12),
                      Align(
                        alignment: Alignment.centerRight,
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 140),
                          child: FilledButton.icon(
                            onPressed: () {
                              if (onOpenDetail != null) {
                                onOpenDetail!();
                              } else {
                                Navigator.of(context).push(
                                  MaterialPageRoute(
                                    builder: (context) => DailyRecommendDetailPage(tracks: tracks),
                                  ),
                                );
                              }
                            },
                            icon: const Icon(Icons.chevron_right, size: 20),
                            label: const Text(
                              '查看全部',
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
  
  /// 构建封面网格（2x2）
  Widget _buildCoverGrid(BuildContext context, List<String> coverImages) {
    final cs = Theme.of(context).colorScheme;
    final covers = List<String>.from(coverImages);
    
    while (covers.length < 4) {
      covers.add('');
    }
    
    return GridView.builder(
      padding: EdgeInsets.zero,
      physics: const NeverScrollableScrollPhysics(),
      shrinkWrap: true,
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        crossAxisSpacing: 4,
        mainAxisSpacing: 4,
      ),
      itemCount: 4,
      itemBuilder: (context, index) {
        final url = covers[index];
        return ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: url.isEmpty
              ? Container(
                  color: cs.surfaceContainerHighest,
                  child: Icon(
                    Icons.music_note,
                    color: cs.onSurface.withOpacity(0.3),
                  ),
                )
              : CachedNetworkImage(
                  imageUrl: url,
                  fit: BoxFit.cover,
                  placeholder: (context, url) => Container(
                    color: cs.surfaceContainerHighest,
                    child: Icon(
                      Icons.music_note,
                      color: cs.onSurface.withOpacity(0.3),
                    ),
                  ),
                  errorWidget: (context, url, error) => Container(
                    color: cs.surfaceContainerHighest,
                    child: Icon(
                      Icons.broken_image,
                      color: cs.onSurface.withOpacity(0.3),
                    ),
                  ),
                ),
        );
      },
    );
  }
}

/// 私人FM（移动端）
class _PersonalFm extends StatelessWidget {
  final List<Map<String, dynamic>> list;
  const _PersonalFm({required this.list});
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final themeManager = ThemeManager();
    final isCupertino = (Platform.isIOS || Platform.isAndroid) && themeManager.isCupertinoFramework;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    if (list.isEmpty) return Text('暂无数据', style: Theme.of(context).textTheme.bodySmall);
    return AnimatedBuilder(
      animation: PlayerService(),
      builder: (context, _) {
        Map<String, dynamic> display = list.first;
        final current = PlayerService().currentTrack;
        if (current != null && current.source == MusicSource.netease) {
          for (final m in list) {
            final id = (m['id'] ?? (m['song'] != null ? (m['song'] as Map<String, dynamic>)['id'] : null)) as dynamic;
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

        final fmTracks = _convertListToTracks(list);
        final isFmCurrent = _currentTrackInList(fmTracks);
        final isFmQueue = _isSameQueueAs(fmTracks);
        final isFmPlaying = PlayerService().isPlaying && (isFmCurrent || isFmQueue);

        final cardContent = Padding(
          padding: const EdgeInsets.all(12.0),
          child: Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: Image.network(pic, width: 120, height: 120, fit: BoxFit.cover),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(display['name']?.toString() ?? '', maxLines: 1, overflow: TextOverflow.ellipsis, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600)),
                    const SizedBox(height: 6),
                    Text(artistsText, maxLines: 1, overflow: TextOverflow.ellipsis, style: Theme.of(context).textTheme.bodySmall),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  isCupertino 
                      ? CupertinoButton(
                          padding: const EdgeInsets.all(8),
                          onPressed: () async {
                            final tracks = fmTracks;
                            if (tracks.isEmpty) return;
                            final ps = PlayerService();
                            if (isFmPlaying) {
                              await ps.pause();
                            } else if (ps.isPaused && (isFmQueue || isFmCurrent)) {
                              await ps.resume();
                            } else {
                              PlaylistQueueService().setQueue(tracks, 0, QueueSource.playlist);
                              await ps.playTrack(tracks.first);
                            }
                          },
                          child: Icon(
                            isFmPlaying ? CupertinoIcons.pause_fill : CupertinoIcons.play_fill, 
                            color: ThemeManager.iosBlue,
                            size: 28,
                          ),
                        )
                      : IconButton(
                          onPressed: () async {
                            final tracks = fmTracks;
                            if (tracks.isEmpty) return;
                            final ps = PlayerService();
                            if (isFmPlaying) {
                              await ps.pause();
                            } else if (ps.isPaused && (isFmQueue || isFmCurrent)) {
                              await ps.resume();
                            } else {
                              PlaylistQueueService().setQueue(tracks, 0, QueueSource.playlist);
                              await ps.playTrack(tracks.first);
                              if (context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(content: Text('开始播放私人FM')),
                                );
                              }
                            }
                          },
                          style: IconButton.styleFrom(
                            hoverColor: Theme.of(context).colorScheme.onSurface.withOpacity(0.08),
                            focusColor: Theme.of(context).colorScheme.onSurface.withOpacity(0.12),
                            overlayColor: Theme.of(context).colorScheme.onSurface.withOpacity(0.10),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                          ),
                          icon: Icon(isFmPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded, color: cs.onSurface),
                          tooltip: isFmPlaying ? '暂停' : '播放',
                        ),
                  const SizedBox(width: 8),
                  isCupertino 
                      ? CupertinoButton(
                          padding: const EdgeInsets.all(8),
                          onPressed: () async {
                            final tracks = fmTracks;
                            if (tracks.isEmpty) return;
                            if (_isSameQueueAs(tracks)) {
                              await PlayerService().playNext();
                            } else {
                              final startIndex = tracks.length > 1 ? 1 : 0;
                              PlaylistQueueService().setQueue(tracks, startIndex, QueueSource.playlist);
                              await PlayerService().playTrack(tracks[startIndex]);
                            }
                          },
                          child: Icon(
                            CupertinoIcons.forward_fill, 
                            color: ThemeManager.iosBlue,
                            size: 28,
                          ),
                        )
                      : IconButton(
                          onPressed: () async {
                            final tracks = fmTracks;
                            if (tracks.isEmpty) return;
                            if (_isSameQueueAs(tracks)) {
                              await PlayerService().playNext();
                            } else {
                              final startIndex = tracks.length > 1 ? 1 : 0;
                              PlaylistQueueService().setQueue(tracks, startIndex, QueueSource.playlist);
                              await PlayerService().playTrack(tracks[startIndex]);
                            }
                          },
                          style: IconButton.styleFrom(
                            hoverColor: Theme.of(context).colorScheme.onSurface.withOpacity(0.08),
                            focusColor: Theme.of(context).colorScheme.onSurface.withOpacity(0.12),
                            overlayColor: Theme.of(context).colorScheme.onSurface.withOpacity(0.10),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                          ),
                          icon: Icon(Icons.skip_next_rounded, color: cs.onSurface),
                          tooltip: '下一首',
                        ),
                ],
              ),
            ],
          ),
        );

        if (themeManager.isFluentFramework) {
          return fluent.Card(
            padding: EdgeInsets.zero,
            child: cardContent,
          );
        }

        if (isCupertino) {
          return Container(
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF1C1C1E) : CupertinoColors.white,
              borderRadius: BorderRadius.circular(12),
              boxShadow: [
                BoxShadow(
                  color: CupertinoColors.black.withOpacity(isDark ? 0.2 : 0.08),
                  blurRadius: 10,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: cardContent,
          );
        }

        return Card(
          color: cs.surfaceContainer,
          child: cardContent,
        );
      },
    );
  }

  List<Track> _convertListToTracks(List<Map<String, dynamic>> src) {
    return src.map((m) => _convertToTrack(m)).toList();
  }

  bool _isSameQueueAs(List<Track> tracks) {
    final q = PlaylistQueueService().queue;
    if (q.length != tracks.length) return false;
    for (var i = 0; i < q.length; i++) {
      if (q[i].id.toString() != tracks[i].id.toString() || q[i].source != tracks[i].source) {
        return false;
      }
    }
    return true;
  }

  bool _currentTrackInList(List<Track> tracks) {
    final ct = PlayerService().currentTrack;
    if (ct == null) return false;
    return tracks.any((t) => t.id.toString() == ct.id.toString() && t.source == ct.source);
  }
}

/// 歌单网格（移动端）
class _PlaylistGrid extends StatelessWidget {
  final List<Map<String, dynamic>> list;
  final void Function(int id)? onTap;
  const _PlaylistGrid({required this.list, this.onTap});
  @override
  Widget build(BuildContext context) {
    if (list.isEmpty) return Text('暂无数据', style: Theme.of(context).textTheme.bodySmall);
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 220,
        childAspectRatio: 0.68,
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
      ),
      itemCount: list.length,
      itemBuilder: (context, i) {
        final p = list[i];
        final pic = (p['picUrl'] ?? p['coverImgUrl'] ?? '').toString();
        final idVal = p['id'];
        final id = int.tryParse(idVal?.toString() ?? '');
        return InkWell(
          onTap: id != null && onTap != null ? () => onTap!(id) : null,
          child: _HoverPlaylistCard(
            name: p['name']?.toString() ?? '',
            picUrl: pic,
            description: (p['description'] ?? p['copywriter'] ?? '').toString(),
          ),
        );
      },
    );
  }
}

class _HoverPlaylistCard extends StatefulWidget {
  final String name;
  final String picUrl;
  final String description;
  const _HoverPlaylistCard({required this.name, required this.picUrl, required this.description});

  @override
  State<_HoverPlaylistCard> createState() => _HoverPlaylistCardState();
}

class _HoverPlaylistCardState extends State<_HoverPlaylistCard> {
  bool _hovering = false;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final themeManager = ThemeManager();
    final isCupertino = (Platform.isIOS || Platform.isAndroid) && themeManager.isCupertinoFramework;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    
    return MouseRegion(
      onEnter: (_) => setState(() => _hovering = true),
      onExit: (_) => setState(() => _hovering = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        curve: Curves.easeOut,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          boxShadow: _hovering
              ? [
                  BoxShadow(
                    color: cs.shadow.withOpacity(0.06),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  )
                ]
              : [],
        ),
        child: isCupertino
            ? Container(
                decoration: BoxDecoration(
                  color: isDark ? const Color(0xFF1C1C1E) : CupertinoColors.white,
                  borderRadius: BorderRadius.circular(12),
                ),
                clipBehavior: Clip.antiAlias,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    AspectRatio(
                      aspectRatio: 1,
                      child: ClipRect(
                        child: Stack(
                          fit: StackFit.expand,
                          children: [
                            SizedBox.expand(
                              child: AnimatedScale(
                                duration: const Duration(milliseconds: 160),
                                curve: Curves.easeOut,
                                scale: _hovering ? 1.10 : 1.0,
                                child: CachedNetworkImage(
                                  imageUrl: widget.picUrl,
                                  fit: BoxFit.cover,
                                  placeholder: (context, url) => Container(
                                    color: CupertinoColors.systemGrey6,
                                    child: const Icon(
                                      CupertinoIcons.music_note,
                                      color: CupertinoColors.systemGrey,
                                    ),
                                  ),
                                  errorWidget: (context, url, error) => Container(
                                    color: CupertinoColors.systemGrey6,
                                    child: const Icon(
                                      CupertinoIcons.exclamationmark_circle,
                                      color: CupertinoColors.systemGrey,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                            Align(
                              alignment: Alignment.bottomCenter,
                              child: AnimatedSlide(
                                duration: const Duration(milliseconds: 200),
                                curve: Curves.easeOutCubic,
                                offset: _hovering ? Offset.zero : const Offset(0, 1),
                                child: FractionallySizedBox(
                                  widthFactor: 1.0,
                                  heightFactor: 0.38,
                                  alignment: Alignment.bottomCenter,
                                  child: Container(
                                    decoration: BoxDecoration(
                                      gradient: LinearGradient(
                                        begin: Alignment.topCenter,
                                        end: Alignment.bottomCenter,
                                        colors: [
                                          Colors.black.withOpacity(0.0),
                                          Colors.black.withOpacity(0.65),
                                        ],
                                      ),
                                    ),
                                    padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
                                    child: Align(
                                      alignment: Alignment.bottomLeft,
                                      child: Text(
                                        (widget.description.isNotEmpty ? widget.description : widget.name),
                                        style: const TextStyle(color: Colors.white, fontSize: 12, height: 1.2),
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.all(8.0),
                      child: SizedBox(
                        width: double.infinity,
                        height: 50,
                        child: Align(
                          alignment: Alignment.topLeft,
                          child: Text(
                            widget.name,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            softWrap: true,
                            textAlign: TextAlign.left,
                            style: TextStyle(
                              fontWeight: FontWeight.w600,
                              color: isDark ? CupertinoColors.white : CupertinoColors.black,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              )
            : Card(
          clipBehavior: Clip.antiAlias,
          elevation: 0,
          color: themeManager.isFluentFramework ? null : cs.surfaceContainer,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              AspectRatio(
                aspectRatio: 1,
                child: ClipRect(
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      SizedBox.expand(
                        child: AnimatedScale(
                          duration: const Duration(milliseconds: 160),
                          curve: Curves.easeOut,
                          scale: _hovering ? 1.10 : 1.0,
                          child: CachedNetworkImage(
                            imageUrl: widget.picUrl,
                            fit: BoxFit.cover,
                            placeholder: (context, url) => Container(
                              color: cs.surfaceContainerHighest,
                              child: Icon(
                                Icons.music_note,
                                color: cs.onSurface.withOpacity(0.3),
                              ),
                            ),
                            errorWidget: (context, url, error) => Container(
                              color: cs.surfaceContainerHighest,
                              child: Icon(
                                Icons.broken_image,
                                color: cs.onSurface.withOpacity(0.3),
                              ),
                            ),
                          ),
                        ),
                      ),
                      Align(
                        alignment: Alignment.bottomCenter,
                        child: AnimatedSlide(
                          duration: const Duration(milliseconds: 200),
                          curve: Curves.easeOutCubic,
                          offset: _hovering ? Offset.zero : const Offset(0, 1),
                          child: FractionallySizedBox(
                            widthFactor: 1.0,
                            heightFactor: 0.38,
                            alignment: Alignment.bottomCenter,
                            child: Container(
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  begin: Alignment.topCenter,
                                  end: Alignment.bottomCenter,
                                  colors: [
                                    Colors.black.withOpacity(0.0),
                                    Colors.black.withOpacity(0.65),
                                  ],
                                ),
                              ),
                              padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
                              child: Align(
                                alignment: Alignment.bottomLeft,
                                child: Text(
                                  (widget.description.isNotEmpty ? widget.description : widget.name),
                                  style: const TextStyle(color: Colors.white, fontSize: 12, height: 1.2),
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(8.0),
                child: SizedBox(
                  width: double.infinity,
                  height: 50,
                  child: Align(
                    alignment: Alignment.topLeft,
                    child: Text(
                      widget.name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      softWrap: true,
                      textAlign: TextAlign.left,
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 新歌列表（移动端）
class _NewsongList extends StatelessWidget {
  final List<Map<String, dynamic>> list;
  const _NewsongList({required this.list});
  @override
  Widget build(BuildContext context) {
    final themeManager = ThemeManager();
    final isCupertino = (Platform.isIOS || Platform.isAndroid) && themeManager.isCupertinoFramework;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    
    if (list.isEmpty) return Text('暂无数据', style: Theme.of(context).textTheme.bodySmall);
    
    if (isCupertino) {
      return Container(
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF1C1C1E) : CupertinoColors.white,
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            BoxShadow(
              color: CupertinoColors.black.withOpacity(isDark ? 0.2 : 0.08),
              blurRadius: 10,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        clipBehavior: Clip.antiAlias,
        child: ListView.separated(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: list.length,
          separatorBuilder: (_, __) => Divider(
            height: 0.5,
            color: isDark 
                ? CupertinoColors.systemGrey.withOpacity(0.3)
                : CupertinoColors.systemGrey.withOpacity(0.2),
          ),
          itemBuilder: (context, i) {
            final s = list[i];
            final song = (s['song'] ?? s);
            final al = (song['al'] ?? song['album'] ?? {}) as Map<String, dynamic>;
            final ar = (song['ar'] ?? song['artists'] ?? []) as List<dynamic>;
            final pic = (al['picUrl'] ?? '').toString();
            final artists = ar.map((e) => (e as Map<String, dynamic>)['name']?.toString() ?? '').where((e) => e.isNotEmpty).join('/');
            return CupertinoButton(
              padding: EdgeInsets.zero,
              onPressed: () {
                // TODO: Play this song
              },
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                child: Row(
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(6), 
                      child: Image.network(pic, width: 48, height: 48, fit: BoxFit.cover),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            song['name']?.toString() ?? '', 
                            maxLines: 1, 
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w500,
                              color: isDark ? CupertinoColors.white : CupertinoColors.black,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            artists, 
                            maxLines: 1, 
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 13,
                              color: CupertinoColors.systemGrey,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Icon(
                      CupertinoIcons.chevron_right,
                      size: 16,
                      color: CupertinoColors.systemGrey,
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      );
    }
    
    return ListView.separated(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: list.length,
      separatorBuilder: (_, __) => const Divider(height: 1),
      itemBuilder: (context, i) {
        final s = list[i];
        final song = (s['song'] ?? s);
        final al = (song['al'] ?? song['album'] ?? {}) as Map<String, dynamic>;
        final ar = (song['ar'] ?? song['artists'] ?? []) as List<dynamic>;
        final pic = (al['picUrl'] ?? '').toString();
        final artists = ar.map((e) => (e as Map<String, dynamic>)['name']?.toString() ?? '').where((e) => e.isNotEmpty).join('/');
        return ListTile(
          leading: ClipRRect(borderRadius: BorderRadius.circular(6), child: Image.network(pic, width: 48, height: 48, fit: BoxFit.cover)),
          title: Text(song['name']?.toString() ?? '', maxLines: 1, overflow: TextOverflow.ellipsis),
          subtitle: Text(artists, maxLines: 1, overflow: TextOverflow.ellipsis),
        );
      },
    );
  }
}

/// 未登录状态下的精美登录提示组件
/// 适配 iOS Cupertino、Material Design 3 和 Fluent UI 三种主题
class _ForYouLoginPrompt extends StatefulWidget {
  final VoidCallback onLoginPressed;
  
  const _ForYouLoginPrompt({required this.onLoginPressed});
  
  @override
  State<_ForYouLoginPrompt> createState() => _ForYouLoginPromptState();
}

class _ForYouLoginPromptState extends State<_ForYouLoginPrompt> 
    with SingleTickerProviderStateMixin {
  late AnimationController _animationController;
  late Animation<double> _fadeAnimation;
  late Animation<Offset> _slideAnimation;
  
  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );
    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _animationController, curve: Curves.easeOut),
    );
    _slideAnimation = Tween<Offset>(
      begin: const Offset(0, 0.1),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _animationController, curve: Curves.easeOutCubic));
    _animationController.forward();
  }
  
  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }
  
  @override
  Widget build(BuildContext context) {
    final themeManager = ThemeManager();
    final isMobile = Platform.isIOS || Platform.isAndroid;
    
    if (themeManager.isFluentFramework) {
      return _buildFluentPrompt(context);
    }
    
    if (isMobile && themeManager.isCupertinoFramework) {
      return _buildCupertinoPrompt(context);
    }
    
    return _buildMaterialPrompt(context);
  }
  
  /// Material Design 3 风格登录提示
  Widget _buildMaterialPrompt(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    
    return FadeTransition(
      opacity: _fadeAnimation,
      child: SlideTransition(
        position: _slideAnimation,
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // 动画图标区域
                TweenAnimationBuilder<double>(
                  tween: Tween(begin: 0.8, end: 1.0),
                  duration: const Duration(milliseconds: 1200),
                  curve: Curves.elasticOut,
                  builder: (context, value, child) {
                    return Transform.scale(scale: value, child: child);
                  },
                  child: Container(
                    width: 140,
                    height: 140,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [
                          cs.primary.withOpacity(0.15),
                          cs.tertiary.withOpacity(0.1),
                        ],
                      ),
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: cs.primary.withOpacity(0.1),
                          blurRadius: 30,
                          spreadRadius: 5,
                        ),
                      ],
                    ),
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        // 外圈装饰
                        Container(
                          width: 120,
                          height: 120,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: cs.primary.withOpacity(0.3),
                              width: 2,
                            ),
                          ),
                        ),
                        // 音符图标
                        Icon(
                          Icons.music_note_rounded,
                          size: 60,
                          color: cs.primary,
                        ),
                        // 锁图标叠加
                        Positioned(
                          right: 25,
                          bottom: 25,
                          child: Container(
                            padding: const EdgeInsets.all(6),
                            decoration: BoxDecoration(
                              color: cs.surfaceContainerHighest,
                              shape: BoxShape.circle,
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withOpacity(0.1),
                                  blurRadius: 8,
                                ),
                              ],
                            ),
                            child: Icon(
                              Icons.lock_outline_rounded,
                              size: 20,
                              color: cs.onSurfaceVariant,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 40),
                // 标题
                Text(
                  '登录后查看更多内容',
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: cs.onSurface,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 16),
                // 副标题
                Container(
                  constraints: const BoxConstraints(maxWidth: 300),
                  child: Text(
                    '登录即可获取每日推荐、私人FM、专属歌单等个性化内容',
                    style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                      color: cs.onSurfaceVariant,
                      height: 1.5,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
                const SizedBox(height: 40),
                // 功能亮点
                Container(
                  constraints: const BoxConstraints(maxWidth: 360),
                  child: Wrap(
                    spacing: 12,
                    runSpacing: 12,
                    alignment: WrapAlignment.center,
                    children: [
                      _buildFeatureChip(context, Icons.calendar_today, '每日推荐', cs),
                      _buildFeatureChip(context, Icons.radio, '私人FM', cs),
                      _buildFeatureChip(context, Icons.library_music, '专属歌单', cs),
                      _buildFeatureChip(context, Icons.new_releases_outlined, '新歌推荐', cs),
                    ],
                  ),
                ),
                const SizedBox(height: 48),
                // 登录按钮
                FilledButton.icon(
                  onPressed: widget.onLoginPressed,
                  icon: const Icon(Icons.login_rounded),
                  label: const Text('立即登录'),
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
                    textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
  
  Widget _buildFeatureChip(BuildContext context, IconData icon, String label, ColorScheme cs) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest.withOpacity(0.5),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: cs.outline.withOpacity(0.2)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 18, color: cs.primary),
          const SizedBox(width: 8),
          Text(label, style: TextStyle(color: cs.onSurface, fontWeight: FontWeight.w500)),
        ],
      ),
    );
  }
  
  /// iOS Cupertino 风格登录提示
  Widget _buildCupertinoPrompt(BuildContext context) {
    final isDark = CupertinoTheme.brightnessOf(context) == Brightness.dark;
    
    return FadeTransition(
      opacity: _fadeAnimation,
      child: SlideTransition(
        position: _slideAnimation,
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // 动画图标区域
                TweenAnimationBuilder<double>(
                  tween: Tween(begin: 0.8, end: 1.0),
                  duration: const Duration(milliseconds: 1200),
                  curve: Curves.elasticOut,
                  builder: (context, value, child) {
                    return Transform.scale(scale: value, child: child);
                  },
                  child: Container(
                    width: 140,
                    height: 140,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [
                          CupertinoColors.systemBlue.withOpacity(0.15),
                          CupertinoColors.systemIndigo.withOpacity(0.1),
                        ],
                      ),
                      shape: BoxShape.circle,
                    ),
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        // 外圈装饰
                        Container(
                          width: 120,
                          height: 120,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: CupertinoColors.systemBlue.withOpacity(0.3),
                              width: 2,
                            ),
                          ),
                        ),
                        // 音符图标
                        Icon(
                          CupertinoIcons.music_note_2,
                          size: 60,
                          color: CupertinoColors.systemBlue,
                        ),
                        // 锁图标叠加
                        Positioned(
                          right: 25,
                          bottom: 25,
                          child: Container(
                            padding: const EdgeInsets.all(6),
                            decoration: BoxDecoration(
                              color: isDark ? const Color(0xFF2C2C2E) : CupertinoColors.white,
                              shape: BoxShape.circle,
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withOpacity(0.1),
                                  blurRadius: 8,
                                ),
                              ],
                            ),
                            child: Icon(
                              CupertinoIcons.lock,
                              size: 18,
                              color: CupertinoColors.systemGrey,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 40),
                // 标题
                Text(
                  '登录后查看更多内容',
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    color: isDark ? CupertinoColors.white : CupertinoColors.black,
                    letterSpacing: -0.5,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 16),
                // 副标题
                Container(
                  constraints: const BoxConstraints(maxWidth: 300),
                  child: Text(
                    '登录即可获取每日推荐、私人FM、专属歌单等个性化内容',
                    style: TextStyle(
                      fontSize: 16,
                      color: CupertinoColors.systemGrey,
                      height: 1.5,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
                const SizedBox(height: 32),
                // 功能亮点
                Container(
                  constraints: const BoxConstraints(maxWidth: 340),
                  child: Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    alignment: WrapAlignment.center,
                    children: [
                      _buildCupertinoFeatureChip(CupertinoIcons.calendar, '每日推荐', isDark),
                      _buildCupertinoFeatureChip(CupertinoIcons.radiowaves_right, '私人FM', isDark),
                      _buildCupertinoFeatureChip(CupertinoIcons.music_albums, '专属歌单', isDark),
                      _buildCupertinoFeatureChip(CupertinoIcons.sparkles, '新歌推荐', isDark),
                    ],
                  ),
                ),
                const SizedBox(height: 48),
                // 登录按钮
                CupertinoButton.filled(
                  onPressed: widget.onLoginPressed,
                  borderRadius: BorderRadius.circular(12),
                  child: const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 16),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(CupertinoIcons.arrow_right_circle_fill, size: 20),
                        SizedBox(width: 8),
                        Text('立即登录', style: TextStyle(fontWeight: FontWeight.w600)),
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
  
  Widget _buildCupertinoFeatureChip(IconData icon, String label, bool isDark) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF2C2C2E) : CupertinoColors.systemGrey6,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: CupertinoColors.systemBlue),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              fontSize: 14,
              color: isDark ? CupertinoColors.white : CupertinoColors.black,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
  
  /// Fluent UI 风格登录提示
  Widget _buildFluentPrompt(BuildContext context) {
    final theme = fluent.FluentTheme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    
    return FadeTransition(
      opacity: _fadeAnimation,
      child: SlideTransition(
        position: _slideAnimation,
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(40),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // 动画图标区域
                TweenAnimationBuilder<double>(
                  tween: Tween(begin: 0.8, end: 1.0),
                  duration: const Duration(milliseconds: 1200),
                  curve: Curves.elasticOut,
                  builder: (context, value, child) {
                    return Transform.scale(scale: value, child: child);
                  },
                  child: Container(
                    width: 140,
                    height: 140,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [
                          theme.accentColor.withOpacity(0.15),
                          theme.accentColor.withOpacity(0.05),
                        ],
                      ),
                      shape: BoxShape.circle,
                    ),
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        // 外圈装饰
                        Container(
                          width: 120,
                          height: 120,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: theme.accentColor.withOpacity(0.3),
                              width: 2,
                            ),
                          ),
                        ),
                        // 音符图标
                        Icon(
                          fluent.FluentIcons.music_in_collection_fill,
                          size: 56,
                          color: theme.accentColor,
                        ),
                        // 锁图标叠加
                        Positioned(
                          right: 25,
                          bottom: 25,
                          child: Container(
                            padding: const EdgeInsets.all(6),
                            decoration: BoxDecoration(
                              color: theme.resources.controlAltFillColorSecondary,
                              shape: BoxShape.circle,
                            ),
                            child: Icon(
                              fluent.FluentIcons.lock,
                              size: 16,
                              color: theme.resources.textFillColorSecondary,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 40),
                // 标题
                Text(
                  '登录后查看更多内容',
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    color: theme.resources.textFillColorPrimary,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 16),
                // 副标题
                Container(
                  constraints: const BoxConstraints(maxWidth: 320),
                  child: Text(
                    '登录即可获取每日推荐、私人FM、专属歌单等个性化内容',
                    style: TextStyle(
                      fontSize: 14,
                      color: theme.resources.textFillColorSecondary,
                      height: 1.6,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
                const SizedBox(height: 32),
                // 功能亮点
                Container(
                  constraints: const BoxConstraints(maxWidth: 400),
                  child: Wrap(
                    spacing: 12,
                    runSpacing: 12,
                    alignment: WrapAlignment.center,
                    children: [
                      _buildFluentFeatureChip(fluent.FluentIcons.calendar, '每日推荐', theme),
                      _buildFluentFeatureChip(fluent.FluentIcons.streaming, '私人FM', theme),
                      _buildFluentFeatureChip(fluent.FluentIcons.music_in_collection, '专属歌单', theme),
                      _buildFluentFeatureChip(fluent.FluentIcons.music_note, '新歌推荐', theme),
                    ],
                  ),
                ),
                const SizedBox(height: 48),
                // 登录按钮 - 桌面端直接弹出登录对话框
                fluent.FilledButton(
                  onPressed: () async {
                    final result = await showFluentLoginDialog(context);
                    if (result == true && mounted) {
                      // 登录成功后刷新页面
                      widget.onLoginPressed();
                    }
                  },
                  style: fluent.ButtonStyle(
                    padding: WidgetStatePropertyAll(
                      const EdgeInsets.symmetric(horizontal: 32, vertical: 12),
                    ),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(fluent.FluentIcons.signin, size: 16),
                      SizedBox(width: 8),
                      Text('立即登录', style: TextStyle(fontWeight: FontWeight.w600)),
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
  
  Widget _buildFluentFeatureChip(IconData icon, String label, fluent.FluentThemeData theme) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: theme.resources.controlAltFillColorSecondary,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: theme.resources.controlStrokeColorDefault),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: theme.accentColor),
          const SizedBox(width: 8),
          Text(
            label,
            style: TextStyle(
              color: theme.resources.textFillColorPrimary,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}
