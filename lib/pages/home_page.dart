import 'dart:async';
import 'dart:io';
import 'dart:ui';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:fluent_ui/fluent_ui.dart' as fluent;
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../features/auth/auth_feature.dart';
import '../services/announcement_service.dart';
import '../services/music_service.dart';
import '../services/version_service.dart';
import '../services/app_settings_service.dart';
import '../services/home_search_service.dart';
import '../widgets/announcement_dialog.dart';
import '../models/track.dart';
import '../models/version_info.dart';
import '../widgets/search_widget.dart';
import '../utils/page_visibility_notifier.dart';
import '../utils/theme_manager.dart';
import '../pages/auth/auth_page.dart';
import '../pages/auth/qr_login_scan_page.dart';
import '../services/play_history_service.dart';
import 'dart:math';
import 'package:flutter_acrylic/flutter_acrylic.dart';
import '../services/netease_login_service.dart';
import '../services/auto_update_service.dart';
import 'home_for_you_tab.dart';
import 'discover_playlist_detail_page.dart';
import 'home_page/daily_recommend_detail_page.dart';
import 'home_page/home_breadcrumbs.dart';
import 'home_page/home_overlay_controller.dart';
import '../services/global_back_handler_service.dart';
import 'home_page/toplist_detail.dart';
import 'home_page/charts_tab.dart';
import '../widgets/cupertino/cupertino_home_widgets.dart';
import '../widgets/skeleton_loader.dart';

/// 首页 - 展示音乐和视频内容
class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage>
    with AutomaticKeepAliveClientMixin, WidgetsBindingObserver {
  static const String _homeFontFamily = 'Microsoft YaHei';
  final AuthFacade _authFacade = AuthFacade();
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
  int _forYouReloadToken = 0;
  bool _reverseTransition = false; // 用于控制滑动动画方向
  bool _isBindingsLoading = false; // 是否正在加载绑定状态

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
    _authFacade.addAuthStateListener(_onAuthChanged);

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
    _isBindingsLoading = _authFacade.isLoggedIn;
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

    // 📢 首次进入时检查公告（优先级高于更新检查）
    _checkAnnouncementOnce();

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
      if (!_authFacade.isLoggedIn) {
        if (mounted) {
          setState(() {
            _isNeteaseBound = false;
            _isBindingsLoading = false;
            _homeTabIndex = 1; // 回到“推荐”
          });
        }
        return;
      }

      if (mounted) {
        setState(() {
          _isBindingsLoading = true;
        });
      }

      final resp = await NeteaseLoginService().fetchBindings();
      final data = resp['data'] as Map<String, dynamic>?;
      final netease =
          data != null ? data['netease'] as Map<String, dynamic>? : null;
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
    } finally {
      if (mounted) {
        setState(() {
          _isBindingsLoading = false;
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
    _authFacade.removeAuthStateListener(_onAuthChanged);
    _homeSearchService.removeListener(_onExternalSearchRequested);
    _bannerController.dispose();
    _homeOverlayController.setBackHandler(null);
    GlobalBackHandlerService().unregister('home_overlay');
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

  /// 每次进入首页时检查公告（优先级高于更新检查）
  Future<void> _checkAnnouncementOnce() async {
    try {
      // 延迟1秒后检查，优先级高于更新检查
      await Future.delayed(const Duration(seconds: 1));

      if (!mounted) return;

      print('📢 [HomePage] 开始检查公告...');

      final announcementService = AnnouncementService();

      // 添加详细的调试信息
      print('📢 [HomePage] 公告服务状态:');
      print('  - isInitialized: ${announcementService.isInitialized}');
      print('  - isLoading: ${announcementService.isLoading}');
      print('  - error: ${announcementService.error}');
      print('  - currentAnnouncement: ${announcementService.currentAnnouncement}');

      if (announcementService.currentAnnouncement != null) {
        final announcement = announcementService.currentAnnouncement!;
        print('  - announcement.enabled: ${announcement.enabled}');
        print('  - announcement.id: ${announcement.id}');
        print('  - announcement.title: ${announcement.title}');
      }

      // 如果服务还在加载中，等待加载完成
      if (announcementService.isLoading) {
        print('📢 [HomePage] 公告服务正在加载，等待完成...');
        // 最多等待5秒
        for (int i = 0; i < 50; i++) {
          await Future.delayed(const Duration(milliseconds: 100));
          if (!announcementService.isLoading) break;
        }
        print('📢 [HomePage] 等待完成，当前状态: isLoading=${announcementService.isLoading}');
      }

      // 检查是否应该显示公告
      final shouldShow = announcementService.shouldShowAnnouncement();
      print('📢 [HomePage] shouldShowAnnouncement() 返回: $shouldShow');

      if (shouldShow && announcementService.currentAnnouncement != null) {
        print('📢 [HomePage] 显示公告: ${announcementService.currentAnnouncement!.title}');

        await AnnouncementDialog.show(
          context,
          announcementService.currentAnnouncement!,
        );

        print('📢 [HomePage] 公告已关闭');
      } else {
        print('📢 [HomePage] 无需显示公告');
        if (announcementService.error != null) {
          print('📢 [HomePage] 错误信息: ${announcementService.error}');
        }
      }
    } catch (e, stackTrace) {
      print('❌ [HomePage] 检查公告失败: $e');
      print('❌ [HomePage] 堆栈: $stackTrace');
    }
  }

  /// 每次进入首页时检查更新
  Future<void> _checkForUpdateOnce() async {
    try {
      // 延迟2秒后检查，避免影响首页加载
      await Future.delayed(const Duration(seconds: 2));

      if (!mounted) return;

      final appSettings = AppSettingsService();
      await appSettings.ensureInitialized();
      final allowStartupUpdatePrompt = appSettings.showUpdatePromptOnStartup;

      // 如果更新提示已关闭且自动更新也未开启，跳过网络请求
      if (!allowStartupUpdatePrompt && !AutoUpdateService().isEnabled) {
        print('🔕 [HomePage] 更新提示与自动更新均已关闭，跳过版本检查');
        return;
      }

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

        if (!allowStartupUpdatePrompt) {
          print('🔕 [HomePage] 启动更新提示已关闭，跳过弹窗');
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

    // 根据当前主题模式显示不同的对话框
    if (_themeManager.isFluentFramework) {
      _showUpdateDialogFluent(versionInfo);
      return;
    }

    showDialog(
      context: context,
      barrierDismissible: !versionInfo.forceUpdate, // 强制更新时不能关闭对话框
      builder: (context) => PopScope(
        canPop: !versionInfo.forceUpdate,
        child: AlertDialog(
        title: Row(
          children: [
            Icon(
              versionInfo.fixing ? Icons.build : Icons.system_update,
              color: versionInfo.fixing ? Colors.orange : Colors.blue,
            ),
            const SizedBox(width: 8),
            Text(versionInfo.fixing ? '服务器正在维护' : '发现新版本'),
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
              if (versionInfo.forceUpdate && !versionInfo.fixing) ...[
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

              // 服务器维护提示
              if (versionInfo.fixing) ...[
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
                        Icons.build,
                        color: Colors.orange.shade700,
                        size: 20,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          '服务器正在维护中，请稍后再试',
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
          // 稍后提醒（仅非强制更新且非维护时显示，本次会话不再提醒）
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

          // 忽略此版本（仅非强制更新且非维护时显示，永久忽略）
          if (!versionInfo.forceUpdate && !versionInfo.fixing)
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

          // 立即更新/一键更新（维护时不显示）
          if (!versionInfo.fixing)
            ElevatedButton(
              onPressed: () async {
                Navigator.of(context).pop();
                final autoUpdateService = AutoUpdateService();
                if (autoUpdateService.isPlatformSupported) {
                  // 支持自动更新的平台，显示进度对话框
                  _showUpdateProgressDialog(versionInfo);
                  await autoUpdateService.startUpdate(
                    versionInfo: versionInfo,
                    autoTriggered: false,
                  );
                } else {
                  // 不支持自动更新的平台，打开下载链接
                  _openDownloadUrl(versionInfo.downloadUrl);
                }
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.blue,
                foregroundColor: Colors.white,
              ),
              child: Text(AutoUpdateService().isPlatformSupported ? '一键更新' : '立即更新'),
            ),
        ],
      ),
    ));
  }

  /// 显示更新提示对话框（Fluent UI 版本）
  void _showUpdateDialogFluent(VersionInfo versionInfo) {
    if (!mounted) return;

    final isForceUpdate = versionInfo.forceUpdate;
    final isFxing = versionInfo.fixing;
    final autoUpdateService = AutoUpdateService();
    final platformSupported = autoUpdateService.isPlatformSupported;

    fluent.showDialog(
      context: context,
      barrierDismissible: !isForceUpdate,
      builder: (context) => PopScope(
        canPop: !isForceUpdate,
        child: fluent.ContentDialog(
        title: Text(isFxing ? '服务器正在维护' : '发现新版本'),
        content: Column(
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
            const SizedBox(height: 4),
            Text(
              '当前版本: ${VersionService().currentVersion}',
              style: const TextStyle(fontSize: 14),
            ),
            const SizedBox(height: 16),

            // 更新日志
            const Text(
              '更新内容：',
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(
              versionInfo.changelog,
              style: const TextStyle(fontSize: 14),
            ),

            // 强制更新提示（非维护时显示）
            if (isForceUpdate && !isFxing) ...[
              const SizedBox(height: 16),
              fluent.InfoBar(
                title: const Text('强制更新'),
                content: const Text('此版本为强制更新，请立即更新'),
                severity: fluent.InfoBarSeverity.warning,
              ),
            ],

            // 服务器维护提示
            if (isFxing) ...[
              const SizedBox(height: 16),
              fluent.InfoBar(
                title: const Text('服务器维护'),
                content: const Text('服务器正在维护中，请稍后再试'),
                severity: fluent.InfoBarSeverity.warning,
              ),
            ],
          ],
        ),
        actions: [
          // 稍后提醒（仅非强制更新时显示）
          if (!isForceUpdate)
            fluent.Button(
              onPressed: () {
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

          // 忽略此版本（仅非强制更新且非维护时显示）
          if (!isForceUpdate && !isFxing)
            fluent.Button(
              onPressed: () async {
                await VersionService().ignoreCurrentVersion(versionInfo.version);
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

          // 立即更新/一键更新（维护时不显示）
          if (!isFxing)
            fluent.FilledButton(
              onPressed: () async {
                Navigator.of(context).pop();
                if (platformSupported) {
                  // 支持自动更新的平台，显示进度对话框
                  _showUpdateProgressDialogFluent(versionInfo);
                  await autoUpdateService.startUpdate(
                    versionInfo: versionInfo,
                    autoTriggered: false,
                  );
                } else {
                  // 不支持自动更新的平台，打开下载链接
                  _openDownloadUrl(versionInfo.downloadUrl);
                }
              },
              child: Text(platformSupported ? '一键更新' : '立即更新'),
            ),
        ],
      ),
    ));
  }

  /// 显示更新进度对话框（Material Design 版本）
  void _showUpdateProgressDialog(VersionInfo versionInfo) {
    if (!mounted) return;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => PopScope(
        canPop: false,
        child: AlertDialog(
          title: const Row(
            children: [
              Icon(Icons.system_update_alt, color: Colors.blue),
              SizedBox(width: 8),
              Text('正在更新'),
            ],
          ),
          content: AnimatedBuilder(
            animation: AutoUpdateService(),
            builder: (context, child) {
              final service = AutoUpdateService();
              final progress = service.progress;
              final statusMessage = service.statusMessage;
              final hasError = service.lastError != null;
              final isUpdating = service.isUpdating;
              final requiresRestart = service.requiresRestart;

              // 如果更新完成或出错，自动关闭对话框
              if (!isUpdating && mounted) {
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (mounted && Navigator.of(context).canPop()) {
                    Navigator.of(context).pop();
                    
                    if (hasError) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text('更新失败: ${service.lastError}'),
                          backgroundColor: Colors.red,
                          duration: const Duration(seconds: 5),
                        ),
                      );
                    } else if (requiresRestart) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('更新完成！应用即将重启...'),
                          backgroundColor: Colors.green,
                          duration: Duration(seconds: 3),
                        ),
                      );
                    }
                  }
                });
              }

              return Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 状态消息
                  Text(
                    statusMessage,
                    style: const TextStyle(fontSize: 14),
                  ),
                  const SizedBox(height: 20),

                  // 进度条
                  LinearProgressIndicator(
                    value: progress,
                    backgroundColor: Colors.grey[300],
                    valueColor: const AlwaysStoppedAnimation<Color>(Colors.blue),
                  ),
                  const SizedBox(height: 12),

                  // 进度百分比
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        '${(progress * 100).toStringAsFixed(1)}%',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: Colors.grey[700],
                        ),
                      ),
                      if (isUpdating)
                        const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                    ],
                  ),

                  // 错误提示
                  if (hasError) ...[
                    const SizedBox(height: 16),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.red.shade50,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.red.shade200),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.error_outline, color: Colors.red.shade700, size: 20),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              service.lastError!,
                              style: TextStyle(fontSize: 13, color: Colors.red.shade900),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  /// 显示更新进度对话框（Fluent UI 版本）
  void _showUpdateProgressDialogFluent(VersionInfo versionInfo) {
    if (!mounted) return;

    fluent.showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => PopScope(
        canPop: false,
        child: fluent.ContentDialog(
        title: const Text('正在更新'),
        content: AnimatedBuilder(
          animation: AutoUpdateService(),
          builder: (context, child) {
            final service = AutoUpdateService();
            final progress = service.progress;
            final statusMessage = service.statusMessage;
            final hasError = service.lastError != null;
            final isUpdating = service.isUpdating;
            final requiresRestart = service.requiresRestart;

            // 如果更新完成或出错，自动关闭对话框
            if (!isUpdating && mounted) {
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (mounted && Navigator.of(context).canPop()) {
                  Navigator.of(context).pop();
                  
                  if (hasError) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('更新失败: ${service.lastError}'),
                        backgroundColor: Colors.red,
                        duration: const Duration(seconds: 5),
                      ),
                    );
                  } else if (requiresRestart) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('更新完成！应用即将重启...'),
                        backgroundColor: Colors.green,
                        duration: Duration(seconds: 3),
                      ),
                    );
                  }
                }
              });
            }

            return Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 状态消息
                Text(
                  statusMessage,
                  style: const TextStyle(fontSize: 14),
                ),
                const SizedBox(height: 20),

                // 进度条
                fluent.ProgressBar(
                  value: progress * 100,
                ),
                const SizedBox(height: 12),

                // 进度百分比
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      '${(progress * 100).toStringAsFixed(1)}%',
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    if (isUpdating)
                      const SizedBox(
                        width: 16,
                        height: 16,
                        child: fluent.ProgressRing(strokeWidth: 2),
                      ),
                  ],
                ),

                // 错误提示
                if (hasError) ...[
                  const SizedBox(height: 16),
                  fluent.InfoBar(
                    title: const Text('更新失败'),
                    content: Text(service.lastError!),
                    severity: fluent.InfoBarSeverity.error,
                  ),
                ],
              ],
            );
          },
        ),
      ),
    ));
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
    if (_authFacade.isLoggedIn) {
      return true;
    }

    // 根据主题模式显示不同的对话框
    if (_themeManager.isFluentFramework) {
      return await _checkLoginStatusFluent();
    }

    // Cupertino 版本的对话框
    if ((Platform.isIOS || Platform.isAndroid) && _themeManager.isCupertinoFramework) {
      return await _checkLoginStatusCupertino();
    }

    // Material Design 版本的对话框
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
      return result == true && _authFacade.isLoggedIn;
    }

    return false;
  }

  /// Fluent UI 版本的登录状态检查
  Future<bool> _checkLoginStatusFluent() async {
    // 显示 Fluent UI 风格的提示对话框
    final shouldGoToSettings = await fluent.showDialog<bool>(
      context: context,
      builder: (context) => fluent.ContentDialog(
        title: const Text('需要登录'),
        content: const Text(
          '此功能需要登录后才能使用。\n\n'
          '请前往左侧菜单栏的「设置」页面进行登录。',
        ),
        actions: [
          fluent.Button(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          fluent.FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('我知道了'),
          ),
        ],
      ),
    );

    if (shouldGoToSettings == true && mounted) {
      // 显示提示信息
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('请点击左侧菜单栏的「设置」进行登录'),
          duration: Duration(seconds: 3),
        ),
      );
    }

    return false;
  }

  /// Cupertino (iOS) 版本的登录状态检查
  Future<bool> _checkLoginStatusCupertino() async {
    final shouldLogin = await showCupertinoDialog<bool>(
      context: context,
      builder: (context) => CupertinoAlertDialog(
        title: const Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(CupertinoIcons.lock, color: CupertinoColors.systemOrange),
            SizedBox(width: 8),
            Text('需要登录'),
          ],
        ),
        content: const Padding(
          padding: EdgeInsets.only(top: 12),
          child: Text('此功能需要登录后才能使用，是否前往登录？'),
        ),
        actions: [
          CupertinoDialogAction(
            isDefaultAction: false,
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          CupertinoDialogAction(
            isDefaultAction: true,
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
      return result == true && _authFacade.isLoggedIn;
    }

    return false;
  }

  @override
  Widget build(BuildContext context) {
    super.build(context); // 必须调用以支持 AutomaticKeepAliveClientMixin
    final theme = Theme.of(context);
    final bool showTabs = _isNeteaseBound; // 绑定网易云后显示 Tabs

    // Windows Fluent UI
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

    // iOS/Android Cupertino
    if ((Platform.isIOS || Platform.isAndroid) && _themeManager.isCupertinoFramework) {
      return _buildCupertinoHome(context, showTabs);
    }

    // Material Design (default)
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
    final mediaQuery = MediaQuery.of(context);
    final windowHeight = mediaQuery.size.height;
    final topPadding = mediaQuery.viewPadding.top;
    
    // 检测是否处于安卓小窗模式：
    // 1. 窗口高度较小 (< 500)
    // 2. 或者顶部 padding 占窗口高度的比例过大 (> 10%)，表明系统可能错误地为小窗应用了状态栏高度
    final bool shouldRemoveTopPadding = windowHeight < 500 || 
        (topPadding > 0 && topPadding / windowHeight > 0.1);

    final scaffold = Scaffold(
      backgroundColor: colorScheme.surface,
      body: _buildSlidingSwitcher(
        _buildMaterialContentArea(context, colorScheme, showTabs),
      ),
    );

    // 在需要时移除顶部安全区域 padding
    if (shouldRemoveTopPadding) {
      return MediaQuery.removePadding(
        context: context,
        removeTop: true,
        child: scaffold,
      );
    }

    return scaffold;
  }

  /// 构建 iOS Cupertino 风格首页
  Widget _buildCupertinoHome(BuildContext context, bool showTabs) {
    final isDark = CupertinoTheme.of(context).brightness == Brightness.dark;
    final backgroundColor = isDark
        ? CupertinoColors.black
        : CupertinoColors.systemGroupedBackground;

    final mediaQuery = MediaQuery.of(context);
    final windowHeight = mediaQuery.size.height;
    final topPadding = mediaQuery.viewPadding.top;
    
    // 检测是否处于安卓小窗模式：
    // 1. 窗口高度较小 (< 500)
    // 2. 或者顶部 padding 占窗口高度的比例过大 (> 10%)
    final bool shouldRemoveTopPadding = windowHeight < 500 || 
        (topPadding > 0 && topPadding / windowHeight > 0.1);

    final pageScaffold = Material(
      type: MaterialType.transparency,
      child: CupertinoPageScaffold(
        backgroundColor: backgroundColor,
        // 使用 RepaintBoundary 隔离滚动内容，防止底部 BackdropFilter 导致快速滚动残影
        child: RepaintBoundary(
          child: _buildSlidingSwitcher(
            _buildCupertinoContentArea(context, showTabs),
          ),
        ),
      ),
    );

    // 在小窗模式下移除顶部安全区域 padding
    if (shouldRemoveTopPadding) {
      return MediaQuery.removePadding(
        context: context,
        removeTop: true,
        child: pageScaffold,
      );
    }

    return pageScaffold;
  }

  /// 构建 iOS 风格内容区域
  Widget _buildCupertinoContentArea(BuildContext context, bool showTabs) {

    if (_showSearch) {
      return SearchWidget(
        key: ValueKey('cupertino_search_${_initialSearchKeyword ?? ''}'),
        onClose: () {
          if (!mounted) return;
          setState(() {
            _reverseTransition = true;
            _showSearch = false;
            _initialSearchKeyword = null;
          });
          _syncGlobalBackHandler();
        },
        initialKeyword: _initialSearchKeyword,
      );
    }

    // 主页内容
    return CustomScrollView(
      key: const ValueKey('cupertino_home_overview'),
      slivers: _buildCupertinoHomeSlivers(context, showTabs),
    );
  }

  /// 构建 Cupertino 风格的返回头部
  Widget _buildCupertinoBackHeader(
      BuildContext context, String title, VoidCallback onBack) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      child: Row(
        children: [
          CupertinoButton(
            padding: EdgeInsets.zero,
            onPressed: onBack,
            child: Row(
              children: [
                Icon(
                  CupertinoIcons.back,
                  color: ThemeManager.iosBlue,
                  size: 22,
                ),
                const SizedBox(width: 4),
                Text(
                  '返回',
                  style: TextStyle(
                    color: ThemeManager.iosBlue,
                    fontSize: 17,
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          // 占位，保持标题居中
          const SizedBox(width: 70),
        ],
      ),
    );
  }

  /// 构建 iOS 风格首页 Slivers
  List<Widget> _buildCupertinoHomeSlivers(BuildContext context, bool showTabs) {
    final isDark = CupertinoTheme.of(context).brightness == Brightness.dark;
    final isLoggedIn = _authFacade.isLoggedIn;
    
    final mediaQuery = MediaQuery.of(context);
    final windowHeight = mediaQuery.size.height;
    final topPadding = mediaQuery.viewPadding.top;
    
    // 检测是否处于安卓小窗模式
    final bool isSmallWindow = windowHeight < 500 || 
        (topPadding > 0 && topPadding / windowHeight > 0.1);
    
    return [
      // iOS 下拉刷新
      CupertinoSliverRefreshControl(
        onRefresh: _onRefresh,
      ),
      // iOS 大标题导航栏
      // 注意：移除 opacity 以避免与 BackdropFilter 组合导致快速滚动残影
      CupertinoSliverNavigationBar(
        // 小窗模式下使用紧凑标题而非大标题
        largeTitle: isSmallWindow ? null : const Text('首页'),
        middle: isSmallWindow ? const Text('首页') : null,
        backgroundColor: isDark
            ? const Color(0xFF1C1C1E)
            : CupertinoColors.systemBackground,
        border: null,
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            CupertinoButton(
              padding: EdgeInsets.zero,
              onPressed: () => openQrLoginScanPage(context),
              child: Icon(
                CupertinoIcons.qrcode_viewfinder,
                color: ThemeManager.iosBlue,
              ),
            ),
            CupertinoButton(
              padding: EdgeInsets.zero,
              onPressed: () => _handleSearchPressed(context),
              child: Icon(
                CupertinoIcons.search,
                color: ThemeManager.iosBlue,
              ),
            ),
            CupertinoButton(
              padding: EdgeInsets.zero,
              onPressed: _onRefresh,
              child: Icon(
                CupertinoIcons.refresh,
                color: ThemeManager.iosBlue,
              ),
            ),
          ],
        ),
      ),
      // 固定的分段控制器（滚动时吸顶）- 未登录时隐藏
      if (isLoggedIn && showTabs)
        SliverPersistentHeader(
          pinned: true,
          delegate: CupertinoHomeStickyHeaderDelegate(
            tabs: const ['为你推荐', '榜单'],
            currentIndex: _homeTabIndex,
            onChanged: (i) => setState(() => _homeTabIndex = i),
          ),
        ),
      // 内容
      SliverPadding(
        padding: const EdgeInsets.all(16.0),
        sliver: SliverList(
          delegate: SliverChildListDelegate([
            // 未登录时显示登录提示
            if (!isLoggedIn) ...[
              HomeForYouTab(
                key: const ValueKey('for_you_not_logged_in_cupertino'),
                onOpenPlaylistDetail: (id) {},
                onOpenDailyDetail: (tracks) {},
              ),
            ] else if (showTabs && _homeTabIndex == 0) ...[
              HomeForYouTab(
                key: ValueKey('for_you_$_forYouReloadToken'),
                onOpenPlaylistDetail: (id) {
                  if (ThemeManager().isFluentFramework) {
                    setState(() {
                      _homeTabIndex = 0;
                      _discoverPlaylistId = id;
                      _showDiscoverDetail = true;
                    });
                    _syncGlobalBackHandler();
                    return;
                  }
                  Navigator.of(context).push(
                    CupertinoPageRoute(
                      builder: (context) => DiscoverPlaylistDetailPage(playlistId: id),
                    ),
                  );
                },
                onOpenDailyDetail: (tracks) {
                  if (ThemeManager().isFluentFramework) {
                    setState(() {
                      _homeTabIndex = 0;
                      _dailyTracks = tracks;
                      _showDailyDetail = true;
                    });
                    _syncGlobalBackHandler();
                    return;
                  }
                  Navigator.of(context).push(
                    CupertinoPageRoute(
                      builder: (context) => DailyRecommendDetailPage(tracks: tracks),
                    ),
                  );
                },
              ),
            ] else ...[
              if (MusicService().isLoading)
                const CupertinoLoadingSection()
              else if (MusicService().errorMessage != null)
                const CupertinoErrorSection()
              else if (MusicService().toplists.isEmpty)
                const CupertinoEmptySection()
              else ...[
                CupertinoBannerSection(
                  cachedRandomTracks: _cachedRandomTracks,
                  bannerController: _bannerController,
                  currentBannerIndex: _currentBannerIndex,
                  onPageChanged: (index) {
                    setState(() {
                      _currentBannerIndex = index;
                    });
                    _restartBannerTimer();
                  },
                  checkLoginStatus: _checkLoginStatus,
                ),
                const SizedBox(height: 24),
                LayoutBuilder(
                  builder: (context, constraints) {
                    final useVerticalLayout =
                        constraints.maxWidth < 600 || Platform.isAndroid || Platform.isIOS;

                    if (useVerticalLayout) {
                      return Column(
                        children: [
                          const CupertinoHistorySection(),
                          const SizedBox(height: 16),
                          CupertinoGuessYouLikeSection(
                            guessYouLikeFuture: _guessYouLikeFuture,
                          ),
                        ],
                      );
                    } else {
                      return Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Expanded(child: CupertinoHistorySection()),
                          const SizedBox(width: 16),
                          Expanded(
                            child: CupertinoGuessYouLikeSection(
                              guessYouLikeFuture: _guessYouLikeFuture,
                            ),
                          ),
                        ],
                      );
                    }
                  },
                ),
                const SizedBox(height: 24),
                CupertinoToplistsGrid(
                  checkLoginStatus: _checkLoginStatus,
                  showToplistDetail: (toplist) =>
                      showToplistDetail(context, toplist),
                ),
              ],
            ],
            // 底部安全区域
            SizedBox(height: MediaQuery.of(context).padding.bottom + 100),
          ]),
        ),
      ),
    ];
  }

  Future<void> _handleSearchPressed(BuildContext context) async {
    final isLoggedIn = await _checkLoginStatus();
    if (isLoggedIn && mounted) {
      setState(() {
        _reverseTransition = false;
        _showSearch = true;
        _initialSearchKeyword = null;
      });
      _syncGlobalBackHandler();
    }
  }

  Future<void> _onRefresh() async {
    await _clearForYouCache();
    if (mounted) {
      setState(() {
        _forYouReloadToken++;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('正在刷新为你推荐...')),
      );
    }
    await MusicService().refreshToplists();
  }

  Future<void> _clearForYouCache() async {
    final prefs = await SharedPreferences.getInstance();
    final userId = _authFacade.currentUser?.id?.toString() ?? 'guest';
    final base = 'home_for_you_$userId';
    await prefs.remove('${base}_data');
    await prefs.remove('${base}_expire');
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

  void _closeDiscoverDetail() {
    if (!mounted) return;
    setState(() {
      _reverseTransition = true;
      _showDiscoverDetail = false;
      _discoverPlaylistId = null;
    });
    _syncGlobalBackHandler();
  }

  void _closeDailyDetail() {
    if (!mounted) return;
    setState(() {
      _reverseTransition = true;
      _showDailyDetail = false;
      _dailyTracks = const [];
    });
    _syncGlobalBackHandler();
  }

  void _openSearchFromExternal(String? keyword) {
    if (!mounted) return;
    final normalizedKeyword = keyword?.trim();
    setState(() {
      _reverseTransition = false;
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

    final fluentTheme = fluent.FluentTheme.maybeOf(context);
    final bool useWindowEffect =
        Platform.isWindows && ThemeManager().windowEffect != WindowEffect.disabled;
    final micaBackgroundColor = fluentTheme?.micaBackgroundColor ?? Colors.transparent;

    final Widget content = Column(
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
        const SizedBox(height: 0),
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
    );

    return Scaffold(
      backgroundColor: useWindowEffect ? Colors.transparent : micaBackgroundColor,
      body: content,
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
            _reverseTransition = true;
            _showSearch = false;
            _initialSearchKeyword = null;
          });
          _syncGlobalBackHandler();
        },
        initialKeyword: _initialSearchKeyword,
      );
    }

    return RefreshIndicator(
      onRefresh: _onRefresh,
      displacement: 20,
      edgeOffset: 0, 
      child: CustomScrollView(
        key: const ValueKey('material_home_overview'),
        slivers: _buildHomeSlivers(
          context: context,
          colorScheme: colorScheme,
          showTabs: showTabs,
          includeAppBar: true,
        ),
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
    // 根据 _reverseTransition 决定动画方向
    // 只有状态为 forward 时才是新进入的组件
    final bool isEntering = animation.status == AnimationStatus.forward;
    
    Offset begin;
    if (_reverseTransition) {
      // 退出 (Pop)：新页面从左滑入 (-1,0)，旧页面向右滑出 (1,0)
      begin = isEntering ? const Offset(-1.0, 0.0) : const Offset(1.0, 0.0);
    } else {
      // 进入 (Push)：新页面从右滑入 (1,0)，旧页面向左滑出 (-1,0)
      begin = isEntering ? const Offset(1.0, 0.0) : const Offset(-1.0, 0.0);
    }

    final curvedAnimation = CurvedAnimation(
      parent: animation,
      curve: Curves.easeOutCubic,
      reverseCurve: Curves.easeInCubic,
    );
    final positionAnimation = Tween<Offset>(
      begin: begin,
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
    // 根据当前主题亮度设置状态栏样式（仅 Android 需要）
    final brightness = Theme.of(context).brightness;
    final systemOverlayStyle = brightness == Brightness.light
        ? SystemUiOverlayStyle.dark.copyWith(
            statusBarColor: Colors.transparent,
          )
        : SystemUiOverlayStyle.light.copyWith(
            statusBarColor: Colors.transparent,
          );

    final mediaQuery = MediaQuery.of(context);
    final windowHeight = mediaQuery.size.height;
    final topPadding = mediaQuery.viewPadding.top;
    
    // 检测是否处于安卓小窗模式
    final bool shouldDisablePrimary = windowHeight < 500 || 
        (topPadding > 0 && topPadding / windowHeight > 0.1);

    return SliverAppBar(
      primary: !shouldDisablePrimary,
      pinned: true,
      backgroundColor: colorScheme.surface,
      surfaceTintColor: colorScheme.surface,
      elevation: 0,
      scrolledUnderElevation: 0,
      systemOverlayStyle: Platform.isAndroid ? systemOverlayStyle : null,
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
          icon: const Icon(Icons.qr_code_scanner),
          tooltip: '扫码登录',
          onPressed: () => openQrLoginScanPage(context),
        ),
        IconButton(
          icon: const Icon(Icons.search),
          tooltip: '搜索',
          onPressed: () => _handleSearchPressed(context),
        ),
        IconButton(
          icon: const Icon(Icons.refresh),
          tooltip: '刷新',
          onPressed: _onRefresh,
        ),
      ],
    );
  }

  Widget _buildHomeContentSliver(BuildContext context, bool showTabs) {
    // 未登录状态下直接显示登录提示（通过 HomeForYouTab）
    final isLoggedIn = _authFacade.isLoggedIn;

    if (_isBindingsLoading) {
      return SliverFillRemaining(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: ForYouSkeleton(),
        ),
      );
    }

    return SliverPadding(
      padding: const EdgeInsets.all(24.0),
      sliver: SliverList(
        delegate: SliverChildListDelegate([
          // 未登录时不显示 Tabs，只显示登录提示
          if (isLoggedIn && showTabs) ...[
            Padding(
              padding: const EdgeInsets.only(bottom: 12.0),
              child: _HomeTabs(
                tabs: const ['为你推荐', '榜单'],
                currentIndex: _homeTabIndex,
                onChanged: (i) => setState(() => _homeTabIndex = i),
              ),
            ),
            const SizedBox(height: 8),
          ],
          // 未登录时显示 HomeForYouTab（内部有登录提示）
          if (!isLoggedIn) ...[
            HomeForYouTab(
              key: const ValueKey('for_you_not_logged_in'),
              onOpenPlaylistDetail: (id) {},
              onOpenDailyDetail: (tracks) {},
            ),
          ] else if (showTabs && _homeTabIndex == 0) ...[
            HomeForYouTab(
              key: ValueKey('for_you_$_forYouReloadToken'),
              onOpenPlaylistDetail: (id) {
                if (ThemeManager().isFluentFramework) {
                  setState(() {
                    _homeTabIndex = 0;
                    _discoverPlaylistId = id;
                    _showDiscoverDetail = true;
                  });
                  _syncGlobalBackHandler();
                  return;
                }
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (context) => DiscoverPlaylistDetailPage(playlistId: id),
                  ),
                );
              },
              onOpenDailyDetail: (tracks) {
                if (ThemeManager().isFluentFramework) {
                  setState(() {
                    _homeTabIndex = 0;
                    _dailyTracks = tracks;
                    _showDailyDetail = true;
                  });
                  _syncGlobalBackHandler();
                  return;
                }
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (context) => DailyRecommendDetailPage(tracks: tracks),
                  ),
                );
              },
            ),
          ] else ...[
            ChartsTab(
              cachedRandomTracks: _cachedRandomTracks,
              checkLoginStatus: _checkLoginStatus,
              guessYouLikeFuture: _guessYouLikeFuture,
              onRefresh: _onRefresh,
            ),
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
    final fluentTheme = fluent.FluentTheme.of(context);
    final bool useWindowEffect =
        Platform.isWindows && ThemeManager().windowEffect != WindowEffect.disabled;
    final Color embeddedBgColor = useWindowEffect
        ? Colors.transparent
        : fluentTheme.micaBackgroundColor;

    if (_showDailyDetail) {
      return Container(
        key: const ValueKey('fluent_daily_detail'),
        color: embeddedBgColor,
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
        color: embeddedBgColor,
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
        color: embeddedBgColor,
        child: SearchWidget(
          key: ValueKey('fluent_search_body_${_initialSearchKeyword ?? ''}'),
          onClose: () {
            if (!mounted) return;
            setState(() {
              _reverseTransition = true;
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
            onPressed: _onRefresh,
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

  /// 准备“猜你喜欢”的 Future
  void _prepareGuessYouLikeFuture() {
    _guessYouLikeFuture = _fetchRandomTracksFromToplists();
  }

  /// 从榜单中获取随机歌曲
  Future<List<Track>> _fetchRandomTracksFromToplists() async {
    // 等待一小段时间确保榜单数据已加载（如果是首次启动）
    if (MusicService().toplists.isEmpty) {
      await Future.delayed(const Duration(seconds: 1));
    }
    
    final toplists = MusicService().toplists;
    if (toplists.isEmpty) {
      // 如果还没有榜单数据，尝试刷新一次
      await MusicService().refreshToplists();
      if (MusicService().toplists.isEmpty) {
        return []; // 仍然没有数据，返回空
      }
    }

    // 收集所有榜单的前10首歌曲作为候选池
    final List<Track> candidates = [];
    
    // 如果榜单数据中已经包含了 tracks (Track list)，直接使用
    // 注意：Toplist 模型中包含 tracks 字段，是 ToplistTrack 类型
    for (final toplist in MusicService().toplists) {
      if (toplist.tracks.isNotEmpty) {
        candidates.addAll(toplist.tracks);
      }
    }

    if (candidates.isEmpty) {
       return [];
    }

    // 随机挑选3首
    final random = Random();
    final List<Track> selected = [];
    final count = min(3, candidates.length);
    
    // 简单的随机不重复选择
    final List<int> selectedIndices = [];
    while (selected.length < count) {
      final index = random.nextInt(candidates.length);
      if (!selectedIndices.contains(index)) {
        selectedIndices.add(index);
        selected.add(candidates[index]);
      }
    }
    
    return selected;
  }

  void _syncGlobalBackHandler() {
    if (!mounted) {
      _homeOverlayController.setBackHandler(null);
      GlobalBackHandlerService().unregister('home_overlay');
      return;
    }

    if (_showSearch) {
      final handler = () {
        if (!mounted) return;
        setState(() {
          _showSearch = false;
          _initialSearchKeyword = null;
        });
        _syncGlobalBackHandler();
      };
      _homeOverlayController.setBackHandler(handler);
      GlobalBackHandlerService().register('home_overlay', () {
        handler();
        return true;
      });
      return;
    }

    if (_showDailyDetail) {
      final handler = () {
        _closeDailyDetail();
      };
      _homeOverlayController.setBackHandler(handler);
      GlobalBackHandlerService().register('home_overlay', () {
        handler();
        return true;
      });
      return;
    }

    if (_showDiscoverDetail && _discoverPlaylistId != null) {
      final handler = () {
        _closeDiscoverDetail();
      };
      _homeOverlayController.setBackHandler(handler);
      GlobalBackHandlerService().register('home_overlay', () {
        handler();
        return true;
      });
      return;
    }

    _homeOverlayController.setBackHandler(null);
    GlobalBackHandlerService().unregister('home_overlay');
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

/// 首页顶部 Tabs
/// Fluent UI 主题下使用 Win11 Pivot 风格（下划线指示器）
/// Material Design 主题下使用 Android 16 Expressive 风格（大标题 + 开阔布局）
class _HomeTabs extends StatelessWidget {
  final List<String> tabs;
  final int currentIndex;
  final ValueChanged<int> onChanged;
  const _HomeTabs({
    required this.tabs,
    required this.currentIndex,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final isFluent = ThemeManager().isFluentFramework;
    
    // Fluent UI 主题使用 Win11 Pivot 风格
    if (isFluent) {
      return _buildFluentPivotTabs(context);
    }
    
    // Material Design / Android 16 Expressive 风格
    return _buildMaterialExpressiveTabs(context);
  }
  
  /// Win11 风格的 Pivot Tab 栏
  Widget _buildFluentPivotTabs(BuildContext context) {
    final fluentTheme = fluent.FluentTheme.of(context);
    final isLight = fluentTheme.brightness == Brightness.light;
    final accentColor = fluentTheme.accentColor;
    final textColor = fluentTheme.typography.body?.color ??
        (isLight ? Colors.black : Colors.white);
    final subtleTextColor = isLight 
        ? Colors.black.withOpacity(0.6) 
        : Colors.white.withOpacity(0.6);
    
    return SizedBox(
      height: 40,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: List.generate(tabs.length, (i) {
          final selected = i == currentIndex;
          return Padding(
            padding: EdgeInsets.only(right: i < tabs.length - 1 ? 8 : 0),
            child: _FluentPivotTabItem(
              label: tabs[i],
              isSelected: selected,
              accentColor: accentColor,
              selectedTextColor: textColor,
              unselectedTextColor: subtleTextColor,
              onTap: () => onChanged(i),
            ),
          );
        }),
      ),
    );
  }
  
  /// Android 16 / Material Expressive 风格 - 摆脱胶囊形态，更开阔的表现力
  Widget _buildMaterialExpressiveTabs(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final selectedColor = cs.primary;
    final unselectedColor = cs.onSurface.withOpacity(0.7);

    return LayoutBuilder(
      builder: (context, constraints) {
        const height = 60.0;
        final count = tabs.length;
        // 在开阔布局下，我们不再固定宽度，而是根据内容自适应或平均分配
        final tabWidth = constraints.maxWidth / count;

        return SizedBox(
          height: height,
          child: Stack(
            children: [
              // 底部指示器 - 采用厚度适中的圆角长条，带弹性滑动
              AnimatedPositioned(
                duration: const Duration(milliseconds: 400),
                curve: Curves.elasticOut,
                bottom: 4,
                left: currentIndex * tabWidth + (tabWidth - 28) / 2, // 居中且宽度固定为28
                width: 28,
                height: 4,
                child: Container(
                  decoration: BoxDecoration(
                    color: selectedColor,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              // 标签点击与表现力文字
              Row(
                children: List.generate(count, (i) {
                  final selected = i == currentIndex;
                  return InkWell(
                    onTap: () => onChanged(i),
                    splashColor: Colors.transparent,
                    highlightColor: Colors.transparent,
                    child: Container(
                      width: tabWidth,
                      alignment: Alignment.center,
                      child: AnimatedDefaultTextStyle(
                        duration: const Duration(milliseconds: 300),
                        curve: Curves.easeOutBack,
                        style: TextStyle(
                          color: selected ? cs.onSurface : unselectedColor,
                          fontSize: selected ? 22 : 18,
                          fontWeight: selected ? FontWeight.w900 : FontWeight.w600,
                          letterSpacing: selected ? -0.5 : 0,
                          fontFamily: 'Microsoft YaHei',
                        ),
                        child: Text(tabs[i]),
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

/// Win11 风格的 Pivot Tab 单项
class _FluentPivotTabItem extends StatefulWidget {
  final String label;
  final bool isSelected;
  final Color accentColor;
  final Color selectedTextColor;
  final Color unselectedTextColor;
  final VoidCallback onTap;

  const _FluentPivotTabItem({
    required this.label,
    required this.isSelected,
    required this.accentColor,
    required this.selectedTextColor,
    required this.unselectedTextColor,
    required this.onTap,
  });

  @override
  State<_FluentPivotTabItem> createState() => _FluentPivotTabItemState();
}

class _FluentPivotTabItemState extends State<_FluentPivotTabItem> {
  bool _isHovering = false;

  @override
  Widget build(BuildContext context) {
    final isLight = fluent.FluentTheme.of(context).brightness == Brightness.light;
    
    // 计算当前文字颜色
    Color textColor;
    if (widget.isSelected) {
      textColor = widget.selectedTextColor;
    } else if (_isHovering) {
      textColor = widget.selectedTextColor.withOpacity(0.8);
    } else {
      textColor = widget.unselectedTextColor;
    }
    
    // 计算下划线颜色和宽度
    final indicatorColor = widget.isSelected ? widget.accentColor : Colors.transparent;
    final indicatorWidth = widget.isSelected ? 20.0 : 0.0;
    
    // hover 背景色
    final hoverBg = _isHovering && !widget.isSelected
        ? (isLight ? Colors.black.withOpacity(0.04) : Colors.white.withOpacity(0.04))
        : Colors.transparent;

    return MouseRegion(
      onEnter: (_) => setState(() => _isHovering = true),
      onExit: (_) => setState(() => _isHovering = false),
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: widget.onTap,
        behavior: HitTestBehavior.opaque,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          curve: Curves.easeOutCubic,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          decoration: BoxDecoration(
            color: hoverBg,
            borderRadius: BorderRadius.circular(6),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // 文字
              AnimatedDefaultTextStyle(
                duration: const Duration(milliseconds: 150),
                curve: Curves.easeOutCubic,
                style: TextStyle(
                  color: textColor,
                  fontSize: 13,
                  fontWeight: widget.isSelected ? FontWeight.w600 : FontWeight.w500,
                  fontFamily: 'Microsoft YaHei',
                ),
                child: Text(widget.label),
              ),
              const SizedBox(height: 2),
              // 下划线指示器
              AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                curve: Curves.easeOutCubic,
                width: indicatorWidth,
                height: 2.5,
                decoration: BoxDecoration(
                  color: indicatorColor,
                  borderRadius: BorderRadius.circular(1.25),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
