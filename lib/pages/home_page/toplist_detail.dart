import 'dart:io';
import 'dart:ui';

import 'package:window_manager/window_manager.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:cyrene_music/models/track.dart';
import 'package:cyrene_music/models/toplist.dart';
import 'package:cyrene_music/widgets/track_list_tile.dart';
import 'package:cyrene_music/features/auth/auth_feature.dart';
import '../../widgets/track_action_menu.dart';
import 'package:cyrene_music/utils/theme_manager.dart';
import 'package:cyrene_music/utils/image_utils.dart';
import 'package:cyrene_music/services/player_service.dart';
import 'package:cyrene_music/services/playlist_queue_service.dart';
import 'package:cyrene_music/pages/auth/auth_page.dart';
import 'package:flutter/material.dart';
import 'package:fluent_ui/fluent_ui.dart' as fluent;

/// 显示榜单详情
void showToplistDetail(BuildContext context, Toplist toplist) {
  if (ThemeManager().isFluentFramework) {
    _showToplistDetailSidebarFluent(context, toplist);
    return;
  }

  if (Platform.isWindows || Platform.isMacOS || Platform.isLinux) {
    // 桌面端：从左侧弹出侧边栏
    _showToplistDetailSidebar(context, toplist);
  } else {
    // 移动端：从底部弹出抽屉
    _showToplistDetailBottomSheet(context, toplist);
  }
}

/// 桌面端：从左侧弹出侧边栏（Fluent UI 样式）
void _showToplistDetailSidebarFluent(BuildContext context, Toplist toplist) {
  final fluentTheme = fluent.FluentTheme.of(context);
  
  showGeneralDialog(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'Dismiss',
    barrierColor: Colors.transparent, 
    transitionDuration: const Duration(milliseconds: 300),
    pageBuilder: (context, animation, secondaryAnimation) {
      final curvedAnimation = CurvedAnimation(
        parent: animation,
        curve: fluent.Curves.easeOut,
        reverseCurve: fluent.Curves.easeIn,
      );

      return Stack(
        children: [
          // 模糊遮罩
          Padding(
            padding: const EdgeInsets.all(0),
            child: FadeTransition(
              opacity: curvedAnimation,
              child: GestureDetector(
                onTap: () => Navigator.of(context).pop(),
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 20.0, sigmaY: 20.0),
                  child: Container(
                    color: Colors.black.withOpacity(0.2), 
                  ),
                ),
              ),
            ),
          ),
          
          // 侧边栏内容
          SlideTransition(
            position: Tween<Offset>(
              begin: const Offset(-1.0, 0.0),
              end: Offset.zero,
            ).animate(curvedAnimation),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Padding(
                padding: const EdgeInsets.only(top: 0, bottom: 0, left: 0), 
                child: Container(
                  width: 420,
                  height: double.infinity,
                  decoration: BoxDecoration(
                    color: fluentTheme.micaBackgroundColor,
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.2),
                        blurRadius: 24,
                        offset: const Offset(4, 0),
                      ),
                    ],
                    border: Border(
                      right: BorderSide(
                        color: fluentTheme.resources.surfaceStrokeColorDefault,
                        width: 1,
                      ),
                    ),
                  ),
                  child: _ToplistDetailContentFluent(toplist: toplist),
                ),
              ),
            ),
          ),

            Positioned(
              top: 0,
              left: 0,
              right: 0,
              height: 40,
              child: GestureDetector(
                behavior: HitTestBehavior.translucent,
                onPanStart: (details) {
                  windowManager.startDragging();
                },
                child: Container(color: Colors.transparent),
              ),
            ),
        ],
      );
    },
    transitionBuilder: (context, animation, secondaryAnimation, child) {
      return child!;
    },
  );
}

/// 桌面端：从左侧弹出侧边栏（Material Design 3 样式 + 高斯模糊背景）
void _showToplistDetailSidebar(BuildContext context, Toplist toplist) {
  final colorScheme = Theme.of(context).colorScheme;

  showGeneralDialog(
    context: context,
    barrierDismissible: true,
    barrierLabel: MaterialLocalizations.of(context).modalBarrierDismissLabel,
    barrierColor: Colors.transparent, // 使用透明色，自定义背景
    transitionDuration: const Duration(milliseconds: 300),
    pageBuilder: (context, animation, secondaryAnimation) {
      // M3 标准动画曲线
      final curvedAnimation = CurvedAnimation(
        parent: animation,
        curve: Curves.easeOutCubic,
        reverseCurve: Curves.easeInCubic,
      );

      return Stack(
        children: [
          // 高斯模糊背景层（淡入效果 + 圆角裁剪）
          Padding(
            padding: const EdgeInsets.all(8.0), // 与主窗口外边距一致
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12), // 与主窗口圆角一致
              child: FadeTransition(
                opacity: curvedAnimation,
                child: GestureDetector(
                  onTap: () => Navigator.of(context).pop(), // 点击背景关闭
                  child: BackdropFilter(
                    filter: ImageFilter.blur(
                      sigmaX: 10.0, // 水平模糊强度
                      sigmaY: 10.0, // 垂直模糊强度
                    ),
                    child: Container(
                      color: colorScheme.scrim.withOpacity(0.25), // 半透明遮罩
                    ),
                  ),
                ),
              ),
            ),
          ),
          // Windows 标题栏可拖动区域（覆盖在模糊层上方）
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              height: 48, // 标题栏高度
              child: GestureDetector(
                behavior: HitTestBehavior.translucent,
                onPanStart: (details) {
                  windowManager.startDragging();
                },
                child: Container(
                  color: Colors.transparent,
                ),
              ),
            ),
          // 侧边栏内容（滑入 + 淡入效果）
          SlideTransition(
            position: Tween<Offset>(
              begin: const Offset(-1.0, 0.0),
              end: Offset.zero,
            ).animate(curvedAnimation),
            child: FadeTransition(
              opacity: curvedAnimation,
              child: Align(
                alignment: Alignment.centerLeft,
                child: Padding(
                  padding: const EdgeInsets.all(8.0), // 与主窗口保持一致的外边距
                  child: Material(
                    elevation: 0,
                    type: MaterialType.card,
                    color: Colors.transparent,
                    child: Container(
                      width: 400,
                      // 减去上下的 padding，避免超出主窗口
                      height: MediaQuery.of(context).size.height - 16,
                      decoration: BoxDecoration(
                        color:
                            colorScheme.surfaceContainerHigh, // M3 标准侧板背景色
                        borderRadius:
                            BorderRadius.circular(12), // 与主窗口圆角保持一致
                        // M3 标准阴影
                        boxShadow: [
                          BoxShadow(
                            color: colorScheme.shadow.withOpacity(0.08),
                            blurRadius: 4,
                            offset: const Offset(2, 0),
                          ),
                          BoxShadow(
                            color: colorScheme.shadow.withOpacity(0.16),
                            blurRadius: 12,
                            offset: const Offset(4, 0),
                          ),
                        ],
                      ),
                      child: ClipRRect(
                        borderRadius:
                            BorderRadius.circular(12), // 裁剪内容，与主窗口一致
                        child: _ToplistDetailContent(toplist: toplist),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      );
    },
    transitionBuilder: (context, animation, secondaryAnimation, child) {
      return child!;
    },
  );
}

/// 移动端：从底部弹出抽屉
void _showToplistDetailBottomSheet(BuildContext context, Toplist toplist) {
  final isDark = Theme.of(context).brightness == Brightness.dark;

  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    barrierColor: Colors.black.withOpacity(0.5),
    builder: (context) => DraggableScrollableSheet(
      initialChildSize: 0.88,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      builder: (context, scrollController) {
        return ClipRRect(
          borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 25, sigmaY: 25),
            child: Container(
              decoration: BoxDecoration(
                color: (isDark ? const Color(0xFF141418) : Colors.white)
                    .withOpacity(0.92),
                borderRadius:
                    const BorderRadius.vertical(top: Radius.circular(28)),
                border: Border(
                  top: BorderSide(
                    color: Colors.white.withOpacity(isDark ? 0.12 : 0.4),
                    width: 0.8,
                  ),
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(isDark ? 0.45 : 0.12),
                    blurRadius: 30,
                    offset: const Offset(0, -10),
                  ),
                ],
              ),
              child: Column(
                children: [
                  // 拖动指示器
                  Container(
                    margin: const EdgeInsets.only(top: 12, bottom: 6),
                    width: 38,
                    height: 4.5,
                    decoration: BoxDecoration(
                      color: isDark ? Colors.white24 : Colors.black12,
                      borderRadius: BorderRadius.circular(2.5),
                    ),
                  ),
                  // 榜单内容
                  Expanded(
                    child: _ToplistDetailContent(
                      toplist: toplist,
                      scrollController: scrollController,
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    ),
  );
}

/// 构建榜单详情内容（Fluent UI 样式）
class _ToplistDetailContentFluent extends StatelessWidget {
  final Toplist toplist;
  const _ToplistDetailContentFluent({required this.toplist});

  @override
  Widget build(BuildContext context) {
    final theme = fluent.FluentTheme.of(context);
    
    return Column(
      children: [
        // 头部
        Container(
          padding: const EdgeInsets.fromLTRB(24, 48, 24, 24),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 封面
              Container(
                width: 100,
                height: 100,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(8),
                  boxShadow: [
                     BoxShadow(
                      color: Colors.black.withOpacity(0.1),
                      blurRadius: 12,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: CachedNetworkImage(
                    imageUrl: toplist.coverImgUrl,
                    httpHeaders: getImageHeaders(toplist.coverImgUrl),
                    memCacheWidth: 200,
                    memCacheHeight: 200,
                    fit: BoxFit.cover,
                  ),
                ),
              ),
              const SizedBox(width: 20),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      toplist.name,
                      style: theme.typography.subtitle?.copyWith(fontWeight: FontWeight.bold),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 8),
                    Row(
                       children: [
                        Icon(fluent.FluentIcons.contact, size: 14, color: theme.resources.textFillColorSecondary),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            toplist.creator,
                            style: theme.typography.caption?.copyWith(color: theme.resources.textFillColorSecondary),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${toplist.trackCount} songs',
                      style: theme.typography.caption?.copyWith(color: theme.resources.textFillColorTertiary),
                    ),
                  ],
                ),
              ),
              // 关闭按钮
              fluent.Tooltip(
                message: '关闭',
                child: fluent.IconButton(
                  icon: const Icon(fluent.FluentIcons.chrome_close, size: 14),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ),
            ],
          ),
        ),
        
        // 分隔线
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Container(height: 1, color: theme.resources.cardStrokeColorDefault),
        ),

        // 列表
        Expanded(
          child: fluent.ListView.builder(
             padding: const EdgeInsets.symmetric(vertical: 12),
             itemCount: toplist.tracks.length,
             itemBuilder: (context, index) {
               return _FluentTrackListTile(
                 track: toplist.tracks[index],
                 index: index,
               );
             },
          ),
        ),
      ],
    );
  }
}

class _FluentTrackListTile extends StatefulWidget {
  final Track track;
  final int index;
  
  const _FluentTrackListTile({
    required this.track,
    required this.index,
  });

  @override
  State<_FluentTrackListTile> createState() => _FluentTrackListTileState();
}

class _FluentTrackListTileState extends State<_FluentTrackListTile> {
  final AuthFacade _authFacade = AuthFacade();

  // 复用 track_list_tile.dart 中的登录检查逻辑
  Future<bool> _checkLoginStatus() async {
     if (_authFacade.isLoggedIn) return true;
     
     // Fluent UI Dialog
     final result = await fluent.showDialog<bool>(
       context: context,
       builder: (context) => fluent.ContentDialog(
         title: const Text('需要登录'),
         content: const Text('此功能需要登录后才能使用，请先登录。'),
         actions: [
            fluent.Button(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('取消'),
            ),
            fluent.FilledButton(
               onPressed: () => Navigator.pop(context, true),
               child: const Text('去登录'),
            )
         ],
       ),
     );
     
     if (result == true && mounted) {
        // 假设 showAuthDialog 是全局可用的，或者我们需要引入它
        // 由于是独立文件，我们需要确认 showAuthDialog 的可用性
        // 它在 auth_page.dart 中定义，我们有 import
        final authResult = await showAuthDialog(context);
        return authResult == true && _authFacade.isLoggedIn;
     }
     return false;
  }

  @override
  Widget build(BuildContext context) {
    final theme = fluent.FluentTheme.of(context);
    final isTop3 = widget.index < 3;
    final rankColor = isTop3 ? theme.accentColor : theme.resources.textFillColorSecondary;

    return fluent.ListTile.selectable(
      selectionMode: fluent.ListTileSelectionMode.none,
      onPressed: () async {
         if (await _checkLoginStatus() && mounted) {
             PlayerService().playTrack(widget.track);
             // 简单的 toast
             _showToast(context, '正在加载: ${widget.track.name}');
         }
      },
      leading: SizedBox(
        width: 32,
        child: Center(
          child: Text(
            '${widget.index + 1}',
            style: TextStyle(
              fontWeight: FontWeight.bold,
              color: rankColor,
            ),
          ),
        ),
      ),
      title: Row(
        children: [
           ClipRRect(
             borderRadius: BorderRadius.circular(4),
             child: CachedNetworkImage(
               imageUrl: widget.track.picUrl,
               httpHeaders: getImageHeaders(widget.track.picUrl),
               width: 40,
               height: 40,
               memCacheWidth: 128,
               memCacheHeight: 128,
               fit: BoxFit.cover,
               placeholder: (c, u) => Container(color: theme.resources.controlFillColorSecondary),
             ),
           ),
           const SizedBox(width: 12),
           Expanded(
             child: Column(
               mainAxisAlignment: MainAxisAlignment.center,
               crossAxisAlignment: CrossAxisAlignment.start,
               children: [
                 Text(
                   widget.track.name,
                   maxLines: 1,
                   overflow: TextOverflow.ellipsis,
                   style: const TextStyle(fontWeight: FontWeight.w500),
                 ),
                 Text(
                   '${widget.track.artists} - ${widget.track.album}',
                   maxLines: 1,
                   overflow: TextOverflow.ellipsis,
                   style: theme.typography.caption?.copyWith(
                     color: theme.resources.textFillColorSecondary,
                   ),
                 ),
               ],
             ),
           ),
        ],
      ),
      trailing: TrackMoreButton(
        track: widget.track,
        onPlay: () async {
          if (await _checkLoginStatus() && mounted) {
            PlayerService().playTrack(widget.track);
            _showToast(context, '正在加载: ${widget.track.name}');
          }
        },
        size: 28,
      ),
    );
  }

  void _showToast(BuildContext context, String message) {
    // 尝试寻找 ScaffoldMessenger，如果没有则忽略（或实现自定义 overlay）
    // Fluent 应用如果嵌套在 MaterialApp 下通常有 ScaffoldMessenger
    try {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message), duration: const Duration(milliseconds: 1000)),
      );
    } catch (_) {
      // 忽略错误
    }
  }
}

/// 构建榜单详情内容（桌面端和移动端共用 - 流光质感风格）
class _ToplistDetailContent extends StatelessWidget {
  final Toplist toplist;
  final ScrollController? scrollController;
  const _ToplistDetailContent({required this.toplist, this.scrollController});

  Future<bool> _ensureLogin(BuildContext context) async {
    final authFacade = AuthFacade();
    if (authFacade.isLoggedIn) return true;
    final ok = await showAuthDialog(context);
    return ok == true && authFacade.isLoggedIn;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;
    final isDesktop =
        Platform.isWindows || Platform.isMacOS || Platform.isLinux;

    return ValueListenableBuilder<Color?>(
      valueListenable: PlayerService().themeColorNotifier,
      builder: (context, dynamicColor, _) {
        final accentColor = dynamicColor ?? colorScheme.primary;

        return Column(
          children: [
            // 头部信息与动态氛围
            Container(
              padding: EdgeInsets.fromLTRB(
                isDesktop ? 24.0 : 18.0,
                isDesktop ? 16.0 : 10.0,
                isDesktop ? 20.0 : 18.0,
                14.0,
              ),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    accentColor.withOpacity(isDark ? 0.14 : 0.08),
                    Colors.transparent,
                  ],
                ),
              ),
              child: Column(
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // 封面
                      Container(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(16),
                          boxShadow: [
                            BoxShadow(
                              color: accentColor.withOpacity(0.25),
                              blurRadius: 18,
                              offset: const Offset(0, 6),
                            ),
                          ],
                        ),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(16),
                          child: CachedNetworkImage(
                            imageUrl: toplist.coverImgUrl,
                            httpHeaders: getImageHeaders(toplist.coverImgUrl),
                            width: isDesktop ? 96 : 82,
                            height: isDesktop ? 96 : 82,
                            memCacheWidth: 200,
                            memCacheHeight: 200,
                            fit: BoxFit.cover,
                            placeholder: (context, url) => Container(
                              width: isDesktop ? 96 : 82,
                              height: isDesktop ? 96 : 82,
                              color: colorScheme.surfaceContainerHighest,
                              child: Center(
                                child: SizedBox(
                                  width: 24,
                                  height: 24,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2.5,
                                    color: accentColor,
                                  ),
                                ),
                              ),
                            ),
                            errorWidget: (context, url, error) => Container(
                              width: isDesktop ? 96 : 82,
                              height: isDesktop ? 96 : 82,
                              color: colorScheme.surfaceContainerHighest,
                              child: Icon(
                                Icons.music_note_rounded,
                                size: 40,
                                color: colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 16),
                      // 信息区域
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              toplist.name,
                              style: theme.textTheme.titleLarge?.copyWith(
                                fontWeight: FontWeight.w800,
                                letterSpacing: -0.5,
                                color: colorScheme.onSurface,
                              ),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 6),
                            // 创建者与曲数
                            Row(
                              children: [
                                Icon(
                                  Icons.person_outline_rounded,
                                  size: 15,
                                  color: colorScheme.onSurfaceVariant
                                      .withOpacity(0.8),
                                ),
                                const SizedBox(width: 4),
                                Expanded(
                                  child: Text(
                                    toplist.creator,
                                    style: theme.textTheme.bodySmall?.copyWith(
                                      color: colorScheme.onSurfaceVariant
                                          .withOpacity(0.85),
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 4),
                            Text(
                              '共 ${toplist.trackCount} 首歌曲',
                              style: theme.textTheme.labelMedium?.copyWith(
                                color: colorScheme.onSurfaceVariant
                                    .withOpacity(0.7),
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                      ),
                      // 关闭按钮
                      IconButton(
                        icon: Icon(
                          Icons.close_rounded,
                          size: 20,
                          color: colorScheme.onSurfaceVariant,
                        ),
                        onPressed: () => Navigator.of(context).pop(),
                        tooltip: '关闭',
                        style: IconButton.styleFrom(
                          backgroundColor: isDark
                              ? Colors.white.withOpacity(0.08)
                              : Colors.black.withOpacity(0.05),
                          padding: const EdgeInsets.all(8),
                          minimumSize: const Size(36, 36),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  // 播放全部按钮栏
                  Row(
                    children: [
                      Builder(
                        builder: (context) {
                          Color effectiveAccent = accentColor;
                          final hsv = HSVColor.fromColor(accentColor);
                          if (hsv.saturation < 0.18 && (hsv.value > 0.65 || hsv.value < 0.25)) {
                            effectiveAccent = colorScheme.primary;
                          }
                          final isLight = effectiveAccent.computeLuminance() > 0.55;
                          final onAccent = isLight ? const Color(0xFF1A1A1A) : Colors.white;

                          return Material(
                            color: Colors.transparent,
                            child: InkWell(
                              borderRadius: BorderRadius.circular(20),
                              onTap: () async {
                                if (toplist.tracks.isEmpty) return;
                                final ok = await _ensureLogin(context);
                                if (!ok) return;

                                PlaylistQueueService().setQueue(
                                  toplist.tracks,
                                  0,
                                  QueueSource.playlist,
                                );
                                await PlayerService()
                                    .playTrack(toplist.tracks.first);
                                if (context.mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: Text('开始播放：${toplist.name}'),
                                      duration: const Duration(seconds: 1),
                                    ),
                                  );
                                }
                              },
                              child: Ink(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 18,
                                  vertical: 8,
                                ),
                                decoration: BoxDecoration(
                                  gradient: LinearGradient(
                                    colors: [
                                      effectiveAccent,
                                      effectiveAccent.withOpacity(0.85),
                                    ],
                                  ),
                                  borderRadius: BorderRadius.circular(20),
                                  boxShadow: [
                                    BoxShadow(
                                      color: effectiveAccent.withOpacity(0.35),
                                      blurRadius: 12,
                                      offset: const Offset(0, 3),
                                    ),
                                  ],
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      Icons.play_arrow_rounded,
                                      color: onAccent,
                                      size: 20,
                                    ),
                                    const SizedBox(width: 6),
                                    Text(
                                      '播放全部 (${toplist.tracks.length})',
                                      style: TextStyle(
                                        color: onAccent,
                                        fontWeight: FontWeight.bold,
                                        fontSize: 13,
                                        letterSpacing: -0.2,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                    ],
                  ),
                ],
              ),
            ),
            // 优雅分隔线
            Divider(
              height: 1,
              thickness: 0.6,
              color: isDark ? Colors.white10 : Colors.black.withOpacity(0.06),
            ),
            // 歌曲列表
            Expanded(
              child: AnimatedBuilder(
                animation: PlayerService(),
                builder: (context, _) {
                  final playingTrack = PlayerService().currentTrack;
                  return ListView.builder(
                    controller: scrollController,
                    padding: EdgeInsets.only(
                      top: 4,
                      bottom: MediaQuery.of(context).padding.bottom + 16,
                    ),
                    itemCount: toplist.tracks.length,
                    itemBuilder: (context, index) {
                      final track = toplist.tracks[index];
                      final isPlaying = playingTrack != null &&
                          playingTrack.id.toString() == track.id.toString() &&
                          playingTrack.source == track.source;

                      return _ToplistSongTile(
                        track: track,
                        index: index,
                        isPlaying: isPlaying,
                        accentColor: accentColor,
                        onTap: () async {
                          final ok = await _ensureLogin(context);
                          if (!ok) return;

                          PlaylistQueueService().setQueue(
                            toplist.tracks,
                            index,
                            QueueSource.playlist,
                          );
                          await PlayerService().playTrack(track);
                        },
                      );
                    },
                  );
                },
              ),
            ),
          ],
        );
      },
    );
  }
}

class _ToplistSongTile extends StatelessWidget {
  final Track track;
  final int index;
  final bool isPlaying;
  final Color accentColor;
  final VoidCallback onTap;

  const _ToplistSongTile({
    required this.track,
    required this.index,
    required this.isPlaying,
    required this.accentColor,
    required this.onTap,
  });

  Color _getRankColor(int rank, ColorScheme colorScheme) {
    if (rank == 1) return const Color(0xFFFF9500); // 金色
    if (rank == 2) return const Color(0xFF0A84FF); // 银蓝
    if (rank == 3) return const Color(0xFFFF6B4A); // 铜橙
    return colorScheme.onSurfaceVariant.withOpacity(0.5);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;
    final rank = index + 1;
    final rankColor = _getRankColor(rank, colorScheme);

    return Material(
      color: isPlaying
          ? accentColor.withOpacity(isDark ? 0.15 : 0.1)
          : Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            children: [
              // 排名或正在播放图标
              SizedBox(
                width: 32,
                child: isPlaying
                    ? Icon(
                        Icons.volume_up_rounded,
                        color: accentColor,
                        size: 20,
                      )
                    : Text(
                        '$rank',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: rank <= 3 ? 16 : 14,
                          fontWeight:
                              rank <= 3 ? FontWeight.w900 : FontWeight.w500,
                          color: rankColor,
                          letterSpacing: -0.3,
                        ),
                      ),
              ),
              const SizedBox(width: 8),
              // 封面
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: CachedNetworkImage(
                  imageUrl: track.picUrl,
                  httpHeaders: getImageHeaders(track.picUrl),
                  width: 44,
                  height: 44,
                  memCacheWidth: 100,
                  memCacheHeight: 100,
                  fit: BoxFit.cover,
                  placeholder: (context, url) => Container(
                    width: 44,
                    height: 44,
                    color: colorScheme.surfaceContainerHighest,
                  ),
                  errorWidget: (context, url, error) => Container(
                    width: 44,
                    height: 44,
                    color: colorScheme.surfaceContainerHighest,
                    child: Icon(
                      Icons.music_note_rounded,
                      size: 20,
                      color: colorScheme.onSurfaceVariant,
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
                        fontSize: 15,
                        fontWeight:
                            isPlaying ? FontWeight.w700 : FontWeight.w600,
                        color: isPlaying ? accentColor : colorScheme.onSurface,
                        letterSpacing: -0.2,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Row(
                      children: [
                        Text(
                          track.getSourceIcon(),
                          style: const TextStyle(fontSize: 11),
                        ),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(
                            '${track.artists} - ${track.album}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 12,
                              color: colorScheme.onSurfaceVariant
                                  .withOpacity(0.75),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              // 更多操作按钮
              TrackMoreButton(
                track: track,
                onPlay: onTap,
                size: 28,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
