import 'dart:io';
import 'package:flutter/material.dart';
import '../pages/navidrome_library_page.dart';
import '../pages/navidrome_search_page.dart';
import '../pages/navidrome_playlists_page.dart';
import '../pages/navidrome_settings_page.dart';
import '../services/player_service.dart';
import '../widgets/mini_player.dart';

class NavidromeMainLayout extends StatefulWidget {
  const NavidromeMainLayout({super.key});

  @override
  State<NavidromeMainLayout> createState() => _NavidromeMainLayoutState();
}

class _NavidromeMainLayoutState extends State<NavidromeMainLayout> {
  int _selectedIndex = 0;

  List<Widget> get _pages => const [
        NavidromeLibraryPage(),
        NavidromeSearchPage(),
        NavidromePlaylistsPage(),
        NavidromeSettingsPage(),
      ];

  bool get _isDesktop =>
      Platform.isWindows || Platform.isMacOS || Platform.isLinux;

  @override
  Widget build(BuildContext context) {
    return _isDesktop ? _buildDesktop(context) : _buildMobile(context);
  }

  Widget _buildDesktop(BuildContext context) {
    return Scaffold(
      body: Column(
        children: [
          Expanded(
            child: Row(
              children: [
                NavigationRail(
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
                const VerticalDivider(width: 1),
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

  Widget _buildMobile(BuildContext context) {
    // Navidrome Scheme B Design Colors
    const backgroundColor = Color(0xFF0A0A0A);
    const bottomBarColor = Color(0xFF0F0F0F);
    const bottomBarBorderColor = Color(0xFF2C2C2E);
    const activeColor = Color(0xFF0A84FF);
    const inactiveColor = Color(0xFF8E8E93);

    return Scaffold(
      backgroundColor: backgroundColor,
      body: Stack(
        children: [
          // Main Content
          Positioned.fill(
            bottom: 44 + MediaQuery.of(context).padding.bottom + 64, // TabBar + Safe Area + MiniPlayer
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
                  decoration: const BoxDecoration(
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
