import '../services/structured_log_service.dart';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';
import '../widgets/custom_title_bar.dart';
import '../widgets/cupertino/cupertino_bottom_nav.dart';
import '../widgets/mini_player.dart';
import '../pages/home_page.dart';
import '../pages/discover_page.dart';
import '../pages/history_page.dart';
import '../pages/my_page/my_page.dart';
import '../pages/local_page.dart';
import '../pages/settings_page.dart';
import '../pages/developer_page.dart';
import '../services/layout_preference_service.dart';
import '../services/developer_mode_service.dart';
import '../services/global_back_handler_service.dart';
import '../utils/page_visibility_notifier.dart';
import '../utils/theme_manager.dart';
import '../pages/auth/auth_page.dart';
import '../services/auth_overlay_service.dart';
import '../services/player_service.dart';
import '../services/persistent_storage_service.dart';
import '../services/experience_profile_service.dart';
import '../pages/mobile_setup_page.dart';
import '../widgets/global_watermark.dart';
import '../widgets/fixed_navigation_dock.dart';
import '../utils/dynamic_color_utils.dart';

/// 主布局 - 包含侧边导航栏和内容区域
class MainLayout extends StatefulWidget {
  const MainLayout({super.key});

  @override
  State<MainLayout> createState() => _MainLayoutState();
}

class _MainLayoutState extends State<MainLayout>
    with SingleTickerProviderStateMixin {
  int _selectedIndex = 0;
  // NavigationDrawer 固定宽度与 NavigationRail 展开状态一致（Material 3 默认 256）
  static const double _drawerWidth = 256.0;
  static const double _collapsedWidth = 80.0; // 折叠状态宽度，仅显示图标
  bool _isDrawerCollapsed = true; // 抽屉是否处于折叠状态（默认收起）

  // 页面列表
  List<Widget> get _pages {
    final isLocalMode = PersistentStorageService().enableLocalMode;

    if (isLocalMode) {
      return [
        const LocalPage(),
        MobileSetupPage(), // 本地模式下的“设置”显示引导页
      ];
    }

    final pages = <Widget>[
      const HomePage(),
      const DiscoverPage(),
      const HistoryPage(),
      const LocalPage(), // 本地
      const MyPage(), // 我的（歌单+听歌统计）
      const SettingsPage(),
    ];

    // 如果开发者模式启用，添加开发者页面
    if (DeveloperModeService().isDeveloperMode) {
      pages.add(const DeveloperPage());
    }

    return pages;
  }

  int get _settingsIndex => _pages.indexWhere((w) => w is SettingsPage);

  @override
  void initState() {
    super.initState();
    PageVisibilityNotifier().addListener(_onPageVisibilityNotifierChanged);
    DeveloperModeService().addListener(_onDeveloperModeChanged);
    PageVisibilityNotifier().setCurrentPage(_selectedIndex);
  }

  @override
  void dispose() {
    PageVisibilityNotifier().removeListener(_onPageVisibilityNotifierChanged);
    DeveloperModeService().removeListener(_onDeveloperModeChanged);
    super.dispose();
  }

  void _onPageVisibilityNotifierChanged() {
    if (!mounted) return;

    final newIndex = PageVisibilityNotifier().currentPageIndex;
    if (newIndex < 0 ||
        newIndex >= _pages.length ||
        newIndex == _selectedIndex) {
      return;
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      setState(() => _selectedIndex = newIndex);
    });
  }

  void _onDeveloperModeChanged() {
    if (!mounted) return;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final maxIndex = _pages.length - 1;
      if (_selectedIndex <= maxIndex) return;

      setState(() => _selectedIndex = 0);
      PageVisibilityNotifier().setCurrentPage(0);
    });
  }

  void _handleAndroidBack() {
    // 1. 首先检查全局返回处理器（二级页面等）
    if (GlobalBackHandlerService().handleBack()) {
      return;
    }

    // 2. 如果不在首页，返回首页
    if (_selectedIndex != 0) {
      setState(() {
        _selectedIndex = 0;
      });
      PageVisibilityNotifier().setCurrentPage(0);
      return;
    }

    // 3. 在首页，退出应用
    SystemNavigator.pop();
  }

  @override
  Widget build(BuildContext context) {
    StructuredLogService.log(
      '🏗️ [MainLayout] build called. SelectedIndex: $_selectedIndex, LocalMode: ${PersistentStorageService().enableLocalMode}',
    );
    // 根据平台选择不同的布局
    if (Platform.isAndroid || Platform.isIOS) {
      if (ThemeManager().isTablet) {
        return AnimatedBuilder(
          animation: ExperienceProfileService(),
          builder: (context, child) {
            final size = MediaQuery.sizeOf(context);
            final profile = ExperienceProfileService().resolve(
              width: size.width,
              height: size.height,
            );
            return GlobalWatermark(
              child: _buildDesktopLayout(
                context,
                useFixedDock:
                    profile == ExperienceProfile.tablet ||
                    profile == ExperienceProfile.car,
              ),
            );
          },
        );
      }
      // 手机始终使用移动布局
      return GlobalWatermark(child: _buildMobileLayout(context));
    } else if (Platform.isWindows) {
      // Windows 根据用户偏好选择布局，使用 AnimatedBuilder 确保更新
      return AnimatedBuilder(
        animation: LayoutPreferenceService(),
        builder: (context, child) {
          final isDesktop = LayoutPreferenceService().isDesktopLayout;
          StructuredLogService.log(
            '🖥️ [MainLayout] 当前布局模式: ${isDesktop ? "桌面模式" : "移动模式"}',
          );

          return GlobalWatermark(
            child: isDesktop
                ? _buildDesktopLayout(context, useFixedDock: true)
                : _buildMobileLayout(context),
          );
        },
      );
    } else {
      // 其他桌面平台（macOS/Linux）默认使用桌面布局
      return _buildDesktopLayout(context);
    }
  }

  /// 构建桌面端布局（Windows/Linux/macOS）
  Widget _buildDesktopLayout(
    BuildContext context, {
    bool useFixedDock = false,
  }) {
    final colorScheme = Theme.of(context).colorScheme;
    final fixedDockWidth = useFixedDock
        ? FixedNavigationDock.widthFor(context)
        : null;

    return Scaffold(
      backgroundColor: colorScheme.surface,
      body: Column(
        children: [
          // Windows 平台显示自定义标题栏
          if (Platform.isWindows) const CustomTitleBar(),

          // 主要内容区域
          Expanded(
            child: AnimatedBuilder(
              animation: AuthOverlayService(),
              builder: (context, child) {
                final overlay = AuthOverlayService();
                return Stack(
                  children: [
                    Row(
                      children: [
                        // 侧边导航栏
                        useFixedDock
                            ? _buildTabletNavigationDock(colorScheme)
                            : _buildNavigationDrawer(colorScheme),
                        // 内容区域
                        Expanded(child: _pages[_selectedIndex]),
                      ],
                    ),
                    if (overlay.isVisible)
                      // 完全参照首页-歌单详情样式：覆盖右侧内容区，保留侧栏与标题栏
                      Positioned.fill(
                        child: Row(
                          children: [
                            // 占位侧栏宽度
                            SizedBox(
                              width:
                                  fixedDockWidth ??
                                  (_isDrawerCollapsed
                                      ? _collapsedWidth
                                      : _drawerWidth),
                            ),
                            // 右侧内容覆盖
                            Expanded(
                              child: Material(
                                color: Theme.of(context).colorScheme.surface,
                                child: SafeArea(
                                  child: Column(
                                    children: [
                                      Align(
                                        alignment: Alignment.centerLeft,
                                        child: IconButton(
                                          icon: const Icon(
                                            Icons.arrow_back_rounded,
                                          ),
                                          onPressed: () =>
                                              AuthOverlayService().hide(false),
                                          tooltip: '返回',
                                        ),
                                      ),
                                      Expanded(
                                        child: PrimaryScrollController.none(
                                          child: AuthPage(
                                            initialTab: overlay.initialTab,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                );
              },
            ),
          ),

          // 迷你播放器
          const MiniPlayer(),
        ],
      ),
    );
  }

  /// 构建移动端布局（Android/iOS）
  Widget _buildMobileLayout(BuildContext context) {
    final isLocalMode = PersistentStorageService().enableLocalMode;
    StructuredLogService.log(
      '📱 [MainLayout] Building Mobile Layout (LocalMode: $isLocalMode, SelectedIndex: $_selectedIndex)',
    );

    final colorScheme = Theme.of(context).colorScheme;
    final isCupertinoUI =
        (Platform.isIOS || Platform.isAndroid) &&
        ThemeManager().isCupertinoFramework;
    final orientation = MediaQuery.of(context).orientation;
    final isLandscape = orientation == Orientation.landscape;

    final scaffold = PopScope(
      canPop: false, // 始终拦截返回键
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        _handleAndroidBack();
      },
      child: Scaffold(
        backgroundColor: isCupertinoUI
            ? (Theme.of(context).brightness == Brightness.dark
                  ? CupertinoColors.black
                  : CupertinoColors.systemGroupedBackground)
            : colorScheme.surface,
        body: isLandscape && !isCupertinoUI
            ? Row(
                children: [
                  _buildLandscapeSideNavigation(context),
                  Expanded(
                    child: MediaQuery.removePadding(
                      context: context,
                      removeLeft: true,
                      child: Stack(
                      children: [
                        // 主内容层 - 使用 RepaintBoundary 隔离，防止 BackdropFilter 导致滚动残影
                        RepaintBoundary(
                          child: Column(
                            children: [
                              if (Platform.isWindows) const CustomTitleBar(),
                              Expanded(child: _pages[_selectedIndex]),
                            ],
                          ),
                        ),
                        // 悬浮迷你播放器（不占用布局空间）
                        Positioned(
                          left: 0,
                          right: 0,
                          bottom: 0,
                          child: AnimatedBuilder(
                            animation: PlayerService(),
                            builder: (context, child) {
                              final hasMiniPlayer =
                                  PlayerService().currentTrack != null ||
                                  PlayerService().currentSong != null;
                              if (!hasMiniPlayer) {
                                return const SizedBox.shrink();
                              }
                              return const MiniPlayer();
                            },
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                ],
              )
            : Stack(
                children: [
                  // 主内容层 - 使用 RepaintBoundary 隔离，防止 BackdropFilter 导致滚动残影
                  RepaintBoundary(
                    child: Column(
                      children: [
                        if (Platform.isWindows) const CustomTitleBar(),
                        Expanded(child: _pages[_selectedIndex]),
                      ],
                    ),
                  ),
                  // 横屏布局没有使用 bottomNavigationBar，迷你播放器需要单独悬浮在内容底部。
                  if (isCupertinoUI || isLandscape)
                    Positioned(
                      left: 0,
                      right: 0,
                      bottom: isCupertinoUI ? 80 : 0,
                      child: AnimatedBuilder(
                        animation: PlayerService(),
                        builder: (context, child) {
                          final hasMiniPlayer =
                              PlayerService().currentTrack != null ||
                              PlayerService().currentSong != null;
                          if (!hasMiniPlayer) return const SizedBox.shrink();
                          return const MiniPlayer();
                        },
                      ),
                    ),
                  // iOS 26 悬浮液态玻璃 Tab 栏
                  if (isCupertinoUI)
                    Positioned(
                      left: 0,
                      right: 0,
                      bottom: 0,
                      child: _buildCupertinoTabBar(context),
                    ),
                ],
              ),
        // 非 Cupertino 模式使用 bottomNavigationBar
        bottomNavigationBar: isCupertinoUI
            ? null
            : (isLandscape ? null : _buildGlassBottomNavigationBar(context)),
      ),
    );

    if (!Platform.isAndroid) {
      return scaffold;
    }

    return AnimatedBuilder(
      animation: PlayerService(),
      builder: (context, child) {
        final theme = Theme.of(context);
        final isDark = theme.brightness == Brightness.dark;
        final hasPlayback =
            PlayerService().currentTrack != null ||
            PlayerService().currentSong != null;
        final navColor = hasPlayback
            ? Colors.transparent
            : theme.colorScheme.surface;
        return AnnotatedRegion<SystemUiOverlayStyle>(
          value: SystemUiOverlayStyle(
            statusBarColor: Colors.transparent,
            statusBarIconBrightness: isDark
                ? Brightness.light
                : Brightness.dark,
            statusBarBrightness: isDark ? Brightness.dark : Brightness.light,
            systemNavigationBarColor: navColor,
            systemNavigationBarDividerColor: navColor,
            systemNavigationBarIconBrightness: isDark
                ? Brightness.light
                : Brightness.dark,
          ),
          child: child!,
        );
      },
      child: scaffold,
    );
  }

  Widget _buildLandscapeSideNavigation(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;
    final int myIndex = _pages.indexWhere((w) => w is MyPage);

    final isLocalMode = PersistentStorageService().enableLocalMode;

    int navSelectedIndex() {
      if (isLocalMode) return _selectedIndex;
      if (_selectedIndex == 0) return 0; // 首页
      if (_selectedIndex == 1) return 1; // 发现
      if (_selectedIndex == myIndex) return 2; // 我的
      if (_selectedIndex == _settingsIndex) return 3; // 设置
      return 2;
    }

    final selectedIdx = navSelectedIndex();

    return ValueListenableBuilder<Color?>(
      valueListenable: PlayerService().themeColorNotifier,
      builder: (context, extractedThemeColor, _) {
        final dynamicAccent = DynamicColorUtils.resolveAccent(
          extractedThemeColor,
          colorScheme,
          isDark: isDark,
        );
        final dynamicAmbient = DynamicColorUtils.resolveAmbient(
          extractedThemeColor,
          colorScheme,
          isDark: isDark,
        );

        final items = isLocalMode
            ? [
                (
                  icon: Icons.folder_outlined,
                  activeIcon: Icons.folder_rounded,
                  label: '本地',
                ),
                (
                  icon: Icons.settings_outlined,
                  activeIcon: Icons.settings_rounded,
                  label: '设置',
                ),
              ]
            : [
                (
                  icon: Icons.home_outlined,
                  activeIcon: Icons.home_rounded,
                  label: '首页',
                ),
                (
                  icon: Icons.explore_outlined,
                  activeIcon: Icons.explore_rounded,
                  label: '发现',
                ),
                (
                  icon: Icons.person_outline_rounded,
                  activeIcon: Icons.person_rounded,
                  label: '我的',
                ),
                (
                  icon: Icons.settings_outlined,
                  activeIcon: Icons.settings_rounded,
                  label: '设置',
                ),
              ];

        final safePadding = MediaQuery.of(context).padding;

        return SizedBox(
          width: 74,
          height: double.infinity,
          child: Stack(
            children: [
              // 1. 毛玻璃模糊层 (铺满全高)
              Positioned.fill(
                child: BackdropFilter(
                  filter: ui.ImageFilter.blur(sigmaX: 30, sigmaY: 30),
                  child: const SizedBox.shrink(),
                ),
              ),
              // 2. 液态玻璃动态流光渐变背景 + 右侧微光细边框 (铺满全高)
              Positioned.fill(
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 400),
                  curve: Curves.easeOutCubic,
                  decoration: BoxDecoration(
                    color: colorScheme.surface.withValues(
                      alpha: isDark ? 0.82 : 0.88,
                    ),
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        colorScheme.surface.withValues(
                          alpha: isDark ? 0.88 : 0.92,
                        ),
                        dynamicAmbient.withValues(alpha: isDark ? 0.16 : 0.08),
                        dynamicAmbient.withValues(alpha: isDark ? 0.06 : 0.03),
                        colorScheme.surface.withValues(
                          alpha: isDark ? 0.82 : 0.86,
                        ),
                      ],
                      stops: const [0.0, 0.35, 0.70, 1.0],
                    ),
                    border: Border(
                      right: BorderSide(
                        color: dynamicAccent.withValues(
                          alpha: isDark ? 0.28 : 0.38,
                        ),
                        width: 0.8,
                      ),
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(
                          alpha: isDark ? 0.25 : 0.06,
                        ),
                        blurRadius: 16,
                        offset: const Offset(2, 0),
                      ),
                    ],
                  ),
                ),
              ),
              // 3. Apple Music 风格有机弥散微光光晕 (顶部微光)
              Positioned(
                top: -20,
                left: -20,
                width: 110,
                height: 110,
                child: IgnorePointer(
                  child: Container(
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: RadialGradient(
                        colors: [
                          dynamicAmbient.withValues(
                            alpha: isDark ? 0.25 : 0.16,
                          ),
                          Colors.transparent,
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              // 4. 侧边栏内容 (内部根据安全区域适配，垂直居中排布)
              Padding(
                padding: EdgeInsets.only(
                  top: safePadding.top > 0 ? safePadding.top + 4 : 12,
                  bottom: safePadding.bottom > 0 ? safePadding.bottom + 4 : 12,
                ),
                child: Column(
                  children: List.generate(items.length, (index) {
                    final item = items[index];
                    final isSelected = selectedIdx == index;

                    return Expanded(
                      child: Material(
                        color: Colors.transparent,
                        child: InkWell(
                          onTap: () {
                            StructuredLogService.log(
                              '🖱️ [MainLayout] Landscape side dock tab tapped: $index',
                            );
                            HapticFeedback.lightImpact();

                            int targetPageIndex = _selectedIndex;
                            if (isLocalMode) {
                              targetPageIndex = index;
                            } else {
                              if (index == 0) targetPageIndex = 0;
                              if (index == 1) targetPageIndex = 1;
                              if (index == 2) targetPageIndex = myIndex;
                              if (index == 3) targetPageIndex = _settingsIndex;
                            }

                            setState(() {
                              _selectedIndex = targetPageIndex;
                            });
                            PageVisibilityNotifier().setCurrentPage(
                              targetPageIndex,
                            );
                          },
                          borderRadius: BorderRadius.circular(16),
                          splashColor: Colors.transparent,
                          highlightColor: Colors.transparent,
                          child: Center(
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 240),
                              curve: Curves.easeOutCubic,
                              width: 58,
                              padding: const EdgeInsets.symmetric(vertical: 8),
                              decoration: BoxDecoration(
                                color: isSelected
                                    ? dynamicAccent.withValues(
                                        alpha: isDark ? 0.22 : 0.12,
                                      )
                                    : Colors.transparent,
                                borderRadius: BorderRadius.circular(16),
                                border: isSelected
                                    ? Border.all(
                                        color: dynamicAccent.withValues(
                                          alpha: isDark ? 0.40 : 0.25,
                                        ),
                                        width: 0.8,
                                      )
                                    : null,
                              ),
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    isSelected ? item.activeIcon : item.icon,
                                    size: 22,
                                    color: isSelected
                                        ? dynamicAccent
                                        : colorScheme.onSurfaceVariant
                                              .withValues(alpha: 0.70),
                                  ),
                                  const SizedBox(height: 4),
                                  AnimatedDefaultTextStyle(
                                    duration: const Duration(milliseconds: 180),
                                    style: TextStyle(
                                      fontSize: 10.5,
                                      fontWeight: isSelected
                                          ? FontWeight.bold
                                          : FontWeight.w500,
                                      color: isSelected
                                          ? dynamicAccent
                                          : colorScheme.onSurfaceVariant
                                                .withValues(alpha: 0.70),
                                      letterSpacing: -0.2,
                                    ),
                                    child: Text(item.label),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    );
                  }),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  /// 构建 iOS 26 风格的悬浮液态玻璃底部导航栏
  Widget _buildCupertinoTabBar(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final int myIndex = _pages.indexWhere((w) => w is MyPage);
    final bottomPadding = MediaQuery.of(context).padding.bottom;

    // 计算当前选中的 tab 索引
    int navSelectedIndex() {
      if (_selectedIndex == 0) return 0; // 首页
      if (_selectedIndex == 1) return 1; // 发现
      if (_selectedIndex == myIndex) return 2; // 我的
      return 3; // 更多
    }

    final isLocalMode = PersistentStorageService().enableLocalMode;

    // Tab 项目数据 - 使用自定义 SVG 图标
    final List<_FloatingTabItem> tabItems = isLocalMode
        ? [
            _FloatingTabItem(
              svgAsset: 'assets/ui/FluentColorHistory16.svg',
              label: '本地',
            ),
            _FloatingTabItem(
              svgAsset: 'assets/ui/FluentColorSettings16.svg',
              label: '退出本地',
            ),
          ]
        : [
            _FloatingTabItem(
              svgAsset: 'assets/ui/FluentColorHome16.svg',
              label: '首页',
            ),
            _FloatingTabItem(
              svgAsset: 'assets/ui/FluentColorSearchSparkle16.svg',
              label: '发现',
            ),
            _FloatingTabItem(
              svgAsset: 'assets/ui/FluentColorPerson16.svg',
              label: '我的',
            ),
            _FloatingTabItem(
              svgAsset: 'assets/ui/FluentColorAppsList20.svg',
              label: '更多',
            ),
          ];

    final int currentIndex = navSelectedIndex();

    return Container(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        bottom: bottomPadding > 0 ? bottomPadding : 16,
        top: 8,
      ),
      child: _LiquidGlassContainer(
        borderRadius: 32,
        height: 60,
        isDark: isDark,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: List.generate(tabItems.length, (index) {
            final item = tabItems[index];
            final isSelected = index == currentIndex;

            return Expanded(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () async {
                  final isLocalMode =
                      PersistentStorageService().enableLocalMode;
                  if (isSelected) return;

                  if (isLocalMode) {
                    // 本地模式：0 -> 本地, 1 -> 退出本地(其实是 MobileSetupPage)
                    setState(() {
                      _selectedIndex = index;
                    });
                    PageVisibilityNotifier().setCurrentPage(index);
                    return;
                  }

                  // 非本地模式：映射 Tab 索引到页面索引
                  final int moreTab = tabItems.length - 1;
                  if (index == moreTab) {
                    await _openCupertinoMoreSheet(context);
                    return;
                  }

                  int targetPageIndex;
                  if (index == 0) {
                    targetPageIndex = 0; // 首页
                  } else if (index == 1) {
                    targetPageIndex = 1; // 发现
                  } else if (index == 2) {
                    targetPageIndex = myIndex; // 我的
                  } else {
                    // 理论上不会走到这里，因为 moreTab 已经提前拦截了
                    return;
                  }

                  setState(() {
                    _selectedIndex = targetPageIndex;
                  });
                  PageVisibilityNotifier().setCurrentPage(targetPageIndex);
                },
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  curve: Curves.easeOutCubic,
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      // 图标容器（选中时有背景）
                      AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        curve: Curves.easeOutCubic,
                        padding: EdgeInsets.symmetric(
                          horizontal: isSelected ? 16 : 12,
                          vertical: isSelected ? 6 : 4,
                        ),
                        decoration: BoxDecoration(
                          color: isSelected
                              ? ThemeManager.iosBlue.withValues(alpha: 0.2)
                              : Colors.transparent,
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: SvgPicture.asset(
                          item.svgAsset,
                          width: 22,
                          height: 22,
                          fit: BoxFit.contain,
                        ),
                      ),
                      const SizedBox(height: 2),
                      // 标签
                      AnimatedDefaultTextStyle(
                        duration: const Duration(milliseconds: 200),
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: isSelected
                              ? FontWeight.w600
                              : FontWeight.w500,
                          color: isSelected
                              ? ThemeManager.iosBlue
                              : (isDark
                                    ? Colors.white.withValues(alpha: 0.7)
                                    : Colors.black.withValues(alpha: 0.5)),
                          shadows: [
                            Shadow(
                              color: Colors.black.withValues(alpha: 0.2),
                              blurRadius: 4,
                              offset: const Offset(0, 1),
                            ),
                          ],
                        ),
                        child: Text(item.label),
                      ),
                    ],
                  ),
                ),
              ),
            );
          }),
        ),
      ),
    );
  }

  /// Cupertino 风格的更多菜单
  Future<void> _openCupertinoMoreSheet(BuildContext context) async {
    await showCupertinoMoreSheet(
      context: context,
      onHistoryTap: () {
        setState(() => _selectedIndex = 2);
        PageVisibilityNotifier().setCurrentPage(2);
      },
      onLocalTap: () {
        setState(() => _selectedIndex = 3);
        PageVisibilityNotifier().setCurrentPage(3);
      },
      onSettingsTap: () {
        final idx = _settingsIndex;
        setState(() => _selectedIndex = idx);
        PageVisibilityNotifier().setCurrentPage(idx);
        DeveloperModeService().onSettingsClicked();
      },
      onDevTap: () {
        setState(() => _selectedIndex = _pages.length - 1);
        PageVisibilityNotifier().setCurrentPage(_pages.length - 1);
      },
      showDev: DeveloperModeService().isDeveloperMode,
    );
  }

  Widget _buildGlassBottomNavigationBar(BuildContext context) {
    final isLocalMode = PersistentStorageService().enableLocalMode;
    StructuredLogService.log(
      '🎨 [MainLayout] Building Glass Bottom Navigation (LocalMode: $isLocalMode)',
    );
    final orientation = MediaQuery.of(context).orientation;
    final bool useGlass =
        Platform.isAndroid || orientation == Orientation.portrait;

    final bool isLandscape = orientation == Orientation.landscape;
    final int myIndex = _pages.indexWhere((w) => w is MyPage);

    int navSelectedIndex() {
      final isLocalMode = PersistentStorageService().enableLocalMode;
      if (isLocalMode) return _selectedIndex;

      if (_selectedIndex == 0) return 0; // 首页
      if (_selectedIndex == 1) return 1; // 发现
      if (_selectedIndex == myIndex) return 2; // 我的
      if (_selectedIndex == _settingsIndex) return 3; // 设置
      return 2;
    }

    final selectedIdx = navSelectedIndex();
    final tabTitles = isLocalMode
        ? const ['本地', '设置']
        : const ['首页', '发现', '我的', '设置'];

    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final baseNav = SizedBox(
      height: 48.0,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: List.generate(tabTitles.length, (tabIndex) {
            final isSelected = selectedIdx == tabIndex;
            final title = tabTitles[tabIndex];
            return Expanded(
              child: InkWell(
                onTap: () async {
                  final isLocalMode =
                      PersistentStorageService().enableLocalMode;
                  StructuredLogService.log(
                    '🖱️ [MainLayout] Navigation tab selected: $tabIndex (LocalMode: $isLocalMode)',
                  );

                  int targetIndex = tabIndex;
                  if (!isLocalMode) {
                    if (tabIndex == 0) {
                      targetIndex = 0;
                    } else if (tabIndex == 1) {
                      targetIndex = 1;
                    } else if (tabIndex == 2) {
                      targetIndex = myIndex;
                    } else if (tabIndex == 3) {
                      targetIndex = _settingsIndex;
                    }
                  }

                  setState(() {
                    _selectedIndex = targetIndex;
                    StructuredLogService.log(
                      '🔄 [MainLayout] _selectedIndex updated to: $_selectedIndex',
                    );
                  });
                  PageVisibilityNotifier().setCurrentPage(targetIndex);
                },
                splashColor: Colors.transparent,
                highlightColor: Colors.transparent,
                child: Center(
                  child: AnimatedDefaultTextStyle(
                    duration: const Duration(milliseconds: 180),
                    curve: Curves.easeOutCubic,
                    style: TextStyle(
                      fontSize: isSelected ? 16.5 : 15.0,
                      fontWeight: isSelected
                          ? FontWeight.w900
                          : FontWeight.w500,
                      color: isSelected
                          ? (isDark ? Colors.white : const Color(0xFF0F172A))
                          : (isDark ? Colors.white54 : const Color(0xFF64748B)),
                      letterSpacing: -0.2,
                    ),
                    child: Text(title),
                  ),
                ),
              ),
            );
          }),
        ),
      ),
    );

    const double navHeight = 48.0;
    Widget navWidget = baseNav;
    if (isLandscape) {
      final width = MediaQuery.of(context).size.width;
      final navWidth = (width * 0.62).clamp(360.0, 560.0).toDouble();
      navWidget = SizedBox(
        height: navHeight,
        child: Align(
          alignment: Alignment.centerLeft,
          child: SizedBox(width: navWidth, child: baseNav),
        ),
      );
    } else {
      navWidget = SizedBox(height: navHeight, child: navWidget);
    }

    if (!useGlass) return navWidget;

    return ValueListenableBuilder<Color?>(
      valueListenable: PlayerService().themeColorNotifier,
      builder: (context, extractedThemeColor, _) {
        final dynamicAccent = DynamicColorUtils.resolveAccent(
          extractedThemeColor,
          cs,
          isDark: isDark,
        );
        final dynamicAmbient = DynamicColorUtils.resolveAmbient(
          extractedThemeColor,
          cs,
          isDark: isDark,
        );

        return Theme(
          data: Theme.of(context).copyWith(
            navigationBarTheme: NavigationBarThemeData(
              height: 56.0,
              indicatorColor: Colors.transparent,
              backgroundColor: Colors.transparent,
              surfaceTintColor: Colors.transparent,
              elevation: 0,
              labelTextStyle: WidgetStateProperty.resolveWith((states) {
                if (states.contains(WidgetState.selected)) {
                  return TextStyle(
                    color: dynamicAccent,
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                  );
                }
                return TextStyle(
                  color: cs.onSurface.withValues(alpha: 0.6),
                  fontSize: 11,
                );
              }),
              iconTheme: WidgetStateProperty.resolveWith((states) {
                if (states.contains(WidgetState.selected)) {
                  return IconThemeData(color: dynamicAccent, size: 24);
                }
                return IconThemeData(
                  color: cs.onSurface.withValues(alpha: 0.6),
                  size: 24,
                );
              }),
            ),
          ),
          child: Container(
            decoration: BoxDecoration(
              color: Colors.transparent,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.08),
                  blurRadius: 24,
                  offset: const Offset(0, -6),
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(24),
              ),
              child: Stack(
                children: [
                  // 毛玻璃模糊层
                  Positioned.fill(
                    child: ClipRect(
                      child: BackdropFilter(
                        filter: ui.ImageFilter.blur(sigmaX: 30, sigmaY: 30),
                        child: const SizedBox.shrink(),
                      ),
                    ),
                  ),
                  // 液态玻璃渐变层（Apple Music 风格动态流光微光）
                  Positioned.fill(
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 400),
                      curve: Curves.easeOutCubic,
                      decoration: BoxDecoration(
                        color: cs.surface.withValues(
                          alpha: isDark ? 0.85 : 0.90,
                        ),
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            cs.surface.withValues(alpha: isDark ? 0.90 : 0.95),
                            dynamicAmbient.withValues(
                              alpha: isDark ? 0.16 : 0.08,
                            ),
                            dynamicAmbient.withValues(
                              alpha: isDark ? 0.08 : 0.04,
                            ),
                            cs.surface.withValues(alpha: isDark ? 0.84 : 0.88),
                          ],
                          stops: const [0.0, 0.35, 0.70, 1.0],
                        ),
                        border: Border(
                          top: BorderSide(
                            color: dynamicAccent.withValues(
                              alpha: isDark ? 0.28 : 0.38,
                            ),
                            width: 1.0,
                          ),
                        ),
                      ),
                    ),
                  ),
                  // Apple Music 风格有机弥散微光光晕 (Fluid Ambient Aura)
                  Positioned(
                    top: -30,
                    left: 16,
                    width: 220,
                    height: 120,
                    child: IgnorePointer(
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 400),
                        curve: Curves.easeOutCubic,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: RadialGradient(
                            colors: [
                              dynamicAmbient.withValues(
                                alpha: isDark ? 0.22 : 0.14,
                              ),
                              dynamicAmbient.withValues(
                                alpha: isDark ? 0.08 : 0.04,
                              ),
                              Colors.transparent,
                            ],
                            stops: const [0.0, 0.45, 1.0],
                          ),
                        ),
                      ),
                    ),
                  ),
                  // 高光微反光
                  Positioned.fill(
                    child: IgnorePointer(
                      ignoring: true,
                      child: Container(
                        decoration: const BoxDecoration(
                          gradient: RadialGradient(
                            center: Alignment(-0.9, -0.9),
                            radius: 1.2,
                            colors: [
                              Color(0x22FFFFFF),
                              Color(0x08FFFFFF),
                              Colors.transparent,
                            ],
                            stops: [0.0, 0.45, 1.0],
                          ),
                        ),
                      ),
                    ),
                  ),
                  // 整合 MiniPlayer + 导航栏 (一体化流光晶透底座)
                  AnimatedBuilder(
                    animation: PlayerService(),
                    builder: (context, _) {
                      final hasMiniPlayer =
                          PlayerService().currentTrack != null ||
                          PlayerService().currentSong != null;
                      return SafeArea(
                        top: false,
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            AnimatedSize(
                              duration: const Duration(milliseconds: 250),
                              curve: Curves.easeOutCubic,
                              child: hasMiniPlayer
                                  ? const MiniPlayer(transparent: true)
                                  : const SizedBox.shrink(),
                            ),
                            navWidget,
                          ],
                        ),
                      );
                    },
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildTabletNavigationDock(ColorScheme colorScheme) {
    final isLocalMode = PersistentStorageService().enableLocalMode;
    final items = isLocalMode
        ? const [
            FixedNavigationDockItem(
              icon: Icons.folder_open_outlined,
              selectedIcon: Icons.folder_rounded,
              label: '本地',
            ),
            FixedNavigationDockItem(
              icon: Icons.settings_outlined,
              selectedIcon: Icons.settings_rounded,
              label: '本地设置',
            ),
          ]
        : <FixedNavigationDockItem>[
            const FixedNavigationDockItem(
              icon: Icons.home_outlined,
              selectedIcon: Icons.home_rounded,
              label: '首页',
            ),
            const FixedNavigationDockItem(
              icon: Icons.explore_outlined,
              selectedIcon: Icons.explore_rounded,
              label: '发现',
            ),
            const FixedNavigationDockItem(
              icon: Icons.history_outlined,
              selectedIcon: Icons.history_rounded,
              label: '历史',
            ),
            const FixedNavigationDockItem(
              icon: Icons.folder_open_outlined,
              selectedIcon: Icons.folder_rounded,
              label: '本地',
            ),
            const FixedNavigationDockItem(
              icon: Icons.person_outline_rounded,
              selectedIcon: Icons.person_rounded,
              label: '我的',
            ),
            const FixedNavigationDockItem(
              icon: Icons.settings_outlined,
              selectedIcon: Icons.settings_rounded,
              label: '设置',
            ),
            if (DeveloperModeService().isDeveloperMode)
              const FixedNavigationDockItem(
                icon: Icons.code_rounded,
                selectedIcon: Icons.code_rounded,
                label: '开发',
              ),
          ];

    return FixedNavigationDock(
      items: items,
      selectedIndex: _selectedIndex,
      onSelected: _selectDesktopDestination,
      backgroundColor: colorScheme.surfaceContainerLow,
      selectedBackgroundColor: colorScheme.secondaryContainer,
      foregroundColor: colorScheme.onSurfaceVariant,
      selectedForegroundColor: colorScheme.onSecondaryContainer,
      dividerColor: colorScheme.outlineVariant,
    );
  }

  void _selectDesktopDestination(int index) {
    final isLocalMode = PersistentStorageService().enableLocalMode;
    if (!isLocalMode && index == _settingsIndex) {
      DeveloperModeService().onSettingsClicked();
    }
    setState(() => _selectedIndex = index);
    PageVisibilityNotifier().setCurrentPage(index);
  }

  /// 构建侧边导航抽屉（Material Design 3 NavigationDrawer）
  Widget _buildNavigationDrawer(ColorScheme colorScheme) {
    final bool isCollapsed = _isDrawerCollapsed;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeInOutCubic,
      width: isCollapsed ? _collapsedWidth : _drawerWidth,
      child: Column(
        children: [
          // 顶部折叠/展开按钮
          Padding(
            padding: const EdgeInsets.only(top: 8.0, left: 8.0, right: 8.0),
            child: Align(
              alignment: Alignment.centerLeft,
              child: IconButton(
                onPressed: () {
                  setState(() {
                    _isDrawerCollapsed = !_isDrawerCollapsed;
                  });
                },
                icon: AnimatedRotation(
                  turns: isCollapsed ? 0.0 : 0.5, // 旋转 180°
                  duration: const Duration(milliseconds: 200),
                  curve: Curves.easeInOut,
                  child: const Icon(Icons.chevron_left),
                ),
                tooltip: isCollapsed ? '展开' : '收起',
              ),
            ),
          ),
          Expanded(
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 200),
              switchInCurve: Curves.easeOutCubic,
              switchOutCurve: Curves.easeInCubic,
              transitionBuilder: (child, animation) =>
                  FadeTransition(opacity: animation, child: child),
              child: isCollapsed
                  ? KeyedSubtree(
                      key: const ValueKey('collapsed'),
                      child: _buildCollapsedDestinations(colorScheme),
                    )
                  : KeyedSubtree(
                      key: const ValueKey('expanded'),
                      child: Theme(
                        data: Theme.of(context).copyWith(
                          navigationDrawerTheme:
                              const NavigationDrawerThemeData(
                                backgroundColor: Colors.transparent,
                                surfaceTintColor: Colors.transparent,
                              ),
                        ),
                        child: NavigationDrawer(
                          selectedIndex: _selectedIndex,
                          onDestinationSelected: (int index) {
                            final isLocalMode =
                                PersistentStorageService().enableLocalMode;
                            StructuredLogService.log(
                              '🖱️ [MainLayout] NavigationDrawer index selected: $index (LocalMode: $isLocalMode)',
                            );

                            // 如果点击的是设置按钮，触发开发者模式检测
                            if (!isLocalMode && index == _settingsIndex) {
                              DeveloperModeService().onSettingsClicked();
                            }

                            setState(() {
                              _selectedIndex = index;
                              StructuredLogService.log(
                                '🔄 [MainLayout] _selectedIndex updated to: $_selectedIndex',
                              );
                            });
                            // 通知页面切换
                            PageVisibilityNotifier().setCurrentPage(index);
                          },
                          children: [
                            const SizedBox(height: 8),
                            if (PersistentStorageService().enableLocalMode) ...[
                              const NavigationDrawerDestination(
                                icon: Icon(Icons.folder_open),
                                selectedIcon: Icon(Icons.folder),
                                label: Text('本地'),
                              ),
                              const NavigationDrawerDestination(
                                icon: Icon(Icons.settings_outlined),
                                selectedIcon: Icon(Icons.settings),
                                label: Text('本地设置'),
                              ),
                            ] else ...[
                              const NavigationDrawerDestination(
                                icon: Icon(Icons.home_outlined),
                                selectedIcon: Icon(Icons.home),
                                label: Text('首页'),
                              ),
                              const NavigationDrawerDestination(
                                icon: Icon(Icons.explore_outlined),
                                selectedIcon: Icon(Icons.explore),
                                label: Text('发现'),
                              ),
                              const NavigationDrawerDestination(
                                icon: Icon(Icons.history_outlined),
                                selectedIcon: Icon(Icons.history),
                                label: Text('历史'),
                              ),
                              const NavigationDrawerDestination(
                                icon: Icon(Icons.folder_open),
                                selectedIcon: Icon(Icons.folder),
                                label: Text('本地'),
                              ),
                              const NavigationDrawerDestination(
                                icon: Icon(Icons.person_outlined),
                                selectedIcon: Icon(Icons.person),
                                label: Text('我的'),
                              ),
                              const NavigationDrawerDestination(
                                icon: Icon(Icons.settings_outlined),
                                selectedIcon: Icon(Icons.settings),
                                label: Text('设置'),
                              ),
                              if (DeveloperModeService().isDeveloperMode)
                                const NavigationDrawerDestination(
                                  icon: Icon(Icons.code),
                                  selectedIcon: Icon(Icons.code),
                                  label: Text('开发者'),
                                ),
                            ],
                          ],
                        ),
                      ),
                    ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCollapsedDestinations(ColorScheme colorScheme) {
    final isLocalMode = PersistentStorageService().enableLocalMode;

    final List<_CollapsedItem> items = isLocalMode
        ? [
            _CollapsedItem(
              icon: Icons.folder_open,
              selectedIcon: Icons.folder,
              label: '本地',
            ),
            _CollapsedItem(
              icon: Icons.settings_outlined,
              selectedIcon: Icons.settings,
              label: '本地设置',
            ),
          ]
        : [
            _CollapsedItem(
              icon: Icons.home_outlined,
              selectedIcon: Icons.home,
              label: '首页',
            ),
            _CollapsedItem(
              icon: Icons.explore_outlined,
              selectedIcon: Icons.explore,
              label: '发现',
            ),
            _CollapsedItem(
              icon: Icons.history_outlined,
              selectedIcon: Icons.history,
              label: '历史',
            ),
            _CollapsedItem(
              icon: Icons.folder_open,
              selectedIcon: Icons.folder,
              label: '本地',
            ),
            _CollapsedItem(
              icon: Icons.person_outlined,
              selectedIcon: Icons.person,
              label: '我的',
            ),
            _CollapsedItem(
              icon: Icons.settings_outlined,
              selectedIcon: Icons.settings,
              label: '设置',
            ),
          ];
    if (DeveloperModeService().isDeveloperMode) {
      items.add(
        _CollapsedItem(
          icon: Icons.code,
          selectedIcon: Icons.code,
          label: 'Dev',
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      itemCount: items.length,
      itemBuilder: (context, index) {
        final bool isSelected = _selectedIndex == index;
        final item = items[index];
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 4.0, horizontal: 8.0),
          child: Tooltip(
            message: item.label,
            child: Material(
              color: isSelected
                  ? colorScheme.primaryContainer
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(16),
              child: InkWell(
                borderRadius: BorderRadius.circular(16),
                onTap: () {
                  final isLocalMode =
                      PersistentStorageService().enableLocalMode;
                  StructuredLogService.log(
                    '🖱️ [MainLayout] Collapsed Drawer item selected: $index (LocalMode: $isLocalMode)',
                  );

                  if (!isLocalMode && index == _settingsIndex) {
                    DeveloperModeService().onSettingsClicked();
                  }

                  setState(() {
                    _selectedIndex = index;
                    StructuredLogService.log(
                      '🔄 [MainLayout] _selectedIndex updated via Collapsed Drawer to: $_selectedIndex',
                    );
                  });
                  PageVisibilityNotifier().setCurrentPage(index);
                },
                child: SizedBox(
                  height: 48,
                  child: Center(
                    child: Icon(
                      isSelected ? item.selectedIcon : item.icon,
                      color: isSelected
                          ? colorScheme.onPrimaryContainer
                          : colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _CollapsedItem {
  final IconData icon;
  final IconData selectedIcon;
  final String label;
  const _CollapsedItem({
    required this.icon,
    required this.selectedIcon,
    required this.label,
  });
}

/// iOS 26 风格悬浮 Tab 项目数据
class _FloatingTabItem {
  final String svgAsset;
  final String label;
  const _FloatingTabItem({required this.svgAsset, required this.label});
}

/// iOS 26 液态玻璃容器
/// 参考 Apple 的 Liquid Glass 设计语言
class _LiquidGlassContainer extends StatelessWidget {
  final Widget child;
  final double borderRadius;
  final double height;
  final bool isDark;

  const _LiquidGlassContainer({
    required this.child,
    required this.borderRadius,
    required this.height,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: height,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(borderRadius),
        // 外部阴影
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.5 : 0.15),
            blurRadius: 32,
            offset: const Offset(0, 12),
            spreadRadius: -4,
          ),
          // 底部环境光反射
          BoxShadow(
            color: ThemeManager.iosBlue.withValues(alpha: isDark ? 0.2 : 0.1),
            blurRadius: 24,
            offset: const Offset(0, 8),
            spreadRadius: -8,
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(borderRadius),
        child: BackdropFilter(
          // 极致背景模糊
          filter: ui.ImageFilter.blur(sigmaX: 60, sigmaY: 60),
          child: CustomPaint(
            painter: _LiquidGlassPainter(
              borderRadius: borderRadius,
              isDark: isDark,
            ),
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(borderRadius),
                // 半透明背景 - 增加噪点纹理感
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    (isDark ? const Color(0xFF3A3A3C) : Colors.white)
                        .withValues(alpha: isDark ? 0.6 : 0.5),
                    (isDark ? const Color(0xFF1C1C1E) : Colors.white)
                        .withValues(alpha: isDark ? 0.4 : 0.2),
                  ],
                ),
                // 边框由 Painter 绘制以实现渐变
              ),
              child: Stack(
                children: [
                  // 顶部高光
                  Positioned(
                    top: 0,
                    left: 0,
                    right: 0,
                    height: height / 2,
                    child: Container(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            Colors.white.withValues(alpha: isDark ? 0.1 : 0.4),
                            Colors.white.withValues(alpha: 0),
                          ],
                        ),
                        borderRadius: BorderRadius.vertical(
                          top: Radius.circular(borderRadius),
                        ),
                      ),
                    ),
                  ),
                  // 内容
                  child,
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 液态玻璃内阴影绘制器
class _LiquidGlassPainter extends CustomPainter {
  final double borderRadius;
  final bool isDark;

  _LiquidGlassPainter({required this.borderRadius, required this.isDark});

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Rect.fromLTWH(0, 0, size.width, size.height);
    final rrect = RRect.fromRectAndRadius(rect, Radius.circular(borderRadius));

    // 1. 绘制细腻的边框 (渐变)
    final borderPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0
      ..shader = LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          Colors.white.withValues(alpha: isDark ? 0.3 : 0.8),
          Colors.white.withValues(alpha: isDark ? 0.05 : 0.1),
          Colors.white.withValues(alpha: isDark ? 0.05 : 0.1),
          Colors.white.withValues(alpha: isDark ? 0.2 : 0.4),
        ],
        stops: const [0.0, 0.4, 0.6, 1.0],
      ).createShader(rect);

    canvas.drawRRect(rrect.deflate(0.5), borderPaint);

    // 2. 绘制内部反光 (Inset Light)
    final innerGlowPaint = Paint()
      ..shader = RadialGradient(
        center: const Alignment(0, -0.8),
        radius: 1.0,
        colors: [
          Colors.white.withValues(alpha: isDark ? 0.1 : 0.2),
          Colors.transparent,
        ],
        stops: const [0.0, 0.7],
      ).createShader(rect);

    canvas.save();
    canvas.clipRRect(rrect);
    canvas.drawRect(rect, innerGlowPaint);
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _LiquidGlassPainter oldDelegate) {
    return oldDelegate.isDark != isDark ||
        oldDelegate.borderRadius != borderRadius;
  }
}
