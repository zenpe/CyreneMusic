part of 'search_widget.dart';

extension _SearchWidgetShared on _SearchWidgetState {
  Future<void> _retryArtistSearch() async {
    final keyword = _lastTrackSearchKeyword;
    final session = _searchService.sessionId;
    if (keyword.isEmpty || _artistLoading) return;
    if (!await _checkLoginStatus() || !mounted) return;
    if (session != _searchService.sessionId ||
        keyword != _lastTrackSearchKeyword) {
      return;
    }
    await _searchArtists(keyword);
  }

  Widget _buildArtistSearchFailure() {
    final button = _isFluent
        ? fluent.Button(onPressed: _retryArtistSearch, child: const Text('重试'))
        : _isCupertino
        ? CupertinoButton(onPressed: _retryArtistSearch, child: const Text('重试'))
        : TextButton(onPressed: _retryArtistSearch, child: const Text('重试'));
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(_artistError!, textAlign: TextAlign.center),
            const SizedBox(height: 8),
            button,
          ],
        ),
      ),
    );
  }

  Future<void> _retrySearch() async {
    final platform = _selectedTab.platform;
    final session = _searchService.sessionId;
    if (platform == null) return;
    if (!await _checkLoginStatus() || !mounted) return;
    if (session != _searchService.sessionId) return;
    await _searchService.retryPlatform(platform);
  }

  Widget _buildSearchFailure() {
    final button = _isFluent
        ? fluent.Button(onPressed: _retrySearch, child: const Text('重试'))
        : _isCupertino
        ? CupertinoButton(onPressed: _retrySearch, child: const Text('重试'))
        : TextButton(onPressed: _retrySearch, child: const Text('重试'));
    final content = Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text('搜索失败，请稍后重试', textAlign: TextAlign.center),
          button,
        ],
      ),
    );
    return Center(child: content);
  }

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
                    minimumSize: Size.zero,
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
                        color: isDark
                            ? CupertinoColors.white
                            : CupertinoColors.black,
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
        ? fluent.FluentTheme.of(context).resources.dividerStrokeColorDefault
        : _isCupertino
        ? CupertinoColors.systemGrey.withValues(alpha: 0.3)
        : Theme.of(context).dividerColor;

    final content = Column(
      children: [
        header,
        if (_isFluent || _isCupertino) Divider(height: 1, color: dividerColor),

        Expanded(
          child: _secondaryAlbumId != null
              ? AlbumDetailPage(albumId: _secondaryAlbumId!, embedded: true)
              : ArtistDetailContent(
                  artistId: _secondaryArtistId!,
                  onOpenAlbum: (albumId) {
                    _refreshState(() {
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
    _refreshState(() {
      if (_secondaryAlbumId != null) {
        _secondaryAlbumId = null;
      } else {
        _secondaryArtistId = null;
        _secondaryArtistName = null;
      }
    });
  }

  // ─── Platform tabs / content builders ──────────────────────────────

  Widget _buildSearchTabsArea(
    BuildContext context,
    SearchResult searchResult, {
    required EdgeInsetsGeometry padding,
  }) {
    final tabs = _searchTabs;

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
          Expanded(child: _buildTabContent(_currentTabIndex, searchResult)),
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

  Widget _buildActiveTabView(BuildContext context, SearchResult searchResult) {
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

    final tabs = _searchTabs;

    // 如果 tabIndex 在平台范围内，显示对应平台的结果
    if (tabIndex >= 0 &&
        tabIndex < tabs.length &&
        tabs[tabIndex].platform != null) {
      final platform = tabs[tabIndex].platform!;
      return Container(
        key: ValueKey('${platform.name}_tab'),
        color: backgroundColor,
        child: _buildPlatformResults(platform),
      );
    }

    // 最后一个 tab 是歌手
    return Container(
      key: const ValueKey('artists_tab'),
      color: backgroundColor,
      child: _isFluent ? _buildFluentArtistResults() : _buildArtistResults(),
    );
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

  Widget _buildPlatformResults(
    MusicSource platform, {
    bool cupertino = false,
    bool isDark = false,
  }) {
    final result = _searchService.searchResult;
    final tracks = result.resultsFor(platform);
    final loading = result.loadingFor(platform);
    final state = _searchService.pageFor(platform);
    if (_searchService.currentKeyword.isEmpty) {
      return cupertino
          ? _buildCupertinoSearchHistory(isDark)
          : _buildSearchHistory();
    }
    if (!loading && result.errorFor(platform) != null) {
      return _buildSearchFailure();
    }
    // A filtered page may be empty while the raw upstream page still has more.
    if (!loading && tracks.isEmpty && !state.hasMore && !state.blocked) {
      return cupertino
          ? _buildCupertinoEmptyState(
              icon: CupertinoIcons.music_note,
              title: '没有找到相关歌曲',
              subtitle: '试试其他关键词吧',
              isDark: isDark,
            )
          : _buildEmptyState(
              icon: Icons.music_off,
              title: '没有找到相关歌曲',
              subtitle: '试试其他关键词吧',
            );
    }
    final notice = result.noticeFor(platform);
    return ListView.builder(
      key: PageStorageKey(
        'search_${_searchService.sessionId}_${platform.name}',
      ),
      primary: false,
      padding: cupertino
          ? const EdgeInsets.symmetric(horizontal: 16, vertical: 8)
          : const EdgeInsets.all(16),
      itemCount: tracks.length + 2,
      itemBuilder: (context, index) {
        if (index == 0) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              cupertino
                  ? _buildCupertinoSearchHeader(tracks.length, isDark)
                  : _buildSearchHeader(tracks.length),
              if (notice != null) _buildSearchNotice(notice),
              if (loading)
                Padding(
                  padding: EdgeInsets.all(16),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      SizedBox(
                        width: 16,
                        height: 16,
                        child: cupertino
                            ? const CupertinoActivityIndicator()
                            : _isFluent
                            ? const fluent.ProgressRing(strokeWidth: 2)
                            : const CircularProgressIndicator(strokeWidth: 2),
                      ),
                      const SizedBox(width: 12),
                      const Text('搜索中...'),
                    ],
                  ),
                ),
              SizedBox(height: cupertino ? 12 : 16),
            ],
          );
        }
        if (index == tracks.length + 1) {
          return loading ? const SizedBox.shrink() : _buildPageFooter(platform);
        }
        final track = tracks[index - 1];
        if (!cupertino) return _buildSingleTrackItem(track);
        final first = index == 1;
        final last = index == tracks.length;
        return Container(
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF1C1C1E) : CupertinoColors.white,
            borderRadius: BorderRadius.vertical(
              top: first ? const Radius.circular(10) : Radius.zero,
              bottom: last ? const Radius.circular(10) : Radius.zero,
            ),
          ),
          child: Column(
            children: [
              _buildCupertinoTrackTile(track, isDark),
              if (!last)
                Padding(
                  padding: const EdgeInsets.only(left: 72),
                  child: Container(
                    height: 0.5,
                    color: CupertinoColors.systemGrey.withValues(alpha: 0.3),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _requestMore(MusicSource platform) async {
    final session = _searchService.sessionId;
    if (!await _checkLoginStatus() ||
        !mounted ||
        session != _searchService.sessionId) {
      return;
    }
    await _searchService.loadMore(platform);
  }

  Widget _buildPageFooter(MusicSource platform) {
    final state = _searchService.pageFor(platform);
    if (state.blocked) return _buildSearchNotice(state.error!);
    if (state.page == 0 ||
        (platform == MusicSource.qq &&
            _searchService.searchResult.qqSuggestions)) {
      return const SizedBox.shrink();
    }
    if (!state.hasMore) {
      return const Padding(
        padding: EdgeInsets.all(16),
        child: Center(child: Text('已全部加载')),
      );
    }
    final label = state.loadingMore
        ? '加载中...'
        : state.error != null
        ? '加载失败，重试'
        : '加载更多';
    final callback = state.loadingMore ? null : () => _requestMore(platform);
    final Widget button = _isFluent
        ? fluent.Button(onPressed: callback, child: Text(label))
        : _isCupertino
        ? CupertinoButton(onPressed: callback, child: Text(label))
        : TextButton(onPressed: callback, child: Text(label));
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Center(child: button),
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
                      httpHeaders: getImageHeaders(track.picUrl),
                      width: 64,
                      height: 64,
                      memCacheWidth: 128,
                      memCacheHeight: 128,
                      fit: BoxFit.cover,
                      placeholder: (_, _) => Container(
                        width: 64,
                        height: 64,
                        color: resources.controlAltFillColorSecondary,
                        alignment: Alignment.center,
                        child: const fluent.ProgressRing(strokeWidth: 2),
                      ),
                      errorWidget: (_, _, _) => Container(
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
                      color: Colors.black.withValues(alpha: 0.08),
                      blurRadius: 10,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(14),
                  child: CachedNetworkImage(
                    imageUrl: track.picUrl,
                    httpHeaders: getImageHeaders(track.picUrl),
                    fit: BoxFit.cover,
                    memCacheWidth: 128,
                    memCacheHeight: 128,
                    placeholder: (context, url) => Container(
                      color: cs.surfaceContainerHighest,
                      child: const Center(
                        child: SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      ),
                    ),
                    errorWidget: (context, url, error) => Container(
                      color: cs.surfaceContainerHighest,
                      child: Icon(
                        Icons.music_note,
                        color: cs.primary.withValues(alpha: 0.5),
                      ),
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
                      color: cs.onSurfaceVariant.withValues(alpha: 0.8),
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
      provider = CachedNetworkImageProvider(
        track.picUrl,
        headers: getImageHeaders(track.picUrl),
      );
      PlayerService().setCurrentCoverImageProvider(provider);
    }
    PlayerService().playTrack(track, coverProvider: provider);
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
      return _buildArtistSearchFailure();
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
                  color: Colors.black.withValues(alpha: 0.1),
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
                      child: Icon(
                        Icons.person,
                        size: 32,
                        color: cs.primary.withValues(alpha: 0.5),
                      ),
                    )
                  : CachedNetworkImage(
                      imageUrl: artist.picUrl,
                      httpHeaders: getImageHeaders(artist.picUrl),
                      fit: BoxFit.cover,
                      memCacheWidth: 128,
                      memCacheHeight: 128,
                      placeholder: (context, url) => Container(
                        color: cs.surfaceContainerHighest,
                        child: const Center(
                          child: SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                        ),
                      ),
                    ),
            ),
          ),
        );

        return InkWell(
          onTap: () {
            _refreshState(() {
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
                Icon(
                  Icons.arrow_forward_ios,
                  size: 16,
                  color: cs.onSurfaceVariant.withValues(alpha: 0.5),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  // ─── Search header ─────────────────────────────────────────────────

  Widget _buildSearchNotice(String notice) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 8),
    child: Text(
      notice,
      style: TextStyle(
        fontSize: 13,
        color: _isFluent
            ? fluent.FluentTheme.of(context).resources.textFillColorSecondary
            : _isCupertino
            ? CupertinoColors.secondaryLabel.resolveFrom(context)
            : Theme.of(context).colorScheme.onSurfaceVariant,
      ),
    ),
  );

  /// 构建搜索头部（统计信息）
  Widget _buildSearchHeader(int totalCount) {
    if (_isFluent) {
      final textStyle = Theme.of(
        context,
      ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold);
      return _wrapCard(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            const Icon(Icons.music_note, size: 20),
            const SizedBox(width: 8),
            Text('已加载 $totalCount 首歌曲', style: textStyle),
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
            '已加载',
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
        ],
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
        subtitle:
            '支持${SearchTab.tabs().where((tab) => tab.platform != null).map((tab) => tab.label).join('、')}',
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
                        color: fluentTheme?.resources.textFillColorSecondary,
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
                    onPressed: () =>
                        _searchService.removeSearchHistory(keyword),
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
              color: colorScheme.onSurfaceVariant.withValues(alpha: 0.7),
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
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact =
            constraints.hasBoundedHeight && constraints.maxHeight < 180;
        final minHeight = constraints.hasBoundedHeight
            ? constraints.maxHeight
            : 0.0;
        return SingleChildScrollView(
          physics: const ClampingScrollPhysics(),
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: minHeight),
            child: Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 8,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      icon,
                      size: compact ? 56 : 80,
                      color: colorScheme.onSurfaceVariant.withValues(
                        alpha: 0.3,
                      ),
                    ),
                    SizedBox(height: compact ? 10 : 16),
                    Text(
                      title,
                      textAlign: TextAlign.center,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleLarge?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      subtitle,
                      textAlign: TextAlign.center,
                      maxLines: compact ? 1 : 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: colorScheme.onSurfaceVariant.withValues(
                          alpha: 0.7,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
