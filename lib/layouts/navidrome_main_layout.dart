import 'dart:io';
import 'package:flutter/material.dart';
import '../pages/navidrome_library_page.dart';
import '../pages/navidrome_search_page.dart';
import '../pages/navidrome_playlists_page.dart';
import '../pages/navidrome_settings_page.dart';
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

  List<Widget> get _pages => [
        NavidromeLibraryPage(
          key: const PageStorageKey('navidrome_library'),
          onSearchTap: () => _setSelectedIndex(1),
        ),
        const NavidromeSearchPage(key: PageStorageKey('navidrome_search')),
        const NavidromePlaylistsPage(key: PageStorageKey('navidrome_playlists')),
        const NavidromeSettingsPage(key: PageStorageKey('navidrome_settings')),
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
    final bottomBarColor = navTheme.bottomBarBackground;
    final bottomBarBorderColor = navTheme.bottomBarBorder;
    const activeColor = NavidromeColors.activeBlue;
    final inactiveColor = navTheme.textSecondary;

    return Scaffold(
      backgroundColor: backgroundColor,
      body: AnimatedBuilder(
        animation: PlayerService(),
        builder: (context, _) {
          final hasMiniPlayer = PlayerService().currentTrack != null ||
              PlayerService().currentSong != null;
          final bottomInset = 44 +
              MediaQuery.of(context).padding.bottom +
              (hasMiniPlayer ? 64 : 0);

          return Stack(
            children: [
              // Main Content
              Positioned.fill(
                bottom: bottomInset,
                child: IndexedStack(
                  index: _selectedIndex,
                  children: _pages,
                ),
              ),

              // Mini Player & Bottom Bar Area
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _buildMiniPlayer(),
                    // Custom Bottom Navigation Bar
                    Container(
                      height: 44 + MediaQuery.of(context).padding.bottom,
                      decoration: BoxDecoration(
                        color: bottomBarColor,
                        border: Border(
                          top: BorderSide(color: bottomBarBorderColor, width: 0.5),
                        ),
                      ),
                      child: Padding(
                        padding: EdgeInsets.only(
                          bottom: MediaQuery.of(context).padding.bottom,
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceAround,
                          children: [
                            _buildNavItem(0, Icons.library_music, '音乐库', activeColor, inactiveColor),
                            _buildNavItem(1, Icons.search, '搜索', activeColor, inactiveColor),
                            _buildNavItem(2, Icons.favorite, '收藏', activeColor, inactiveColor),
                            _buildNavItem(3, Icons.settings, '设置', activeColor, inactiveColor),
                          ],
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
    );
  }

  Widget _buildNavItem(
    int index,
    IconData icon,
    String label,
    Color activeColor,
    Color inactiveColor,
  ) {
    final isSelected = _selectedIndex == index;
    return Expanded(
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => setState(() => _selectedIndex = index),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              size: 24,
              color: isSelected ? activeColor : inactiveColor,
            ),
            const SizedBox(height: 2),
            Text(
              label,
              style: TextStyle(
                fontSize: 10,
                color: isSelected ? activeColor : inactiveColor,
                fontWeight: isSelected ? FontWeight.w500 : FontWeight.normal,
              ),
            ),
          ],
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
