import 'dart:io';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:fluent_ui/fluent_ui.dart' as fluent;
import '../services/local_library_service.dart';
import '../services/player_service.dart';
import '../models/track.dart';
import '../utils/theme_manager.dart';

class LocalPage extends StatefulWidget {
  const LocalPage({super.key});

  @override
  State<LocalPage> createState() => _LocalPageState();
}

// === Fluent helpers ===
extension on _LocalPageState {
  void _showFluentInfo(String text, [fluent.InfoBarSeverity severity = fluent.InfoBarSeverity.info]) {
    _infoBarTimer?.cancel();
    setState(() {
      _fluentInfoText = text;
      _fluentInfoSeverity = severity;
    });
    _infoBarTimer = Timer(const Duration(seconds: 1), () {
      if (!mounted) return;
      setState(() {
        _fluentInfoText = null;
      });
    });
  }

  Widget _buildFluentEmpty() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.hasBoundedHeight && constraints.maxHeight < 200;
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
                    Icon(fluent.FluentIcons.folder, size: compact ? 56 : 80),
                    SizedBox(height: compact ? 10 : 12),
                    const Text(
                      '未选择本地音乐',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 18),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '可选择单首歌曲或扫描整个文件夹（支持 mp3/wav/flac 等）',
                      textAlign: TextAlign.center,
                      maxLines: compact ? 2 : 3,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 12),
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

  String _extOf(dynamic id) {
    if (id is String) {
      final idx = id.lastIndexOf('.');
      if (idx > 0 && idx < id.length - 1) {
        return id.substring(idx + 1).toUpperCase();
      }
    }
    return '';
  }

  /// 构建 subtitle 显示（艺术家 • 格式）
  String _buildSubtitle(Track track) {
    final parts = <String>[];
    if (track.artists.isNotEmpty && track.artists != '本地文件') {
      parts.add(track.artists);
    }
    parts.add(_extOf(track.id));
    return parts.join(' • ');
  }
}

/// 独立的本地音乐卡片组件，用于性能优化
class _FluentLocalTrackTile extends StatelessWidget {
  final Track track;
  final int index;
  final VoidCallback onPlay;

  const _FluentLocalTrackTile({
    required this.track,
    required this.index,
    required this.onPlay,
  });

  @override
  Widget build(BuildContext context) {
    final theme = fluent.FluentTheme.of(context);
    final resources = theme.resources;

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: fluent.Card(
        borderRadius: BorderRadius.circular(12),
        padding: EdgeInsets.zero,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onPlay,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                SizedBox(
                  width: 32,
                  child: Text(
                    '${index + 1}',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      color: resources.textFillColorSecondary,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                _buildCover(resources, track),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        track.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 15,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        _buildSubtitleText(track),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 13,
                          color: resources.textFillColorSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                fluent.IconButton(
                  icon: const Icon(fluent.FluentIcons.play),
                  onPressed: onPlay,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildCover(fluent.ResourceDictionary resources, Track track) {
    final placeholder = Container(
      width: 64,
      height: 64,
      decoration: BoxDecoration(
        color: resources.controlAltFillColorSecondary,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Icon(
        fluent.FluentIcons.music_in_collection,
        color: resources.textFillColorTertiary,
        size: 24,
      ),
    );

    if (track.picUrl.isEmpty) return placeholder;

    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: Image.file(
        File(track.picUrl),
        width: 64,
        height: 64,
        cacheWidth: 128, // 性能优化
        cacheHeight: 128,
        fit: BoxFit.cover,
        errorBuilder: (context, error, stackTrace) => placeholder,
      ),
    );
  }

  String _buildSubtitleText(Track track) {
    final parts = <String>[];
    if (track.artists.isNotEmpty && track.artists != '本地文件') {
      parts.add(track.artists);
    }
    final id = track.id;
    if (id is String) {
      final idx = id.lastIndexOf('.');
      if (idx > 0 && idx < id.length - 1) {
        parts.add(id.substring(idx + 1).toUpperCase());
      }
    }
    return parts.join(' • ');
  }
}

class _LocalPageState extends State<LocalPage> {
  final LocalLibraryService _local = LocalLibraryService();
  final ThemeManager _themeManager = ThemeManager();
  String? _fluentInfoText;
  fluent.InfoBarSeverity _fluentInfoSeverity = fluent.InfoBarSeverity.info;
  Timer? _infoBarTimer;

  @override
  void initState() {
    super.initState();
    _local.addListener(_onChanged);
  }

  @override
  void dispose() {
    _local.removeListener(_onChanged);
    _infoBarTimer?.cancel();
    super.dispose();
  }

  void _onChanged() {
    if (mounted) setState(() {});
  }

  bool get _isCupertino => _themeManager.isCupertinoFramework;
  bool get _isAndroid => Theme.of(context).platform == TargetPlatform.android;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    if (_themeManager.isFluentFramework) {
      return _buildFluentPage(context);
    }
    if (_isCupertino) {
      return _buildCupertinoPage(context);
    }
    return Scaffold(
      backgroundColor: colorScheme.surface,
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            floating: true,
            snap: true,
            backgroundColor: colorScheme.surface,
            title: Text(
              '本地',
              style: TextStyle(
                color: colorScheme.onSurface,
                fontSize: 24,
                fontWeight: FontWeight.bold,
              ),
            ),
            actions: [
              IconButton(
                icon: const Icon(Icons.audio_file),
                tooltip: '选择单首歌曲',
                onPressed: () async {
                  await _local.pickSingleSong();
                },
              ),
              IconButton(
                icon: Icon(_isAndroid ? Icons.library_music : Icons.folder_open),
                tooltip: _isAndroid ? '批量选择音频文件' : '选择文件夹并扫描',
                onPressed: () async {
                  await _local.pickAndScanFolder();
                },
              ),
              if (_local.tracks.isNotEmpty)
                IconButton(
                  icon: const Icon(Icons.delete_sweep),
                  tooltip: '清空列表',
                  onPressed: () {
                    _local.clear();
                  },
                ),
            ],
          ),
          SliverPadding(
            padding: const EdgeInsets.all(24.0),
            sliver: _local.tracks.isEmpty
                ? SliverToBoxAdapter(child: _buildEmpty())
                : SliverList.builder(
                    itemCount: _local.tracks.length,
                    itemBuilder: (context, index) {
                      final track = _local.tracks[index];
                      return _LocalTrackTile(track: track);
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildFluentPage(BuildContext context) {
    final tracks = _local.tracks;
    return fluent.ScaffoldPage(
      padding: EdgeInsets.zero,
      content: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
            child: Row(
              children: [
                const Text(
                  '本地',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                ),
                const Spacer(),
                fluent.IconButton(
                  icon: const Icon(fluent.FluentIcons.music_in_collection),
                  onPressed: () async {
                    await _local.pickSingleSong();
                  },
                ),
                const SizedBox(width: 6),
                fluent.IconButton(
                  icon: const Icon(fluent.FluentIcons.folder_open),
                  onPressed: () async {
                    await _local.pickAndScanFolder();
                  },
                ),
                if (tracks.isNotEmpty) ...[
                  const SizedBox(width: 6),
                  fluent.IconButton(
                    icon: const Icon(fluent.FluentIcons.delete),
                    onPressed: () {
                      _local.clear();
                      _showFluentInfo('已清空');
                    },
                  ),
                ],
              ],
            ),
          ),
          if (_fluentInfoText != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 12, 24, 0),
              child: fluent.InfoBar(
                title: Text(_fluentInfoText!),
                severity: _fluentInfoSeverity,
                isLong: false,
              ),
            ),
          Expanded(
            child: tracks.isEmpty
                ? _buildFluentEmpty()
                : ListView.separated(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                    itemBuilder: (context, index) => RepaintBoundary(
                      child: _FluentLocalTrackTile(
                        track: tracks[index],
                        index: index,
                        onPlay: () async {
                          await PlayerService().playTrack(tracks[index]);
                          _showFluentInfo('正在播放: ${tracks[index].name}');
                        },
                      ),
                    ),
                    separatorBuilder: (_, __) => const SizedBox(height: 8),
                    itemCount: tracks.length,
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmpty() {
    final cs = Theme.of(context).colorScheme;
    final isAndroid = Theme.of(context).platform == TargetPlatform.android;
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.hasBoundedHeight && constraints.maxHeight < 200;
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
                    Icon(Icons.folder, size: compact ? 52 : 64, color: cs.onSurfaceVariant),
                    SizedBox(height: compact ? 10 : 12),
                    Text(
                      '未选择本地音乐',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 8),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Text(
                        isAndroid
                            ? '点击右上方按钮选择单首或批量选择多首音乐文件\n（支持 mp3/wav/flac 等格式）'
                            : '可选择单首歌曲或扫描整个文件夹（支持 mp3/wav/flac 等）',
                        textAlign: TextAlign.center,
                        maxLines: compact ? 2 : 3,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(
                          context,
                        ).textTheme.bodyMedium?.copyWith(color: cs.onSurfaceVariant),
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

  /// iOS Cupertino 风格页面
  Widget _buildCupertinoPage(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final tracks = _local.tracks;
    return Material(
      type: MaterialType.transparency,
      child: CupertinoPageScaffold(
        backgroundColor: isDark ? const Color(0xFF000000) : CupertinoColors.systemGroupedBackground,
        navigationBar: CupertinoNavigationBar(
          middle: const Text('本地'),
          backgroundColor: (isDark ? const Color(0xFF1C1C1E) : CupertinoColors.white).withOpacity(0.9),
          border: null,
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              CupertinoButton(
                padding: EdgeInsets.zero,
                child: const Icon(CupertinoIcons.music_note, size: 22),
                onPressed: () async {
                  await _local.pickSingleSong();
                },
              ),
              CupertinoButton(
                padding: EdgeInsets.zero,
                child: const Icon(CupertinoIcons.music_albums, size: 22),
                onPressed: () async {
                  await _local.pickAndScanFolder();
                },
              ),
              if (tracks.isNotEmpty)
                CupertinoButton(
                  padding: EdgeInsets.zero,
                  child: const Icon(CupertinoIcons.trash, size: 22),
                  onPressed: () {
                    _local.clear();
                  },
                ),
            ],
          ),
        ),
        child: SafeArea(
          child: tracks.isEmpty
              ? _buildCupertinoEmpty(isDark)
              : ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: tracks.length + 1, // +1 for bottom padding
                  itemBuilder: (context, index) {
                    if (index == tracks.length) {
                      return SizedBox(height: MediaQuery.of(context).padding.bottom + 80);
                    }
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: _buildCupertinoTrackTile(tracks[index], isDark),
                    );
                  },
                ),
        ),
      ),
    );
  }

  Widget _buildCupertinoEmpty(bool isDark) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.hasBoundedHeight && constraints.maxHeight < 200;
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
                      CupertinoIcons.folder,
                      size: compact ? 56 : 80,
                      color: CupertinoColors.systemGrey.withOpacity(0.5),
                    ),
                    SizedBox(height: compact ? 10 : 16),
                    Text(
                      '未选择本地音乐',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w500,
                        color: isDark ? CupertinoColors.white : CupertinoColors.black,
                      ),
                    ),
                    const SizedBox(height: 8),
                    const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 16),
                      child: Text(
                        '点击右上方按钮选择单首或批量选择多首音乐文件\n（支持 mp3/wav/flac 等格式）',
                        textAlign: TextAlign.center,
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 14,
                          color: CupertinoColors.systemGrey,
                        ),
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

  Widget _buildCupertinoTrackTile(Track track, bool isDark) {
    return Container(
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1C1C1E) : CupertinoColors.white,
        borderRadius: BorderRadius.circular(10),
      ),
      child: CupertinoButton(
        padding: EdgeInsets.zero,
        onPressed: () async {
          await PlayerService().playTrack(track);
        },
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              // 封面
              _buildCupertinoCover(track, isDark),
              const SizedBox(width: 12),
              // 信息
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
                        color: isDark ? CupertinoColors.white : CupertinoColors.black,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _buildSubtitle(track),
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
              // 播放按钮
              CupertinoButton(
                padding: const EdgeInsets.all(8),
                minSize: 0,
                onPressed: () async {
                  await PlayerService().playTrack(track);
                },
                child: Icon(CupertinoIcons.play_fill, size: 22, color: CupertinoColors.activeBlue),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCupertinoCover(Track track, bool isDark) {
    if (track.picUrl.isNotEmpty) {
      // 本地文件使用 Image.file
      return ClipRRect(
        borderRadius: BorderRadius.circular(6),
        child: Image.file(
          File(track.picUrl),
          width: 48,
          height: 48,
          fit: BoxFit.cover,
          errorBuilder: (context, error, stackTrace) => Container(
            width: 48,
            height: 48,
            color: isDark ? const Color(0xFF2C2C2E) : CupertinoColors.systemGrey5,
            child: Icon(CupertinoIcons.music_note, color: CupertinoColors.systemGrey),
          ),
        ),
      );
    }
    return Container(
      width: 48,
      height: 48,
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF2C2C2E) : CupertinoColors.systemGrey5,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Icon(CupertinoIcons.music_note, color: CupertinoColors.systemGrey),
    );
  }
}

class _LocalTrackTile extends StatelessWidget {
  final Track track;
  const _LocalTrackTile({required this.track});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: ListTile(
        leading: _buildCover(cs),
        title: Text(track.name, maxLines: 1, overflow: TextOverflow.ellipsis),
        subtitle: Text(_buildSubtitle(track), maxLines: 1, overflow: TextOverflow.ellipsis),
        trailing: IconButton(
          icon: const Icon(Icons.play_arrow),
          onPressed: () async {
            await PlayerService().playTrack(track);
          },
          tooltip: '播放',
        ),
        onTap: () async {
          await PlayerService().playTrack(track);
        },
      ),
    );
  }

  /// 构建 subtitle 显示（艺术家 • 格式）
  String _buildSubtitle(Track track) {
    final parts = <String>[];
    if (track.artists.isNotEmpty && track.artists != '本地文件') {
      parts.add(track.artists);
    }
    parts.add(_extOf(track.id));
    return parts.join(' • ');
  }

  Widget _buildCover(ColorScheme cs) {
    if (track.picUrl.isNotEmpty) {
      // 本地文件使用 Image.file
      return ClipRRect(
        borderRadius: BorderRadius.circular(6),
        child: Image.file(
          File(track.picUrl),
          width: 48,
          height: 48,
          fit: BoxFit.cover,
          errorBuilder: (context, error, stackTrace) => Container(
            width: 48,
            height: 48,
            color: cs.surfaceContainerHighest,
            child: Icon(Icons.music_note, color: cs.onSurfaceVariant),
          ),
        ),
      );
    }
    return Container(
      width: 48,
      height: 48,
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Icon(Icons.music_note, color: cs.onSurfaceVariant),
    );
  }

  String _extOf(dynamic id) {
    if (id is String) {
      final idx = id.lastIndexOf('.');
      if (idx > 0 && idx < id.length - 1) return id.substring(idx + 1).toUpperCase();
    }
    return '';
  }
}


