import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import '../services/netease_recommend_service.dart';
import 'home_page/for_you_data.dart';
import 'home_page/greeting_header.dart';
import 'home_page/hero_section.dart';
import 'home_page/bento_playlist_grid.dart';
import 'home_page/horizontal_playlist_carousel.dart';
import 'home_page/mixed_playlist_grid.dart';
import 'home_page/newsong_cards.dart';
import 'home_page/mobile_daily_recommend_card.dart';
import 'home_page/mobile_personal_fm.dart';
import 'home_page/mobile_playlist_grid.dart';
import 'home_page/mobile_newsong_list.dart';
import 'home_page/login_prompt.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/auth_service.dart';
import '../utils/theme_manager.dart';
import '../widgets/skeleton_loader.dart';
import '../widgets/audio_source_prompt.dart';
import '../services/audio_source_service.dart';
import 'settings_page/audio_source_settings.dart';

/// 首页 - 为你推荐 Tab 内容 (优化版)
class HomeForYouTab extends StatefulWidget {
  const HomeForYouTab({super.key, this.onOpenPlaylistDetail, this.onOpenDailyDetail});

  final void Function(int playlistId)? onOpenPlaylistDetail;
  final void Function(List<Map<String, dynamic>> tracks)? onOpenDailyDetail;

  @override
  State<HomeForYouTab> createState() => _HomeForYouTabState();
}

class _HomeForYouTabState extends State<HomeForYouTab> {
  late Future<ForYouData> _future;
  
  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<ForYouData> _load() async {
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
          final data = ForYouData.fromJsonString(jsonString);
          return data;
        } catch (_) {}
      }
    }

    final svc = NeteaseRecommendService();
    final combined = await svc.fetchForYouCombined(personalizedLimit: 12, newsongLimit: 10);
    final result = ForYouData(
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

  /// 导航到音源设置页面
  void _navigateToAudioSourceSettings(BuildContext context) {
    final themeManager = ThemeManager();
    
    if (themeManager.isFluentFramework) {
      // Fluent UI (Windows)：全屏打开音源设置页面
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (context) => const AudioSourceSettings(),
        ),
      );
    } else {
      // Material/Cupertino：全屏打开音源设置页面
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (context) => const AudioSourceSettings(),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final themeManager = ThemeManager();
    final isCupertino = (Platform.isIOS || Platform.isAndroid) && themeManager.isCupertinoFramework;
    final isMobile = Platform.isIOS || Platform.isAndroid;
    
    // 未登录状态下显示登录提示
    if (!AuthService().isLoggedIn) {
      return ForYouLoginPrompt(
        onLoginPressed: () {
          // ForYouLoginPrompt 内部已处理登录对话框，这里只需刷新状态
          if (mounted && AuthService().isLoggedIn) {
            setState(() {
              _future = _load();
            });
          }
        },
      );
    }
    
    // 已登录但音源未配置时，显示音源配置提示
    if (!AudioSourceService().isConfigured) {
      return AnimatedBuilder(
        animation: AudioSourceService(),
        builder: (context, _) {
          // 如果音源已配置，刷新数据
          if (AudioSourceService().isConfigured) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) {
                setState(() {
                  _future = _load();
                });
              }
            });
          }
          return AudioSourcePrompt(
            onConfigurePressed: () {
              // 桌面端：导航到设置页面的音源配置子页面
              // 这里通过回调触发上层页面的导航
              _navigateToAudioSourceSettings(context);
            },
          );
        },
      );
    }
    
    return FutureBuilder<ForYouData>(
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
              const GreetingHeader(),
              MobileDailyRecommendCard(
                tracks: data.dailySongs,
                onOpenDetail: () => widget.onOpenDailyDetail?.call(data.dailySongs),
              ),
              SizedBox(height: isCupertino ? 24 : 32),
              SectionTitle(title: '私人FM'),
              MobilePersonalFm(list: data.fm),
              SizedBox(height: isCupertino ? 24 : 32),
              SectionTitle(title: '每日推荐歌单'),
              MobilePlaylistGrid(
                list: data.dailyPlaylists,
                onTap: (id) => widget.onOpenPlaylistDetail?.call(id),
              ),
              SizedBox(height: isCupertino ? 24 : 32),
              SectionTitle(title: '专属歌单'),
              MobilePlaylistGrid(
                list: data.personalizedPlaylists,
                onTap: (id) => widget.onOpenPlaylistDetail?.call(id),
              ),
              SizedBox(height: isCupertino ? 24 : 32),
              SectionTitle(title: '雷达歌单'),
              MobilePlaylistGrid(
                list: data.radarPlaylists,
                onTap: (id) => widget.onOpenPlaylistDetail?.call(id),
              ),
              SizedBox(height: isCupertino ? 24 : 32),
              SectionTitle(title: '个性化新歌'),
              MobileNewsongList(list: data.personalizedNewsongs),
              const SizedBox(height: 16),
            ],
          );
        }
        
        // 桌面端使用新布局
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const GreetingHeader(),
            const SizedBox(height: 16),
            // Hero 双卡区域：每日推荐 + 私人FM
            HeroSection(
              dailySongs: data.dailySongs,
              fmList: data.fm,
              onOpenDailyDetail: () => widget.onOpenDailyDetail?.call(data.dailySongs),
            ),
            const SizedBox(height: 28),
            // 每日推荐歌单 - Bento 网格
            SectionTitle(title: '每日推荐歌单'),
            BentoPlaylistGrid(
              list: data.dailyPlaylists,
              onTap: (id) => widget.onOpenPlaylistDetail?.call(id),
            ),
            const SizedBox(height: 28),
            // 专属歌单 - 横向滚动大卡片
            SectionTitle(title: '专属歌单'),
            HorizontalPlaylistCarousel(
              list: data.personalizedPlaylists,
              onTap: (id) => widget.onOpenPlaylistDetail?.call(id),
            ),
            const SizedBox(height: 28),
            // 雷达歌单 - 混合尺寸网格
            SectionTitle(title: '雷达歌单'),
            MixedSizePlaylistGrid(
              list: data.radarPlaylists,
              onTap: (id) => widget.onOpenPlaylistDetail?.call(id),
            ),
            const SizedBox(height: 28),
            // 个性化新歌 - 卡片列表
            SectionTitle(title: '发现新歌'),
            NewsongCards(list: data.personalizedNewsongs),
            const SizedBox(height: 24),
          ],
        );
      },
    );
  }
}




















