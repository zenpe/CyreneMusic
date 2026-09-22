import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import '../../utils/theme_manager.dart';

/// 新歌列表（移动端）
class MobileNewsongList extends StatelessWidget {
  final List<Map<String, dynamic>> list;
  const MobileNewsongList({super.key, required this.list});

  @override
  Widget build(BuildContext context) {
    final themeManager = ThemeManager();
    final isCupertino = (Platform.isIOS || Platform.isAndroid) && themeManager.isCupertinoFramework;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    if (list.isEmpty) return Text('暂无数据', style: Theme.of(context).textTheme.bodySmall);

    if (isCupertino) {
      return Container(
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF1C1C1E) : CupertinoColors.white,
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            BoxShadow(
              color: CupertinoColors.black.withValues(alpha: isDark ? 0.2 : 0.08),
              blurRadius: 10,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        clipBehavior: Clip.antiAlias,
        child: ListView.separated(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: list.length,
          separatorBuilder: (_, __) => Divider(
            height: 0.5,
            color: isDark
                ? CupertinoColors.systemGrey.withValues(alpha: 0.3)
                : CupertinoColors.systemGrey.withValues(alpha: 0.2),
          ),
          itemBuilder: (context, i) {
            final s = list[i];
            final song = (s['song'] ?? s);
            final al = (song['al'] ?? song['album'] ?? {}) as Map<String, dynamic>;
            final ar = (song['ar'] ?? song['artists'] ?? []) as List<dynamic>;
            final pic = (al['picUrl'] ?? '').toString();
            final artists = ar.map((e) => (e as Map<String, dynamic>)['name']?.toString() ?? '').where((e) => e.isNotEmpty).join('/');
            return CupertinoButton(
              padding: EdgeInsets.zero,
              onPressed: () {
                // TODO: Play this song
              },
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                child: Row(
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(6),
                      child: Image.network(pic, width: 48, height: 48, fit: BoxFit.cover),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            song['name']?.toString() ?? '',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w500,
                              color: isDark ? CupertinoColors.white : CupertinoColors.black,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            artists,
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
                    Icon(
                      CupertinoIcons.chevron_right,
                      size: 16,
                      color: CupertinoColors.systemGrey,
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      );
    }

    return ListView.separated(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: list.length,
      separatorBuilder: (_, __) => const Divider(height: 1),
      itemBuilder: (context, i) {
        final s = list[i];
        final song = (s['song'] ?? s);
        final al = (song['al'] ?? song['album'] ?? {}) as Map<String, dynamic>;
        final ar = (song['ar'] ?? song['artists'] ?? []) as List<dynamic>;
        final pic = (al['picUrl'] ?? '').toString();
        final artists = ar.map((e) => (e as Map<String, dynamic>)['name']?.toString() ?? '').where((e) => e.isNotEmpty).join('/');
        return ListTile(
          leading: ClipRRect(borderRadius: BorderRadius.circular(6), child: Image.network(pic, width: 48, height: 48, fit: BoxFit.cover)),
          title: Text(song['name']?.toString() ?? '', maxLines: 1, overflow: TextOverflow.ellipsis),
          subtitle: Text(artists, maxLines: 1, overflow: TextOverflow.ellipsis),
        );
      },
    );
  }
}
