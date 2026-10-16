part of 'search_widget.dart';

extension _SearchWidgetCupertino on _SearchWidgetState {
  /// iOS 风格搜索界面
  Widget _buildCupertinoSearch(
    BuildContext context,
    SearchResult searchResult,
  ) {
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
                ? CupertinoColors.systemGrey.darkColor.withValues(alpha: 0.3)
                : CupertinoColors.systemGrey.withValues(alpha: 0.2),
            width: 0.5,
          ),
        ),
      ),
      child: Row(
        children: [
          // 返回按钮
          CupertinoButton(
            padding: const EdgeInsets.all(8),
            minimumSize: Size.zero,
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
              onChanged: _onSearchInputChanged,
              onSubmitted: (_) => _performSearch(),
              onSuffixTap: _clearSearchInputAndResult,
            ),
          ),
          const SizedBox(width: 8),
          // 搜索按钮
          CupertinoButton(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            minimumSize: Size.zero,
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
    final tabs = _searchTabs;
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
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 6,
                    ),
                    child: tabs[i].platform != null
                        // 平台tab：显示彩色小球
                        ? Container(
                            width: 14,
                            height: 14,
                            decoration: BoxDecoration(
                              color: _getPlatformDotColor(
                                tabs[i].platform!.name,
                                brightness,
                              ),
                              shape: BoxShape.circle,
                            ),
                          )
                        // 功能tab：显示文字
                        : Text(
                            tabs[i].label,
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
    final tabs = _searchTabs;

    // 如果 _currentTabIndex 在平台范围内，显示对应平台的结果
    if (tabs[_currentTabIndex].platform != null) {
      final platform = tabs[_currentTabIndex].platform!;
      return Container(
        key: ValueKey('cupertino_${platform.name}_tab'),
        child: _buildPlatformResults(platform, cupertino: true, isDark: isDark),
      );
    }

    // 最后一个 tab 是歌手
    return Container(
      key: const ValueKey('cupertino_artists_tab'),
      child: _buildCupertinoArtistResults(isDark),
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
            '已加载 $count 首歌曲',
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
                httpHeaders: getImageHeaders(track.picUrl),
                width: 48,
                height: 48,
                fit: BoxFit.cover,
                memCacheWidth: 128,
                memCacheHeight: 128,
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
                      color: isDark
                          ? CupertinoColors.white
                          : CupertinoColors.black,
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

    if (_artistLoading &&
        _secondaryArtistId == null &&
        _secondaryAlbumId == null) {
      return const Center(child: CupertinoActivityIndicator(radius: 14));
    }

    if (_artistError != null &&
        _secondaryArtistId == null &&
        _secondaryAlbumId == null) {
      return Center(
        child: Text(
          '搜索失败: $_artistError',
          style: TextStyle(color: CupertinoColors.systemGrey),
        ),
      );
    }

    if (_artistResults.isEmpty &&
        _secondaryArtistId == null &&
        _secondaryAlbumId == null) {
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
                      color: CupertinoColors.systemGrey.withValues(alpha: 0.3),
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
        _refreshState(() {
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
                      httpHeaders: getImageHeaders(artist.picUrl),
                      width: 48,
                      height: 48,
                      fit: BoxFit.cover,
                      memCacheWidth: 128,
                      memCacheHeight: 128,
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

  /// iOS 风格搜索历史
  Widget _buildCupertinoSearchHistory(bool isDark) {
    final history = _searchService.searchHistory;

    if (history.isEmpty) {
      return _buildCupertinoEmptyState(
        icon: CupertinoIcons.search,
        title: '搜索音乐',
        subtitle:
            '支持${SearchTab.tabs().where((tab) => tab.platform != null).map((tab) => tab.label).join('、')}',
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
                    color: isDark
                        ? CupertinoColors.white
                        : CupertinoColors.black,
                  ),
                ),
              ],
            ),
            CupertinoButton(
              padding: EdgeInsets.zero,
              minimumSize: Size.zero,
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
                      color: CupertinoColors.systemGrey.withValues(alpha: 0.3),
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
              color: CupertinoColors.systemGrey.withValues(alpha: 0.7),
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
              minimumSize: Size.zero,
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
    final titleColor = isDark
        ? CupertinoColors.white.withValues(alpha: 0.8)
        : CupertinoColors.black.withValues(alpha: 0.8);
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
                      size: compact ? 52 : 64,
                      color: CupertinoColors.systemGrey.withValues(alpha: 0.4),
                    ),
                    SizedBox(height: compact ? 10 : 16),
                    Text(
                      title,
                      textAlign: TextAlign.center,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                        color: titleColor,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      subtitle,
                      textAlign: TextAlign.center,
                      maxLines: compact ? 1 : 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 14,
                        color: CupertinoColors.systemGrey,
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
