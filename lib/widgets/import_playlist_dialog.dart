import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:fluent_ui/fluent_ui.dart' as fluent;
import 'package:http/http.dart' as http;
import '../services/url_service.dart';
import '../services/playlist_service.dart';
import '../services/auth_service.dart';
import '../services/kugou_login_service.dart';
import '../services/netease_login_service.dart';
import '../models/playlist.dart';
import '../models/track.dart';
import '../models/music_platform.dart';
import '../models/universal_playlist.dart';
import '../utils/theme_manager.dart';

part 'import_playlist_dialog_dialogs.dart';
part 'import_playlist_dialog_utils.dart';

/// 从网易云/QQ音乐导入歌单对话框
class ImportPlaylistDialog {

  // ==================== 公共辅助方法 ====================

  /// 显示统一的提示对话框（自动适配三平台 UI）
  static Future<void> _showAlertDialog(
    BuildContext context, {
    required String title,
    required String content,
    String confirmText = '确定',
  }) async {
    if (ThemeManager().isFluentFramework) {
      await fluent.showDialog(
        context: context,
        builder: (context) => fluent.ContentDialog(
          title: Text(title),
          content: Text(content),
          actions: [
            fluent.FilledButton(
              onPressed: () => Navigator.pop(context),
              child: Text(confirmText),
            ),
          ],
        ),
      );
    } else if (ThemeManager().isCupertinoFramework) {
      await showCupertinoDialog(
        context: context,
        builder: (context) => CupertinoAlertDialog(
          title: Text(title),
          content: Text(content),
          actions: [
            CupertinoDialogAction(
              onPressed: () => Navigator.pop(context),
              child: Text(confirmText),
            ),
          ],
        ),
      );
    } else {
      await showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(title),
          content: Text(content),
          actions: [
            FilledButton(
              onPressed: () => Navigator.pop(context),
              child: Text(confirmText),
            ),
          ],
        ),
      );
    }
  }

  /// 显示统一的加载中对话框（自动适配三平台 UI）
  static void _showLoadingDialog(BuildContext context, String message) {
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
                Text(message),
              ],
            ),
          ),
        ),
      );
    } else if (ThemeManager().isCupertinoFramework) {
      showCupertinoDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => Center(
          child: Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: CupertinoColors.systemBackground.resolveFrom(context),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const CupertinoActivityIndicator(radius: 16),
                const SizedBox(height: 16),
                Text(
                  message,
                  style: TextStyle(
                    fontSize: 14,
                    color: CupertinoColors.label.resolveFrom(context),
                    decoration: TextDecoration.none,
                  ),
                ),
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
                  Text(message),
                ],
              ),
            ),
          ),
        ),
      );
    }
  }

  /// 构建歌单封面 Widget（自动适配三平台 UI）
  static Widget _buildPlaylistCover(String? coverUrl, {double size = 48}) {
    final hasValidUrl = coverUrl != null && coverUrl.isNotEmpty;
    
    if (ThemeManager().isFluentFramework) {
      if (hasValidUrl) {
        return ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: Image.network(
            coverUrl,
            width: size,
            height: size,
            fit: BoxFit.cover,
            errorBuilder: (_, __, ___) => Container(
              width: size,
              height: size,
              color: Colors.grey[300],
              child: const Icon(fluent.FluentIcons.music_in_collection),
            ),
          ),
        );
      }
      return Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: Colors.grey[300],
          borderRadius: BorderRadius.circular(4),
        ),
        child: const Icon(fluent.FluentIcons.music_in_collection),
      );
    } else if (ThemeManager().isCupertinoFramework) {
      if (hasValidUrl) {
        return ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: Image.network(
            coverUrl,
            width: size,
            height: size,
            fit: BoxFit.cover,
            errorBuilder: (_, __, ___) => Container(
              width: size,
              height: size,
              color: CupertinoColors.systemGrey5,
              child: const Icon(Icons.music_note, color: CupertinoColors.systemGrey),
            ),
          ),
        );
      }
      return Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: CupertinoColors.systemGrey5,
          borderRadius: BorderRadius.circular(6),
        ),
        child: const Icon(Icons.music_note, color: CupertinoColors.systemGrey),
      );
    } else {
      if (hasValidUrl) {
        return ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: Image.network(
            coverUrl,
            width: size,
            height: size,
            fit: BoxFit.cover,
            errorBuilder: (_, __, ___) => Container(
              width: size,
              height: size,
              color: Colors.grey[300],
              child: const Icon(Icons.library_music),
            ),
          ),
        );
      }
      return Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: Colors.grey[300],
          borderRadius: BorderRadius.circular(4),
        ),
        child: const Icon(Icons.library_music),
      );
    }
  }

  /// 构建 Cupertino 风格的"收藏"标签
  static Widget _buildSubscribedBadge() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: CupertinoColors.systemOrange.withOpacity(0.1),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: CupertinoColors.systemOrange.withOpacity(0.3)),
      ),
      child: const Text(
        '收藏',
        style: TextStyle(
          fontSize: 10,
          color: CupertinoColors.systemOrange,
        ),
      ),
    );
  }

  // ==================== 原有方法 ====================

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

  /// 解析酷我音乐歌单URL，提取歌单ID
  /// 支持格式：
  /// - 纯数字ID：3567349593
  /// - 分享链接：https://m.kuwo.cn/newh5app/playlist_detail/3567349593?t=plantform&from=ar
  /// - PC端链接：https://www.kuwo.cn/playlist_detail/3567349593
  static String? _parseKuwoPlaylistId(String input) {
    final trimmedInput = input.trim();
    
    // 如果输入的是纯数字ID，直接返回
    if (RegExp(r'^\d+$').hasMatch(trimmedInput)) {
      return trimmedInput;
    }
    
    // 尝试从URL中解析ID
    try {
      final uri = Uri.parse(trimmedInput);
      
      // 检查是否是酷我音乐域名
      if (!uri.host.contains('kuwo.cn')) {
        return null;
      }
      
      String? playlistId;
      
      // 从路径中提取 (形如 /playlist_detail/3567349593 或 /newh5app/playlist_detail/3567349593)
      final pathSegments = uri.pathSegments;
      for (int i = 0; i < pathSegments.length; i++) {
        if (pathSegments[i] == 'playlist_detail' && i + 1 < pathSegments.length) {
          final nextSegment = pathSegments[i + 1];
          if (RegExp(r'^\d+$').hasMatch(nextSegment)) {
            playlistId = nextSegment;
            break;
          }
        }
      }
      
      // 正则表达式兜底
      if (playlistId == null) {
        final idMatch = RegExp(r'playlist_detail[/](\d+)').firstMatch(trimmedInput);
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
        final idMatch = RegExp(r'playlist_detail[/](\d+)').firstMatch(trimmedInput);
        if (idMatch != null) {
          return idMatch.group(1);
        }
      } catch (_) {
        // 忽略正则表达式错误
      }
      return null;
    }
  }

  /// 解析Apple Music歌单URL，提取歌单ID
  /// 支持格式：
  /// - 歌单ID：pl.u-55D6ZJ3iDyp2AD
  /// - 分享链接：https://music.apple.com/cn/playlist/%E5%95%8A%E8%BF%99/pl.u-55D6ZJ3iDyp2AD
  static String? _parseApplePlaylistId(String input) {
    final trimmedInput = input.trim();
    
    // 如果输入的是歌单ID格式 (pl.u-xxx 或 pl.xxx)，直接返回
    if (RegExp(r'^pl\.[a-zA-Z0-9\-]+$').hasMatch(trimmedInput)) {
      return trimmedInput;
    }
    
    // 尝试从URL中解析ID
    try {
      final uri = Uri.parse(trimmedInput);
      
      // 检查是否是Apple Music域名
      if (!uri.host.contains('music.apple.com')) {
        return null;
      }
      
      String? playlistId;
      
      // 从路径中提取 (形如 /cn/playlist/xxx/pl.u-55D6ZJ3iDyp2AD)
      final pathSegments = uri.pathSegments;
      for (final segment in pathSegments) {
        if (segment.startsWith('pl.')) {
          playlistId = segment;
          break;
        }
      }
      
      // 正则表达式兜底
      if (playlistId == null) {
        final idMatch = RegExp(r'(pl\.[a-zA-Z0-9\-]+)').firstMatch(trimmedInput);
        if (idMatch != null) {
          playlistId = idMatch.group(1);
        }
      }
      
      // 验证ID格式
      if (playlistId != null && RegExp(r'^pl\.[a-zA-Z0-9\-]+$').hasMatch(playlistId)) {
        return playlistId;
      }
      
      return null;
    } catch (e) {
      // URL解析失败，尝试正则表达式兜底
      try {
        final idMatch = RegExp(r'(pl\.[a-zA-Z0-9\-]+)').firstMatch(trimmedInput);
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

  /// 获取输入提示文本
  static String _getInputHintText(MusicPlatform platform) {
    switch (platform) {
      case MusicPlatform.netease:
        return '支持以下两种输入方式：\n• 直接输入歌单ID，如：19723756\n• 粘贴完整URL，如：https://music.163.com/#/playlist?id=19723756';
      case MusicPlatform.qq:
        return '支持以下两种输入方式：\n• 直接输入歌单ID，如：8522515502\n• 粘贴完整URL，如：https://y.qq.com/n/ryqq/playlist/8522515502';
      case MusicPlatform.kuwo:
        return '支持以下两种输入方式：\n• 直接输入歌单ID，如：3567349593\n• 粘贴分享链接，如：https://m.kuwo.cn/newh5app/playlist_detail/3567349593';
      case MusicPlatform.kugou:
        return '';
      case MusicPlatform.apple:
        return '支持以下两种输入方式：\n• 直接输入歌单ID，如：pl.u-55D6ZJ3iDyp2AD\n• 粘贴分享链接，如：https://music.apple.com/cn/playlist/xxx/pl.u-55D6ZJ3iDyp2AD';
    }
  }

  /// 显示导入歌单对话框
  static Future<void> show(BuildContext context) async {
    final controller = TextEditingController();
    MusicPlatform selectedPlatform = MusicPlatform.netease;
    // 网易云导入方式: 'account' 从账号导入, 'url' 从URL/ID导入
    String neteaseImportMode = 'account';
    Map<String, dynamic>? result;
    
    // Fluent 风格 (Windows 桌面优先检查)
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
                        setState(() {
                          selectedPlatform = platform;
                          controller.clear();
                          errorText = null;
                        });
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
                ] else if (selectedPlatform == MusicPlatform.netease) ...[
                  // 网易云音乐：支持两种导入方式
                  const Text('导入方式', style: TextStyle(fontWeight: FontWeight.w600)),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      fluent.RadioButton(
                        checked: neteaseImportMode == 'account',
                        onChanged: (v) => setState(() {
                          neteaseImportMode = 'account';
                          controller.clear();
                          errorText = null;
                        }),
                      ),
                      const SizedBox(width: 8),
                      const Text('从绑定账号导入'),
                      const SizedBox(width: 24),
                      fluent.RadioButton(
                        checked: neteaseImportMode == 'url',
                        onChanged: (v) => setState(() {
                          neteaseImportMode = 'url';
                          errorText = null;
                        }),
                      ),
                      const SizedBox(width: 8),
                      const Text('输入歌单ID/URL'),
                    ],
                  ),
                  const SizedBox(height: 12),
                  if (neteaseImportMode == 'account') ...[
                    const fluent.InfoBar(
                      title: Text('从账号导入'),
                      content: Text('点击"下一步"将显示您绑定的网易云账号中的歌单'),
                      severity: fluent.InfoBarSeverity.info,
                    ),
                  ] else ...[
                    Text(
                      _getInputHintText(selectedPlatform),
                      style: const TextStyle(fontSize: 12),
                    ),
                    const SizedBox(height: 12),
                    fluent.TextBox(
                      controller: controller,
                      placeholder: '歌单ID或URL',
                      maxLines: 2,
                    ),
                  ],
                ] else ...[
                  const Text('输入歌单信息', style: TextStyle(fontWeight: FontWeight.w600)),
                  const SizedBox(height: 8),
                  Text(
                    _getInputHintText(selectedPlatform),
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
                  // 网易云从账号导入
                  if (selectedPlatform == MusicPlatform.netease && neteaseImportMode == 'account') {
                    Navigator.pop(context, {
                      'platform': selectedPlatform,
                      'isNeteaseAccount': true,
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
                  } else if (selectedPlatform == MusicPlatform.qq) {
                    playlistId = _parseQQPlaylistId(input);
                  } else if (selectedPlatform == MusicPlatform.kuwo) {
                    playlistId = _parseKuwoPlaylistId(input);
                  } else if (selectedPlatform == MusicPlatform.apple) {
                    playlistId = _parseApplePlaylistId(input);
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
    }
    // Cupertino 风格 (iOS/Android 移动端)
    else if (ThemeManager().isCupertinoFramework) {
      result = await _showCupertinoImportDialogImpl(context, controller, selectedPlatform, neteaseImportMode);
    }
    // Material 风格 (默认)
    else {
      result = await showDialog<Map<String, dynamic>>(
        context: context,
        builder: (context) => StatefulBuilder(
          builder: (context, setState) => AlertDialog(
            scrollable: true,
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
                        if (selected) {
                          setState(() {
                            selectedPlatform = platform;
                            controller.clear();
                          });
                        }
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
                ] else if (selectedPlatform == MusicPlatform.netease) ...[
                  // 网易云音乐：支持两种导入方式
                  const Text('导入方式', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Radio<String>(
                        value: 'account',
                        groupValue: neteaseImportMode,
                        onChanged: (v) => setState(() {
                          neteaseImportMode = v!;
                          controller.clear();
                        }),
                      ),
                      const Text('从绑定账号导入'),
                      const SizedBox(width: 16),
                      Radio<String>(
                        value: 'url',
                        groupValue: neteaseImportMode,
                        onChanged: (v) => setState(() => neteaseImportMode = v!),
                      ),
                      const Text('输入歌单ID/URL'),
                    ],
                  ),
                  const SizedBox(height: 12),
                  if (neteaseImportMode == 'account') ...[
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
                            child: Text('点击"下一步"将显示您绑定的网易云账号中的歌单'),
                          ),
                        ],
                      ),
                    ),
                  ] else ...[
                    Text(
                      _getInputHintText(selectedPlatform),
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
                ] else ...[
                  const Text('输入歌单信息', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  Text(
                    _getInputHintText(selectedPlatform),
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
                  // 网易云从账号导入
                  if (selectedPlatform == MusicPlatform.netease && neteaseImportMode == 'account') {
                    Navigator.pop(context, {
                      'platform': selectedPlatform,
                      'isNeteaseAccount': true,
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
                  } else if (selectedPlatform == MusicPlatform.qq) {
                    playlistId = _parseQQPlaylistId(input);
                  } else if (selectedPlatform == MusicPlatform.kuwo) {
                    playlistId = _parseKuwoPlaylistId(input);
                  } else if (selectedPlatform == MusicPlatform.apple) {
                    playlistId = _parseApplePlaylistId(input);
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
      // 网易云从账号导入
      if (result['isNeteaseAccount'] == true) {
        await _showNeteasePlaylistsDialog(context);
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
      } else if (ThemeManager().isCupertinoFramework) {
        await showCupertinoDialog(
          context: context,
          builder: (context) => CupertinoAlertDialog(
            title: const Text('未绑定酷狗账号'),
            content: const Text('请先在「设置 → 第三方账号」中绑定酷狗账号后再导入歌单。'),
            actions: [
              CupertinoDialogAction(
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
    } else if (ThemeManager().isCupertinoFramework) {
      showCupertinoDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => const Center(
          child: CupertinoActivityIndicator(radius: 16),
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
        } else if (ThemeManager().isCupertinoFramework) {
          await showCupertinoDialog(
            context: context,
            builder: (context) => CupertinoAlertDialog(
              title: const Text('暂无歌单'),
              content: const Text('您的酷狗账号中暂无歌单。'),
              actions: [
                CupertinoDialogAction(
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
      } else if (ThemeManager().isCupertinoFramework) {
        selectedPlaylist = await showCupertinoModalPopup<KugouPlaylistInfo>(
          context: context,
          builder: (context) {
            final isDark = CupertinoTheme.brightnessOf(context) == Brightness.dark;
            return Material(
              type: MaterialType.transparency,
              child: Container(
                height: MediaQuery.of(context).size.height * 0.7,
                decoration: BoxDecoration(
                  color: isDark ? const Color(0xFF1C1C1E) : CupertinoColors.systemBackground,
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
                ),
                child: SafeArea(
                  top: false,
                  child: Column(
                    children: [
                      // 顶部拖动条
                      Container(
                        margin: const EdgeInsets.only(top: 8),
                        width: 36,
                        height: 5,
                        decoration: BoxDecoration(
                          color: CupertinoColors.systemGrey3,
                          borderRadius: BorderRadius.circular(2.5),
                        ),
                      ),
                      // 标题栏
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            CupertinoButton(
                              padding: EdgeInsets.zero,
                              onPressed: () => Navigator.pop(context),
                              child: const Text('取消'),
                            ),
                            Text(
                              '选择酷狗歌单',
                              style: TextStyle(
                                fontSize: 17,
                                fontWeight: FontWeight.w600,
                                color: isDark ? CupertinoColors.white : CupertinoColors.black,
                              ),
                            ),
                            const SizedBox(width: 60), // 占位，保持标题居中
                          ],
                        ),
                      ),
                      const Divider(height: 1),
                      // 歌单列表
                      Expanded(
                        child: ListView.builder(
                          padding: EdgeInsets.zero,
                          itemCount: playlists.length,
                          itemBuilder: (context, index) {
                            final playlist = playlists[index];
                            return Material(
                              color: Colors.transparent,
                              child: InkWell(
                                onTap: () => Navigator.pop(context, playlist),
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                                  child: Row(
                                    children: [
                                      ClipRRect(
                                        borderRadius: BorderRadius.circular(6),
                                        child: playlist.pic.isNotEmpty
                                            ? Image.network(
                                                playlist.pic,
                                                width: 50,
                                                height: 50,
                                                fit: BoxFit.cover,
                                                errorBuilder: (_, __, ___) => Container(
                                                  width: 50,
                                                  height: 50,
                                                  color: CupertinoColors.systemGrey5,
                                                  child: const Icon(Icons.music_note, color: CupertinoColors.systemGrey),
                                                ),
                                              )
                                            : Container(
                                                width: 50,
                                                height: 50,
                                                color: CupertinoColors.systemGrey5,
                                                child: const Icon(Icons.music_note, color: CupertinoColors.systemGrey),
                                              ),
                                      ),
                                      const SizedBox(width: 12),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              playlist.name,
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: TextStyle(
                                                fontSize: 16,
                                                color: isDark ? CupertinoColors.white : CupertinoColors.black,
                                              ),
                                            ),
                                            const SizedBox(height: 4),
                                            Text(
                                              '${playlist.count} 首歌曲',
                                              style: const TextStyle(
                                                fontSize: 14,
                                                color: CupertinoColors.systemGrey,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                      const Icon(CupertinoIcons.chevron_right, color: CupertinoColors.systemGrey3, size: 20),
                                    ],
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
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

      await _showAlertDialog(
        context,
        title: '获取歌单失败',
        content: '$e',
      );
    }
  }

  /// 显示网易云歌单选择对话框
  static Future<void> _showNeteasePlaylistsDialog(BuildContext context) async {
    final neteaseService = NeteaseLoginService();
    
    // 先检查是否已绑定网易云账号
    final isBound = await neteaseService.isNeteaseBound();
    if (!isBound) {
      if (!context.mounted) return;
      await _showAlertDialog(
        context,
        title: '未绑定网易云账号',
        content: '请先在「设置 → 第三方账号」中绑定网易云账号后再导入歌单。',
      );
      return;
    }

    if (!context.mounted) return;

    // 显示加载中
    _showLoadingDialog(context, '正在获取网易云歌单...');

    try {
      final playlists = await neteaseService.fetchUserPlaylists(limit: 100);
      if (!context.mounted) return;
      Navigator.pop(context); // 关闭加载对话框

      if (playlists.isEmpty) {
        await _showAlertDialog(
          context,
          title: '暂无歌单',
          content: '您的网易云账号中暂无歌单。',
        );
        return;
      }

      // 显示歌单选择对话框
      NeteasePlaylistInfo? selectedPlaylist;
      if (ThemeManager().isFluentFramework) {
        selectedPlaylist = await fluent.showDialog<NeteasePlaylistInfo>(
          context: context,
          builder: (context) => fluent.ContentDialog(
            title: const Text('选择要导入的网易云歌单'),
            content: SizedBox(
              width: 480,
              height: 400,
              child: ListView.builder(
                itemCount: playlists.length,
                itemBuilder: (context, index) {
                  final playlist = playlists[index];
                  return fluent.ListTile(
                    leading: playlist.coverImgUrl.isNotEmpty
                        ? ClipRRect(
                            borderRadius: BorderRadius.circular(4),
                            child: Image.network(
                              playlist.coverImgUrl,
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
                    subtitle: Text(
                      '${playlist.trackCount} 首歌曲${playlist.subscribed ? ' · 收藏' : ''}',
                      style: TextStyle(
                        color: playlist.subscribed ? Colors.orange : null,
                      ),
                    ),
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
      } else if (ThemeManager().isCupertinoFramework) {
        selectedPlaylist = await showCupertinoModalPopup<NeteasePlaylistInfo>(
          context: context,
          builder: (context) {
            final isDark = CupertinoTheme.brightnessOf(context) == Brightness.dark;
            return Material(
              type: MaterialType.transparency,
              child: Container(
                height: MediaQuery.of(context).size.height * 0.7,
                decoration: BoxDecoration(
                  color: isDark ? const Color(0xFF1C1C1E) : CupertinoColors.systemBackground,
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
                ),
                child: SafeArea(
                  top: false,
                  child: Column(
                    children: [
                      // 顶部拖动条
                      Container(
                        margin: const EdgeInsets.only(top: 8),
                        width: 36,
                        height: 5,
                        decoration: BoxDecoration(
                          color: CupertinoColors.systemGrey3,
                          borderRadius: BorderRadius.circular(2.5),
                        ),
                      ),
                      // 标题栏
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            CupertinoButton(
                              padding: EdgeInsets.zero,
                              onPressed: () => Navigator.pop(context),
                              child: const Text('取消'),
                            ),
                            Text(
                              '选择网易云歌单',
                              style: TextStyle(
                                fontSize: 17,
                                fontWeight: FontWeight.w600,
                                color: isDark ? CupertinoColors.white : CupertinoColors.black,
                              ),
                            ),
                            const SizedBox(width: 60), // 占位
                          ],
                        ),
                      ),
                      const Divider(height: 1),
                      // 歌单列表
                      Expanded(
                        child: ListView.builder(
                          padding: EdgeInsets.zero,
                          itemCount: playlists.length,
                          itemBuilder: (context, index) {
                            final playlist = playlists[index];
                            return Material(
                              color: Colors.transparent,
                              child: InkWell(
                                onTap: () => Navigator.pop(context, playlist),
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                                  child: Row(
                                    children: [
                                      _buildPlaylistCover(playlist.coverImgUrl, size: 50),
                                      const SizedBox(width: 12),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              playlist.name,
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: TextStyle(
                                                fontSize: 16,
                                                color: isDark ? CupertinoColors.white : CupertinoColors.black,
                                              ),
                                            ),
                                            const SizedBox(height: 4),
                                            Row(
                                              children: [
                                                Text(
                                                  '${playlist.trackCount} 首歌曲',
                                                  style: const TextStyle(
                                                    fontSize: 14,
                                                    color: CupertinoColors.systemGrey,
                                                  ),
                                                ),
                                                if (playlist.subscribed) ...[
                                                  const SizedBox(width: 8),
                                                  _buildSubscribedBadge(),
                                                ],
                                              ],
                                            ),
                                          ],
                                        ),
                                      ),
                                      const Icon(CupertinoIcons.chevron_right, color: CupertinoColors.systemGrey3, size: 20),
                                    ],
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      } else {
        selectedPlaylist = await showDialog<NeteasePlaylistInfo>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('选择要导入的网易云歌单'),
            content: SizedBox(
              width: double.maxFinite,
              height: 400,
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: playlists.length,
                itemBuilder: (context, index) {
                  final playlist = playlists[index];
                  return ListTile(
                    leading: playlist.coverImgUrl.isNotEmpty
                        ? ClipRRect(
                            borderRadius: BorderRadius.circular(4),
                            child: Image.network(
                              playlist.coverImgUrl,
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
                    subtitle: Text(
                      '${playlist.trackCount} 首歌曲${playlist.subscribed ? ' · 收藏' : ''}',
                      style: TextStyle(
                        color: playlist.subscribed ? Colors.orange : null,
                      ),
                    ),
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
        // 使用现有的 _fetchAndImportPlaylist 方法，传入歌单ID
        await _fetchAndImportPlaylist(context, MusicPlatform.netease, selectedPlaylist.id);
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
    _showLoadingDialog(context, '正在获取「${kugouPlaylist.name}」的歌曲...');

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
        } else if (ThemeManager().isCupertinoFramework) {
          showCupertinoDialog(
            context: context,
            barrierDismissible: false,
            builder: (dialogCtx) {
              return StatefulBuilder(
                builder: (context, setState) {
                  dialogSetState = setState;
                  return Center(
                    child: Container(
                      padding: const EdgeInsets.all(24),
                      decoration: BoxDecoration(
                        color: CupertinoColors.systemBackground.resolveFrom(context),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const CupertinoActivityIndicator(radius: 16),
                          const SizedBox(height: 16),
                          Text(
                            '正在导入\n$currentProgress/${tracks.length}',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 14,
                              color: CupertinoColors.label.resolveFrom(context),
                              decoration: TextDecoration.none,
                            ),
                          ),
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
      } else if (ThemeManager().isCupertinoFramework) {
        await showCupertinoDialog(
          context: context,
          builder: (context) => CupertinoAlertDialog(
            title: const Text('获取歌曲失败'),
            content: Text('$e'),
            actions: [
              CupertinoDialogAction(
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
    } else if (ThemeManager().isCupertinoFramework) {
      showCupertinoDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => WillPopScope(
          onWillPop: () async => false,
          child: Center(
            child: Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: CupertinoColors.systemBackground.resolveFrom(context),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const CupertinoActivityIndicator(radius: 16),
                  const SizedBox(height: 16),
                  Text(
                    '正在获取${platform.name}歌单信息...',
                    style: TextStyle(
                      fontSize: 14,
                      color: CupertinoColors.label.resolveFrom(context),
                      decoration: TextDecoration.none,
                    ),
                  ),
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

    bool loadingClosed = false;
    void closeLoadingIfOpen() {
      if (!loadingClosed && context.mounted) {
        Navigator.pop(context); // 关闭加载对话框
        loadingClosed = true;
      }
    }

    try {
      final baseUrl = UrlService().baseUrl;
      String url;
      if (platform == MusicPlatform.netease) {
        url = '$baseUrl/playlist?id=$playlistId&limit=1000';
      } else if (platform == MusicPlatform.qq) {
        url = '$baseUrl/qq/playlist?id=$playlistId&limit=1000';
      } else if (platform == MusicPlatform.kuwo) {
        url = '$baseUrl/kuwo/playlist?pid=$playlistId&limit=500';
      } else if (platform == MusicPlatform.apple) {
        url = '$baseUrl/apple/playlist?id=$playlistId';
      } else {
        throw Exception('不支持的平台');
      }
      
      debugPrint('[ImportPlaylistDialog] fetch playlist request: url=$url');

      final response = await http.get(
        Uri.parse(url),
      ).timeout(
        const Duration(seconds: 30),
        onTimeout: () => throw Exception('请求超时'),
      );

      if (!context.mounted) return;
      closeLoadingIfOpen(); // 关闭加载对话框

      debugPrint('[ImportPlaylistDialog] fetch playlist response status=${response.statusCode}');
      if (response.body.isNotEmpty) {
        debugPrint('[ImportPlaylistDialog] fetch playlist response body: ${response.body}');
      }

      if (response.statusCode == 200) {
        final data = json.decode(utf8.decode(response.bodyBytes));

        // 酷我音乐返回格式不同
        if (platform == MusicPlatform.kuwo) {
          if (data['status'] == 200 && data['data'] != null) {
            final playlist = UniversalPlaylist.fromKuwoJson(data['data']);
            await _showSelectTargetPlaylistDialog(context, playlist);
          } else {
            throw Exception(data['msg'] ?? '获取歌单失败');
          }
        } else if (platform == MusicPlatform.apple) {
          // Apple Music 返回格式
          if (data['status'] == 200 && data['data'] != null) {
            final playlist = UniversalPlaylist.fromAppleJson(data['data']['playlist']);
            await _showSelectTargetPlaylistDialog(context, playlist);
          } else {
            throw Exception(data['msg'] ?? '获取歌单失败');
          }
        } else if (data['status'] == 200 && data['success'] == true) {
          final playlistData = data['data']['playlist'];
          final playlist = UniversalPlaylist.fromJson(playlistData, platform);

          // 显示选择目标歌单对话框
          await _showSelectTargetPlaylistDialog(context, playlist);
        } else {
          debugPrint('[ImportPlaylistDialog] fetch playlist failed: data=$data');
          throw Exception(data['msg'] ?? '获取歌单失败');
        }
      } else {
        debugPrint('[ImportPlaylistDialog] fetch playlist failed: HTTP ${response.statusCode}');
        throw Exception('HTTP ${response.statusCode}');
      }
    } catch (e) {
      debugPrint('[ImportPlaylistDialog] fetch playlist exception: $e');
      if (!context.mounted) return;
      closeLoadingIfOpen(); // 关闭加载对话框

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
      } else if (ThemeManager().isCupertinoFramework) {
        await showCupertinoDialog(
          context: context,
          builder: (context) => CupertinoAlertDialog(
            title: const Text('导入失败'),
            content: Text('获取歌单失败: $e'),
            actions: [
              CupertinoDialogAction(
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
    } else if (ThemeManager().isCupertinoFramework) {
      targetPlaylist = await _showCupertinoSelectTargetPlaylistDialog(context, sourcePlaylist);
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

  /// Cupertino UI: 选择目标歌单对话框
  static Future<Playlist?> _showCupertinoSelectTargetPlaylistDialog(
    BuildContext context,
    UniversalPlaylist sourcePlaylist,
  ) async {
    final playlistService = PlaylistService();
    if (playlistService.playlists.isEmpty) {
      await playlistService.loadPlaylists();
    }
    if (!context.mounted) return null;

    return showCupertinoModalPopup<Playlist>(
      context: context,
      builder: (context) {
        final isDark = CupertinoTheme.brightnessOf(context) == Brightness.dark;
        
        // 内部状态组件，用于处理新建歌单
        return StatefulBuilder(
          builder: (context, setState) {
            return Material(
              type: MaterialType.transparency,
              child: Container(
                height: MediaQuery.of(context).size.height * 0.7,
                decoration: BoxDecoration(
                  color: isDark ? const Color(0xFF1C1C1E) : CupertinoColors.systemBackground,
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
                ),
                child: SafeArea(
                  top: false,
                  child: Column(
                    children: [
                      // 顶部拖动条
                      Container(
                        margin: const EdgeInsets.only(top: 8),
                        width: 36,
                        height: 5,
                        decoration: BoxDecoration(
                          color: CupertinoColors.systemGrey3,
                          borderRadius: BorderRadius.circular(2.5),
                        ),
                      ),
                      // 标题栏
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            CupertinoButton(
                              padding: EdgeInsets.zero,
                              onPressed: () => Navigator.pop(context),
                              child: const Text('取消'),
                            ),
                            Text(
                              '选择目标歌单',
                              style: TextStyle(
                                fontSize: 17,
                                fontWeight: FontWeight.w600,
                                color: isDark ? CupertinoColors.white : CupertinoColors.black,
                              ),
                            ),
                            const SizedBox(width: 60), // 占位
                          ],
                        ),
                      ),
                      const Divider(height: 1),
                      // 内容区域
                      Expanded(
                        child: ListView(
                          padding: EdgeInsets.zero,
                          children: [
                            // 源歌单信息
                            Container(
                              margin: const EdgeInsets.all(16),
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: CupertinoColors.systemGrey6.resolveFrom(context),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Row(
                                children: [
                                  ClipRRect(
                                    borderRadius: BorderRadius.circular(6),
                                    child: Image.network(
                                      sourcePlaylist.coverImgUrl,
                                      width: 60,
                                      height: 60,
                                      fit: BoxFit.cover,
                                      errorBuilder: (_, __, ___) => Container(
                                        width: 60,
                                        height: 60,
                                        color: CupertinoColors.systemGrey5,
                                        child: const Icon(Icons.music_note, color: CupertinoColors.systemGrey),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          '${sourcePlaylist.name}',
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: TextStyle(
                                            fontSize: 16,
                                            fontWeight: FontWeight.w600,
                                            color: isDark ? CupertinoColors.white : CupertinoColors.black,
                                          ),
                                        ),
                                        const SizedBox(height: 4),
                                        Text(
                                          '来源: ${sourcePlaylist.platform.name} · ${sourcePlaylist.trackCount} 首',
                                          style: const TextStyle(
                                            fontSize: 13,
                                            color: CupertinoColors.systemGrey,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            
                            // 新建歌单
                            Material(
                              color: Colors.transparent,
                              child: InkWell(
                                onTap: () async {
                                  final controller = TextEditingController(text: sourcePlaylist.name);
                                  final name = await showCupertinoDialog<String>(
                                    context: context,
                                    builder: (context) => CupertinoAlertDialog(
                                      title: const Text('新建歌单'),
                                      content: Padding(
                                        padding: const EdgeInsets.only(top: 16),
                                        child: CupertinoTextField(
                                          controller: controller,
                                          placeholder: '歌单名称',
                                          autofocus: true,
                                        ),
                                      ),
                                      actions: [
                                        CupertinoDialogAction(
                                          onPressed: () => Navigator.pop(context),
                                          child: const Text('取消'),
                                        ),
                                        CupertinoDialogAction(
                                          onPressed: () {
                                            final n = controller.text.trim();
                                            if (n.isNotEmpty) {
                                              Navigator.pop(context, n);
                                            }
                                          },
                                          child: const Text('创建'),
                                        ),
                                      ],
                                    ),
                                  );
                                  
                                  if (name != null) {
                                    final newPlaylist = await playlistService.createPlaylist(name);
                                    if (newPlaylist != null && context.mounted) {
                                      setState(() {}); // 刷新列表
                                      // 可选：直接选中并返回
                                      // Navigator.pop(context, newPlaylist);
                                    }
                                  }
                                },
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                                  child: Row(
                                    children: [
                                      Container(
                                        width: 40,
                                        height: 40,
                                        decoration: BoxDecoration(
                                          color: CupertinoColors.activeBlue,
                                          borderRadius: BorderRadius.circular(20),
                                        ),
                                        child: const Icon(CupertinoIcons.add, color: CupertinoColors.white, size: 24),
                                      ),
                                      const SizedBox(width: 12),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              '新建歌单',
                                              style: TextStyle(
                                                fontSize: 16,
                                                color: isDark ? CupertinoColors.white : CupertinoColors.black,
                                              ),
                                            ),
                                            const SizedBox(height: 2),
                                            const Text(
                                              '创建一个新歌单来导入',
                                              style: TextStyle(
                                                fontSize: 13,
                                                color: CupertinoColors.systemGrey,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                      const Icon(CupertinoIcons.chevron_right, color: CupertinoColors.systemGrey3, size: 20),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                            
                            const Padding(
                              padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                              child: Text(
                                '现有歌单',
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w500,
                                  color: CupertinoColors.systemGrey,
                                ),
                              ),
                            ),
                            
                            // 现有歌单列表
                            ...playlistService.playlists.map((p) {
                              return Material(
                                color: Colors.transparent,
                                child: InkWell(
                                  onTap: () => Navigator.pop(context, p),
                                  child: Padding(
                                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                                    child: Row(
                                      children: [
                                        Container(
                                          width: 40,
                                          height: 40,
                                          decoration: BoxDecoration(
                                            color: p.isDefault ? CupertinoColors.systemPink.withOpacity(0.1) : CupertinoColors.systemGrey5,
                                            borderRadius: BorderRadius.circular(6),
                                          ),
                                          child: Icon(
                                            p.isDefault ? CupertinoIcons.heart_fill : CupertinoIcons.music_albums,
                                            color: p.isDefault ? CupertinoColors.systemPink : CupertinoColors.systemGrey,
                                            size: 20,
                                          ),
                                        ),
                                        const SizedBox(width: 12),
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                p.name,
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                                style: TextStyle(
                                                  fontSize: 16,
                                                  color: isDark ? CupertinoColors.white : CupertinoColors.black,
                                                ),
                                              ),
                                              const SizedBox(height: 2),
                                              Text(
                                                '${p.trackCount} 首歌曲',
                                                style: const TextStyle(
                                                  fontSize: 13,
                                                  color: CupertinoColors.systemGrey,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                        if (p.isDefault)
                                          Container(
                                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                            margin: const EdgeInsets.only(right: 8),
                                            decoration: BoxDecoration(
                                              color: CupertinoColors.systemPink.withOpacity(0.1),
                                              borderRadius: BorderRadius.circular(4),
                                            ),
                                            child: const Text(
                                              '默认',
                                              style: TextStyle(
                                                fontSize: 10,
                                                color: CupertinoColors.systemPink,
                                              ),
                                            ),
                                          ),
                                        const Icon(CupertinoIcons.chevron_right, color: CupertinoColors.systemGrey3, size: 20),
                                      ],
                                    ),
                                  ),
                                ),
                              );
                            }).toList(),
                          ],
                        ),
                      ),
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
                    final newPlaylist = await playlistService.createPlaylist(name);
                    if (newPlaylist != null && context.mounted) {
                      Navigator.pop(context, newPlaylist);
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
      // 使用批量导入 API（一次网络请求，大幅提升速度）
      final result = await playlistService.addTracksToPlaylist(
        targetPlaylist.id,
        sourcePlaylist.tracks,
      );
      
      final successCount = result['successCount'] ?? 0;
      final skipCount = result['skipCount'] ?? 0;
      final failCount = result['failCount'] ?? 0;

      if (!context.mounted) return;
      Navigator.pop(context); // 关闭进度对话框

      final platformKey = sourcePlaylist.platform == MusicPlatform.netease 
          ? 'netease' 
          : sourcePlaylist.platform == MusicPlatform.qq 
              ? 'qq' 
              : sourcePlaylist.platform == MusicPlatform.kuwo
                  ? 'kuwo'
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
                if (skipCount > 0) Text('已存在跳过: $skipCount 首', style: TextStyle(color: Colors.orange[700])),
                if (failCount > 0) Text('导入失败: $failCount 首', style: const TextStyle(color: Colors.red)),
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
                if (skipCount > 0) Text('已存在跳过: $skipCount 首', style: TextStyle(color: Colors.orange[700])),
                if (failCount > 0) Text('导入失败: $failCount 首', style: const TextStyle(color: Colors.red)),
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
