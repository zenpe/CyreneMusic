import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:fluent_ui/fluent_ui.dart' as fluent;
import 'package:cached_network_image/cached_network_image.dart';
import '../models/track.dart';
import '../services/playlist_service.dart';
import '../utils/theme_manager.dart';


/// 歌曲操作菜单组件
/// 用于搜索结果页面中歌曲列表项的"更多"按钮
class TrackActionMenu {
  /// 显示歌曲操作菜单
  /// [context] - BuildContext
  /// [track] - 目标歌曲
  /// [onPlay] - 播放回调
  /// [anchor] - 菜单锚点位置（用于 Fluent UI popup）
  static void show({
    required BuildContext context,
    required Track track,
    VoidCallback? onPlay,
    VoidCallback? onDelete,
    Offset? anchor,
  }) {
    final themeManager = ThemeManager();
    final isExpressive = !themeManager.isCupertinoFramework && 
                        !themeManager.isFluentFramework && 
                        (Platform.isAndroid || Platform.isIOS);

    if (themeManager.isCupertinoFramework) {
      _showCupertinoActionSheet(context, track, onPlay);
    } else if (themeManager.isFluentFramework && Platform.isWindows) {
      _showFluentMenu(context, track, onPlay, anchor);
    } else if (isExpressive) {
      _showExpressiveBottomSheet(context, track, onPlay, onDelete);
    } else {
      _showMaterialMenu(context, track, onPlay);
    }
  }

  /// Material Design 3 风格弹出菜单
  static void _showMaterialMenu(
    BuildContext context,
    Track track,
    VoidCallback? onPlay,
  ) {
    final colorScheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    
    // 获取按钮位置
    final RenderBox? button = context.findRenderObject() as RenderBox?;
    final Offset buttonPosition = button?.localToGlobal(Offset.zero) ?? Offset.zero;
    final Size buttonSize = button?.size ?? const Size(40, 40);
    
    // 计算菜单位置
    final menuPosition = RelativeRect.fromLTRB(
      buttonPosition.dx,
      buttonPosition.dy + buttonSize.height,
      buttonPosition.dx + buttonSize.width,
      buttonPosition.dy,
    );
    
    showMenu<String>(
      context: context,
      position: menuPosition,
      elevation: 8,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      color: colorScheme.surface,
      items: [
        // 歌曲信息头部
        PopupMenuItem<String>(
          enabled: false,
          height: 72,
          child: Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: CachedNetworkImage(
                  imageUrl: track.picUrl,
                  width: 48,
                  height: 48,
                  memCacheWidth: 128,
                  memCacheHeight: 128,
                  fit: BoxFit.cover,
                  placeholder: (context, url) => Container(
                    width: 48,
                    height: 48,
                    color: colorScheme.surfaceContainerHighest,
                  ),
                  errorWidget: (context, url, error) => Container(
                    width: 48,
                    height: 48,
                    color: colorScheme.surfaceContainerHighest,
                    child: Icon(
                      Icons.music_note,
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
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
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: colorScheme.onSurface,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      track.artists,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12,
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              Text(
                track.getSourceIcon(),
                style: const TextStyle(fontSize: 16),
              ),
            ],
          ),
        ),
        const PopupMenuDivider(),
        // 立即播放
        PopupMenuItem<String>(
          value: 'play',
          height: 48,
          child: Row(
            children: [
              Icon(
                Icons.play_arrow_rounded,
                size: 20,
                color: colorScheme.onSurface,
              ),
              const SizedBox(width: 12),
              Text(
                '立即播放',
                style: TextStyle(
                  fontSize: 14,
                  color: colorScheme.onSurface,
                ),
              ),
            ],
          ),
        ),
        // 添加到播放队列
        PopupMenuItem<String>(
          value: 'queue',
          height: 48,
          child: Row(
            children: [
              Icon(
                Icons.queue_music_rounded,
                size: 20,
                color: colorScheme.onSurface,
              ),
              const SizedBox(width: 12),
              Text(
                '添加到播放队列',
                style: TextStyle(
                  fontSize: 14,
                  color: colorScheme.onSurface,
                ),
              ),
            ],
          ),
        ),
        // 添加到歌单
        PopupMenuItem<String>(
          value: 'playlist',
          height: 48,
          child: Row(
            children: [
              Icon(
                Icons.playlist_add_rounded,
                size: 20,
                color: colorScheme.onSurface,
              ),
              const SizedBox(width: 12),
              Text(
                '添加到歌单',
                style: TextStyle(
                  fontSize: 14,
                  color: colorScheme.onSurface,
                ),
              ),
            ],
          ),
        ),
      ],
    ).then((value) {
      if (value == null) return;
      
      switch (value) {
        case 'play':
          onPlay?.call();
          break;
        case 'queue':
          _addToQueue(context, track);
          break;
        case 'playlist':
          _showAddToPlaylistDialog(context, track);
          break;
      }
    });
  }


  /// Material Design Expressive 风格底部操作板
  static void _showExpressiveBottomSheet(
    BuildContext context,
    Track track,
    VoidCallback? onPlay,
    VoidCallback? onDelete,
  ) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.45,
        minChildSize: 0.3,
        maxChildSize: 0.8,
        expand: false,
        builder: (context, scrollController) => Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                colorScheme.surfaceContainerHigh,
                colorScheme.surfaceContainerHighest.withOpacity(isDark ? 0.95 : 0.98),
              ],
            ),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(isDark ? 0.4 : 0.15),
                blurRadius: 30,
                offset: const Offset(0, -10),
              ),
            ],
          ),
          child: Column(
            children: [
              // 拖动指示器
              Container(
                padding: const EdgeInsets.only(top: 14, bottom: 10),
                child: Container(
                  width: 48,
                  height: 5,
                  decoration: BoxDecoration(
                    color: colorScheme.outline.withOpacity(0.4),
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
              ),
              // 标题栏
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 4, 16, 16),
                child: Row(
                  children: [
                    Container(
                      width: 52,
                      height: 52,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [
                            colorScheme.primary.withOpacity(0.2),
                            colorScheme.primary.withOpacity(0.1),
                          ],
                        ),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(16),
                        child: CachedNetworkImage(
                          imageUrl: track.picUrl,
                          memCacheWidth: 200,
                          memCacheHeight: 200,
                          fit: BoxFit.cover,
                          errorWidget: (context, url, error) => Icon(
                            Icons.music_note_rounded,
                            color: colorScheme.primary,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            track.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: colorScheme.onSurface,
                              fontSize: 18,
                              fontWeight: FontWeight.w800,
                              letterSpacing: -0.5,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            track.artists,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: colorScheme.onSurfaceVariant.withOpacity(0.7),
                              fontSize: 13,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Material(
                      color: colorScheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(14),
                      child: InkWell(
                        onTap: () => Navigator.pop(context),
                        borderRadius: BorderRadius.circular(14),
                        child: Container(
                          width: 44,
                          height: 44,
                          alignment: Alignment.center,
                          child: Icon(
                            Icons.close_rounded,
                            color: colorScheme.onSurfaceVariant,
                            size: 22,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              // 操作列表
              Expanded(
                child: ListView(
                  controller: scrollController,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  children: [
                    _buildExpressiveActionItem(
                      context,
                      icon: Icons.play_arrow_rounded,
                      label: '立即播放',
                      onTap: () {
                        Navigator.pop(context);
                        onPlay?.call();
                      },
                    ),
                    _buildExpressiveActionItem(
                      context,
                      icon: Icons.queue_music_rounded,
                      label: '添加到播放队列',
                      onTap: () {
                        Navigator.pop(context);
                        _addToQueue(context, track);
                      },
                    ),
                    _buildExpressiveActionItem(
                      context,
                      icon: Icons.playlist_add_rounded,
                      label: '添加到歌单',
                      onTap: () {
                        Navigator.pop(context);
                        _showAddToPlaylistDialog(context, track);
                      },
                    ),
                    if (onDelete != null)
                      _buildExpressiveActionItem(
                        context,
                        icon: Icons.delete_outline_rounded,
                        label: '从历史记录中删除',
                        isDestructive: true,
                        onTap: () {
                          Navigator.pop(context);
                          onDelete?.call();
                        },
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  static Widget _buildExpressiveActionItem(
    BuildContext context, {
    required IconData icon,
    required String label,
    required VoidCallback onTap,
    bool isDestructive = false,
  }) {
    final colorScheme = Theme.of(context).colorScheme;
    final color = isDestructive ? colorScheme.error : colorScheme.onSurface;

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: isDestructive 
            ? colorScheme.errorContainer.withOpacity(0.3)
            : colorScheme.surfaceContainerHighest.withOpacity(0.4),
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(16),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
            child: Row(
              children: [
                Icon(icon, color: color, size: 24),
                const SizedBox(width: 16),
                Text(
                  label,
                  style: TextStyle(
                    color: color,
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const Spacer(),
                Icon(
                  Icons.chevron_right_rounded,
                  color: color.withOpacity(0.3),
                  size: 20,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// iOS Cupertino 风格操作表
  static void _showCupertinoActionSheet(
    BuildContext context,
    Track track,
    VoidCallback? onPlay,
  ) {
    final isDark = MediaQuery.of(context).platformBrightness == Brightness.dark;

    
    showCupertinoModalPopup(
      context: context,
      builder: (context) => CupertinoActionSheet(
        title: Column(
          children: [
            // 封面和标题
            Row(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: CachedNetworkImage(
                    imageUrl: track.picUrl,
                    width: 48,
                    height: 48,
                    memCacheWidth: 128,
                    memCacheHeight: 128,
                    fit: BoxFit.cover,
                    placeholder: (context, url) => Container(
                      width: 48,
                      height: 48,
                      color: isDark
                          ? const Color(0xFF2C2C2E)
                          : CupertinoColors.systemGrey5,
                    ),
                    errorWidget: (context, url, error) => Container(
                      width: 48,
                      height: 48,
                      color: isDark 
                          ? const Color(0xFF2C2C2E) 
                          : CupertinoColors.systemGrey5,
                      child: const Icon(
                        CupertinoIcons.music_note,
                        color: CupertinoColors.systemGrey,
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
                        track.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: isDark 
                              ? CupertinoColors.white 
                              : CupertinoColors.black,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        track.artists,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 13,
                          color: CupertinoColors.systemGrey,
                        ),
                      ),
                    ],
                  ),
                ),
                Text(
                  track.getSourceIcon(),
                  style: const TextStyle(fontSize: 20),
                ),
              ],
            ),
          ],
        ),
        actions: [
          CupertinoActionSheetAction(
            onPressed: () {
              Navigator.pop(context);
              onPlay?.call();
            },
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(CupertinoIcons.play_fill, size: 20),
                const SizedBox(width: 8),
                const Text('立即播放'),
              ],
            ),
          ),
          CupertinoActionSheetAction(
            onPressed: () {
              Navigator.pop(context);
              _addToQueue(context, track);
            },
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(CupertinoIcons.music_note_list, size: 20),
                const SizedBox(width: 8),
                const Text('添加到播放队列'),
              ],
            ),
          ),
          CupertinoActionSheetAction(
            onPressed: () {
              Navigator.pop(context);
              _showCupertinoAddToPlaylistDialog(context, track);
            },
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(CupertinoIcons.text_badge_plus, size: 20),
                const SizedBox(width: 8),
                const Text('添加到歌单'),
              ],
            ),
          ),
        ],
        cancelButton: CupertinoActionSheetAction(
          isDestructiveAction: false,
          onPressed: () => Navigator.pop(context),
          child: const Text('取消'),
        ),
      ),
    );
  }

  /// iOS 添加到歌单对话框
  static void _showCupertinoAddToPlaylistDialog(
    BuildContext context, 
    Track track,
  ) {
    final playlistService = PlaylistService();
    
    // 确保已加载歌单列表
    if (playlistService.playlists.isEmpty) {
      playlistService.loadPlaylists();
    }

    final isDark = MediaQuery.of(context).platformBrightness == Brightness.dark;
    
    showCupertinoModalPopup(
      context: context,
      builder: (context) => AnimatedBuilder(
        animation: playlistService,
        builder: (context, child) {
          final playlists = playlistService.playlists;
          
          return Container(
            decoration: BoxDecoration(
              color: isDark 
                  ? const Color(0xFF1C1C1E) 
                  : CupertinoColors.systemBackground,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
            ),
            child: SafeArea(
              top: false,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // 拖动指示器
                  Container(
                    width: 36,
                    height: 5,
                    margin: const EdgeInsets.only(top: 8, bottom: 12),
                    decoration: BoxDecoration(
                      color: CupertinoColors.systemGrey3,
                      borderRadius: BorderRadius.circular(2.5),
                    ),
                  ),
                  
                  // 标题
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    child: Row(
                      children: [
                        Text(
                          '添加到歌单',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w600,
                            color: isDark 
                                ? CupertinoColors.white 
                                : CupertinoColors.black,
                          ),
                        ),
                        const Spacer(),
                        CupertinoButton(
                          padding: EdgeInsets.zero,
                          onPressed: () => Navigator.pop(context),
                          child: const Icon(CupertinoIcons.xmark_circle_fill),
                        ),
                      ],
                    ),
                  ),
                  
                  // 歌单列表
                  if (playlists.isEmpty)
                    const Padding(
                      padding: EdgeInsets.all(32),
                      child: CupertinoActivityIndicator(),
                    )
                  else
                    ConstrainedBox(
                      constraints: BoxConstraints(
                        maxHeight: MediaQuery.of(context).size.height * 0.5,
                      ),
                      child: ListView.builder(
                        shrinkWrap: true,
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        itemCount: playlists.length,
                        itemBuilder: (context, index) {
                          final playlist = playlists[index];
                          return CupertinoButton(
                            padding: EdgeInsets.zero,
                            onPressed: () async {
                              Navigator.pop(context);
                              final success = await playlistService.addTrackToPlaylist(
                                playlist.id,
                                track,
                              );
                              if (context.mounted) {
                                _showCupertinoToast(
                                  context,
                                  success
                                      ? '已添加到「${playlist.name}」'
                                      : '添加失败',
                                  success,
                                );
                              }
                            },
                            child: Container(
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              child: Row(
                                children: [
                                  Container(
                                    width: 44,
                                    height: 44,
                                    decoration: BoxDecoration(
                                      color: playlist.isDefault
                                          ? CupertinoColors.systemRed.withOpacity(0.15)
                                          : CupertinoColors.systemBlue.withOpacity(0.15),
                                      borderRadius: BorderRadius.circular(10),
                                    ),
                                    child: Icon(
                                      playlist.isDefault
                                          ? CupertinoIcons.heart_fill
                                          : CupertinoIcons.music_note_list,
                                      color: playlist.isDefault
                                          ? CupertinoColors.systemRed
                                          : CupertinoColors.systemBlue,
                                      size: 20,
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          playlist.name,
                                          style: TextStyle(
                                            fontSize: 16,
                                            color: isDark 
                                                ? CupertinoColors.white 
                                                : CupertinoColors.black,
                                          ),
                                        ),
                                        Text(
                                          '${playlist.trackCount} 首歌曲',
                                          style: const TextStyle(
                                            fontSize: 13,
                                            color: CupertinoColors.systemGrey,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  const Icon(
                                    CupertinoIcons.chevron_right,
                                    color: CupertinoColors.systemGrey,
                                    size: 18,
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  
                  const SizedBox(height: 16),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  /// Fluent UI 风格菜单（Windows）- Win11 右键菜单样式
  static void _showFluentMenu(
    BuildContext context,
    Track track,
    VoidCallback? onPlay,
    Offset? anchor,
  ) {
    final fluentTheme = fluent.FluentTheme.of(context);
    final isDark = fluentTheme.brightness == Brightness.dark;
    
    // 获取按钮位置
    final RenderBox? button = context.findRenderObject() as RenderBox?;
    final Offset buttonPosition = button?.localToGlobal(Offset.zero) ?? Offset.zero;
    final Size buttonSize = button?.size ?? const Size(40, 40);
    
    // 获取屏幕尺寸
    final screenSize = MediaQuery.of(context).size;
    
    // 计算菜单位置 - 在按钮下方显示，确保不超出屏幕
    double left = buttonPosition.dx;
    double top = buttonPosition.dy + buttonSize.height;
    
    const menuWidth = 200.0;
    const menuHeight = 140.0; // 估算高度
    
    // 如果超出右边界，向左调整
    if (left + menuWidth > screenSize.width) {
      left = screenSize.width - menuWidth - 8;
    }
    // 如果超出下边界，在按钮上方显示
    if (top + menuHeight > screenSize.height) {
      top = buttonPosition.dy - menuHeight;
    }
    
    final menuPosition = anchor ?? Offset(left, top);
    
    late OverlayEntry overlayEntry;
    
    overlayEntry = OverlayEntry(
      builder: (overlayContext) {
        return Stack(
          children: [
            // 点击外部关闭
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => overlayEntry.remove(),
                child: Container(color: Colors.transparent),
              ),
            ),
            // Win11 风格菜单
            Positioned(
              left: menuPosition.dx,
              top: menuPosition.dy,
              child: TweenAnimationBuilder<double>(
                tween: Tween(begin: 0.0, end: 1.0),
                duration: const Duration(milliseconds: 100),
                curve: Curves.easeOut,
                builder: (context, value, child) {
                  return Transform.scale(
                    scale: 0.95 + (0.05 * value),
                    alignment: Alignment.topLeft,
                    child: Opacity(
                      opacity: value,
                      child: child,
                    ),
                  );
                },
                child: fluent.Acrylic(
                  elevation: 8,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                    side: BorderSide(
                      color: isDark 
                          ? Colors.white.withOpacity(0.08)
                          : Colors.black.withOpacity(0.08),
                      width: 1,
                    ),
                  ),
                  child: Container(
                    width: menuWidth,
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // 播放
                        _buildWin11MenuItem(
                          icon: fluent.FluentIcons.play,
                          label: '播放',
                          isDark: isDark,
                          onTap: () {
                            overlayEntry.remove();
                            onPlay?.call();
                          },
                        ),
                        // 添加到播放队列
                        _buildWin11MenuItem(
                          icon: fluent.FluentIcons.playlist_music,
                          label: '添加到播放队列',
                          isDark: isDark,
                          onTap: () {
                            overlayEntry.remove();
                            _addToQueue(context, track);
                          },
                        ),
                        // 分隔线
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                          child: Divider(
                            height: 1,
                            color: isDark 
                                ? Colors.white.withOpacity(0.1)
                                : Colors.black.withOpacity(0.1),
                          ),
                        ),
                        // 添加到歌单
                        _buildWin11MenuItem(
                          icon: fluent.FluentIcons.add_to,
                          label: '添加到歌单',
                          isDark: isDark,
                          onTap: () {
                            overlayEntry.remove();
                            _showFluentAddToPlaylistDialog(context, track);
                          },
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
    
    Overlay.of(context).insert(overlayEntry);
  }

  /// Win11 风格菜单项
  static Widget _buildWin11MenuItem({
    required IconData icon,
    required String label,
    required bool isDark,
    required VoidCallback onTap,
  }) {
    return fluent.HoverButton(
      onPressed: onTap,
      builder: (context, states) {
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: states.isHovering
                ? (isDark 
                    ? Colors.white.withOpacity(0.06)
                    : Colors.black.withOpacity(0.04))
                : Colors.transparent,
            borderRadius: BorderRadius.circular(4),
          ),
          margin: const EdgeInsets.symmetric(horizontal: 4),
          child: Row(
            children: [
              Icon(
                icon,
                size: 14,
                color: isDark ? Colors.white70 : Colors.black54,
              ),
              const SizedBox(width: 12),
              Text(
                label,
                style: TextStyle(
                  fontSize: 13,
                  color: isDark ? Colors.white : Colors.black87,
                  fontFamily: 'Segoe UI',
                ),
              ),
            ],
          ),
        );
      },
    );
  }


  /// Fluent 添加到歌单对话框
  static void _showFluentAddToPlaylistDialog(BuildContext context, Track track) {
    final playlistService = PlaylistService();
    
    // 确保已加载歌单列表
    if (playlistService.playlists.isEmpty) {
      playlistService.loadPlaylists();
    }

    final fluentTheme = fluent.FluentTheme.of(context);
    
    fluent.showDialog(
      context: context,
      builder: (context) => fluent.ContentDialog(
        constraints: const BoxConstraints(maxWidth: 400, maxHeight: 500),
        title: const Text('添加到歌单'),
        content: AnimatedBuilder(
          animation: playlistService,
          builder: (context, child) {
            final playlists = playlistService.playlists;
            
            if (playlists.isEmpty) {
              return const Center(
                child: Padding(
                  padding: EdgeInsets.all(32.0),
                  child: fluent.ProgressRing(),
                ),
              );
            }

            return ListView.builder(
              shrinkWrap: true,
              itemCount: playlists.length,
              itemBuilder: (context, index) {
                final playlist = playlists[index];
                return Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: fluent.ListTile(
                    leading: Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: playlist.isDefault
                            ? Colors.red.withOpacity(0.15)
                            : fluentTheme.accentColor.withOpacity(0.15),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Icon(
                        playlist.isDefault
                            ? fluent.FluentIcons.heart_fill
                            : fluent.FluentIcons.music_in_collection,
                        color: playlist.isDefault
                            ? Colors.red
                            : fluentTheme.accentColor,
                        size: 18,
                      ),
                    ),
                    title: Text(playlist.name),
                    subtitle: Text(
                      '${playlist.trackCount} 首歌曲',
                      style: TextStyle(
                        color: fluentTheme.resources.textFillColorSecondary,
                        fontSize: 12,
                      ),
                    ),
                    trailing: const Icon(fluent.FluentIcons.chevron_right),
                    onPressed: () async {
                      Navigator.pop(context);
                      final success = await playlistService.addTrackToPlaylist(
                        playlist.id,
                        track,
                      );
                      if (context.mounted) {
                        _showFluentToast(
                          context,
                          success
                              ? '已添加到「${playlist.name}」'
                              : '添加失败',
                          success,
                        );
                      }
                    },
                  ),
                );
              },
            );
          },
        ),
        actions: [
          fluent.Button(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
        ],
      ),
    );
  }

  /// Material 添加到歌单对话框
  static void _showAddToPlaylistDialog(BuildContext context, Track track) {
    final playlistService = PlaylistService();
    
    // 确保已加载歌单列表
    if (playlistService.playlists.isEmpty) {
      playlistService.loadPlaylists();
    }

    final colorScheme = Theme.of(context).colorScheme;
    
    showModalBottomSheet(
      context: context,
      backgroundColor: colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => AnimatedBuilder(
        animation: playlistService,
        builder: (context, child) {
          final playlists = playlistService.playlists;
          
          return SafeArea(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // 拖动指示器
                Container(
                  width: 40,
                  height: 4,
                  margin: const EdgeInsets.only(top: 12, bottom: 16),
                  decoration: BoxDecoration(
                    color: colorScheme.outline.withOpacity(0.4),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                
                // 标题
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                  child: Row(
                    children: [
                      Text(
                        '添加到歌单',
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const Spacer(),
                      IconButton(
                        icon: const Icon(Icons.close),
                        onPressed: () => Navigator.pop(context),
                      ),
                    ],
                  ),
                ),
                
                const Divider(height: 1),
                
                // 歌单列表
                if (playlists.isEmpty)
                  const Padding(
                    padding: EdgeInsets.all(32),
                    child: CircularProgressIndicator(),
                  )
                else
                  ConstrainedBox(
                    constraints: BoxConstraints(
                      maxHeight: MediaQuery.of(context).size.height * 0.5,
                    ),
                    child: ListView.builder(
                      shrinkWrap: true,
                      itemCount: playlists.length,
                      itemBuilder: (context, index) {
                        final playlist = playlists[index];
                        return ListTile(
                          leading: Container(
                            width: 44,
                            height: 44,
                            decoration: BoxDecoration(
                              color: playlist.isDefault
                                  ? Colors.red.withOpacity(0.15)
                                  : colorScheme.primaryContainer,
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Icon(
                              playlist.isDefault
                                  ? Icons.favorite
                                  : Icons.queue_music,
                              color: playlist.isDefault
                                  ? Colors.red
                                  : colorScheme.primary,
                              size: 20,
                            ),
                          ),
                          title: Text(playlist.name),
                          subtitle: Text('${playlist.trackCount} 首歌曲'),
                          trailing: const Icon(Icons.chevron_right),
                          onTap: () async {
                            Navigator.pop(context);
                            final success = await playlistService.addTrackToPlaylist(
                              playlist.id,
                              track,
                            );
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text(
                                    success
                                        ? '已添加到「${playlist.name}」'
                                        : '添加失败',
                                  ),
                                  duration: const Duration(seconds: 1),
                                ),
                              );
                            }
                          },
                        );
                      },
                    ),
                  ),
                
                const SizedBox(height: 8),
              ],
            ),
          );
        },
      ),
    );
  }

  /// 添加到播放队列
  static void _addToQueue(BuildContext context, Track track) {
    // TODO: 实现添加到播放队列功能
    // 目前 PlaylistQueueService 没有 addToQueue 方法
    // 暂时显示提示信息
    
    final themeManager = ThemeManager();
    const message = '功能开发中，敬请期待';
    
    if (themeManager.isCupertinoFramework) {
      _showCupertinoToast(context, message, false);
    } else if (themeManager.isFluentFramework && Platform.isWindows) {
      _showFluentToast(context, message, false);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(message),
          duration: Duration(seconds: 1),
        ),
      );
    }
  }


  /// iOS 风格 Toast 提示
  static void _showCupertinoToast(BuildContext context, String message, bool success) {
    showCupertinoModalPopup(
      context: context,
      builder: (context) {
        // 自动关闭
        Future.delayed(const Duration(seconds: 1), () {
          if (context.mounted) {
            Navigator.of(context).maybePop();
          }
        });
        
        return Container(
          margin: const EdgeInsets.only(bottom: 100),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
          decoration: BoxDecoration(
            color: Colors.black.withOpacity(0.75),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                success ? CupertinoIcons.checkmark_circle_fill : CupertinoIcons.xmark_circle_fill,
                color: success ? CupertinoColors.systemGreen : CupertinoColors.systemRed,
                size: 20,
              ),
              const SizedBox(width: 8),
              Text(
                message,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 15,
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  /// Fluent 风格 Toast 提示
  static void _showFluentToast(BuildContext context, String message, bool success) {
    // 使用 ScaffoldMessenger 作为后备方案
    final messenger = ScaffoldMessenger.maybeOf(context);
    if (messenger != null) {
      messenger.showSnackBar(
        SnackBar(
          content: Text(message),
          duration: const Duration(seconds: 1),
        ),
      );
    }
  }
}

/// "更多"按钮组件
/// 用于歌曲列表项右侧
class TrackMoreButton extends StatelessWidget {
  final Track track;
  final VoidCallback? onPlay;
  final VoidCallback? onDelete;
  final double? size;
  
  const TrackMoreButton({
    super.key,
    required this.track,
    this.onPlay,
    this.onDelete,
    this.size,
  });

  @override
  Widget build(BuildContext context) {
    final themeManager = ThemeManager();
    
    if (themeManager.isCupertinoFramework) {
      return CupertinoButton(
        padding: EdgeInsets.zero,
        minSize: size ?? 36,
        onPressed: () => TrackActionMenu.show(
          context: context,
          track: track,
          onPlay: onPlay,
          onDelete: onDelete,
        ),
        child: Icon(
          CupertinoIcons.ellipsis,
          size: size != null ? size! * 0.55 : 20,
          color: CupertinoColors.systemGrey,
        ),
      );
    } else if (themeManager.isFluentFramework && Platform.isWindows) {
      return fluent.IconButton(
        icon: Icon(
          fluent.FluentIcons.more,
          size: size != null ? size! * 0.45 : 16,
        ),
        onPressed: () => TrackActionMenu.show(
          context: context,
          track: track,
          onPlay: onPlay,
          onDelete: onDelete,
        ),
      );
    } else {
      return IconButton(
        iconSize: size != null ? size! * 0.55 : 20,
        constraints: BoxConstraints(
          minWidth: size ?? 36,
          minHeight: size ?? 36,
        ),
        padding: EdgeInsets.zero,
        icon: Icon(
          Icons.more_vert,
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
        onPressed: () => TrackActionMenu.show(
          context: context,
          track: track,
          onPlay: onPlay,
          onDelete: onDelete,
        ),
        tooltip: '更多操作',
      );
    }
  }
}
