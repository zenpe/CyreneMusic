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

part 'search_widget_fluent.dart';
part 'search_widget_cupertino.dart';
part 'search_widget_shared.dart';

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
                              suffixIcon: ValueListenableBuilder<TextEditingValue>(
                                valueListenable: _searchController,
                                builder: (context, value, _) {
                                  return value.text.isNotEmpty
                                      ? IconButton(
                                          icon: const Icon(Icons.close, size: 20),
                                          onPressed: () {
                                            _searchController.clear();
                                            _searchService.clear();
                                          },
                                        )
                                      : const SizedBox.shrink();
                                },
                              ),
                              border: InputBorder.none,
                              contentPadding: const EdgeInsets.symmetric(
                                vertical: 14,
                                horizontal: 16,
                              ),
                            ),
                            textInputAction: TextInputAction.search,
                            onSubmitted: (_) => _performSearch(),
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

}
