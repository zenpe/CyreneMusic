import 'dart:async';
import 'dart:io';
import 'dart:ui';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:bitsdojo_window/bitsdojo_window.dart';
import 'package:fluent_ui/fluent_ui.dart' as fluent;
import 'package:flutter/material.dart';
import '../services/music_service.dart';
import '../services/player_service.dart';
import '../services/version_service.dart';
import '../services/auth_service.dart';
import '../services/home_search_service.dart';
import '../models/toplist.dart';
import '../models/track.dart';
import '../models/version_info.dart';
import '../widgets/toplist_card.dart';
import '../widgets/track_list_tile.dart';
import '../widgets/search_widget.dart';
import '../utils/page_visibility_notifier.dart';
import '../utils/theme_manager.dart';
import '../pages/auth/auth_page.dart';
import '../services/play_history_service.dart';
import '../services/playlist_service.dart';
import '../models/playlist.dart';
import 'dart:math';
import 'dart:convert';
import 'package:http/http.dart' as http;
import '../services/url_service.dart';
import '../services/netease_login_service.dart';
import '../services/auto_update_service.dart';
import 'home_for_you_tab.dart';
import 'discover_playlist_detail_page.dart';
import 'home_page/daily_recommend_detail_page.dart';
import 'home_page/home_breadcrumbs.dart';
import 'home_page/home_overlay_controller.dart';
import 'home_page/home_widgets.dart';
import 'home_page/toplist_detail.dart';

/// 首页 - 展示音乐和视频内容
class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage>
    with AutomaticKeepAliveClientMixin, WidgetsBindingObserver {
  static const String _homeFontFamily = 'Microsoft YaHei';
  final PageController _bannerController = PageController();
  int _currentBannerIndex = 0;
  Timer? _bannerTimer;
  List<Track> _cachedRandomTracks = []; // 缓存随机歌曲列表
  bool _isPageVisible = true; // 页面是否可见
  bool _showSearch = false; // 是否显示搜索界面
  Future<List<Track>>? _guessYouLikeFuture; // 缓存猜你喜欢的结果
  bool _isNeteaseBound = false; // 是否已绑定网易云
  int _homeTabIndex = 1; // 0: 为你推荐, 1: 推荐（默认显示推荐）
  bool _showDiscoverDetail = false; // 是否显示歌单详情覆盖层
  int? _discoverPlaylistId; // 当前展示的歌单ID
  bool _showDailyDetail = false; // 是否显示每日推荐覆盖层
  List<Map<String, dynamic>> _dailyTracks = const [];
  final HomeOverlayController _homeOverlayController = HomeOverlayController();
  final HomeSearchService _homeSearchService = HomeSearchService();
  final ThemeManager _themeManager = ThemeManager();
  String? _initialSearchKeyword;
  int _lastHandledSearchRequestId = 0;

  @override
  bool get wantKeepAlive => true; // 保持页面状态

  @override
  void initState() {
    super.initState();

    // 添加应用生命周期监听
    WidgetsBinding.instance.addObserver(this);

    // 监听音乐服务变化
    MusicService().addListener(_onMusicServiceChanged);

    // 监听页面可见性变化
    PageVisibilityNotifier().addListener(_onPageVisibilityChanged);

    // 监听播放历史变化
    PlayHistoryService().addListener(_onHistoryChanged);

    // 监听登录状态变化
    AuthService().addListener(_onAuthChanged);

    // 如果还没有数据，自动获取
    if (MusicService().toplists.isEmpty && !MusicService().isLoading) {
      print('🏠 [HomePage] 首次加载，获取榜单数据...');
      MusicService().fetchToplists();
    } else {
      // 如果已有数据，初始化缓存并启动定时器
      _updateCachedTracksAndStartTimer();
    }

    // 首次加载“猜你喜欢”
    _prepareGuessYouLikeFuture();

    // 首次加载第三方绑定状态
    _loadBindings();

    // 监听来自主布局的搜索请求
    _homeSearchService.addListener(_onExternalSearchRequested);
    final pendingRequest = _homeSearchService.latestRequest;
    if (pendingRequest != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _handleExternalSearchRequest(pendingRequest);
      });
    }

    // 🔍 首次进入时检查更新
    _checkForUpdateOnce();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _syncGlobalBackHandler();
      }
    });
  }

  void _onAuthChanged() {
    if (mounted) {
      setState(() {
        // 登录状态变化时，重新加载“猜你喜欢”
        _prepareGuessYouLikeFuture();
      });
      // 登录状态变化时，刷新绑定状态
      _loadBindings();
    }
  }

  void _onHistoryChanged() {
    if (mounted) {
      setState(() {});
    }
  }

  /// 加载第三方绑定状态（仅在登录后查询）
  Future<void> _loadBindings() async {
    try {
      if (!AuthService().isLoggedIn) {
        if (mounted) {
          setState(() {
            _isNeteaseBound = false;
            _homeTabIndex = 1; // 回到“推荐”
          });
        }
        return;
      }
      final resp = await NeteaseLoginService().fetchBindings();
      final data = resp['data'] as Map<String, dynamic>?;
      final netease = data != null
          ? data['netease'] as Map<String, dynamic>?
          : null;
      final bound = (netease != null) && (netease['bound'] == true);
      if (mounted) {
        setState(() {
          _isNeteaseBound = bound;
          // 根据绑定状态设置默认首页 Tab：已绑定 -> 为你推荐，未绑定 -> 推荐
          _homeTabIndex = bound ? 0 : 1;
        });
      }
    } catch (e) {
      // 失败时不影响首页显示
      if (mounted) {
        setState(() {
          _isNeteaseBound = false;
          _homeTabIndex = 1;
        });
      }
    }
  }

  void _onPlaylistChanged() {
    if (mounted) {
      setState(() {});
    }
  }

  void _onPageVisibilityChanged() {
    final isVisible = PageVisibilityNotifier().isHomePage;

    if (isVisible && _isPageVisible == false) {
      // 从隐藏变为可见
      print('🏠 [HomePage] 页面重新显示，刷新轮播图...');
      _isPageVisible = true;
      _refreshBannerTracks();
    } else if (!isVisible && _isPageVisible == true) {
      // 从可见变为隐藏
      print('🏠 [HomePage] 页面隐藏，停止轮播图...');
      _isPageVisible = false;
      _stopBannerTimer();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);

    if (state == AppLifecycleState.resumed && _isPageVisible) {
      // 应用恢复到前台且页面可见时，刷新轮播图
      print('🏠 [HomePage] 应用恢复，刷新轮播图...');
      _refreshBannerTracks();
    } else if (state == AppLifecycleState.paused) {
      // 应用进入后台时，停止定时器
      _stopBannerTimer();
    }
  }

  @override
  void dispose() {
    _bannerTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    MusicService().removeListener(_onMusicServiceChanged);
    PageVisibilityNotifier().removeListener(_onPageVisibilityChanged);
    PlayHistoryService().removeListener(_onHistoryChanged);
    AuthService().removeListener(_onAuthChanged);
    _homeSearchService.removeListener(_onExternalSearchRequested);
    _bannerController.dispose();
    _homeOverlayController.setBackHandler(null);
    super.dispose();
  }

  void _onMusicServiceChanged() {
    if (mounted) {
      setState(() {
        // 数据变化时更新缓存并重启定时器
        _updateCachedTracksAndStartTimer();
      });
    }
  }

  /// 更新缓存的随机歌曲列表并启动定时器
  void _updateCachedTracksAndStartTimer() {
    _cachedRandomTracks = MusicService().getRandomTracks(5);

    // 在下一帧启动定时器，确保 UI 已渲染完成
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _startBannerTimer();
    });
  }

  /// 刷新轮播图歌曲
  void _refreshBannerTracks() {
    print('🏠 [HomePage] 刷新轮播图歌曲...');
    if (mounted) {
      setState(() {
        // 重置当前索引
        _currentBannerIndex = 0;
        // 更新随机歌曲
        _updateCachedTracksAndStartTimer();
        // 跳转到第一页
        if (_bannerController.hasClients) {
          _bannerController.jumpToPage(0);
        }
      });
    }
  }

  /// 启动轮播图自动切换定时器
  void _startBannerTimer() {
    _bannerTimer?.cancel();

    // 只有当有轮播图内容时才启动定时器
    if (_cachedRandomTracks.length > 1) {
      print('🎵 [HomePage] 启动轮播图定时器，共 ${_cachedRandomTracks.length} 张');

      _bannerTimer = Timer.periodic(const Duration(seconds: 5), (timer) {
        if (mounted && _bannerController.hasClients) {
          // 计算下一页索引
          final nextPage =
              (_currentBannerIndex + 1) % _cachedRandomTracks.length;

          print('🎵 [HomePage] 自动切换轮播图：$_currentBannerIndex -> $nextPage');

          // 平滑切换到下一页
          _bannerController.animateToPage(
            nextPage,
            duration: const Duration(milliseconds: 500),
            curve: Curves.easeInOut,
          );
        }
      });
    } else {
      print('🎵 [HomePage] 轮播图数量不足，不启动定时器');
    }
  }

  /// 停止轮播图定时器
  void _stopBannerTimer() {
    _bannerTimer?.cancel();
    print('🎵 [HomePage] 停止轮播图定时器');
  }

  /// 重启轮播图定时器
  void _restartBannerTimer() {
    print('🎵 [HomePage] 重启轮播图定时器');
    _stopBannerTimer();
    _startBannerTimer();
  }

  /// 每次进入首页时检查更新
  Future<void> _checkForUpdateOnce() async {
    try {
      // 延迟2秒后检查，避免影响首页加载
      await Future.delayed(const Duration(seconds: 2));

      if (!mounted) return;

      print('🔍 [HomePage] 开始检查更新...');

      final versionInfo = await VersionService().checkForUpdate(silent: true);

      if (!mounted) return;

      // 如果有更新，检查是否应该提示
      if (versionInfo != null && VersionService().hasUpdate) {
        final autoUpdateService = AutoUpdateService();
        final isAutoHandled =
            autoUpdateService.isEnabled &&
            autoUpdateService.isPlatformSupported &&
            !versionInfo.forceUpdate;

        if (isAutoHandled) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Row(
                  children: [
                    const Icon(Icons.system_update_alt, color: Colors.white),
                    const SizedBox(width: 12),
                    const Expanded(child: Text('检测到新版本，已在后台自动更新')),
                  ],
                ),
                duration: const Duration(seconds: 3),
              ),
            );
          }
          return;
        }

        // 检查用户是否已忽略此版本
        final shouldShow = await VersionService().shouldShowUpdateDialog(
          versionInfo,
        );

        // 检查本次会话是否已提醒过（稍后提醒）
        final hasReminded = VersionService().hasRemindedInSession(
          versionInfo.version,
        );

        if (shouldShow && !hasReminded) {
          _showUpdateDialog(versionInfo);
        } else {
          if (hasReminded) {
            print('⏰ [HomePage] 用户选择了稍后提醒，本次会话不再提示');
          } else {
            print('🔕 [HomePage] 用户已忽略此版本，不再提示');
          }
        }
      }
    } catch (e) {
      print('❌ [HomePage] 检查更新失败: $e');
    }
  }

  /// 显示更新提示对话框
  void _showUpdateDialog(VersionInfo versionInfo) {
    if (!mounted) return;

    showDialog(
      context: context,
      barrierDismissible: !versionInfo.forceUpdate, // 强制更新时不能关闭对话框
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            const Icon(Icons.system_update, color: Colors.blue),
            const SizedBox(width: 8),
            const Text('发现新版本'),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 版本信息
              Text(
                '最新版本: ${versionInfo.version}',
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
              Text(
                '当前版本: ${VersionService().currentVersion}',
                style: TextStyle(fontSize: 14, color: Colors.grey[600]),
              ),
              const SizedBox(height: 16),

              // 更新日志
              const Text(
                '更新内容：',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              Text(versionInfo.changelog, style: const TextStyle(fontSize: 14)),

              // 强制更新提示
              if (versionInfo.forceUpdate) ...[
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.orange.shade50,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.orange.shade200),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.warning,
                        color: Colors.orange.shade700,
                        size: 20,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          '此版本为强制更新，请立即更新',
                          style: TextStyle(
                            fontSize: 13,
                            color: Colors.orange.shade900,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
        actions: [
          // 稍后提醒（仅非强制更新时显示，本次会话不再提醒）
          if (!versionInfo.forceUpdate)
            TextButton(
              onPressed: () {
                // 标记本次会话已提醒，不保存到持久化存储
                VersionService().markVersionReminded(versionInfo.version);
                if (mounted) {
                  Navigator.of(context).pop();
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('本次启动将不再提醒，下次启动时会再次提示'),
                      duration: Duration(seconds: 2),
                    ),
                  );
                }
              },
              child: const Text('稍后提醒'),
            ),

          // 忽略此版本（仅非强制更新时显示，永久忽略）
          if (!versionInfo.forceUpdate)
            TextButton(
              onPressed: () async {
                // 永久保存用户忽略的版本号
                await VersionService().ignoreCurrentVersion(
                  versionInfo.version,
                );
                if (mounted) {
                  Navigator.of(context).pop();
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('已忽略版本 ${versionInfo.version}，有新版本时将再次提醒'),
                      duration: const Duration(seconds: 2),
                    ),
                  );
                }
              },
              child: const Text('忽略此版本'),
            ),

          // 立即更新
          ElevatedButton(
            onPressed: () {
              Navigator.of(context).pop();
              _openDownloadUrl(versionInfo.downloadUrl);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.blue,
              foregroundColor: Colors.white,
            ),
            child: const Text('立即更新'),
          ),
        ],
      ),
    );
  }

  /// 打开下载链接
  Future<void> _openDownloadUrl(String url) async {
    try {
      final uri = Uri.parse(url);
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      } else {
        if (mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(const SnackBar(content: Text('无法打开下载链接')));
        }
      }
    } catch (e) {
      print('❌ [HomePage] 打开下载链接失败: $e');
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('打开链接失败: $e')));
      }
    }
  }

  /// 检查登录状态，如果未登录则跳转到登录页面
  /// 返回 true 表示已登录或登录成功，返回 false 表示未登录或取消登录
  Future<bool> _checkLoginStatus() async {
    if (AuthService().isLoggedIn) {
      return true;
    }

    // 显示提示并询问是否要登录
    final shouldLogin = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.lock_outline, color: Colors.orange),
            SizedBox(width: 8),
            Text('需要登录'),
          ],
        ),
        content: const Text('此功能需要登录后才能使用，是否前往登录？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('去登录'),
          ),
        ],
      ),
    );

    if (shouldLogin == true && mounted) {
      // 跳转到登录页面
      final result = await showAuthDialog(context);

      // 返回登录是否成功
      return result == true && AuthService().isLoggedIn;
    }

    return false;
  }

  @override
  Widget build(BuildContext context) {
    super.build(context); // 必须调用以支持 AutomaticKeepAliveClientMixin
    final theme = Theme.of(context);
    final bool showTabs = _isNeteaseBound; // 绑定网易云后显示 Tabs

    if (_themeManager.isFluentFramework) {
      return Theme(
        data: _materialHomeThemeWithFont(theme),
        child: Builder(
          builder: (context) {
            final fluentColorScheme = Theme.of(context).colorScheme;
            return _buildFluentHome(context, fluentColorScheme, showTabs);
          },
        ),
      );
    }

    return Theme(
      data: _materialHomeThemeWithFont(theme),
      child: Builder(
        builder: (context) {
          final materialColorScheme = Theme.of(context).colorScheme;
          return _buildMaterialHome(context, materialColorScheme, showTabs);
        },
      ),
    );
  }

  Widget _buildMaterialHome(
    BuildContext context,
    ColorScheme colorScheme,
    bool showTabs,
  ) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: _buildSlidingSwitcher(
        _buildMaterialContentArea(context, colorScheme, showTabs),
      ),
    );
  }

  Future<void> _handleSearchPressed(BuildContext context) async {
    final isLoggedIn = await _checkLoginStatus();
    if (isLoggedIn && mounted) {
      setState(() {
        _showSearch = true;
        _initialSearchKeyword = null;
      });
      _syncGlobalBackHandler();
    }
  }

  void _handleRefreshPressed(BuildContext context) {
    MusicService().refreshToplists();
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('正在刷新榜单...')));
  }

  void _onExternalSearchRequested() {
    final request = _homeSearchService.latestRequest;
    if (request == null || !mounted) {
      return;
    }
    _handleExternalSearchRequest(request);
  }

  void _handleExternalSearchRequest(HomeSearchRequest request) {
    if (request.id == _lastHandledSearchRequestId) {
      return;
    }
    _lastHandledSearchRequestId = request.id;
    _openSearchFromExternal(request.keyword);
  }

  void _openSearchFromExternal(String? keyword) {
    if (!mounted) return;
    final normalizedKeyword = keyword?.trim();
    setState(() {
      _initialSearchKeyword =
          (normalizedKeyword == null || normalizedKeyword.isEmpty)
          ? null
          : normalizedKeyword;
      _showSearch = true;
    });
    _syncGlobalBackHandler();
  }

  Widget _buildFluentHome(
    BuildContext context,
    ColorScheme colorScheme,
    bool showTabs,
  ) {
    final breadcrumbs = _buildBreadcrumbItems(showTabs);

    return Scaffold(
      backgroundColor: colorScheme.surface,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(
                  child: FluentHomeBreadcrumbs(
                    items: breadcrumbs,
                    padding: EdgeInsets.zero,
                  ),
                ),
                const SizedBox(width: 12),
                _buildFluentActionButtons(context),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: Stack(
              children: [
                Positioned.fill(
                  child: _buildSlidingSwitcher(
                    _buildFluentContentArea(context, colorScheme, showTabs),
                  ),
                ),
                if (_showSearch)
                  Positioned.fill(
                    child: SearchWidget(
                      key: ValueKey(
                        'fluent_search_${_initialSearchKeyword ?? ''}',
                      ),
                      onClose: () {
                        if (!mounted) return;
                        setState(() {
                          _showSearch = false;
                          _initialSearchKeyword = null;
                        });
                        _syncGlobalBackHandler();
                      },
                      initialKeyword: _initialSearchKeyword,
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMaterialContentArea(
    BuildContext context,
    ColorScheme colorScheme,
    bool showTabs,
  ) {
    if (_showSearch) {
      return SearchWidget(
        key: ValueKey('material_search_${_initialSearchKeyword ?? ''}'),
        onClose: () {
          if (!mounted) return;
          setState(() {
            _showSearch = false;
            _initialSearchKeyword = null;
          });
          _syncGlobalBackHandler();
        },
        initialKeyword: _initialSearchKeyword,
      );
    }

    if (_showDailyDetail) {
      return Material(
        key: const ValueKey('material_daily_detail'),
        color: Colors.transparent,
        child: SafeArea(
          child: DailyRecommendDetailPage(
            tracks: _dailyTracks,
            embedded: true,
            onClose: _closeDailyDetail,
          ),
        ),
      );
    }

    if (_showDiscoverDetail && _discoverPlaylistId != null) {
      return Material(
        key: ValueKey('material_playlist_${_discoverPlaylistId!}'),
        color: Colors.transparent,
        child: SafeArea(
          child: Column(
            children: [
              Align(
                alignment: Alignment.centerLeft,
                child: IconButton(
                  icon: const Icon(Icons.arrow_back_rounded),
                  onPressed: _closeDiscoverDetail,
                  tooltip: '返回',
                ),
              ),
              Expanded(
                child: PrimaryScrollController.none(
                  child: DiscoverPlaylistDetailContent(
                    playlistId: _discoverPlaylistId!,
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }

    return CustomScrollView(
      key: const ValueKey('material_home_overview'),
      slivers: _buildHomeSlivers(
        context: context,
        colorScheme: colorScheme,
        showTabs: showTabs,
        includeAppBar: true,
      ),
    );
  }

  Widget _buildSlidingSwitcher(Widget child) {
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 280),
      switchInCurve: Curves.easeOutCubic,
      switchOutCurve: Curves.easeInCubic,
      transitionBuilder: (child, animation) =>
          _buildSlideTransition(child, animation),
      layoutBuilder: (currentChild, previousChildren) {
        return Stack(
          children: [
            ...previousChildren,
            if (currentChild != null) currentChild,
          ],
        );
      },
      child: child,
    );
  }

  Widget _buildSlideTransition(Widget child, Animation<double> animation) {
    final isReverse = animation is ReverseAnimation;
    final beginOffset = isReverse
        ? const Offset(-1.0, 0.0)
        : const Offset(1.0, 0.0);
    final curvedAnimation = CurvedAnimation(
      parent: animation,
      curve: Curves.easeOutCubic,
      reverseCurve: Curves.easeInCubic,
    );
    final positionAnimation = Tween<Offset>(
      begin: beginOffset,
      end: Offset.zero,
    ).animate(curvedAnimation);

    return SlideTransition(
      position: positionAnimation,
      child: FadeTransition(opacity: curvedAnimation, child: child),
    );
  }

  List<Widget> _buildHomeSlivers({
    required BuildContext context,
    required ColorScheme colorScheme,
    required bool showTabs,
    required bool includeAppBar,
  }) {
    final slivers = <Widget>[];

    if (includeAppBar) {
      slivers.add(_buildHomeSliverAppBar(context, colorScheme));
    }

    slivers.add(_buildHomeContentSliver(context, showTabs));

    return slivers;
  }

  SliverAppBar _buildHomeSliverAppBar(
    BuildContext context,
    ColorScheme colorScheme,
  ) {
    return SliverAppBar(
      floating: true,
      snap: true,
      backgroundColor: Colors.transparent,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0,
      title: Text(
        '首页',
        style: TextStyle(
          color: colorScheme.onSurface,
          fontSize: 24,
          fontWeight: FontWeight.bold,
        ),
      ),
      actions: [
        IconButton(
          icon: const Icon(Icons.search),
          tooltip: '搜索',
          onPressed: () => _handleSearchPressed(context),
        ),
        IconButton(
          icon: const Icon(Icons.refresh),
          tooltip: '刷新',
          onPressed: () => _handleRefreshPressed(context),
        ),
      ],
    );
  }

  Widget _buildHomeContentSliver(BuildContext context, bool showTabs) {
    return SliverPadding(
      padding: const EdgeInsets.all(24.0),
      sliver: SliverList(
        delegate: SliverChildListDelegate([
          if (showTabs) ...[
            Padding(
              padding: const EdgeInsets.only(bottom: 12.0),
              child: _HomeCapsuleTabs(
                tabs: const ['为你推荐', '榜单'],
                currentIndex: _homeTabIndex,
                onChanged: (i) => setState(() => _homeTabIndex = i),
              ),
            ),
            const SizedBox(height: 8),
          ],
          if (showTabs && _homeTabIndex == 0) ...[
            HomeForYouTab(
              onOpenPlaylistDetail: (id) {
                setState(() {
                  _homeTabIndex = 0;
                  _discoverPlaylistId = id;
                  _showDiscoverDetail = true;
                });
                _syncGlobalBackHandler();
              },
              onOpenDailyDetail: (tracks) {
                setState(() {
                  _homeTabIndex = 0;
                  _dailyTracks = tracks;
                  _showDailyDetail = true;
                });
                _syncGlobalBackHandler();
              },
            ),
          ] else ...[
            if (MusicService().isLoading)
              const LoadingSection()
            else if (MusicService().errorMessage != null)
              const ErrorSection()
            else if (MusicService().toplists.isEmpty)
              const EmptySection()
            else ...[
              BannerSection(
                cachedRandomTracks: _cachedRandomTracks,
                bannerController: _bannerController,
                currentBannerIndex: _currentBannerIndex,
                onPageChanged: (index) {
                  setState(() {
                    _currentBannerIndex = index;
                  });
                  print('🎵 [HomePage] 页面切换到: $index');
                  _restartBannerTimer();
                },
                checkLoginStatus: _checkLoginStatus,
              ),
              const SizedBox(height: 32),
              LayoutBuilder(
                builder: (context, constraints) {
                  final useVerticalLayout =
                      constraints.maxWidth < 600 || Platform.isAndroid;

                  if (useVerticalLayout) {
                    return Column(
                      children: [
                        const HistorySection(),
                        const SizedBox(height: 16),
                        GuessYouLikeSection(
                          guessYouLikeFuture: _guessYouLikeFuture,
                        ),
                      ],
                    );
                  } else {
                    return Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Expanded(child: HistorySection()),
                        const SizedBox(width: 24),
                        Expanded(
                          child: GuessYouLikeSection(
                            guessYouLikeFuture: _guessYouLikeFuture,
                          ),
                        ),
                      ],
                    );
                  }
                },
              ),
              const SizedBox(height: 32),
              ToplistsGrid(
                checkLoginStatus: _checkLoginStatus,
                showToplistDetail: (toplist) =>
                    showToplistDetail(context, toplist),
              ),
            ],
          ],
        ]),
      ),
    );
  }

  Widget _buildFluentContentArea(
    BuildContext context,
    ColorScheme colorScheme,
    bool showTabs,
  ) {
    if (_showDailyDetail) {
      return Container(
        key: const ValueKey('fluent_daily_detail'),
        color: colorScheme.surface,
        child: PrimaryScrollController.none(
          child: DailyRecommendDetailPage(
            tracks: _dailyTracks,
            embedded: true,
            showHeader: false,
            onClose: _closeDailyDetail,
          ),
        ),
      );
    }

    if (_showDiscoverDetail && _discoverPlaylistId != null) {
      return Container(
        key: ValueKey('fluent_playlist_${_discoverPlaylistId!}'),
        color: colorScheme.surface,
        child: PrimaryScrollController.none(
          child: DiscoverPlaylistDetailContent(
            playlistId: _discoverPlaylistId!,
          ),
        ),
      );
    }

    if (_showSearch) {
      return Container(
        key: ValueKey('fluent_search_${_initialSearchKeyword ?? ''}'),
        color: colorScheme.surface,
        child: SearchWidget(
          key: ValueKey('fluent_search_body_${_initialSearchKeyword ?? ''}'),
          onClose: () {
            if (!mounted) return;
            setState(() {
              _showSearch = false;
              _initialSearchKeyword = null;
            });
            _syncGlobalBackHandler();
          },
          initialKeyword: _initialSearchKeyword,
        ),
      );
    }

    return CustomScrollView(
      key: const ValueKey('fluent_home_overview'),
      slivers: _buildHomeSlivers(
        context: context,
        colorScheme: colorScheme,
        showTabs: showTabs,
        includeAppBar: false,
      ),
    );
  }

  Widget _buildFluentActionButtons(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        fluent.Tooltip(
          message: '搜索',
          child: fluent.IconButton(
            icon: const Icon(fluent.FluentIcons.search, size: 16),
            onPressed: () => _handleSearchPressed(context),
          ),
        ),
        const SizedBox(width: 4),
        fluent.Tooltip(
          message: '刷新',
          child: fluent.IconButton(
            icon: const Icon(fluent.FluentIcons.refresh, size: 16),
            onPressed: () => _handleRefreshPressed(context),
          ),
        ),
      ],
    );
  }

  List<HomeBreadcrumbItem> _buildBreadcrumbItems(bool showTabs) {
    final showingPlaylist = _showDiscoverDetail && _discoverPlaylistId != null;
    final showingDaily = _showDailyDetail;
    final showingDetail = showingPlaylist || showingDaily;

    final items = <HomeBreadcrumbItem>[
      HomeBreadcrumbItem(
        label: '首页',
        isEmphasized: true,
        isCurrent: !showingDetail && !_showSearch && !_showDailyDetail,
        onTap: showingDetail || _showSearch
            ? () => _switchToHomeTab(_homeTabIndex)
            : null,
      ),
    ];

    if (_showSearch) {
      items.add(
        const HomeBreadcrumbItem(
          label: '搜索',
          isCurrent: true,
          isEmphasized: true,
        ),
      );
    } else if (showingDetail) {
      items.add(
        HomeBreadcrumbItem(
          label: showingDaily ? '每日推荐' : '歌单详情',
          isCurrent: true,
          isEmphasized: true,
        ),
      );
    }

    return items;
  }

  void _switchToHomeTab(int index) {
    if (!mounted) return;
    setState(() {
      _homeTabIndex = index;
      _showDiscoverDetail = false;
      _discoverPlaylistId = null;
      _showDailyDetail = false;
      _dailyTracks = const [];
    });
    _syncGlobalBackHandler();
  }

  void _closeDiscoverDetail() {
    if (!mounted) return;
    setState(() {
      _showDiscoverDetail = false;
      _discoverPlaylistId = null;
    });
    _syncGlobalBackHandler();
  }

  void _closeDailyDetail() {
    if (!mounted) return;
    setState(() {
      _showDailyDetail = false;
      _dailyTracks = const [];
    });
    _syncGlobalBackHandler();
  }

  /// 准备“猜你喜欢”的 Future
  void _prepareGuessYouLikeFuture() {
    if (AuthService().isLoggedIn) {
      _guessYouLikeFuture = _fetchRandomTracksFromPlaylists();
    } else {
      _guessYouLikeFuture = null;
    }
  }

  /// 从多个歌单中获取随机歌曲
  Future<List<Track>> _fetchRandomTracksFromPlaylists() async {
    final String baseUrl = UrlService().baseUrl;
    final String? token = AuthService().token;
    if (token == null) throw Exception('未登录');

    // 1. 获取所有歌单
    final playlistsResponse = await http.get(
      Uri.parse('$baseUrl/playlists'),
      headers: {'Authorization': 'Bearer $token'},
    );

    if (playlistsResponse.statusCode != 200) {
      throw Exception('获取歌单列表失败');
    }

    final playlistsBody = json.decode(utf8.decode(playlistsResponse.bodyBytes));
    if (playlistsBody['status'] != 200) {
      throw Exception(playlistsBody['message'] ?? '获取歌单列表失败');
    }

    final List<dynamic> playlistsJson = playlistsBody['playlists'] ?? [];
    final List<Playlist> allPlaylists = playlistsJson
        .map((p) => Playlist.fromJson(p))
        .toList();

    // 2. 筛选非空歌单
    final nonEmptyPlaylists = allPlaylists
        .where((p) => p.trackCount > 0)
        .toList();
    if (nonEmptyPlaylists.isEmpty) {
      throw Exception('没有包含歌曲的歌单');
    }

    // 3. 随机选择一个歌单并获取其歌曲
    final randomPlaylist =
        nonEmptyPlaylists[Random().nextInt(nonEmptyPlaylists.length)];
    final tracksResponse = await http.get(
      Uri.parse('$baseUrl/playlists/${randomPlaylist.id}/tracks'),
      headers: {'Authorization': 'Bearer $token'},
    );

    if (tracksResponse.statusCode != 200) {
      throw Exception('获取歌曲失败');
    }

    final tracksBody = json.decode(utf8.decode(tracksResponse.bodyBytes));
    if (tracksBody['status'] != 200) {
      throw Exception(tracksBody['message'] ?? '获取歌曲失败');
    }

    final List<dynamic> tracksJson = tracksBody['tracks'] ?? [];
    final List<PlaylistTrack> tracks = tracksJson
        .map((t) => PlaylistTrack.fromJson(t))
        .toList();

    // 4. 随机挑选3首
    tracks.shuffle();
    return tracks.take(3).map((t) => t.toTrack()).toList();
  }

  /// 加载歌单中的一小部分歌曲用于展示
  Future<List<PlaylistTrack>> _loadPlaylistTracksSample(int playlistId) async {
    // 这里我们直接调用 PlaylistService 的方法，但理想情况下可以做一个缓存或优化
    // 为了简单起见，我们直接加载
    await PlaylistService().loadPlaylistTracks(playlistId);
    return PlaylistService().currentTracks;
  }

  void _syncGlobalBackHandler() {
    if (!mounted) {
      _homeOverlayController.setBackHandler(null);
      return;
    }

    if (_showSearch) {
      _homeOverlayController.setBackHandler(() {
        if (!mounted) return;
        setState(() {
          _showSearch = false;
          _initialSearchKeyword = null;
        });
        _syncGlobalBackHandler();
      });
      return;
    }

    if (_showDailyDetail) {
      _homeOverlayController.setBackHandler(() {
        _closeDailyDetail();
      });
      return;
    }

    if (_showDiscoverDetail && _discoverPlaylistId != null) {
      _homeOverlayController.setBackHandler(() {
        _closeDiscoverDetail();
      });
      return;
    }

    _homeOverlayController.setBackHandler(null);
  }

  ThemeData _materialHomeThemeWithFont(ThemeData base) {
    final textTheme = base.textTheme.apply(fontFamily: _homeFontFamily);
    final primaryTextTheme = base.primaryTextTheme.apply(
      fontFamily: _homeFontFamily,
    );
    final appBarTheme = base.appBarTheme.copyWith(
      titleTextStyle: (base.appBarTheme.titleTextStyle ?? textTheme.titleLarge)
          ?.copyWith(fontFamily: _homeFontFamily),
      toolbarTextStyle:
          (base.appBarTheme.toolbarTextStyle ?? textTheme.titleMedium)
              ?.copyWith(fontFamily: _homeFontFamily),
    );

    return base.copyWith(
      textTheme: textTheme,
      primaryTextTheme: primaryTextTheme,
      appBarTheme: appBarTheme,
    );
  }
}

/// 首页顶部胶囊 Tabs（参考歌手详情页样式）
class _HomeCapsuleTabs extends StatelessWidget {
  final List<String> tabs;
  final int currentIndex;
  final ValueChanged<int> onChanged;
  const _HomeCapsuleTabs({
    required this.tabs,
    required this.currentIndex,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final bg = cs.surfaceContainerHighest;
    final pillColor = cs.primary;
    final selFg = cs.onPrimary;
    final unSelFg = cs.onSurfaceVariant;

    return LayoutBuilder(
      builder: (context, constraints) {
        final height = 48.0;
        final padding = 5.0;
        final radius = height / 2;
        final totalWidth = constraints.maxWidth;
        final count = tabs.length;
        final tabWidth = totalWidth / count;

        return SizedBox(
          height: height,
          child: Stack(
            children: [
              // 背景容器
              Positioned.fill(
                child: Container(
                  decoration: BoxDecoration(
                    color: bg,
                    borderRadius: BorderRadius.circular(radius),
                  ),
                ),
              ),
              // 滑动胶囊指示器
              AnimatedPositioned(
                duration: const Duration(milliseconds: 280),
                curve: Curves.easeInOutCubic,
                top: padding,
                bottom: padding,
                left: padding + currentIndex * (tabWidth - padding * 2),
                width: tabWidth - padding * 2,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 280),
                  curve: Curves.easeInOutCubic,
                  decoration: BoxDecoration(
                    color: pillColor,
                    borderRadius: BorderRadius.circular(radius - padding),
                    boxShadow: [
                      BoxShadow(
                        color: pillColor.withOpacity(0.25),
                        blurRadius: 10,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                ),
              ),
              // 标签点击与文字
              Row(
                children: List.generate(count, (i) {
                  final selected = i == currentIndex;
                  return SizedBox(
                    width: tabWidth,
                    height: height,
                    child: InkWell(
                      borderRadius: BorderRadius.circular(radius),
                      onTap: () => onChanged(i),
                      child: Center(
                        child: AnimatedDefaultTextStyle(
                          duration: const Duration(milliseconds: 180),
                          curve: Curves.easeInOut,
                          style: TextStyle(
                            color: selected ? selFg : unSelFg,
                            fontWeight: FontWeight.w600,
                          ),
                          child: Text(tabs[i]),
                        ),
                      ),
                    ),
                  );
                }),
              ),
            ],
          ),
        );
      },
    );
  }
}
