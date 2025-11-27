import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:fluent_ui/fluent_ui.dart' as fluent;
import 'package:http/http.dart' as http;
import '../services/url_service.dart';
import '../services/playlist_service.dart';
import '../services/auth_service.dart';
import '../services/kugou_login_service.dart';
import '../models/playlist.dart';
import '../models/track.dart';
import '../utils/theme_manager.dart';

/// 音乐平台枚举
enum MusicPlatform {
  netease('网易云音乐', '🎵'),
  qq('QQ音乐', '🎶'),
  kugou('酷狗音乐', '🎸');

  final String name;
  final String icon;
  const MusicPlatform(this.name, this.icon);
}

/// 从网易云/QQ音乐导入歌单对话框
class ImportPlaylistDialog {

  /// 解析网易云音乐歌单URL，提取歌单ID
  static String? _parseNeteasePlaylistId(String input) {
    final trimmedInput = input.trim();
    
    // 如果输入的是纯数字ID，直接返回
    if (RegExp(r'^\d+$').hasMatch(trimmedInput)) {
      return trimmedInput;
    }
 
    
    // 尝试从URL中解析ID
    try {
      // 支持的URL格式：
      // https://music.163.com/#/playlist?id=2154199263&creatorId=1408148628
      // https://music.163.com/playlist?id=2154199263&creatorId=1408148628
      // http://music.163.com/#/playlist?id=2154199263
      
      final uri = Uri.parse(trimmedInput);
      
      // 检查是否是网易云音乐域名
      if (!uri.host.contains('music.163.com')) {
        return null;
      }
      
      String? playlistId;
      
      // 首先检查主URL的查询参数
      playlistId = uri.queryParameters['id'];
      
      // 如果主URL没有，检查fragment中的查询参数
      if (playlistId == null && uri.fragment.isNotEmpty) {
        // fragment可能包含路径和查询参数，如：/playlist?id=2154199263&creatorId=1408148628
        final fragmentParts = uri.fragment.split('?');
        if (fragmentParts.length > 1) {
          // 解析fragment中的查询参数
          final fragmentQuery = fragmentParts[1];
          final fragmentParams = Uri.splitQueryString(fragmentQuery);
          playlistId = fragmentParams['id'];
        }
      }
      
      // 也尝试直接用正则表达式从整个URL中匹配ID
      if (playlistId == null) {
        final idMatch = RegExp(r'[?&]id=(\d+)').firstMatch(trimmedInput);
        if (idMatch != null) {
          playlistId = idMatch.group(1);
        }
      }
      
      // 验证ID是否为纯数字
      if (playlistId != null && RegExp(r'^\d+$').hasMatch(playlistId)) {
        return playlistId;
      }
      
      return null;
    } catch (e) {
      // URL解析失败，尝试正则表达式兜底
      try {
        final idMatch = RegExp(r'[?&]id=(\d+)').firstMatch(trimmedInput);
        if (idMatch != null) {
          return idMatch.group(1);
        }
      } catch (_) {
        // 忽略正则表达式错误
      }
      return null;
    }
  }

  /// 解析QQ音乐歌单URL，提取歌单ID (dissid)
  static String? _parseQQPlaylistId(String input) {
    final trimmedInput = input.trim();
    
    // 如果输入的是纯数字ID，直接返回
    if (RegExp(r'^\d+$').hasMatch(trimmedInput)) {
      return trimmedInput;
    }
    
    // 尝试从URL中解析ID
    try {
      // 支持的URL格式：
      // https://y.qq.com/n/ryqq/playlist/8522515502
      // https://y.qq.com/n/m/detail/taoge/index.html?id=8522515502
      // https://c.y.qq.com/base/fcgi-bin/u?__=8522515502
      
      final uri = Uri.parse(trimmedInput);
      
      // 检查是否是QQ音乐域名
      if (!uri.host.contains('qq.com')) {
        return null;
      }
      
      String? playlistId;
      
      // 从查询参数中提取
      playlistId = uri.queryParameters['id'];
      
      // 从路径中提取 (形如 /n/ryqq/playlist/8522515502)
      if (playlistId == null) {
        final pathSegments = uri.pathSegments;
        if (pathSegments.isNotEmpty) {
          final lastSegment = pathSegments.last;
          if (RegExp(r'^\d+$').hasMatch(lastSegment)) {
            playlistId = lastSegment;
          }
        }
      }
      
      // 正则表达式兜底
      if (playlistId == null) {
        final idMatch = RegExp(r'[\?&/](?:id=|playlist/)(\d+)').firstMatch(trimmedInput);
        if (idMatch != null) {
          playlistId = idMatch.group(1);
        }
      }
      
      // 验证ID是否为纯数字
      if (playlistId != null && RegExp(r'^\d+$').hasMatch(playlistId)) {
        return playlistId;
      }
      
      return null;
    } catch (e) {
      // URL解析失败，尝试正则表达式兜底
      try {
        final idMatch = RegExp(r'[\?&/](?:id=|playlist/)(\d+)').firstMatch(trimmedInput);
        if (idMatch != null) {
          return idMatch.group(1);
        }
      } catch (_) {
        // 忽略正则表达式错误
      }
      return null;
    }
  }

  /// 显示导入歌单对话框
  static Future<void> show(BuildContext context) async {
    final controller = TextEditingController();
    MusicPlatform selectedPlatform = MusicPlatform.netease;
    Map<String, dynamic>? result;
    if (ThemeManager().isFluentFramework) {
      String? errorText;
      result = await fluent.showDialog<Map<String, dynamic>>(
        context: context,
        builder: (context) => StatefulBuilder(
          builder: (context, setState) => fluent.ContentDialog(
            title: const Text('导入歌单'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('选择平台', style: TextStyle(fontWeight: FontWeight.w600)),
                const SizedBox(height: 8),
                fluent.DropDownButton(
                  title: Text('${selectedPlatform.icon} ${selectedPlatform.name}'),
                  items: MusicPlatform.values.map((platform) {
                    return fluent.MenuFlyoutItem(
                      text: Text('${platform.icon} ${platform.name}'),
                      onPressed: () {
                        setState(() => selectedPlatform = platform);
                      },
                    );
                  }).toList(),
                ),
                const SizedBox(height: 16),
                // 酷狗音乐显示不同的提示
                if (selectedPlatform == MusicPlatform.kugou) ...[
                  const fluent.InfoBar(
                    title: Text('酷狗音乐'),
                    content: Text('点击"下一步"将显示您绑定的酷狗账号中的歌单'),
                    severity: fluent.InfoBarSeverity.info,
                  ),
                ] else ...[
                  const Text('输入歌单信息', style: TextStyle(fontWeight: FontWeight.w600)),
                  const SizedBox(height: 8),
                  Text(
                    selectedPlatform == MusicPlatform.netease
                        ? '支持以下两种输入方式：\n• 直接输入歌单ID，如：19723756\n• 粘贴完整URL，如：https://music.163.com/#/playlist?id=19723756'
                        : '支持以下两种输入方式：\n• 直接输入歌单ID，如：8522515502\n• 粘贴完整URL，如：https://y.qq.com/n/ryqq/playlist/8522515502',
                    style: const TextStyle(fontSize: 12),
                  ),
                  const SizedBox(height: 12),
                  fluent.TextBox(
                    controller: controller,
                    placeholder: '歌单ID或URL',
                    maxLines: 2,
                  ),
                ],
                if (errorText != null) ...[
                  const SizedBox(height: 8),
                  fluent.InfoBar(title: Text(errorText!), severity: fluent.InfoBarSeverity.warning),
                ],
              ],
            ),
            actions: [
              fluent.Button(
                onPressed: () => Navigator.pop(context),
                child: const Text('取消'),
              ),
              fluent.FilledButton(
                onPressed: () {
                  // 酷狗音乐直接进入歌单选择
                  if (selectedPlatform == MusicPlatform.kugou) {
                    Navigator.pop(context, {
                      'platform': selectedPlatform,
                      'isKugou': true,
                    });
                    return;
                  }
                  final input = controller.text.trim();
                  if (input.isEmpty) {
                    setState(() => errorText = '请输入歌单ID或URL');
                    return;
                  }
                  String? playlistId;
                  if (selectedPlatform == MusicPlatform.netease) {
                    playlistId = _parseNeteasePlaylistId(input);
                  } else {
                    playlistId = _parseQQPlaylistId(input);
                  }
                  if (playlistId == null) {
                    setState(() => errorText = '无效的${selectedPlatform.name}歌单ID或URL格式');
                    return;
                  }
                  Navigator.pop(context, {
                    'platform': selectedPlatform,
                    'playlistId': playlistId,
                  });
                },
                child: const Text('下一步'),
              ),
            ],
          ),
        ),
      );
    } else {
      result = await showDialog<Map<String, dynamic>>(
        context: context,
        builder: (context) => StatefulBuilder(
          builder: (context, setState) => AlertDialog(
            title: const Row(
              children: [
                Icon(Icons.cloud_download, size: 24),
                SizedBox(width: 12),
                Text('导入歌单'),
              ],
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('选择平台', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: MusicPlatform.values.map((platform) {
                    final isSelected = selectedPlatform == platform;
                    return ChoiceChip(
                      label: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(platform.icon),
                          const SizedBox(width: 4),
                          Text(platform.name),
                        ],
                      ),
                      selected: isSelected,
                      onSelected: (selected) {
                        if (selected) setState(() => selectedPlatform = platform);
                      },
                    );
                  }).toList(),
                ),
                const SizedBox(height: 16),
                // 酷狗音乐显示不同的提示
                if (selectedPlatform == MusicPlatform.kugou) ...[
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.primaryContainer,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.info_outline, color: Theme.of(context).colorScheme.primary),
                        const SizedBox(width: 12),
                        const Expanded(
                          child: Text('点击"下一步"将显示您绑定的酷狗账号中的歌单'),
                        ),
                      ],
                    ),
                  ),
                ] else ...[
                  const Text('输入歌单信息', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  Text(
                    selectedPlatform == MusicPlatform.netease
                        ? '支持以下两种输入方式：\n• 直接输入歌单ID，如：19723756\n• 粘贴完整URL，如：https://music.163.com/#/playlist?id=19723756'
                        : '支持以下两种输入方式：\n• 直接输入歌单ID，如：8522515502\n• 粘贴完整URL，如：https://y.qq.com/n/ryqq/playlist/8522515502',
                    style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: controller,
                    decoration: const InputDecoration(
                      labelText: '歌单ID或URL',
                      hintText: '例如: 19723756 或完整URL',
                      border: OutlineInputBorder(),
                    ),
                    autofocus: true,
                    maxLines: 2,
                    minLines: 1,
                  ),
                ],
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('取消'),
              ),
              FilledButton(
                onPressed: () {
                  // 酷狗音乐直接进入歌单选择
                  if (selectedPlatform == MusicPlatform.kugou) {
                    Navigator.pop(context, {
                      'platform': selectedPlatform,
                      'isKugou': true,
                    });
                    return;
                  }
                  final input = controller.text.trim();
                  if (input.isEmpty) {
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('请输入歌单ID或URL')));
                    return;
                  }
                  String? playlistId;
                  if (selectedPlatform == MusicPlatform.netease) {
                    playlistId = _parseNeteasePlaylistId(input);
                  } else {
                    playlistId = _parseQQPlaylistId(input);
                  }
                  if (playlistId == null) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('无效的${selectedPlatform.name}歌单ID或URL格式\n请检查输入是否正确'), duration: const Duration(seconds: 3)),
                    );
                    return;
                  }
                  Navigator.pop(context, {
                    'platform': selectedPlatform,
                    'playlistId': playlistId,
                  });
                },
                child: const Text('下一步'),
              ),
            ],
          ),
        ),
      );
    }

    if (result != null && context.mounted) {
      final platform = result['platform'] as MusicPlatform;
      // 酷狗音乐走单独的流程
      if (result['isKugou'] == true) {
        await _showKugouPlaylistsDialog(context);
        return;
      }
      final playlistId = result['playlistId'] as String;
      await _fetchAndImportPlaylist(context, platform, playlistId);
    }
  }

  /// 显示酷狗歌单选择对话框
  static Future<void> _showKugouPlaylistsDialog(BuildContext context) async {
    final kugouService = KugouLoginService();
    
    // 先检查是否已绑定酷狗账号
    final isBound = await kugouService.isKugouBound();
    if (!isBound) {
      if (!context.mounted) return;
      if (ThemeManager().isFluentFramework) {
        await fluent.showDialog(
          context: context,
          builder: (context) => fluent.ContentDialog(
            title: const Text('未绑定酷狗账号'),
            content: const Text('请先在「设置 → 第三方账号」中绑定酷狗账号后再导入歌单。'),
            actions: [
              fluent.FilledButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('确定'),
              ),
            ],
          ),
        );
      } else {
        await showDialog(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('未绑定酷狗账号'),
            content: const Text('请先在「设置 → 第三方账号」中绑定酷狗账号后再导入歌单。'),
            actions: [
              FilledButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('确定'),
              ),
            ],
          ),
        );
      }
      return;
    }

    if (!context.mounted) return;

    // 显示加载中
    if (ThemeManager().isFluentFramework) {
      fluent.showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => const Center(
          child: fluent.Card(
            padding: EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                fluent.ProgressRing(),
                SizedBox(height: 16),
                Text('正在获取酷狗歌单...'),
              ],
            ),
          ),
        ),
      );
    } else {
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => const Center(
          child: Card(
            child: Padding(
              padding: EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircularProgressIndicator(),
                  SizedBox(height: 16),
                  Text('正在获取酷狗歌单...'),
                ],
              ),
            ),
          ),
        ),
      );
    }

    try {
      final playlists = await kugouService.fetchUserPlaylists(pagesize: 50);
      if (!context.mounted) return;
      Navigator.pop(context); // 关闭加载对话框

      if (playlists.isEmpty) {
        if (ThemeManager().isFluentFramework) {
          await fluent.showDialog(
            context: context,
            builder: (context) => fluent.ContentDialog(
              title: const Text('暂无歌单'),
              content: const Text('您的酷狗账号中暂无歌单。'),
              actions: [
                fluent.FilledButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('确定'),
                ),
              ],
            ),
          );
        } else {
          await showDialog(
            context: context,
            builder: (context) => AlertDialog(
              title: const Text('暂无歌单'),
              content: const Text('您的酷狗账号中暂无歌单。'),
              actions: [
                FilledButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('确定'),
                ),
              ],
            ),
          );
        }
        return;
      }

      // 显示歌单选择对话框
      KugouPlaylistInfo? selectedPlaylist;
      if (ThemeManager().isFluentFramework) {
        selectedPlaylist = await fluent.showDialog<KugouPlaylistInfo>(
          context: context,
          builder: (context) => fluent.ContentDialog(
            title: const Text('选择要导入的酷狗歌单'),
            content: SizedBox(
              width: 480,
              height: 400,
              child: ListView.builder(
                itemCount: playlists.length,
                itemBuilder: (context, index) {
                  final playlist = playlists[index];
                  return fluent.ListTile(
                    leading: playlist.pic.isNotEmpty
                        ? ClipRRect(
                            borderRadius: BorderRadius.circular(4),
                            child: Image.network(
                              playlist.pic,
                              width: 48,
                              height: 48,
                              fit: BoxFit.cover,
                              errorBuilder: (_, __, ___) => Container(
                                width: 48,
                                height: 48,
                                color: Colors.grey[300],
                                child: const Icon(fluent.FluentIcons.music_in_collection),
                              ),
                            ),
                          )
                        : Container(
                            width: 48,
                            height: 48,
                            decoration: BoxDecoration(
                              color: Colors.grey[300],
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: const Icon(fluent.FluentIcons.music_in_collection),
                          ),
                    title: Text(playlist.name, maxLines: 1, overflow: TextOverflow.ellipsis),
                    subtitle: Text('${playlist.count} 首歌曲'),
                    onPressed: () => Navigator.pop(context, playlist),
                  );
                },
              ),
            ),
            actions: [
              fluent.Button(
                onPressed: () => Navigator.pop(context),
                child: const Text('取消'),
              ),
            ],
          ),
        );
      } else {
        selectedPlaylist = await showDialog<KugouPlaylistInfo>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('选择要导入的酷狗歌单'),
            content: SizedBox(
              width: double.maxFinite,
              height: 400,
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: playlists.length,
                itemBuilder: (context, index) {
                  final playlist = playlists[index];
                  return ListTile(
                    leading: playlist.pic.isNotEmpty
                        ? ClipRRect(
                            borderRadius: BorderRadius.circular(4),
                            child: Image.network(
                              playlist.pic,
                              width: 48,
                              height: 48,
                              fit: BoxFit.cover,
                              errorBuilder: (_, __, ___) => Container(
                                width: 48,
                                height: 48,
                                color: Colors.grey[300],
                                child: const Icon(Icons.library_music),
                              ),
                            ),
                          )
                        : Container(
                            width: 48,
                            height: 48,
                            decoration: BoxDecoration(
                              color: Colors.grey[300],
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: const Icon(Icons.library_music),
                          ),
                    title: Text(playlist.name, maxLines: 1, overflow: TextOverflow.ellipsis),
                    subtitle: Text('${playlist.count} 首歌曲'),
                    onTap: () => Navigator.pop(context, playlist),
                  );
                },
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('取消'),
              ),
            ],
          ),
        );
      }

      if (selectedPlaylist != null && context.mounted) {
        await _fetchAndImportKugouPlaylist(context, selectedPlaylist);
      }
    } catch (e) {
      if (!context.mounted) return;
      Navigator.pop(context); // 关闭加载对话框

      if (ThemeManager().isFluentFramework) {
        await fluent.showDialog(
          context: context,
          builder: (context) => fluent.ContentDialog(
            title: const Text('获取歌单失败'),
            content: Text('$e'),
            actions: [
              fluent.FilledButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('确定'),
              ),
            ],
          ),
        );
      } else {
        await showDialog(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('获取歌单失败'),
            content: Text('$e'),
            actions: [
              FilledButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('确定'),
              ),
            ],
          ),
        );
      }
    }
  }

  /// 获取并导入酷狗歌单
  static Future<void> _fetchAndImportKugouPlaylist(
    BuildContext context,
    KugouPlaylistInfo kugouPlaylist,
  ) async {
    final kugouService = KugouLoginService();

    // 显示加载对话框
    if (ThemeManager().isFluentFramework) {
      fluent.showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => Center(
          child: fluent.Card(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const fluent.ProgressRing(),
                const SizedBox(height: 16),
                Text('正在获取「${kugouPlaylist.name}」的歌曲...'),
              ],
            ),
          ),
        ),
      );
    } else {
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => Center(
          child: Card(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const CircularProgressIndicator(),
                  const SizedBox(height: 16),
                  Text('正在获取「${kugouPlaylist.name}」的歌曲...'),
                ],
              ),
            ),
          ),
        ),
      );
    }

    try {
      final tracks = await kugouService.fetchPlaylistTracks(kugouPlaylist.globalCollectionId, pagesize: 500);
      if (!context.mounted) return;
      Navigator.pop(context); // 关闭加载对话框

      // 显示导入进度对话框（使用 StatefulBuilder 以便在对话框内更新进度）
      int currentProgress = 0;
      void Function(void Function())? dialogSetState;
      
      if (context.mounted) {
        if (ThemeManager().isFluentFramework) {
          fluent.showDialog(
            context: context,
            barrierDismissible: false,
            builder: (dialogCtx) {
              return fluent.StatefulBuilder(
                builder: (context, setState) {
                  dialogSetState = setState;
                  return Center(
                    child: fluent.Card(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const fluent.ProgressRing(),
                          const SizedBox(height: 16),
                          Text('正在导入\n$currentProgress/${tracks.length}'),
                        ],
                      ),
                    ),
                  );
                },
              );
            },
          );
        } else {
          showDialog(
            context: context,
            barrierDismissible: false,
            builder: (dialogCtx) {
              return StatefulBuilder(
                builder: (context, setState) {
                  dialogSetState = setState;
                  return Center(
                    child: Card(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const CircularProgressIndicator(),
                            const SizedBox(height: 16),
                            Text('正在导入\n$currentProgress/${tracks.length}'),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              );
            },
          );
        }
      }

      // 更新进度对话框内容的辅助函数
      void updateProgress(int progress) {
        if (dialogSetState != null) {
          dialogSetState!(() {
            currentProgress = progress;
          });
        }
      }

      // 为每首歌搜索获取emixsongid
      final universalTracks = <Track>[];
      for (int i = 0; i < tracks.length; i++) {
        final track = tracks[i];
        if (!context.mounted) break;

        // 更新进度（不关闭对话框）
        updateProgress(i + 1);

        String? emixsongid;
        try {
          // 构建搜索关键词：使用"歌曲名 歌手名"格式
          // 如果歌手名存在，使用"歌手名 歌曲名"；否则只使用歌曲名
          final searchKeyword = track.artists.isNotEmpty 
              ? '${track.artists} ${track.name}'
              : track.name;
          
          // 搜索歌曲，只取前3个结果进行验证
          final searchResults = await kugouService.searchKugou(searchKeyword, limit: 3);
          
          if (searchResults.isNotEmpty) {
            // 如果原歌曲有歌手信息，验证第一个结果的歌手是否匹配
            if (track.artists.isNotEmpty) {
              final firstResult = searchResults[0];
              if (_artistsMatch(track.artists, firstResult.singer)) {
                // 歌手匹配，使用第一个结果
                emixsongid = firstResult.emixsongid;
              } else {
                // 歌手不匹配，尝试在结果中找匹配的
                for (final result in searchResults) {
                  if (_artistsMatch(track.artists, result.singer) && result.emixsongid.isNotEmpty) {
                    emixsongid = result.emixsongid;
                    break;
                  }
                }
                // 如果都没匹配到，记录警告但不使用
                if (emixsongid == null) {
                  debugPrint('⚠️ [ImportPlaylistDialog] 未找到歌手匹配的结果: ${track.name} - ${track.artists}');
                }
              }
            } else {
              // 没有歌手信息，直接使用第一个结果
              emixsongid = searchResults[0].emixsongid;
            }
          }
        } catch (e) {
          debugPrint('⚠️ [ImportPlaylistDialog] 搜索歌曲失败: ${track.name} - $e');
          // 搜索失败，继续处理下一首
        }

        // 如果找到了emixsongid，使用它；否则使用hash作为备用
        final trackId = emixsongid ?? track.hash;
        
        // 处理歌曲封面URL
        String trackPicUrl = track.img ?? '';
        if (trackPicUrl.isNotEmpty) {
          trackPicUrl = trackPicUrl
              .replaceAll('http://', 'https://')
              .replaceAll('{size}', '400');  // 替换尺寸占位符
        }
        
        universalTracks.add(Track(
          id: trackId,
          name: track.name,
          artists: track.artists,
          album: track.albumName,
          picUrl: trackPicUrl,
          source: MusicSource.kugou,
        ));
      }

      if (!context.mounted) return;
      Navigator.pop(context); // 关闭进度对话框

      // 处理封面图片URL
      String coverImgUrl = kugouPlaylist.pic;
      
      // 如果歌单封面为空，尝试使用第一首歌曲的封面
      if (coverImgUrl.isEmpty && universalTracks.isNotEmpty) {
        coverImgUrl = universalTracks.first.picUrl;
      }
      
      // 处理URL格式：替换http为https，处理占位符
      if (coverImgUrl.isNotEmpty) {
        coverImgUrl = coverImgUrl
            .replaceAll('http://', 'https://')
            .replaceAll('{size}', '400');  // 替换尺寸占位符
      }

      final universalPlaylist = UniversalPlaylist(
        id: kugouPlaylist.listid,
        name: kugouPlaylist.name,
        coverImgUrl: coverImgUrl,
        creator: '酷狗用户',
        trackCount: universalTracks.length,
        description: kugouPlaylist.intro,
        tracks: universalTracks,
        platform: MusicPlatform.kugou,
      );

      // 显示选择目标歌单对话框
      await _showSelectTargetPlaylistDialog(context, universalPlaylist);
    } catch (e) {
      if (!context.mounted) return;
      Navigator.pop(context); // 关闭加载对话框

      if (ThemeManager().isFluentFramework) {
        await fluent.showDialog(
          context: context,
          builder: (context) => fluent.ContentDialog(
            title: const Text('获取歌曲失败'),
            content: Text('$e'),
            actions: [
              fluent.FilledButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('确定'),
              ),
            ],
          ),
        );
      } else {
        await showDialog(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('获取歌曲失败'),
            content: Text('$e'),
            actions: [
              FilledButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('确定'),
              ),
            ],
          ),
        );
      }
    }
  }

  /// 获取歌单并导入
  static Future<void> _fetchAndImportPlaylist(
      BuildContext context, MusicPlatform platform, String playlistId) async {
    // 显示加载对话框
    if (ThemeManager().isFluentFramework) {
      fluent.showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => WillPopScope(
          onWillPop: () async => false,
          child: Center(
            child: fluent.Card(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const fluent.ProgressRing(),
                  const SizedBox(height: 16),
                  Text('正在获取${platform.name}歌单信息...'),
                ],
              ),
            ),
          ),
        ),
      );
    } else {
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => Center(
          child: Card(
            child: Padding(
              padding: const EdgeInsets.all(24.0),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const CircularProgressIndicator(),
                  const SizedBox(height: 16),
                  Text('正在获取${platform.name}歌单信息...'),
                ],
              ),
            ),
          ),
        ),
      );
    }

    try {
      final baseUrl = UrlService().baseUrl;
      final url = platform == MusicPlatform.netease
          ? '$baseUrl/playlist?id=$playlistId&limit=1000'
          : '$baseUrl/qq/playlist?id=$playlistId&limit=1000';
      
      final response = await http.get(
        Uri.parse(url),
      ).timeout(
        const Duration(seconds: 30),
        onTimeout: () => throw Exception('请求超时'),
      );

      if (!context.mounted) return;
      Navigator.pop(context); // 关闭加载对话框

      if (response.statusCode == 200) {
        final data = json.decode(utf8.decode(response.bodyBytes));

        if (data['status'] == 200 && data['success'] == true) {
          final playlistData = data['data']['playlist'];
          final playlist = UniversalPlaylist.fromJson(playlistData, platform);

          // 显示选择目标歌单对话框
          await _showSelectTargetPlaylistDialog(context, playlist);
        } else {
          throw Exception(data['msg'] ?? '获取歌单失败');
        }
      } else {
        throw Exception('HTTP ${response.statusCode}');
      }
    } catch (e) {
      if (!context.mounted) return;
      Navigator.pop(context); // 关闭加载对话框

      if (ThemeManager().isFluentFramework) {
        await fluent.showDialog(
          context: context,
          builder: (context) => fluent.ContentDialog(
            title: const Text('导入失败'),
            content: Text('获取歌单失败: $e'),
            actions: [
              fluent.FilledButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('确定'),
              ),
            ],
          ),
        );
      } else {
        showDialog(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('导入失败'),
            content: Text('获取歌单失败: $e'),
            actions: [
              FilledButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('确定'),
              ),
            ],
          ),
        );
      }
    }
  }

  /// 显示选择目标歌单对话框
  static Future<void> _showSelectTargetPlaylistDialog(
      BuildContext context, UniversalPlaylist sourcePlaylist) async {
    final playlistService = PlaylistService();

    // 确保已加载歌单列表
    if (playlistService.playlists.isEmpty) {
      await playlistService.loadPlaylists();
    }

    if (!context.mounted) return;

    Playlist? targetPlaylist;
    if (ThemeManager().isFluentFramework) {
      targetPlaylist = await _showFluentSelectTargetPlaylistDialog(context, sourcePlaylist);
    } else {
      targetPlaylist = await showDialog<Playlist>(
        context: context,
        builder: (context) => _SelectTargetPlaylistDialog(
          sourcePlaylist: sourcePlaylist,
        ),
      );
    }

    if (targetPlaylist != null && context.mounted) {
      await _importTracks(context, sourcePlaylist, targetPlaylist);
    }
  }

  /// Fluent UI: 选择目标歌单对话框
  static Future<Playlist?> _showFluentSelectTargetPlaylistDialog(
    BuildContext context,
    UniversalPlaylist sourcePlaylist,
  ) async {
    final playlistService = PlaylistService();
    if (playlistService.playlists.isEmpty) {
      await playlistService.loadPlaylists();
    }
    if (!context.mounted) return null;

    return fluent.showDialog<Playlist>(
      context: context,
      builder: (context) => fluent.ContentDialog(
        title: const Text('选择目标歌单'),
        content: SizedBox(
          width: 520,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              fluent.Card(
                padding: const EdgeInsets.all(12),
                child: Row(
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: Image.network(
                        sourcePlaylist.coverImgUrl,
                        width: 60,
                        height: 60,
                        fit: BoxFit.cover,
                        errorBuilder: (context, error, stackTrace) => const SizedBox(
                          width: 60,
                          height: 60,
                          child: Icon(fluent.FluentIcons.music_in_collection),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('${sourcePlaylist.platform.icon} ${sourcePlaylist.name}',
                              maxLines: 1, overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontWeight: FontWeight.w600)),
                          const SizedBox(height: 2),
                          Text('创建者: ${sourcePlaylist.creator}', style: const TextStyle(fontSize: 12)),
                          Text('歌曲数量: ${sourcePlaylist.tracks.length} 首', style: const TextStyle(fontSize: 12)),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              const Divider(),
              fluent.ListTile(
                leading: const Icon(fluent.FluentIcons.add),
                title: const Text('新建歌单'),
                subtitle: const Text('创建一个新歌单来导入'),
                onPressed: () async {
                  final name = await fluent.showDialog<String>(
                    context: context,
                    builder: (context) {
                      final controller = TextEditingController(text: sourcePlaylist.name);
                      String? err;
                      return fluent.ContentDialog(
                        title: const Text('新建歌单'),
                        content: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            fluent.TextBox(controller: controller, placeholder: '歌单名称', autofocus: true),
                            if (err != null) ...[
                              const SizedBox(height: 8),
                              fluent.InfoBar(title: Text(err!), severity: fluent.InfoBarSeverity.warning),
                            ],
                          ],
                        ),
                        actions: [
                          fluent.Button(
                            onPressed: () => Navigator.pop(context),
                            child: const Text('取消'),
                          ),
                          fluent.FilledButton(
                            onPressed: () {
                              final n = controller.text.trim();
                              if (n.isEmpty) {
                                err = '歌单名称不能为空';
                                (context as Element).markNeedsBuild();
                                return;
                              }
                              Navigator.pop(context, n);
                            },
                            child: const Text('创建'),
                          ),
                        ],
                      );
                    },
                  );
                  if (name != null) {
                    final success = await playlistService.createPlaylist(name);
                    if (success && context.mounted) {
                      await Future.delayed(const Duration(milliseconds: 400));
                      Navigator.pop(
                        context,
                        playlistService.playlists.firstWhere(
                          (p) => p.name == name,
                          orElse: () => playlistService.playlists.last,
                        ),
                      );
                    }
                  }
                },
              ),
              const Divider(),
              SizedBox(
                height: 320,
                child: ListView.builder(
                  itemCount: playlistService.playlists.length,
                  itemBuilder: (context, index) {
                    final p = playlistService.playlists[index];
                    return fluent.ListTile(
                      leading: Icon(p.isDefault ? fluent.FluentIcons.heart : fluent.FluentIcons.music_in_collection),
                      title: Text(p.name),
                      subtitle: Text('${p.trackCount} 首歌曲'),
                      onPressed: () => Navigator.pop(context, p),
                    );
                  },
                ),
              ),
            ],
          ),
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

  /// 导入歌曲到目标歌单
  static Future<void> _importTracks(
    BuildContext context,
    UniversalPlaylist sourcePlaylist,
    Playlist targetPlaylist,
  ) async {
    final playlistService = PlaylistService();

    // 显示导入进度对话框
    if (ThemeManager().isFluentFramework) {
      fluent.showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => WillPopScope(
          onWillPop: () async => false,
          child: Center(
            child: fluent.Card(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const fluent.ProgressRing(),
                  const SizedBox(height: 16),
                  const Text('正在导入歌曲...'),
                  const SizedBox(height: 8),
                  Text('从「${sourcePlaylist.name}」到「${targetPlaylist.name}」', style: const TextStyle(fontSize: 12)),
                  Text('共 ${sourcePlaylist.tracks.length} 首歌曲', style: const TextStyle(fontSize: 12)),
                ],
              ),
            ),
          ),
        ),
      );
    } else {
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => WillPopScope(
          onWillPop: () async => false,
          child: _ImportProgressDialog(
            sourcePlaylist: sourcePlaylist,
            targetPlaylist: targetPlaylist,
          ),
        ),
      );
    }

    try {
      int successCount = 0;
      int failCount = 0;

      for (final track in sourcePlaylist.tracks) {
        try {
          await playlistService.addTrackToPlaylist(
            targetPlaylist.id,
            track,
          );
          successCount++;
        } catch (e) {
          // 如果是重复添加，也算成功
          if (e.toString().contains('已在歌单中')) {
            successCount++;
          } else {
            failCount++;
          }
        }

        // 更新进度
        if (context.mounted) {
          // 这里可以通过状态管理更新进度，简化起见直接继续
        }
      }

      if (!context.mounted) return;
      Navigator.pop(context); // 关闭进度对话框

      final platformKey = sourcePlaylist.platform == MusicPlatform.netease 
          ? 'netease' 
          : sourcePlaylist.platform == MusicPlatform.qq 
              ? 'qq' 
              : 'kugou';
      final playlistId = sourcePlaylist.id.toString();
      final bound = await playlistService.updateImportConfig(
        targetPlaylist.id,
        source: platformKey,
        sourcePlaylistId: playlistId,
      );
      if (!bound) {
        print('⚠️ [ImportPlaylistDialog] 更新导入配置失败 playlist=${targetPlaylist.id}');
      }

      // 显示结果
      if (ThemeManager().isFluentFramework) {
        await fluent.showDialog(
          context: context,
          builder: (context) => fluent.ContentDialog(
            title: const Text('导入完成'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('${sourcePlaylist.platform.icon} 来源: ${sourcePlaylist.platform.name}'),
                const SizedBox(height: 6),
                Text('歌单名称: ${sourcePlaylist.name}'),
                const SizedBox(height: 6),
                Text('目标歌单: ${targetPlaylist.name}'),
                const SizedBox(height: 6),
                Text('成功导入: $successCount 首'),
                if (failCount > 0) Text('导入失败: $failCount 首'),
              ],
            ),
            actions: [
              fluent.FilledButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('确定'),
              ),
            ],
          ),
        );
      } else {
        showDialog(
          context: context,
          builder: (context) => AlertDialog(
            title: const Row(
              children: [
                Icon(Icons.check_circle, color: Colors.green),
                SizedBox(width: 12),
                Text('导入完成'),
              ],
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(sourcePlaylist.platform.icon),
                    const SizedBox(width: 4),
                    Expanded(child: Text('来源: ${sourcePlaylist.platform.name}')),
                  ],
                ),
                const SizedBox(height: 8),
                Text('歌单名称: ${sourcePlaylist.name}'),
                const SizedBox(height: 8),
                Text('目标歌单: ${targetPlaylist.name}'),
                const SizedBox(height: 8),
                Text('成功导入: $successCount 首'),
                if (failCount > 0) Text('导入失败: $failCount 首'),
              ],
            ),
            actions: [
              FilledButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('确定'),
              ),
            ],
          ),
        );
      }
    } catch (e) {
      if (!context.mounted) return;
      Navigator.pop(context); // 关闭进度对话框

      if (ThemeManager().isFluentFramework) {
        await fluent.showDialog(
          context: context,
          builder: (context) => fluent.ContentDialog(
            title: const Text('导入失败'),
            content: Text('导入过程中发生错误: $e'),
            actions: [
              fluent.FilledButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('确定'),
              ),
            ],
          ),
        );
      } else {
        showDialog(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('导入失败'),
            content: Text('导入过程中发生错误: $e'),
            actions: [
              FilledButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('确定'),
              ),
            ],
          ),
        );
      }
    }
  }
}

/// 通用歌单数据模型（支持网易云和QQ音乐）
class UniversalPlaylist {
  final dynamic id;  // 网易云用int，QQ用String
  final String name;
  final String coverImgUrl;
  final String creator;
  final int trackCount;
  final String? description;
  final List<Track> tracks;
  final MusicPlatform platform;

  UniversalPlaylist({
    required this.id,
    required this.name,
    required this.coverImgUrl,
    required this.creator,
    required this.trackCount,
    this.description,
    required this.tracks,
    required this.platform,
  });

  factory UniversalPlaylist.fromJson(
    Map<String, dynamic> json,
    MusicPlatform platform,
  ) {
    final List<dynamic> tracksJson = json['tracks'] ?? [];
    
    // 根据平台设置正确的MusicSource
    final MusicSource source = platform == MusicPlatform.netease
        ? MusicSource.netease
        : platform == MusicPlatform.qq
            ? MusicSource.qq
            : MusicSource.kugou;
    
    final tracks = tracksJson.map((trackJson) {
      return Track(
        // QQ音乐使用songmid，网易云使用id，酷狗使用album_audio_id或hash
        id: platform == MusicPlatform.qq
            ? (trackJson['songmid'] ?? trackJson['id'] ?? '')
            : platform == MusicPlatform.kugou
                ? (trackJson['album_audio_id'] ?? trackJson['hash'] ?? '')
                : (trackJson['id'] ?? 0),
        name: (trackJson['name'] ?? '未知歌曲') as String,
        artists: (trackJson['artists'] ?? '未知艺术家') as String,
        album: (trackJson['album'] ?? '未知专辑') as String,
        picUrl: (trackJson['picUrl'] ?? '') as String,
        source: source,  // 🔥 关键：确保标记正确的来源
      );
    }).toList();

    return UniversalPlaylist(
      id: json['id'],
      name: (json['name'] ?? '未命名歌单') as String,
      coverImgUrl: (json['coverImgUrl'] ?? '') as String,
      creator: (json['creator'] ?? '未知') as String,
      trackCount: json['trackCount'] as int? ?? 0,
      description: json['description'] as String?,
      tracks: tracks,
      platform: platform,
    );
  }
}

/// 选择目标歌单对话框
class _SelectTargetPlaylistDialog extends StatefulWidget {
  final UniversalPlaylist sourcePlaylist;

  const _SelectTargetPlaylistDialog({
    required this.sourcePlaylist,
  });

  @override
  State<_SelectTargetPlaylistDialog> createState() =>
      _SelectTargetPlaylistDialogState();
}

class _SelectTargetPlaylistDialogState
    extends State<_SelectTargetPlaylistDialog> {
  final PlaylistService _playlistService = PlaylistService();

  @override
  void initState() {
    super.initState();
    _playlistService.addListener(_onPlaylistsChanged);
  }

  @override
  void dispose() {
    _playlistService.removeListener(_onPlaylistsChanged);
    super.dispose();
  }

  void _onPlaylistsChanged() {
    if (mounted) {
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    final playlists = _playlistService.playlists;
    final colorScheme = Theme.of(context).colorScheme;

    return AlertDialog(
      title: const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('选择目标歌单'),
          SizedBox(height: 4),
          Text(
            '将歌曲导入到以下歌单',
            style: TextStyle(fontSize: 14, fontWeight: FontWeight.normal),
          ),
        ],
      ),
      content: SizedBox(
        width: double.maxFinite,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // 源歌单信息
            Card(
              color: colorScheme.primaryContainer.withOpacity(0.3),
              child: Padding(
                padding: const EdgeInsets.all(12.0),
                child: Row(
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: Image.network(
                        widget.sourcePlaylist.coverImgUrl,
                        width: 60,
                        height: 60,
                        fit: BoxFit.cover,
                        errorBuilder: (context, error, stackTrace) => Container(
                          width: 60,
                          height: 60,
                          color: colorScheme.surfaceContainerHighest,
                          child: const Icon(Icons.music_note),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Text(widget.sourcePlaylist.platform.icon),
                              const SizedBox(width: 4),
                              Expanded(
                                child: Text(
                                  widget.sourcePlaylist.name,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 16,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '创建者: ${widget.sourcePlaylist.creator}',
                            style: const TextStyle(fontSize: 12),
                          ),
                          Text(
                            '歌曲数量: ${widget.sourcePlaylist.tracks.length} 首',
                            style: const TextStyle(fontSize: 12),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 16),
            const Divider(),
            const SizedBox(height: 8),

            // 新建歌单按钮
            ListTile(
              leading: CircleAvatar(
                backgroundColor: colorScheme.secondaryContainer,
                child: Icon(
                  Icons.add,
                  color: colorScheme.onSecondaryContainer,
                ),
              ),
              title: const Text('新建歌单'),
              subtitle: const Text('创建一个新歌单来导入'),
              onTap: () async {
                final newPlaylist = await _showCreatePlaylistDialog();
                if (newPlaylist != null && mounted) {
                  Navigator.pop(context, newPlaylist);
                }
              },
            ),

            const Divider(),

            // 歌单列表
            Flexible(
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: playlists.length,
                itemBuilder: (context, index) {
                  final playlist = playlists[index];
                  return ListTile(
                    leading: CircleAvatar(
                      backgroundColor: playlist.isDefault
                          ? colorScheme.primaryContainer
                          : colorScheme.secondaryContainer,
                      child: Icon(
                        playlist.isDefault
                            ? Icons.favorite
                            : Icons.queue_music,
                        color: playlist.isDefault
                            ? colorScheme.onPrimaryContainer
                            : colorScheme.onSecondaryContainer,
                      ),
                    ),
                    title: Row(
                      children: [
                        Expanded(
                          child: Text(
                            playlist.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (playlist.isDefault)
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 2),
                            decoration: BoxDecoration(
                              color: colorScheme.primaryContainer,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Text(
                              '默认',
                              style: TextStyle(
                                color: colorScheme.onPrimaryContainer,
                                fontSize: 12,
                              ),
                            ),
                          ),
                      ],
                    ),
                    subtitle: Text('${playlist.trackCount} 首歌曲'),
                    onTap: () => Navigator.pop(context, playlist),
                  );
                },
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('取消'),
        ),
      ],
    );
  }

  /// 显示创建歌单对话框
  Future<Playlist?> _showCreatePlaylistDialog() async {
    final controller = TextEditingController(
      text: widget.sourcePlaylist.name, // 默认使用源歌单名称
    );

    final name = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('新建歌单'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(
            labelText: '歌单名称',
            hintText: '请输入歌单名称',
          ),
          autofocus: true,
          maxLength: 30,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () {
              final name = controller.text.trim();
              if (name.isEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('歌单名称不能为空')),
                );
                return;
              }
              Navigator.pop(context, name);
            },
            child: const Text('创建'),
          ),
        ],
      ),
    );

    if (name != null) {
      final success = await _playlistService.createPlaylist(name);
      if (success) {
        // 等待列表更新
        await Future.delayed(const Duration(milliseconds: 500));
        // 返回新创建的歌单
        final newPlaylist = _playlistService.playlists.firstWhere(
          (p) => p.name == name,
          orElse: () => _playlistService.playlists.last,
        );
        return newPlaylist;
      }
    }
    return null;
  }
}

/// 导入进度对话框
class _ImportProgressDialog extends StatelessWidget {
  final UniversalPlaylist sourcePlaylist;
  final Playlist targetPlaylist;

  const _ImportProgressDialog({
    required this.sourcePlaylist,
    required this.targetPlaylist,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const CircularProgressIndicator(),
              const SizedBox(height: 16),
              Text(
                '正在导入歌曲...',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 8),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(sourcePlaylist.platform.icon),
                  const SizedBox(width: 4),
                  Text(
                    '从「${sourcePlaylist.name}」',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
              Text(
                '导入到「${targetPlaylist.name}」',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 8),
              Text(
                '共 ${sourcePlaylist.tracks.length} 首歌曲',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.primary,
                      fontWeight: FontWeight.bold,
                    ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 字符串相似度计算（Levenshtein距离）
int _levenshteinDistance(String s1, String s2) {
  if (s1.isEmpty) return s2.length;
  if (s2.isEmpty) return s1.length;

  final matrix = List.generate(
    s1.length + 1,
    (i) => List.generate(s2.length + 1, (j) => 0),
  );

  for (int i = 0; i <= s1.length; i++) {
    matrix[i][0] = i;
  }
  for (int j = 0; j <= s2.length; j++) {
    matrix[0][j] = j;
  }

  for (int i = 1; i <= s1.length; i++) {
    for (int j = 1; j <= s2.length; j++) {
      final cost = s1[i - 1].toLowerCase() == s2[j - 1].toLowerCase() ? 0 : 1;
      matrix[i][j] = [
        matrix[i - 1][j] + 1,      // deletion
        matrix[i][j - 1] + 1,      // insertion
        matrix[i - 1][j - 1] + cost, // substitution
      ].reduce((a, b) => a < b ? a : b);
    }
  }

  return matrix[s1.length][s2.length];
}

/// 计算字符串相似度（0-1之间，1表示完全相同）
double _similarity(String s1, String s2) {
  if (s1.isEmpty && s2.isEmpty) return 1.0;
  if (s1.isEmpty || s2.isEmpty) return 0.0;
  
  final distance = _levenshteinDistance(s1, s2);
  final maxLength = s1.length > s2.length ? s1.length : s2.length;
  return 1.0 - (distance / maxLength);
}

/// 检查艺术家是否完全匹配（忽略大小写和空格）
bool _artistsMatch(String trackArtists, String resultSinger) {
  if (trackArtists.isEmpty && resultSinger.isEmpty) return true;
  if (trackArtists.isEmpty || resultSinger.isEmpty) return false;

  // 标准化：转换为小写，移除空格
  final normalize = (String s) => s.toLowerCase().replaceAll(RegExp(r'\s+'), '');
  
  // 分割艺术家（支持多种分隔符）
  final trackArtistsList = trackArtists.split(RegExp(r'[/、,，\s]+'))
      .map((s) => normalize(s.trim()))
      .where((s) => s.isNotEmpty)
      .toList();
  final resultArtistsList = resultSinger.split(RegExp(r'[/、,，\s]+'))
      .map((s) => normalize(s.trim()))
      .where((s) => s.isNotEmpty)
      .toList();

  if (trackArtistsList.isEmpty || resultArtistsList.isEmpty) return false;

  // 检查是否所有trackArtists都在resultArtistsList中（或反之）
  // 允许部分匹配，但至少要有主要艺术家匹配
  bool hasMatch = false;
  for (final trackArtist in trackArtistsList) {
    for (final resultArtist in resultArtistsList) {
      // 完全匹配或包含关系
      if (trackArtist == resultArtist || 
          trackArtist.contains(resultArtist) || 
          resultArtist.contains(trackArtist)) {
        hasMatch = true;
        break;
      }
    }
    if (hasMatch) break;
  }

  return hasMatch;
}

/// 找到最匹配的搜索结果
/// 要求：至少确保歌手完全一致（或至少有一个主要歌手匹配）
KugouSearchResult? _findBestMatch(String trackName, String trackArtists, List<KugouSearchResult> results) {
  if (results.isEmpty) return null;

  double bestScore = 0.0;
  KugouSearchResult? bestMatch;

  for (final result in results) {
    // 首先检查艺术家是否匹配（必需条件）
    final artistsMatch = _artistsMatch(trackArtists, result.singer);
    
    // 如果艺术家不匹配，跳过这个结果（除非原歌曲没有艺术家信息）
    if (trackArtists.isNotEmpty && !artistsMatch) {
      continue; // 跳过不匹配的结果
    }
    
    // 计算歌曲名相似度
    final nameSimilarity = _similarity(trackName, result.name);
    
    // 计算艺术家相似度（如果艺术家信息存在）
    double artistSimilarity = 0.0;
    if (trackArtists.isNotEmpty && result.singer.isNotEmpty) {
      // 尝试匹配艺术家（支持多个艺术家，用/或、分隔）
      final trackArtistsList = trackArtists.split(RegExp(r'[/、,，]')).map((s) => s.trim()).toList();
      final resultArtistsList = result.singer.split(RegExp(r'[/、,，]')).map((s) => s.trim()).toList();
      
      // 计算最高艺术家匹配度
      for (final trackArtist in trackArtistsList) {
        for (final resultArtist in resultArtistsList) {
          final sim = _similarity(trackArtist, resultArtist);
          if (sim > artistSimilarity) {
            artistSimilarity = sim;
          }
        }
      }
    } else if (trackArtists.isEmpty && result.singer.isEmpty) {
      // 都没有艺术家信息，给一个基础分
      artistSimilarity = 0.5;
    } else if (artistsMatch) {
      // 艺术家已匹配，给高分
      artistSimilarity = 1.0;
    }

    // 综合评分：歌曲名权重70%，艺术家权重30%
    final score = nameSimilarity * 0.7 + artistSimilarity * 0.3;

    if (score > bestScore) {
      bestScore = score;
      bestMatch = result;
    }
  }

  // 如果最佳匹配的相似度低于0.3，认为匹配失败
  // 或者如果原歌曲有艺术家信息但最佳匹配没有匹配到艺术家，也认为失败
  if (bestScore < 0.3) {
    return null;
  }
  
  // 如果原歌曲有艺术家信息，必须确保艺术家匹配
  if (trackArtists.isNotEmpty && bestMatch != null) {
    if (!_artistsMatch(trackArtists, bestMatch.singer)) {
      return null; // 艺术家不匹配，返回null
    }
  }

  return bestMatch;
}
