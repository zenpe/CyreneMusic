import 'dart:io';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:fluent_ui/fluent_ui.dart' as fluent;
import 'package:http/http.dart' as http;
import '../../widgets/material/material_settings_widgets.dart';
import '../../services/audio_source_service.dart';

import '../../services/lx_music_source_parser.dart';
import '../../models/audio_source_config.dart';
import '../../utils/theme_manager.dart';

/// 音源设置二级页面内容
class AudioSourceSettingsContent extends StatefulWidget {
  final VoidCallback? onBack;
  final bool embed;

  const AudioSourceSettingsContent({
    super.key,
    this.onBack,
    this.embed = false,
  });

  @override
  State<AudioSourceSettingsContent> createState() =>
      _AudioSourceSettingsContentState();

  /// 构建 Fluent UI 面包屑导航
  Widget buildFluentBreadcrumb(BuildContext context) {
    final theme = fluent.FluentTheme.of(context);
    final typography = theme.typography;

    return Row(
      children: [
        MouseRegion(
          cursor: SystemMouseCursors.click,
          child: GestureDetector(
            onTap: onBack,
            child: Text(
              '设置',
              style: typography.title?.copyWith(
                color: theme.resources.textFillColorSecondary,
              ),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Icon(
            fluent.FluentIcons.chevron_right,
            size: 14,
            color: theme.resources.textFillColorSecondary,
          ),
        ),
        Text(
          '音源设置',
          style: typography.title,
        ),
      ],
    );
  }
}

class _AudioSourceSettingsContentState
    extends State<AudioSourceSettingsContent> {
  final AudioSourceService _audioSourceService = AudioSourceService();

  @override
  void initState() {
    super.initState();
    _audioSourceService.addListener(_onSourceChanged);
  }

  @override
  void dispose() {
    _audioSourceService.removeListener(_onSourceChanged);
    super.dispose();
  }

  void _onSourceChanged() {
    setState(() {});
  }

  // ==================== Actions ====================

  /// 切换当前活动音源
  void _setActiveSource(String id) {
    _audioSourceService.setActiveSource(id);
  }

  /// 删除音源
  Future<void> _deleteSource(String id) async {
    // 弹出确认对话框
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        final themeManager = ThemeManager();
        if (themeManager.isFluentFramework && Platform.isWindows) {
          return fluent.ContentDialog(
            title: const Text('删除音源'),
            content: const Text('确定要删除这个音源吗？此操作无法撤销。'),
            actions: [
              fluent.Button(
                child: const Text('取消'),
                onPressed: () => Navigator.pop(context, false),
              ),
              fluent.FilledButton(
                style: fluent.ButtonStyle(
                  backgroundColor: fluent.ButtonState.all(fluent.Colors.red),
                ),
                onPressed: () => Navigator.pop(context, true),
                child: const Text('删除'),
              ),
            ],
          );
        } else {
          return AlertDialog(
            title: const Text('删除音源'),
            content: const Text('确定要删除这个音源吗？'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('取消'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(context, true),
                style: TextButton.styleFrom(foregroundColor: Colors.red),
                child: const Text('删除'),
              ),
            ],
          );
        }
      },
    );

    if (confirmed == true) {
      await _audioSourceService.removeSource(id);
    }
  }

  /// 打开添加音源对话框
  Future<void> _showAddSourceDialog() async {
    final themeManager = ThemeManager();
    if (themeManager.isCupertinoFramework &&
        (Platform.isIOS || Platform.isMacOS || Platform.isAndroid)) {
       await showCupertinoModalPopup(
        context: context,
        builder: (context) => const AddAudioSourceDialog(),
      );
    } else {
      await showDialog(
        context: context,
        builder: (context) => const AddAudioSourceDialog(),
      );
    }
  }

  /// 打开编辑音源对话框
  Future<void> _showEditSourceDialog(AudioSourceConfig config) async {
    final themeManager = ThemeManager();
    if (themeManager.isCupertinoFramework &&
        (Platform.isIOS || Platform.isMacOS || Platform.isAndroid)) {
      await showCupertinoModalPopup(
        context: context,
        builder: (context) => AddAudioSourceDialog(existingConfig: config),
      );
    } else {
      await showDialog(
        context: context,
        builder: (context) => AddAudioSourceDialog(existingConfig: config),
      );
    }
  }

  // ==================== Helpers ====================

  String _getSourceTypeName(AudioSourceType type) {
    switch (type) {
      case AudioSourceType.omniparse: return 'OmniParse';
      case AudioSourceType.lxmusic: return '洛雪音乐';
      case AudioSourceType.tunehub: return 'TuneHub';
    }
  }

  // ==================== Builders ====================

  @override
  Widget build(BuildContext context) {
    final themeManager = ThemeManager();

    if (themeManager.isFluentFramework && Platform.isWindows) {
      return _buildFluentContent(context);
    } else if (themeManager.isCupertinoFramework &&
        (Platform.isIOS || Platform.isAndroid)) {
      return _buildCupertinoContent(context);
    } else {
      return _buildMaterialContent(context);
    }
  }

  /// Fluent UI 内容 (Windows)
  Widget _buildFluentContent(BuildContext context) {
    final theme = fluent.FluentTheme.of(context);
    final sources = _audioSourceService.sources;

    return fluent.ScaffoldPage(
      content: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 说明卡片
            fluent.Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(fluent.FluentIcons.info, color: theme.accentColor),
                        const SizedBox(width: 8),
                        Text(
                          '关于音源',
                          style: theme.typography.subtitle,
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Text(
                      '添加并管理多个音源。您可以随时切换当前使用的音源。',
                      style: theme.typography.body,
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),
            Text('已配置音源', style: theme.typography.subtitle),
            const SizedBox(height: 16),
            
            // 音源卡片网格
            Wrap(
              spacing: 16,
              runSpacing: 16,
              children: [
                ...sources.map((config) => _buildFluentSourceCard(config, theme)),
                // 添加音源按钮
                _buildFluentAddCard(theme),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFluentSourceCard(AudioSourceConfig config, fluent.FluentThemeData theme) {
    final isActive = config.id == _audioSourceService.activeSource?.id;
    
    return SizedBox(
      width: 280,
      height: 180, // Fixed height for consistency
      child: fluent.Card(
        padding: const EdgeInsets.all(12),
        borderColor: isActive ? theme.accentColor : null,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.spaceBetween, // Distribute space
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      config.type == AudioSourceType.lxmusic 
                          ? fluent.FluentIcons.music_note 
                          : (config.type == AudioSourceType.tunehub ? fluent.FluentIcons.globe : fluent.FluentIcons.link),
                      size: 20,
                      color: isActive ? theme.accentColor : theme.resources.textFillColorSecondary,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        config.name,
                        style: theme.typography.subtitle?.copyWith(fontSize: 16),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (isActive)
                      fluent.Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: theme.accentColor,
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          '当前使用',
                          style: theme.typography.caption?.copyWith(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  '类型: ${config.type == AudioSourceType.lxmusic ? "洛雪音乐" : (config.type == AudioSourceType.tunehub ? "TuneHub" : "OmniParse")}',
                  style: theme.typography.caption,
                ),
                if (config.version.isNotEmpty)
                  Text('版本: ${config.version}', style: theme.typography.caption),
                const SizedBox(height: 4),
                fluent.Tooltip(
                  message: config.url,
                  child: Text(
                    config.url,
                    style: theme.typography.caption?.copyWith(
                      color: theme.resources.textFillColorSecondary,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                if (!isActive)
                  fluent.Button(
                    onPressed: () => _setActiveSource(config.id),
                    child: const Text('启用'),
                  ),
                const SizedBox(width: 8),
                fluent.IconButton(
                  icon: const Icon(fluent.FluentIcons.edit),
                  onPressed: () => _showEditSourceDialog(config),
                ),
                const SizedBox(width: 4),
                fluent.IconButton(
                  icon: const Icon(fluent.FluentIcons.delete),
                  onPressed: () => _deleteSource(config.id),
                  style: fluent.ButtonStyle(
                    foregroundColor: fluent.ButtonState.resolveWith((states) {
                      if (states.isHovering) return fluent.Colors.red;
                      return fluent.Colors.red.withOpacity(0.8);
                    }),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFluentAddCard(fluent.FluentThemeData theme) {
    return fluent.MouseRegion(
      cursor: SystemMouseCursors.click,
      child: fluent.GestureDetector(
        onTap: _showAddSourceDialog,
        child: SizedBox(
          width: 280,
          height: 180, // Same fixed height as source card
          child: fluent.Card(
            padding: EdgeInsets.zero,
            child: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(fluent.FluentIcons.add, size: 24, color: theme.accentColor),
                  const SizedBox(height: 8),
                  Text(
                    '添加音源',
                    style: TextStyle(
                      color: theme.accentColor,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// Cupertino 风格内容
  Widget _buildCupertinoContent(BuildContext context) {
    final sources = _audioSourceService.sources;
    final brightness = CupertinoTheme.brightnessOf(context);
    final isDark = brightness == Brightness.dark;
    
    // 颜色定义
    final backgroundColor = CupertinoColors.systemGroupedBackground.resolveFrom(context);
    final cardColor = isDark 
        ? const Color(0xFF2C2C2E) 
        : CupertinoColors.secondarySystemGroupedBackground.resolveFrom(context);
    final labelColor = CupertinoColors.label.resolveFrom(context);
    final secondaryLabelColor = CupertinoColors.secondaryLabel.resolveFrom(context);
    final separatorColor = CupertinoColors.separator.resolveFrom(context);

    // 构建音源类型图标
    Widget buildSourceIcon(AudioSourceConfig config, bool isActive) {
      final gradientColors = switch (config.type) {
        AudioSourceType.lxmusic => [const Color(0xFF667eea), const Color(0xFF764ba2)],
        AudioSourceType.tunehub => [const Color(0xFF11998e), const Color(0xFF38ef7d)],
        AudioSourceType.omniparse => [const Color(0xFFf093fb), const Color(0xFFf5576c)],
      };
      
      return Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: isActive ? gradientColors : [
              CupertinoColors.systemGrey4.resolveFrom(context),
              CupertinoColors.systemGrey3.resolveFrom(context),
            ],
          ),
          borderRadius: BorderRadius.circular(10),
          boxShadow: isActive ? [
            BoxShadow(
              color: gradientColors[0].withValues(alpha: 0.3),
              blurRadius: 8,
              offset: const Offset(0, 4),
            ),
          ] : null,
        ),
        child: Icon(
          switch (config.type) {
            AudioSourceType.lxmusic => CupertinoIcons.music_note_2,
            AudioSourceType.tunehub => CupertinoIcons.cloud,
            AudioSourceType.omniparse => CupertinoIcons.link,
          },
          color: CupertinoColors.white,
          size: 22,
        ),
      );
    }

    // 构建单个音源卡片
    Widget buildSourceCard(AudioSourceConfig config, int index) {
      final isActive = config.id == _audioSourceService.activeSource?.id;
      
      return Padding(
        padding: EdgeInsets.only(
          left: 16,
          right: 16,
          top: index == 0 ? 0 : 8,
          bottom: 8,
        ),
        child: GestureDetector(
          onTap: () => _setActiveSource(config.id),
          child: Container(
            decoration: BoxDecoration(
              color: cardColor,
              borderRadius: BorderRadius.circular(14),
              border: isActive ? Border.all(
                color: CupertinoColors.activeBlue.resolveFrom(context),
                width: 2,
              ) : null,
              boxShadow: [
                BoxShadow(
                  color: CupertinoColors.black.withValues(alpha: isDark ? 0.3 : 0.08),
                  blurRadius: 10,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Column(
              children: [
                // 主内容区
                Padding(
                  padding: const EdgeInsets.all(14),
                  child: Row(
                    children: [
                      // 图标
                      buildSourceIcon(config, isActive),
                      const SizedBox(width: 14),
                      
                      // 信息
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // 名称 + 活跃标签
                            Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    config.name,
                                    style: TextStyle(
                                      fontSize: 17,
                                      fontWeight: FontWeight.w600,
                                      color: labelColor,
                                      decoration: TextDecoration.none,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                if (isActive) ...[
                                  const SizedBox(width: 8),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 8,
                                      vertical: 3,
                                    ),
                                    decoration: BoxDecoration(
                                      color: CupertinoColors.activeBlue.withValues(alpha: 0.15),
                                      borderRadius: BorderRadius.circular(6),
                                    ),
                                    child: Text(
                                      '使用中',
                                      style: TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.w600,
                                        color: CupertinoColors.activeBlue.resolveFrom(context),
                                        decoration: TextDecoration.none,
                                      ),
                                    ),
                                  ),
                                ],
                              ],
                            ),
                            const SizedBox(height: 4),
                            
                            // 类型 + 版本
                            Row(
                              children: [
                                Text(
                                  _getSourceTypeName(config.type),
                                  style: TextStyle(
                                    fontSize: 13,
                                    color: secondaryLabelColor,
                                    decoration: TextDecoration.none,
                                  ),
                                ),
                                if (config.version.isNotEmpty) ...[
                                  Container(
                                    margin: const EdgeInsets.symmetric(horizontal: 6),
                                    width: 3,
                                    height: 3,
                                    decoration: BoxDecoration(
                                      color: secondaryLabelColor,
                                      shape: BoxShape.circle,
                                    ),
                                  ),
                                  Text(
                                    'v${config.version}',
                                    style: TextStyle(
                                      fontSize: 13,
                                      color: secondaryLabelColor,
                                      decoration: TextDecoration.none,
                                    ),
                                  ),
                                ],
                                if (config.author.isNotEmpty) ...[
                                  Container(
                                    margin: const EdgeInsets.symmetric(horizontal: 6),
                                    width: 3,
                                    height: 3,
                                    decoration: BoxDecoration(
                                      color: secondaryLabelColor,
                                      shape: BoxShape.circle,
                                    ),
                                  ),
                                  Expanded(
                                    child: Text(
                                      config.author,
                                      style: TextStyle(
                                        fontSize: 13,
                                        color: secondaryLabelColor,
                                        decoration: TextDecoration.none,
                                      ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ],
                        ),
                      ),
                      
                      // 右侧箭头
                      Icon(
                        CupertinoIcons.chevron_right,
                        color: CupertinoColors.tertiaryLabel.resolveFrom(context),
                        size: 16,
                      ),
                    ],
                  ),
                ),
                
                // 分割线
                Padding(
                  padding: const EdgeInsets.only(left: 72),
                  child: Container(
                    height: 0.5,
                    color: separatorColor,
                  ),
                ),
                
                // 操作按钮区
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  child: Row(
                    children: [
                      // 编辑按钮
                      Expanded(
                        child: CupertinoButton(
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          minSize: 0,
                          onPressed: () => _showEditSourceDialog(config),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                CupertinoIcons.pencil,
                                size: 16,
                                color: CupertinoColors.activeBlue.resolveFrom(context),
                              ),
                              const SizedBox(width: 6),
                              Text(
                                '编辑',
                                style: TextStyle(
                                  fontSize: 14,
                                  color: CupertinoColors.activeBlue.resolveFrom(context),
                                  decoration: TextDecoration.none,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      
                      // 分割线
                      Container(
                        width: 0.5,
                        height: 20,
                        color: separatorColor,
                      ),
                      
                      // 删除按钮
                      Expanded(
                        child: CupertinoButton(
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          minSize: 0,
                          onPressed: () => _deleteSource(config.id),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const Icon(
                                CupertinoIcons.trash,
                                size: 16,
                                color: CupertinoColors.destructiveRed,
                              ),
                              const SizedBox(width: 6),
                              const Text(
                                '删除',
                                style: TextStyle(
                                  fontSize: 14,
                                  color: CupertinoColors.destructiveRed,
                                  decoration: TextDecoration.none,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    // 构建空状态
    Widget buildEmptyState() {
      return Container(
        margin: const EdgeInsets.symmetric(horizontal: 16),
        padding: const EdgeInsets.symmetric(vertical: 48),
        decoration: BoxDecoration(
          color: cardColor,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Column(
          children: [
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                color: CupertinoColors.systemGrey5.resolveFrom(context),
                shape: BoxShape.circle,
              ),
              child: Icon(
                CupertinoIcons.music_note_list,
                size: 32,
                color: CupertinoColors.systemGrey.resolveFrom(context),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              '暂无音源',
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w600,
                color: labelColor,
                decoration: TextDecoration.none,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              '点击下方按钮添加您的第一个音源',
              style: TextStyle(
                fontSize: 14,
                color: secondaryLabelColor,
                decoration: TextDecoration.none,
              ),
            ),
          ],
        ),
      );
    }

    return CupertinoPageScaffold(
      navigationBar: widget.embed ? null : CupertinoNavigationBar(
        middle: const Text('音源设置'),
        backgroundColor: backgroundColor.withValues(alpha: 0.9),
        border: null,
      ),
      backgroundColor: backgroundColor,
      child: SafeArea(
        child: ListView(
          children: [
            const SizedBox(height: 16),
            
            // 说明卡片
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 16),
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: isDark 
                      ? [const Color(0xFF1a1a2e), const Color(0xFF16213e)]
                      : [const Color(0xFFe8f4fd), const Color(0xFFd4e8f8)],
                ),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: CupertinoColors.activeBlue.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(
                      CupertinoIcons.info_circle_fill,
                      color: CupertinoColors.activeBlue.resolveFrom(context),
                      size: 22,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      '您可以添加多个音源，点击卡片切换使用。',
                      style: TextStyle(
                        fontSize: 14,
                        color: labelColor,
                        decoration: TextDecoration.none,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            
            const SizedBox(height: 24),
            
            // 分组标题
            if (sources.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(left: 32, bottom: 8),
                child: Text(
                  '已配置音源',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    color: secondaryLabelColor,
                    letterSpacing: -0.08,
                    decoration: TextDecoration.none,
                  ),
                ),
              ),
            
            // 音源列表或空状态
            if (sources.isEmpty)
              buildEmptyState()
            else
              ...sources.asMap().entries.map(
                (entry) => buildSourceCard(entry.value, entry.key),
              ),
            
            const SizedBox(height: 24),
            
            // 添加按钮
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: CupertinoButton(
                padding: const EdgeInsets.symmetric(vertical: 14),
                color: CupertinoColors.activeBlue.resolveFrom(context),
                borderRadius: BorderRadius.circular(12),
                onPressed: _showAddSourceDialog,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(
                      CupertinoIcons.add_circled_solid,
                      size: 20,
                      color: CupertinoColors.white,
                    ),
                    const SizedBox(width: 8),
                    const Text(
                      '添加音源',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: CupertinoColors.white,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            
            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }

  Widget _buildMaterialContent(BuildContext context) {
    final sources = _audioSourceService.sources;
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('音源设置'),
        centerTitle: true,
      ),
      body: ListView(
        padding: const EdgeInsets.symmetric(vertical: 8),
        children: [
          // 说明卡片
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: colorScheme.secondaryContainer.withValues(alpha: 0.3),
                borderRadius: BorderRadius.circular(24),
              ),
              child: Row(
                children: [
                  Icon(Icons.info_outline, color: colorScheme.secondary),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '关于音源',
                          style: theme.textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.bold,
                            color: colorScheme.onSecondaryContainer,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '添加并管理多个音源。您可以随时切换当前使用的音源。',
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: colorScheme.onSecondaryContainer.withValues(alpha: 0.8),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),

          MD3SettingsSection(
            title: '已配置音源',
            children: [
              if (sources.isEmpty)
                const Padding(
                  padding: EdgeInsets.all(24.0),
                  child: Center(child: Text('暂无已配置音源')),
                )
              else
                ...sources.map((config) {
                  final isActive = config.id == _audioSourceService.activeSource?.id;
                  return _buildMaterialSourceTile(config, theme, isActive);
                }),
              MD3SettingsTile(
                leading: Icon(Icons.add_circle_outline, color: colorScheme.primary),
                title: '添加音源',
                onTap: _showAddSourceDialog,
              ),
            ],
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _showAddSourceDialog,
        elevation: 0,
        focusElevation: 0,
        hoverElevation: 0,
        disabledElevation: 0,
        highlightElevation: 0,
        backgroundColor: colorScheme.primaryContainer,
        foregroundColor: colorScheme.onPrimaryContainer,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: const Icon(Icons.add),
      ),
    );
  }

  Widget _buildMaterialSourceTile(AudioSourceConfig config, ThemeData theme, bool isActive) {
    final colorScheme = theme.colorScheme;
    return MD3SettingsTile(
      leading: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: isActive ? colorScheme.primaryContainer : colorScheme.surfaceContainerHigh,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Icon(
          config.type == AudioSourceType.lxmusic ? Icons.music_note : Icons.link,
          color: isActive ? colorScheme.onPrimaryContainer : colorScheme.onSurfaceVariant,
          size: 20,
        ),
      ),
      title: config.name,
      subtitle: '${_getSourceTypeName(config.type)} • ${isActive ? "当前使用" : "未开启"}',
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            icon: const Icon(Icons.edit_outlined, size: 20),
            onPressed: () => _showEditSourceDialog(config),
          ),
          IconButton(
            icon: Icon(Icons.delete_outline, size: 20, color: colorScheme.error),
            onPressed: () => _deleteSource(config.id),
          ),
        ],
      ),
      onTap: isActive ? null : () => _setActiveSource(config.id),
    );
  }
}

/// 添加/编辑音源对话框
class AddAudioSourceDialog extends StatefulWidget {
  final AudioSourceConfig? existingConfig;

  const AddAudioSourceDialog({super.key, this.existingConfig});

  @override
  State<AddAudioSourceDialog> createState() => _AddAudioSourceDialogState();
}

class _AddAudioSourceDialogState extends State<AddAudioSourceDialog> {
  late AudioSourceType _selectedType;
  
  // Controllers
  final TextEditingController _urlController = TextEditingController();
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _lxScriptUrlController = TextEditingController();
  final TextEditingController _lxApiKeyController = TextEditingController();
  final TextEditingController _tuneHubApiKeyController = TextEditingController();
  
  // Services
  final LxMusicSourceParser _lxParser = LxMusicSourceParser();
  final AudioSourceService _audioSourceService = AudioSourceService();
  
  // State
  bool _isProcessing = false;
  String? _statusMessage;
  bool _isError = false;

  // LxMusic specific
  bool _needsApiKeyInput = false;
  LxMusicSourceConfig? _pendingLxConfig;
  String? _pendingScriptSource;

  bool get _isEditing => widget.existingConfig != null;

  @override
  void initState() {
    super.initState();
    if (_isEditing) {
      final config = widget.existingConfig!;
      _selectedType = config.type;
      _nameController.text = config.name;
      _urlController.text = config.url;
      if (config.type == AudioSourceType.lxmusic) {
        _lxScriptUrlController.text = config.scriptSource;
        _lxApiKeyController.text = config.apiKey;
      } else if (config.type == AudioSourceType.tunehub) {
        _tuneHubApiKeyController.text = config.apiKey;
      }
    } else {
      _selectedType = AudioSourceType.lxmusic;
    }
  }

  @override
  void dispose() {
    _urlController.dispose();
    _nameController.dispose();
    _lxScriptUrlController.dispose();
    _lxApiKeyController.dispose();
    _tuneHubApiKeyController.dispose();
    super.dispose();
  }

  // --- Logic ---

  Future<void> _importLxScriptFromUrl() async {
    final scriptUrl = _lxScriptUrlController.text.trim();
    if (scriptUrl.isEmpty) {
      _setStatus('请输入脚本链接', isError: true);
      return;
    }

    setState(() {
      _isProcessing = true;
      _setStatus('正在获取脚本...');
      _needsApiKeyInput = false;
      _pendingLxConfig = null;
    });

    try {
      final config = await _lxParser.parseFromUrl(scriptUrl);
      if (config == null || !config.isValid) {
        _setStatus('解析失败：无法从脚本中提取 API 地址', isError: true);
        return;
      }
      
      _handleLxConfig(config, scriptUrl);
    } catch (e) {
      _setStatus('导入失败：$e', isError: true);
    } finally {
      setState(() => _isProcessing = false);
    }
  }

  Future<void> _importLxScriptFromFile() async {
    setState(() {
      _isProcessing = true;
      _setStatus('正在读取文件...');
      _needsApiKeyInput = false;
      _pendingLxConfig = null;
    });

    try {
      final config = await _lxParser.parseFromFile();
      if (config == null) {
        _setStatus(null); 
        setState(() => _isProcessing = false);
        return;
      }
      
      if (!config.isValid) {
        _setStatus('解析失败：文件无效', isError: true);
        return;
      }

      _handleLxConfig(config, config.source);
    } catch (e) {
      _setStatus('导入失败：$e', isError: true);
    } finally {
      setState(() => _isProcessing = false);
    }
  }

  void _handleLxConfig(LxMusicSourceConfig config, String sourcePath) {
    // 检查是否需要 API Key
    final needsKey = config.apiKey.isEmpty && config.scriptContent.isEmpty;
    
    if (needsKey) {
      setState(() {
        _pendingLxConfig = config;
        _pendingScriptSource = sourcePath;
        _needsApiKeyInput = true;
        _setStatus('此脚本需要手动输入 API Key', isError: false);
      });
    } else {
      _saveLxSource(config, sourcePath, config.apiKey);
    }
  }

  void _confirmLxApiKey() {
    if (_pendingLxConfig == null) return;
    final apiKey = _lxApiKeyController.text.trim();
    _saveLxSource(_pendingLxConfig!, _pendingScriptSource!, apiKey);
  }

  void _saveLxSource(LxMusicSourceConfig config, String sourcePath, String apiKey) {
    if (_isEditing) {
      final newConfig = widget.existingConfig!.copyWith(
        name: config.name,
        version: config.version,
        url: config.apiUrl,
        apiKey: apiKey,
        scriptSource: sourcePath,
        scriptContent: config.scriptContent,
        author: config.author,
        description: config.description,
        urlPathTemplate: config.urlPathTemplate,
      );
      _audioSourceService.updateSource(newConfig);
    } else {
      _audioSourceService.addSource(AudioSourceConfig(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        type: AudioSourceType.lxmusic,
        name: config.name,
        version: config.version,
        url: config.apiUrl,
        apiKey: apiKey,
        scriptSource: sourcePath,
        scriptContent: config.scriptContent,
        author: config.author,
        description: config.description,
        urlPathTemplate: config.urlPathTemplate,
      ));
    }

    Navigator.of(context).pop();
  }
  
  Future<void> _saveTuneHubSource() async {
    final url = _urlController.text.trim();
    if (url.isEmpty || !AudioSourceService.isValidUrl(url)) {
      _setStatus('请输入有效的 URL', isError: true);
      return;
    }

    final apiKey = _tuneHubApiKeyController.text.trim();

    setState(() => _isProcessing = true);
    
    try {
      final response = await http.get(Uri.parse(url)).timeout(const Duration(seconds: 5));
      if (response.statusCode >= 200 && response.statusCode < 400) {
        if (_isEditing) {
          final newConfig = widget.existingConfig!.copyWith(
            name: _nameController.text.isEmpty ? 'TuneHub' : _nameController.text,
            url: url,
            apiKey: apiKey,
          );
          _audioSourceService.updateSource(newConfig);
        } else {
           _audioSourceService.addSource(AudioSourceConfig(
            id: DateTime.now().millisecondsSinceEpoch.toString(),
            type: AudioSourceType.tunehub,
            name: _nameController.text.isEmpty ? 'TuneHub' : _nameController.text,
            url: url,
            apiKey: apiKey,
          ));
        }
         Navigator.of(context).pop();
      } else {
        _setStatus('连接测试失败: HTTP ${response.statusCode}', isError: true);
      }
    } catch (e) {
      _setStatus('连接测试失败: $e', isError: true);
    } finally {
       setState(() => _isProcessing = false);
    }
  }

  Future<void> _saveOmniParseSource() async {
    final url = _urlController.text.trim();
     if (url.isEmpty || !AudioSourceService.isValidUrl(url)) {
      _setStatus('请输入有效的 URL', isError: true);
      return;
    }
    
    if (_isEditing) {
       final newConfig = widget.existingConfig!.copyWith(
        name: _nameController.text.isEmpty ? 'OmniParse' : _nameController.text,
        url: url,
      );
      _audioSourceService.updateSource(newConfig);
    } else {
       _audioSourceService.addSource(AudioSourceConfig(
            id: DateTime.now().millisecondsSinceEpoch.toString(),
            type: AudioSourceType.omniparse,
            name: _nameController.text.isEmpty ? 'OmniParse' : _nameController.text,
            url: url,
          ));
    }
    Navigator.of(context).pop();
  }

  void _setStatus(String? msg, {bool isError = false}) {
    setState(() {
      _statusMessage = msg;
      _isError = isError;
    });
  }

  // --- UI Builders ---

  @override
  Widget build(BuildContext context) {
     final themeManager = ThemeManager();
     if (themeManager.isFluentFramework && Platform.isWindows) {
       return _buildFluentDialog(context);
     } else if (themeManager.isCupertinoFramework && (Platform.isIOS || Platform.isMacOS || Platform.isAndroid)) {
        // Checking Android too for manual theme switch cases
       return _buildCupertinoDialog(context);
     }
     return _buildMaterialDialog(context);
  }

  Widget _buildFluentDialog(BuildContext context) {
    return fluent.ContentDialog(
      title: Text(_isEditing ? '编辑音源' : '添加音源'),
      content: SizedBox(
        width: 400,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Type Selector (Disabled if editing)
            fluent.InfoLabel(
              label: '音源类型',
              child: fluent.ComboBox<AudioSourceType>(
                value: _selectedType,
                items: AudioSourceType.values.map((e) => fluent.ComboBoxItem(
                  value: e,
                  child: Text(_getTypeName(e)),
                )).toList(),
                onChanged: _isEditing ? null : (v) {
                  if (v != null) setState(() {
                    _selectedType = v;
                    _statusMessage = null;
                    _needsApiKeyInput = false;
                    _pendingLxConfig = null;
                  });
                },
              ),
            ),
            const SizedBox(height: 16),
            
            // Content based on type
            if (_selectedType == AudioSourceType.lxmusic) ...[
               Text('输入洛雪音源脚本链接或从文件导入', style: fluent.FluentTheme.of(context).typography.caption),
               const SizedBox(height: 8),
               fluent.TextBox(
                 controller: _lxScriptUrlController,
                 placeholder: 'https://example.com/script.js',
               ),
               const SizedBox(height: 8),
               Row(
                 children: [
                    fluent.Button(
                      onPressed: _isProcessing ? null : _importLxScriptFromUrl,
                      child: const Text('链接导入'),
                    ),
                    const SizedBox(width: 8),
                    fluent.Button(
                      onPressed: _isProcessing ? null : _importLxScriptFromFile,
                      child: const Text('本地文件'),
                    ),
                 ],
               ),
               if (_needsApiKeyInput) ...[
                 const SizedBox(height: 12),
                 fluent.InfoLabel(
                   label: '需要 API Key',
                   child: fluent.TextBox(
                     controller: _lxApiKeyController,
                     placeholder: '输入 API Key',
                   ),
                 ),
                 const SizedBox(height: 8),
                 fluent.FilledButton(
                   onPressed: _confirmLxApiKey,
                   child: const Text('确认添加'),
                 ),
               ]
            ] else ...[
               fluent.InfoLabel(
                 label: '名称 (可选)',
                 child: fluent.TextBox(controller: _nameController, placeholder: '给音源起个名字'),
               ),
               const SizedBox(height: 8),
               fluent.InfoLabel(
                 label: 'API 地址',
                 child: fluent.TextBox(controller: _urlController, placeholder: 'http://...'),
               ),
               // TuneHub v3 需要 API Key
               if (_selectedType == AudioSourceType.tunehub) ...[
                 const SizedBox(height: 8),
                 fluent.InfoLabel(
                   label: 'API Key',
                   child: fluent.TextBox(
                     controller: _tuneHubApiKeyController, 
                     placeholder: 'th_your_api_key_here',
                     obscureText: true,
                   ),
                 ),
               ],
            ],

            if (_statusMessage != null) ...[
              const SizedBox(height: 16),
              fluent.InfoBar(
                title: Text(_statusMessage!),
                severity: _isError ? fluent.InfoBarSeverity.error : fluent.InfoBarSeverity.success,
              ),
            ]
          ],
        ),
      ),
      actions: [
        fluent.Button(
          onPressed: () => Navigator.pop(context),
          child: const Text('取消'),
        ),
        if (_selectedType != AudioSourceType.lxmusic) // LxMusic has its own confirm flow inside content (if key needed) or auto-adds
          fluent.FilledButton(
            onPressed: _isProcessing ? null : (_selectedType == AudioSourceType.tunehub ? _saveTuneHubSource : _saveOmniParseSource),
            child: _isProcessing 
                ? const SizedBox(width: 16, height: 16, child: fluent.ProgressRing(strokeWidth: 2)) 
                : Text(_isEditing ? '保存' : '添加'),
          ),
      ],
    );
  }

  Widget _buildCupertinoDialog(BuildContext context) {
    final brightness = CupertinoTheme.brightnessOf(context);
    final isDark = brightness == Brightness.dark;
    
    // 颜色定义
    final backgroundColor = isDark 
        ? const Color(0xFF1C1C1E) 
        : CupertinoColors.systemBackground.resolveFrom(context);
    final cardColor = isDark 
        ? const Color(0xFF2C2C2E) 
        : CupertinoColors.secondarySystemGroupedBackground.resolveFrom(context);
    final separatorColor = CupertinoColors.separator.resolveFrom(context);
    final labelColor = CupertinoColors.label.resolveFrom(context);
    final secondaryLabelColor = CupertinoColors.secondaryLabel.resolveFrom(context);

    // 构建分组标题
    Widget buildSectionHeader(String title) {
      return Padding(
        padding: const EdgeInsets.only(left: 16, bottom: 8, top: 20),
        child: Text(
          title.toUpperCase(),
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w400,
            color: secondaryLabelColor,
            letterSpacing: -0.08,
          ),
        ),
      );
    }

    // 构建分组卡片
    Widget buildGroupedCard({required List<Widget> children}) {
      return Container(
        margin: const EdgeInsets.symmetric(horizontal: 16),
        decoration: BoxDecoration(
          color: cardColor,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Column(
          children: children.asMap().entries.map((entry) {
            final index = entry.key;
            final child = entry.value;
            final isLast = index == children.length - 1;
            return Column(
              children: [
                child,
                if (!isLast)
                  Padding(
                    padding: const EdgeInsets.only(left: 16),
                    child: Container(
                      height: 0.5,
                      color: separatorColor,
                    ),
                  ),
              ],
            );
          }).toList(),
        ),
      );
    }

    // 构建列表项
    Widget buildListTile({
      required String title,
      String? subtitle,
      Widget? trailing,
      VoidCallback? onTap,
      bool showChevron = false,
    }) {
      return CupertinoButton(
        padding: EdgeInsets.zero,
        onPressed: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontSize: 17,
                        color: labelColor,
                        fontWeight: FontWeight.w400,
                      ),
                    ),
                    if (subtitle != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        subtitle,
                        style: TextStyle(
                          fontSize: 14,
                          color: secondaryLabelColor,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              if (trailing != null) trailing,
              if (showChevron)
                Padding(
                  padding: const EdgeInsets.only(left: 8),
                  child: Icon(
                    CupertinoIcons.chevron_right,
                    size: 14,
                    color: CupertinoColors.tertiaryLabel.resolveFrom(context),
                  ),
                ),
            ],
          ),
        ),
      );
    }

    // 构建输入框项
    Widget buildInputTile({
      required String placeholder,
      required TextEditingController controller,
      bool obscureText = false,
      TextInputType? keyboardType,
    }) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        child: CupertinoTextField(
          controller: controller,
          placeholder: placeholder,
          obscureText: obscureText,
          keyboardType: keyboardType,
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: const BoxDecoration(),
          style: TextStyle(fontSize: 17, color: labelColor),
          placeholderStyle: TextStyle(
            fontSize: 17,
            color: CupertinoColors.placeholderText.resolveFrom(context),
          ),
        ),
      );
    }

    // 状态提示组件
    Widget buildStatusBanner() {
      if (_statusMessage == null) return const SizedBox.shrink();
      
      final isSuccess = !_isError;
      final bannerColor = isSuccess 
          ? CupertinoColors.activeGreen.withValues(alpha: 0.15)
          : CupertinoColors.destructiveRed.withValues(alpha: 0.15);
      final iconColor = isSuccess 
          ? CupertinoColors.activeGreen 
          : CupertinoColors.destructiveRed;
      final textColor = isSuccess 
          ? CupertinoColors.activeGreen 
          : CupertinoColors.destructiveRed;

      return Container(
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: bannerColor,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          children: [
            Icon(
              isSuccess ? CupertinoIcons.checkmark_circle_fill : CupertinoIcons.xmark_circle_fill,
              color: iconColor,
              size: 20,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                _statusMessage!,
                style: TextStyle(
                  fontSize: 14,
                  color: textColor,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ],
        ),
      );
    }

    // 获取键盘高度用于内容区域底部 padding
    final keyboardHeight = MediaQuery.of(context).viewInsets.bottom;

    return Material(
      type: MaterialType.transparency,
      child: Container(
        height: MediaQuery.of(context).size.height * 0.75,
        decoration: BoxDecoration(
          color: backgroundColor,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
        ),
        child: Column(
          children: [
            // 拖拽手柄
            Container(
              width: 36,
              height: 5,
              margin: const EdgeInsets.only(top: 8),
              decoration: BoxDecoration(
                color: CupertinoColors.systemGrey3.resolveFrom(context),
                borderRadius: BorderRadius.circular(2.5),
              ),
            ),
            
            // 导航栏（带毛玻璃效果）
            ClipRRect(
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                  decoration: BoxDecoration(
                    color: backgroundColor.withValues(alpha: 0.9),
                    border: Border(
                      bottom: BorderSide(
                        color: separatorColor,
                        width: 0.5,
                      ),
                    ),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      CupertinoButton(
                        padding: EdgeInsets.zero,
                        minSize: 0,
                        child: Text(
                          '取消',
                          style: TextStyle(
                            fontSize: 17,
                            color: CupertinoColors.activeBlue.resolveFrom(context),
                          ),
                        ),
                        onPressed: () => Navigator.pop(context),
                      ),
                      Text(
                        _isEditing ? '编辑音源' : '添加音源',
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 17,
                          color: labelColor,
                        ),
                      ),
                      _isProcessing
                          ? const CupertinoActivityIndicator()
                          : CupertinoButton(
                              padding: EdgeInsets.zero,
                              minSize: 0,
                              onPressed: _selectedType == AudioSourceType.lxmusic
                                  ? null
                                  : (_selectedType == AudioSourceType.tunehub
                                      ? _saveTuneHubSource
                                      : _saveOmniParseSource),
                              child: Text(
                                _isEditing ? '保存' : '添加',
                                style: TextStyle(
                                  fontSize: 17,
                                  fontWeight: FontWeight.w600,
                                  color: _selectedType == AudioSourceType.lxmusic
                                      ? CupertinoColors.tertiaryLabel.resolveFrom(context)
                                      : CupertinoColors.activeBlue.resolveFrom(context),
                                ),
                              ),
                            ),
                    ],
                  ),
                ),
              ),
            ),
            
            // 内容区域
            Expanded(
              child: SingleChildScrollView(
                keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
                padding: EdgeInsets.only(bottom: keyboardHeight),
                child: SafeArea(
                  top: false,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // 音源类型选择
                      buildSectionHeader('音源类型'),
                      buildGroupedCard(
                        children: [
                          buildListTile(
                            title: _getTypeName(_selectedType),
                            trailing: _isEditing
                                ? null
                                : Text(
                                    '更改',
                                    style: TextStyle(
                                      fontSize: 17,
                                      color: CupertinoColors.activeBlue.resolveFrom(context),
                                    ),
                                  ),
                            onTap: _isEditing
                                ? null
                                : () {
                                    showCupertinoModalPopup<void>(
                                      context: context,
                                      builder: (BuildContext ctx) => Container(
                                        height: 280,
                                        decoration: BoxDecoration(
                                          color: backgroundColor,
                                          borderRadius: const BorderRadius.vertical(
                                            top: Radius.circular(12),
                                          ),
                                        ),
                                        child: Column(
                                          children: [
                                            // Picker 导航栏
                                            Container(
                                              padding: const EdgeInsets.symmetric(
                                                horizontal: 16,
                                                vertical: 10,
                                              ),
                                              decoration: BoxDecoration(
                                                border: Border(
                                                  bottom: BorderSide(
                                                    color: separatorColor,
                                                    width: 0.5,
                                                  ),
                                                ),
                                              ),
                                              child: Row(
                                                mainAxisAlignment:
                                                    MainAxisAlignment.spaceBetween,
                                                children: [
                                                  CupertinoButton(
                                                    padding: EdgeInsets.zero,
                                                    minSize: 0,
                                                    child: const Text('取消'),
                                                    onPressed: () =>
                                                        Navigator.pop(ctx),
                                                  ),
                                                  Text(
                                                    '选择音源类型',
                                                    style: TextStyle(
                                                      fontWeight: FontWeight.w600,
                                                      fontSize: 17,
                                                      color: labelColor,
                                                    ),
                                                  ),
                                                  CupertinoButton(
                                                    padding: EdgeInsets.zero,
                                                    minSize: 0,
                                                    child: const Text(
                                                      '完成',
                                                      style: TextStyle(
                                                        fontWeight: FontWeight.w600,
                                                      ),
                                                    ),
                                                    onPressed: () =>
                                                        Navigator.pop(ctx),
                                                  ),
                                                ],
                                              ),
                                            ),
                                            // Picker
                                            Expanded(
                                              child: CupertinoPicker(
                                                magnification: 1.22,
                                                squeeze: 1.2,
                                                useMagnifier: true,
                                                itemExtent: 40,
                                                scrollController:
                                                    FixedExtentScrollController(
                                                  initialItem: AudioSourceType
                                                      .values
                                                      .indexOf(_selectedType),
                                                ),
                                                onSelectedItemChanged:
                                                    (int selectedItem) {
                                                  setState(() {
                                                    _selectedType =
                                                        AudioSourceType.values[
                                                            selectedItem];
                                                    _statusMessage = null;
                                                    _needsApiKeyInput = false;
                                                    _pendingLxConfig = null;
                                                  });
                                                },
                                                children: AudioSourceType.values
                                                    .map((type) => Center(
                                                          child: Text(
                                                            _getTypeName(type),
                                                            style: TextStyle(
                                                              fontSize: 20,
                                                              color: labelColor,
                                                            ),
                                                          ),
                                                        ))
                                                    .toList(),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    );
                                  },
                          ),
                        ],
                      ),

                      // 状态提示
                      buildStatusBanner(),

                      // 根据音源类型显示不同配置
                      if (_selectedType == AudioSourceType.lxmusic) ...[
                        buildSectionHeader('脚本配置'),
                        buildGroupedCard(
                          children: [
                            buildInputTile(
                              placeholder: '输入脚本链接 (https://...)',
                              controller: _lxScriptUrlController,
                              keyboardType: TextInputType.url,
                            ),
                          ],
                        ),
                        
                        // 导入按钮
                        Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 20,
                          ),
                          child: Row(
                            children: [
                              Expanded(
                                child: CupertinoButton(
                                  padding: const EdgeInsets.symmetric(vertical: 14),
                                  color: CupertinoColors.activeBlue.resolveFrom(context),
                                  borderRadius: BorderRadius.circular(10),
                                  onPressed: _isProcessing ? null : _importLxScriptFromUrl,
                                  child: Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      const Icon(
                                        CupertinoIcons.link,
                                        size: 18,
                                        color: CupertinoColors.white,
                                      ),
                                      const SizedBox(width: 8),
                                      const Text(
                                        '链接导入',
                                        style: TextStyle(
                                          fontSize: 16,
                                          fontWeight: FontWeight.w600,
                                          color: CupertinoColors.white,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: CupertinoButton(
                                  padding: const EdgeInsets.symmetric(vertical: 14),
                                  color: cardColor,
                                  borderRadius: BorderRadius.circular(10),
                                  onPressed: _isProcessing ? null : _importLxScriptFromFile,
                                  child: Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Icon(
                                        CupertinoIcons.folder,
                                        size: 18,
                                        color: labelColor,
                                      ),
                                      const SizedBox(width: 8),
                                      Text(
                                        '本地文件',
                                        style: TextStyle(
                                          fontSize: 16,
                                          fontWeight: FontWeight.w600,
                                          color: labelColor,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),

                        // API Key 输入（如果需要）
                        if (_needsApiKeyInput) ...[
                          buildSectionHeader('认证'),
                          buildGroupedCard(
                            children: [
                              buildInputTile(
                                placeholder: '输入 API Key',
                                controller: _lxApiKeyController,
                                obscureText: true,
                              ),
                            ],
                          ),
                          Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 20,
                            ),
                            child: SizedBox(
                              width: double.infinity,
                              child: CupertinoButton(
                                padding: const EdgeInsets.symmetric(vertical: 14),
                                color: CupertinoColors.activeBlue.resolveFrom(context),
                                borderRadius: BorderRadius.circular(10),
                                onPressed: _confirmLxApiKey,
                                child: const Text(
                                  '确认添加',
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w600,
                                    color: CupertinoColors.white,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ] else ...[
                        // TuneHub / OmniParse 配置
                        buildSectionHeader('基本信息'),
                        buildGroupedCard(
                          children: [
                            buildInputTile(
                              placeholder: '音源名称（可选）',
                              controller: _nameController,
                            ),
                          ],
                        ),
                        
                        buildSectionHeader('服务器配置'),
                        buildGroupedCard(
                          children: [
                            buildInputTile(
                              placeholder: 'API 地址 (http://...)',
                              controller: _urlController,
                              keyboardType: TextInputType.url,
                            ),
                          ],
                        ),

                        if (_selectedType == AudioSourceType.tunehub) ...[
                          buildSectionHeader('认证'),
                          buildGroupedCard(
                            children: [
                              buildInputTile(
                                placeholder: 'API Key',
                                controller: _tuneHubApiKeyController,
                                obscureText: true,
                              ),
                            ],
                          ),
                        ],
                        
                        // 添加说明
                        Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 32,
                            vertical: 8,
                          ),
                          child: Text(
                            _selectedType == AudioSourceType.tunehub
                                ? '请输入 TuneHub 服务器的 API 地址'
                                : '请输入 OmniParse 服务的地址',
                            style: TextStyle(
                              fontSize: 13,
                              color: secondaryLabelColor,
                            ),
                          ),
                        ),
                      ],
                      
                      const SizedBox(height: 32),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMaterialDialog(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
      backgroundColor: colorScheme.surfaceContainerHigh,
      title: Text(_isEditing ? '编辑音源' : '添加音源'),
      content: SingleChildScrollView(
        child: SizedBox(
          width: 400,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Type Selector
              DropdownButtonFormField<AudioSourceType>(
                value: _selectedType,
                decoration: InputDecoration(
                  labelText: '音源类型',
                  filled: true,
                  fillColor: colorScheme.surfaceContainerHighest,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none,
                  ),
                ),
                items: AudioSourceType.values.map((e) => DropdownMenuItem(
                      value: e,
                      child: Text(_getTypeName(e)),
                    ))
                    .toList(),
                onChanged: _isEditing
                    ? null
                    : (v) {
                        if (v != null) {
                          setState(() {
                            _selectedType = v;
                            _statusMessage = null;
                            _needsApiKeyInput = false;
                            _pendingLxConfig = null;
                          });
                        }
                      },
              ),
              const SizedBox(height: 20),

              // Content based on type
              if (_selectedType == AudioSourceType.lxmusic) ...[
                Text('输入洛雪音源脚本链接或从文件导入', 
                   style: theme.textTheme.bodySmall?.copyWith(color: colorScheme.onSurfaceVariant)),
                const SizedBox(height: 12),
                TextField(
                  controller: _lxScriptUrlController,
                  decoration: InputDecoration(
                    labelText: '脚本链接',
                    hintText: 'https://example.com/script.js',
                    filled: true,
                    fillColor: colorScheme.surfaceContainerHighest,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: FilledButton.tonalIcon(
                        icon: const Icon(Icons.link),
                        onPressed: _isProcessing ? null : _importLxScriptFromUrl,
                         label: const Text('链接导入'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: OutlinedButton.icon(
                        icon: const Icon(Icons.folder_open_outlined),
                        onPressed: _isProcessing ? null : _importLxScriptFromFile,
                        label: const Text('本地文件'),
                        style: OutlinedButton.styleFrom(
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                      ),
                    ),
                  ],
                ),
                if (_needsApiKeyInput) ...[
                  const SizedBox(height: 20),
                  TextField(
                    controller: _lxApiKeyController,
                     decoration: InputDecoration(
                      labelText: 'API Key',
                      hintText: '输入 API Key',
                      filled: true,
                      fillColor: colorScheme.surfaceContainerHighest,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide.none,
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed: _confirmLxApiKey,
                      child: const Text('确认添加'),
                    ),
                  ),
                ]
              ] else ...[
                 TextField(
                  controller: _nameController,
                  decoration: InputDecoration(
                    labelText: '名称 (可选)',
                    hintText: '给音源起个名字',
                    filled: true,
                    fillColor: colorScheme.surfaceContainerHighest,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _urlController,
                   decoration: InputDecoration(
                    labelText: 'API 地址',
                    hintText: 'http://...',
                    filled: true,
                    fillColor: colorScheme.surfaceContainerHighest,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
                if (_selectedType == AudioSourceType.tunehub) ...[
                  const SizedBox(height: 16),
                  TextField(
                    controller: _tuneHubApiKeyController,
                    obscureText: true,
                    decoration: InputDecoration(
                      labelText: 'API Key',
                      hintText: 'th_your_api_key_here',
                      filled: true,
                      fillColor: colorScheme.surfaceContainerHighest,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide.none,
                      ),
                    ),
                  ),
                ],
              ],

               if (_statusMessage != null) ...[
                const SizedBox(height: 20),
                Container(
                   padding: const EdgeInsets.all(12),
                   decoration: BoxDecoration(
                     color: _isError ? colorScheme.errorContainer : colorScheme.primaryContainer,
                     borderRadius: BorderRadius.circular(16),
                   ),
                   child: Row(
                     children: [
                       Icon(
                         _isError ? Icons.error_outline : Icons.check_circle_outline,
                         color: _isError ? colorScheme.onErrorContainer : colorScheme.onPrimaryContainer,
                         size: 20
                       ),
                       const SizedBox(width: 12),
                       Expanded(
                         child: Text(
                           _statusMessage!,
                           style: theme.textTheme.bodyMedium?.copyWith(
                              color: _isError ? colorScheme.onErrorContainer : colorScheme.onPrimaryContainer,
                           ),
                         ),
                       ),
                     ],
                   ),
                )
              ]
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('取消'),
        ),
        if (_selectedType != AudioSourceType.lxmusic)
          FilledButton(
            onPressed: _isProcessing
                ? null
                : (_selectedType == AudioSourceType.tunehub
                    ? _saveTuneHubSource
                    : _saveOmniParseSource),
            child: _isProcessing
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white)
                  )
                : Text(_isEditing ? '保存' : '添加'),
          ),
      ],
    );
  }

  String _getTypeName(AudioSourceType type) {
    switch (type) {
      case AudioSourceType.omniparse: return 'OmniParse / 自定义';
      case AudioSourceType.lxmusic: return '洛雪音乐脚本';
      case AudioSourceType.tunehub: return 'TuneHub';
    }
  }
}
