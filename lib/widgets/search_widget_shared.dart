part of 'search_widget.dart';

extension _SearchWidgetShared on _SearchWidgetState {
  // ─── Secondary overlay ─────────────────────────────────────────────

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

  // ─── Platform tabs / content builders ──────────────────────────────

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

  // ─── Card / ListTile helpers ───────────────────────────────────────

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

  // ─── Single-platform list ──────────────────────────────────────────

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

  // ─── Single track item ─────────────────────────────────────────────

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
                    memCacheWidth: 128,
                    memCacheHeight: 128,
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

  // ─── Play helpers ──────────────────────────────────────────────────

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

  // ─── Song results (merged mode) ───────────────────────────────────

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

  // ─── Artist results ────────────────────────────────────────────────

  Widget _buildArtistResults() {
    final keyword = _searchService.currentKeyword;
    if (keyword.isEmpty) {
      return _buildEmptyState(
        icon: Icons.person_search,
        title: '搜索歌手',
        subtitle: '输入关键词后切换到"歌手"',
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
                      memCacheWidth: 128,
                      memCacheHeight: 128,
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

  // ─── Search header ─────────────────────────────────────────────────

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

  // ─── Merged track item ─────────────────────────────────────────────

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
                    memCacheWidth: 128,
                    memCacheHeight: 128,
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

  // ─── Play merged track ─────────────────────────────────────────────

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

  // ─── Platform selector (long press) ────────────────────────────────

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

  // ─── Search history ────────────────────────────────────────────────

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

  // ─── Confirm clear history ─────────────────────────────────────────

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

  // ─── Empty state ───────────────────────────────────────────────────

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

}
