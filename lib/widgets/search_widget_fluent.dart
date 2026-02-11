part of 'search_widget.dart';

extension _SearchWidgetFluent on _SearchWidgetState {
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
            child: ValueListenableBuilder<TextEditingValue>(
              valueListenable: _searchController,
              builder: (context, value, _) {
                return fluent.TextBox(
                  controller: _searchController,
                  autofocus: true,
                  placeholder: '搜索歌曲、歌手...',
                  prefix: const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 8),
                    child: Icon(fluent.FluentIcons.search),
                  ),
                  suffix: value.text.isNotEmpty
                      ? fluent.IconButton(
                          icon: const Icon(fluent.FluentIcons.clear),
                          onPressed: () {
                            _searchController.clear();
                            _searchService.clear();
                          },
                        )
                      : null,
                  onSubmitted: (_) => _performSearch(),
                );
              },
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
