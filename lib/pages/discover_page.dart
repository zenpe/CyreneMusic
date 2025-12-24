import 'dart:io';
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:fluent_ui/fluent_ui.dart' as fluent;
import 'package:flutter/cupertino.dart';
import '../services/netease_discover_service.dart';
import '../services/auth_service.dart';
import '../models/netease_discover.dart';
import '../utils/theme_manager.dart';
import 'discover_playlist_detail_page.dart';
import 'discover_page/discover_breadcrumbs.dart';
import '../widgets/cupertino/cupertino_discover_widgets.dart';
import '../widgets/skeleton_loader.dart';
import '../widgets/login_prompt.dart';
import 'auth/auth_page.dart';

class DiscoverPage extends StatefulWidget {
  const DiscoverPage({super.key});

  @override
  State<DiscoverPage> createState() => _DiscoverPageState();
}

class _DiscoverPageState extends State<DiscoverPage> {
  int? _selectedPlaylistId;
  String? _selectedPlaylistName;
  final ThemeManager _themeManager = ThemeManager();
  @override
  void initState() {
    super.initState();
    if (NeteaseDiscoverService().playlists.isEmpty && !NeteaseDiscoverService().isLoading) {
      NeteaseDiscoverService().fetchDiscoverPlaylists();
    }
    if (NeteaseDiscoverService().tags.isEmpty) {
      NeteaseDiscoverService().fetchTags();
    }
    NeteaseDiscoverService().addListener(_onChanged);
  }

  @override
  void dispose() {
    NeteaseDiscoverService().removeListener(_onChanged);
    super.dispose();
  }

  void _onChanged() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final service = NeteaseDiscoverService();

    if (_themeManager.isFluentFramework) {
      return _buildFluentPage(context, service);
    }

    if ((Platform.isIOS || Platform.isAndroid) && _themeManager.isCupertinoFramework) {
      return _buildCupertinoPage(context, service);
    }

    return _buildMaterialPage(context, service);
  }

  Widget _buildCupertinoPage(
    BuildContext context,
    NeteaseDiscoverService service,
  ) {
    // 未登录状态下显示登录提示
    if (!AuthService().isLoggedIn) {
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
                onLoginPressed: () => showAuthDialog(context).then((_) {
                  if (mounted && AuthService().isLoggedIn) {
                    setState(() {});
                  }
                }),
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
              await NeteaseDiscoverService().fetchDiscoverPlaylists(cat: currentCat);
            },
          ),
          ..._buildCupertinoSlivers(service),
          const SliverToBoxAdapter(
            child: SizedBox(height: 80),
          ),
        ],
      ),
    );
  }

  List<Widget> _buildCupertinoSlivers(NeteaseDiscoverService service) {
    if (service.isLoading) {
      return [
        // 使用骨架屏替代简单的加载指示器
        const MobileDiscoverPageSliverSkeleton(),
      ];
    }
    if (service.errorMessage != null) {
      return [
        SliverFillRemaining(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(24.0),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(CupertinoIcons.exclamationmark_circle,
                      size: 48, color: CupertinoColors.systemRed),
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

    final items = service.playlists;
    if (items.isEmpty) {
      return [
        const SliverFillRemaining(
          child: Center(child: Text('暂无数据')),
        ),
      ];
    }

    return [
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
              delegate: SliverChildBuilderDelegate(
                (context, index) {
                  return CupertinoDiscoverPlaylistCard(
                    summary: items[index],
                    onTap: () {
                      setState(() {
                        _selectedPlaylistId = items[index].id;
                        _selectedPlaylistName = items[index].name;
                      });
                    },
                  );
                },
                childCount: items.length,
              ),
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
            isDefaultAction: service.currentCat.isEmpty || service.currentCat == '全部歌单',
            onPressed: () {
              Navigator.pop(context);
              NeteaseDiscoverService().fetchDiscoverPlaylists(cat: '全部歌单');
            },
            child: const Text('全部歌单'),
          ),
          ...service.tags.map((t) => CupertinoActionSheetAction(
            isDefaultAction: service.currentCat == t.name,
            onPressed: () {
              Navigator.pop(context);
              NeteaseDiscoverService().fetchDiscoverPlaylists(cat: t.name);
            },
            child: Text(t.name),
          )),
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

    // 未登录状态下显示登录提示
    if (!AuthService().isLoggedIn) {
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
                onLoginPressed: () => showAuthDialog(context).then((_) {
                  if (mounted && AuthService().isLoggedIn) {
                    setState(() {});
                  }
                }),
              ),
            ),
          ],
        ),
      );
    }

    return Scaffold(
      backgroundColor: colorScheme.surface,
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            floating: true,
            snap: true,
            backgroundColor: colorScheme.surface,
            title: _buildMaterialTitle(colorScheme),
          ),
          SliverPadding(
            padding: const EdgeInsets.all(24.0),
            sliver: SliverToBoxAdapter(
              child: _buildMaterialContent(service),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMaterialTitle(ColorScheme colorScheme) {
    if (_selectedPlaylistId == null) {
      return Text(
        '发现',
        style: TextStyle(
          color: colorScheme.onSurface,
          fontSize: 24,
          fontWeight: FontWeight.bold,
        ),
      );
    }

    // 面包屑样式：发现 > 歌单名
    return Row(
      children: [
        InkWell(
          onTap: () {
            setState(() {
              _selectedPlaylistId = null;
              _selectedPlaylistName = null;
            });
          },
          child: Row(
            children: [
              const Icon(Icons.explore, size: 20),
              const SizedBox(width: 6),
              const Text('发现', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600)),
            ],
          ),
        ),
        const SizedBox(width: 8),
        Icon(Icons.chevron_right, color: colorScheme.onSurfaceVariant),
        const SizedBox(width: 8),
        Flexible(
          child: Text(
            _selectedPlaylistName ?? '',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w500),
          ),
        ),
      ],
    );
  }

  Widget _buildMaterialContent(NeteaseDiscoverService service) {
    // 二级：歌单详情（内嵌在发现页，使用面包屑）
    if (_selectedPlaylistId != null) {
      return SizedBox(
        height: MediaQuery.of(context).size.height - 160,
        child: DiscoverPlaylistDetailContent(playlistId: _selectedPlaylistId!),
      );
    }

    if (service.isLoading) {
      // 使用骨架屏替代简单的加载指示器
      return const Padding(
        padding: EdgeInsets.symmetric(horizontal: 16.0),
        child: MobileDiscoverPageSkeleton(),
      );
    }
    if (service.errorMessage != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Text(service.errorMessage!),
        ),
      );
    }

    final items = service.playlists;
    if (items.isEmpty) {
      return const SizedBox.shrink();
    }

    // 顶部分类选择 + 自适应网格
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        int crossAxisCount = 2;
        if (width >= 1200) crossAxisCount = 6;
        else if (width >= 1000) crossAxisCount = 5;
        else if (width >= 800) crossAxisCount = 4;
        else if (width >= 600) crossAxisCount = 3;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildMaterialTagSelector(service),
            const SizedBox(height: 16),
            GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: crossAxisCount,
                mainAxisSpacing: 16,
                crossAxisSpacing: 16,
                // 调整纵横比，避免卡片内容溢出
                childAspectRatio: 0.72,
              ),
              itemCount: items.length,
              itemBuilder: (context, index) => _MaterialPlaylistCard(
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
        );
      },
    );
  }

  Widget _buildMaterialTagSelector(NeteaseDiscoverService service) {
    final current = service.currentCat;
    return ChoiceChip(
      label: Text(current.isEmpty ? '全部歌单' : current),
      selected: true,
      onSelected: (_) => _showMaterialTagDialog(service),
    );
  }

  void _showMaterialTagDialog(NeteaseDiscoverService service) {
    final tags = service.tags;
    final allLabel = '全部歌单';
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('选择歌单类型'),
          content: SingleChildScrollView(
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                ChoiceChip(
                  label: const Text('全部歌单'),
                  selected: service.currentCat == allLabel,
                  onSelected: (_) {
                    Navigator.of(context).pop();
                    NeteaseDiscoverService().fetchDiscoverPlaylists(cat: allLabel);
                  },
                ),
                ...tags.map((t) => ChoiceChip(
                      label: Text(t.name),
                      selected: service.currentCat == t.name,
                      onSelected: (_) {
                        Navigator.of(context).pop();
                        NeteaseDiscoverService().fetchDiscoverPlaylists(cat: t.name);
                      },
                    )),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('关闭'),
            )
          ],
        );
      },
    );
  }

  Widget _buildFluentPage(
    BuildContext context,
    NeteaseDiscoverService service,
  ) {
    // 未登录状态下显示登录提示
    if (!AuthService().isLoggedIn) {
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
                  if (mounted && AuthService().isLoggedIn) {
                    setState(() {});
                  }
                },
              ),
            ),
          ],
        ),
      );
    }

    final bool isDetail = _selectedPlaylistId != null;

    return fluent.ScaffoldPage(
      padding: EdgeInsets.zero,
      content: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
            child: FluentDiscoverBreadcrumbs(
              items: _buildFluentBreadcrumbItems(service),
              padding: EdgeInsets.zero,
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

    if (service.isLoading) {
      return const DiscoverPageSkeleton(
        key: ValueKey('discover_loading'),
      );
    }

    if (service.errorMessage != null) {
      return Padding(
        key: const ValueKey('discover_error'),
        padding: padding,
        child: fluent.InfoBar(
          title: const Text('加载失败'),
          content: Text(service.errorMessage!),
          severity: fluent.InfoBarSeverity.error,
        ),
      );
    }

    final items = service.playlists;
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
    final hasCustomTag =
        currentTag.isNotEmpty && currentTag != '全部歌单';

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
          DiscoverBreadcrumbItem(
            label: currentTag,
            onTap: _resetSelection,
          ),
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
  final void Function(int id, String name)? onOpen;
  const _MaterialPlaylistCard({required this.summary, this.onOpen});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () async {
          if (onOpen != null) onOpen!(summary.id, summary.name);
        },
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AspectRatio(
              aspectRatio: 1,
              child: CachedNetworkImage(
                imageUrl: summary.coverImgUrl,
                fit: BoxFit.cover,
                placeholder: (context, url) => Container(
                  color: colorScheme.surfaceContainerHighest,
                ),
                errorWidget: (context, url, error) => Container(
                  color: colorScheme.surfaceContainerHighest,
                  child: Icon(Icons.image_not_supported, color: colorScheme.onSurfaceVariant),
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
                      softWrap: false,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'by ${summary.creatorNickname}',
                      maxLines: 1,
                      softWrap: false,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(color: colorScheme.onSurfaceVariant),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${summary.trackCount} 首 · 播放 ${summary.playCount}',
                      maxLines: 1,
                      softWrap: false,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(color: colorScheme.onSurfaceVariant),
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
                borderRadius:
                    const BorderRadius.vertical(top: Radius.circular(12)),
                child: CachedNetworkImage(
                  imageUrl: summary.coverImgUrl,
                  fit: BoxFit.cover,
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

