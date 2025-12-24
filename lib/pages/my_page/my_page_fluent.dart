part of 'my_page.dart';

/// Fluent UI 构建方法
extension MyPageFluentUI on _MyPageState {
  Widget _buildFluentPage(BuildContext context, bool isLoggedIn) {
    if (!isLoggedIn) {
      return fluent.ScaffoldPage(
        padding: EdgeInsets.zero,
        content: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(fluent.FluentIcons.contact, size: 80),
              const SizedBox(height: 24),
              const Text('登录后查看更多', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600)),
              const SizedBox(height: 8),
              const Text('登录即可管理歌单和查看听歌统计'),
              const SizedBox(height: 24),
              fluent.FilledButton(
                onPressed: () async {
                  final result = await showFluentLoginDialog(context);
                  if (result == true) { refresh(); }
                },
                child: const Text('立即登录'),
              ),
            ],
          ),
        ),
      );
    }

    if (_selectedPlaylist != null) {
      return _buildFluentPlaylistDetailPage(_selectedPlaylist!);
    }

    final brightness = switch (_themeManager.themeMode) {
      ThemeMode.system => MediaQuery.platformBrightnessOf(context),
      ThemeMode.dark => Brightness.dark,
      _ => Brightness.light,
    };
    final materialTheme = _themeManager.buildThemeData(brightness);

    return fluent.ScaffoldPage(
      padding: EdgeInsets.zero,
      content: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 24, vertical: 16),
            child: Text('我的', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
          ),
          Expanded(
            child: Theme(
              data: materialTheme,
              child: Material(
                color: Colors.transparent,
                child: RefreshIndicator(
                  onRefresh: () async {
                    await _playlistService.loadPlaylists();
                    await _loadStats();
                  },
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _buildMaterialUserCard(materialTheme.colorScheme),
                        const SizedBox(height: 16),
                        if (_isLoadingStats)
                          const fluent.Card(padding: EdgeInsets.all(16), child: Center(child: fluent.ProgressRing()))
                        else if (_statsData == null)
                          fluent.InfoBar(title: const Text('暂无统计数据'), severity: fluent.InfoBarSeverity.info)
                        else
                          _buildFluentStatsCard(),
                        const SizedBox(height: 24),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text('我的歌单', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, fontFamily: 'Microsoft YaHei')),
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                fluent.IconButton(icon: const Icon(fluent.FluentIcons.auto_enhance_on), onPressed: _showMusicTasteDialog),
                                fluent.IconButton(icon: const Icon(fluent.FluentIcons.cloud_download), onPressed: _showImportPlaylistDialog),
                                const SizedBox(width: 8),
                                fluent.FilledButton(onPressed: _showCreatePlaylistDialog, child: const Text('新建')),
                              ],
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        _buildFluentPlaylistsList(),
                        const SizedBox(height: 24),
                        if (_statsData != null && _statsData!.playCounts.isNotEmpty) ...[
                          const Text('播放排行榜 Top 10', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, fontFamily: 'Microsoft YaHei')),
                          const SizedBox(height: 8),
                          _buildFluentTopPlaysList(),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFluentPlaylistDetailPage(Playlist playlist) {
    final allTracks = _playlistService.currentPlaylistId == playlist.id ? _playlistService.currentTracks : <PlaylistTrack>[];
    final isLoading = _playlistService.isLoadingTracks;
    final filteredTracks = _filterTracks(allTracks);

    return fluent.ScaffoldPage(
      padding: EdgeInsets.zero,
      content: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                fluent.IconButton(icon: const Icon(fluent.FluentIcons.back), onPressed: _backToList),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(_isEditMode ? '已选择 ${_selectedTrackIds.length} 首' : playlist.name, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600), overflow: TextOverflow.ellipsis),
                      if (!_isEditMode && playlist.isDefault) const Text('默认歌单', style: TextStyle(fontSize: 12)),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                if (_isEditMode) ...[
                  fluent.Button(onPressed: allTracks.isNotEmpty ? _toggleSelectAll : null, child: Text(_selectedTrackIds.length == allTracks.length ? '取消全选' : '全选')),
                  const SizedBox(width: 8),
                  fluent.FilledButton(onPressed: _selectedTrackIds.isNotEmpty ? _batchRemoveTracks : null, child: const Text('删除选中')),
                  const SizedBox(width: 8),
                  fluent.Button(onPressed: _toggleEditMode, child: const Text('取消')),
                ] else ...[
                  if (allTracks.isNotEmpty) ...[
                    fluent.IconButton(icon: Icon(_isSearchMode ? fluent.FluentIcons.search_and_apps : fluent.FluentIcons.search), onPressed: _toggleSearchMode),
                    const SizedBox(width: 4),
                  ],
                  if (allTracks.isNotEmpty) ...[
                    fluent.IconButton(icon: const Icon(fluent.FluentIcons.switch_widget), onPressed: () => _showSourceSwitchDialog(playlist, allTracks)),
                    const SizedBox(width: 4),
                  ],
                  if (allTracks.isNotEmpty) ...[
                    fluent.IconButton(icon: const Icon(fluent.FluentIcons.edit), onPressed: _toggleEditMode),
                    const SizedBox(width: 4),
                  ],
                  fluent.IconButton(
                    icon: const Icon(fluent.FluentIcons.sync),
                    onPressed: () async {
                      if (!_hasImportConfig(playlist)) {
                        fluent.displayInfoBar(context, builder: (context, close) => fluent.InfoBar(title: const Text('同步'), content: const Text('请先在"导入管理"中绑定来源后再同步'), severity: fluent.InfoBarSeverity.warning, action: fluent.IconButton(icon: const Icon(fluent.FluentIcons.clear), onPressed: close)));
                        return;
                      }
                      fluent.displayInfoBar(context, builder: (context, close) => fluent.InfoBar(title: const Text('同步'), content: const Text('正在同步...'), severity: fluent.InfoBarSeverity.info, action: fluent.IconButton(icon: const Icon(fluent.FluentIcons.clear), onPressed: close)));
                      final result = await _playlistService.syncPlaylist(playlist.id);
                      if (!mounted) return;
                      fluent.displayInfoBar(context, builder: (context, close) => fluent.InfoBar(title: const Text('同步完成'), content: Text(_formatSyncResultMessage(result)), severity: fluent.InfoBarSeverity.success, action: fluent.IconButton(icon: const Icon(fluent.FluentIcons.clear), onPressed: close)));
                      await _playlistService.loadPlaylistTracks(playlist.id);
                    },
                  ),
                ],
              ],
            ),
          ),
          if (_isSearchMode)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: fluent.TextBox(
                controller: _searchController,
                placeholder: '搜索歌曲、歌手、专辑...',
                prefix: const Padding(padding: EdgeInsets.only(left: 8), child: Icon(fluent.FluentIcons.search, size: 16)),
                suffix: _searchQuery.isNotEmpty ? fluent.IconButton(icon: const Icon(fluent.FluentIcons.clear, size: 12), onPressed: () { _searchController.clear(); _onSearchChanged(''); }) : null,
                onChanged: _onSearchChanged,
                autofocus: true,
              ),
            ),
          if (isLoading && allTracks.isEmpty)
            const Expanded(child: Center(child: fluent.ProgressRing()))
          else if (allTracks.isEmpty)
            Expanded(child: _buildFluentDetailEmptyState())
          else if (filteredTracks.isEmpty && _searchQuery.isNotEmpty)
            Expanded(child: _buildFluentSearchEmptyState())
          else ...[
            Padding(padding: const EdgeInsets.all(16.0), child: _buildFluentDetailStatisticsCard(filteredTracks.length, totalCount: allTracks.length)),
            Expanded(
              child: ListView.separated(
                padding: const EdgeInsets.symmetric(horizontal: 16.0),
                itemBuilder: (context, index) {
                  final track = filteredTracks[index];
                  final originalIndex = allTracks.indexOf(track);
                  return _buildFluentTrackItem(track, originalIndex);
                },
                separatorBuilder: (_, __) => const SizedBox(height: 8),
                itemCount: filteredTracks.length,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildFluentSearchEmptyState() {
    return const Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(fluent.FluentIcons.search, size: 64),
          SizedBox(height: 16),
          Text('未找到匹配的歌曲'),
          SizedBox(height: 8),
          Text('尝试其他关键词', style: TextStyle(fontSize: 12)),
        ],
      ),
    );
  }

  Widget _buildFluentDetailStatisticsCard(int count, {int? totalCount}) {
    final String countText = (totalCount != null && totalCount != count) ? '筛选出 $count / 共 $totalCount 首' : '共 $count 首';
    return fluent.Card(
      padding: const EdgeInsets.all(16.0),
      child: Row(
        children: [
          const Icon(fluent.FluentIcons.music_in_collection, size: 20),
          const SizedBox(width: 12),
          const Text('歌曲', style: TextStyle(fontWeight: FontWeight.w600)),
          const SizedBox(width: 6),
          Text(countText),
          const Spacer(),
          if (count > 0) fluent.FilledButton(onPressed: _playAll, child: const Text('播放全部')),
        ],
      ),
    );
  }

  Widget _buildFluentTrackItem(PlaylistTrack item, int index) {
    final theme = fluent.FluentTheme.of(context);
    final trackKey = _getTrackKey(item);
    final isSelected = _selectedTrackIds.contains(trackKey);

    return fluent.Card(
      padding: EdgeInsets.zero,
      child: fluent.ListTile(
        leading: _isEditMode
            ? fluent.Checkbox(checked: isSelected, onChanged: (_) => _toggleTrackSelection(item))
            : Stack(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: CachedNetworkImage(
                      imageUrl: item.picUrl, width: 50, height: 50, fit: BoxFit.cover,
                      placeholder: (_, __) => Container(width: 50, height: 50, color: theme.resources.controlAltFillColorSecondary),
                      errorWidget: (_, __, ___) => Container(width: 50, height: 50, color: theme.resources.controlAltFillColorSecondary, child: Icon(fluent.FluentIcons.music_in_collection, color: theme.resources.textFillColorTertiary)),
                    ),
                  ),
                  Positioned(bottom: 0, right: 0, child: Container(padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2), decoration: BoxDecoration(color: theme.resources.controlFillColorTertiary, borderRadius: const BorderRadius.only(topLeft: Radius.circular(4))), child: Text('#${index + 1}', style: TextStyle(color: theme.resources.textFillColorSecondary, fontSize: 10, fontWeight: FontWeight.bold)))),
                ],
              ),
        title: Text(item.name, maxLines: 1, overflow: TextOverflow.ellipsis),
        subtitle: Row(
          children: [
            Expanded(child: Text('${item.artists} • ${item.album}', maxLines: 1, overflow: TextOverflow.ellipsis)),
            const SizedBox(width: 8),
            Text(_getSourceIcon(item.source), style: const TextStyle(fontSize: 12)),
          ],
        ),
        trailing: _isEditMode ? null : Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            fluent.IconButton(icon: const Icon(fluent.FluentIcons.play), onPressed: () => _playDetailTrack(index)),
            fluent.IconButton(icon: const Icon(fluent.FluentIcons.delete), onPressed: () => _confirmRemoveTrack(item)),
          ],
        ),
        onPressed: _isEditMode ? () => _toggleTrackSelection(item) : () => _playDetailTrack(index),
      ),
    );
  }

  Widget _buildFluentDetailEmptyState() {
    return const Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(fluent.FluentIcons.music_in_collection, size: 64),
          SizedBox(height: 16),
          Text('歌单为空'),
          SizedBox(height: 8),
          Text('快去添加一些喜欢的歌曲吧', style: TextStyle(fontSize: 12)),
        ],
      ),
    );
  }

  Widget _buildFluentStatsCard() {
    final stats = _statsData!;
    return fluent.Card(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('听歌统计', style: TextStyle(fontWeight: FontWeight.w600)),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(child: _buildFluentStatTile(icon: fluent.FluentIcons.time_picker, label: '累计时长', value: ListeningStatsService.formatDuration(stats.totalListeningTime))),
              const SizedBox(width: 16),
              Expanded(child: _buildFluentStatTile(icon: fluent.FluentIcons.play, label: '播放次数', value: '${stats.totalPlayCount} 次')),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildFluentStatTile({required IconData icon, required String label, required String value}) {
    final theme = fluent.FluentTheme.of(context);
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: theme.resources.controlAltFillColorSecondary, borderRadius: BorderRadius.circular(8)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18),
          const SizedBox(height: 8),
          Text(label, style: TextStyle(fontSize: 12, color: theme.resources.textFillColorSecondary)),
          const SizedBox(height: 4),
          Text(value, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }

  Widget _buildFluentPlaylistsList() {
    final playlists = _playlistService.playlists;
    final theme = fluent.FluentTheme.of(context);

    if (playlists.isEmpty) {
      return fluent.Card(
        padding: const EdgeInsets.all(32),
        child: Center(
          child: Column(
            children: [
              Icon(fluent.FluentIcons.music_in_collection, size: 48, color: theme.resources.textFillColorTertiary),
              const SizedBox(height: 16),
              Text('暂无歌单', style: TextStyle(color: theme.resources.textFillColorSecondary, fontFamily: 'Microsoft YaHei')),
            ],
          ),
        ),
      );
    }

    return Column(
      children: playlists.map((playlist) {
        final canSync = _hasImportConfig(playlist);
        return Padding(
          padding: const EdgeInsets.only(bottom: 4),
          child: fluent.Card(
            padding: EdgeInsets.zero,
            child: fluent.ListTile(
              leading: _buildFluentPlaylistCover(playlist),
              title: Text(playlist.name, style: const TextStyle(fontFamily: 'Microsoft YaHei')),
              subtitle: Text('${playlist.trackCount} 首歌曲', style: TextStyle(color: theme.resources.textFillColorSecondary, fontFamily: 'Microsoft YaHei')),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (!playlist.isDefault) ...[
                    fluent.IconButton(icon: Icon(fluent.FluentIcons.sync, color: canSync ? theme.accentColor : theme.resources.textFillColorDisabled), onPressed: canSync ? () => _syncPlaylistFromList(playlist) : null),
                    fluent.IconButton(icon: const Icon(fluent.FluentIcons.delete, color: Colors.redAccent), onPressed: () => _confirmDeletePlaylist(playlist)),
                  ],
                  const Icon(fluent.FluentIcons.chevron_right),
                ],
              ),
              onPressed: () => _openPlaylistDetail(playlist),
            ),
          ),
        );
      }).toList(),
    );
  }

  Widget _buildFluentPlaylistCover(Playlist playlist) {
    final theme = fluent.FluentTheme.of(context);
    if (playlist.coverUrl != null && playlist.coverUrl!.isNotEmpty) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(6),
        child: CachedNetworkImage(
          imageUrl: playlist.coverUrl!, width: 48, height: 48, fit: BoxFit.cover,
          placeholder: (_, __) => Container(width: 48, height: 48, decoration: BoxDecoration(color: theme.resources.controlAltFillColorSecondary, borderRadius: BorderRadius.circular(6)), child: Icon(playlist.isDefault ? fluent.FluentIcons.heart_fill : fluent.FluentIcons.music_in_collection, color: playlist.isDefault ? Colors.red : theme.accentColor, size: 20)),
          errorWidget: (_, __, ___) => Container(width: 48, height: 48, decoration: BoxDecoration(color: theme.resources.controlAltFillColorSecondary, borderRadius: BorderRadius.circular(6)), child: Icon(playlist.isDefault ? fluent.FluentIcons.heart_fill : fluent.FluentIcons.music_in_collection, color: playlist.isDefault ? Colors.red : theme.accentColor, size: 20)),
        ),
      );
    }
    return Container(width: 48, height: 48, decoration: BoxDecoration(color: theme.resources.controlAltFillColorSecondary, borderRadius: BorderRadius.circular(6)), child: Icon(playlist.isDefault ? fluent.FluentIcons.heart_fill : fluent.FluentIcons.music_in_collection, color: playlist.isDefault ? Colors.red : theme.accentColor, size: 20));
  }

  Widget _buildFluentTopPlaysList() {
    final topPlays = _statsData!.playCounts.take(10).toList();
    final theme = fluent.FluentTheme.of(context);

    return fluent.Card(
      padding: EdgeInsets.zero,
      child: Column(
        children: topPlays.asMap().entries.map((entry) {
          final index = entry.key;
          final item = entry.value;
          final rank = index + 1;
          Color? rankColor;
          if (rank == 1) rankColor = Colors.amber;
          else if (rank == 2) rankColor = Colors.grey[400];
          else if (rank == 3) rankColor = Colors.orange[300];

          return Column(
            children: [
              fluent.ListTile(
                leading: Stack(
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(6),
                      child: CachedNetworkImage(
                        imageUrl: item.picUrl, width: 48, height: 48, fit: BoxFit.cover,
                        placeholder: (_, __) => Container(width: 48, height: 48, decoration: BoxDecoration(color: theme.resources.controlAltFillColorSecondary, borderRadius: BorderRadius.circular(6)), child: Icon(fluent.FluentIcons.music_in_collection, color: theme.resources.textFillColorTertiary)),
                        errorWidget: (_, __, ___) => Container(width: 48, height: 48, decoration: BoxDecoration(color: theme.resources.controlAltFillColorSecondary, borderRadius: BorderRadius.circular(6)), child: Icon(fluent.FluentIcons.music_in_collection, color: theme.resources.textFillColorTertiary)),
                      ),
                    ),
                    Positioned(left: 0, top: 0, child: Container(padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2), decoration: BoxDecoration(color: rankColor ?? theme.accentColor, borderRadius: const BorderRadius.only(topLeft: Radius.circular(6), bottomRight: Radius.circular(6))), child: Text('$rank', style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.white, fontFamily: 'Microsoft YaHei')))),
                  ],
                ),
                title: Text(item.trackName, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontFamily: 'Microsoft YaHei')),
                subtitle: Text(item.artists, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: theme.resources.textFillColorSecondary, fontFamily: 'Microsoft YaHei')),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(fluent.FluentIcons.play, size: 14, color: theme.resources.textFillColorSecondary),
                    const SizedBox(width: 4),
                    Text('${item.playCount}', style: TextStyle(color: theme.resources.textFillColorSecondary, fontFamily: 'Microsoft YaHei')),
                  ],
                ),
                onPressed: () => _playTrack(item),
              ),
              if (index < topPlays.length - 1) Divider(height: 1, color: theme.resources.dividerStrokeColorDefault),
            ],
          );
        }).toList(),
      ),
    );
  }
}
