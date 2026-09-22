import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:fluent_ui/fluent_ui.dart' as fluent_ui;
import 'package:file_picker/file_picker.dart';
import '../../services/cache_service.dart';
import '../../services/download_service.dart';
import '../../services/media_cache_service.dart';
import '../../utils/format_utils.dart';
import '../../widgets/fluent_settings_card.dart';
import '../../widgets/cupertino/cupertino_settings_widgets.dart';
import '../../utils/theme_manager.dart';
import '../../widgets/material/material_settings_widgets.dart';

/// 存储设置组件
class StorageSettings extends StatefulWidget {
  final bool cardWrapped;

  const StorageSettings({super.key, this.cardWrapped = true});

  @override
  State<StorageSettings> createState() => _StorageSettingsState();
}

class _StorageSettingsState extends State<StorageSettings> {
  static const List<int> _cacheSizeLimitOptions = <int>[
    512 * 1024 * 1024,
    1024 * 1024 * 1024,
    2 * 1024 * 1024 * 1024,
    4 * 1024 * 1024 * 1024,
    8 * 1024 * 1024 * 1024,
  ];

  Future<MediaCacheStats> _loadCombinedCacheStats() async {
    return MediaCacheService().getCombinedCacheStats();
  }

  Future<void> _clearAllCaches() async {
    await MediaCacheService().clearAllCaches();
  }

  String _formatCacheSizeLimitOption(int bytes) {
    return formatFileSize(bytes, fractionDigits: 1, trimTrailingZeros: true);
  }

  Future<void> _applyCacheSizeLimit(int bytes) async {
    final previous = CacheService().maxCacheSizeBytes;
    await CacheService().setMaxCacheSizeBytes(bytes);
    if (!mounted) return;

    setState(() {});

    if (previous == bytes) {
      return;
    }

    final messenger = ScaffoldMessenger.maybeOf(context);
    if (messenger != null) {
      messenger.showSnackBar(
        SnackBar(
          content: Text('缓存空间上限已更新为 ${_formatCacheSizeLimitOption(bytes)}'),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final isFluent = fluent_ui.FluentTheme.maybeOf(context) != null;
    final isCupertino = ThemeManager().isCupertinoFramework;

    if (isFluent) {
      return FluentSettingsGroup(
        title: '存储',
        children: [
          FluentSwitchTile(
            icon: Icons.cloud_download,
            title: '启用音频缓存',
            subtitle: CacheService().cacheEnabled ? '自动缓存播放过的歌曲' : '缓存已禁用',
            value: CacheService().cacheEnabled,
            onChanged: (value) async {
              await CacheService().setCacheEnabled(value);
              setState(() {});
            },
          ),
          FluentSettingsTile(
            icon: Icons.sd_storage,
            title: '缓存空间限制',
            subtitle: _getCacheSizeLimitSubtitle(),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => _showCacheSizeLimitSettingsFluent(),
          ),
          if (Platform.isWindows)
            FluentSettingsTile(
              icon: Icons.folder,
              title: '缓存目录',
              subtitle: _getCacheDirSubtitle(),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => _showCacheDirSettingsFluent(),
            ),
          FluentSettingsTile(
            icon: Icons.storage,
            title: '缓存管理',
            subtitle: _getCacheSubtitle(),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => _showCacheManagementFluent(),
          ),
          if (Platform.isWindows)
            FluentSettingsTile(
              icon: Icons.download,
              title: '下载目录',
              subtitle: _getDownloadDirSubtitle(),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => _showDownloadDirSettingsFluent(),
            ),
        ],
      );
    }

    if (isCupertino) {
      return _buildCupertinoUI(context);
    }

    if (!widget.cardWrapped) {
      final colorScheme = Theme.of(context).colorScheme;
      final isDark = Theme.of(context).brightness == Brightness.dark;

      Widget buildItem({
        required IconData icon,
        required Color iconColor,
        required String title,
        String? subtitle,
        Widget? trailing,
        VoidCallback? onTap,
      }) {
        return InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            child: Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: iconColor.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(icon, color: iconColor, size: 20),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: colorScheme.onSurface,
                        ),
                      ),
                      if (subtitle != null) ...[
                        const SizedBox(height: 2),
                        Text(
                          subtitle,
                          style: TextStyle(
                            fontSize: 13,
                            color: colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                trailing ??
                    Icon(
                      Icons.chevron_right,
                      color: colorScheme.onSurfaceVariant.withValues(
                        alpha: 0.5,
                      ),
                      size: 20,
                    ),
              ],
            ),
          ),
        );
      }

      final items = <Widget>[
        buildItem(
          icon: Icons.cloud_download_outlined,
          iconColor: const Color(0xFF009688),
          title: '启用音频缓存',
          subtitle: CacheService().cacheEnabled ? '自动缓存播放过的歌曲' : '缓存已禁用',
          trailing: Switch(
            value: CacheService().cacheEnabled,
            onChanged: (value) async {
              await CacheService().setCacheEnabled(value);
              setState(() {});
            },
          ),
          onTap: () async {
            await CacheService().setCacheEnabled(!CacheService().cacheEnabled);
            setState(() {});
          },
        ),
        buildItem(
          icon: Icons.sd_storage_outlined,
          iconColor: const Color(0xFFFF5722),
          title: '缓存空间限制',
          subtitle: _getCacheSizeLimitSubtitle(),
          onTap: () => _showCacheSizeLimitSettings(),
        ),
        if (Platform.isWindows)
          buildItem(
            icon: Icons.folder_outlined,
            iconColor: const Color(0xFF795548),
            title: '缓存目录',
            subtitle: _getCacheDirSubtitle(),
            onTap: () => _showCacheDirSettings(),
          ),
        buildItem(
          icon: Icons.storage_outlined,
          iconColor: const Color(0xFFE91E63),
          title: '缓存管理',
          subtitle: _getCacheSubtitle(),
          onTap: () => _showCacheManagement(),
        ),
        if (Platform.isWindows)
          buildItem(
            icon: Icons.download_outlined,
            iconColor: const Color(0xFF4CAF50),
            title: '下载目录',
            subtitle: _getDownloadDirSubtitle(),
            onTap: () => _showDownloadDirSettings(),
          ),
      ];

      final childrenWithDividers = <Widget>[];
      for (int i = 0; i < items.length; i++) {
        childrenWithDividers.add(items[i]);
        if (i < items.length - 1) {
          childrenWithDividers.add(
            Padding(
              padding: const EdgeInsets.only(left: 64),
              child: Divider(
                height: 1,
                thickness: 0.5,
                color: isDark
                    ? Colors.white12
                    : Colors.black.withValues(alpha: 0.06),
              ),
            ),
          );
        }
      }

      return Column(
        mainAxisSize: MainAxisSize.min,
        children: childrenWithDividers,
      );
    }

    return MD3SettingsSection(
      children: [
        MD3SwitchTile(
          leading: const Icon(Icons.cloud_download_outlined),
          title: '启用音频缓存',
          subtitle: CacheService().cacheEnabled ? '自动缓存播放过的歌曲' : '缓存已禁用',
          value: CacheService().cacheEnabled,
          onChanged: (value) async {
            await CacheService().setCacheEnabled(value);
            setState(() {});
          },
        ),
        MD3SettingsTile(
          leading: const Icon(Icons.sd_storage_outlined),
          title: '缓存空间限制',
          subtitle: _getCacheSizeLimitSubtitle(),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => _showCacheSizeLimitSettings(),
        ),
        if (Platform.isWindows)
          MD3SettingsTile(
            leading: const Icon(Icons.folder_outlined),
            title: '缓存目录',
            subtitle: _getCacheDirSubtitle(),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => _showCacheDirSettings(),
          ),
        MD3SettingsTile(
          leading: const Icon(Icons.storage_outlined),
          title: '缓存管理',
          subtitle: _getCacheSubtitle(),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => _showCacheManagement(),
        ),
        if (Platform.isWindows)
          MD3SettingsTile(
            leading: const Icon(Icons.download_outlined),
            title: '下载目录',
            subtitle: _getDownloadDirSubtitle(),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => _showDownloadDirSettings(),
          ),
      ],
    );
  }

  /// 构建 Cupertino UI 版本
  Widget _buildCupertinoUI(BuildContext context) {
    return Column(
      children: [
        // 启用缓存开关
        CupertinoSwitchTile(
          icon: CupertinoIcons.cloud_download,
          iconColor: CupertinoColors.systemBlue,
          title: '启用音频缓存',
          subtitle: CacheService().cacheEnabled ? '自动缓存播放过的歌曲' : '缓存已禁用',
          value: CacheService().cacheEnabled,
          onChanged: (value) async {
            await CacheService().setCacheEnabled(value);
            setState(() {});
          },
        ),
        CupertinoSettingsTile(
          icon: CupertinoIcons.archivebox,
          iconColor: CupertinoColors.systemPurple,
          title: '缓存空间限制',
          subtitle: _getCacheSizeLimitSubtitle(),
          showChevron: true,
          onTap: () => _showCacheSizeLimitSettingsCupertino(),
        ),
        // 缓存管理
        CupertinoSettingsTile(
          icon: CupertinoIcons.tray_full,
          iconColor: CupertinoColors.systemOrange,
          title: '缓存管理',
          subtitle: _getCacheSubtitle(),
          showChevron: true,
          onTap: () => _showCacheManagementCupertino(),
        ),
      ],
    );
  }

  Future<void> _showCacheSizeLimitSettingsCupertino() async {
    final currentLimit = CacheService().maxCacheSizeBytes;
    if (!mounted) return;

    showCupertinoModalPopup<void>(
      context: context,
      builder: (context) => CupertinoActionSheet(
        title: const Text('缓存空间限制'),
        message: Text(
          '当前上限 ${_formatCacheSizeLimitOption(currentLimit)}\n'
          '超出上限后会自动清理较早使用的音频缓存',
        ),
        actions: _cacheSizeLimitOptions.map((option) {
          final label = _formatCacheSizeLimitOption(option);
          final isCurrent = option == currentLimit;
          return CupertinoActionSheetAction(
            isDefaultAction: isCurrent,
            onPressed: () async {
              Navigator.pop(context);
              await _applyCacheSizeLimit(option);
            },
            child: Text(isCurrent ? '$label（当前）' : label),
          );
        }).toList(),
        cancelButton: CupertinoActionSheetAction(
          isDefaultAction: true,
          onPressed: () => Navigator.pop(context),
          child: const Text('取消'),
        ),
      ),
    );
  }

  /// 显示 Cupertino 风格的缓存管理对话框
  Future<void> _showCacheManagementCupertino() async {
    final stats = await _loadCombinedCacheStats();
    if (!mounted) return;

    showCupertinoModalPopup<void>(
      context: context,
      builder: (context) => CupertinoActionSheet(
        title: const Text('缓存管理'),
        message: Text(
          '占用空间: ${stats.formattedSize}\n'
          '空间上限: ${CacheService().formattedMaxCacheSize}\n'
          '音频缓存 ${stats.audio.totalFiles} 首歌曲\n'
          '歌词缓存 ${stats.lyric.totalFiles} 条记录\n'
          '歌词详情 可用 ${stats.lyric.readyCount} / 空结果 ${stats.lyric.emptyCount} / 失败退避 ${stats.lyric.failedCount}',
        ),
        actions: [
          if (stats.totalFiles > 0)
            CupertinoActionSheetAction(
              isDestructiveAction: true,
              onPressed: () {
                Navigator.pop(context);
                _confirmClearCacheCupertino();
              },
              child: const Text('清除缓存'),
            ),
        ],
        cancelButton: CupertinoActionSheetAction(
          isDefaultAction: true,
          onPressed: () => Navigator.pop(context),
          child: const Text('关闭'),
        ),
      ),
    );
  }

  /// 确认清除缓存 - Cupertino 风格
  Future<void> _confirmClearCacheCupertino() async {
    final stats = await _loadCombinedCacheStats();
    if (!mounted) return;

    showCupertinoDialog<void>(
      context: context,
      builder: (context) => CupertinoAlertDialog(
        title: const Text('清除缓存'),
        content: Text(
          '确定要清除所有缓存吗？\n\n'
          '将删除音频缓存 ${stats.audio.totalFiles} 首歌曲\n'
          '清除歌词缓存 ${stats.lyric.totalFiles} 条记录\n'
          '释放 ${stats.formattedSize} 空间',
        ),
        actions: [
          CupertinoDialogAction(
            isDestructiveAction: false,
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          CupertinoDialogAction(
            isDestructiveAction: true,
            onPressed: () async {
              Navigator.pop(context);
              await _clearAllCaches();
              if (mounted) {
                setState(() {});
              }
            },
            child: const Text('清除'),
          ),
        ],
      ),
    );
  }


  String _getCacheSubtitle() {
    if (!CacheService().isInitialized) {
      return '初始化中...';
    }

    if (!CacheService().cacheEnabled) {
      return '音频缓存已禁用，可管理已有缓存';
    }

    return '管理音频与歌词缓存';
  }

  String _getCacheDirSubtitle() {
    final customDir = CacheService().customCacheDir;
    if (customDir != null && customDir.isNotEmpty) {
      return '自定义：$customDir';
    }
    return '默认位置';
  }

  String _getCacheSizeLimitSubtitle() {
    return '当前上限 ${_formatCacheSizeLimitOption(CacheService().maxCacheSizeBytes)}';
  }

  String _getDownloadDirSubtitle() {
    final downloadPath = DownloadService().downloadPath;
    if (downloadPath != null && downloadPath.isNotEmpty) {
      return downloadPath;
    }
    return '未设置';
  }

  Future<void> _showCacheManagement() async {
    final stats = await _loadCombinedCacheStats();

    if (!mounted) return;

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Row(
          children: [Icon(Icons.storage), SizedBox(width: 8), Text('缓存管理')],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Theme.of(
                  context,
                ).colorScheme.primaryContainer.withValues(alpha: 0.5),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '占用空间',
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        stats.formattedSize,
                        style: Theme.of(context).textTheme.headlineSmall
                            ?.copyWith(
                              fontWeight: FontWeight.bold,
                              color: Theme.of(context).colorScheme.primary,
                            ),
                      ),
                    ],
                  ),
                  Icon(
                    Icons.folder_outlined,
                    size: 48,
                    color: Theme.of(
                      context,
                    ).colorScheme.primary.withValues(alpha: 0.3),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Icon(
                  Icons.audiotrack,
                  size: 20,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
                const SizedBox(width: 8),
                Text(
                  '音频缓存 ${stats.audio.totalFiles} 首歌曲',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Icon(
                  Icons.sd_storage_outlined,
                  size: 20,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
                const SizedBox(width: 8),
                Text(
                  '空间上限 ${CacheService().formattedMaxCacheSize}',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Icon(
                  Icons.lyrics_outlined,
                  size: 20,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
                const SizedBox(width: 8),
                Text(
                  '歌词缓存 ${stats.lyric.totalFiles} 条记录',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Icon(
                  Icons.fact_check_outlined,
                  size: 20,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
                const SizedBox(width: 8),
                Text(
                  '歌词详情 可用 ${stats.lyric.readyCount} / 空结果 ${stats.lyric.emptyCount} / 失败退避 ${stats.lyric.failedCount}',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ],
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('关闭'),
          ),
          if (stats.totalFiles > 0)
            FilledButton.icon(
              onPressed: () {
                Navigator.pop(context);
                _confirmClearCache();
              },
              icon: const Icon(Icons.delete_sweep),
              label: const Text('清除缓存'),
              style: FilledButton.styleFrom(
                backgroundColor: Theme.of(context).colorScheme.error,
              ),
            ),
        ],
      ),
    );
  }

  Future<void> _confirmClearCache() async {
    final stats = await _loadCombinedCacheStats();

    if (stats.totalFiles == 0) {
      if (mounted) {
        final messenger = ScaffoldMessenger.maybeOf(context);
        if (messenger != null) {
          messenger.showSnackBar(const SnackBar(content: Text('暂无缓存可清除')));
        }
      }
      return;
    }

    if (!mounted) return;

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('清除缓存'),
        content: Text(
          '确定要清除所有缓存吗？\n\n'
          '将删除音频缓存 ${stats.audio.totalFiles} 首歌曲\n'
          '清除歌词缓存 ${stats.lyric.totalFiles} 条记录\n'
          '释放 ${stats.formattedSize} 空间',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () async {
              Navigator.pop(context);

              final clearContext = context;
              if (mounted && clearContext.mounted) {
                final messenger = ScaffoldMessenger.maybeOf(clearContext);
                if (messenger != null) {
                  messenger.showSnackBar(
                    const SnackBar(
                      content: Row(
                        children: [
                          SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          ),
                          SizedBox(width: 16),
                          Text('正在清除缓存...'),
                        ],
                      ),
                      duration: Duration(seconds: 3),
                    ),
                  );
                }
              }

              await _clearAllCaches();

              final pageContext = context;
              if (mounted && pageContext.mounted) {
                final messenger = ScaffoldMessenger.maybeOf(pageContext);
                if (messenger != null) {
                  messenger.hideCurrentSnackBar();
                  messenger.showSnackBar(
                    SnackBar(
                      content: Text(
                        '已清除音频缓存 ${stats.audio.totalFiles} 首，歌词缓存 ${stats.lyric.totalFiles} 条',
                      ),
                      backgroundColor: Colors.green,
                    ),
                  );
                }
              }
            },
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
            ),
            child: const Text('清除'),
          ),
        ],
      ),
    );
  }

  Future<void> _showCacheManagementFluent() async {
    final stats = await _loadCombinedCacheStats();
    if (!mounted) return;
    fluent_ui.showDialog(
      context: context,
      builder: (context) => fluent_ui.ContentDialog(
        title: const Text('缓存管理'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('占用空间: ${stats.formattedSize}'),
            const SizedBox(height: 8),
            Text('空间上限: ${CacheService().formattedMaxCacheSize}'),
            const SizedBox(height: 8),
            Text('音频缓存 ${stats.audio.totalFiles} 首歌曲'),
            const SizedBox(height: 4),
            Text('歌词缓存 ${stats.lyric.totalFiles} 条记录'),
            const SizedBox(height: 4),
            Text(
              '歌词详情 可用 ${stats.lyric.readyCount} / 空结果 ${stats.lyric.emptyCount} / 失败退避 ${stats.lyric.failedCount}',
            ),
          ],
        ),
        actions: [
          fluent_ui.Button(
            onPressed: () => Navigator.pop(context),
            child: const Text('关闭'),
          ),
          if (stats.totalFiles > 0)
            fluent_ui.FilledButton(
              onPressed: () {
                Navigator.pop(context);
                _confirmClearCacheFluent();
              },
              child: const Text('清除缓存'),
            ),
        ],
      ),
    );
  }

  Future<void> _showCacheSizeLimitSettings() async {
    final currentLimit = CacheService().maxCacheSizeBytes;
    var selectedLimit = currentLimit;

    if (!mounted) return;

    await showDialog<void>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Row(
            children: [
              Icon(Icons.sd_storage_outlined),
              SizedBox(width: 8),
              Text('缓存空间限制'),
            ],
          ),
          content: SizedBox(
            width: 420,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '超出上限后会自动清理较早使用的音频缓存。',
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                  const SizedBox(height: 12),
                  ..._cacheSizeLimitOptions.map(
                    (option) => RadioGroup<int>(
                      groupValue: selectedLimit,
                      onChanged: (value) {
                        if (value == null) return;
                        setDialogState(() {
                          selectedLimit = value;
                        });
                      },
                      child: RadioListTile<int>(
                        contentPadding: EdgeInsets.zero,
                        value: option,
                        title: Text(_formatCacheSizeLimitOption(option)),
                        subtitle: Text(
                          option == currentLimit ? '当前设置' : '达到上限后自动清理旧缓存',
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () async {
                Navigator.pop(context);
                await _applyCacheSizeLimit(selectedLimit);
              },
              child: const Text('保存'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showCacheSizeLimitSettingsFluent() async {
    final currentLimit = CacheService().maxCacheSizeBytes;
    var selectedLimit = currentLimit;
    if (!mounted) return;

    fluent_ui.showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => fluent_ui.ContentDialog(
          title: const Text('缓存空间限制'),
          content: SizedBox(
            width: 360,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('超出上限后会自动清理较早使用的音频缓存。'),
                const SizedBox(height: 12),
                fluent_ui.RadioGroup<int>(
                  groupValue: selectedLimit,
                  onChanged: (value) {
                    if (value == null) return;
                    setDialogState(() {
                      selectedLimit = value;
                    });
                  },
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: _cacheSizeLimitOptions.map((option) {
                      final isCurrent = option == currentLimit;
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 6),
                        child: fluent_ui.RadioButton<int>(
                          value: option,
                          content: Text(
                            isCurrent
                                ? '${_formatCacheSizeLimitOption(option)}（当前）'
                                : _formatCacheSizeLimitOption(option),
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            fluent_ui.Button(
              onPressed: () => Navigator.pop(context),
              child: const Text('取消'),
            ),
            fluent_ui.FilledButton(
              onPressed: () async {
                Navigator.pop(context);
                await _applyCacheSizeLimit(selectedLimit);
              },
              child: const Text('保存'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _confirmClearCacheFluent() async {
    final stats = await _loadCombinedCacheStats();
    if (!mounted) return;
    fluent_ui.showDialog(
      context: context,
      builder: (context) => fluent_ui.ContentDialog(
        title: const Text('清除缓存'),
        content: Text(
          '确定要清除所有缓存吗？\n\n'
          '将删除音频缓存 ${stats.audio.totalFiles} 首歌曲\n'
          '清除歌词缓存 ${stats.lyric.totalFiles} 条记录\n'
          '释放 ${stats.formattedSize} 空间',
        ),
        actions: [
          fluent_ui.Button(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          fluent_ui.FilledButton(
            onPressed: () async {
              Navigator.pop(context);
              await _clearAllCaches();
              if (!context.mounted) return;
              final messenger = ScaffoldMessenger.maybeOf(context);
              if (messenger != null) {
                messenger.showSnackBar(
                  SnackBar(
                    content: Text(
                      '已清除音频缓存 ${stats.audio.totalFiles} 首，歌词缓存 ${stats.lyric.totalFiles} 条',
                    ),
                    backgroundColor: Colors.green,
                  ),
                );
              }
            },
            child: const Text('清除'),
          ),
        ],
      ),
    );
  }

  Future<void> _showCacheDirSettings() async {
    final currentCustomDir = CacheService().customCacheDir;
    final currentDir = CacheService().currentCacheDir;
    final defaultDir = await CacheService().getDefaultCacheDir();

    final dirController = TextEditingController(text: currentCustomDir ?? '');

    if (!mounted) return;

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: const Row(
            children: [Icon(Icons.folder), SizedBox(width: 8), Text('缓存目录设置')],
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '当前目录：',
                  style: Theme.of(
                    context,
                  ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                SelectableText(
                  currentDir ?? '未知',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    fontFamily: 'monospace',
                    color: Theme.of(context).colorScheme.primary,
                  ),
                ),
                const SizedBox(height: 16),
                const Divider(),
                const SizedBox(height: 16),
                Text(
                  '默认目录：',
                  style: Theme.of(
                    context,
                  ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                SelectableText(
                  defaultDir,
                  style: Theme.of(
                    context,
                  ).textTheme.bodySmall?.copyWith(fontFamily: 'monospace'),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: dirController,
                        decoration: const InputDecoration(
                          labelText: '自定义目录（留空使用默认）',
                          hintText: '例：D:\\Music\\Cache',
                          prefixIcon: Icon(Icons.edit_location),
                          border: OutlineInputBorder(),
                        ),
                        maxLines: 1,
                      ),
                    ),
                    const SizedBox(width: 8),
                    IconButton.filledTonal(
                      onPressed: () async {
                        String? selectedDirectory = await FilePicker.platform
                            .getDirectoryPath(
                              dialogTitle: '选择缓存目录',
                              lockParentWindow: true,
                            );

                        if (selectedDirectory != null) {
                          setState(() {
                            dirController.text = selectedDirectory;
                          });
                        }
                      },
                      icon: const Icon(Icons.folder_open),
                      tooltip: '浏览选择目录',
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Theme.of(
                      context,
                    ).colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(
                            Icons.info_outline,
                            size: 16,
                            color: Theme.of(context).colorScheme.primary,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            '提示',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              color: Theme.of(context).colorScheme.primary,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        '• 点击文件夹图标选择目录\n'
                        '• 更改目录需要重启应用生效\n'
                        '• 确保目录有读写权限\n'
                        '• 旧缓存不会自动迁移',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          actions: [
            if (currentCustomDir != null && currentCustomDir.isNotEmpty)
              TextButton.icon(
                onPressed: () async {
                  final success = await CacheService().setCustomCacheDir(null);
                  if (success && context.mounted) {
                    Navigator.pop(context);
                    final messenger = ScaffoldMessenger.maybeOf(context);
                    if (messenger != null) {
                      messenger.showSnackBar(
                        const SnackBar(content: Text('已恢复默认目录，请重启应用生效')),
                      );
                    }
                  }
                },
                icon: const Icon(Icons.restore),
                label: const Text('恢复默认'),
              ),
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () async {
                final newDir = dirController.text.trim();

                if (newDir.isEmpty || newDir == currentCustomDir) {
                  Navigator.pop(context);
                  return;
                }

                final success = await CacheService().setCustomCacheDir(newDir);

                if (context.mounted) {
                  Navigator.pop(context);
                  if (success) {
                    _showRestartDialog(newDir);
                  } else {
                    final messenger = ScaffoldMessenger.maybeOf(context);
                    if (messenger != null) {
                      messenger.showSnackBar(
                        SnackBar(
                          content: const Text('目录设置失败，请检查路径是否正确'),
                          backgroundColor: Theme.of(context).colorScheme.error,
                        ),
                      );
                    }
                  }
                }
              },
              child: const Text('保存'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showCacheDirSettingsFluent() async {
    final currentCustomDir = CacheService().customCacheDir;
    final currentDir = CacheService().currentCacheDir;
    final defaultDir = await CacheService().getDefaultCacheDir();
    final dirController = TextEditingController(text: currentCustomDir ?? '');
    if (!mounted) return;
    fluent_ui.showDialog(
      context: context,
      builder: (context) => fluent_ui.ContentDialog(
        title: const Text('缓存目录设置'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('当前目录：'),
            const SizedBox(height: 4),
            Text(currentDir ?? '未知'),
            const SizedBox(height: 12),
            Text('默认目录：'),
            const SizedBox(height: 4),
            Text(defaultDir),
            const SizedBox(height: 12),
            fluent_ui.TextBox(
              controller: dirController,
              placeholder: '自定义目录（留空使用默认）',
            ),
            const SizedBox(height: 8),
            fluent_ui.Button(
              onPressed: () async {
                String? selectedDirectory = await FilePicker.platform
                    .getDirectoryPath(
                      dialogTitle: '选择缓存目录',
                      lockParentWindow: true,
                    );
                if (selectedDirectory != null) {
                  dirController.text = selectedDirectory;
                }
              },
              child: const Text('浏览选择目录'),
            ),
          ],
        ),
        actions: [
          if (currentCustomDir != null && currentCustomDir.isNotEmpty)
            fluent_ui.Button(
              onPressed: () async {
                final success = await CacheService().setCustomCacheDir(null);
                if (success) {
                  if (!context.mounted) return;
                  Navigator.pop(context);
                  final messenger = ScaffoldMessenger.maybeOf(context);
                  if (messenger != null) {
                    messenger.showSnackBar(
                      const SnackBar(content: Text('已恢复默认目录，请重启应用生效')),
                    );
                  }
                }
              },
              child: const Text('恢复默认'),
            ),
          fluent_ui.Button(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          fluent_ui.FilledButton(
            onPressed: () async {
              final newDir = dirController.text.trim();
              if (newDir.isEmpty || newDir == currentCustomDir) {
                Navigator.pop(context);
                return;
              }
              final success = await CacheService().setCustomCacheDir(newDir);
              if (context.mounted) {
                Navigator.pop(context);
                if (success) {
                  _showRestartDialogFluent(newDir);
                } else {
                  final messenger = ScaffoldMessenger.maybeOf(context);
                  if (messenger != null) {
                    messenger.showSnackBar(
                      const SnackBar(content: Text('目录设置失败，请检查路径是否正确')),
                    );
                  }
                }
              }
            },
            child: const Text('保存'),
          ),
        ],
      ),
    );
  }

  void _showRestartDialog(String newDir) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        icon: const Icon(Icons.restart_alt, size: 48),
        title: const Text('需要重启应用'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('缓存目录已设置为：', style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 8),
            SelectableText(
              newDir,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                fontWeight: FontWeight.bold,
                color: Theme.of(context).colorScheme.primary,
              ),
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.errorContainer,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.warning,
                    color: Theme.of(context).colorScheme.error,
                    size: 20,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '必须重启应用才能使用新目录！\n当前播放的歌曲仍会缓存到旧目录。',
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.onErrorContainer,
                        fontSize: 12,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('知道了'),
          ),
        ],
      ),
    );
  }

  void _showRestartDialogFluent(String newDir) {
    fluent_ui.showDialog(
      context: context,
      builder: (context) => fluent_ui.ContentDialog(
        title: const Text('需要重启应用'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('缓存目录已设置为：'),
            const SizedBox(height: 8),
            Text(newDir),
            const SizedBox(height: 12),
            const Text('必须重启应用才能使用新目录！'),
          ],
        ),
        actions: [
          fluent_ui.FilledButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('知道了'),
          ),
        ],
      ),
    );
  }

  Future<void> _showDownloadDirSettings() async {
    final currentDownloadPath = DownloadService().downloadPath;
    final dirController = TextEditingController(
      text: currentDownloadPath ?? '',
    );

    if (!mounted) return;

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('下载目录设置'),
        content: SizedBox(
          width: 500,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('当前下载目录：', style: Theme.of(context).textTheme.titleSmall),
              const SizedBox(height: 8),
              Text(
                currentDownloadPath ?? '未设置',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 24),
              TextField(
                controller: dirController,
                decoration: const InputDecoration(
                  labelText: '新下载目录',
                  border: OutlineInputBorder(),
                  hintText: '例如: D:\\Music\\Cyrene',
                ),
                readOnly: true,
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () async {
                        final result = await FilePicker.platform
                            .getDirectoryPath(dialogTitle: '选择下载目录');

                        if (result != null) {
                          dirController.text = result;
                        }
                      },
                      icon: const Icon(Icons.folder_open),
                      label: const Text('浏览'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.secondaryContainer,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.info_outline,
                      size: 20,
                      color: Theme.of(context).colorScheme.onSecondaryContainer,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        '下载的音乐文件将保存到指定目录',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(
                            context,
                          ).colorScheme.onSecondaryContainer,
                        ),
                      ),
                    ),
                  ],
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
          FilledButton(
            onPressed: () async {
              final newDir = dirController.text.trim();

              if (newDir.isEmpty) {
                final messenger = ScaffoldMessenger.maybeOf(context);
                if (messenger != null) {
                  messenger.showSnackBar(
                    const SnackBar(content: Text('请选择下载目录')),
                  );
                }
                return;
              }

              final success = await DownloadService().setDownloadPath(newDir);

              if (context.mounted) {
                Navigator.pop(context);
                final messenger = ScaffoldMessenger.maybeOf(context);
                if (messenger != null) {
                  if (success) {
                    messenger.showSnackBar(
                      const SnackBar(content: Text('下载目录已更新')),
                    );
                  } else {
                    messenger.showSnackBar(
                      const SnackBar(content: Text('设置下载目录失败')),
                    );
                  }
                }
              }
            },
            child: const Text('保存'),
          ),
        ],
      ),
    );
  }

  Future<void> _showDownloadDirSettingsFluent() async {
    final currentDownloadPath = DownloadService().downloadPath;
    final dirController = TextEditingController(
      text: currentDownloadPath ?? '',
    );
    if (!mounted) return;
    fluent_ui.showDialog(
      context: context,
      builder: (context) => fluent_ui.ContentDialog(
        title: const Text('下载目录设置'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('当前下载目录：'),
            const SizedBox(height: 4),
            Text(currentDownloadPath ?? '未设置'),
            const SizedBox(height: 12),
            fluent_ui.TextBox(
              controller: dirController,
              placeholder: '例如: D:\\Music\\Cyrene',
              readOnly: true,
            ),
            const SizedBox(height: 8),
            fluent_ui.Button(
              onPressed: () async {
                final result = await FilePicker.platform.getDirectoryPath(
                  dialogTitle: '选择下载目录',
                );
                if (result != null) {
                  dirController.text = result;
                }
              },
              child: const Text('浏览'),
            ),
          ],
        ),
        actions: [
          fluent_ui.Button(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          fluent_ui.FilledButton(
            onPressed: () async {
              final newDir = dirController.text.trim();
              if (newDir.isEmpty) {
                final messenger = ScaffoldMessenger.maybeOf(context);
                if (messenger != null) {
                  messenger.showSnackBar(
                    const SnackBar(content: Text('请选择下载目录')),
                  );
                }
                return;
              }
              final success = await DownloadService().setDownloadPath(newDir);
              if (context.mounted) {
                Navigator.pop(context);
                final messenger = ScaffoldMessenger.maybeOf(context);
                if (messenger != null) {
                  messenger.showSnackBar(
                    SnackBar(content: Text(success ? '下载目录已更新' : '设置下载目录失败')),
                  );
                }
              }
            },
            child: const Text('保存'),
          ),
        ],
      ),
    );
  }
}
