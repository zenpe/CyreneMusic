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
    return Scaffold(
      body: Stack(
        children: [
          IndexedStack(
            index: _selectedIndex,
            children: _pages,
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: kBottomNavigationBarHeight,
            child: _buildMiniPlayer(),
          ),
        ],
      ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _selectedIndex,
        onTap: (index) {
          setState(() {
            _selectedIndex = index;
          });
        },
        items: const [
          BottomNavigationBarItem(
            icon: Icon(Icons.library_music_outlined),
            activeIcon: Icon(Icons.library_music),
            label: '音乐库',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.search_outlined),
            activeIcon: Icon(Icons.search),
            label: '搜索',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.queue_music_outlined),
            activeIcon: Icon(Icons.queue_music),
            label: '歌单',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.settings_outlined),
            activeIcon: Icon(Icons.settings),
            label: '设置',
          ),
        ],
        type: BottomNavigationBarType.fixed,
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
