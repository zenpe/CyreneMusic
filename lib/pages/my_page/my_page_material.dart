part of 'my_page.dart';

/// Material UI 构建方法
extension MyPageMaterialUI on _MyPageState {
  Widget _buildMaterialPage(BuildContext context, ColorScheme colorScheme, bool isLoggedIn) {
    if (!isLoggedIn) {
      return Scaffold(
        body: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                colorScheme.primaryContainer.withOpacity(0.3),
                colorScheme.surface,
              ],
            ),
          ),
          child: Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  padding: const EdgeInsets.all(32),
                  decoration: BoxDecoration(
                    color: colorScheme.primaryContainer.withOpacity(0.5),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(Icons.person_outline, size: 80, color: colorScheme.primary),
                ),
                const SizedBox(height: 32),
                Text('发现你的音乐世界', style: Theme.of(context).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.bold)),
                const SizedBox(height: 12),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 48),
                  child: Text(
                    '登录即可解锁个性化推荐、管理云端歌单并记录你的每一次聆听。',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: colorScheme.onSurface.withOpacity(0.7), fontSize: 16),
                  ),
                ),
                const SizedBox(height: 48),
                FilledButton.icon(
                  onPressed: () => showAuthDialog(context).then((_) { refresh(); }),
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
                    textStyle: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  icon: const Icon(Icons.login),
                  label: const Text('立即开启'),
                ),
              ],
            ),
          ),
        ),
      );
    }

    if (_selectedPlaylist != null) {
      return _buildMaterialPlaylistDetail(_selectedPlaylist!, colorScheme);
    }

    final user = _authFacade.currentUser;

    return Scaffold(
      backgroundColor: colorScheme.surface,
      body: Stack(
        children: [
          // 1. 全局自适应流光沉浸渐变 (Apple Music 风格全域色彩联动)
          Positioned.fill(
            child: ValueListenableBuilder<Color?>(
              valueListenable: PlayerService().themeColorNotifier,
              builder: (context, dynamicColor, _) {
                final isDark = Theme.of(context).brightness == Brightness.dark;
                final baseColor = DynamicColorUtils.resolveAmbient(
                  dynamicColor,
                  colorScheme,
                  isDark: isDark,
                );
                return IgnorePointer(
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      // 垂直自适应主光场渐变
                      AnimatedContainer(
                        duration: const Duration(milliseconds: 450),
                        curve: Curves.easeOutCubic,
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [
                              baseColor.withValues(alpha: isDark ? 0.28 : 0.16),
                              baseColor.withValues(alpha: isDark ? 0.12 : 0.06),
                              colorScheme.surface.withValues(alpha: 0.6),
                              colorScheme.surface,
                            ],
                            stops: const [0.0, 0.35, 0.65, 1.0],
                          ),
                        ),
                      ),
                      // 顶部广角有机弥散流光
                      Positioned(
                        top: -120,
                        right: -80,
                        width: 500,
                        height: 500,
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 450),
                          curve: Curves.easeOutCubic,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            gradient: RadialGradient(
                              colors: [
                                baseColor.withValues(alpha: isDark ? 0.35 : 0.22),
                                baseColor.withValues(alpha: isDark ? 0.14 : 0.08),
                                Colors.transparent,
                              ],
                              stops: const [0.0, 0.5, 1.0],
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),

          // 2. 页面可滚动主体
          RefreshIndicator(
            onRefresh: () async {
              await _playlistService.loadPlaylists();
              await _loadStats();
            },
            child: CustomScrollView(
              physics: const BouncingScrollPhysics(),
              slivers: [
                // 顶部安全区占位
                const SliverToBoxAdapter(
                  child: SafeArea(bottom: false, child: SizedBox(height: 12)),
                ),

                // 个人主页 Hero 头部
                SliverToBoxAdapter(
                  child: _buildMaterialProfileHero(user, colorScheme),
                ),

                // 核心统计磁贴
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                    child: _buildMaterialStatsTiles(colorScheme),
                  ),
                ),

                // 歌单标题与操作栏
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 20, 20, 10),
                    child: _buildMaterialPlaylistHeader(colorScheme),
                  ),
                ),

                // 歌单列表
                SliverPadding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  sliver: _buildMaterialPlaylistsSliver(colorScheme),
                ),

                // 播放排行榜标题
                if (_statsData != null && _statsData!.playCounts.isNotEmpty) ...[
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(20, 24, 20, 10),
                      child: Row(
                        children: [
                          Text(
                            '播放排行 Top 10',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w800,
                              letterSpacing: -0.3,
                              color: colorScheme.onSurface,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                            decoration: BoxDecoration(
                              color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.6),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Text(
                              '高频循环',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                color: colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  SliverPadding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    sliver: _buildMaterialTopPlaysSliver(colorScheme),
                  ),
                ],

                // 底部防遮挡占位 (MiniPlayer + Nav)
                const SliverToBoxAdapter(child: SizedBox(height: 100)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMaterialProfileHero(User? user, ColorScheme colorScheme) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return ValueListenableBuilder<Color?>(
      valueListenable: PlayerService().themeColorNotifier,
      builder: (context, extractedColor, _) {
        final dynamicAccent = DynamicColorUtils.resolveAccent(
          extractedColor,
          colorScheme,
          isDark: isDark,
        );

        return Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // 头像外层光环与柔和弥散阴影
                Container(
                  padding: const EdgeInsets.all(3.5),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: LinearGradient(
                      colors: [
                        dynamicAccent.withValues(alpha: 0.55),
                        dynamicAccent.withValues(alpha: 0.12),
                      ],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: dynamicAccent.withValues(alpha: 0.2),
                        blurRadius: 16,
                        spreadRadius: 2,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: ClipOval(
                    child: user?.avatarUrl != null && user!.avatarUrl!.contains('linux.do')
                        ? LinuxDoAvatarMaterial(
                            url: user.avatarUrl!,
                            userId: user.id,
                            size: 72,
                          )
                        : (user?.avatarUrl != null
                            ? CachedNetworkImage(
                                imageUrl: user!.avatarUrl!,
                                width: 72,
                                height: 72,
                                fit: BoxFit.cover,
                                memCacheWidth: 200,
                                memCacheHeight: 200,
                                placeholder: (_, __) => Container(
                                  width: 72,
                                  height: 72,
                                  color: colorScheme.surfaceContainerHighest,
                                  child: Icon(Icons.person, color: colorScheme.onSurfaceVariant),
                                ),
                                errorWidget: (_, __, ___) => Container(
                                  width: 72,
                                  height: 72,
                                  color: colorScheme.surfaceContainerHighest,
                                  child: Icon(Icons.person, color: colorScheme.onSurfaceVariant),
                                ),
                              )
                            : Container(
                                width: 72,
                                height: 72,
                                color: colorScheme.primaryContainer,
                                alignment: Alignment.center,
                                child: Text(
                                  user?.username.isNotEmpty == true ? user!.username[0].toUpperCase() : '?',
                                  style: TextStyle(
                                    fontSize: 28,
                                    fontWeight: FontWeight.bold,
                                    color: colorScheme.onPrimaryContainer,
                                  ),
                                ),
                              )),
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  user?.username ?? '未登录',
                  style: TextStyle(
                    fontSize: 21,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.4,
                    color: colorScheme.onSurface,
                  ),
                ),
                if (user?.displayEmail != null) ...[
                  const SizedBox(height: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3.5),
                    decoration: BoxDecoration(
                      color: colorScheme.surfaceContainerHighest.withValues(alpha: isDark ? 0.45 : 0.7),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: colorScheme.outlineVariant.withValues(alpha: isDark ? 0.25 : 0.4),
                        width: 0.8,
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.alternate_email_rounded,
                          size: 12,
                          color: colorScheme.onSurfaceVariant.withValues(alpha: 0.8),
                        ),
                        const SizedBox(width: 4.5),
                        Text(
                          user!.displayEmail!,
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                            color: colorScheme.onSurfaceVariant,
                            letterSpacing: 0.1,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildMaterialStatsTiles(ColorScheme colorScheme) {
    if (_isLoadingStats) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 24),
        child: Center(child: CircularProgressIndicator(strokeWidth: 2.5)),
      );
    }

    if (_statsData == null) {
      return const SizedBox.shrink();
    }

    final isDark = Theme.of(context).brightness == Brightness.dark;

    return ValueListenableBuilder<Color?>(
      valueListenable: PlayerService().themeColorNotifier,
      builder: (context, extractedColor, _) {
        final dynamicAccent = DynamicColorUtils.resolveAccent(
          extractedColor,
          colorScheme,
          isDark: isDark,
        );

        return Row(
          children: [
            Expanded(
              child: _buildExpressiveStatCard(
                icon: Icons.access_time_rounded,
                label: '累计聆听',
                value: ListeningStatsService.formatDuration(_statsData!.totalListeningTime),
                tintColor: dynamicAccent,
                colorScheme: colorScheme,
                isDark: isDark,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _buildExpressiveStatCard(
                icon: Icons.headphones_rounded,
                label: '累计播放',
                value: '${_statsData!.totalPlayCount} 次',
                tintColor: colorScheme.tertiary,
                colorScheme: colorScheme,
                isDark: isDark,
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildExpressiveStatCard({
    required IconData icon,
    required String label,
    required String value,
    required Color tintColor,
    required ColorScheme colorScheme,
    required bool isDark,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest.withValues(alpha: isDark ? 0.35 : 0.65),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: colorScheme.outlineVariant.withValues(alpha: isDark ? 0.25 : 0.4),
          width: 0.8,
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: tintColor.withValues(alpha: isDark ? 0.18 : 0.12),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, size: 20, color: tintColor),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.3,
                    color: colorScheme.onSurface,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w500,
                    color: colorScheme.onSurfaceVariant.withValues(alpha: 0.8),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMaterialPlaylistHeader(ColorScheme colorScheme) {
    final playlists = _playlistService.playlists;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return ValueListenableBuilder<Color?>(
      valueListenable: PlayerService().themeColorNotifier,
      builder: (context, extractedColor, _) {
        final dynamicAccent = DynamicColorUtils.resolveAccent(
          extractedColor,
          colorScheme,
          isDark: isDark,
        );
        final textColor = ThemeData.estimateBrightnessForColor(dynamicAccent) == Brightness.dark
            ? Colors.white
            : const Color(0xFF0F172A);

        return Row(
          children: [
            Text(
              '我的歌单',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w800,
                letterSpacing: -0.3,
                color: colorScheme.onSurface,
              ),
            ),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.6),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                '${playlists.length}',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
            ),
            const Spacer(),
            // 导入歌单按钮
            _buildActionGlassButton(
              icon: Icons.cloud_download_outlined,
              label: '导入',
              tooltip: '导入外部歌单',
              onTap: _showImportPlaylistDialog,
              colorScheme: colorScheme,
              isDark: isDark,
            ),
            const SizedBox(width: 8),
            // 新建歌单胶囊 (主操作高亮)
            InkWell(
              onTap: _showCreatePlaylistDialog,
              borderRadius: BorderRadius.circular(18),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 350),
                curve: Curves.easeOutCubic,
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6.5),
                decoration: BoxDecoration(
                  color: dynamicAccent,
                  borderRadius: BorderRadius.circular(18),
                  boxShadow: [
                    BoxShadow(
                      color: dynamicAccent.withValues(alpha: 0.35),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.add_rounded, size: 16, color: textColor),
                    const SizedBox(width: 3),
                    Text(
                      '新建',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: textColor,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildActionGlassButton({
    required IconData icon,
    required String label,
    required String tooltip,
    required VoidCallback onTap,
    required ColorScheme colorScheme,
    required bool isDark,
  }) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: colorScheme.surfaceContainerHighest.withValues(alpha: isDark ? 0.45 : 0.7),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: colorScheme.outlineVariant.withValues(alpha: isDark ? 0.25 : 0.4),
              width: 0.8,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 14, color: colorScheme.onSurfaceVariant),
              const SizedBox(width: 4),
              Text(
                label,
                style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w600,
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMaterialPlaylistsSliver(ColorScheme colorScheme) {
    final playlists = _playlistService.playlists;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    if (playlists.isEmpty) {
      return SliverToBoxAdapter(
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 40),
          decoration: BoxDecoration(
            color: colorScheme.surfaceContainerHighest.withValues(alpha: isDark ? 0.3 : 0.5),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: colorScheme.outlineVariant.withValues(alpha: isDark ? 0.2 : 0.35),
              width: 0.8,
            ),
          ),
          child: Column(
            children: [
              Icon(Icons.library_music_outlined, size: 44, color: colorScheme.outline.withValues(alpha: 0.5)),
              const SizedBox(height: 12),
              Text('快去开启你的第一个歌单吧', style: TextStyle(color: colorScheme.onSurfaceVariant, fontSize: 13, fontWeight: FontWeight.w500)),
            ],
          ),
        ),
      );
    }

    return SliverList(
      delegate: SliverChildBuilderDelegate(
        (context, index) {
          final playlist = playlists[index];
          final canSync = _hasImportConfig(playlist);

          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
            child: Material(
              color: Colors.transparent,
              borderRadius: BorderRadius.circular(12),
              child: InkWell(
                borderRadius: BorderRadius.circular(12),
                onTap: () => _openPlaylistDetail(playlist),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                  child: Row(
                    children: [
                      // 精致封面 (48x48, 10px圆角)
                      _buildMaterialPlaylistCover(playlist, colorScheme, size: 48, radius: 10),
                      const SizedBox(width: 14),
                      // 歌单名与副信息
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              playlist.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w700,
                                letterSpacing: -0.2,
                                color: colorScheme.onSurface,
                              ),
                            ),
                            const SizedBox(height: 3),
                            Row(
                              children: [
                                Text(
                                  '${playlist.trackCount} 首歌曲',
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w500,
                                    color: colorScheme.onSurfaceVariant.withValues(alpha: 0.75),
                                  ),
                                ),
                                if (canSync) ...[
                                  Text(
                                    '  •  ',
                                    style: TextStyle(
                                      fontSize: 10,
                                      color: colorScheme.outlineVariant,
                                    ),
                                  ),
                                  Icon(Icons.sync_rounded, size: 12, color: colorScheme.primary),
                                  const SizedBox(width: 2.5),
                                  Text(
                                    '已关联同步',
                                    style: TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w600,
                                      color: colorScheme.primary,
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ],
                        ),
                      ),
                      // 更多操作按钮
                      IconButton(
                        icon: Icon(
                          Icons.more_horiz_rounded,
                          size: 20,
                          color: colorScheme.onSurfaceVariant.withValues(alpha: 0.8),
                        ),
                        onPressed: () => _showPlaylistMoreOptions(playlist, colorScheme),
                        tooltip: '更多选项',
                        visualDensity: VisualDensity.compact,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        },
        childCount: playlists.length,
      ),
    );
  }

  /// 显示歌单更多操作底板
  void _showPlaylistMoreOptions(Playlist playlist, ColorScheme colorScheme) {
    final canSync = _hasImportConfig(playlist);
    
    showModalBottomSheet(
      context: context,
      useRootNavigator: true,
      backgroundColor: colorScheme.surface,
      elevation: 0,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 8),
            Container(
              width: 32,
              height: 4,
              decoration: BoxDecoration(
                color: colorScheme.outlineVariant,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 16),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
              child: Row(
                children: [
                  _buildMaterialPlaylistCover(playlist, colorScheme),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(playlist.name, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
                        Text('${playlist.trackCount} 首歌曲', style: Theme.of(context).textTheme.bodySmall?.copyWith(color: colorScheme.onSurfaceVariant)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const Divider(indent: 24, endIndent: 24),
            ListTile(
              leading: const Icon(Icons.play_circle_outline),
              title: const Text('播放全部'),
              onTap: () {
                Navigator.pop(context);
                _openPlaylistDetail(playlist);
                // 等待加载完成后播放的逻辑通常在详情页，这里仅打开详情
              },
            ),
            ListTile(
              leading: Icon(Icons.sync, color: canSync ? colorScheme.primary : colorScheme.onSurfaceVariant.withOpacity(0.3)),
              title: const Text('同步歌单'),
              subtitle: canSync ? null : const Text('请先设置导入来源', style: TextStyle(fontSize: 10)),
              onTap: canSync ? () {
                Navigator.pop(context);
                _syncPlaylistFromList(playlist);
              } : null,
            ),
            if (!playlist.isDefault)
              ListTile(
                leading: const Icon(Icons.delete_outline, color: Colors.redAccent),
                title: const Text('删除歌单', style: TextStyle(color: Colors.redAccent)),
                onTap: () {
                  Navigator.pop(context);
                  _confirmDeletePlaylist(playlist);
                },
              ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  Widget _buildMaterialTopPlaysSliver(ColorScheme colorScheme) {
    final topPlays = _statsData!.playCounts.take(10).toList();
    final player = PlayerService();
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return SliverList(
      delegate: SliverChildBuilderDelegate(
        (context, index) {
          final item = topPlays[index];
          final rank = index + 1;

          Color rankColor;
          if (rank == 1) {
            rankColor = const Color(0xFFFFB300); // 冠军金
          } else if (rank == 2) {
            rankColor = const Color(0xFF94A3B8); // 亚军银
          } else if (rank == 3) {
            rankColor = const Color(0xFFD97706); // 季军铜
          } else {
            rankColor = colorScheme.onSurfaceVariant.withValues(alpha: 0.45);
          }

          return ValueListenableBuilder<Color?>(
            valueListenable: player.themeColorNotifier,
            builder: (context, extractedColor, _) {
              final dynamicAccent = DynamicColorUtils.resolveAccent(
                extractedColor,
                colorScheme,
                isDark: isDark,
              );

              return AnimatedBuilder(
                animation: Listenable.merge([player, player.positionNotifier]),
                builder: (context, _) {
                  final currentTrack = player.currentTrack;
                  final currentSong = player.currentSong;
                  final displayTitle = player.displayTitle;

                  final isCurrentPlaying = (displayTitle.isNotEmpty &&
                          (displayTitle == item.trackName ||
                              item.trackName.contains(displayTitle) ||
                              displayTitle.contains(item.trackName))) ||
                      (currentTrack != null && currentTrack.name == item.trackName) ||
                      (currentSong != null && currentSong.name == item.trackName);

                  final Color itemBg = isCurrentPlaying
                      ? dynamicAccent.withValues(alpha: isDark ? 0.18 : 0.08)
                      : colorScheme.surfaceContainerHighest.withValues(alpha: isDark ? 0.25 : 0.45);

                  return Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                    child: Material(
                      color: isCurrentPlaying
                          ? dynamicAccent.withValues(alpha: isDark ? 0.18 : 0.08)
                          : Colors.transparent,
                      borderRadius: BorderRadius.circular(12),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(12),
                        onTap: () => _playTrack(item),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
                          child: Row(
                            children: [
                              // 排名编号 (播放中显示均衡器，与详情页一致)
                              SizedBox(
                                width: 28,
                                child: isCurrentPlaying
                                    ? Icon(Icons.equalizer_rounded, color: dynamicAccent, size: 20)
                                    : Text(
                                        rank.toString().padLeft(2, '0'),
                                        textAlign: TextAlign.center,
                                        style: TextStyle(
                                          fontSize: 13,
                                          fontWeight: rank <= 3 ? FontWeight.w900 : FontWeight.w600,
                                          color: rankColor,
                                          letterSpacing: -0.5,
                                        ),
                                      ),
                              ),
                              const SizedBox(width: 8),
                              // 歌曲封面 (44x44, 8px 圆角)
                              ClipRRect(
                                borderRadius: BorderRadius.circular(8),
                                child: CachedNetworkImage(
                                  imageUrl: item.picUrl,
                                  width: 44,
                                  height: 44,
                                  fit: BoxFit.cover,
                                  memCacheWidth: 128,
                                  memCacheHeight: 128,
                                  placeholder: (_, __) => Container(
                                    width: 44,
                                    height: 44,
                                    color: colorScheme.surfaceContainerHighest,
                                  ),
                                  errorWidget: (_, __, ___) => Container(
                                    width: 44,
                                    height: 44,
                                    color: colorScheme.surfaceContainerHighest,
                                    child: Icon(Icons.music_note, color: colorScheme.onSurfaceVariant, size: 20),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 12),
                              // 歌名与歌手
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(
                                      item.trackName,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        fontSize: 14.5,
                                        fontWeight: isCurrentPlaying ? FontWeight.w800 : FontWeight.w600,
                                        letterSpacing: -0.2,
                                        color: isCurrentPlaying ? dynamicAccent : colorScheme.onSurface,
                                      ),
                                    ),
                                    const SizedBox(height: 3),
                                    Text(
                                      item.artists,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.normal,
                                        color: isCurrentPlaying
                                            ? dynamicAccent.withValues(alpha: 0.85)
                                            : colorScheme.onSurfaceVariant.withValues(alpha: 0.75),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              // 播放次数与来源
                              Column(
                                mainAxisSize: MainAxisSize.min,
                                crossAxisAlignment: CrossAxisAlignment.end,
                                children: [
                                  Text(
                                    '${item.playCount}次',
                                    style: TextStyle(
                                      fontSize: 11.5,
                                      fontWeight: isCurrentPlaying ? FontWeight.w700 : FontWeight.w600,
                                      color: isCurrentPlaying
                                          ? dynamicAccent
                                          : colorScheme.onSurfaceVariant.withValues(alpha: 0.7),
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    item.toTrack().getSourceName(),
                                    style: TextStyle(
                                      fontSize: 9.5,
                                      color: colorScheme.onSurfaceVariant.withValues(alpha: 0.5),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(width: 4),
                              // 更多操作
                              TrackMoreButton(
                                track: item.toTrack(),
                                onPlay: () => _playTrack(item),
                                size: 30,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  );
                },
              );
            },
          );
        },
        childCount: topPlays.length,
      ),
    );
  }

  Widget _buildMaterialPlaylistDetail(Playlist playlist, ColorScheme colorScheme) {
    final allTracks = _playlistService.currentPlaylistId == playlist.id ? _playlistService.currentTracks : <PlaylistTrack>[];
    final isLoading = _playlistService.isLoadingTracks;
    final filteredTracks = _filterTracks(allTracks);

    return Scaffold(
      backgroundColor: colorScheme.surface,
      body: Stack(
        children: [
          // 全屏自适应流光沉浸渐变 (Apple Music 风格全域色彩联动)
          Positioned.fill(
            child: ValueListenableBuilder<Color?>(
              valueListenable: PlayerService().themeColorNotifier,
              builder: (context, dynamicColor, _) {
                final isDark = Theme.of(context).brightness == Brightness.dark;
                final baseColor = DynamicColorUtils.resolveAmbient(
                  dynamicColor,
                  colorScheme,
                  isDark: isDark,
                );
                return IgnorePointer(
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      // 垂直自适应主光场渐变：从顶部柔光向底部表面色自然晕染
                      AnimatedContainer(
                        duration: const Duration(milliseconds: 450),
                        curve: Curves.easeOutCubic,
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [
                              baseColor.withValues(alpha: isDark ? 0.28 : 0.16),
                              baseColor.withValues(alpha: isDark ? 0.12 : 0.06),
                              colorScheme.surface.withValues(alpha: 0.6),
                              colorScheme.surface,
                            ],
                            stops: const [0.0, 0.32, 0.65, 1.0],
                          ),
                        ),
                      ),
                      // 顶部广角有机弥散流光：打造通透空间深度
                      Positioned(
                        top: -120,
                        right: -80,
                        width: 520,
                        height: 520,
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 450),
                          curve: Curves.easeOutCubic,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            gradient: RadialGradient(
                              colors: [
                                baseColor.withValues(alpha: isDark ? 0.35 : 0.22),
                                baseColor.withValues(alpha: isDark ? 0.14 : 0.08),
                                Colors.transparent,
                              ],
                              stops: const [0.0, 0.5, 1.0],
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
          CustomScrollView(
            physics: const BouncingScrollPhysics(),
            slivers: [
              _buildMaterialDetailAppBar(playlist, colorScheme, allTracks),
              if (_isSearchMode)
                SliverToBoxAdapter(child: Padding(padding: const EdgeInsets.fromLTRB(20, 8, 20, 8), child: _buildMaterialSearchField(colorScheme)))
              else if (!_isEditMode)
                SliverToBoxAdapter(child: _buildMaterialPlaylistHeroHeader(playlist, colorScheme, allTracks)),
              if (isLoading && allTracks.isEmpty)
                const SliverFillRemaining(child: Center(child: CircularProgressIndicator()))
              else if (allTracks.isEmpty)
                SliverFillRemaining(child: _buildMaterialDetailEmptyState(colorScheme))
              else if (filteredTracks.isEmpty && _searchQuery.isNotEmpty)
                SliverFillRemaining(child: _buildMaterialSearchEmptyState(colorScheme))
              else ...[
                if (_searchQuery.isNotEmpty)
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
                      child: Text(
                        '筛选出 ${filteredTracks.length} / 共 ${allTracks.length} 首歌曲',
                        style: TextStyle(fontSize: 13, color: colorScheme.onSurfaceVariant, fontWeight: FontWeight.w500),
                      ),
                    ),
                  ),
                SliverPadding(
                  padding: const EdgeInsets.symmetric(horizontal: 4.0),
                  sliver: SliverList(delegate: SliverChildBuilderDelegate((context, index) {
                    final track = filteredTracks[index];
                    final originalIndex = allTracks.indexOf(track);
                    return _buildMaterialTrackItem(track, originalIndex, colorScheme);
                  }, childCount: filteredTracks.length)),
                ),
                const SliverToBoxAdapter(child: SizedBox(height: 16)),
              ],
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildMaterialSearchField(ColorScheme colorScheme) {
    return TextField(
      controller: _searchController,
      decoration: InputDecoration(
        hintText: '搜索歌曲、歌手、专辑...',
        prefixIcon: const Icon(Icons.search),
        suffixIcon: _searchQuery.isNotEmpty ? IconButton(icon: const Icon(Icons.clear), onPressed: () { _searchController.clear(); _onSearchChanged(''); }) : null,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(24), borderSide: BorderSide.none),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(24), borderSide: BorderSide.none),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(24), borderSide: BorderSide(color: colorScheme.primary, width: 2)),
        filled: true,
        fillColor: colorScheme.surfaceContainerHigh,
        contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      ),
      onChanged: _onSearchChanged,
      autofocus: true,
    );
  }

  Widget _buildMaterialSearchEmptyState(ColorScheme colorScheme) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.hasBoundedHeight && constraints.maxHeight < 180;
        final minHeight = constraints.hasBoundedHeight ? constraints.maxHeight : 0.0;
        return SingleChildScrollView(
          physics: const ClampingScrollPhysics(),
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: minHeight),
            child: Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.search_off,
                      size: compact ? 52 : 64,
                      color: colorScheme.onSurface.withOpacity(0.3),
                    ),
                    SizedBox(height: compact ? 10 : 16),
                    Text(
                      '未找到匹配的歌曲',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 16,
                        color: colorScheme.onSurface.withOpacity(0.6),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '尝试其他关键词',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 14,
                        color: colorScheme.onSurface.withOpacity(0.5),
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

  Widget _buildMaterialDetailAppBar(Playlist playlist, ColorScheme colorScheme, List<PlaylistTrack> tracks) {
    return SliverAppBar(
      pinned: true,
      floating: false,
      backgroundColor: Colors.transparent,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      leading: IconButton(
        icon: const Icon(Icons.arrow_back_rounded, size: 24),
        onPressed: _backToList,
      ),
      titleSpacing: 0,
      title: _isEditMode
          ? Text(
              '已选择 ${_selectedTrackIds.length} 首',
              style: TextStyle(
                color: colorScheme.onSurface,
                fontSize: 18,
                fontWeight: FontWeight.w900,
                letterSpacing: -0.3,
              ),
            )
          : null,
      actions: [
        if (_isEditMode) ...[
          IconButton(
            icon: Icon(_selectedTrackIds.length == tracks.length ? Icons.check_box : Icons.check_box_outline_blank, size: 22),
            onPressed: tracks.isNotEmpty ? _toggleSelectAll : null,
            tooltip: _selectedTrackIds.length == tracks.length ? '取消全选' : '全选',
          ),
          IconButton(
            icon: const Icon(Icons.delete, color: Colors.redAccent, size: 22),
            onPressed: _selectedTrackIds.isNotEmpty ? _batchRemoveTracks : null,
            tooltip: '删除选中',
          ),
          TextButton(onPressed: _toggleEditMode, child: const Text('取消')),
        ] else ...[
          if (tracks.isNotEmpty)
            IconButton(
              icon: Icon(_isSearchMode ? Icons.search_off : Icons.search_rounded, size: 22, color: colorScheme.onSurfaceVariant),
              onPressed: _toggleSearchMode,
              tooltip: _isSearchMode ? '关闭搜索' : '搜索歌曲',
            ),
          IconButton(
            icon: Icon(Icons.sync_rounded, size: 22, color: colorScheme.onSurfaceVariant),
            onPressed: () async {
              if (!_hasImportConfig(playlist)) {
                _showUserNotification('请先在"导入管理"中绑定来源后再同步', severity: fluent.InfoBarSeverity.warning);
                return;
              }
              _showUserNotification('正在同步...', duration: const Duration(seconds: 1));
              final result = await _playlistService.syncPlaylist(playlist.id);
              _showUserNotification(_formatSyncResultMessage(result), severity: result.insertedCount > 0 ? fluent.InfoBarSeverity.success : fluent.InfoBarSeverity.info);
              await _playlistService.loadPlaylistTracks(playlist.id);
            },
            tooltip: '同步',
          ),
        ],
        const SizedBox(width: 8),
      ],
    );
  }

  Widget _buildMaterialPlaylistHeroHeader(Playlist playlist, ColorScheme colorScheme, List<PlaylistTrack> tracks) {
    final String coverUrl = (playlist.coverUrl != null && playlist.coverUrl!.isNotEmpty)
        ? playlist.coverUrl!
        : (tracks.isNotEmpty ? tracks.first.picUrl : '');
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 18),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // 88x88 歌单封面 (大圆角 + 柔和弥散阴影)
          Container(
            width: 88,
            height: 88,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.14),
                  blurRadius: 18,
                  offset: const Offset(0, 7),
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: coverUrl.isNotEmpty
                  ? CachedNetworkImage(
                      imageUrl: coverUrl,
                      width: 88,
                      height: 88,
                      fit: BoxFit.cover,
                      memCacheWidth: 200,
                      memCacheHeight: 200,
                      placeholder: (_, __) => Container(
                        color: colorScheme.primaryContainer,
                        child: Icon(Icons.music_note_rounded, color: colorScheme.primary, size: 38),
                      ),
                      errorWidget: (_, __, ___) => Container(
                        color: colorScheme.primaryContainer,
                        child: Icon(
                          playlist.isDefault ? Icons.favorite_rounded : Icons.music_note_rounded,
                          color: colorScheme.primary,
                          size: 38,
                        ),
                      ),
                    )
                  : Container(
                      color: colorScheme.primaryContainer,
                      child: Icon(
                        playlist.isDefault ? Icons.favorite_rounded : Icons.music_note_rounded,
                        color: colorScheme.primary,
                        size: 38,
                      ),
                    ),
            ),
          ),
          const SizedBox(width: 16),
          // 标题、副标题与横向操作按钮组 (紧凑优雅排布)
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  playlist.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: colorScheme.onSurface,
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.4,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '${playlist.isDefault ? "默认歌单 · " : ""}${tracks.length} 首歌曲',
                  style: TextStyle(
                    color: colorScheme.onSurfaceVariant.withValues(alpha: 0.8),
                    fontSize: 12.5,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 12),
                // 胶囊操作按钮行
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      if (tracks.isNotEmpty)
                        ValueListenableBuilder<Color?>(
                          valueListenable: PlayerService().themeColorNotifier,
                          builder: (context, extractedColor, _) {
                            final accent = DynamicColorUtils.resolveAccent(
                              extractedColor,
                              colorScheme,
                              isDark: isDark,
                            );
                            final textColor = ThemeData.estimateBrightnessForColor(accent) == Brightness.dark
                                ? Colors.white
                                : const Color(0xFF0F172A);
                            return InkWell(
                              onTap: _playAll,
                              borderRadius: BorderRadius.circular(20),
                              child: AnimatedContainer(
                                duration: const Duration(milliseconds: 350),
                                curve: Curves.easeOutCubic,
                                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7.5),
                                decoration: BoxDecoration(
                                  color: accent,
                                  borderRadius: BorderRadius.circular(20),
                                  boxShadow: [
                                    BoxShadow(
                                      color: accent.withValues(alpha: 0.38),
                                      blurRadius: 10,
                                      offset: const Offset(0, 3),
                                    ),
                                  ],
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(Icons.play_arrow_rounded, size: 17, color: textColor),
                                    const SizedBox(width: 4),
                                    Text(
                                      '播放全部',
                                      style: TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.bold,
                                        color: textColor,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
                      if (tracks.isNotEmpty) ...[
                        const SizedBox(width: 8),
                        InkWell(
                          onTap: () => _showSourceSwitchDialog(playlist, tracks),
                          borderRadius: BorderRadius.circular(20),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7.5),
                            decoration: BoxDecoration(
                              color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.75),
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(
                                color: colorScheme.outlineVariant.withValues(alpha: 0.4),
                                width: 0.8,
                              ),
                            ),
                            child: Text(
                              '换源',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: colorScheme.onSurface,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        InkWell(
                          onTap: _toggleEditMode,
                          borderRadius: BorderRadius.circular(20),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7.5),
                            decoration: BoxDecoration(
                              color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.75),
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(
                                color: colorScheme.outlineVariant.withValues(alpha: 0.4),
                                width: 0.8,
                              ),
                            ),
                            child: Text(
                              '管理',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: colorScheme.onSurface,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMaterialDetailEmptyState(ColorScheme colorScheme) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.hasBoundedHeight && constraints.maxHeight < 220;
        final minHeight = constraints.hasBoundedHeight ? constraints.maxHeight : 0.0;
        return SingleChildScrollView(
          physics: const ClampingScrollPhysics(),
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: minHeight),
            child: Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      padding: EdgeInsets.all(compact ? 18 : 28),
                      decoration: BoxDecoration(
                        color: colorScheme.surfaceContainerHighest.withOpacity(0.5),
                        borderRadius: BorderRadius.circular(compact ? 24 : 32),
                      ),
                      child: Icon(
                        Icons.music_off_rounded,
                        size: compact ? 52 : 64,
                        color: colorScheme.onSurface.withOpacity(0.4),
                      ),
                    ),
                    SizedBox(height: compact ? 14 : 24),
                    Text(
                      '歌单为空',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                        color: colorScheme.onSurface.withOpacity(0.7),
                        letterSpacing: -0.3,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '快去添加一些喜欢的歌曲吧',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                        color: colorScheme.onSurface.withOpacity(0.5),
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

  Widget _buildMaterialTrackItem(PlaylistTrack item, int index, ColorScheme colorScheme) {
    final trackKey = _getTrackKey(item);
    final isSelected = _selectedTrackIds.contains(trackKey);
    final player = PlayerService();
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final dynamicAccent = DynamicColorUtils.resolveAccent(
      player.themeColorNotifier.value,
      colorScheme,
      isDark: isDark,
    );

    return AnimatedBuilder(
      animation: Listenable.merge([player, player.positionNotifier]),
      builder: (context, _) {
        final currentTrack = player.currentTrack;
        final currentSong = player.currentSong;
        final displayTitle = player.displayTitle;

        final isCurrentPlaying = (displayTitle.isNotEmpty &&
                (displayTitle == item.name ||
                    item.name.contains(displayTitle) ||
                    displayTitle.contains(item.name))) ||
            (currentTrack != null && currentTrack.name == item.name) ||
            (currentSong != null && currentSong.name == item.name);

        final Color itemBg = isSelected && _isEditMode
            ? colorScheme.primaryContainer.withOpacity(0.35)
            : (isCurrentPlaying
                ? dynamicAccent.withValues(alpha: isDark ? 0.18 : 0.08)
                : Colors.transparent);

        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
          child: Material(
            color: itemBg,
            borderRadius: BorderRadius.circular(12),
            child: InkWell(
              onTap: _isEditMode ? () => _toggleTrackSelection(item) : () => _playDetailTrack(index),
              borderRadius: BorderRadius.circular(12),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
                child: Row(
                  children: [
                    if (_isEditMode)
                      Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: Checkbox(
                          value: isSelected,
                          onChanged: (_) => _toggleTrackSelection(item),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
                        ),
                      )
                    else
                      SizedBox(
                        width: 28,
                        child: isCurrentPlaying
                            ? Icon(Icons.equalizer_rounded, color: dynamicAccent, size: 20)
                            : Text(
                                (index + 1).toString().padLeft(2, '0'),
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                  color: colorScheme.onSurfaceVariant.withOpacity(0.5),
                                ),
                              ),
                      ),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: CachedNetworkImage(
                        imageUrl: item.picUrl,
                        width: 44,
                        height: 44,
                        fit: BoxFit.cover,
                        memCacheWidth: 128,
                        memCacheHeight: 128,
                        placeholder: (_, __) => Container(
                          width: 44,
                          height: 44,
                          color: colorScheme.surfaceContainerHighest,
                        ),
                        errorWidget: (_, __, ___) => Container(
                          width: 44,
                          height: 44,
                          color: colorScheme.surfaceContainerHighest,
                          child: Icon(Icons.music_note, color: colorScheme.onSurfaceVariant, size: 20),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            item.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 14.5,
                              fontWeight: isCurrentPlaying ? FontWeight.w800 : FontWeight.w600,
                              letterSpacing: -0.2,
                              color: isCurrentPlaying ? dynamicAccent : colorScheme.onSurface,
                            ),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            '${item.artists} • ${item.album}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 12,
                              color: isCurrentPlaying
                                  ? dynamicAccent.withValues(alpha: 0.85)
                                  : colorScheme.onSurfaceVariant.withOpacity(0.75),
                              fontWeight: FontWeight.normal,
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (!_isEditMode)
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Padding(
                            padding: const EdgeInsets.only(right: 8),
                            child: Text(
                              _getTrackDurationString(item, isCurrentPlaying, player),
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: isCurrentPlaying ? FontWeight.w700 : FontWeight.w500,
                                color: isCurrentPlaying
                                    ? dynamicAccent
                                    : colorScheme.onSurfaceVariant.withValues(alpha: 0.6),
                              ),
                            ),
                          ),
                          TrackMoreButton(
                            track: item.toTrack(),
                            onPlay: () => _playDetailTrack(index),
                            onDelete: () => _confirmRemoveTrack(item),
                            size: 32,
                          ),
                        ],
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

  Widget _buildMaterialUserCard(ColorScheme colorScheme) {
    final user = _authFacade.currentUser;
    if (user == null) return const SizedBox.shrink();

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            // 用户头像
            if (user.avatarUrl != null && user.avatarUrl!.contains('linux.do'))
              ClipOval(
                child: LinuxDoAvatarMaterial(
                  url: user.avatarUrl!,
                  userId: user.id,
                  size: 64,
                ),
              )
            else
              CircleAvatar(
                radius: 32,
                backgroundImage: user.avatarUrl != null ? CachedNetworkImageProvider(user.avatarUrl!) : null,
                child: user.avatarUrl == null ? Text(user.username[0].toUpperCase(), style: const TextStyle(fontSize: 24)) : null,
              ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(user.username, style: Theme.of(context).textTheme.titleLarge),
                  const SizedBox(height: 4),
                  Text(user.email, style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: colorScheme.onSurface.withOpacity(0.6))),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMaterialPlaylistCover(
    Playlist playlist,
    ColorScheme colorScheme, {
    double size = 52,
    double radius = 12,
  }) {
    if (playlist.coverUrl != null && playlist.coverUrl!.isNotEmpty) {
      return Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(radius),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.1),
              blurRadius: 6,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(radius),
          child: CachedNetworkImage(
            imageUrl: playlist.coverUrl!,
            width: size,
            height: size,
            fit: BoxFit.cover,
            memCacheWidth: 128,
            memCacheHeight: 128,
            placeholder: (_, __) => Container(
              color: colorScheme.surfaceContainerHighest,
              child: Icon(Icons.music_note_rounded, color: colorScheme.primary, size: size * 0.45),
            ),
            errorWidget: (_, __, ___) => _buildFallbackPlaylistCover(playlist, colorScheme, size: size, radius: radius),
          ),
        ),
      );
    }
    return _buildFallbackPlaylistCover(playlist, colorScheme, size: size, radius: radius);
  }

  Widget _buildFallbackPlaylistCover(
    Playlist playlist,
    ColorScheme colorScheme, {
    double size = 52,
    double radius = 12,
  }) {
    if (playlist.isDefault) {
      // 默认我喜欢的音乐：红心渐变封面，极具辨识度与高级感
      return Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(radius),
          gradient: const LinearGradient(
            colors: [Color(0xFFFF5E7E), Color(0xFFFF2A55)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFFFF2A55).withValues(alpha: 0.3),
              blurRadius: 8,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: Center(
          child: Icon(
            Icons.favorite_rounded,
            color: Colors.white,
            size: size * 0.48,
          ),
        ),
      );
    }

    // 自建普通歌单：优雅中性渐变
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(radius),
        gradient: LinearGradient(
          colors: [
            colorScheme.surfaceContainerHighest,
            colorScheme.surfaceContainerHigh,
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        border: Border.all(
          color: colorScheme.outlineVariant.withValues(alpha: 0.3),
          width: 0.8,
        ),
      ),
      child: Center(
        child: Icon(
          Icons.queue_music_rounded,
          color: colorScheme.primary,
          size: size * 0.48,
        ),
      ),
    );
  }
}

