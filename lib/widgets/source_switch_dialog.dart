import 'package:flutter/material.dart';
import 'package:fluent_ui/fluent_ui.dart' as fluent;
import 'package:cached_network_image/cached_network_image.dart';
import '../models/track.dart';
import '../models/playlist.dart';
import '../services/track_source_switch_service.dart';
import '../utils/theme_manager.dart';

/// 换源选择对话框 - 第一步：选择平台和歌曲
class SourceSwitchSelectDialog extends StatefulWidget {
  final List<PlaylistTrack> tracks;
  final MusicSource currentSource;

  const SourceSwitchSelectDialog({
    super.key,
    required this.tracks,
    required this.currentSource,
  });

  @override
  State<SourceSwitchSelectDialog> createState() => _SourceSwitchSelectDialogState();
}

class _SourceSwitchSelectDialogState extends State<SourceSwitchSelectDialog> {
  MusicSource? _targetSource;
  final Set<int> _selectedIndices = {};
  bool _selectAll = true;
  
  // 搜索相关
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    // 默认全选
    _selectedIndices.addAll(List.generate(widget.tracks.length, (i) => i));
    // 默认选择第一个非当前平台
    _targetSource = _getAvailableSources().firstOrNull;
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  List<MusicSource> _getAvailableSources() {
    return MusicSource.values
        .where((s) =>
            s != MusicSource.local &&
            s != MusicSource.apple &&
            s != MusicSource.navidrome &&
            s != widget.currentSource)
        .toList();
  }

  /// 根据搜索关键词过滤歌曲，返回原始索引列表
  List<int> _getFilteredIndices() {
    if (_searchQuery.isEmpty) {
      return List.generate(widget.tracks.length, (i) => i);
    }
    final query = _searchQuery.toLowerCase();
    return List.generate(widget.tracks.length, (i) => i).where((i) {
      final track = widget.tracks[i];
      return track.name.toLowerCase().contains(query) ||
          track.artists.toLowerCase().contains(query) ||
          track.album.toLowerCase().contains(query);
    }).toList();
  }

  void _onSearchChanged(String value) {
    setState(() {
      _searchQuery = value;
    });
  }

  void _toggleSelectAll() {
    setState(() {
      final filteredIndices = _getFilteredIndices();
      final allFilteredSelected = filteredIndices.every((i) => _selectedIndices.contains(i));
      
      if (allFilteredSelected) {
        // 取消选择所有过滤后的歌曲
        for (final i in filteredIndices) {
          _selectedIndices.remove(i);
        }
      } else {
        // 选择所有过滤后的歌曲
        _selectedIndices.addAll(filteredIndices);
      }
      _selectAll = _selectedIndices.length == widget.tracks.length;
    });
  }

  void _toggleTrack(int index) {
    setState(() {
      if (_selectedIndices.contains(index)) {
        _selectedIndices.remove(index);
      } else {
        _selectedIndices.add(index);
      }
      _selectAll = _selectedIndices.length == widget.tracks.length;
    });
  }

  @override
  Widget build(BuildContext context) {
    final themeManager = ThemeManager();
    if (themeManager.isFluentFramework) {
      return _buildFluentDialog(context);
    }
    return _buildMaterialDialog(context);
  }

  Widget _buildMaterialDialog(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final availableSources = _getAvailableSources();

    return AlertDialog(
      title: const Text('歌单换源'),
      content: SizedBox(
        width: 500,
        height: 500,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 平台选择
            Text('选择目标平台', style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: availableSources.map((source) {
                final isSelected = _targetSource == source;
                return ChoiceChip(
                  label: Text(_getSourceName(source)),
                  selected: isSelected,
                  onSelected: (selected) {
                    if (selected) {
                      setState(() => _targetSource = source);
                    }
                  },
                );
              }).toList(),
            ),
            const SizedBox(height: 16),
            // 搜索框
            TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: '搜索歌曲、歌手、专辑...',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _searchQuery.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: () {
                          _searchController.clear();
                          _onSearchChanged('');
                        },
                      )
                    : null,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
                filled: true,
                fillColor: colorScheme.surfaceContainerHighest.withOpacity(0.5),
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                isDense: true,
              ),
              onChanged: _onSearchChanged,
            ),
            const SizedBox(height: 12),
            // 歌曲选择标题
            Row(
              children: [
                Text('选择需要换源的歌曲', style: Theme.of(context).textTheme.titleSmall),
                const Spacer(),
                TextButton.icon(
                  onPressed: _toggleSelectAll,
                  icon: Icon(_selectAll ? Icons.check_box : Icons.check_box_outline_blank),
                  label: Text(_selectAll ? '取消全选' : '全选'),
                ),
              ],
            ),
            Builder(
              builder: (context) {
                final filteredIndices = _getFilteredIndices();
                final selectedInFiltered = filteredIndices.where((i) => _selectedIndices.contains(i)).length;
                return Text(
                  _searchQuery.isEmpty
                      ? '已选择 ${_selectedIndices.length}/${widget.tracks.length} 首'
                      : '筛选 ${filteredIndices.length} 首，已选 $selectedInFiltered 首',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                );
              },
            ),
            const SizedBox(height: 8),
            // 歌曲列表
            Expanded(
              child: Builder(
                builder: (context) {
                  final filteredIndices = _getFilteredIndices();
                  if (filteredIndices.isEmpty) {
                    return LayoutBuilder(
                      builder: (context, constraints) {
                        final compact = constraints.hasBoundedHeight && constraints.maxHeight < 160;
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
                                      size: compact ? 40 : 48,
                                      color: colorScheme.onSurfaceVariant,
                                    ),
                                    const SizedBox(height: 8),
                                    Text(
                                      '未找到匹配的歌曲',
                                      textAlign: TextAlign.center,
                                      style: TextStyle(color: colorScheme.onSurfaceVariant),
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
                  return ListView.builder(
                    itemCount: filteredIndices.length,
                    itemBuilder: (context, listIndex) {
                      final index = filteredIndices[listIndex];
                      final track = widget.tracks[index];
                      final isSelected = _selectedIndices.contains(index);
                  return ListTile(
                    leading: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Checkbox(
                          value: isSelected,
                          onChanged: (_) => _toggleTrack(index),
                        ),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(4),
                          child: CachedNetworkImage(
                            imageUrl: track.picUrl,
                            width: 40,
                            height: 40,
                            memCacheWidth: 128,
                            memCacheHeight: 128,
                            fit: BoxFit.cover,
                            errorWidget: (_, __, ___) => Container(
                              width: 40,
                              height: 40,
                              color: colorScheme.surfaceContainerHighest,
                              child: const Icon(Icons.music_note, size: 20),
                            ),
                          ),
                        ),
                      ],
                    ),
                    title: Text(
                      track.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    subtitle: Text(
                      '${track.artists} · ${track.album}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    trailing: _buildSourceBadge(track.source, colorScheme),
                    onTap: () => _toggleTrack(index),
                  );
                    },
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
        FilledButton(
          onPressed: _targetSource != null && _selectedIndices.isNotEmpty
              ? () => Navigator.pop(context, {
                    'targetSource': _targetSource,
                    'selectedTracks': _selectedIndices
                        .map((i) => widget.tracks[i])
                        .toList(),
                  })
              : null,
          child: const Text('开始换源'),
        ),
      ],
    );
  }

  Widget _buildFluentDialog(BuildContext context) {
    final theme = fluent.FluentTheme.of(context);
    final availableSources = _getAvailableSources();

    return fluent.ContentDialog(
      title: const Text('歌单换源'),
      content: SizedBox(
        width: 500,
        height: 500,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 平台选择
            Text('选择目标平台', style: theme.typography.bodyStrong),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: availableSources.map((source) {
                final isSelected = _targetSource == source;
                return fluent.ToggleButton(
                  checked: isSelected,
                  onChanged: (checked) {
                    if (checked) {
                      setState(() => _targetSource = source);
                    }
                  },
                  child: Text(_getSourceName(source)),
                );
              }).toList(),
            ),
            const SizedBox(height: 16),
            // 搜索框
            fluent.TextBox(
              controller: _searchController,
              placeholder: '搜索歌曲、歌手、专辑...',
              prefix: const Padding(
                padding: EdgeInsets.only(left: 8),
                child: Icon(fluent.FluentIcons.search, size: 16),
              ),
              suffix: _searchQuery.isNotEmpty
                  ? fluent.IconButton(
                      icon: const Icon(fluent.FluentIcons.clear, size: 12),
                      onPressed: () {
                        _searchController.clear();
                        _onSearchChanged('');
                      },
                    )
                  : null,
              onChanged: _onSearchChanged,
            ),
            const SizedBox(height: 12),
            // 歌曲选择标题
            Row(
              children: [
                Text('选择需要换源的歌曲', style: theme.typography.bodyStrong),
                const Spacer(),
                fluent.Button(
                  onPressed: _toggleSelectAll,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        _selectAll
                            ? fluent.FluentIcons.checkbox_composite
                            : fluent.FluentIcons.checkbox,
                        size: 16,
                      ),
                      const SizedBox(width: 4),
                      Text(_selectAll ? '取消全选' : '全选'),
                    ],
                  ),
                ),
              ],
            ),
            Builder(
              builder: (context) {
                final filteredIndices = _getFilteredIndices();
                final selectedInFiltered = filteredIndices.where((i) => _selectedIndices.contains(i)).length;
                return Text(
                  _searchQuery.isEmpty
                      ? '已选择 ${_selectedIndices.length}/${widget.tracks.length} 首'
                      : '筛选 ${filteredIndices.length} 首，已选 $selectedInFiltered 首',
                  style: theme.typography.caption?.copyWith(
                    color: theme.resources.textFillColorSecondary,
                  ),
                );
              },
            ),
            const SizedBox(height: 8),
            // 歌曲列表
            Expanded(
              child: Builder(
                builder: (context) {
                  final filteredIndices = _getFilteredIndices();
                  if (filteredIndices.isEmpty) {
                    return LayoutBuilder(
                      builder: (context, constraints) {
                        final compact = constraints.hasBoundedHeight && constraints.maxHeight < 160;
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
                                      fluent.FluentIcons.search,
                                      size: compact ? 40 : 48,
                                      color: theme.resources.textFillColorSecondary,
                                    ),
                                    const SizedBox(height: 8),
                                    Text(
                                      '未找到匹配的歌曲',
                                      textAlign: TextAlign.center,
                                      style: TextStyle(
                                        color: theme.resources.textFillColorSecondary,
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
                  return ListView.builder(
                    itemCount: filteredIndices.length,
                    itemBuilder: (context, listIndex) {
                      final index = filteredIndices[listIndex];
                      final track = widget.tracks[index];
                      final isSelected = _selectedIndices.contains(index);
                      return fluent.ListTile.selectable(
                        selected: isSelected,
                        onSelectionChange: (_) => _toggleTrack(index),
                        leading: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            fluent.Checkbox(
                              checked: isSelected,
                              onChanged: (_) => _toggleTrack(index),
                            ),
                            const SizedBox(width: 8),
                            ClipRRect(
                              borderRadius: BorderRadius.circular(4),
                              child: CachedNetworkImage(
                                imageUrl: track.picUrl,
                                width: 40,
                                height: 40,
                                memCacheWidth: 128,
                                memCacheHeight: 128,
                                fit: BoxFit.cover,
                                errorWidget: (_, __, ___) => Container(
                                  width: 40,
                                  height: 40,
                                  color: theme.resources.controlFillColorDefault,
                                  child: const Icon(fluent.FluentIcons.music_note, size: 20),
                                ),
                              ),
                            ),
                          ],
                        ),
                        title: Text(
                          track.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        subtitle: Text(
                          '${track.artists} · ${track.album}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        trailing: _buildFluentSourceBadge(track.source, theme),
                      );
                    },
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
        fluent.FilledButton(
          onPressed: _targetSource != null && _selectedIndices.isNotEmpty
              ? () => Navigator.pop(context, {
                    'targetSource': _targetSource,
                    'selectedTracks': _selectedIndices
                        .map((i) => widget.tracks[i])
                        .toList(),
                  })
              : null,
          child: const Text('开始换源'),
        ),
      ],
    );
  }

  Widget _buildSourceBadge(MusicSource source, ColorScheme colorScheme) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: colorScheme.primaryContainer,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        _getSourceName(source),
        style: TextStyle(
          fontSize: 10,
          color: colorScheme.onPrimaryContainer,
        ),
      ),
    );
  }

  Widget _buildFluentSourceBadge(MusicSource source, fluent.FluentThemeData theme) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: theme.accentColor.withOpacity(0.2),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        _getSourceName(source),
        style: TextStyle(
          fontSize: 10,
          color: theme.accentColor,
        ),
      ),
    );
  }

  String _getSourceName(MusicSource source) {
    switch (source) {
      case MusicSource.netease:
        return '网易云';
      case MusicSource.apple:
        return 'Apple';
      case MusicSource.qq:
        return 'QQ音乐';
      case MusicSource.kugou:
        return '酷狗';
      case MusicSource.kuwo:
        return '酷我';
      case MusicSource.navidrome:
        return 'Navidrome';
      case MusicSource.spotify:
        return 'Spotify';
      case MusicSource.local:
        return '本地';
    }
  }
}

/// 换源处理进度对话框 - 第二步：显示处理进度
class SourceSwitchProgressDialog extends StatefulWidget {
  final List<PlaylistTrack> tracks;
  final MusicSource targetSource;

  const SourceSwitchProgressDialog({
    super.key,
    required this.tracks,
    required this.targetSource,
  });

  @override
  State<SourceSwitchProgressDialog> createState() => _SourceSwitchProgressDialogState();
}

class _SourceSwitchProgressDialogState extends State<SourceSwitchProgressDialog> {
  final TrackSourceSwitchService _service = TrackSourceSwitchService();

  @override
  void initState() {
    super.initState();
    _service.addListener(_onServiceChanged);
    _startProcessing();
  }

  @override
  void dispose() {
    _service.removeListener(_onServiceChanged);
    super.dispose();
  }

  void _onServiceChanged() {
    if (mounted) setState(() {});
    
    // 处理完成后自动关闭并返回结果
    if (!_service.isProcessing && _service.results.isNotEmpty) {
      Navigator.pop(context, true);
    }
  }

  Future<void> _startProcessing() async {
    await _service.startSourceSwitch(widget.tracks, widget.targetSource);
  }

  void _cancel() {
    _service.cancel();
    Navigator.pop(context, false);
  }

  @override
  Widget build(BuildContext context) {
    final themeManager = ThemeManager();
    if (themeManager.isFluentFramework) {
      return _buildFluentDialog(context);
    }
    return _buildMaterialDialog(context);
  }

  Widget _buildMaterialDialog(BuildContext context) {
    final progress = _service.progress;
    final progressText = progress != null
        ? '正在处理 ${progress.current}/${progress.total}'
        : '准备中...';
    final trackName = progress?.currentTrackName ?? '';

    return AlertDialog(
      title: const Text('正在换源'),
      content: SizedBox(
        width: 400,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(),
            const SizedBox(height: 16),
            Text(progressText),
            if (trackName.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                trackName,
                style: Theme.of(context).textTheme.bodySmall,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
            if (progress != null) ...[
              const SizedBox(height: 16),
              LinearProgressIndicator(value: progress.percentage),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _cancel,
          child: const Text('取消'),
        ),
      ],
    );
  }

  Widget _buildFluentDialog(BuildContext context) {
    final progress = _service.progress;
    final progressText = progress != null
        ? '正在处理 ${progress.current}/${progress.total}'
        : '准备中...';
    final trackName = progress?.currentTrackName ?? '';
    final theme = fluent.FluentTheme.of(context);

    return fluent.ContentDialog(
      title: const Text('正在换源'),
      content: SizedBox(
        width: 400,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const fluent.ProgressRing(),
            const SizedBox(height: 16),
            Text(progressText),
            if (trackName.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                trackName,
                style: theme.typography.caption,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
            if (progress != null) ...[
              const SizedBox(height: 16),
              fluent.ProgressBar(value: progress.percentage * 100),
            ],
          ],
        ),
      ),
      actions: [
        fluent.Button(
          onPressed: _cancel,
          child: const Text('取消'),
        ),
      ],
    );
  }
}

/// 换源结果选择对话框 - 第三步：选择匹配结果
class SourceSwitchResultDialog extends StatefulWidget {
  const SourceSwitchResultDialog({super.key});

  @override
  State<SourceSwitchResultDialog> createState() => _SourceSwitchResultDialogState();
}

class _SourceSwitchResultDialogState extends State<SourceSwitchResultDialog> {
  final TrackSourceSwitchService _service = TrackSourceSwitchService();
  final Set<int> _selectedIndices = {};
  bool _selectAll = true;

  @override
  void initState() {
    super.initState();
    _service.addListener(_onServiceChanged);
    // 默认选中所有有结果的项
    for (int i = 0; i < _service.results.length; i++) {
      if (_service.results[i].selectedTrack != null) {
        _selectedIndices.add(i);
      }
    }
    _updateSelectAllState();
  }

  @override
  void dispose() {
    _service.removeListener(_onServiceChanged);
    super.dispose();
  }

  void _onServiceChanged() {
    if (mounted) setState(() {});
  }

  void _updateSelectAllState() {
    final validCount = _service.results.where((r) => r.selectedTrack != null).length;
    _selectAll = _selectedIndices.length == validCount && validCount > 0;
  }

  void _toggleSelectAll() {
    setState(() {
      if (_selectAll) {
        _selectedIndices.clear();
      } else {
        _selectedIndices.clear();
        for (int i = 0; i < _service.results.length; i++) {
          if (_service.results[i].selectedTrack != null) {
            _selectedIndices.add(i);
          }
        }
      }
      _updateSelectAllState();
    });
  }

  void _toggleItem(int index) {
    setState(() {
      if (_selectedIndices.contains(index)) {
        _selectedIndices.remove(index);
      } else {
        if (_service.results[index].selectedTrack != null) {
          _selectedIndices.add(index);
        }
      }
      _updateSelectAllState();
    });
  }

  void _changeSelectedTrack(int index, Track track) {
    _service.updateSelectedTrack(index, track);
    if (!_selectedIndices.contains(index)) {
      setState(() {
        _selectedIndices.add(index);
        _updateSelectAllState();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final themeManager = ThemeManager();
    if (themeManager.isFluentFramework) {
      return _buildFluentDialog(context);
    }
    return _buildMaterialDialog(context);
  }

  Widget _buildMaterialDialog(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final results = _service.results;
    final validCount = results.where((r) => r.selectedTrack != null).length;

    return AlertDialog(
      title: const Text('选择换源结果'),
      content: SizedBox(
        width: 700,
        height: 500,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  '已匹配 $validCount/${results.length} 首',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
                const Spacer(),
                TextButton.icon(
                  onPressed: _toggleSelectAll,
                  icon: Icon(_selectAll ? Icons.check_box : Icons.check_box_outline_blank),
                  label: Text(_selectAll ? '取消全选' : '全选'),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Expanded(
              child: ListView.builder(
                itemCount: results.length,
                itemBuilder: (context, index) {
                  final result = results[index];
                  return _buildResultItem(context, index, result, colorScheme);
                },
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () {
            _service.clear();
            Navigator.pop(context);
          },
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: _selectedIndices.isNotEmpty
              ? () {
                  final selected = _selectedIndices
                      .map((i) => MapEntry(
                            results[i].originalTrack,
                            results[i].selectedTrack!,
                          ))
                      .toList();
                  Navigator.pop(context, selected);
                }
              : null,
          child: Text('确认换源 (${_selectedIndices.length})'),
        ),
      ],
    );
  }

  Widget _buildResultItem(
    BuildContext context,
    int index,
    SourceSwitchResult result,
    ColorScheme colorScheme,
  ) {
    final isSelected = _selectedIndices.contains(index);
    final hasResult = result.selectedTrack != null;
    final original = result.originalTrack;

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      color: isSelected ? colorScheme.primaryContainer.withOpacity(0.3) : null,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 原始歌曲
            Row(
              children: [
                Checkbox(
                  value: isSelected,
                  onChanged: hasResult ? (_) => _toggleItem(index) : null,
                ),
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: CachedNetworkImage(
                    imageUrl: original.picUrl,
                    width: 48,
                    height: 48,
                    memCacheWidth: 128,
                    memCacheHeight: 128,
                    fit: BoxFit.cover,
                    errorWidget: (_, __, ___) => Container(
                      width: 48,
                      height: 48,
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
                      Text(
                        '原: ${original.name}',
                        style: const TextStyle(fontWeight: FontWeight.bold),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      Text(
                        '${original.artists} · ${original.album}',
                        style: Theme.of(context).textTheme.bodySmall,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                _buildSourceBadge(original.source, colorScheme),
              ],
            ),
            const Divider(height: 16),
            // 搜索结果
            if (result.error != null)
              Text(
                '搜索失败: ${result.error}',
                style: TextStyle(color: colorScheme.error),
              )
            else if (result.searchResults.isEmpty)
              Text(
                '未找到匹配结果',
                style: TextStyle(color: colorScheme.onSurfaceVariant),
              )
            else
              _buildSearchResultsDropdown(context, index, result, colorScheme),
          ],
        ),
      ),
    );
  }

  Widget _buildSearchResultsDropdown(
    BuildContext context,
    int index,
    SourceSwitchResult result,
    ColorScheme colorScheme,
  ) {
    final selected = result.selectedTrack;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '换源到:',
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
            color: colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 8),
        ...result.searchResults.map((track) {
          final isTrackSelected = selected?.id == track.id;
          return InkWell(
            onTap: () => _changeSelectedTrack(index, track),
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 8),
              margin: const EdgeInsets.only(bottom: 4),
              decoration: BoxDecoration(
                color: isTrackSelected
                    ? colorScheme.primaryContainer.withOpacity(0.5)
                    : colorScheme.surfaceContainerHighest.withOpacity(0.3),
                borderRadius: BorderRadius.circular(8),
                border: isTrackSelected
                    ? Border.all(color: colorScheme.primary, width: 2)
                    : null,
              ),
              child: Row(
                children: [
                  Radio<dynamic>(
                    value: track.id,
                    groupValue: selected?.id,
                    onChanged: (_) => _changeSelectedTrack(index, track),
                  ),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: CachedNetworkImage(
                      imageUrl: track.picUrl,
                      width: 40,
                      height: 40,
                      memCacheWidth: 128,
                      memCacheHeight: 128,
                      fit: BoxFit.cover,
                      errorWidget: (_, __, ___) => Container(
                        width: 40,
                        height: 40,
                        color: colorScheme.surfaceContainerHighest,
                        child: const Icon(Icons.music_note, size: 20),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          track.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontWeight: isTrackSelected ? FontWeight.bold : null,
                          ),
                        ),
                        Text(
                          '${track.artists} · ${track.album}',
                          style: Theme.of(context).textTheme.bodySmall,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          );
        }),
      ],
    );
  }

  Widget _buildSourceBadge(MusicSource source, ColorScheme colorScheme) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: colorScheme.primaryContainer,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        _getSourceName(source),
        style: TextStyle(
          fontSize: 10,
          color: colorScheme.onPrimaryContainer,
        ),
      ),
    );
  }

  Widget _buildFluentDialog(BuildContext context) {
    final theme = fluent.FluentTheme.of(context);
    final results = _service.results;
    final validCount = results.where((r) => r.selectedTrack != null).length;

    return fluent.ContentDialog(
      title: const Text('选择换源结果'),
      content: SizedBox(
        width: 700,
        height: 500,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  '已匹配 $validCount/${results.length} 首',
                  style: theme.typography.caption?.copyWith(
                    color: theme.resources.textFillColorSecondary,
                  ),
                ),
                const Spacer(),
                fluent.Button(
                  onPressed: _toggleSelectAll,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        _selectAll
                            ? fluent.FluentIcons.checkbox_composite
                            : fluent.FluentIcons.checkbox,
                        size: 16,
                      ),
                      const SizedBox(width: 4),
                      Text(_selectAll ? '取消全选' : '全选'),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Expanded(
              child: ListView.builder(
                itemCount: results.length,
                itemBuilder: (context, index) {
                  final result = results[index];
                  return _buildFluentResultItem(context, index, result, theme);
                },
              ),
            ),
          ],
        ),
      ),
      actions: [
        fluent.Button(
          onPressed: () {
            _service.clear();
            Navigator.pop(context);
          },
          child: const Text('取消'),
        ),
        fluent.FilledButton(
          onPressed: _selectedIndices.isNotEmpty
              ? () {
                  final selected = _selectedIndices
                      .map((i) => MapEntry(
                            results[i].originalTrack,
                            results[i].selectedTrack!,
                          ))
                      .toList();
                  Navigator.pop(context, selected);
                }
              : null,
          child: Text('确认换源 (${_selectedIndices.length})'),
        ),
      ],
    );
  }

  Widget _buildFluentResultItem(
    BuildContext context,
    int index,
    SourceSwitchResult result,
    fluent.FluentThemeData theme,
  ) {
    final isSelected = _selectedIndices.contains(index);
    final hasResult = result.selectedTrack != null;
    final original = result.originalTrack;

    return fluent.Card(
      margin: const EdgeInsets.only(bottom: 8),
      backgroundColor: isSelected
          ? theme.accentColor.withOpacity(0.1)
          : null,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 原始歌曲
            Row(
              children: [
                fluent.Checkbox(
                  checked: isSelected,
                  onChanged: hasResult ? (_) => _toggleItem(index) : null,
                ),
                const SizedBox(width: 8),
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: CachedNetworkImage(
                    imageUrl: original.picUrl,
                    width: 48,
                    height: 48,
                    memCacheWidth: 128,
                    memCacheHeight: 128,
                    fit: BoxFit.cover,
                    errorWidget: (_, __, ___) => Container(
                      width: 48,
                      height: 48,
                      color: theme.resources.controlFillColorDefault,
                      child: const Icon(fluent.FluentIcons.music_note),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '原: ${original.name}',
                        style: theme.typography.bodyStrong,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      Text(
                        '${original.artists} · ${original.album}',
                        style: theme.typography.caption,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                _buildFluentSourceBadge(original.source, theme),
              ],
            ),
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 8),
              child: fluent.Divider(),
            ),
            // 搜索结果
            if (result.error != null)
              Text(
                '处理失败: ${result.error}',
                style: TextStyle(color: Colors.red),
              )
            else if (result.searchResults.isEmpty)
              Text(
                '未找到匹配结果',
                style: theme.typography.caption?.copyWith(
                  color: theme.resources.textFillColorSecondary,
                ),
              )
            else
              _buildFluentSearchResultsDropdown(context, index, result, theme),
          ],
        ),
      ),
    );
  }

  Widget _buildFluentSearchResultsDropdown(
    BuildContext context,
    int index,
    SourceSwitchResult result,
    fluent.FluentThemeData theme,
  ) {
    final selected = result.selectedTrack;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '换源到:',
          style: theme.typography.caption?.copyWith(
            color: theme.resources.textFillColorSecondary,
          ),
        ),
        const SizedBox(height: 8),
        ...result.searchResults.map((track) {
          final isTrackSelected = selected?.id == track.id;
          return fluent.GestureDetector(
            onTap: () => _changeSelectedTrack(index, track),
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 8),
              margin: const EdgeInsets.only(bottom: 4),
              decoration: BoxDecoration(
                color: isTrackSelected
                    ? theme.accentColor.withOpacity(0.2)
                    : theme.resources.controlFillColorDefault,
                borderRadius: BorderRadius.circular(8),
                border: isTrackSelected
                    ? Border.all(color: theme.accentColor, width: 2)
                    : null,
              ),
              child: Row(
                children: [
                  fluent.RadioButton(
                    checked: isTrackSelected,
                    onChanged: (checked) {
                      if (checked) _changeSelectedTrack(index, track);
                    },
                  ),
                  const SizedBox(width: 8),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: CachedNetworkImage(
                      imageUrl: track.picUrl,
                      width: 40,
                      height: 40,
                      memCacheWidth: 128,
                      memCacheHeight: 128,
                      fit: BoxFit.cover,
                      errorWidget: (_, __, ___) => Container(
                        width: 40,
                        height: 40,
                        color: theme.resources.controlFillColorDefault,
                        child: const Icon(fluent.FluentIcons.music_note, size: 20),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          track.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: isTrackSelected
                              ? theme.typography.bodyStrong
                              : theme.typography.body,
                        ),
                        Text(
                          '${track.artists} · ${track.album}',
                          style: theme.typography.caption,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          );
        }),
      ],
    );
  }

  Widget _buildFluentSourceBadge(MusicSource source, fluent.FluentThemeData theme) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: theme.accentColor.withOpacity(0.2),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        _getSourceName(source),
        style: TextStyle(
          fontSize: 10,
          color: theme.accentColor,
        ),
      ),
    );
  }

  String _getSourceName(MusicSource source) {
    switch (source) {
      case MusicSource.netease:
        return '网易云';
      case MusicSource.apple:
        return 'Apple';
      case MusicSource.qq:
        return 'QQ音乐';
      case MusicSource.kugou:
        return '酷狗';
      case MusicSource.kuwo:
        return '酷我';
      case MusicSource.navidrome:
        return 'Navidrome';
      case MusicSource.spotify:
        return 'Spotify';      case MusicSource.local:
        return '本地';
    }
  }
}

