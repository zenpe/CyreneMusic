import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../pages/navidrome_library_page.dart';
import '../pages/navidrome_search_page.dart';
import '../pages/navidrome_playlists_page.dart';
import '../pages/settings_page.dart';
import '../services/player_service.dart';
import '../services/navidrome_session_service.dart';
import '../widgets/mini_player.dart';
import '../widgets/navidrome_ui.dart';

class NavidromeMainLayout extends StatefulWidget {
  const NavidromeMainLayout({super.key});

  @override
  State<NavidromeMainLayout> createState() => _NavidromeMainLayoutState();
}

class _NavidromeMainLayoutState extends State<NavidromeMainLayout> {
  int _selectedIndex = 0;
  static const double _landscapeRailWidth = 84.0;

  List<Widget> get _pages => [
        NavidromeLibraryPage(
          key: const PageStorageKey('navidrome_library'),
          onSearchTap: () => _setSelectedIndex(1),
        ),
        const NavidromeSearchPage(key: PageStorageKey('navidrome_search')),
        const NavidromePlaylistsPage(key: PageStorageKey('navidrome_playlists')),
        SettingsPage(
          key: const PageStorageKey('navidrome_settings'),
          initialSubPage: SettingsSubPage.audioSource,
          isActive: _selectedIndex == 3,
        ),
      ];

  bool get _isDesktop =>
      Platform.isWindows || Platform.isMacOS || Platform.isLinux;

  @override
  Widget build(BuildContext context) {
    return _isDesktop ? _buildDesktop(context) : _buildMobile(context);
  }

  void _setSelectedIndex(int index) {
    if (_selectedIndex == index) return;
    setState(() {
      _selectedIndex = index;
    });
  }

  Widget _buildDesktop(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    final useFullSidebar = width >= NavidromeLayout.desktopWidth;
    final navTheme = NavidromeTheme.of(context);

    return Scaffold(
      backgroundColor: navTheme.background,
      body: Column(
        children: [
          Expanded(
            child: Row(
              children: [
                if (useFullSidebar)
                  _buildFullSidebar(context)
                else
                  _buildNavigationRail(context),
                VerticalDivider(width: 1, color: navTheme.divider),
                Expanded(
                  child: IndexedStack(
                    index: _selectedIndex,
                    children: _pages,
                  ),
                ),
              ],
            ),
          ),
          _buildMiniPlayer(),
        ],
      ),
    );
  }

  /// 完整侧边栏（宽屏桌面端）
  Widget _buildFullSidebar(BuildContext context) {
    final theme = Theme.of(context);
    final navTheme = NavidromeTheme.of(context);
    final backgroundColor = navTheme.isDark ? const Color(0xFF0F0F0F) : navTheme.background;
    final borderColor = navTheme.isDark ? NavidromeColors.cardBorder : navTheme.divider;

    return Container(
      width: 220,
      decoration: BoxDecoration(
        color: backgroundColor,
        border: Border(
          right: BorderSide(color: borderColor, width: 0.5),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Logo / 标题区域
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
            child: Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: NavidromeColors.activeBlue,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(
                    Icons.music_note,
                    color: Colors.white,
                    size: 22,
                  ),
                ),
                const SizedBox(width: 12),
                Text(
                  'Navidrome',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: navTheme.textPrimary,
                  ),
                ),
              ],
            ),
          ),

          Divider(height: 1, color: navTheme.divider),

          // 导航项
          Expanded(
            child: ListView(
              padding: const EdgeInsets.symmetric(vertical: 8),
              children: [
                _buildSidebarSection('浏览'),
                _buildSidebarItem(
                  index: 0,
                  icon: Icons.library_music,
                  label: '音乐库',
                ),
                _buildSidebarItem(
                  index: 1,
                  icon: Icons.search,
                  label: '搜索',
                ),
                _buildSidebarItem(
                  index: 2,
                  icon: Icons.queue_music,
                  label: '歌单',
                ),

                const SizedBox(height: 16),
                _buildSidebarSection('智能列表'),
                _buildSidebarItem(
                  index: 0,
                  icon: Icons.shuffle,
                  label: '随机发现',
                  badge: null,
                  onTap: () => _navigateToSmartList('random'),
                ),
                _buildSidebarItem(
                  index: 0,
                  icon: Icons.trending_up,
                  label: '最常播放',
                  badge: null,
                  onTap: () => _navigateToSmartList('frequent'),
                ),
                _buildSidebarItem(
                  index: 0,
                  icon: Icons.schedule,
                  label: '最近添加',
                  badge: null,
                  onTap: () => _navigateToSmartList('newest'),
                ),

                const SizedBox(height: 16),
                _buildSidebarSection('系统'),
                _buildSidebarItem(
                  index: 3,
                  icon: Icons.settings,
                  label: '设置',
                ),
              ],
            ),
          ),

          // 底部服务器状态
          _buildServerStatus(context),
        ],
      ),
    );
  }

  Widget _buildSidebarSection(String title) {
    final theme = Theme.of(context);
    final navTheme = NavidromeTheme.of(context);

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 4),
      child: Text(
        title,
        style: theme.textTheme.labelSmall?.copyWith(
          color: navTheme.textTertiary,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.5,
        ),
      ),
    );
  }

  Widget _buildSidebarItem({
    required int index,
    required IconData icon,
    required String label,
    String? badge,
    VoidCallback? onTap,
  }) {
    final theme = Theme.of(context);
    final navTheme = NavidromeTheme.of(context);
    final isSelected = onTap == null && _selectedIndex == index;

    final backgroundColor = isSelected
        ? NavidromeColors.activeBlue.withValues(alpha: navTheme.isDark ? 0.15 : 0.1)
        : Colors.transparent;
    final foregroundColor = isSelected
        ? NavidromeColors.activeBlue
        : navTheme.textPrimary;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
      child: Material(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          onTap: onTap ?? () => setState(() => _selectedIndex = index),
          borderRadius: BorderRadius.circular(8),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Row(
              children: [
                Icon(icon, size: 20, color: foregroundColor),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    label,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: foregroundColor,
                      fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
                    ),
                  ),
                ),
                if (badge != null)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: navTheme.isDark ? NavidromeColors.cardBackground : NavidromeColors.lightCardBackground,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      badge,
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: navTheme.textSecondary,
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

  Widget _buildServerStatus(BuildContext context) {
    final theme = Theme.of(context);
    final navTheme = NavidromeTheme.of(context);
    final session = NavidromeSessionService();
    final isConnected = session.api != null;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(
            color: navTheme.divider,
            width: 0.5,
          ),
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              color: isConnected ? Colors.green : Colors.red,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  isConnected ? '已连接' : '未连接',
                  style: theme.textTheme.bodySmall?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                if (isConnected && session.baseUrl.isNotEmpty)
                  Text(
                    Uri.tryParse(session.baseUrl)?.host ?? session.baseUrl,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: navTheme.textTertiary,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _navigateToSmartList(String type) {
    // TODO: 实现智能列表导航
    // 可以通过传递参数到 NavidromeLibraryPage 或创建新页面
    setState(() => _selectedIndex = 0);
  }

  /// NavigationRail（平板端）
  Widget _buildNavigationRail(BuildContext context) {
    final navTheme = NavidromeTheme.of(context);

    return Container(
      color: navTheme.background,
      child: NavigationRail(
        backgroundColor: navTheme.background,
        selectedIndex: _selectedIndex,
        onDestinationSelected: (index) {
          setState(() {
            _selectedIndex = index;
          });
        },
        labelType: NavigationRailLabelType.selected,
        destinations: const [
          NavigationRailDestination(
            icon: Icon(Icons.library_music_outlined),
            selectedIcon: Icon(Icons.library_music),
            label: Text('音乐库'),
          ),
          NavigationRailDestination(
            icon: Icon(Icons.search_outlined),
            selectedIcon: Icon(Icons.search),
            label: Text('搜索'),
          ),
          NavigationRailDestination(
            icon: Icon(Icons.queue_music_outlined),
            selectedIcon: Icon(Icons.queue_music),
            label: Text('歌单'),
          ),
          NavigationRailDestination(
            icon: Icon(Icons.settings_outlined),
            selectedIcon: Icon(Icons.settings),
            label: Text('设置'),
          ),
        ],
      ),
    );
  }

  Widget _buildMobile(BuildContext context) {
    final navTheme = NavidromeTheme.of(context);
    final backgroundColor = navTheme.background;
    final orientation = MediaQuery.of(context).orientation;
    final bool isLandscape = orientation == Orientation.landscape;
    final scaffold = isLandscape
        ? Scaffold(
            backgroundColor: backgroundColor,
            body: Row(
              children: [
                _buildLandscapeSideNavigation(context),
                Expanded(
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      return Stack(
                        children: [
                          Positioned.fill(
                            child: IndexedStack(
                              index: _selectedIndex,
                              children: _pages,
                            ),
                          ),
                          Positioned(
                            left: 0,
                            right: 0,
                            bottom: 0,
                            child: _buildMiniPlayer(),
                          ),
                        ],
                      );
                    },
                  ),
                ),
              ],
            ),
          )
        : Scaffold(
            backgroundColor: backgroundColor,
            body: Stack(
              children: [
                Positioned.fill(
                  child: IndexedStack(
                    index: _selectedIndex,
                    children: _pages,
                  ),
                ),
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  child: _buildMiniPlayer(),
                ),
              ],
            ),
            bottomNavigationBar: _buildGlassBottomNavigationBar(context),
          );

    if (!Platform.isAndroid) {
      return scaffold;
    }

    return AnimatedBuilder(
      animation: PlayerService(),
      builder: (context, child) {
        final theme = Theme.of(context);
        final isDark = theme.brightness == Brightness.dark;
        final hasPlayback = PlayerService().currentTrack != null ||
            PlayerService().currentSong != null;
        final navColor = hasPlayback ? Colors.transparent : theme.colorScheme.surface;
        return AnnotatedRegion<SystemUiOverlayStyle>(
          value: SystemUiOverlayStyle(
            statusBarColor: Colors.transparent,
            statusBarIconBrightness:
                isDark ? Brightness.light : Brightness.dark,
            statusBarBrightness: isDark ? Brightness.dark : Brightness.light,
            systemNavigationBarColor: navColor,
            systemNavigationBarDividerColor: navColor,
            systemNavigationBarIconBrightness:
                isDark ? Brightness.light : Brightness.dark,
          ),
          child: child!,
        );
      },
      child: scaffold,
    );
  }

  Widget _buildLandscapeSideNavigation(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final Color? themeTint = PlayerService().themeColorNotifier.value;

    return SafeArea(
      left: true,
      right: false,
      top: true,
      bottom: true,
      child: SizedBox(
        width: _landscapeRailWidth,
        child: ClipRRect(
          borderRadius: const BorderRadius.only(
            topRight: Radius.circular(16),
            bottomRight: Radius.circular(16),
          ),
          child: Stack(
            children: [
              Positioned.fill(
                child: BackdropFilter(
                  filter: ui.ImageFilter.blur(sigmaX: 18, sigmaY: 18),
                  child: const SizedBox.shrink(),
                ),
              ),
              Positioned.fill(
                child: Container(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        Colors.white.withOpacity(0.24),
                        (themeTint ?? colorScheme.primary).withOpacity(0.08),
                        Colors.white.withOpacity(0.06),
                      ],
                    ),
                    border: Border(
                      right: BorderSide(
                        color: Colors.white.withOpacity(0.18),
                        width: 1,
                      ),
                    ),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.only(top: 6, bottom: 6),
                child: NavigationRail(
                  backgroundColor: Colors.transparent,
                  selectedIndex: _selectedIndex,
                  labelType: NavigationRailLabelType.selected,
                  groupAlignment: -0.95,
                  minWidth: _landscapeRailWidth,
                  minExtendedWidth: _landscapeRailWidth,
                  selectedIconTheme: IconThemeData(
                    color: colorScheme.primary,
                    size: 22,
                  ),
                  unselectedIconTheme: IconThemeData(
                    color: colorScheme.onSurfaceVariant,
                    size: 22,
                  ),
                  selectedLabelTextStyle: TextStyle(
                    color: colorScheme.primary,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                  unselectedLabelTextStyle: TextStyle(
                    color: colorScheme.onSurfaceVariant,
                    fontSize: 11,
                  ),
                  onDestinationSelected: (index) {
                    setState(() => _selectedIndex = index);
                  },
                  destinations: const [
                    NavigationRailDestination(
                      icon: Icon(Icons.library_music_outlined),
                      selectedIcon: Icon(Icons.library_music),
                      label: Text('音乐库'),
                    ),
                    NavigationRailDestination(
                      icon: Icon(Icons.search_outlined),
                      selectedIcon: Icon(Icons.search),
                      label: Text('搜索'),
                    ),
                    NavigationRailDestination(
                      icon: Icon(Icons.queue_music_outlined),
                      selectedIcon: Icon(Icons.queue_music),
                      label: Text('歌单'),
                    ),
                    NavigationRailDestination(
                      icon: Icon(Icons.settings_outlined),
                      selectedIcon: Icon(Icons.settings),
                      label: Text('设置'),
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

  Widget _buildGlassBottomNavigationBar(BuildContext context) {
    final orientation = MediaQuery.of(context).orientation;
    final bool useGlass = Platform.isAndroid || orientation == Orientation.portrait;

    final destinations = const [
      NavigationDestination(
        icon: Icon(Icons.library_music_outlined),
        selectedIcon: Icon(Icons.library_music),
        label: '音乐库',
      ),
      NavigationDestination(
        icon: Icon(Icons.search_outlined),
        selectedIcon: Icon(Icons.search),
        label: '搜索',
      ),
      NavigationDestination(
        icon: Icon(Icons.favorite_outline),
        selectedIcon: Icon(Icons.favorite),
        label: '收藏',
      ),
      NavigationDestination(
        icon: Icon(Icons.settings_outlined),
        selectedIcon: Icon(Icons.settings),
        label: '设置',
      ),
    ];

    final baseNav = NavigationBar(
      selectedIndex: _selectedIndex,
      onDestinationSelected: (int index) {
        if (_selectedIndex == index) return;
        setState(() => _selectedIndex = index);
      },
      destinations: destinations,
    );
 
    if (!useGlass) return baseNav;

    final cs = Theme.of(context).colorScheme;
    final Color? themeTint = PlayerService().themeColorNotifier.value;
    return Theme(
      data: Theme.of(context).copyWith(
        navigationBarTheme: const NavigationBarThemeData(
          backgroundColor: Colors.transparent,
          surfaceTintColor: Colors.transparent,
          elevation: 0,
        ),
      ),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.transparent,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.08),
              blurRadius: 12,
              offset: const Offset(0, -2),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.zero,
          child: Stack(
            children: [
              Positioned.fill(
                child: ClipRect(
                  child: BackdropFilter(
                    filter: ui.ImageFilter.blur(sigmaX: 20, sigmaY: 20),
                    child: const SizedBox.shrink(),
                  ),
                ),
              ),
              Positioned.fill(
                child: Container(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        Colors.white.withOpacity(0.16),
                        (themeTint ?? cs.primary).withOpacity(0.10),
                        Colors.white.withOpacity(0.05),
                      ],
                      stops: const [0.0, 0.45, 1.0],
                    ),
                    border: Border(
                      top: BorderSide(
                        color: Colors.white.withOpacity(0.18),
                        width: 1,
                      ),
                    ),
                  ),
                ),
              ),
              Positioned.fill(
                child: IgnorePointer(
                  ignoring: true,
                  child: Container(
                    decoration: const BoxDecoration(
                      gradient: RadialGradient(
                        center: Alignment(-0.9, -0.9),
                        radius: 1.2,
                        colors: [
                          Color(0x33FFFFFF),
                          Color(0x0AFFFFFF),
                          Colors.transparent,
                        ],
                        stops: [0.0, 0.45, 1.0],
                      ),
                    ),
                  ),
                ),
              ),
              baseNav,
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMiniPlayer() {
    return AnimatedBuilder(
      animation: PlayerService(),
      builder: (context, _) {
        final hasMiniPlayer = PlayerService().currentTrack != null ||
            PlayerService().currentSong != null;
        if (!hasMiniPlayer) return const SizedBox.shrink();
        return const MiniPlayer();
      },
    );
  }
}
