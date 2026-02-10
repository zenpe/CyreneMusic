import 'package:fluent_ui/fluent_ui.dart' as fluent;
import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../models/track.dart';
import '../models/merged_track.dart';
import '../services/search_service.dart';
import '../services/developer_mode_service.dart';
import '../services/netease_artist_service.dart';
import '../pages/artist_detail_page.dart';
import '../pages/album_detail_page.dart';
import '../services/player_service.dart';
import '../services/auth_service.dart';
import '../pages/auth/auth_page.dart';
import '../utils/theme_manager.dart';
import 'track_action_menu.dart';

/// 平台配色映射 - 使用品牌相关色系的小球代替文字
/// 用于规避直接显示平台名称的风险
Color _getPlatformDotColor(String platformCode, Brightness brightness) {
  switch (platformCode) {
    case 'netease':
      return const Color(0xFFE72D2D); // 红色
    case 'qq':
      return const Color(0xFF31C27C); // 绿色
    case 'kugou':
      return const Color(0xFF00A9FF); // 蓝色
    case 'kuwo':
      return const Color(0xFFFFD800); // 黄色
    case 'apple':
      return brightness == Brightness.dark ? Colors.white : Colors.black;
    case 'spotify':
      return const Color(0xFF1DB954); // Spotify 绿色
    default:
      return brightness == Brightness.dark ? Colors.white70 : Colors.black54;
  }
}

/// 判断是否为平台tab（非歌手/歌曲等功能tab）
bool _isPlatformTab(String tab) {
  return tab == 'netease' || tab == 'qq' || tab == 'kugou' || 
         tab == 'kuwo' || tab == 'apple' || tab == 'spotify' ||
         tab.contains('网易云') || tab.contains('QQ') || tab.contains('酷狗') ||
         tab.contains('酷我') || tab.contains('Apple') || tab.contains('Spotify');
}

/// 从显示名称获取平台代码
String _getPlatformCodeFromLabel(String label) {
  if (label.contains('网易云')) return 'netease';
  if (label.contains('Apple')) return 'apple';
  if (label.contains('QQ')) return 'qq';
  if (label.contains('酷狗')) return 'kugou';
  if (label.contains('酷我')) return 'kuwo';
  if (label.contains('Spotify')) return 'spotify';
  return '';
}


/// 搜索组件（内嵌版本）
class SearchWidget extends StatefulWidget {
  final VoidCallback onClose;
  final String? initialKeyword; // 初始搜索关键词

  const SearchWidget({super.key, required this.onClose, this.initialKeyword});

  @override
  State<SearchWidget> createState() => _SearchWidgetState();
}


/// Material Design Expressive 风格的 Tab 栏
/// 平台tab使用彩色小球，功能tab（如歌手）保留文字
class _SearchExpressiveTabs extends StatelessWidget {
  final List<String> tabs;
  final int currentIndex;
  final ValueChanged<int> onChanged;

  const _SearchExpressiveTabs({
    required this.tabs,
    required this.currentIndex,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final brightness = Theme.of(context).brightness;
    
    // 品牌配色映射
    Color getPlatformColor(String tab) {
      final code = _getPlatformCodeFromLabel(tab);
      if (code.isNotEmpty) {
        return _getPlatformDotColor(code, brightness);
      }
      // 非平台tab使用主题色
      return cs.primary;
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final count = tabs.length;
        if (count == 0) return const SizedBox.shrink();
        
        final totalWidth = constraints.maxWidth;
        final tabWidth = totalWidth / count;
        const height = 56.0;

        return SizedBox(
          height: height,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              // 底部指示器
              AnimatedPositioned(
                duration: const Duration(milliseconds: 500),
                curve: Curves.fastOutSlowIn,
                bottom: 4,
                left: currentIndex * tabWidth + (tabWidth - 28) / 2,
                width: 28,
                height: 4,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 300),
                  decoration: BoxDecoration(
                    color: getPlatformColor(tabs[currentIndex]),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              // Tab 标签
              Row(
                children: List.generate(count, (i) {
                  final selected = i == currentIndex;
                  final platformColor = getPlatformColor(tabs[i]);
                  final isPlatform = _isPlatformTab(tabs[i]);
                  
                  return Expanded(
                    child: GestureDetector(
                      onTap: () => onChanged(i),
                      behavior: HitTestBehavior.opaque,
                      child: Container(
                        alignment: Alignment.center,
                        child: isPlatform 
                          // 平台tab：显示彩色小球
                          ? AnimatedContainer(
                              duration: const Duration(milliseconds: 250),
                              curve: Curves.easeOutCubic,
                              width: selected ? 20 : 14,
                              height: selected ? 20 : 14,
                              decoration: BoxDecoration(
                                color: platformColor.withOpacity(selected ? 1.0 : 0.5),
                                shape: BoxShape.circle,
                                boxShadow: selected ? [
                                  BoxShadow(
                                    color: platformColor.withOpacity(0.4),
                                    blurRadius: 8,
                                    spreadRadius: 1,
                                  ),
                                ] : null,
                              ),
                            )
                          // 功能tab（如歌手）：显示文字
                          : AnimatedDefaultTextStyle(
                              duration: const Duration(milliseconds: 250),
                              curve: Curves.easeOutCubic,
                              style: TextStyle(
                                color: selected ? (brightness == Brightness.dark ? Colors.white : Colors.black87) : cs.onSurface.withOpacity(0.5),
                                fontSize: selected ? 19 : 15,
                                fontWeight: selected ? FontWeight.w900 : FontWeight.w600,
                                letterSpacing: selected ? -0.2 : 0,
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









/// 滑动指示器组件 - 通过测量文字宽度来计算位置


class _SearchWidgetState extends State<SearchWidget> {
  final TextEditingController _searchController = TextEditingController();
  final SearchService _searchService = SearchService();
  int _currentTabIndex = 0;
  final ThemeManager _themeManager = ThemeManager();

  bool get _isFluent => _themeManager.isFluentFramework;
  bool get _isCupertino => _themeManager.isCupertinoFramework;

  // 歌手搜索状态
  List<NeteaseArtistBrief> _artistResults = [];
  bool _artistLoading = false;
  String? _artistError;
  // 二级页面（面包屑）状态
  int? _secondaryArtistId;
  String? _secondaryArtistName;
  int? _secondaryAlbumId;
  String? _secondaryAlbumName;

  @override
  void initState() {
    super.initState();
    _searchService.addListener(_onSearchResultChanged);
    DeveloperModeService().addListener(_onSearchResultChanged);

    // 如果有初始关键词，自动填充并搜索
    if (widget.initialKeyword != null && widget.initialKeyword!.isNotEmpty) {
      _searchController.text = widget.initialKeyword!;
      // 延迟执行搜索，确保 UI 已经构建完成
      Future.delayed(const Duration(milliseconds: 100), () {
        if (mounted) {
          _performSearch();
        }
      });
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    _searchService.removeListener(_onSearchResultChanged);
    DeveloperModeService().removeListener(_onSearchResultChanged);
    super.dispose();
  }

  void _onSearchResultChanged() {
    if (mounted) {
      setState(() {});
    }
  }

  /// 检查登录状态，如果未登录则跳转到登录页面
  /// 返回 true 表示已登录或登录成功，返回 false 表示未登录或取消登录
  Future<bool> _checkLoginStatus() async {
    if (AuthService().isLoggedIn) {
      return true;
    }

    // 显示提示并询问是否要登录
    bool? shouldLogin;
    
    if (_isFluent) {
      shouldLogin = await fluent.showDialog<bool>(
        context: context,
        builder: (context) => fluent.ContentDialog(
          title: const Text('需要登录'),
          content: const Text('此功能需要登录后才能使用，是否前往登录？'),
          actions: [
            fluent.Button(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('取消'),
            ),
            fluent.FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('去登录'),
            ),
          ],
        ),
      );
    } else if (_isCupertino) {
      shouldLogin = await showCupertinoDialog<bool>(
        context: context,
        builder: (context) => CupertinoAlertDialog(
          title: const Text('需要登录'),
          content: const Text('此功能需要登录后才能使用，是否前往登录？'),
          actions: [
            CupertinoDialogAction(
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
    } else {
      shouldLogin = await showDialog<bool>(
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
    }

    if (shouldLogin == true && mounted) {
      // 跳转到登录页面
      final result = await showAuthDialog(context);

      // 返回登录是否成功
      return result == true && AuthService().isLoggedIn;
    }

    return false;
  }

  void _performSearch() async {
    // 检查登录状态
    final isLoggedIn = await _checkLoginStatus();
    if (!isLoggedIn) return;

    final keyword = _searchController.text.trim();
    if (keyword.isNotEmpty) {
      _searchService.search(keyword);
      
      final isMergeEnabled = DeveloperModeService().isSearchResultMergeEnabled;
      // 合并模式: 歌手索引为 1，分平台模式: 歌手索引为平台数量
      final artistTabIndex = isMergeEnabled ? 1 : _getSupportedPlatformCodes().length;
      final isArtistTab = _currentTabIndex == artistTabIndex;
      
      if (isArtistTab) {
        _searchArtists(keyword);
      }
    }
  }

  void _triggerArtistSearchIfNeeded() {
    final keyword = _searchController.text.trim();
    if (keyword.isNotEmpty) {
      _searchArtists(keyword);
    }
  }

  void _handleTabChanged(int index) {
    final isMergeEnabled = DeveloperModeService().isSearchResultMergeEnabled;
    // 合并模式: 歌手索引为 1，分平台模式: 歌手索引为平台数量
    final artistTabIndex = isMergeEnabled ? 1 : _getSupportedPlatformCodes().length;
    final isArtistTab = index == artistTabIndex;
    
    if (_currentTabIndex == index) {
      if (isArtistTab) {
        _triggerArtistSearchIfNeeded();
      }
      return;
    }

    setState(() {
      _currentTabIndex = index;
    });

    if (isArtistTab) {
      _triggerArtistSearchIfNeeded();
    }
  }

  Future<void> _searchArtists(String keyword) async {
    setState(() {
      _artistLoading = true;
      _artistError = null;
      _artistResults = [];
    });
    try {
      final results = await NeteaseArtistDetailService().searchArtists(
        keyword,
        limit: 20,
      );
      if (!mounted) return;
      setState(() {
        _artistResults = results;
        _artistLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _artistLoading = false;
        _artistError = e.toString();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final searchResult = _searchService.searchResult;
    if (_isFluent) {
      return _buildFluentSearch(context, searchResult);
    }
    if (_isCupertino) {
      return _buildCupertinoSearch(context, searchResult);
    }
    return _buildMaterialSearch(context, searchResult);
  }

  Widget _buildMaterialSearch(BuildContext context, SearchResult searchResult) {
    final colorScheme = Theme.of(context).colorScheme;

    return SafeArea(
      bottom: false,
      child: Stack(
        children: [
          Positioned.fill(
            child: Column(
              children: [
                // 搜索栏
                Container(
                  padding: const EdgeInsets.fromLTRB(12, 16, 16, 16),
                  decoration: BoxDecoration(
                    color: colorScheme.surface,
                  ),
                  child: Row(
                    children: [
                      IconButton(
                        icon: const Icon(Icons.arrow_back_ios_new, size: 20),
                        onPressed: widget.onClose,
                        tooltip: '返回',
                        padding: EdgeInsets.zero,
                      ),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Container(
                          height: 52,
                          decoration: BoxDecoration(
                            color: colorScheme.surfaceContainerHighest.withOpacity(0.5),
                            borderRadius: BorderRadius.circular(26),
                          ),
                          child: TextField(
                            controller: _searchController,
                            autofocus: true,
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w500,
                            ),
                            decoration: InputDecoration(
                              hintText: '搜索歌曲、歌手...',
                              hintStyle: TextStyle(
                                color: colorScheme.onSurfaceVariant.withOpacity(0.6),
                                fontSize: 16,
                              ),
                              prefixIcon: Icon(
                                Icons.search,
                                color: colorScheme.primary.withOpacity(0.7),
                                size: 22,
                              ),
                              suffixIcon: _searchController.text.isNotEmpty
                                  ? IconButton(
                                      icon: const Icon(Icons.close, size: 20),
                                      onPressed: () {
                                        _searchController.clear();
                                        _searchService.clear();
                                        setState(() {});
                                      },
                                    )
                                  : null,
                              border: InputBorder.none,
                              contentPadding: const EdgeInsets.symmetric(
                                vertical: 14,
                                horizontal: 16,
                              ),
                            ),
                            textInputAction: TextInputAction.search,
                            onSubmitted: (_) => _performSearch(),
                            onChanged: (_) => setState(() {}),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      SizedBox(
                        height: 48,
                        child: FilledButton(
                          onPressed: _performSearch,
                          style: FilledButton.styleFrom(
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(24),
                            ),
                            padding: const EdgeInsets.symmetric(horizontal: 20),
                            elevation: 2,
                            shadowColor: colorScheme.primary.withOpacity(0.3),
                          ),
                          child: const Text(
                            '搜索',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 15,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

                // 选项卡 + 结果区域
                Expanded(
                  child: _buildSearchTabsArea(
                    context,
                    searchResult,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 12,
                    ),
                  ),
                ),
              ],
            ),
          ),

          // 覆盖搜索栏的二级详情层（歌手/专辑）
          if (_secondaryArtistId != null || _secondaryAlbumId != null)
            Positioned.fill(
              child: _buildSecondaryOverlayContainer(
                backgroundColor: colorScheme.surface,
                useMaterialWrapper: true,
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildFluentSearch(BuildContext context, SearchResult searchResult) {
    final fluentTheme = fluent.FluentTheme.of(context);
    final overlayBackground =
        fluentTheme.micaBackgroundColor ??
        fluentTheme.scaffoldBackgroundColor ??
        Colors.transparent;

    return SafeArea(
      bottom: false,
      child: Stack(
        children: [
          Positioned.fill(
            child: Column(
              children: [
                _buildFluentSearchBar(fluentTheme),
                Expanded(
                  child: _buildSearchTabsArea(
                    context,
                    searchResult,
                    padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
                  ),
                ),
              ],
            ),
          ),
          if (_secondaryArtistId != null || _secondaryAlbumId != null)
            Positioned.fill(
              child: _buildSecondaryOverlayContainer(
                backgroundColor: overlayBackground,
                useMaterialWrapper: false,
              ),
            ),
        ],
      ),
    );
  }

  /// iOS 风格搜索界面
  Widget _buildCupertinoSearch(BuildContext context, SearchResult searchResult) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final backgroundColor = isDark 
        ? const Color(0xFF000000) 
        : CupertinoColors.systemGroupedBackground;

    return Material(
      color: backgroundColor,
      child: SafeArea(
        bottom: false,
        child: Stack(
          children: [
            Positioned.fill(
              child: Column(
                children: [
                  // iOS 风格搜索栏
                  _buildCupertinoSearchBar(context, isDark),
                  // 选项卡 + 结果区域
                  Expanded(
                    child: _buildCupertinoSearchTabsArea(
                      context,
                      searchResult,
                      isDark,
                    ),
                  ),
                ],
              ),
            ),
            // 覆盖搜索栏的二级详情层（歌手/专辑）
            if (_secondaryArtistId != null || _secondaryAlbumId != null)
              Positioned.fill(
                child: _buildSecondaryOverlayContainer(
                  backgroundColor: backgroundColor,
                  useMaterialWrapper: true,
                ),
              ),
          ],
        ),
      ),
    );
  }

  /// iOS 风格搜索栏
  Widget _buildCupertinoSearchBar(BuildContext context, bool isDark) {
    return Container(
      padding: const EdgeInsets.fromLTRB(8, 8, 16, 8),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1C1C1E) : CupertinoColors.white,
        border: Border(
          bottom: BorderSide(
            color: isDark 
                ? CupertinoColors.systemGrey.darkColor.withOpacity(0.3) 
                : CupertinoColors.systemGrey.withOpacity(0.2),
            width: 0.5,
          ),
        ),
      ),
      child: Row(
        children: [
          // 返回按钮
          CupertinoButton(
            padding: const EdgeInsets.all(8),
            minSize: 0,
            onPressed: widget.onClose,
            child: Icon(
              CupertinoIcons.back,
              color: CupertinoColors.activeBlue,
              size: 24,
            ),
          ),
          const SizedBox(width: 4),
          // 搜索框
          Expanded(
            child: CupertinoSearchTextField(
              controller: _searchController,
              autofocus: true,
              placeholder: '搜索歌曲、歌手...',
              onSubmitted: (_) => _performSearch(),
              onChanged: (_) => setState(() {}),
              onSuffixTap: () {
                _searchController.clear();
                _searchService.clear();
                setState(() {});
              },
            ),
          ),
          const SizedBox(width: 8),
          // 搜索按钮
          CupertinoButton(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            minSize: 0,
            onPressed: _performSearch,
            child: Text(
              '搜索',
              style: TextStyle(
                color: CupertinoColors.activeBlue,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// iOS 风格选项卡区域
  Widget _buildCupertinoSearchTabsArea(
    BuildContext context,
    SearchResult searchResult,
    bool isDark,
  ) {
    final isMergeEnabled = DeveloperModeService().isSearchResultMergeEnabled;
    final tabs = isMergeEnabled 
        ? ['歌曲', '歌手'] 
        : ['网易云', 'Apple', 'Spotify', 'QQ音乐', '酷狗', '酷我', '歌手'];
    final brightness = isDark ? Brightness.dark : Brightness.light;

    return Column(
      children: [
        // iOS 分段控件
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: SizedBox(
            width: double.infinity,
            child: CupertinoSlidingSegmentedControl<int>(
              groupValue: _currentTabIndex,
              children: {
                for (int i = 0; i < tabs.length; i++)
                  i: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                    child: _isPlatformTab(tabs[i])
                      // 平台tab：显示彩色小球
                      ? Container(
                          width: 14,
                          height: 14,
                          decoration: BoxDecoration(
                            color: _getPlatformDotColor(
                              _getPlatformCodeFromLabel(tabs[i]),
                              brightness,
                            ),
                            shape: BoxShape.circle,
                          ),
                        )
                      // 功能tab：显示文字
                      : Text(
                          tabs[i],
                          style: const TextStyle(fontSize: 13),
                        ),
                  ),
              },
              onValueChanged: (value) {
                if (value != null) {
                  _handleTabChanged(value);
                }
              },

            ),
          ),
        ),
        const SizedBox(height: 4),
        // 结果区域
        Expanded(
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 200),
            switchInCurve: Curves.easeOutQuad,
            switchOutCurve: Curves.easeInQuad,
            child: _buildCupertinoActiveTabView(context, searchResult, isDark),
          ),
        ),
      ],
    );
  }

  /// iOS 风格活动选项卡视图
  Widget _buildCupertinoActiveTabView(
    BuildContext context,
    SearchResult searchResult,
    bool isDark,
  ) {
    final isMergeEnabled = DeveloperModeService().isSearchResultMergeEnabled;

    if (isMergeEnabled) {
      if (_currentTabIndex == 0) {
        return Container(
          key: const ValueKey('cupertino_songs_tab'),
          child: _buildCupertinoSongResults(searchResult, isDark),
        );
      }
      return Container(
        key: const ValueKey('cupertino_artists_tab'),
        child: _buildCupertinoArtistResults(isDark),
      );
    } else {
      // 分平台模式：根据当前音源支持的平台动态显示
      final platformCodes = _getSupportedPlatformCodes();
      
      // 如果 _currentTabIndex 在平台范围内，显示对应平台的结果
      if (_currentTabIndex < platformCodes.length) {
        final platform = platformCodes[_currentTabIndex];
        
        List<Track> results;
        bool isLoading;
        String valueKey;
        
        switch (platform) {
          case 'netease':
            results = searchResult.neteaseResults;
            isLoading = searchResult.neteaseLoading;
            valueKey = 'cupertino_netease_tab';
            break;
          case 'apple':
            results = searchResult.appleResults;
            isLoading = searchResult.appleLoading;
            valueKey = 'cupertino_apple_tab';
            break;
          case 'qq':
            results = searchResult.qqResults;
            isLoading = searchResult.qqLoading;
            valueKey = 'cupertino_qq_tab';
            break;
          case 'kugou':
            results = searchResult.kugouResults;
            isLoading = searchResult.kugouLoading;
            valueKey = 'cupertino_kugou_tab';
            break;
          case 'kuwo':
            results = searchResult.kuwoResults;
            isLoading = searchResult.kuwoLoading;
            valueKey = 'cupertino_kuwo_tab';
            break;
          case 'spotify':
            results = searchResult.spotifyResults;
            isLoading = searchResult.spotifyLoading;
            valueKey = 'cupertino_spotify_tab';
            break;
          default:
            return Container(
              key: const ValueKey('cupertino_artists_tab'),
              child: _buildCupertinoArtistResults(isDark),
            );
        }
        
        return Container(
          key: ValueKey(valueKey),
          child: _buildCupertinoSinglePlatformList(results, isLoading, isDark),
        );
      }
      
      // 最后一个 tab 是歌手
      return Container(
        key: const ValueKey('cupertino_artists_tab'),
        child: _buildCupertinoArtistResults(isDark),
      );
    }
  }

  /// iOS 风格单平台歌曲列表
  Widget _buildCupertinoSinglePlatformList(
    List<Track> tracks,
    bool isLoading,
    bool isDark,
  ) {
    if (_searchService.currentKeyword.isEmpty) {
      return _buildCupertinoSearchHistory(isDark);
    }

    if (!isLoading && tracks.isEmpty) {
      return _buildCupertinoEmptyState(
        icon: CupertinoIcons.music_note,
        title: '没有找到相关歌曲',
        subtitle: '试试其他关键词吧',
        isDark: isDark,
      );
    }

    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      children: [
        // 搜索统计
        _buildCupertinoSearchHeader(tracks.length, isDark),
        const SizedBox(height: 12),
        // 加载提示
        if (isLoading)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const CupertinoActivityIndicator(),
                const SizedBox(width: 12),
                Text(
                  '搜索中...',
                  style: TextStyle(
                    color: CupertinoColors.systemGrey,
                    fontSize: 14,
                  ),
                ),
              ],
            ),
          ),
        // 歌曲列表
        _buildCupertinoTrackSection(tracks, isDark),
      ],
    );
  }

  /// iOS 风格歌曲结果
  Widget _buildCupertinoSongResults(SearchResult result, bool isDark) {
    if (_searchService.currentKeyword.isEmpty) {
      return _buildCupertinoSearchHistory(isDark);
    }

    final isLoading = result.neteaseLoading || 
        result.appleLoading ||
        result.qqLoading || 
        result.kugouLoading || 
        result.kuwoLoading ||
        result.spotifyLoading;
    final mergedResults = _searchService.getMergedResults();

    if (result.allCompleted && mergedResults.isEmpty) {
      return _buildCupertinoEmptyState(
        icon: CupertinoIcons.music_note,
        title: '没有找到相关歌曲',
        subtitle: '试试其他关键词吧',
        isDark: isDark,
      );
    }

    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      children: [
        _buildCupertinoSearchHeader(mergedResults.length, isDark),
        const SizedBox(height: 12),
        if (isLoading)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const CupertinoActivityIndicator(),
                const SizedBox(width: 12),
                Text(
                  '搜索中...',
                  style: TextStyle(
                    color: CupertinoColors.systemGrey,
                    fontSize: 14,
                  ),
                ),
              ],
            ),
          ),
        _buildCupertinoMergedTrackSection(mergedResults, isDark),
      ],
    );
  }

  /// iOS 风格搜索头部统计
  Widget _buildCupertinoSearchHeader(int count, bool isDark) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1C1C1E) : CupertinoColors.white,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          Icon(
            CupertinoIcons.music_note,
            size: 20,
            color: CupertinoColors.activeBlue,
          ),
          const SizedBox(width: 8),
          Text(
            '找到 $count 首歌曲',
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: isDark ? CupertinoColors.white : CupertinoColors.black,
            ),
          ),
        ],
      ),
    );
  }

  /// iOS 风格歌曲卡片区域
  Widget _buildCupertinoTrackSection(List<Track> tracks, bool isDark) {
    return Container(
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1C1C1E) : CupertinoColors.white,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        children: [
          for (int i = 0; i < tracks.length; i++) ...[
            _buildCupertinoTrackTile(tracks[i], isDark),
            if (i < tracks.length - 1)
              Padding(
                padding: const EdgeInsets.only(left: 72),
                child: Container(
                  height: 0.5,
                  color: CupertinoColors.systemGrey.withOpacity(0.3),
                ),
              ),
          ],
        ],
      ),
    );
  }

  /// iOS 风格合并歌曲卡片区域
  Widget _buildCupertinoMergedTrackSection(
    List<MergedTrack> tracks,
    bool isDark,
  ) {
    return Container(
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1C1C1E) : CupertinoColors.white,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        children: [
          for (int i = 0; i < tracks.length; i++) ...[
            _buildCupertinoMergedTrackTile(tracks[i], isDark),
            if (i < tracks.length - 1)
              Padding(
                padding: const EdgeInsets.only(left: 72),
                child: Container(
                  height: 0.5,
                  color: CupertinoColors.systemGrey.withOpacity(0.3),
                ),
              ),
          ],
        ],
      ),
    );
  }

  /// iOS 风格单曲项
  Widget _buildCupertinoTrackTile(Track track, bool isDark) {
    return CupertinoButton(
      padding: EdgeInsets.zero,
      onPressed: () => _playSingleTrack(track),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(
          children: [
            // 封面
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: CachedNetworkImage(
                imageUrl: track.picUrl,
                width: 48,
                height: 48,
                fit: BoxFit.cover,
                placeholder: (context, url) => Container(
                  width: 48,
                  height: 48,
                  color: isDark 
                      ? const Color(0xFF2C2C2E) 
                      : CupertinoColors.systemGrey5,
                  child: const Center(
                    child: CupertinoActivityIndicator(radius: 10),
                  ),
                ),
                errorWidget: (context, url, error) => Container(
                  width: 48,
                  height: 48,
                  color: isDark 
                      ? const Color(0xFF2C2C2E) 
                      : CupertinoColors.systemGrey5,
                  child: Icon(
                    CupertinoIcons.music_note,
                    color: CupertinoColors.systemGrey,
                    size: 24,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 12),
            // 歌曲信息
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    track.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 16,
                      color: isDark ? CupertinoColors.white : CupertinoColors.black,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${track.artists} • ${track.album}',
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
            // 更多按钮
            TrackMoreButton(
              track: track,
              onPlay: () => _playSingleTrack(track),
              size: 36,
            ),
          ],
        ),
      ),
    );
  }

  /// iOS 风格合并歌曲项
  Widget _buildCupertinoMergedTrackTile(MergedTrack mergedTrack, bool isDark) {
    final bestTrack = mergedTrack.getBestTrack();
    
    return GestureDetector(
      onLongPress: () => _showCupertinoPlatformSelector(mergedTrack),
      child: CupertinoButton(
        padding: EdgeInsets.zero,
        onPressed: () => _playMergedTrack(mergedTrack),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: CachedNetworkImage(
                  imageUrl: mergedTrack.picUrl,
                  width: 48,
                  height: 48,
                  fit: BoxFit.cover,
                  placeholder: (context, url) => Container(
                    width: 48,
                    height: 48,
                    color: isDark 
                        ? const Color(0xFF2C2C2E) 
                        : CupertinoColors.systemGrey5,
                    child: const Center(
                      child: CupertinoActivityIndicator(radius: 10),
                    ),
                  ),
                  errorWidget: (context, url, error) => Container(
                    width: 48,
                    height: 48,
                    color: isDark 
                        ? const Color(0xFF2C2C2E) 
                        : CupertinoColors.systemGrey5,
                    child: Icon(
                      CupertinoIcons.music_note,
                      color: CupertinoColors.systemGrey,
                      size: 24,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      mergedTrack.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 16,
                        color: isDark ? CupertinoColors.white : CupertinoColors.black,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${mergedTrack.artists} • ${mergedTrack.album}',
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
              // 更多按钮
              TrackMoreButton(
                track: bestTrack,
                onPlay: () => _playMergedTrack(mergedTrack),
                size: 36,
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// iOS 风格歌手结果
  Widget _buildCupertinoArtistResults(bool isDark) {
    final keyword = _searchService.currentKeyword;
    if (keyword.isEmpty) {
      return _buildCupertinoEmptyState(
        icon: CupertinoIcons.person_2,
        title: '搜索歌手',
        subtitle: '输入关键词后切换到"歌手"',
        isDark: isDark,
      );
    }

    if (_artistLoading && _secondaryArtistId == null && _secondaryAlbumId == null) {
      return const Center(child: CupertinoActivityIndicator(radius: 14));
    }

    if (_artistError != null && _secondaryArtistId == null && _secondaryAlbumId == null) {
      return Center(
        child: Text(
          '搜索失败: $_artistError',
          style: TextStyle(color: CupertinoColors.systemGrey),
        ),
      );
    }

    if (_artistResults.isEmpty && _secondaryArtistId == null && _secondaryAlbumId == null) {
      return _buildCupertinoEmptyState(
        icon: CupertinoIcons.person_badge_minus,
        title: '没有找到相关歌手',
        subtitle: '试试其他关键词吧',
        isDark: isDark,
      );
    }

    if (_secondaryArtistId != null || _secondaryAlbumId != null) {
      return const SizedBox.shrink();
    }

    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      children: [
        Container(
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF1C1C1E) : CupertinoColors.white,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Column(
            children: [
              for (int i = 0; i < _artistResults.length; i++) ...[
                _buildCupertinoArtistTile(_artistResults[i], isDark),
                if (i < _artistResults.length - 1)
                  Padding(
                    padding: const EdgeInsets.only(left: 72),
                    child: Container(
                      height: 0.5,
                      color: CupertinoColors.systemGrey.withOpacity(0.3),
                    ),
                  ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  /// iOS 风格歌手项
  Widget _buildCupertinoArtistTile(NeteaseArtistBrief artist, bool isDark) {
    return CupertinoButton(
      padding: EdgeInsets.zero,
      onPressed: () {
        setState(() {
          _secondaryArtistId = artist.id;
          _secondaryArtistName = artist.name;
        });
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(
          children: [
            // 头像
            artist.picUrl.isEmpty
                ? Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: isDark 
                          ? const Color(0xFF2C2C2E) 
                          : CupertinoColors.systemGrey5,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      CupertinoIcons.person_fill,
                      color: CupertinoColors.systemGrey,
                      size: 24,
                    ),
                  )
                : ClipRRect(
                    borderRadius: BorderRadius.circular(24),
                    child: CachedNetworkImage(
                      imageUrl: artist.picUrl,
                      width: 48,
                      height: 48,
                      fit: BoxFit.cover,
                      placeholder: (context, url) => Container(
                        width: 48,
                        height: 48,
                        color: isDark 
                            ? const Color(0xFF2C2C2E) 
                            : CupertinoColors.systemGrey5,
                        child: const Center(
                          child: CupertinoActivityIndicator(radius: 10),
                        ),
                      ),
                    ),
                  ),
            const SizedBox(width: 12),
            // 歌手名
            Expanded(
              child: Text(
                artist.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 16,
                  color: isDark ? CupertinoColors.white : CupertinoColors.black,
                ),
              ),
            ),
            // 箭头
            Icon(
              CupertinoIcons.chevron_forward,
              color: CupertinoColors.systemGrey,
              size: 18,
            ),
          ],
        ),
      ),
    );
  }

  /// Fluent UI 风格歌手结果
  Widget _buildFluentArtistResults() {
    final fluentTheme = fluent.FluentTheme.of(context);
    final keyword = _searchService.currentKeyword;
    
    if (keyword.isEmpty) {
      return _buildFluentEmptyState(
        icon: fluent.FluentIcons.people,
        title: '搜索歌手',
        subtitle: '输入关键词后切换到"歌手"',
      );
    }

    if (_artistLoading && _secondaryArtistId == null && _secondaryAlbumId == null) {
      return const Center(child: fluent.ProgressRing());
    }

    if (_artistError != null && _secondaryArtistId == null && _secondaryAlbumId == null) {
      return Center(
        child: Text(
          '搜索失败: $_artistError',
          style: TextStyle(color: fluentTheme.resources.textFillColorSecondary),
        ),
      );
    }

    if (_artistResults.isEmpty && _secondaryArtistId == null && _secondaryAlbumId == null) {
      return _buildFluentEmptyState(
        icon: fluent.FluentIcons.people,
        title: '没有找到相关歌手',
        subtitle: '试试其他关键词吧',
      );
    }

    if (_secondaryArtistId != null || _secondaryAlbumId != null) {
      return const SizedBox.shrink();
    }

    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      itemCount: _artistResults.length,
      itemBuilder: (context, index) => _buildFluentArtistTile(_artistResults[index]),
    );
  }

  /// Fluent UI 风格歌手项（参考歌单卡片样式）
  Widget _buildFluentArtistTile(NeteaseArtistBrief artist) {
    final theme = fluent.FluentTheme.of(context);
    final resources = theme.resources;

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: fluent.Card(
        borderRadius: BorderRadius.circular(12),
        padding: EdgeInsets.zero,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () {
            setState(() {
              _secondaryArtistId = artist.id;
              _secondaryArtistName = artist.name;
            });
          },
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                // 歌手头像
                Hero(
                  tag: 'fluent_search_artist_${artist.id}',
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(32),
                    child: artist.picUrl.isEmpty
                        ? Container(
                            width: 64,
                            height: 64,
                            color: resources.controlAltFillColorSecondary,
                            alignment: Alignment.center,
                            child: Icon(
                              fluent.FluentIcons.contact,
                              color: resources.textFillColorTertiary,
                              size: 28,
                            ),
                          )
                        : CachedNetworkImage(
                            imageUrl: artist.picUrl,
                            width: 64,
                            height: 64,
                            memCacheWidth: 128,
                            memCacheHeight: 128,
                            fit: BoxFit.cover,
                            placeholder: (_, __) => Container(
                              width: 64,
                              height: 64,
                              color: resources.controlAltFillColorSecondary,
                              alignment: Alignment.center,
                              child: const fluent.ProgressRing(strokeWidth: 2),
                            ),
                            errorWidget: (_, __, ___) => Container(
                              width: 64,
                              height: 64,
                              color: resources.controlAltFillColorSecondary,
                              alignment: Alignment.center,
                              child: Icon(
                                fluent.FluentIcons.contact,
                                color: resources.textFillColorTertiary,
                                size: 28,
                              ),
                            ),
                          ),
                  ),
                ),
                const SizedBox(width: 16),
                // 歌手名
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        artist.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 15,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '歌手',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 13,
                          color: resources.textFillColorSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                // 箭头
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 8),
                  child: Icon(fluent.FluentIcons.chevron_right, size: 12),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Fluent UI 风格空状态
  Widget _buildFluentEmptyState({
    required IconData icon,
    required String title,
    required String subtitle,
  }) {
    final fluentTheme = fluent.FluentTheme.of(context);
    final textColor = fluentTheme.resources.textFillColorPrimary;
    final subtleColor = fluentTheme.resources.textFillColorSecondary;
    
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 48, color: subtleColor),
          const SizedBox(height: 16),
          Text(
            title,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: textColor,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            subtitle,
            style: TextStyle(
              fontSize: 13,
              color: subtleColor,
            ),
          ),
        ],
      ),
    );
  }

  /// iOS 风格搜索历史
  Widget _buildCupertinoSearchHistory(bool isDark) {
    final history = _searchService.searchHistory;

    if (history.isEmpty) {
      return _buildCupertinoEmptyState(
        icon: CupertinoIcons.search,
        title: '搜索音乐',
        subtitle: '支持网易云、QQ音乐、酷狗音乐',
        isDark: isDark,
      );
    }

    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      children: [
        // 标题栏
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              children: [
                Icon(
                  CupertinoIcons.clock,
                  size: 18,
                  color: CupertinoColors.systemGrey,
                ),
                const SizedBox(width: 8),
                Text(
                  '搜索历史',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: isDark ? CupertinoColors.white : CupertinoColors.black,
                  ),
                ),
              ],
            ),
            CupertinoButton(
              padding: EdgeInsets.zero,
              minSize: 0,
              onPressed: _confirmClearHistory,
              child: Text(
                '清空',
                style: TextStyle(
                  fontSize: 14,
                  color: CupertinoColors.destructiveRed,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        // 历史记录列表
        Container(
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF1C1C1E) : CupertinoColors.white,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Column(
            children: [
              for (int i = 0; i < history.length; i++) ...[
                _buildCupertinoHistoryTile(history[i], isDark),
                if (i < history.length - 1)
                  Padding(
                    padding: const EdgeInsets.only(left: 52),
                    child: Container(
                      height: 0.5,
                      color: CupertinoColors.systemGrey.withOpacity(0.3),
                    ),
                  ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 16),
        // 提示
        Center(
          child: Text(
            '点击历史记录快速搜索',
            style: TextStyle(
              fontSize: 13,
              color: CupertinoColors.systemGrey.withOpacity(0.7),
            ),
          ),
        ),
      ],
    );
  }

  /// iOS 风格历史记录项
  Widget _buildCupertinoHistoryTile(String keyword, bool isDark) {
    return CupertinoButton(
      padding: EdgeInsets.zero,
      onPressed: () {
        _searchController.text = keyword;
        _performSearch();
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            Icon(
              CupertinoIcons.clock,
              size: 20,
              color: CupertinoColors.activeBlue,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                keyword,
                style: TextStyle(
                  fontSize: 16,
                  color: isDark ? CupertinoColors.white : CupertinoColors.black,
                ),
              ),
            ),
            CupertinoButton(
              padding: EdgeInsets.zero,
              minSize: 0,
              onPressed: () => _searchService.removeSearchHistory(keyword),
              child: Icon(
                CupertinoIcons.xmark_circle_fill,
                size: 20,
                color: CupertinoColors.systemGrey,
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// iOS 风格空状态
  Widget _buildCupertinoEmptyState({
    required IconData icon,
    required String title,
    required String subtitle,
    required bool isDark,
  }) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            icon,
            size: 64,
            color: CupertinoColors.systemGrey.withOpacity(0.4),
          ),
          const SizedBox(height: 16),
          Text(
            title,
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w600,
              color: isDark 
                  ? CupertinoColors.white.withOpacity(0.8) 
                  : CupertinoColors.black.withOpacity(0.8),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            subtitle,
            style: TextStyle(
              fontSize: 14,
              color: CupertinoColors.systemGrey,
            ),
          ),
        ],
      ),
    );
  }

  /// iOS 风格平台选择器
  void _showCupertinoPlatformSelector(MergedTrack mergedTrack) {
    showCupertinoModalPopup<void>(
      context: context,
      builder: (context) => Material(
        type: MaterialType.transparency,
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: CupertinoTheme.of(context).barBackgroundColor,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
          ),
          child: SafeArea(
            top: false,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // 拖动条
                Container(
                  width: 36,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(
                    color: CupertinoColors.systemGrey,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                // 标题
                Text(
                  '选择播放平台',
                  style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  mergedTrack.name,
                  style: TextStyle(
                    fontSize: 15,
                    color: CupertinoColors.systemGrey,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 16),
                // 平台列表
                ...mergedTrack.tracks.map(
                  (track) => CupertinoButton(
                    padding: EdgeInsets.zero,
                    onPressed: () async {
                      Navigator.pop(context);
                      final isLoggedIn = await _checkLoginStatus();
                      if (isLoggedIn && mounted) {
                        if (track.picUrl.isNotEmpty) {
                          final provider = CachedNetworkImageProvider(track.picUrl);
                          PlayerService().setCurrentCoverImageProvider(provider);
                          PlayerService().playTrack(track, coverProvider: provider);
                        } else {
                          PlayerService().playTrack(track);
                        }
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text('正在播放: ${track.name}'),
                            duration: const Duration(seconds: 1),
                          ),
                        );
                      }
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 12,
                      ),
                      child: Row(
                        children: [
                          Text(
                            track.getSourceIcon(),
                            style: const TextStyle(fontSize: 24),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  track.getSourceName(),
                                  style: const TextStyle(fontSize: 16),
                                ),
                                Text(
                                  track.album,
                                  style: TextStyle(
                                    fontSize: 13,
                                    color: CupertinoColors.systemGrey,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ],
                            ),
                          ),
                          Icon(
                            CupertinoIcons.play_fill,
                            color: CupertinoColors.activeBlue,
                            size: 20,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                // 取消按钮
                SizedBox(
                  width: double.infinity,
                  child: CupertinoButton(
                    color: CupertinoColors.systemGrey5,
                    borderRadius: BorderRadius.circular(10),
                    onPressed: () => Navigator.pop(context),
                    child: const Text(
                      '取消',
                      style: TextStyle(color: CupertinoColors.activeBlue),
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

  Widget _buildSecondaryOverlayContainer({
    required Color backgroundColor,
    required bool useMaterialWrapper,
  }) {
    final title = _secondaryAlbumId != null
        ? (_secondaryAlbumName ?? '专辑详情')
        : (_secondaryArtistName ?? '歌手详情');

    final isDark = Theme.of(context).brightness == Brightness.dark;
    
    final header = SafeArea(
      bottom: false,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(
          children: [
            _isFluent
                ? fluent.Tooltip(
                    message: '返回',
                    child: fluent.IconButton(
                      icon: const Icon(fluent.FluentIcons.back),
                      onPressed: _handleSecondaryBack,
                    ),
                  )
                : _isCupertino
                    ? CupertinoButton(
                        padding: const EdgeInsets.all(8),
                        minSize: 0,
                        onPressed: _handleSecondaryBack,
                        child: Icon(
                          CupertinoIcons.back,
                          color: CupertinoColors.activeBlue,
                          size: 24,
                        ),
                      )
                    : IconButton(
                        icon: const Icon(Icons.arrow_back),
                        onPressed: _handleSecondaryBack,
                        tooltip: '返回',
                      ),
            const SizedBox(width: 4),
            Expanded(
              child: Text(
                title,
                style: _isCupertino
                    ? TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w600,
                        color: isDark ? CupertinoColors.white : CupertinoColors.black,
                      )
                    : Theme.of(context).textTheme.titleMedium,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );

    final dividerColor = _isFluent
        ? fluent.FluentTheme.of(context).resources?.dividerStrokeColorDefault
        : _isCupertino
            ? CupertinoColors.systemGrey.withOpacity(0.3)
            : Theme.of(context).dividerColor;

    final content = Column(
      children: [
        header,
        if (_isFluent || _isCupertino)
          Divider(height: 1, color: dividerColor),

        Expanded(
          child: _secondaryAlbumId != null
              ? AlbumDetailPage(albumId: _secondaryAlbumId!, embedded: true)
              : ArtistDetailContent(
                  artistId: _secondaryArtistId!,
                  onOpenAlbum: (albumId) {
                    setState(() {
                      _secondaryAlbumId = albumId;
                      _secondaryAlbumName = null;
                    });
                  },
                ),
        ),
      ],
    );

    if (useMaterialWrapper) {
      return Material(color: backgroundColor, child: content);
    }
    return Container(color: backgroundColor, child: content);
  }

  void _handleSecondaryBack() {
    setState(() {
      if (_secondaryAlbumId != null) {
        _secondaryAlbumId = null;
      } else {
        _secondaryArtistId = null;
        _secondaryArtistName = null;
      }
    });
  }

  Widget _buildFluentSearchBar(fluent.FluentThemeData theme) {
    final dividerColor =
        theme.resources?.dividerStrokeColorDefault ??
        Colors.black.withOpacity(0.06);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      decoration: BoxDecoration(
        color: theme.micaBackgroundColor ?? theme.scaffoldBackgroundColor,
        border: Border(bottom: BorderSide(color: dividerColor, width: 1)),
      ),
      child: Row(
        children: [
          fluent.Tooltip(
            message: '返回',
            child: fluent.IconButton(
              icon: const Icon(fluent.FluentIcons.back),
              onPressed: widget.onClose,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: fluent.TextBox(
              controller: _searchController,
              autofocus: true,
              placeholder: '搜索歌曲、歌手...',
              prefix: const Padding(
                padding: EdgeInsets.symmetric(horizontal: 8),
                child: Icon(fluent.FluentIcons.search),
              ),
              suffix: _searchController.text.isNotEmpty
                  ? fluent.IconButton(
                      icon: const Icon(fluent.FluentIcons.clear),
                      onPressed: () {
                        _searchController.clear();
                        _searchService.clear();
                        setState(() {});
                      },
                    )
                  : null,
              onSubmitted: (_) => _performSearch(),
              onChanged: (_) => setState(() {}),
            ),
          ),
          const SizedBox(width: 12),
          fluent.FilledButton(
            onPressed: _performSearch,
            child: const Text('搜索'),
          ),
        ],
      ),
    );
  }


  /// 获取当前平台 tab 列表（根据音源支持情况动态生成）
  List<String> _getPlatformTabs() {
    try {
      final supportedPlatforms = _searchService.currentSupportedPlatforms;
      final tabs = <String>[];
      
      // 平台代码到显示名称的映射
      const platformLabels = {
        'netease': '网易云',
        'apple': 'Apple',
        'spotify': 'Spotify',
        'qq': 'QQ音乐',
        'kugou': '酷狗',
        'kuwo': '酷我',
      };
      
      // 按固定顺序添加支持的平台
      for (final platform in ['netease', 'apple', 'spotify', 'qq', 'kugou', 'kuwo']) {
        if (supportedPlatforms.contains(platform)) {
          tabs.add(platformLabels[platform]!);
        }
      }
      
      // 如果没有任何平台，返回默认所有平台
      if (tabs.isEmpty) {
        tabs.addAll(['网易云', 'Apple', 'QQ音乐', '酷狗', '酷我']);
      }
      
      tabs.add('歌手'); // 歌手 tab 始终显示
      return tabs;
    } catch (e) {
      // 出现异常时返回默认 tabs
      print('⚠️ [SearchWidget] _getPlatformTabs error: $e');
      return ['网易云', 'Apple', 'QQ音乐', '酷狗', '酷我', '歌手'];
    }
  }
  
  /// 获取当前支持的平台代码列表（排序后）
  List<String> _getSupportedPlatformCodes() {
    try {
      final supportedPlatforms = _searchService.currentSupportedPlatforms;
      final codes = <String>[];
      
      for (final platform in ['netease', 'apple', 'spotify', 'qq', 'kugou', 'kuwo']) {
        if (supportedPlatforms.contains(platform)) {
          codes.add(platform);
        }
      }
      
      // 如果没有任何平台，返回默认所有平台
      if (codes.isEmpty) {
        return ['netease', 'apple', 'qq', 'kugou', 'kuwo'];
      }
      
      return codes;
    } catch (e) {
      // 出现异常时返回默认平台列表
      print('⚠️ [SearchWidget] _getSupportedPlatformCodes error: $e');
      return ['netease', 'apple', 'qq', 'kugou', 'kuwo'];
    }
  }

  Widget _buildSearchTabsArea(
    BuildContext context,
    SearchResult searchResult, {
    required EdgeInsetsGeometry padding,
  }) {
    final isMergeEnabled = DeveloperModeService().isSearchResultMergeEnabled;
    final tabs = isMergeEnabled 
        ? ['歌曲', '歌手'] 
        : _getPlatformTabs();

    if (_isFluent) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: padding,
            child: _FluentPivotTabs(
              items: tabs.map((t) => _buildFluentTabHeader(t)).toList(),
              selectedIndex: _currentTabIndex.clamp(0, tabs.length - 1),
              onChanged: _handleTabChanged,
            ),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: _buildTabContent(_currentTabIndex, searchResult),
          ),
        ],
      );
    }

    return Column(
      children: [
        Padding(
          padding: padding,
          child: _SearchExpressiveTabs(
            tabs: tabs,
            currentIndex: _currentTabIndex.clamp(0, tabs.length - 1),
            onChanged: _handleTabChanged,
          ),
        ),
        const SizedBox(height: 8),
        Expanded(
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 200),
            switchInCurve: Curves.easeOutQuad,
            switchOutCurve: Curves.easeInQuad,
            child: _buildActiveTabView(context, searchResult),
          ),
        ),
      ],
    );
  }

  Widget _buildFluentTabHeader(String label) {
    if (_isPlatformTab(label)) {
      final platformCode = _getPlatformCodeFromLabel(label);
      final brightness = fluent.FluentTheme.of(context).brightness;
      final dotColor = _getPlatformDotColor(platformCode, brightness);
      
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: Container(
          width: 12,
          height: 12,
          decoration: BoxDecoration(
            color: dotColor,
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: dotColor.withOpacity(0.3),
                blurRadius: 4,
                spreadRadius: 1,
              ),
            ],
          ),
        ),
      );
    }
    
    return Text(label);
  }

  Widget _buildActiveTabView(
    BuildContext context,
    SearchResult searchResult,
  ) {
    return _buildTabContent(_currentTabIndex, searchResult);
  }

  Widget _buildTabContent(int tabIndex, SearchResult searchResult) {
    final fluentTheme = fluent.FluentTheme.maybeOf(context);
    final materialTheme = Theme.of(context);
    final backgroundColor = _isFluent
        ? (fluentTheme?.micaBackgroundColor ??
            fluentTheme?.scaffoldBackgroundColor ??
            materialTheme.colorScheme.surface)
        : materialTheme.colorScheme.surface;

    final isMergeEnabled = DeveloperModeService().isSearchResultMergeEnabled;

    if (isMergeEnabled) {
      // 合并模式：['歌曲', '歌手']
      if (tabIndex == 0) {
        return Container(
          key: const ValueKey('songs_tab'),
          color: backgroundColor,
          child: _buildSongResults(searchResult),
        );
      }
      return Container(
        key: const ValueKey('artists_tab'),
        color: backgroundColor,
        child: _isFluent ? _buildFluentArtistResults() : _buildArtistResults(),
      );
    } else {
      // 分平台模式：根据当前音源支持的平台动态显示
      final platformCodes = _getSupportedPlatformCodes();
      
      // 如果 tabIndex 在平台范围内，显示对应平台的结果
      if (tabIndex < platformCodes.length) {
        final platform = platformCodes[tabIndex];
        
        List<Track> results;
        bool isLoading;
        String valueKey;
        
        switch (platform) {
          case 'netease':
            results = searchResult.neteaseResults;
            isLoading = searchResult.neteaseLoading;
            valueKey = 'netease_tab';
            break;
          case 'apple':
            results = searchResult.appleResults;
            isLoading = searchResult.appleLoading;
            valueKey = 'apple_tab';
            break;
          case 'qq':
            results = searchResult.qqResults;
            isLoading = searchResult.qqLoading;
            valueKey = 'qq_tab';
            break;
          case 'kugou':
            results = searchResult.kugouResults;
            isLoading = searchResult.kugouLoading;
            valueKey = 'kugou_tab';
            break;
          case 'kuwo':
            results = searchResult.kuwoResults;
            isLoading = searchResult.kuwoLoading;
            valueKey = 'kuwo_tab';
            break;
          case 'spotify':
            results = searchResult.spotifyResults;
            isLoading = searchResult.spotifyLoading;
            valueKey = 'spotify_tab';
            break;
          default:
            return Container(
              key: const ValueKey('artists_tab'),
              color: backgroundColor,
              child: _isFluent ? _buildFluentArtistResults() : _buildArtistResults(),
            );
        }
        
        return Container(
          key: ValueKey(valueKey),
          color: backgroundColor,
          child: _buildSinglePlatformList(results, isLoading),
        );
      }
      
      // 最后一个 tab 是歌手
      return Container(
        key: const ValueKey('artists_tab'),
        color: backgroundColor,
        child: _isFluent ? _buildFluentArtistResults() : _buildArtistResults(),
      );
    }
  }

  Widget _wrapCard({
    EdgeInsetsGeometry? margin,
    EdgeInsetsGeometry? padding,
    required Widget child,
  }) {
    if (_isFluent) {
      return Padding(
        padding: margin ?? EdgeInsets.zero,
        child: fluent.Card(padding: padding ?? EdgeInsets.zero, child: child),
      );
    }
    return Card(
      margin: margin,
      child: padding != null ? Padding(padding: padding, child: child) : child,
    );
  }

  Widget _buildAdaptiveListTile({
    Widget? leading,
    Widget? title,
    Widget? subtitle,
    Widget? trailing,
    VoidCallback? onPressed,
    VoidCallback? onLongPress,
  }) {
    if (_isFluent) {
      final tile = fluent.ListTile(
        leading: leading,
        title: title,
        subtitle: subtitle,
        trailing: trailing,
        onPressed: onPressed,
      );

      if (onLongPress == null) {
        return tile;
      }

      return GestureDetector(
        behavior: HitTestBehavior.opaque,
        onLongPress: onLongPress,
        child: tile,
      );
    }
    return ListTile(
      leading: leading,
      title: title,
      subtitle: subtitle,
      trailing: trailing,
      onTap: onPressed,
      onLongPress: onLongPress,
    );
  }

  Widget _buildSinglePlatformList(List<Track> tracks, bool isLoading) {
    // 如果没有搜索或搜索结果为空，显示搜索历史
    if (_searchService.currentKeyword.isEmpty) {
      return _buildSearchHistory();
    }

    // 如果加载完成且没有结果
    if (!isLoading && tracks.isEmpty) {
      return _buildEmptyState(
        icon: Icons.music_off,
        title: '没有找到相关歌曲',
        subtitle: '试试其他关键词吧',
      );
    }

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // 搜索统计
        _buildSearchHeader(tracks.length, _searchService.searchResult),

        const SizedBox(height: 16),

        // 加载提示
        if (isLoading)
          const Padding(
            padding: EdgeInsets.only(bottom: 16),
            child: Center(
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                  SizedBox(width: 12),
                  Text('搜索中...'),
                ],
              ),
            ),
          ),

        // 歌曲列表
        ...tracks.map(
          (track) => _buildSingleTrackItem(track),
        ),
      ],
    );
  }

  Widget _buildSingleTrackItem(Track track) {
    if (_isFluent) {
      final theme = fluent.FluentTheme.of(context);
      final resources = theme.resources;

      return Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: fluent.Card(
          borderRadius: BorderRadius.circular(12),
          padding: EdgeInsets.zero,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => _playSingleTrack(track),
            onLongPress: () => TrackActionMenu.show(
              context: context,
              track: track,
              onPlay: () => _playSingleTrack(track),
            ),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  // 封面
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: CachedNetworkImage(
                      imageUrl: track.picUrl,
                      width: 64,
                      height: 64,
                      memCacheWidth: 128,
                      memCacheHeight: 128,
                      fit: BoxFit.cover,
                      placeholder: (_, __) => Container(
                        width: 64,
                        height: 64,
                        color: resources.controlAltFillColorSecondary,
                        alignment: Alignment.center,
                        child: const fluent.ProgressRing(strokeWidth: 2),
                      ),
                      errorWidget: (_, __, ___) => Container(
                        width: 64,
                        height: 64,
                        color: resources.controlAltFillColorSecondary,
                        alignment: Alignment.center,
                        child: Icon(
                          fluent.FluentIcons.music_in_collection,
                          color: resources.textFillColorTertiary,
                          size: 24,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 16),
                  // 歌曲信息
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          track.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 15,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '${track.artists} • ${track.album}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 13,
                            color: resources.textFillColorSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  // 操作按钮
                  TrackMoreButton(
                    track: track,
                    onPlay: () => _playSingleTrack(track),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    // Material Expressive Style
    final cs = Theme.of(context).colorScheme;
    
    return InkWell(
      onTap: () => _playSingleTrack(track),
      onLongPress: () => TrackActionMenu.show(
        context: context,
        track: track,
        onPlay: () => _playSingleTrack(track),
      ),
      borderRadius: BorderRadius.circular(16),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
        child: Row(
          children: [
            // 大尺寸高圆角封面
            Hero(
              tag: 'search_track_${track.id}_${track.source}',
              child: Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(14),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.08),
                      blurRadius: 10,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(14),
                  child: CachedNetworkImage(
                    imageUrl: track.picUrl,
                    fit: BoxFit.cover,
                    placeholder: (context, url) => Container(
                      color: cs.surfaceContainerHighest,
                      child: const Center(
                        child: SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
                      ),
                    ),
                    errorWidget: (context, url, error) => Container(
                      color: cs.surfaceContainerHighest,
                      child: Icon(Icons.music_note, color: cs.primary.withOpacity(0.5)),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 16),
            // 文字内容
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    track.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: cs.onSurface,
                      letterSpacing: -0.3,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${track.artists} · ${track.album}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                      color: cs.onSurfaceVariant.withOpacity(0.8),
                    ),
                  ),
                ],
              ),
            ),
            // 操作按钮
            TrackMoreButton(
              track: track,
              onPlay: () => _playSingleTrack(track),
            ),
          ],
        ),
      ),
    );
  }

  void _playSingleTrack(Track track) async {
    // 检查登录状态
    final isLoggedIn = await _checkLoginStatus();
    if (!isLoggedIn) return;

    // 播放前注入封面 Provider，避免播放器再次请求
    ImageProvider? provider;
    if (track.picUrl.isNotEmpty) {
      provider = CachedNetworkImageProvider(track.picUrl);
      PlayerService().setCurrentCoverImageProvider(provider);
    }
    PlayerService().playTrack(track, coverProvider: provider);

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('正在播放: ${track.name}'),
          duration: const Duration(seconds: 1),
        ),
      );
    }
  }

  Widget _buildSongResults(SearchResult result) {
    // 如果没有搜索或搜索结果为空，显示搜索历史
    if (_searchService.currentKeyword.isEmpty) {
      return _buildSearchHistory();
    }

    // 显示加载状态
    final isLoading =
        result.neteaseLoading ||
        result.appleLoading ||
        result.qqLoading ||
        result.kugouLoading ||
        result.kuwoLoading ||
        result.spotifyLoading;

    // 获取合并后的结果
    final mergedResults = _searchService.getMergedResults();

    // 如果所有平台都加载完成且没有结果
    if (result.allCompleted && mergedResults.isEmpty) {
      return _buildEmptyState(
        icon: Icons.music_off,
        title: '没有找到相关歌曲',
        subtitle: '试试其他关键词吧',
      );
    }

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // 搜索统计
        _buildSearchHeader(mergedResults.length, result),

        const SizedBox(height: 16),

        // 加载提示
        if (isLoading)
          const Padding(
            padding: EdgeInsets.only(bottom: 16),
            child: Center(
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                  SizedBox(width: 12),
                  Text('搜索中...'),
                ],
              ),
            ),
          ),

        // 合并后的歌曲列表
        ...mergedResults.map(
          (mergedTrack) => _buildMergedTrackItem(mergedTrack),
        ),
      ],
    );
  }

  Widget _buildArtistResults() {
    final keyword = _searchService.currentKeyword;
    if (keyword.isEmpty) {
      return _buildEmptyState(
        icon: Icons.person_search,
        title: '搜索歌手',
        subtitle: '输入关键词后切换到“歌手”',
      );
    }

    if (_artistLoading &&
        _secondaryArtistId == null &&
        _secondaryAlbumId == null) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_artistError != null &&
        _secondaryArtistId == null &&
        _secondaryAlbumId == null) {
      return Center(child: Text('搜索失败: $_artistError'));
    }
    if (_artistResults.isEmpty &&
        _secondaryArtistId == null &&
        _secondaryAlbumId == null) {
      return _buildEmptyState(
        icon: Icons.person_off,
        title: '没有找到相关歌手',
        subtitle: '试试其他关键词吧',
      );
    }

    if (_secondaryArtistId != null || _secondaryAlbumId != null) {
      return const SizedBox.shrink();
    }

    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      itemCount: _artistResults.length,
      itemBuilder: (context, index) {
        final artist = _artistResults[index];
        final cs = Theme.of(context).colorScheme;

        // Expressive Artist Avatar
        final avatar = Hero(
          tag: 'search_artist_${artist.id}',
          child: Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.1),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(32),
              child: artist.picUrl.isEmpty
                  ? Container(
                      color: cs.surfaceContainerHighest,
                      child: Icon(Icons.person, size: 32, color: cs.primary.withOpacity(0.5)),
                    )
                  : CachedNetworkImage(
                      imageUrl: artist.picUrl,
                      fit: BoxFit.cover,
                      placeholder: (context, url) => Container(
                        color: cs.surfaceContainerHighest,
                        child: const Center(
                          child: SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
                        ),
                      ),
                    ),
            ),
          ),
        );

        return InkWell(
          onTap: () {
            setState(() {
              _secondaryArtistId = artist.id;
              _secondaryArtistName = artist.name;
            });
          },
          borderRadius: BorderRadius.circular(16),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
            child: Row(
              children: [
                avatar,
                const SizedBox(width: 20),
                Expanded(
                  child: Text(
                    artist.name,
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                      color: cs.onSurface,
                      letterSpacing: -0.5,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Icon(Icons.arrow_forward_ios, size: 16, color: cs.onSurfaceVariant.withOpacity(0.5)),
              ],
            ),
          ),
        );
      },
    );
  }

  /// 构建搜索头部（统计信息）
  Widget _buildSearchHeader(int totalCount, SearchResult result) {
    if (_isFluent) {
      final textStyle = Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold);
      return _wrapCard(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            const Icon(Icons.music_note, size: 20),
            const SizedBox(width: 8),
            Text('找到 $totalCount 首歌曲', style: textStyle),
          ],
        ),
      );
    }

    final cs = Theme.of(context).colorScheme;
    
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 8, 4, 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.baseline,
        textBaseline: TextBaseline.alphabetic,
        children: [
          Text(
            '找到',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: cs.onSurfaceVariant,
            ),
          ),
          const SizedBox(width: 6),
          Text(
            '$totalCount',
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.w900,
              color: cs.primary,
              letterSpacing: -1,
            ),
          ),
          const SizedBox(width: 6),
          Text(
            '首歌曲',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: cs.onSurfaceVariant,
            ),
          ),
          const Spacer(),
          // 如果有多个来源，可以在这里显示一个小徽章
        ],
      ),
    );
  }

  /// 构建合并后的歌曲项
  Widget _buildMergedTrackItem(MergedTrack mergedTrack) {
    if (_isFluent) {
      final theme = fluent.FluentTheme.of(context);
      final resources = theme.resources;
      final bestTrack = mergedTrack.getBestTrack();

      return Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: fluent.Card(
          borderRadius: BorderRadius.circular(12),
          padding: EdgeInsets.zero,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => _playMergedTrack(mergedTrack),
            onLongPress: () => _showPlatformSelector(mergedTrack),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  // 封面
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: CachedNetworkImage(
                      imageUrl: mergedTrack.picUrl,
                      width: 64,
                      height: 64,
                      memCacheWidth: 128,
                      memCacheHeight: 128,
                      fit: BoxFit.cover,
                      placeholder: (_, __) => Container(
                        width: 64,
                        height: 64,
                        color: resources.controlAltFillColorSecondary,
                        alignment: Alignment.center,
                        child: const fluent.ProgressRing(strokeWidth: 2),
                      ),
                      errorWidget: (_, __, ___) => Container(
                        width: 64,
                        height: 64,
                        color: resources.controlAltFillColorSecondary,
                        alignment: Alignment.center,
                        child: Icon(
                          fluent.FluentIcons.music_in_collection,
                          color: resources.textFillColorTertiary,
                          size: 24,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 16),
                  // 歌曲信息
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          mergedTrack.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 15,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '${mergedTrack.artists} • ${mergedTrack.album}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 13,
                            color: resources.textFillColorSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  // 操作按钮
                  TrackMoreButton(
                    track: bestTrack,
                    onPlay: () => _playMergedTrack(mergedTrack),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    // Material Expressive Style
    final cs = Theme.of(context).colorScheme;
    final bestTrack = mergedTrack.getBestTrack();
    
    return InkWell(
      onTap: () => _playMergedTrack(mergedTrack),
      onLongPress: () => _showPlatformSelector(mergedTrack),
      borderRadius: BorderRadius.circular(16),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
        child: Row(
          children: [
            // 大尺寸高圆角封面
            Hero(
              tag: 'search_merged_${bestTrack.id}_${bestTrack.source}',
              child: Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(14),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.08),
                      blurRadius: 10,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(14),
                  child: CachedNetworkImage(
                    imageUrl: mergedTrack.picUrl,
                    fit: BoxFit.cover,
                    placeholder: (context, url) => Container(
                      color: cs.surfaceContainerHighest,
                      child: const Center(
                        child: SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
                      ),
                    ),
                    errorWidget: (context, url, error) => Container(
                      color: cs.surfaceContainerHighest,
                      child: Icon(Icons.music_note, color: cs.primary.withOpacity(0.5)),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 16),
            // 文字内容
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    mergedTrack.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: cs.onSurface,
                      letterSpacing: -0.3,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${mergedTrack.artists} · ${mergedTrack.album}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                      color: cs.onSurfaceVariant.withOpacity(0.8),
                    ),
                  ),
                ],
              ),
            ),
            // 操作按钮
            TrackMoreButton(
              track: bestTrack,
              onPlay: () => _playMergedTrack(mergedTrack),
              // Note: TrackMoreButton will need to be visually consistent too.
            ),
          ],
        ),
      ),
    );
  }

  /// 播放合并后的歌曲（按优先级选择平台）
  void _playMergedTrack(MergedTrack mergedTrack) async {
    // 检查登录状态
    final isLoggedIn = await _checkLoginStatus();
    if (!isLoggedIn) return;

    final bestTrack = mergedTrack.getBestTrack();
    // 播放前注入封面 Provider，避免播放器再次请求
    ImageProvider? provider;
    if (bestTrack.picUrl.isNotEmpty) {
      provider = CachedNetworkImageProvider(bestTrack.picUrl);
      PlayerService().setCurrentCoverImageProvider(provider);
    }
    PlayerService().playTrack(bestTrack, coverProvider: provider);

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('正在播放: ${mergedTrack.name}'),
          duration: const Duration(seconds: 1),
        ),
      );
    }
  }

  /// 显示平台选择器（长按时）
  void _showPlatformSelector(MergedTrack mergedTrack) {
    if (_isFluent) {
      fluent.showDialog(
        context: context,
        builder: (context) => fluent.ContentDialog(
          title: const Text('选择播放平台'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  mergedTrack.name,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              const SizedBox(height: 12),
              ...mergedTrack.tracks.map(
                (track) => fluent.ListTile(
                  leading: Text(
                    track.getSourceIcon(),
                    style: const TextStyle(fontSize: 20),
                  ),
                  title: Text(track.getSourceName()),
                  subtitle: Text(track.album, overflow: TextOverflow.ellipsis),
                  trailing: const Icon(fluent.FluentIcons.play),
                  onPressed: () async {
                    Navigator.pop(context);
                    final isLoggedIn = await _checkLoginStatus();
                    if (isLoggedIn && mounted) {
                      if (track.picUrl.isNotEmpty) {
                        final provider = CachedNetworkImageProvider(
                          track.picUrl,
                        );
                        PlayerService().setCurrentCoverImageProvider(provider);
                        PlayerService().playTrack(
                          track,
                          coverProvider: provider,
                        );
                      } else {
                        PlayerService().playTrack(track);
                      }
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text('正在播放: ${track.name}'),
                          duration: const Duration(seconds: 1),
                        ),
                      );
                    }
                  },
                ),
              ),
            ],
          ),
          actions: [
            fluent.Button(
              onPressed: () => Navigator.pop(context),
              child: const Text('关闭'),
            ),
          ],
        ),
      );
      return;
    }

    showModalBottomSheet(
      context: context,
      builder: (context) => Container(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '选择播放平台',
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(
              mergedTrack.name,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 16),
            ...mergedTrack.tracks.map(
              (track) => ListTile(
                leading: Text(
                  track.getSourceIcon(),
                  style: const TextStyle(fontSize: 24),
                ),
                title: Text(track.getSourceName()),
                subtitle: Text(track.album),
                trailing: const Icon(Icons.play_arrow),
                onTap: () async {
                  Navigator.pop(context);
                  final isLoggedIn = await _checkLoginStatus();
                  if (isLoggedIn && mounted) {
                    if (track.picUrl.isNotEmpty) {
                      final provider = CachedNetworkImageProvider(track.picUrl);
                      PlayerService().setCurrentCoverImageProvider(provider);
                      PlayerService().playTrack(track, coverProvider: provider);
                    } else {
                      PlayerService().playTrack(track);
                    }
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('正在播放: ${track.name}'),
                        duration: const Duration(seconds: 1),
                      ),
                    );
                  }
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 构建搜索历史列表
  Widget _buildSearchHistory() {
    final history = _searchService.searchHistory;
    final colorScheme = Theme.of(context).colorScheme;
    final fluentTheme = fluent.FluentTheme.maybeOf(context);

    // 如果没有历史记录，显示空状态
    if (history.isEmpty) {
      return _buildEmptyState(
        icon: Icons.search,
        title: '搜索音乐',
        subtitle: '支持网易云、QQ音乐、酷狗音乐',
      );
    }

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // 标题栏
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              children: [
                Icon(
                  Icons.history,
                  size: 20,
                  color: colorScheme.onSurfaceVariant,
                ),
                const SizedBox(width: 8),
                Text(
                  '搜索历史',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: colorScheme.onSurface,
                  ),
                ),
              ],
            ),
            _isFluent
                ? fluent.Tooltip(
                    message: '清空',
                    child: fluent.IconButton(
                      icon: Icon(
                        fluent.FluentIcons.delete,
                        color: fluentTheme?.resources?.textFillColorSecondary,
                      ),
                      onPressed: _confirmClearHistory,
                    ),
                  )
                : TextButton.icon(
                    onPressed: _confirmClearHistory,
                    icon: const Icon(Icons.delete_outline, size: 18),
                    label: const Text('清空'),
                    style: TextButton.styleFrom(
                      foregroundColor: colorScheme.error,
                    ),
                  ),
          ],
        ),
        const SizedBox(height: 8),

        // 历史记录列表
        ...history.map((keyword) {
          final trailing = _isFluent
              ? fluent.Tooltip(
                  message: '删除',
                  child: fluent.IconButton(
                    icon: const Icon(fluent.FluentIcons.chrome_close, size: 12),
                    onPressed: () => _searchService.removeSearchHistory(keyword),
                  ),
                )
              : IconButton(
                  icon: Icon(
                    Icons.close,
                    size: 18,
                    color: colorScheme.onSurfaceVariant,
                  ),
                  onPressed: () => _searchService.removeSearchHistory(keyword),
                  tooltip: '删除',
                );

          final tile = _buildAdaptiveListTile(
            leading: Icon(Icons.history, color: colorScheme.primary),
            title: Text(keyword),
            trailing: trailing,
            onPressed: () {
              _searchController.text = keyword;
              _performSearch();
            },
          );

          return _wrapCard(
            margin: const EdgeInsets.only(bottom: 8),
            padding: EdgeInsets.zero,
            child: tile,
          );
        }),

        const SizedBox(height: 16),

        // 提示信息
        Center(
          child: Text(
            '点击历史记录快速搜索',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: colorScheme.onSurfaceVariant.withOpacity(0.7),
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _confirmClearHistory() async {
    bool? confirmed;
    
    if (_isFluent) {
      confirmed = await fluent.showDialog<bool>(
        context: context,
        builder: (context) => fluent.ContentDialog(
          title: const Text('清空搜索历史'),
          content: const Text('确定要清空所有搜索历史吗？'),
          actions: [
            fluent.Button(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('取消'),
            ),
            fluent.FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('清空'),
            ),
          ],
        ),
      );
    } else if (_isCupertino) {
      confirmed = await showCupertinoDialog<bool>(
        context: context,
        builder: (context) => CupertinoAlertDialog(
          title: const Text('清空搜索历史'),
          content: const Text('确定要清空所有搜索历史吗？'),
          actions: [
            CupertinoDialogAction(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('取消'),
            ),
            CupertinoDialogAction(
              isDestructiveAction: true,
              onPressed: () => Navigator.pop(context, true),
              child: const Text('清空'),
            ),
          ],
        ),
      );
    } else {
      confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('清空搜索历史'),
          content: const Text('确定要清空所有搜索历史吗？'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('清空'),
            ),
          ],
        ),
      );
    }

    if (confirmed == true) {
      _searchService.clearSearchHistory();
    }
  }

  Widget _buildEmptyState({
    required IconData icon,
    required String title,
    required String subtitle,
  }) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            icon,
            size: 80,
            color: Theme.of(
              context,
            ).colorScheme.onSurfaceVariant.withOpacity(0.3),
          ),
          const SizedBox(height: 16),
          Text(
            title,
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            subtitle,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: Theme.of(
                context,
              ).colorScheme.onSurfaceVariant.withOpacity(0.7),
            ),
          ),
        ],
      ),
    );
  }
  bool _isPlatformTab(String label) {
    return ['网易云', 'Apple', 'Spotify', 'QQ音乐', '酷狗', '酷我'].contains(label);
  }

  String _getPlatformCodeFromLabel(String label) {
    switch (label) {
      case '网易云': return 'netease';
      case 'Apple': return 'apple';
      case 'Spotify': return 'spotify';
      case 'QQ音乐': return 'qq';
      case '酷狗': return 'kugou';
      case '酷我': return 'kuwo';
      default: return 'netease';
    }
  }

  Color _getPlatformDotColor(String platformCode, Brightness brightness) {
    final isDark = brightness == Brightness.dark;
    switch (platformCode) {
      case 'netease': return isDark ? Colors.redAccent.shade100 : Colors.red;
      case 'apple': return const Color(0xFFFF2D55);
      case 'spotify': return const Color(0xFF1DB954);
      case 'qq': return const Color(0xFF00CFA5); // Slightly teal/bright green to distinguish from Spotify
      case 'kugou': return isDark ? Colors.blueAccent.shade100 : Colors.blue;
      case 'kuwo': return isDark ? Colors.orangeAccent.shade100 : Colors.orange;
      default: return Colors.grey;
    }
  }
}

class _FluentPivotTabs extends StatelessWidget {
  final List<Widget> items;
  final int selectedIndex;
  final ValueChanged<int> onChanged;

  const _FluentPivotTabs({
    Key? key,
    required this.items,
    required this.selectedIndex,
    required this.onChanged,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final theme = fluent.FluentTheme.of(context);
    final accentColor = theme.accentColor;

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: List.generate(items.length, (index) {
          final isSelected = index == selectedIndex;
          return fluent.HoverButton(
            onPressed: () => onChanged(index),
            builder: (context, states) {
              final isHovering = states.isHovering;
              final textColor = isSelected 
                  ? theme.typography.body?.color 
                  : theme.typography.body?.color?.withOpacity(0.7);

              return Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                margin: const EdgeInsets.only(right: 4),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(4),
                  color: isHovering ? theme.resources.controlFillColorSecondary : Colors.transparent, 
                  border: Border(
                    bottom: BorderSide(
                      color: isSelected ? accentColor : Colors.transparent,
                      width: 2,
                    ),
                  ),
                ),
                child: DefaultTextStyle.merge(
                  style: TextStyle(
                    color: textColor,
                    fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                  ),
                  child: items[index],
                ),
              );
            },
          );
        }),
      ),
    );
  }
}

