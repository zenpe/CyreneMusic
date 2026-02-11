import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../utils/theme_manager.dart';

/// 歌单网格（移动端）
class MobilePlaylistGrid extends StatelessWidget {
  final List<Map<String, dynamic>> list;
  final void Function(int id)? onTap;
  const MobilePlaylistGrid({super.key, required this.list, this.onTap});
  
  @override
  Widget build(BuildContext context) {
    if (list.isEmpty) return Text('暂无数据', style: Theme.of(context).textTheme.bodySmall);
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 220,
        childAspectRatio: 0.68,
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
      ),
      itemCount: list.length,
      itemBuilder: (context, i) {
        final p = list[i];
        final pic = (p['picUrl'] ?? p['coverImgUrl'] ?? '').toString();
        final idVal = p['id'];
        final id = int.tryParse(idVal?.toString() ?? '');
        return InkWell(
          onTap: id != null && onTap != null ? () => onTap!(id) : null,
          child: MobileHoverPlaylistCard(
            id: id ?? 0,
            name: p['name']?.toString() ?? '',
            picUrl: pic,
            description: (p['description'] ?? p['copywriter'] ?? '').toString(),
          ),
        );
      },
    );
  }
}

/// 悬停歌单卡片（移动端）
class MobileHoverPlaylistCard extends StatefulWidget {
  final int id;
  final String name;
  final String picUrl;
  final String description;
  const MobileHoverPlaylistCard({super.key, required this.id, required this.name, required this.picUrl, required this.description});

  @override
  State<MobileHoverPlaylistCard> createState() => _MobileHoverPlaylistCardState();
}

class _MobileHoverPlaylistCardState extends State<MobileHoverPlaylistCard> {
  bool _hovering = false;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final themeManager = ThemeManager();
    final isCupertino = (Platform.isIOS || Platform.isAndroid) && themeManager.isCupertinoFramework;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    
    return MouseRegion(
      onEnter: (_) => setState(() => _hovering = true),
      onExit: (_) => setState(() => _hovering = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        curve: Curves.easeOut,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          boxShadow: _hovering
              ? [
                  BoxShadow(
                    color: cs.shadow.withOpacity(0.06),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  )
                ]
              : [],
        ),
        child: isCupertino
            ? Container(
                decoration: BoxDecoration(
                  color: isDark ? const Color(0xFF1C1C1E) : CupertinoColors.white,
                  borderRadius: BorderRadius.circular(12),
                ),
                clipBehavior: Clip.antiAlias,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    AspectRatio(
                      aspectRatio: 1,
                      child: ClipRect(
                        child: Stack(
                          fit: StackFit.expand,
                          children: [
                            SizedBox.expand(
                              child: AnimatedScale(
                                duration: const Duration(milliseconds: 160),
                                curve: Curves.easeOut,
                                scale: _hovering ? 1.10 : 1.0,
                                child: Hero(
                                  tag: 'playlist_cover_${widget.id}',
                                  child: CachedNetworkImage(
                                    imageUrl: widget.picUrl,
                                    fit: BoxFit.cover,
                                    memCacheWidth: 280,
                                    memCacheHeight: 280,
                                    placeholder: (context, url) => Container(
                                      color: CupertinoColors.systemGrey6,
                                      child: const Icon(
                                        CupertinoIcons.music_note,
                                        color: CupertinoColors.systemGrey,
                                      ),
                                    ),
                                    errorWidget: (context, url, error) => Container(
                                      color: CupertinoColors.systemGrey6,
                                      child: const Icon(
                                        CupertinoIcons.exclamationmark_circle,
                                        color: CupertinoColors.systemGrey,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                            Align(
                              alignment: Alignment.bottomCenter,
                              child: AnimatedSlide(
                                duration: const Duration(milliseconds: 200),
                                curve: Curves.easeOutCubic,
                                offset: _hovering ? Offset.zero : const Offset(0, 1),
                                child: FractionallySizedBox(
                                  widthFactor: 1.0,
                                  heightFactor: 0.38,
                                  alignment: Alignment.bottomCenter,
                                  child: Container(
                                    decoration: BoxDecoration(
                                      gradient: LinearGradient(
                                        begin: Alignment.topCenter,
                                        end: Alignment.bottomCenter,
                                        colors: [
                                          Colors.black.withOpacity(0.0),
                                          Colors.black.withOpacity(0.65),
                                        ],
                                      ),
                                    ),
                                    padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
                                    child: Align(
                                      alignment: Alignment.bottomLeft,
                                      child: Text(
                                        (widget.description.isNotEmpty ? widget.description : widget.name),
                                        style: const TextStyle(color: Colors.white, fontSize: 12, height: 1.2),
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.all(8.0),
                      child: SizedBox(
                        width: double.infinity,
                        height: 50,
                        child: Align(
                          alignment: Alignment.topLeft,
                          child: Text(
                            widget.name,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            softWrap: true,
                            textAlign: TextAlign.left,
                            style: TextStyle(
                              fontWeight: FontWeight.w600,
                              color: isDark ? CupertinoColors.white : CupertinoColors.black,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              )
            : Card(
          clipBehavior: Clip.antiAlias,
          elevation: 0,
          color: themeManager.isFluentFramework ? null : cs.surfaceContainer,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(isCupertino ? 12 : 28)),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              AspectRatio(
                aspectRatio: 1,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(isCupertino ? 12 : 24),
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      SizedBox.expand(
                        child: AnimatedScale(
                          duration: const Duration(milliseconds: 160),
                          curve: Curves.easeOut,
                          scale: _hovering ? 1.10 : 1.0,
                          child: Hero(
                            tag: 'playlist_cover_${widget.id}',
                            child: CachedNetworkImage(
                              imageUrl: widget.picUrl,
                              fit: BoxFit.cover,
                              memCacheWidth: 280,
                              memCacheHeight: 280,
                              placeholder: (context, url) => Container(
                                color: cs.surfaceContainerHighest,
                                child: Icon(
                                  Icons.music_note,
                                  color: cs.onSurface.withOpacity(0.3),
                                ),
                              ),
                              errorWidget: (context, url, error) => Container(
                                color: cs.surfaceContainerHighest,
                                child: Icon(
                                  Icons.broken_image,
                                  color: cs.onSurface.withOpacity(0.3),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                      Align(
                        alignment: Alignment.bottomCenter,
                        child: AnimatedSlide(
                          duration: const Duration(milliseconds: 200),
                          curve: Curves.easeOutCubic,
                          offset: _hovering ? Offset.zero : const Offset(0, 1),
                          child: FractionallySizedBox(
                            widthFactor: 1.0,
                            heightFactor: 0.38,
                            alignment: Alignment.bottomCenter,
                            child: Container(
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  begin: Alignment.topCenter,
                                  end: Alignment.bottomCenter,
                                  colors: [
                                    Colors.black.withOpacity(0.0),
                                    Colors.black.withOpacity(0.65),
                                  ],
                                ),
                              ),
                              padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
                              child: Align(
                                alignment: Alignment.bottomLeft,
                                child: Text(
                                  (widget.description.isNotEmpty ? widget.description : widget.name),
                                  style: const TextStyle(color: Colors.white, fontSize: 12, height: 1.2),
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(8.0),
                child: SizedBox(
                  width: double.infinity,
                  height: 50,
                  child: Align(
                    alignment: Alignment.topLeft,
                    child: Text(
                      widget.name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      softWrap: true,
                      textAlign: TextAlign.left,
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
