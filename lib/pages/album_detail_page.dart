import 'package:cached_network_image/cached_network_image.dart';
import 'package:fluent_ui/fluent_ui.dart' as fluent;
import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'dart:io';
import 'package:flutter_acrylic/flutter_acrylic.dart';
import '../utils/theme_manager.dart';
import '../services/netease_album_service.dart';
import '../models/track.dart';
import '../services/player_service.dart';

class AlbumDetailPage extends StatefulWidget {
  final int albumId;
  final bool embedded;
  const AlbumDetailPage({super.key, required this.albumId, this.embedded = false});

  @override
  State<AlbumDetailPage> createState() => _AlbumDetailPageState();
}

class _AlbumDetailPageState extends State<AlbumDetailPage> {
  Map<String, dynamic>? _data;
  bool _loading = true;
  String? _error;
  bool _useGrid = false; // 歌曲视图模式
  bool _descExpanded = false; // 描述折叠状态

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    final data = await NeteaseAlbumService().fetchAlbumDetail(widget.albumId);
    if (!mounted) return;
    setState(() {
      _data = data;
      _loading = false;
      if (data == null) _error = '加载失败';
    });
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    if (widget.embedded) {
      return _buildBody();
    }
    
    final isFluent = fluent.FluentTheme.maybeOf(context) != null;
    final isCupertino = ThemeManager().isCupertinoFramework;
    final isExpressive = !isFluent && !isCupertino && (Platform.isAndroid || Platform.isIOS);

    if (isFluent) {
      final useWindowEffect =
          Platform.isWindows && ThemeManager().windowEffect != WindowEffect.disabled;
      final body = _buildBody();
      return Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          title: const Text('专辑详情'),
          backgroundColor: Colors.transparent,
          surfaceTintColor: Colors.transparent,
          elevation: 0,
          scrolledUnderElevation: 0,
        ),
        body: useWindowEffect
            ? body
            : Container(
                color: fluent.FluentTheme.of(context).micaBackgroundColor,
                child: body,
              ),
      );
    }

    if (isCupertino) {
      final isDark = Theme.of(context).brightness == Brightness.dark;
      return CupertinoPageScaffold(
        backgroundColor: isDark 
            ? const Color(0xFF000000) 
            : CupertinoColors.systemGroupedBackground,
        navigationBar: CupertinoNavigationBar(
          middle: const Text('专辑详情'),
          backgroundColor: isDark 
              ? const Color(0xFF1C1C1E).withOpacity(0.9) 
              : CupertinoColors.white.withOpacity(0.9),
        ),
        child: _buildBody(),
      );
    }

    return Scaffold(
      backgroundColor: cs.surface,
      appBar: AppBar(
        title: const Text('专辑详情'),
        backgroundColor: cs.surface,
        elevation: 0,
        scrolledUnderElevation: 0,
        surfaceTintColor: Colors.transparent,
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    final isFluent = fluent.FluentTheme.maybeOf(context) != null;
    final isCupertino = ThemeManager().isCupertinoFramework;
    final isExpressive = !isFluent && !isCupertino && (Platform.isAndroid || Platform.isIOS);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    if (_loading) {
      return Center(child: _buildAdaptiveProgressIndicator(isFluent));
    }
    if (_error != null) return Center(child: Text(_error!));

    final album = _data!['album'] as Map<String, dynamic>? ?? {};
    final songs = (album['songs'] as List<dynamic>? ?? []) as List<dynamic>;
    final coverUrl = (album['coverImgUrl'] ?? '') as String? ?? '';
    final fluentTheme = isFluent ? fluent.FluentTheme.of(context) : null;
    final placeholderColor = isFluent
        ? fluentTheme?.resources?.controlAltFillColorSecondary ??
            Colors.black.withOpacity(0.05)
        : Theme.of(context).colorScheme.surfaceContainerHighest;

    Widget buildCover() {
      if (coverUrl.isEmpty) {
        return Container(
          width: 120,
          height: 120,
          color: placeholderColor,
          child: Icon(
            Icons.album,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        );
      }
      return CachedNetworkImage(
        imageUrl: coverUrl,
        width: 120,
        height: 120,
        memCacheWidth: 280,
        memCacheHeight: 280,
        fit: BoxFit.cover,
        placeholder: (_, __) => Container(
          width: 120,
          height: 120,
          color: placeholderColor,
          child: Center(
            child: SizedBox(
              width: 20,
              height: 20,
              child: _buildAdaptiveProgressIndicator(isFluent),
            ),
          ),
        ),
        errorWidget: (_, __, ___) => Container(
          width: 120,
          height: 120,
          color: placeholderColor,
          child: Icon(
            Icons.album,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
      );
    }

    final headerContent = Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(isExpressive ? 24 : 8),
          child: buildCover(),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(album['name']?.toString() ?? '',
                  style: TextStyle(
                    fontSize: isExpressive ? 20 : 18, 
                    fontWeight: FontWeight.w700,
                    color: isCupertino ? (isDark ? Colors.white : Colors.black) : null,
                  )),
              const SizedBox(height: 6),
              Text(album['artist']?.toString() ?? '',
                  style: TextStyle(
                    fontSize: 14,
                    color: isCupertino ? CupertinoColors.systemGrey : null,
                  )),
              GestureDetector(
                onTap: () => setState(() => _descExpanded = !_descExpanded),
                child: AnimatedSize(
                  duration: const Duration(milliseconds: 300),
                  curve: Curves.easeInOut,
                  alignment: Alignment.topLeft,
                  child: Text(
                    album['description']?.toString() ?? '',
                    maxLines: _descExpanded ? null : (isExpressive ? 2 : 3),
                    overflow: _descExpanded ? TextOverflow.visible : TextOverflow.ellipsis,
                    style: isCupertino 
                        ? const TextStyle(color: CupertinoColors.systemGrey, fontSize: 13) 
                        : isExpressive 
                            ? TextStyle(fontSize: 13, color: Theme.of(context).colorScheme.onSurfaceVariant.withOpacity(0.8))
                            : null,
                  ),
                ),
              ),
              if (isExpressive && album['description'] != null && album['description'].toString().length > 40)
                const SizedBox(height: 4),
              if (isExpressive && album['description'] != null && album['description'].toString().length > 40)
                Align(
                  alignment: Alignment.centerRight,
                  child: GestureDetector(
                    onTap: () => setState(() => _descExpanded = !_descExpanded),
                    child: Text(
                      _descExpanded ? '收起' : '展开',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ],
    );

    final header = isExpressive
        ? Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surfaceContainerHigh,
                borderRadius: BorderRadius.circular(32),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(isDark ? 0.3 : 0.05),
                    blurRadius: 20,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: headerContent,
            ),
          )
        : isFluent || isCupertino
            ? _buildAdaptiveCard(
                isFluent: isFluent,
                isCupertino: isCupertino,
                isDark: isDark,
                padding: const EdgeInsets.all(16),
                child: headerContent,
              )
            : headerContent;


    final iconColor = isFluent
        ? fluentTheme?.resources?.textFillColorSecondary ?? Colors.grey
        : Theme.of(context).colorScheme.onSurfaceVariant;

    final viewToggleRow = Padding(
      padding: EdgeInsets.symmetric(horizontal: isExpressive ? 20 : 0),
      child: Row(
        children: [
          Text('歌曲', 
            style: isExpressive 
                ? TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: Theme.of(context).colorScheme.onSurface)
                : isCupertino
                    ? TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: isDark ? Colors.white : Colors.black)
                    : Theme.of(context).textTheme.titleMedium,
          ),
          const Spacer(),
          if (!isExpressive) ...[
            Icon(isCupertino ? CupertinoIcons.list_bullet : Icons.view_list, 
                 size: 18, color: iconColor),
            const SizedBox(width: 8),
            isFluent
                ? fluent.ToggleSwitch(
                    checked: _useGrid,
                    onChanged: (v) => setState(() => _useGrid = v),
                    content: Text(_useGrid ? '缩略图' : '列表'),
                  )
                : isCupertino
                    ? CupertinoSwitch(
                        value: _useGrid,
                        onChanged: (v) => setState(() => _useGrid = v),
                      )
                    : Switch(value: _useGrid, onChanged: (v) => setState(() => _useGrid = v)),
            const SizedBox(width: 8),
            Icon(isCupertino ? CupertinoIcons.square_grid_2x2 : Icons.grid_view, 
                 size: 18, color: iconColor),
          ],
        ],
      ),
    );



    final children = <Widget>[
      header,
      const SizedBox(height: 16),
      viewToggleRow,
      const SizedBox(height: 8),
    ];

    if (!_useGrid) {
      children.addAll(
        songs.map(
          (s0) => _buildSongListItem(
            context: context,
            song: s0 as Map<String, dynamic>,
            album: album,
            isFluent: isFluent,
            placeholderColor: placeholderColor,
          ),
        ),
      );
    } else {
      children.add(const SizedBox(height: 4));
      children.add(
        _buildSongsGrid(
          context: context,
          songs: songs.cast<Map<String, dynamic>>(),
          album: album,
          isFluent: isFluent,
          placeholderColor: placeholderColor,
        ),
      );
    }

    final bottomPadding = MediaQuery.of(context).padding.bottom + 100;
    return ListView(
      padding: EdgeInsets.only(
        left: 16, 
        right: 16, 
        top: isExpressive ? 8 : 16, 
        bottom: bottomPadding
      ),
      children: children,
    );

  }
}

Widget _buildAdaptiveCard({
  required bool isFluent,
  bool isCupertino = false,
  bool isDark = false,
  EdgeInsetsGeometry? margin,
  EdgeInsetsGeometry? padding,
  required Widget child,
}) {
  if (isFluent) {
    return Padding(
      padding: margin ?? EdgeInsets.zero,
      child: fluent.Card(
        padding: padding ?? EdgeInsets.zero,
        child: child,
      ),
    );
  }
  if (isCupertino) {
    return Container(
      margin: margin,
      padding: padding,
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1C1C1E) : Colors.white,
        borderRadius: BorderRadius.circular(12),
      ),
      child: child,
    );
  }
  return Card(
    margin: margin,
    child: padding != null ? Padding(padding: padding, child: child) : child,
  );
}


Widget _buildAdaptiveListTile({
  required bool isFluent,
  Widget? leading,
  Widget? title,
  Widget? subtitle,
  Widget? trailing,
  VoidCallback? onPressed,
}) {
  if (isFluent) {
    return fluent.ListTile(
      leading: leading,
      title: title,
      subtitle: subtitle,
      trailing: trailing,
      onPressed: onPressed,
    );
  }
  return ListTile(
    leading: leading,
    title: title,
    subtitle: subtitle,
    trailing: trailing,
    onTap: onPressed,
  );
}

Widget _buildAdaptiveProgressIndicator(bool isFluent) {
  return isFluent
      ? const fluent.ProgressRing()
      : const CircularProgressIndicator();
}

Widget _buildSongListItem({
  required BuildContext context,
  required Map<String, dynamic> song,
  required Map<String, dynamic> album,
  required bool isFluent,
  required Color placeholderColor,
}) {
  final isCupertino = ThemeManager().isCupertinoFramework;
  final isExpressive = !isFluent && !isCupertino && (Platform.isAndroid || Platform.isIOS);
  final isDark = Theme.of(context).brightness == Brightness.dark;
  final cs = Theme.of(context).colorScheme;

  final track = Track(
    id: song['id'],
    name: song['name']?.toString() ?? '',
    artists: song['artists']?.toString() ?? '',
    album: song['album']?.toString() ?? (album['name']?.toString() ?? ''),
    picUrl: song['picUrl']?.toString() ?? (album['coverImgUrl']?.toString() ?? ''),
    source: MusicSource.netease,
  );

  final leading = Hero(
    tag: 'album_song_${track.id}',
    child: Container(
      decoration: isExpressive ? BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.08),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ) : null,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(isExpressive ? 14 : isCupertino ? 10 : 4),
        child: CachedNetworkImage(
          imageUrl: track.picUrl,
          memCacheWidth: 128,
          memCacheHeight: 128,
          width: isExpressive ? 56 : 50,
          height: isExpressive ? 56 : 50,
          fit: BoxFit.cover,
          placeholder: (_, __) => Container(
            width: isExpressive ? 56 : 50,
            height: isExpressive ? 56 : 50,
            color: placeholderColor,
            child: Center(
              child: SizedBox(
                width: 16,
                height: 16,
                child: _buildAdaptiveProgressIndicator(isFluent),
              ),
            ),
          ),
          errorWidget: (_, __, ___) => Container(
            width: isExpressive ? 56 : 50,
            height: isExpressive ? 56 : 50,
            color: placeholderColor,
            child: Icon(
              isCupertino ? CupertinoIcons.music_note : Icons.music_note,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      ),
    ),
  );

  final trailing = isExpressive
      ? const SizedBox.shrink()
      : isFluent
          ? const fluent.Icon(fluent.FluentIcons.play)
          : isCupertino
              ? const Icon(CupertinoIcons.play_circle, color: CupertinoColors.systemGrey)
              : const Icon(Icons.play_arrow);

  if (isExpressive) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () => PlayerService().playTrack(track),
          borderRadius: BorderRadius.circular(20),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Row(
              children: [
                leading,
                const SizedBox(width: 16),
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
                const SizedBox(width: 8),
                trailing,
              ],
            ),
          ),
        ),
      ),
    );
  }

  return _buildAdaptiveCard(
    isFluent: isFluent,
    isCupertino: isCupertino,
    isDark: isDark,
    margin: const EdgeInsets.only(bottom: 8),
    padding: EdgeInsets.zero,
    child: _buildAdaptiveListTile(
      isFluent: isFluent,
      leading: leading,
      title: Text(
        track.name,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: isCupertino ? TextStyle(color: isDark ? Colors.white : Colors.black, fontWeight: FontWeight.w500) : null,
      ),
      subtitle: Text(
        '${track.artists} • ${track.album}',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: isCupertino ? const TextStyle(color: CupertinoColors.systemGrey, fontSize: 13) : null,
      ),
      trailing: trailing,
      onPressed: () => PlayerService().playTrack(track),
    ),
  );
}


Widget _buildSongsGrid({
  required BuildContext context,
  required List<Map<String, dynamic>> songs,
  required Map<String, dynamic> album,
  required bool isFluent,
  required Color placeholderColor,
}) {
  return Wrap(
    spacing: 12,
    runSpacing: 12,
    children: songs.map((song) {
      final isCupertino = ThemeManager().isCupertinoFramework;
      final isExpressive = !isFluent && !isCupertino && (Platform.isAndroid || Platform.isIOS);
      final isDark = Theme.of(context).brightness == Brightness.dark;
      final cs = Theme.of(context).colorScheme;

      final track = Track(
        id: song['id'],
        name: song['name']?.toString() ?? '',
        artists: song['artists']?.toString() ?? '',
        album: song['album']?.toString() ?? (album['name']?.toString() ?? ''),
        picUrl: song['picUrl']?.toString() ?? (album['coverImgUrl']?.toString() ?? ''),
        source: MusicSource.netease,
      );

      final trailing = isExpressive
          ? const SizedBox.shrink()
          : isFluent
              ? const fluent.Icon(fluent.FluentIcons.play)
              : isCupertino
                  ? const Icon(CupertinoIcons.play_circle_fill, color: CupertinoColors.activeBlue)
                  : const Icon(Icons.play_arrow);

      final cardContent = Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(isExpressive ? 16 : 8),
            child: CachedNetworkImage(
              imageUrl: track.picUrl,
              width: isExpressive ? 88 : 80,
              height: isExpressive ? 88 : 80,
              memCacheWidth: 280,
              memCacheHeight: 280,
              fit: BoxFit.cover,
              placeholder: (_, __) => Container(
                width: isExpressive ? 88 : 80,
                height: isExpressive ? 88 : 80,
                color: placeholderColor,
                child: Center(
                  child: SizedBox(
                    width: 18,
                    height: 18,
                    child: _buildAdaptiveProgressIndicator(isFluent),
                  ),
                ),
              ),
              errorWidget: (_, __, ___) => Container(
                width: isExpressive ? 88 : 80,
                height: isExpressive ? 88 : 80,
                color: placeholderColor,
                child: Icon(
                  Icons.music_note,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
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
                    fontWeight: FontWeight.w700,
                    fontSize: isExpressive ? 15 : null,
                    color: isCupertino ? (isDark ? Colors.white : Colors.black) : null,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  track.artists,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: isCupertino 
                      ? const TextStyle(color: CupertinoColors.systemGrey, fontSize: 12)
                      : Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(height: 6),
                Text(
                  track.album,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: isCupertino 
                      ? const TextStyle(color: CupertinoColors.systemGrey, fontSize: 12)
                      : Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          trailing,
        ],
      );

      final card = isExpressive
          ? Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: cs.surfaceContainerHigh,
                borderRadius: BorderRadius.circular(24),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(isDark ? 0.2 : 0.04),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: cardContent,
            )
          : _buildAdaptiveCard(
              isFluent: isFluent,
              isCupertino: isCupertino,
              isDark: isDark,
              padding: const EdgeInsets.all(10),
              child: cardContent,
            );

      void handleTap() => PlayerService().playTrack(track);

      return ConstrainedBox(
        constraints: BoxConstraints(
          minWidth: 260, 
          maxWidth: isExpressive ? 480 : 440
        ),
        child: isFluent
            ? GestureDetector(onTap: handleTap, child: card)
            : InkWell(
                onTap: handleTap,
                borderRadius: BorderRadius.circular(isExpressive ? 24 : 12),
                child: card,
              ),
      );
    }).toList(),
  );

}
