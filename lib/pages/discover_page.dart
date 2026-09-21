import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:fluent_ui/fluent_ui.dart' as fluent;
import 'package:flutter/cupertino.dart';
import '../features/auth/auth_feature.dart';
import '../services/netease_discover_service.dart';
import '../services/player_service.dart';
import '../models/netease_discover.dart';
import '../utils/image_utils.dart';
import '../utils/theme_manager.dart';
import 'discover_playlist_detail_page.dart';
import 'discover_page/discover_breadcrumbs.dart';
import '../widgets/cupertino/cupertino_discover_widgets.dart';
import '../widgets/skeleton_loader.dart';
import '../widgets/login_prompt.dart';
import '../widgets/audio_source_prompt.dart';
import '../features/audio_source/audio_source_feature.dart';
import 'settings_page/audio_source_settings.dart';

class DiscoverPage extends StatefulWidget {
  const DiscoverPage({super.key});

  @override
  State<DiscoverPage> createState() => _DiscoverPageState();
}

class _DiscoverPageState extends State<DiscoverPage> {
  int? _selectedPlaylistId;
  String? _selectedPlaylistName;
  final ThemeManager _themeManager = ThemeManager();
  final AuthFacade _authFacade = AuthFacade();
  final AudioSourceFacade _audioSourceFacade = AudioSourceFacade();
  late bool _lastAudioConfigured;
  @override
  void initState() {
    super.initState();
    _lastAudioConfigured = _audioSourceFacade.isAudioConfigured;
    if (NeteaseDiscoverService().playlists.isEmpty &&
        !NeteaseDiscoverService().isLoading) {
      NeteaseDiscoverService().fetchDiscoverPlaylists();
    }
    if (NeteaseDiscoverService().tags.isEmpty) {
      NeteaseDiscoverService().fetchTags();
    }
    NeteaseDiscoverService().addListener(_onChanged);
    _audioSourceFacade.addAudioSourceStateListener(_onAudioSourceChanged);
  }

  @override
  void dispose() {
    NeteaseDiscoverService().removeListener(_onChanged);
    _audioSourceFacade.removeAudioSourceStateListener(_onAudioSourceChanged);
    super.dispose();
  }

  void _onChanged() {
    if (mounted) setState(() {});
  }

  void _onAudioSourceChanged() {
    final isConfigured = _audioSourceFacade.isAudioConfigured;
    if (!mounted || isConfigured == _lastAudioConfigured) {
      return;
    }
    _lastAudioConfigured = isConfigured;
    setState(() {});
  }

  /// 导航到音源设置页面
  void _navigateToAudioSourceSettings(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (context) => const AudioSourceSettings()),
    );
  }

  @override
  Widget build(BuildContext context) {
    final service = NeteaseDiscoverService();

    if (_themeManager.isFluentFramework) {
      return _buildFluentPage(context, service);
    }

    if ((Platform.isIOS || Platform.isAndroid) &&
        _themeManager.isCupertinoFramework) {
      return _buildCupertinoPage(context, service);
    }

    return _buildMaterialPage(context, service);
  }

  Widget _buildCupertinoPage(
    BuildContext context,
    NeteaseDiscoverService service,
  ) {
    // 未登录状态下显示登录提示
    if (!_authFacade.isLoggedIn) {
      return CupertinoPageScaffold(
        child: CustomScrollView(
          slivers: [
            const CupertinoSliverNavigationBar(
              largeTitle: Text('发现'),
              border: null,
              backgroundColor: null,
            ),
            SliverFillRemaining(
              child: LoginPrompt(
                title: '登录后发现更多精彩',
                subtitle: '登录即可浏览热门歌单、发现新音乐',
                onLoginPressed: () {
                  // LoginPrompt 内部已处理登录，这里只需刷新状态
                  if (mounted && _authFacade.isLoggedIn) {
                    setState(() {});
                  }
                },
              ),
            ),
          ],
        ),
      );
    }

    // 已登录但音源未配置时，显示音源配置提示
    if (!_audioSourceFacade.isAudioConfigured) {
      return CupertinoPageScaffold(
        child: CustomScrollView(
          slivers: [
            const CupertinoSliverNavigationBar(
              largeTitle: Text('发现'),
              border: null,
              backgroundColor: null,
            ),
            SliverFillRemaining(
              child: AudioSourcePrompt(
                title: '配置音源后发现更多',
                subtitle: '配置音源服务后即可浏览热门歌单、发现新音乐',
                onConfigurePressed: () =>
                    _navigateToAudioSourceSettings(context),
              ),
            ),
          ],
        ),
      );
    }

    // 如果选中了歌单，显示详情页（模拟导航堆栈）
    if (_selectedPlaylistId != null) {
      return CupertinoPageScaffold(
        navigationBar: CupertinoNavigationBar(
          previousPageTitle: '发现',
          middle: Text(_selectedPlaylistName ?? '歌单详情'),
          leading: CupertinoNavigationBarBackButton(
            onPressed: () {
              setState(() {
                _selectedPlaylistId = null;
                _selectedPlaylistName = null;
              });
            },
          ),
        ),
        child: SafeArea(
          bottom: false,
          child: DiscoverPlaylistDetailContent(
            playlistId: _selectedPlaylistId!,
          ),
        ),
      );
    }

    return CupertinoPageScaffold(
      child: CustomScrollView(
        slivers: [
          const CupertinoSliverNavigationBar(
            largeTitle: Text('发现'),
            border: null,
            // 使用默认或半透明背景以避免内容重叠
            backgroundColor: null,
          ),
          CupertinoSliverRefreshControl(
            onRefresh: () async {
              final currentCat = NeteaseDiscoverService().currentCat;
              await NeteaseDiscoverService().fetchDiscoverPlaylists(
                cat: currentCat,
              );
            },
          ),
          ..._buildCupertinoSlivers(service),
          const SliverToBoxAdapter(child: SizedBox(height: 80)),
        ],
      ),
    );
  }

  List<Widget> _buildCupertinoSlivers(NeteaseDiscoverService service) {
    final items = service.playlists;
    final hasItems = items.isNotEmpty;

    if (service.isLoading && !hasItems) {
      return [
        // 使用骨架屏替代简单的加载指示器
        const MobileDiscoverPageSliverSkeleton(),
      ];
    }

    if (service.errorMessage != null && !hasItems && !service.isLoading) {
      return [
        SliverFillRemaining(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(24.0),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    CupertinoIcons.exclamationmark_circle,
                    size: 48,
                    color: CupertinoColors.systemRed,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    service.errorMessage!,
                    style: const TextStyle(color: CupertinoColors.systemGrey),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 16),
                  CupertinoButton(
                    child: const Text('重试'),
                    onPressed: () =>
                        NeteaseDiscoverService().fetchDiscoverPlaylists(),
                  ),
                ],
              ),
            ),
          ),
        ),
      ];
    }

    final slivers = <Widget>[
      if (service.isLoading)
        const SliverToBoxAdapter(
          child: Padding(
            padding: EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: Center(child: CupertinoActivityIndicator()),
          ),
        ),
      if (service.errorMessage != null && hasItems)
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: CupertinoColors.systemRed.withOpacity(0.12),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  const Icon(
                    CupertinoIcons.exclamationmark_triangle_fill,
                    color: CupertinoColors.systemRed,
                    size: 18,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      service.errorMessage!,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: CupertinoColors.systemRed,
                        fontSize: 13,
                      ),
                    ),
                  ),
                  CupertinoButton(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    minSize: 0,
                    onPressed: () {
                      final currentCat = NeteaseDiscoverService().currentCat;
                      NeteaseDiscoverService().fetchDiscoverPlaylists(
                        cat: currentCat,
                      );
                    },
                    child: const Text('重试'),
                  ),
                ],
              ),
            ),
          ),
        ),
    ];

    if (items.isEmpty) {
      return [
        ...slivers,
        const SliverFillRemaining(child: Center(child: Text('暂无数据'))),
      ];
    }

    return [
      ...slivers,
      // 1. 分类选择器
      SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
          child: Row(
            children: [
              CupertinoTagSelector(
                currentTag: service.currentCat,
                onTap: () => _showCupertinoTagDialog(service),
              ),
            ],
          ),
        ),
      ),
      // 2. 歌单网格 - 使用 SliverGrid 优化性能
      SliverPadding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        sliver: SliverLayoutBuilder(
          builder: (context, constraints) {
            final width = constraints.crossAxisExtent;
            int crossAxisCount = 2;
            if (width >= 600) crossAxisCount = 3;
            if (width >= 800) crossAxisCount = 4;
            if (width >= 1200) crossAxisCount = 5;

            return SliverGrid(
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: crossAxisCount,
                mainAxisSpacing: 16,
                crossAxisSpacing: 16,
                childAspectRatio: 0.75,
              ),
              delegate: SliverChildBuilderDelegate((context, index) {
                return CupertinoDiscoverPlaylistCard(
                  summary: items[index],
                  onTap: () {
                    setState(() {
                      _selectedPlaylistId = items[index].id;
                      _selectedPlaylistName = items[index].name;
                    });
                  },
                );
              }, childCount: items.length),
            );
          },
        ),
      ),
    ];
  }

  void _showCupertinoTagDialog(NeteaseDiscoverService service) {
    showCupertinoModalPopup(
      context: context,
      builder: (context) => CupertinoActionSheet(
        title: const Text('选择歌单类型'),
        message: const Text('请选择您感兴趣的歌单分类'),
        actions: [
          CupertinoActionSheetAction(
            isDefaultAction:
                service.currentCat.isEmpty || service.currentCat == '全部歌单',
            onPressed: () {
              Navigator.pop(context);
              NeteaseDiscoverService().fetchDiscoverPlaylists(cat: '全部歌单');
            },
            child: const Text('全部歌单'),
          ),
          ...service.tags.map(
            (t) => CupertinoActionSheetAction(
              isDefaultAction: service.currentCat == t.name,
              onPressed: () {
                Navigator.pop(context);
                NeteaseDiscoverService().fetchDiscoverPlaylists(cat: t.name);
              },
              child: Text(t.name),
            ),
          ),
        ],
        cancelButton: CupertinoActionSheetAction(
          isDestructiveAction: true,
          onPressed: () => Navigator.pop(context),
          child: const Text('取消'),
        ),
      ),
    );
  }

  Widget _buildMaterialPage(
    BuildContext context,
    NeteaseDiscoverService service,
  ) {
    final colorScheme = Theme.of(context).colorScheme;
    final isExpressive =
        !ThemeManager().isFluentFramework &&
        !ThemeManager().isCupertinoFramework &&
        (Platform.isAndroid || Platform.isIOS);

    // 未登录状态下显示登录提示
    if (!_authFacade.isLoggedIn) {
      return Scaffold(
        backgroundColor: colorScheme.surface,
        body: CustomScrollView(
          slivers: [
            SliverAppBar(
              floating: true,
              snap: true,
              backgroundColor: colorScheme.surface,
              title: Text(
                '发现',
                style: TextStyle(
                  color: colorScheme.onSurface,
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            SliverFillRemaining(
              child: LoginPrompt(
                title: '登录后发现更多精彩',
                subtitle: '登录即可浏览热门歌单、发现新音乐',
                onLoginPressed: () {
                  // LoginPrompt 内部已处理登录，这里只需刷新状态
                  if (mounted && _authFacade.isLoggedIn) {
                    setState(() {});
                  }
                },
              ),
            ),
          ],
        ),
      );
    }

    // 已登录但音源未配置时，显示音源配置提示
    if (!_audioSourceFacade.isAudioConfigured) {
      return Scaffold(
        backgroundColor: colorScheme.surface,
        body: CustomScrollView(
          slivers: [
            SliverAppBar(
              floating: true,
              snap: true,
              backgroundColor: colorScheme.surface,
              title: Text(
                '发现',
                style: TextStyle(
                  color: colorScheme.onSurface,
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            SliverFillRemaining(
              child: AudioSourcePrompt(
                title: '配置音源后发现更多',
                subtitle: '配置音源服务后即可浏览热门歌单、发现新音乐',
                onConfigurePressed: () =>
                    _navigateToAudioSourceSettings(context),
              ),
            ),
          ],
        ),
      );
    }

    // Material 桌面分支：选中歌单时展示详情内容
    if (_selectedPlaylistId != null) {
      return Scaffold(
        backgroundColor: isExpressive
            ? colorScheme.surfaceContainerLow
            : colorScheme.surface,
        appBar: AppBar(
          backgroundColor: isExpressive
              ? colorScheme.surfaceContainerLow
              : colorScheme.surface,
          surfaceTintColor: isExpressive
              ? colorScheme.surfaceContainerLow
              : colorScheme.surface,
          title: Text(_selectedPlaylistName ?? '歌单详情'),
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: () {
              setState(() {
                _selectedPlaylistId = null;
                _selectedPlaylistName = null;
              });
            },
          ),
        ),
        body: DiscoverPlaylistDetailContent(playlistId: _selectedPlaylistId!),
      );
    }

    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bgBase = isDark ? const Color(0xFF0F0F13) : const Color(0xFFF7F8FA);

    return ValueListenableBuilder<Color?>(
      valueListenable: PlayerService().themeColorNotifier,
      builder: (context, themeColor, child) {
        final accent = themeColor ?? colorScheme.primary;

        return Scaffold(
          backgroundColor: bgBase,
          body: Stack(
            children: [
              // 顶部流体微光背景 (与全站统一的 Apple Music 动态氛围光)
              Positioned(
                top: -60,
                left: 0,
                right: 0,
                height: 320,
                child: IgnorePointer(
                  child: Container(
                    decoration: BoxDecoration(
                      gradient: RadialGradient(
                        center: const Alignment(0.0, -0.6),
                        radius: 1.25,
                        colors: [
                          accent.withOpacity(isDark ? 0.22 : 0.16),
                          accent.withOpacity(isDark ? 0.08 : 0.05),
                          Colors.transparent,
                        ],
                        stops: const [0.0, 0.55, 1.0],
                      ),
                    ),
                  ),
                ),
              ),
              RefreshIndicator(
                onRefresh: () async {
                  final currentCat = NeteaseDiscoverService().currentCat;
                  await NeteaseDiscoverService().fetchDiscoverPlaylists(
                    cat: currentCat,
                  );
                },
                child: CustomScrollView(
                  physics: const AlwaysScrollableScrollPhysics(
                    parent: BouncingScrollPhysics(),
                  ),
                  slivers: [
                    SliverAppBar(
                      pinned: true,
                      backgroundColor: Colors.transparent,
                      surfaceTintColor: Colors.transparent,
                      elevation: 0,
                      scrolledUnderElevation: 0,
                      flexibleSpace: ClipRect(
                        child: BackdropFilter(
                          filter: ui.ImageFilter.blur(sigmaX: 16, sigmaY: 16),
                          child: Container(
                            color: bgBase.withOpacity(0.72),
                          ),
                        ),
                      ),
                      title: Text(
                        '发现',
                        style: TextStyle(
                          color: colorScheme.onSurface,
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      actions: [
                        IconButton(
                          icon: const Icon(Icons.refresh_rounded),
                          tooltip: '刷新',
                          onPressed: () {
                            final currentCat = NeteaseDiscoverService().currentCat;
                            NeteaseDiscoverService().fetchDiscoverPlaylists(
                              cat: currentCat,
                            );
                          },
                        ),
                      ],
                    ),
                    SliverPadding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16.0,
                        vertical: 8.0,
                      ),
                      sliver: SliverToBoxAdapter(
                        child: _buildMaterialContent(service, isExpressive, accent),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildMaterialContent(
    NeteaseDiscoverService service,
    bool isExpressive,
    Color accent,
  ) {
    final items = service.playlists;
    final hasItems = items.isNotEmpty;

    if (service.isLoading && !hasItems) {
      // 使用骨架屏替代简单的加载指示器
      return const Padding(
        padding: EdgeInsets.symmetric(horizontal: 16.0),
        child: MobileDiscoverPageSkeleton(),
      );
    }
    if (service.errorMessage != null && !hasItems && !service.isLoading) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline, size: 48, color: Colors.red),
              const SizedBox(height: 16),
              Text(service.errorMessage!, textAlign: TextAlign.center),
              const SizedBox(height: 16),
              ElevatedButton.icon(
                onPressed: () {
                  final currentCat = NeteaseDiscoverService().currentCat;
                  NeteaseDiscoverService().fetchDiscoverPlaylists(
                    cat: currentCat,
                  );
                },
                icon: const Icon(Icons.refresh),
                label: const Text('重试'),
              ),
            ],
          ),
        ),
      );
    }

    if (items.isEmpty) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (service.isLoading)
            const Padding(
              padding: EdgeInsets.only(bottom: 12),
              child: LinearProgressIndicator(minHeight: 2),
            ),
          const SizedBox(height: 24),
          const Center(child: Text('暂无数据')),
        ],
      );
    }

    // 顶部分类选择 + 自适应网格
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (service.isLoading)
          const Padding(
            padding: EdgeInsets.only(bottom: 12),
            child: LinearProgressIndicator(minHeight: 2),
          ),
        if (service.errorMessage != null && hasItems)
          Container(
            margin: const EdgeInsets.only(bottom: 12),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Theme.of(
                context,
              ).colorScheme.errorContainer.withOpacity(0.65),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.error_outline,
                  color: Theme.of(context).colorScheme.onErrorContainer,
                  size: 18,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    service.errorMessage!,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onErrorContainer,
                    ),
                  ),
                ),
                TextButton(
                  onPressed: () {
                    final currentCat = NeteaseDiscoverService().currentCat;
                    NeteaseDiscoverService().fetchDiscoverPlaylists(
                      cat: currentCat,
                    );
                  },
                  child: const Text('重试'),
                ),
              ],
            ),
          ),
        LayoutBuilder(
          builder: (context, constraints) {
            final width = constraints.maxWidth;
            int crossAxisCount = 2;
            if (width >= 1200)
              crossAxisCount = 6;
            else if (width >= 1000)
              crossAxisCount = 5;
            else if (width >= 800)
              crossAxisCount = 4;
            else if (width >= 600)
              crossAxisCount = 3;

            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildMaterialTagSelector(service, accent),
                const SizedBox(height: 16),
                GridView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: crossAxisCount,
                    mainAxisSpacing: 18,
                    crossAxisSpacing: 14,
                    childAspectRatio: 0.72,
                  ),
                  itemCount: items.length,
                  itemBuilder: (context, index) => _MaterialPlaylistCard(
                    summary: items[index],
                    isExpressive: isExpressive,
                    onOpen: (id, name) {
                      setState(() {
                        _selectedPlaylistId = id;
                        _selectedPlaylistName = name;
                      });
                    },
                  ),
                ),
                const SizedBox(height: 120), // 彻底避让悬浮 MiniPlayer
              ],
            );
          },
        ),
      ],
    );
  }

  Widget _buildMaterialTagSelector(
    NeteaseDiscoverService service,
    Color accent,
  ) {
    final current = service.currentCat;
    final label = current.isEmpty ? '全部歌单' : current;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => _showMaterialTagDialog(service),
        borderRadius: BorderRadius.circular(20),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
          decoration: BoxDecoration(
            color: accent.withOpacity(isDark ? 0.16 : 0.08),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: accent.withOpacity(isDark ? 0.35 : 0.2),
              width: 1,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.tune_rounded,
                size: 16,
                color: accent,
              ),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  color: isDark ? Colors.white : const Color(0xFF1E293B),
                  fontWeight: FontWeight.w700,
                  fontSize: 13.5,
                ),
              ),
              const SizedBox(width: 4),
              Icon(
                Icons.keyboard_arrow_down_rounded,
                size: 18,
                color: accent.withOpacity(0.8),
              ),
            ],
          ),
        ),
      ),
    );
  }

  static const Map<int, String> _tagCategoryNames = {
    0: '语种',
    1: '风格',
    2: '场景',
    3: '情感',
    4: '主题',
  };

  void _showMaterialTagDialog(NeteaseDiscoverService service) {
    final tags = service.tags;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final colorScheme = Theme.of(context).colorScheme;
    final themeColor = PlayerService().themeColorNotifier.value ?? colorScheme.primary;

    // 按分类归类
    final Map<int, List<NeteaseTag>> groupedTags = {};
    for (final tag in tags) {
      groupedTags.putIfAbsent(tag.category, () => []).add(tag);
    }

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withOpacity(0.45),
      isScrollControlled: true,
      builder: (context) {
        return ClipRRect(
          borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
          child: BackdropFilter(
            filter: ui.ImageFilter.blur(sigmaX: 25, sigmaY: 25),
            child: Container(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.of(context).size.height * 0.75,
              ),
              decoration: BoxDecoration(
                color: (isDark ? const Color(0xFF16161A) : Colors.white).withOpacity(
                  isDark ? 0.88 : 0.94,
                ),
                borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
                border: Border(
                  top: BorderSide(
                    color: (isDark ? Colors.white : Colors.black).withOpacity(0.08),
                    width: 0.8,
                  ),
                ),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const SizedBox(height: 10),
                  // 顶部抽屉拖动手柄
                  Center(
                    child: Container(
                      width: 40,
                      height: 4.5,
                      decoration: BoxDecoration(
                        color: (isDark ? Colors.white : Colors.black).withOpacity(0.18),
                        borderRadius: BorderRadius.circular(3),
                      ),
                    ),
                  ),
                  // 顶部标题栏
                  Padding(
                    padding: const EdgeInsets.fromLTRB(22, 12, 16, 8),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '歌单分类',
                              style: TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.w800,
                                letterSpacing: -0.3,
                                color: colorScheme.onSurface,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              '当前：${service.currentCat.isEmpty ? '全部歌单' : service.currentCat}',
                              style: TextStyle(
                                fontSize: 12,
                                color: colorScheme.onSurfaceVariant.withOpacity(0.7),
                              ),
                            ),
                          ],
                        ),
                        IconButton(
                          onPressed: () => Navigator.of(context).pop(),
                          icon: Container(
                            padding: const EdgeInsets.all(4),
                            decoration: BoxDecoration(
                              color: (isDark ? Colors.white : Colors.black).withOpacity(0.06),
                              shape: BoxShape.circle,
                            ),
                            child: Icon(
                              Icons.close_rounded,
                              size: 20,
                              color: colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const Divider(height: 1, thickness: 0.5),
                  // 可滚动分类列表
                  Flexible(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.fromLTRB(20, 16, 20, 28),
                      physics: const BouncingScrollPhysics(),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // 全部歌单快捷按钮
                          _buildFilterChip(
                            label: '全部歌单',
                            icon: Icons.all_inclusive_rounded,
                            isSelected: service.currentCat.isEmpty || service.currentCat == '全部歌单',
                            onSelected: () {
                              Navigator.of(context).pop();
                              NeteaseDiscoverService().fetchDiscoverPlaylists(cat: '全部歌单');
                            },
                          ),
                          const SizedBox(height: 16),
                          if (groupedTags.isNotEmpty) ...[
                            for (final entry in groupedTags.entries) ...[
                              Padding(
                                padding: const EdgeInsets.only(top: 8, bottom: 10),
                                child: Row(
                                  children: [
                                    Container(
                                      width: 3.5,
                                      height: 14,
                                      decoration: BoxDecoration(
                                        color: themeColor,
                                        borderRadius: BorderRadius.circular(2),
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Text(
                                      _tagCategoryNames[entry.key] ?? '分类 ${entry.key}',
                                      style: TextStyle(
                                        fontSize: 13,
                                        fontWeight: FontWeight.bold,
                                        color: colorScheme.onSurfaceVariant,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              Wrap(
                                spacing: 8,
                                runSpacing: 10,
                                children: entry.value.map((t) => _buildFilterChip(
                                  label: t.name,
                                  isSelected: service.currentCat == t.name,
                                  onSelected: () {
                                    Navigator.of(context).pop();
                                    NeteaseDiscoverService().fetchDiscoverPlaylists(cat: t.name);
                                  },
                                )).toList(),
                              ),
                              const SizedBox(height: 14),
                            ],
                          ] else ...[
                            Wrap(
                              spacing: 8,
                              runSpacing: 10,
                              children: tags.map((t) => _buildFilterChip(
                                label: t.name,
                                isSelected: service.currentCat == t.name,
                                onSelected: () {
                                  Navigator.of(context).pop();
                                  NeteaseDiscoverService().fetchDiscoverPlaylists(cat: t.name);
                                },
                              )).toList(),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildFilterChip({
    required String label,
    required bool isSelected,
    required VoidCallback onSelected,
    IconData? icon,
  }) {
    final themeColor = PlayerService().themeColorNotifier.value ?? Theme.of(context).colorScheme.primary;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onSelected,
        borderRadius: BorderRadius.circular(20),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOutCubic,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            color: isSelected
                ? themeColor
                : (isDark ? Colors.white.withOpacity(0.08) : Colors.black.withOpacity(0.04)),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: isSelected
                  ? themeColor
                  : (isDark ? Colors.white.withOpacity(0.08) : Colors.black.withOpacity(0.06)),
              width: 0.8,
            ),
            boxShadow: isSelected
                ? [
                    BoxShadow(
                      color: themeColor.withOpacity(0.35),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ]
                : null,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (icon != null) ...[
                Icon(
                  icon,
                  size: 14,
                  color: isSelected
                      ? Colors.white
                      : (isDark ? Colors.white70 : const Color(0xFF334155)),
                ),
                const SizedBox(width: 4),
              ],
              Text(
                label,
                style: TextStyle(
                  color: isSelected
                      ? Colors.white
                      : (isDark ? Colors.white.withOpacity(0.85) : const Color(0xFF334155)),
                  fontSize: 13,
                  fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildFluentPage(
    BuildContext context,
    NeteaseDiscoverService service,
  ) {
    // 未登录状态下显示登录提示
    if (!_authFacade.isLoggedIn) {
      return fluent.ScaffoldPage(
        padding: EdgeInsets.zero,
        content: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
              child: FluentDiscoverBreadcrumbs(
                items: [
                  DiscoverBreadcrumbItem(
                    label: '发现',
                    isEmphasized: true,
                    isCurrent: true,
                  ),
                ],
                padding: EdgeInsets.zero,
              ),
            ),
            Expanded(
              child: LoginPrompt(
                title: '登录后发现更多精彩',
                subtitle: '登录即可浏览热门歌单、发现新音乐',
                onLoginPressed: () {
                  if (mounted && _authFacade.isLoggedIn) {
                    setState(() {});
                  }
                },
              ),
            ),
          ],
        ),
      );
    }

    // 已登录但音源未配置时，显示音源配置提示
    if (!_audioSourceFacade.isAudioConfigured) {
      return fluent.ScaffoldPage(
        padding: EdgeInsets.zero,
        content: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
              child: FluentDiscoverBreadcrumbs(
                items: [
                  DiscoverBreadcrumbItem(
                    label: '发现',
                    isEmphasized: true,
                    isCurrent: true,
                  ),
                ],
                padding: EdgeInsets.zero,
              ),
            ),
            Expanded(
              child: AudioSourcePrompt(
                title: '配置音源后发现更多',
                subtitle: '配置音源服务后即可浏览热门歌单、发现新音乐',
                onConfigurePressed: () =>
                    _navigateToAudioSourceSettings(context),
              ),
            ),
          ],
        ),
      );
    }

    return fluent.ScaffoldPage(
      padding: EdgeInsets.zero,
      content: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
            child: Row(
              children: [
                Expanded(
                  child: FluentDiscoverBreadcrumbs(
                    items: _buildFluentBreadcrumbItems(service),
                    padding: EdgeInsets.zero,
                  ),
                ),
                const SizedBox(width: 12),
                fluent.Tooltip(
                  message: '刷新',
                  child: fluent.IconButton(
                    icon: const Icon(fluent.FluentIcons.refresh, size: 16),
                    onPressed: () {
                      final currentCat = NeteaseDiscoverService().currentCat;
                      NeteaseDiscoverService().fetchDiscoverPlaylists(
                        cat: currentCat,
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
          // Removed Divider to avoid white line between header and content under acrylic/mica
          Expanded(
            child: _buildFluentSlidingSwitcher(
              _buildFluentContent(context, service),
            ),
          ),
        ],
      ),
    );
  }

  void _resetSelection() {
    setState(() {
      _selectedPlaylistId = null;
      _selectedPlaylistName = null;
    });
  }

  Widget _buildFluentContent(
    BuildContext context,
    NeteaseDiscoverService service,
  ) {
    final padding = const EdgeInsets.fromLTRB(24, 0, 24, 24);

    if (_selectedPlaylistId != null) {
      final brightness = switch (_themeManager.themeMode) {
        ThemeMode.system => MediaQuery.platformBrightnessOf(context),
        ThemeMode.dark => Brightness.dark,
        _ => Brightness.light,
      };
      final materialTheme = _themeManager.buildThemeData(brightness);

      return Padding(
        key: ValueKey('discover_detail_${_selectedPlaylistId}'),
        padding: padding,
        child: Theme(
          data: materialTheme,
          child: Material(
            color: Colors.transparent,
            child: DiscoverPlaylistDetailContent(
              playlistId: _selectedPlaylistId!,
            ),
          ),
        ),
      );
    }

    final items = service.playlists;
    final hasItems = items.isNotEmpty;

    if (service.isLoading && !hasItems) {
      return const DiscoverPageSkeleton(key: ValueKey('discover_loading'));
    }

    if (service.errorMessage != null && !hasItems && !service.isLoading) {
      return Padding(
        key: const ValueKey('discover_error'),
        padding: padding,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            fluent.InfoBar(
              title: const Text('加载失败'),
              content: Text(service.errorMessage!),
              severity: fluent.InfoBarSeverity.error,
            ),
            const SizedBox(height: 16),
            fluent.Button(
              onPressed: () {
                final currentCat = NeteaseDiscoverService().currentCat;
                NeteaseDiscoverService().fetchDiscoverPlaylists(
                  cat: currentCat,
                );
              },
              child: const Text('重试'),
            ),
          ],
        ),
      );
    }

    if (items.isEmpty) {
      return Padding(
        key: const ValueKey('discover_empty'),
        padding: padding,
        child: fluent.InfoBar(
          title: const Text('暂无歌单'),
          content: const Text('请稍后再试或更换分类'),
          severity: fluent.InfoBarSeverity.info,
        ),
      );
    }

    return LayoutBuilder(
      key: ValueKey('discover_list_${service.currentCat}_${items.length}'),
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        int crossAxisCount = 2;
        if (width >= 1200) {
          crossAxisCount = 6;
        } else if (width >= 1000) {
          crossAxisCount = 5;
        } else if (width >= 800) {
          crossAxisCount = 4;
        } else if (width >= 600) {
          crossAxisCount = 3;
        }

        return SingleChildScrollView(
          padding: padding,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (service.isLoading)
                const Padding(
                  padding: EdgeInsets.only(bottom: 12),
                  child: fluent.ProgressBar(),
                ),
              if (service.errorMessage != null && hasItems) ...[
                fluent.InfoBar(
                  title: const Text('刷新失败'),
                  content: Text(service.errorMessage!),
                  severity: fluent.InfoBarSeverity.warning,
                  action: fluent.Button(
                    onPressed: () {
                      final currentCat = NeteaseDiscoverService().currentCat;
                      NeteaseDiscoverService().fetchDiscoverPlaylists(
                        cat: currentCat,
                      );
                    },
                    child: const Text('重试'),
                  ),
                ),
                const SizedBox(height: 12),
              ],
              _buildFluentTagSelector(service),
              const SizedBox(height: 16),
              GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: crossAxisCount,
                  mainAxisSpacing: 16,
                  crossAxisSpacing: 16,
                  childAspectRatio: 0.72,
                ),
                itemCount: items.length,
                itemBuilder: (context, index) => _FluentPlaylistCard(
                  summary: items[index],
                  onOpen: (id, name) {
                    setState(() {
                      _selectedPlaylistId = id;
                      _selectedPlaylistName = name;
                    });
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildFluentTagSelector(NeteaseDiscoverService service) {
    final current = service.currentCat;
    final displayLabel = current.isEmpty ? '全部歌单' : current;
    final allLabel = '全部歌单';

    return fluent.DropDownButton(
      title: Text(displayLabel),
      items: [
        fluent.MenuFlyoutItem(
          text: const Text('全部歌单'),
          onPressed: () {
            NeteaseDiscoverService().fetchDiscoverPlaylists(cat: allLabel);
          },
        ),
        ...service.tags.map(
          (t) => fluent.MenuFlyoutItem(
            text: Text(t.name),
            onPressed: () {
              NeteaseDiscoverService().fetchDiscoverPlaylists(cat: t.name);
            },
          ),
        ),
      ],
    );
  }

  List<DiscoverBreadcrumbItem> _buildFluentBreadcrumbItems(
    NeteaseDiscoverService service,
  ) {
    final isDetail = _selectedPlaylistId != null;
    final currentTag = service.currentCat.trim();
    final hasCustomTag = currentTag.isNotEmpty && currentTag != '全部歌单';

    final items = <DiscoverBreadcrumbItem>[
      DiscoverBreadcrumbItem(
        label: '发现',
        isEmphasized: true,
        isCurrent: !isDetail,
        onTap: isDetail ? _resetSelection : null,
      ),
    ];

    if (!isDetail && hasCustomTag) {
      items.add(
        DiscoverBreadcrumbItem(
          label: currentTag,
          isCurrent: true,
          isEmphasized: true,
        ),
      );
    }

    if (isDetail) {
      if (hasCustomTag) {
        items.add(
          DiscoverBreadcrumbItem(label: currentTag, onTap: _resetSelection),
        );
      }

      final detailLabel = (_selectedPlaylistName ?? '').trim().isEmpty
          ? '歌单详情'
          : _selectedPlaylistName!;
      items.add(
        DiscoverBreadcrumbItem(
          label: detailLabel,
          isCurrent: true,
          isEmphasized: true,
        ),
      );
    }

    return items;
  }

  Widget _buildFluentSlidingSwitcher(Widget child) {
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 280),
      switchInCurve: Curves.easeOutCubic,
      switchOutCurve: Curves.easeInCubic,
      transitionBuilder: (child, animation) =>
          _buildFluentSlideTransition(child, animation),
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

  Widget _buildFluentSlideTransition(
    Widget child,
    Animation<double> animation,
  ) {
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
}

class _MaterialPlaylistCard extends StatelessWidget {
  final NeteasePlaylistSummary summary;
  final bool isExpressive;
  final void Function(int id, String name)? onOpen;

  const _MaterialPlaylistCard({
    required this.summary,
    this.isExpressive = false,
    this.onOpen,
  });

  String _formatPlayCount(int count) {
    if (count > 100000000) {
      return '${(count / 100000000).toStringAsFixed(1)}亿';
    }
    if (count > 10000) {
      return '${(count / 10000).toStringAsFixed(1)}万';
    }
    return count.toString();
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () {
          if (onOpen != null) {
            onOpen!(summary.id, summary.name);
          } else {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) =>
                    DiscoverPlaylistDetailPage(playlistId: summary.id),
              ),
            );
          }
        },
        borderRadius: BorderRadius.circular(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 封面图片 (Apple Music 风格：纯粹大圆角 + 自然阴影 + 右上角微型半透明播放量角标)
            AspectRatio(
              aspectRatio: 1,
              child: Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(14),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(isDark ? 0.35 : 0.08),
                      blurRadius: 10,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(14),
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      Hero(
                        tag: 'playlist_cover_${summary.id}',
                        child: CachedNetworkImage(
                          imageUrl: summary.coverImgUrl,
                          httpHeaders: getImageHeaders(summary.coverImgUrl),
                          fit: BoxFit.cover,
                          memCacheWidth: 280,
                          memCacheHeight: 280,
                          placeholder: (context, url) => Container(
                            color: colorScheme.surfaceContainerHighest,
                          ),
                          errorWidget: (context, url, error) => Container(
                            color: colorScheme.surfaceContainerHighest,
                            child: Icon(
                              Icons.music_note_rounded,
                              color: colorScheme.primary,
                            ),
                          ),
                        ),
                      ),
                      // 播放量胶囊
                      Positioned(
                        top: 6,
                        right: 6,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: Colors.black.withOpacity(0.55),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(
                                Icons.play_arrow_rounded,
                                color: Colors.white,
                                size: 12,
                              ),
                              const SizedBox(width: 2),
                              Text(
                                _formatPlayCount(summary.playCount),
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 10,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 8),
            // 歌单标题 (2行自适应截断)
            Text(
              summary.name,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: colorScheme.onSurface,
                fontSize: 13.5,
                fontWeight: FontWeight.w700,
                height: 1.25,
                letterSpacing: -0.1,
              ),
            ),
            const SizedBox(height: 3),
            // 创建者
            Text(
              'by ${summary.creatorNickname}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: colorScheme.onSurfaceVariant.withOpacity(0.7),
                fontSize: 11.5,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FluentPlaylistCard extends StatelessWidget {
  final NeteasePlaylistSummary summary;
  final void Function(int id, String name)? onOpen;
  const _FluentPlaylistCard({required this.summary, this.onOpen});

  @override
  Widget build(BuildContext context) {
    final theme = fluent.FluentTheme.of(context);
    final borderRadius = BorderRadius.circular(12);

    return fluent.Card(
      borderRadius: borderRadius,
      padding: EdgeInsets.zero,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => onOpen?.call(summary.id, summary.name),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AspectRatio(
              aspectRatio: 1,
              child: ClipRRect(
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(12),
                ),
                child: CachedNetworkImage(
                  imageUrl: summary.coverImgUrl,
                  httpHeaders: getImageHeaders(summary.coverImgUrl),
                  fit: BoxFit.cover,
                  memCacheWidth: 280,
                  memCacheHeight: 280,
                  placeholder: (context, url) => Container(
                    color: theme.resources.controlAltFillColorSecondary,
                  ),
                  errorWidget: (context, url, error) => Container(
                    color: theme.resources.controlAltFillColorSecondary,
                    alignment: Alignment.center,
                    child: fluent.Icon(
                      fluent.FluentIcons.music_in_collection,
                      color: theme.resources.textFillColorTertiary,
                    ),
                  ),
                ),
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(10.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      summary.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 15,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'by ${summary.creatorNickname}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12,
                        color: theme.resources.textFillColorSecondary,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${summary.trackCount} 首 · 播放 ${summary.playCount}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 11,
                        color: theme.resources.textFillColorTertiary,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
