import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:fluent_ui/fluent_ui.dart' as fluent;
import '../services/music_taste_service.dart';
import '../services/playlist_service.dart';
import '../utils/theme_manager.dart';

/// 听歌品味总结对话框
/// 支持 Material、Fluent UI、Cupertino 三种主题
class MusicTasteDialog extends StatefulWidget {
  const MusicTasteDialog({super.key});

  /// 显示对话框的静态方法
  static Future<void> show(BuildContext context) async {
    final themeManager = ThemeManager();
    
    if (themeManager.isFluentFramework) {
      await fluent.showDialog(
        context: context,
        barrierDismissible: true,
        builder: (context) => const MusicTasteDialog(),
      );
    } else if (themeManager.isCupertinoFramework) {
      await showCupertinoDialog(
        context: context,
        barrierDismissible: true,
        builder: (context) => const MusicTasteDialog(),
      );
    } else {
      await showDialog(
        context: context,
        barrierDismissible: true,
        builder: (context) => const MusicTasteDialog(),
      );
    }
  }

  @override
  State<MusicTasteDialog> createState() => _MusicTasteDialogState();
}

class _MusicTasteDialogState extends State<MusicTasteDialog> {
  final PlaylistService _playlistService = PlaylistService();
  final MusicTasteService _tasteService = MusicTasteService();
  final ThemeManager _themeManager = ThemeManager();
  final ScrollController _scrollController = ScrollController();

  MusicTasteMode _mode = MusicTasteMode.professional;

  // 选中的歌单
  final Set<int> _selectedPlaylistIds = {};
  
  // 当前步骤：0=选择歌单，1=生成中/显示结果
  int _currentStep = 0;

  @override
  void initState() {
    super.initState();
    _tasteService.addListener(_onTasteServiceChanged);
    _tasteService.reset();
  }

  @override
  void dispose() {
    _tasteService.removeListener(_onTasteServiceChanged);
    _scrollController.dispose();
    super.dispose();
  }

  void _onTasteServiceChanged() {
    if (mounted) {
      setState(() {});
      // 自动滚动到底部
      if (_tasteService.isStreaming && _scrollController.hasClients) {
        Future.delayed(const Duration(milliseconds: 50), () {
          if (_scrollController.hasClients) {
            _scrollController.animateTo(
              _scrollController.position.maxScrollExtent,
              duration: const Duration(milliseconds: 100),
              curve: Curves.easeOut,
            );
          }
        });
      }
    }
  }

  void _togglePlaylistSelection(int playlistId) {
    setState(() {
      if (_selectedPlaylistIds.contains(playlistId)) {
        _selectedPlaylistIds.remove(playlistId);
      } else {
        _selectedPlaylistIds.add(playlistId);
      }
    });
  }

  Future<void> _startGeneration() async {
    if (_selectedPlaylistIds.isEmpty) return;

    final selectedPlaylists = _playlistService.playlists
        .where((p) => _selectedPlaylistIds.contains(p.id))
        .toList();

    setState(() => _currentStep = 1);
    
    await _tasteService.generateTasteSummary(selectedPlaylists, mode: _mode);
  }

  void _reset() {
    setState(() {
      _currentStep = 0;
      _selectedPlaylistIds.clear();
    });
    _tasteService.reset();
  }

  @override
  Widget build(BuildContext context) {
    if (_themeManager.isFluentFramework) {
      return _buildFluentDialog(context);
    } else if (_themeManager.isCupertinoFramework) {
      return _buildCupertinoDialog(context);
    } else {
      return _buildMaterialDialog(context);
    }
  }

  // ==================== Material Design ====================

  Widget _buildMaterialDialog(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final size = MediaQuery.of(context).size;
    
    return Dialog(
      child: Container(
        width: size.width * 0.9,
        height: size.height * 0.8,
        constraints: const BoxConstraints(maxWidth: 600, maxHeight: 700),
        child: Column(
          children: [
            // 标题栏
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: colorScheme.primaryContainer,
                borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
              ),
              child: Row(
                children: [
                  Icon(Icons.auto_awesome, color: colorScheme.onPrimaryContainer),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      _currentStep == 0 ? '听歌品味总结' : '品味分析报告',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: colorScheme.onPrimaryContainer,
                      ),
                    ),
                  ),
                  IconButton(
                    icon: Icon(Icons.close, color: colorScheme.onPrimaryContainer),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
            ),
            // 内容区域
            Expanded(
              child: _currentStep == 0
                  ? _buildMaterialPlaylistSelection(colorScheme)
                  : _buildMaterialResultView(colorScheme),
            ),
            // 底部按钮
            _buildMaterialBottomBar(colorScheme),
          ],
        ),
      ),
    );
  }

  Widget _buildMaterialPlaylistSelection(ColorScheme colorScheme) {
    final playlists = _playlistService.playlists;

    if (playlists.isEmpty) {
      return LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.hasBoundedHeight && constraints.maxHeight < 180;
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
                        Icons.library_music_outlined,
                        size: compact ? 52 : 64,
                        color: colorScheme.onSurface.withOpacity(0.3),
                      ),
                      SizedBox(height: compact ? 10 : 16),
                      Text(
                        '暂无歌单',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: colorScheme.onSurface.withOpacity(0.6)),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        '请先创建或导入歌单',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 12,
                          color: colorScheme.onSurface.withOpacity(0.5),
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

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '选择要分析的歌单（可多选）',
                style: TextStyle(color: colorScheme.onSurface.withOpacity(0.7)),
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  ChoiceChip(
                    label: Text(MusicTasteMode.professional.displayName),
                    selected: _mode == MusicTasteMode.professional,
                    onSelected: (_) => setState(() => _mode = MusicTasteMode.professional),
                  ),
                  ChoiceChip(
                    label: Text(MusicTasteMode.tieba.displayName),
                    selected: _mode == MusicTasteMode.tieba,
                    onSelected: (_) => setState(() => _mode = MusicTasteMode.tieba),
                  ),
                ],
              ),
            ],
          ),
        ),
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: playlists.length,
            itemBuilder: (context, index) {
              final playlist = playlists[index];
              final isSelected = _selectedPlaylistIds.contains(playlist.id);

              return Card(
                margin: const EdgeInsets.only(bottom: 8),
                color: isSelected ? colorScheme.primaryContainer.withOpacity(0.3) : null,
                child: ListTile(
                  leading: Checkbox(
                    value: isSelected,
                    onChanged: (_) => _togglePlaylistSelection(playlist.id),
                  ),
                  title: Text(playlist.name),
                  subtitle: Text('${playlist.trackCount} 首歌曲'),
                  trailing: isSelected ? Icon(Icons.check_circle, color: colorScheme.primary) : null,
                  onTap: () => _togglePlaylistSelection(playlist.id),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildMaterialResultView(ColorScheme colorScheme) {
    if (_tasteService.error.isNotEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.error_outline, size: 64, color: Colors.redAccent),
            const SizedBox(height: 16),
            Text(_tasteService.error, style: const TextStyle(color: Colors.redAccent)),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: _reset,
              icon: const Icon(Icons.refresh),
              label: const Text('重试'),
            ),
          ],
        ),
      );
    }

    if (_tasteService.result.isEmpty && _tasteService.isLoading) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const CircularProgressIndicator(),
            const SizedBox(height: 24),
            Text('正在分析你的音乐品味...', style: TextStyle(color: colorScheme.onSurface.withOpacity(0.7))),
            const SizedBox(height: 8),
            Text('这可能需要一点时间', style: TextStyle(fontSize: 12, color: colorScheme.onSurface.withOpacity(0.5))),
          ],
        ),
      );
    }

    return SingleChildScrollView(
      controller: _scrollController,
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildReadmeFormattedContent(
            context,
            _tasteService.result,
            baseStyle: TextStyle(
              fontSize: 15,
              height: 1.6,
              color: colorScheme.onSurface,
            ),
            headingColor: colorScheme.onSurface,
            codeBackgroundColor: colorScheme.surfaceContainerHighest,
            codeBorderColor: colorScheme.outlineVariant,
          ),
          if (_tasteService.isStreaming) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2, color: colorScheme.primary),
                ),
                const SizedBox(width: 8),
                Text('生成中...', style: TextStyle(color: colorScheme.onSurface.withOpacity(0.5))),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildMaterialBottomBar(ColorScheme colorScheme) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: colorScheme.outlineVariant)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          if (_currentStep == 1 && !_tasteService.isLoading) ...[
            TextButton.icon(
              onPressed: _reset,
              icon: const Icon(Icons.refresh),
              label: const Text('重新选择'),
            ),
            const SizedBox(width: 8),
          ],
          if (_currentStep == 0)
            FilledButton.icon(
              onPressed: _selectedPlaylistIds.isEmpty ? null : _startGeneration,
              icon: const Icon(Icons.auto_awesome),
              label: Text('分析 ${_selectedPlaylistIds.isEmpty ? "" : "(${_selectedPlaylistIds.length})"}'),
            ),
          if (_currentStep == 1 && !_tasteService.isLoading)
            FilledButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('完成'),
            ),
        ],
      ),
    );
  }

  // ==================== Fluent UI ====================

  Widget _buildFluentDialog(BuildContext context) {
    final theme = fluent.FluentTheme.of(context);
    final size = MediaQuery.of(context).size;

    return fluent.ContentDialog(
      constraints: BoxConstraints(
        maxWidth: 600,
        maxHeight: size.height * 0.8,
      ),
      title: Row(
        children: [
          Icon(fluent.FluentIcons.auto_enhance_on, color: theme.accentColor),
          const SizedBox(width: 12),
          Text(_currentStep == 0 ? '听歌品味总结' : '品味分析报告'),
        ],
      ),
      content: SizedBox(
        width: 550,
        height: size.height * 0.6,
        child: _currentStep == 0
            ? _buildFluentPlaylistSelection(theme)
            : _buildFluentResultView(theme),
      ),
      actions: [
        if (_currentStep == 1 && !_tasteService.isLoading)
          fluent.Button(
            onPressed: _reset,
            child: const Text('重新选择'),
          ),
        if (_currentStep == 0)
          fluent.FilledButton(
            onPressed: _selectedPlaylistIds.isEmpty ? null : _startGeneration,
            child: Text('分析 ${_selectedPlaylistIds.isEmpty ? "" : "(${_selectedPlaylistIds.length})"}'),
          ),
        if (_currentStep == 1 && !_tasteService.isLoading)
          fluent.FilledButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('完成'),
          ),
        if (_currentStep == 1 && _tasteService.isLoading)
          fluent.Button(
            onPressed: null,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(
                  width: 16,
                  height: 16,
                  child: fluent.ProgressRing(strokeWidth: 2),
                ),
                const SizedBox(width: 8),
                const Text('生成中...'),
              ],
            ),
          ),
      ],
    );
  }

  Widget _buildFluentPlaylistSelection(fluent.FluentThemeData theme) {
    final playlists = _playlistService.playlists;

    if (playlists.isEmpty) {
      return LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.hasBoundedHeight && constraints.maxHeight < 180;
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
                        fluent.FluentIcons.music_in_collection,
                        size: compact ? 52 : 64,
                        color: theme.resources.textFillColorSecondary,
                      ),
                      SizedBox(height: compact ? 10 : 16),
                      Text(
                        '暂无歌单',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: theme.resources.textFillColorSecondary),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        '请先创建或导入歌单',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 12,
                          color: theme.resources.textFillColorTertiary,
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

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '选择要分析的歌单（可多选）',
          style: TextStyle(color: theme.resources.textFillColorSecondary),
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            fluent.RadioButton(
              checked: _mode == MusicTasteMode.professional,
              onChanged: (v) {
                if (v == true) setState(() => _mode = MusicTasteMode.professional);
              },
              content: Text(MusicTasteMode.professional.displayName),
            ),
            fluent.RadioButton(
              checked: _mode == MusicTasteMode.tieba,
              onChanged: (v) {
                if (v == true) setState(() => _mode = MusicTasteMode.tieba);
              },
              content: Text(MusicTasteMode.tieba.displayName),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Expanded(
          child: ListView.builder(
            itemCount: playlists.length,
            itemBuilder: (context, index) {
              final playlist = playlists[index];
              final isSelected = _selectedPlaylistIds.contains(playlist.id);

              return Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: fluent.Card(
                  backgroundColor: isSelected ? theme.accentColor.withOpacity(0.1) : null,
                  child: fluent.ListTile(
                    leading: fluent.Checkbox(
                      checked: isSelected,
                      onChanged: (_) => _togglePlaylistSelection(playlist.id),
                    ),
                    title: Text(playlist.name),
                    subtitle: Text('${playlist.trackCount} 首歌曲'),
                    trailing: isSelected ? Icon(fluent.FluentIcons.check_mark, color: theme.accentColor) : null,
                    onPressed: () => _togglePlaylistSelection(playlist.id),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildFluentResultView(fluent.FluentThemeData theme) {
    if (_tasteService.error.isNotEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(fluent.FluentIcons.error_badge, size: 64, color: Colors.redAccent),
            const SizedBox(height: 16),
            Text(_tasteService.error, style: const TextStyle(color: Colors.redAccent)),
          ],
        ),
      );
    }

    if (_tasteService.result.isEmpty && _tasteService.isLoading) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const fluent.ProgressRing(),
            const SizedBox(height: 24),
            Text('正在分析你的音乐品味...', style: TextStyle(color: theme.resources.textFillColorSecondary)),
            const SizedBox(height: 8),
            Text('这可能需要一点时间', style: TextStyle(fontSize: 12, color: theme.resources.textFillColorTertiary)),
          ],
        ),
      );
    }

    return SingleChildScrollView(
      controller: _scrollController,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildReadmeFormattedContent(
            context,
            _tasteService.result,
            baseStyle: TextStyle(
              fontSize: 14,
              height: 1.6,
              color: theme.resources.textFillColorPrimary,
            ),
            headingColor: theme.resources.textFillColorPrimary,
            codeBackgroundColor: theme.resources.controlFillColorDefault,
            codeBorderColor: theme.resources.controlStrokeColorDefault,
          ),
          if (_tasteService.isStreaming) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                SizedBox(
                  width: 16,
                  height: 16,
                  child: fluent.ProgressRing(strokeWidth: 2, activeColor: theme.accentColor),
                ),
                const SizedBox(width: 8),
                Text('生成中...', style: TextStyle(color: theme.resources.textFillColorSecondary)),
              ],
            ),
          ],
        ],
      ),
    );
  }

  // ==================== Cupertino ====================

  Widget _buildCupertinoDialog(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final brightness = CupertinoTheme.brightnessOf(context);
    final isDark = brightness == Brightness.dark;

    return Center(
      child: Material(
        type: MaterialType.transparency,
        child: Container(
        width: size.width * 0.9,
        height: size.height * 0.8,
        constraints: const BoxConstraints(maxWidth: 500, maxHeight: 600),
        decoration: BoxDecoration(
          color: isDark ? CupertinoColors.darkBackgroundGray : CupertinoColors.white,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Column(
          children: [
            // 标题栏
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                border: Border(
                  bottom: BorderSide(
                    color: isDark ? CupertinoColors.systemGrey : CupertinoColors.systemGrey4,
                    width: 0.5,
                  ),
                ),
              ),
              child: Row(
                children: [
                  CupertinoButton(
                    padding: EdgeInsets.zero,
                    onPressed: () => Navigator.pop(context),
                    child: const Text('关闭'),
                  ),
                  Expanded(
                    child: Text(
                      _currentStep == 0 ? '听歌品味总结' : '品味分析报告',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  if (_currentStep == 0)
                    CupertinoButton(
                      padding: EdgeInsets.zero,
                      onPressed: _selectedPlaylistIds.isEmpty ? null : _startGeneration,
                      child: Text(
                        '分析',
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          color: _selectedPlaylistIds.isEmpty
                              ? CupertinoColors.systemGrey
                              : CupertinoColors.activeBlue,
                        ),
                      ),
                    )
                  else if (!_tasteService.isLoading)
                    CupertinoButton(
                      padding: EdgeInsets.zero,
                      onPressed: _reset,
                      child: const Text('重选'),
                    )
                  else
                    const SizedBox(width: 60),
                ],
              ),
            ),
            // 内容区域
            Expanded(
              child: _currentStep == 0
                  ? _buildCupertinoPlaylistSelection(isDark)
                  : _buildCupertinoResultView(isDark),
            ),
          ],
        ),
      ),
      ),
    );
  }

  Widget _buildCupertinoPlaylistSelection(bool isDark) {
    final playlists = _playlistService.playlists;

    if (playlists.isEmpty) {
      return LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.hasBoundedHeight && constraints.maxHeight < 180;
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
                        CupertinoIcons.music_albums,
                        size: compact ? 52 : 64,
                        color: CupertinoColors.systemGrey,
                      ),
                      SizedBox(height: compact ? 10 : 16),
                      const Text(
                        '暂无歌单',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: CupertinoColors.systemGrey),
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        '请先创建或导入歌单',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 12,
                          color: CupertinoColors.systemGrey2,
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

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '选择要分析的歌单（可多选）',
                style: TextStyle(
                  fontSize: 13,
                  color: CupertinoColors.systemGrey,
                ),
              ),
              const SizedBox(height: 12),
              CupertinoSlidingSegmentedControl<MusicTasteMode>(
                groupValue: _mode,
                onValueChanged: (v) {
                  if (v != null) setState(() => _mode = v);
                },
                children: {
                  MusicTasteMode.professional: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    child: Text(MusicTasteMode.professional.displayName),
                  ),
                  MusicTasteMode.tieba: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    child: Text(MusicTasteMode.tieba.displayName),
                  ),
                },
              ),
            ],
          ),
        ),
        Expanded(
          child: CupertinoScrollbar(
            child: ListView.builder(
              itemCount: playlists.length,
              itemBuilder: (context, index) {
                final playlist = playlists[index];
                final isSelected = _selectedPlaylistIds.contains(playlist.id);

                return CupertinoListTile(
                  backgroundColor: isSelected ? CupertinoColors.activeBlue.withOpacity(0.1) : null,
                  leading: Icon(
                    isSelected ? CupertinoIcons.checkmark_circle_fill : CupertinoIcons.circle,
                    color: isSelected ? CupertinoColors.activeBlue : CupertinoColors.systemGrey,
                  ),
                  title: Text(playlist.name),
                  subtitle: Text('${playlist.trackCount} 首歌曲'),
                  onTap: () => _togglePlaylistSelection(playlist.id),
                );
              },
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildCupertinoResultView(bool isDark) {
    if (_tasteService.error.isNotEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(CupertinoIcons.exclamationmark_circle, size: 64, color: CupertinoColors.destructiveRed),
            const SizedBox(height: 16),
            Text(_tasteService.error, style: const TextStyle(color: CupertinoColors.destructiveRed)),
          ],
        ),
      );
    }

    if (_tasteService.result.isEmpty && _tasteService.isLoading) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const CupertinoActivityIndicator(radius: 16),
            const SizedBox(height: 24),
            Text('正在分析你的音乐品味...', style: TextStyle(color: CupertinoColors.systemGrey)),
            const SizedBox(height: 8),
            Text('这可能需要一点时间', style: TextStyle(fontSize: 12, color: CupertinoColors.systemGrey2)),
          ],
        ),
      );
    }

    return CupertinoScrollbar(
      controller: _scrollController,
      child: SingleChildScrollView(
        controller: _scrollController,
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildReadmeFormattedContent(
              context,
              _tasteService.result,
              baseStyle: TextStyle(
                fontSize: 15,
                height: 1.6,
                color: isDark ? CupertinoColors.white : CupertinoColors.black,
              ),
              headingColor: isDark ? CupertinoColors.white : CupertinoColors.black,
              codeBackgroundColor: (isDark ? CupertinoColors.systemGrey6.darkColor : CupertinoColors.systemGrey6)
                  .withOpacity(isDark ? 0.25 : 0.6),
              codeBorderColor: (isDark ? CupertinoColors.systemGrey4.darkColor : CupertinoColors.systemGrey4)
                  .withOpacity(isDark ? 0.5 : 0.8),
            ),
            if (_tasteService.isStreaming) ...[
              const SizedBox(height: 8),
              Row(
                children: [
                  const CupertinoActivityIndicator(radius: 8),
                  const SizedBox(width: 8),
                  Text('生成中...', style: TextStyle(color: CupertinoColors.systemGrey)),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildReadmeFormattedContent(
    BuildContext context,
    String raw, {
    required TextStyle baseStyle,
    required Color headingColor,
    required Color codeBackgroundColor,
    required Color codeBorderColor,
  }) {
    final text = raw.trimRight();
    if (text.isEmpty) {
      return const SizedBox.shrink();
    }

    final boldStyle = baseStyle.copyWith(fontWeight: FontWeight.w600);
    final codeInlineStyle = baseStyle.copyWith(
      fontFamily: 'monospace',
      fontSize: (baseStyle.fontSize ?? 14) - 1,
    );

    final h1 = baseStyle.copyWith(
      fontSize: (baseStyle.fontSize ?? 14) + 7,
      height: 1.25,
      fontWeight: FontWeight.w700,
      color: headingColor,
    );
    final h2 = baseStyle.copyWith(
      fontSize: (baseStyle.fontSize ?? 14) + 4,
      height: 1.3,
      fontWeight: FontWeight.w700,
      color: headingColor,
    );
    final h3 = baseStyle.copyWith(
      fontSize: (baseStyle.fontSize ?? 14) + 2,
      height: 1.3,
      fontWeight: FontWeight.w700,
      color: headingColor,
    );

    final blocks = _parseReadmeBlocks(text);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final block in blocks) ...[
          switch (block.type) {
            _ReadmeBlockType.heading1 => SelectableText(block.content, style: h1),
            _ReadmeBlockType.heading2 => SelectableText(block.content, style: h2),
            _ReadmeBlockType.heading3 => SelectableText(block.content, style: h3),
            _ReadmeBlockType.paragraph => SelectableText.rich(
                TextSpan(
                  style: baseStyle,
                  children: _parseInlineSpans(
                    block.content,
                    baseStyle: baseStyle,
                    boldStyle: boldStyle,
                    codeStyle: codeInlineStyle,
                  ),
                ),
              ),
            _ReadmeBlockType.listItem => Padding(
                padding: const EdgeInsets.only(left: 2),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: EdgeInsets.only(top: (baseStyle.fontSize ?? 14) * 0.35),
                      child: Text(block.marker ?? '•', style: baseStyle),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: SelectableText.rich(
                        TextSpan(
                          style: baseStyle,
                          children: _parseInlineSpans(
                            block.content,
                            baseStyle: baseStyle,
                            boldStyle: boldStyle,
                            codeStyle: codeInlineStyle,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            _ReadmeBlockType.codeBlock => Container(
                width: double.infinity,
                margin: const EdgeInsets.only(top: 4),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: codeBackgroundColor,
                  border: Border.all(color: codeBorderColor),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: SelectableText(
                    block.content,
                    style: baseStyle.copyWith(
                      fontFamily: 'monospace',
                      fontSize: (baseStyle.fontSize ?? 14) - 1,
                      height: 1.45,
                    ),
                  ),
                ),
              ),
          },
          const SizedBox(height: 10),
        ],
      ],
    );
  }

  List<_ReadmeBlock> _parseReadmeBlocks(String text) {
    final lines = text.replaceAll('\r\n', '\n').split('\n');
    final blocks = <_ReadmeBlock>[];

    final paragraphBuffer = <String>[];
    void flushParagraph() {
      final content = paragraphBuffer.join('\n').trimRight();
      if (content.isNotEmpty) {
        blocks.add(_ReadmeBlock(_ReadmeBlockType.paragraph, content));
      }
      paragraphBuffer.clear();
    }

    bool inCode = false;
    final codeBuffer = <String>[];

    for (final rawLine in lines) {
      final line = rawLine;

      if (line.trim().startsWith('```')) {
        if (inCode) {
          blocks.add(_ReadmeBlock(_ReadmeBlockType.codeBlock, codeBuffer.join('\n').trimRight()));
          codeBuffer.clear();
          inCode = false;
        } else {
          flushParagraph();
          inCode = true;
        }
        continue;
      }

      if (inCode) {
        codeBuffer.add(line);
        continue;
      }

      final trimmed = line.trimRight();
      if (trimmed.trim().isEmpty) {
        flushParagraph();
        continue;
      }

      final headingMatch = RegExp(r'^(#{1,3})\s+(.+)$').firstMatch(trimmed.trimLeft());
      if (headingMatch != null) {
        flushParagraph();
        final level = headingMatch.group(1)!.length;
        final content = headingMatch.group(2)!.trim();
        blocks.add(
          _ReadmeBlock(
            level == 1
                ? _ReadmeBlockType.heading1
                : level == 2
                    ? _ReadmeBlockType.heading2
                    : _ReadmeBlockType.heading3,
            content,
          ),
        );
        continue;
      }

      final listMatch = RegExp(r'^\s*([-*]|\d+\.)\s+(.+)$').firstMatch(trimmed);
      if (listMatch != null) {
        flushParagraph();
        blocks.add(
          _ReadmeBlock(
            _ReadmeBlockType.listItem,
            listMatch.group(2)!.trimRight(),
            marker: listMatch.group(1),
          ),
        );
        continue;
      }

      paragraphBuffer.add(trimmed);
    }

    if (inCode) {
      blocks.add(_ReadmeBlock(_ReadmeBlockType.codeBlock, codeBuffer.join('\n').trimRight()));
    }
    flushParagraph();
    return blocks;
  }

  List<InlineSpan> _parseInlineSpans(
    String text, {
    required TextStyle baseStyle,
    required TextStyle boldStyle,
    required TextStyle codeStyle,
  }) {
    final spans = <InlineSpan>[];

    int i = 0;
    while (i < text.length) {
      final nextBold = text.indexOf('**', i);
      final nextCode = text.indexOf('`', i);

      int next;
      String kind;
      if (nextBold == -1 && nextCode == -1) {
        next = -1;
        kind = '';
      } else if (nextBold == -1) {
        next = nextCode;
        kind = 'code';
      } else if (nextCode == -1) {
        next = nextBold;
        kind = 'bold';
      } else if (nextBold < nextCode) {
        next = nextBold;
        kind = 'bold';
      } else {
        next = nextCode;
        kind = 'code';
      }

      if (next == -1) {
        spans.add(TextSpan(text: text.substring(i), style: baseStyle));
        break;
      }

      if (next > i) {
        spans.add(TextSpan(text: text.substring(i, next), style: baseStyle));
        i = next;
      }

      if (kind == 'bold') {
        final end = text.indexOf('**', i + 2);
        if (end == -1) {
          spans.add(TextSpan(text: text.substring(i), style: baseStyle));
          break;
        }
        final content = text.substring(i + 2, end);
        if (content.isNotEmpty) {
          spans.add(TextSpan(text: content, style: boldStyle));
        }
        i = end + 2;
        continue;
      }

      if (kind == 'code') {
        final end = text.indexOf('`', i + 1);
        if (end == -1) {
          spans.add(TextSpan(text: text.substring(i), style: baseStyle));
          break;
        }
        final content = text.substring(i + 1, end);
        if (content.isNotEmpty) {
          spans.add(TextSpan(text: content, style: codeStyle));
        }
        i = end + 1;
        continue;
      }
    }

    return spans;
  }
}

enum _ReadmeBlockType { heading1, heading2, heading3, paragraph, listItem, codeBlock }

class _ReadmeBlock {
  final _ReadmeBlockType type;
  final String content;
  final String? marker;

  _ReadmeBlock(this.type, this.content, {this.marker});
}
