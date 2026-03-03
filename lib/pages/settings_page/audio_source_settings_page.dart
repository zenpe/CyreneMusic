import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:fluent_ui/fluent_ui.dart' as fluent;
import '../../features/audio_source/audio_source_feature.dart';
import '../../widgets/material/material_settings_widgets.dart';
import '../../services/audio_source_service.dart';

import '../../services/navidrome_session_service.dart';
import '../../models/audio_source_config.dart';
import '../../utils/theme_manager.dart';
import '../../widgets/navidrome_config_form.dart';
import 'add_audio_source_dialog.dart';

/// 音源设置二级页面内容
class AudioSourceSettingsContent extends StatefulWidget {
  final VoidCallback? onBack;
  final bool embed;
  final bool openNavidromeSettings;

  const AudioSourceSettingsContent({
    super.key,
    this.onBack,
    this.embed = false,
    this.openNavidromeSettings = false,
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
        Text('音源设置', style: typography.title),
      ],
    );
  }
}

class _AudioSourceSettingsContentState
    extends State<AudioSourceSettingsContent> {
  final AudioSourceReadController _audioSourceReadController =
      AudioSourceReadController();
  final AudioSourceController _audioSourceController = AudioSourceController();
  bool _showNavidromeConfig = false;
  bool _isSourceActionBusy = false;

  @override
  void initState() {
    super.initState();
    _showNavidromeConfig = widget.openNavidromeSettings;
    if (widget.openNavidromeSettings) {
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        if (!mounted) return;
        await _setActiveSource(AudioSourceService.navidromeSourceId);
      });
    }
    _audioSourceReadController.addListener(_onSourceChanged);
    NavidromeSessionService().addListener(_onSourceChanged);
  }

  @override
  void dispose() {
    _audioSourceReadController.removeListener(_onSourceChanged);
    NavidromeSessionService().removeListener(_onSourceChanged);
    super.dispose();
  }

  void _onSourceChanged() {
    if (!mounted) return;
    setState(() {});
  }

  // ==================== Actions ====================

  Future<void> _runWithSourceActionLock({
    required Future<void> Function() action,
  }) async {
    if (_isSourceActionBusy) return;
    if (mounted) {
      setState(() {
        _isSourceActionBusy = true;
      });
    } else {
      _isSourceActionBusy = true;
    }
    try {
      await action();
    } finally {
      if (!mounted) {
        _isSourceActionBusy = false;
        return;
      }
      setState(() {
        _isSourceActionBusy = false;
      });
    }
  }

  Future<void> _runSourceActionWithFeedback({
    required Future<void> Function() action,
    required String errorMessage,
    Future<void> Function()? onRetry,
  }) async {
    try {
      await action();
    } catch (_) {
      _showActionError(errorMessage, onRetry: onRetry);
    }
  }

  void _showActionError(
    String message, {
    Future<void> Function()? onRetry,
  }) {
    if (!mounted) return;
    final themeManager = ThemeManager();
    if (themeManager.isFluentFramework && Platform.isWindows) {
      fluent.displayInfoBar(
        context,
        duration: const Duration(seconds: 4),
        builder: (context, close) => fluent.InfoBar(
          title: const Text('操作失败'),
          content: Text(message),
          severity: fluent.InfoBarSeverity.error,
          action: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (onRetry != null)
                fluent.Button(
                  onPressed: () {
                    close();
                    onRetry();
                  },
                  child: const Text('重试'),
                ),
              fluent.IconButton(
                icon: const Icon(fluent.FluentIcons.clear),
                onPressed: close,
              ),
            ],
          ),
        ),
      );
      return;
    }

    final messenger = ScaffoldMessenger.maybeOf(context);
    if (messenger != null) {
      messenger.hideCurrentSnackBar();
      messenger.showSnackBar(
        SnackBar(
          content: Text(message),
          behavior: SnackBarBehavior.floating,
          action: onRetry == null
              ? null
              : SnackBarAction(
                  label: '重试',
                  onPressed: () {
                    onRetry();
                  },
                ),
        ),
      );
      return;
    }

    if (themeManager.isCupertinoFramework &&
        (Platform.isIOS || Platform.isAndroid || Platform.isMacOS)) {
      showCupertinoDialog<void>(
        context: context,
        builder: (dialogContext) => CupertinoAlertDialog(
          title: const Text('操作失败'),
          content: Text(message),
          actions: [
            CupertinoDialogAction(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('知道了'),
            ),
            if (onRetry != null)
              CupertinoDialogAction(
                isDefaultAction: true,
                onPressed: () {
                  Navigator.of(dialogContext).pop();
                  onRetry();
                },
                child: const Text('重试'),
              ),
          ],
        ),
      );
      return;
    }

    showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('操作失败'),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('知道了'),
          ),
          if (onRetry != null)
            TextButton(
              onPressed: () {
                Navigator.of(dialogContext).pop();
                onRetry();
              },
              child: const Text('重试'),
            ),
        ],
      ),
    );
  }

  /// 切换当前活动音源
  Future<void> _setActiveSource(String id) async {
    await _runSourceActionWithFeedback(
      errorMessage: '切换音源失败，请稍后重试',
      onRetry: () => _setActiveSource(id),
      action: () => _runWithSourceActionLock(
        action: () async {
          final result = await _audioSourceController.setActiveSource(id);
          if (!result.isSuccess) {
            throw Exception(result.errorMessage ?? '切换音源失败');
          }
        },
      ),
    );
  }

  Future<void> _activateNavidrome({
    bool openSettingsIfUnconfigured = true,
  }) async {
    await _runSourceActionWithFeedback(
      errorMessage: '切换到 Navidrome 失败，请稍后重试',
      onRetry: () =>
          _activateNavidrome(openSettingsIfUnconfigured: openSettingsIfUnconfigured),
      action: () => _runWithSourceActionLock(
        action: () async {
          final result = await _audioSourceController.setActiveSource(
            AudioSourceService.navidromeSourceId,
          );
          if (!result.isSuccess) {
            throw Exception(result.errorMessage ?? '切换到 Navidrome 失败');
          }
          if (openSettingsIfUnconfigured &&
              !_isNavidromeConfigured &&
              mounted) {
            setState(() => _showNavidromeConfig = true);
          }
        },
      ),
    );
  }

  Future<void> _openNavidromeSettings() async {
    await _runSourceActionWithFeedback(
      errorMessage: '打开 Navidrome 配置失败，请稍后重试',
      onRetry: _openNavidromeSettings,
      action: () => _runWithSourceActionLock(
        action: () async {
          final result = await _audioSourceController.setActiveSource(
            AudioSourceService.navidromeSourceId,
          );
          if (!result.isSuccess) {
            throw Exception(result.errorMessage ?? '打开 Navidrome 配置失败');
          }
          if (!mounted) return;
          setState(() => _showNavidromeConfig = true);
        },
      ),
    );
  }

  void _closeNavidromeSettings() {
    if (!_showNavidromeConfig) return;
    setState(() => _showNavidromeConfig = false);
  }

  Widget _buildNavidromeConfigHeader(BuildContext context) {
    final themeManager = ThemeManager();
    if (themeManager.isFluentFramework && Platform.isWindows) {
      final theme = fluent.FluentTheme.of(context);
      return Row(
        children: [
          fluent.IconButton(
            icon: const Icon(fluent.FluentIcons.back),
            onPressed: _closeNavidromeSettings,
          ),
          const SizedBox(width: 8),
          Text('Navidrome 配置', style: theme.typography.title),
        ],
      );
    }

    if (themeManager.isCupertinoFramework &&
        (Platform.isIOS || Platform.isAndroid)) {
      final labelColor = CupertinoColors.label.resolveFrom(context);
      return Row(
        children: [
          CupertinoButton(
            padding: EdgeInsets.zero,
            minSize: 0,
            onPressed: _closeNavidromeSettings,
            child: const Icon(CupertinoIcons.back),
          ),
          const SizedBox(width: 8),
          Text(
            'Navidrome 配置',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w600,
              color: labelColor,
              decoration: TextDecoration.none,
            ),
          ),
        ],
      );
    }

    final theme = Theme.of(context);
    return Row(
      children: [
        IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: _closeNavidromeSettings,
        ),
        const SizedBox(width: 4),
        Text(
          'Navidrome 配置',
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }

  Widget _buildNavidromeConfigForm(
    BuildContext context, {
    EdgeInsetsGeometry? padding,
  }) {
    return NavidromeConfigForm(
      padding: padding ?? const EdgeInsets.all(16),
      showClearButton: true,
      header: _buildNavidromeConfigHeader(context),
    );
  }

  Widget _buildNavidromeConfigBody(
    BuildContext context, {
    EdgeInsetsGeometry? padding,
    bool wrapMaterial = false,
  }) {
    final form = _buildNavidromeConfigForm(context, padding: padding);
    if (!wrapMaterial) return form;
    return Material(type: MaterialType.transparency, child: form);
  }

  /// 删除音源
  Future<void> _deleteSource(String id) async {
    if (_isSourceActionBusy) return;
    await _runSourceActionWithFeedback(
      errorMessage: '删除音源失败，请稍后重试',
      onRetry: () => _deleteSource(id),
      action: () async {
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
                      backgroundColor: WidgetStatePropertyAll(fluent.Colors.red),
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
          await _runWithSourceActionLock(
            action: () async {
              final result = await _audioSourceController.removeSource(id);
              if (!result.isSuccess) {
                throw Exception(result.errorMessage ?? '删除音源失败');
              }
            },
          );
        }
      },
    );
  }

  /// 打开添加音源对话框
  Future<void> _showAddSourceDialog() async {
    if (_isSourceActionBusy) return;
    await _runSourceActionWithFeedback(
      errorMessage: '打开添加音源窗口失败，请稍后重试',
      onRetry: _showAddSourceDialog,
      action: () async {
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
      },
    );
  }

  /// 打开编辑音源对话框
  Future<void> _showEditSourceDialog(AudioSourceConfig config) async {
    if (_isSourceActionBusy) return;
    await _runSourceActionWithFeedback(
      errorMessage: '打开编辑音源窗口失败，请稍后重试',
      onRetry: () => _showEditSourceDialog(config),
      action: () async {
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
      },
    );
  }

  // ==================== Helpers ====================

  String _getSourceTypeName(AudioSourceType type) {
    switch (type) {
      case AudioSourceType.omniparse:
        return 'OmniParse';
      case AudioSourceType.lxmusic:
        return '洛雪音乐';
      case AudioSourceType.tunehub:
        return 'TuneHub';
      case AudioSourceType.navidrome:
        return 'Navidrome';
    }
  }

  AudioSourceConfig _buildNavidromeConfig() {
    final session = NavidromeSessionService();
    return AudioSourceConfig(
      id: AudioSourceService.navidromeSourceId,
      type: AudioSourceType.navidrome,
      name: 'Navidrome',
      url: session.baseUrl,
    );
  }

  bool get _isNavidromeConfigured => NavidromeSessionService().isConfigured;

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
    final sources = _audioSourceReadController.sources;
    final navidromeConfig = _buildNavidromeConfig();
    final displaySources = [navidromeConfig, ...sources];

    if (_showNavidromeConfig) {
      final content = _buildNavidromeConfigBody(
        context,
        padding: const EdgeInsets.all(24),
      );
      if (widget.embed) return content;
      return fluent.ScaffoldPage(
        header: fluent.PageHeader(title: widget.buildFluentBreadcrumb(context)),
        content: content,
      );
    }

    final children = <Widget>[
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
                  Text('关于音源', style: theme.typography.subtitle),
                ],
              ),
              const SizedBox(height: 12),
              Text('添加并管理多个音源。您可以随时切换当前使用的音源。', style: theme.typography.body),
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
          ...displaySources.map(
            (config) => config.type == AudioSourceType.navidrome
                ? _buildFluentNavidromeCard(config, theme)
                : _buildFluentSourceCard(config, theme),
          ),
          // 添加音源按钮
          _buildFluentAddCard(theme),
        ],
      ),
    ];

    if (widget.embed) {
      return fluent.ListView(
        padding: const EdgeInsets.all(24),
        children: children,
      );
    }

    return fluent.ScaffoldPage.scrollable(
      header: fluent.PageHeader(title: widget.buildFluentBreadcrumb(context)),
      padding: const EdgeInsets.all(24),
      children: children,
    );
  }

  Widget _buildFluentSourceCard(
    AudioSourceConfig config,
    fluent.FluentThemeData theme,
  ) {
    final isActive = config.id == _audioSourceReadController.activeSource?.id;

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
                          : (config.type == AudioSourceType.tunehub
                                ? fluent.FluentIcons.globe
                                : fluent.FluentIcons.link),
                      size: 20,
                      color: isActive
                          ? theme.accentColor
                          : theme.resources.textFillColorSecondary,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        config.name,
                        style: theme.typography.subtitle?.copyWith(
                          fontSize: 16,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (isActive)
                      fluent.Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 2,
                        ),
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
                if (config.version.isNotEmpty || config.author.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(
                      '${config.version.isNotEmpty ? "版本: ${config.version}" : ""}${config.version.isNotEmpty && config.author.isNotEmpty ? " • " : ""}${config.author.isNotEmpty ? "作者: ${config.author}" : ""}',
                      style: theme.typography.caption?.copyWith(
                        color: theme.resources.textFillColorSecondary,
                      ),
                    ),
                  ),
                if (config.description.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(
                      config.description,
                      style: theme.typography.caption?.copyWith(
                        color: theme.resources.textFillColorSecondary,
                        fontStyle: FontStyle.italic,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                const SizedBox(height: 4),
                // OmniParse 类型隐藏 URL
                if (config.type == AudioSourceType.omniparse)
                  Text(
                    '已配置 (URL 已隐藏)',
                    style: theme.typography.caption?.copyWith(
                      color: theme.resources.textFillColorSecondary,
                      fontStyle: FontStyle.italic,
                    ),
                  )
                else
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
                    onPressed: _isSourceActionBusy
                        ? null
                        : () async {
                            await _setActiveSource(config.id);
                          },
                    child: const Text('启用'),
                  ),
                const SizedBox(width: 8),
                fluent.IconButton(
                  icon: const Icon(fluent.FluentIcons.edit),
                  onPressed: _isSourceActionBusy
                      ? null
                      : () => _showEditSourceDialog(config),
                ),
                const SizedBox(width: 4),
                fluent.IconButton(
                  icon: const Icon(fluent.FluentIcons.delete),
                  onPressed: _isSourceActionBusy
                      ? null
                      : () => _deleteSource(config.id),
                  style: fluent.ButtonStyle(
                    foregroundColor: WidgetStateProperty.resolveWith((states) {
                      if (states.contains(WidgetState.hovered)) return fluent.Colors.red;
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

  Widget _buildFluentNavidromeCard(
    AudioSourceConfig config,
    fluent.FluentThemeData theme,
  ) {
    final isActive = _audioSourceReadController.isNavidromeActive;
    final isConfigured = _isNavidromeConfigured;
    final subtitle = isConfigured
        ? (config.url.isNotEmpty ? config.url : '已配置')
        : '未配置';

    return SizedBox(
      width: 280,
      height: 180,
      child: fluent.Card(
        padding: const EdgeInsets.all(12),
        borderColor: isActive ? theme.accentColor : null,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      fluent.FluentIcons.server,
                      size: 20,
                      color: isActive
                          ? theme.accentColor
                          : theme.resources.textFillColorSecondary,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        config.name,
                        style: theme.typography.subtitle?.copyWith(
                          fontSize: 16,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (isActive)
                      fluent.Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 2,
                        ),
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
                Text('类型: Navidrome', style: theme.typography.caption),
                const SizedBox(height: 4),
                fluent.Tooltip(
                  message: subtitle,
                  child: Text(
                    subtitle,
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
                    onPressed: _isSourceActionBusy
                        ? null
                        : () async {
                            await _activateNavidrome(
                              openSettingsIfUnconfigured: !isConfigured,
                            );
                          },
                    child: const Text('启用'),
                  ),
                const SizedBox(width: 8),
                fluent.Button(
                  onPressed: _isSourceActionBusy
                      ? null
                      : () async {
                          await _openNavidromeSettings();
                        },
                  child: Text(isConfigured ? '配置' : '设置'),
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
        onTap: _isSourceActionBusy ? null : _showAddSourceDialog,
        child: SizedBox(
          width: 280,
          height: 180, // Same fixed height as source card
          child: fluent.Card(
            padding: EdgeInsets.zero,
            child: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    fluent.FluentIcons.add,
                    size: 24,
                    color: theme.accentColor,
                  ),
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
    final sources = _audioSourceReadController.sources;
    final navidromeConfig = _buildNavidromeConfig();
    final displaySources = [navidromeConfig, ...sources];
    final brightness = CupertinoTheme.brightnessOf(context);
    final isDark = brightness == Brightness.dark;

    // 颜色定义
    final backgroundColor = CupertinoColors.systemGroupedBackground.resolveFrom(
      context,
    );
    final cardColor = isDark
        ? const Color(0xFF2C2C2E)
        : CupertinoColors.secondarySystemGroupedBackground.resolveFrom(context);
    final labelColor = CupertinoColors.label.resolveFrom(context);
    final secondaryLabelColor = CupertinoColors.secondaryLabel.resolveFrom(
      context,
    );
    final separatorColor = CupertinoColors.separator.resolveFrom(context);

    // 构建音源类型图标
    Widget buildSourceIcon(AudioSourceConfig config, bool isActive) {
      final gradientColors = switch (config.type) {
        AudioSourceType.lxmusic => [
          const Color(0xFF667eea),
          const Color(0xFF764ba2),
        ],
        AudioSourceType.tunehub => [
          const Color(0xFF11998e),
          const Color(0xFF38ef7d),
        ],
        AudioSourceType.omniparse => [
          const Color(0xFFf093fb),
          const Color(0xFFf5576c),
        ],
        AudioSourceType.navidrome => [
          const Color(0xFF00B4DB),
          const Color(0xFF0083B0),
        ],
      };

      return Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: isActive
                ? gradientColors
                : [
                    CupertinoColors.systemGrey4.resolveFrom(context),
                    CupertinoColors.systemGrey3.resolveFrom(context),
                  ],
          ),
          borderRadius: BorderRadius.circular(10),
          boxShadow: isActive
              ? [
                  BoxShadow(
                    color: gradientColors[0].withValues(alpha: 0.3),
                    blurRadius: 8,
                    offset: const Offset(0, 4),
                  ),
                ]
              : null,
        ),
        child: Icon(
          switch (config.type) {
            AudioSourceType.lxmusic => CupertinoIcons.music_note_2,
            AudioSourceType.tunehub => CupertinoIcons.cloud,
            AudioSourceType.omniparse => CupertinoIcons.link,
            AudioSourceType.navidrome => CupertinoIcons.music_note_list,
          },
          color: CupertinoColors.white,
          size: 22,
        ),
      );
    }

    // 构建 Navidrome 卡片
    Widget buildNavidromeCard(AudioSourceConfig config, int index) {
      final isActive = _audioSourceReadController.isNavidromeActive;
      final isConfigured = _isNavidromeConfigured;
      final statusText = isConfigured
          ? (config.url.isNotEmpty ? config.url : '已配置')
          : '未配置';
      final actionColor = isActive
          ? CupertinoColors.inactiveGray.resolveFrom(context)
          : CupertinoColors.activeBlue.resolveFrom(context);

      return Padding(
        padding: EdgeInsets.only(
          left: 16,
          right: 16,
          top: index == 0 ? 0 : 8,
          bottom: 8,
        ),
        child: GestureDetector(
          onTap: _isSourceActionBusy
              ? null
              : () async {
                  await _activateNavidrome(
                    openSettingsIfUnconfigured: !isConfigured,
                  );
                },
          child: Container(
            decoration: BoxDecoration(
              color: cardColor,
              borderRadius: BorderRadius.circular(14),
              border: isActive
                  ? Border.all(
                      color: CupertinoColors.activeBlue.resolveFrom(context),
                      width: 2,
                    )
                  : null,
              boxShadow: [
                BoxShadow(
                  color: CupertinoColors.black.withValues(
                    alpha: isDark ? 0.3 : 0.08,
                  ),
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
                                      color: CupertinoColors.activeBlue
                                          .withValues(alpha: 0.15),
                                      borderRadius: BorderRadius.circular(6),
                                    ),
                                    child: Text(
                                      '使用中',
                                      style: TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.w600,
                                        color: CupertinoColors.activeBlue
                                            .resolveFrom(context),
                                        decoration: TextDecoration.none,
                                      ),
                                    ),
                                  ),
                                ],
                              ],
                            ),
                            const SizedBox(height: 4),

                            // 类型
                            Text(
                              _getSourceTypeName(config.type),
                              style: TextStyle(
                                fontSize: 13,
                                color: secondaryLabelColor,
                                decoration: TextDecoration.none,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              statusText,
                              style: TextStyle(
                                fontSize: 12,
                                color: secondaryLabelColor,
                                decoration: TextDecoration.none,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),

                      // 右侧箭头
                      Icon(
                        CupertinoIcons.chevron_right,
                        color: CupertinoColors.tertiaryLabel.resolveFrom(
                          context,
                        ),
                        size: 16,
                      ),
                    ],
                  ),
                ),

                // 分割线
                Padding(
                  padding: const EdgeInsets.only(left: 72),
                  child: Container(height: 0.5, color: separatorColor),
                ),

                // 操作按钮区
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 10,
                  ),
                  child: Row(
                    children: [
                      // 配置按钮
                      Expanded(
                        child: CupertinoButton(
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          minSize: 0,
                          onPressed: _isSourceActionBusy
                              ? null
                              : () async {
                                  await _openNavidromeSettings();
                                },
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                CupertinoIcons.gear,
                                size: 16,
                                color: CupertinoColors.activeBlue.resolveFrom(
                                  context,
                                ),
                              ),
                              const SizedBox(width: 6),
                              Text(
                                '配置',
                                style: TextStyle(
                                  fontSize: 14,
                                  color: CupertinoColors.activeBlue.resolveFrom(
                                    context,
                                  ),
                                  decoration: TextDecoration.none,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),

                      // 分割线
                      Container(width: 0.5, height: 20, color: separatorColor),

                      // 启用按钮
                      Expanded(
                        child: CupertinoButton(
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          minSize: 0,
                          onPressed: isActive || _isSourceActionBusy
                              ? null
                              : () async {
                                  await _activateNavidrome(
                                    openSettingsIfUnconfigured: !isConfigured,
                                  );
                                },
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                isActive
                                    ? CupertinoIcons.check_mark
                                    : CupertinoIcons.play_fill,
                                size: 16,
                                color: actionColor,
                              ),
                              const SizedBox(width: 6),
                              Text(
                                isActive ? '已启用' : '启用',
                                style: TextStyle(
                                  fontSize: 14,
                                  color: actionColor,
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

    // 构建单个音源卡片
    Widget buildSourceCard(AudioSourceConfig config, int index) {
      if (config.type == AudioSourceType.navidrome) {
        return buildNavidromeCard(config, index);
      }

      final isActive =
          config.id == _audioSourceReadController.activeSource?.id;

      return Padding(
        padding: EdgeInsets.only(
          left: 16,
          right: 16,
          top: index == 0 ? 0 : 8,
          bottom: 8,
        ),
        child: GestureDetector(
          onTap: isActive || _isSourceActionBusy
              ? null
              : () async {
                  await _setActiveSource(config.id);
                },
          child: Container(
            decoration: BoxDecoration(
              color: cardColor,
              borderRadius: BorderRadius.circular(14),
              border: isActive
                  ? Border.all(
                      color: CupertinoColors.activeBlue.resolveFrom(context),
                      width: 2,
                    )
                  : null,
              boxShadow: [
                BoxShadow(
                  color: CupertinoColors.black.withValues(
                    alpha: isDark ? 0.3 : 0.08,
                  ),
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
                                      color: CupertinoColors.activeBlue
                                          .withValues(alpha: 0.15),
                                      borderRadius: BorderRadius.circular(6),
                                    ),
                                    child: Text(
                                      '使用中',
                                      style: TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.w600,
                                        color: CupertinoColors.activeBlue
                                            .resolveFrom(context),
                                        decoration: TextDecoration.none,
                                      ),
                                    ),
                                  ),
                                ],
                              ],
                            ),

                            // 描述
                            if (config.description.isNotEmpty) ...[
                              const SizedBox(height: 4),
                              Text(
                                config.description,
                                style: TextStyle(
                                  fontSize: 12,
                                  color: secondaryLabelColor.withValues(
                                    alpha: 0.8,
                                  ),
                                  fontStyle: FontStyle.italic,
                                  decoration: TextDecoration.none,
                                ),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],

                            const SizedBox(height: 6),

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
                                    margin: const EdgeInsets.symmetric(
                                      horizontal: 6,
                                    ),
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
                                    margin: const EdgeInsets.symmetric(
                                      horizontal: 6,
                                    ),
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
                        color: CupertinoColors.tertiaryLabel.resolveFrom(
                          context,
                        ),
                        size: 16,
                      ),
                    ],
                  ),
                ),

                // 分割线
                Padding(
                  padding: const EdgeInsets.only(left: 72),
                  child: Container(height: 0.5, color: separatorColor),
                ),

                // 操作按钮区
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 10,
                  ),
                  child: Row(
                    children: [
                      // 编辑按钮
                      Expanded(
                        child: CupertinoButton(
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          minSize: 0,
                          onPressed: _isSourceActionBusy
                              ? null
                              : () => _showEditSourceDialog(config),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                CupertinoIcons.pencil,
                                size: 16,
                                color: CupertinoColors.activeBlue.resolveFrom(
                                  context,
                                ),
                              ),
                              const SizedBox(width: 6),
                              Text(
                                '编辑',
                                style: TextStyle(
                                  fontSize: 14,
                                  color: CupertinoColors.activeBlue.resolveFrom(
                                    context,
                                  ),
                                  decoration: TextDecoration.none,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),

                      // 分割线
                      Container(width: 0.5, height: 20, color: separatorColor),

                      // 删除按钮
                      Expanded(
                        child: CupertinoButton(
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          minSize: 0,
                          onPressed: _isSourceActionBusy
                              ? null
                              : () => _deleteSource(config.id),
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
              '暂无其他音源',
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

    final content = _showNavidromeConfig
        ? _buildNavidromeConfigBody(
            context,
            padding: const EdgeInsets.all(16),
            wrapMaterial: true,
          )
        : ListView(
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
                        color: CupertinoColors.activeBlue.withValues(
                          alpha: 0.15,
                        ),
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
              if (displaySources.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(left: 32, bottom: 8),
                  child: Text(
                    '音源列表',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                      color: secondaryLabelColor,
                      letterSpacing: -0.08,
                      decoration: TextDecoration.none,
                    ),
                  ),
                ),

              // 音源列表
              ...displaySources.asMap().entries.map(
                (entry) => buildSourceCard(entry.value, entry.key),
              ),
              if (sources.isEmpty) buildEmptyState(),

              const SizedBox(height: 24),

              // 添加按钮
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: CupertinoButton(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  color: CupertinoColors.activeBlue.resolveFrom(context),
                  borderRadius: BorderRadius.circular(12),
                  onPressed: _isSourceActionBusy ? null : _showAddSourceDialog,
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
          );

    if (widget.embed) {
      return Container(color: backgroundColor, child: content);
    }

    return CupertinoPageScaffold(
      navigationBar: CupertinoNavigationBar(
        middle: const Text('音源设置'),
        backgroundColor: backgroundColor.withValues(alpha: 0.9),
        border: null,
      ),
      backgroundColor: backgroundColor,
      child: SafeArea(child: content),
    );
  }

  Widget _buildMaterialContent(BuildContext context) {
    final sources = _audioSourceReadController.sources;
    final navidromeConfig = _buildNavidromeConfig();
    final isNavidromeConfigured = _isNavidromeConfigured;
    final isNavidromeActive = _audioSourceReadController.isNavidromeActive;
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    final content = _showNavidromeConfig
        ? _buildNavidromeConfigBody(context)
        : ListView(
            padding: const EdgeInsets.symmetric(vertical: 8),
            children: [
              // 说明卡片
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 8,
                ),
                child: Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: colorScheme.secondaryContainer.withValues(
                      alpha: 0.3,
                    ),
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
                                color: colorScheme.onSecondaryContainer
                                    .withValues(alpha: 0.8),
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
                  _buildMaterialNavidromeTile(
                    navidromeConfig,
                    theme,
                    isNavidromeActive,
                    isNavidromeConfigured,
                  ),
                  if (sources.isEmpty && !isNavidromeConfigured)
                    const Padding(
                      padding: EdgeInsets.all(24.0),
                      child: Center(child: Text('暂无已配置音源')),
                    )
                  else
                    ...sources.map((config) {
                      final isActive =
                          config.id == _audioSourceReadController.activeSource?.id;
                      return _buildMaterialSourceTile(config, theme, isActive);
                    }),
                  MD3SettingsTile(
                    leading: Icon(
                      Icons.add_circle_outline,
                      color: colorScheme.primary,
                    ),
                    title: '添加音源',
                    onTap: _isSourceActionBusy ? null : _showAddSourceDialog,
                  ),
                ],
              ),
            ],
          );

    if (widget.embed) {
      return content;
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(_showNavidromeConfig ? 'Navidrome 配置' : '音源设置'),
        centerTitle: true,
        leading: _showNavidromeConfig
            ? IconButton(
                icon: const Icon(Icons.arrow_back),
                onPressed: _closeNavidromeSettings,
              )
            : null,
      ),
      body: content,
      floatingActionButton: _showNavidromeConfig
          ? null
          : FloatingActionButton(
              onPressed: _isSourceActionBusy ? null : _showAddSourceDialog,
              elevation: 0,
              focusElevation: 0,
              hoverElevation: 0,
              disabledElevation: 0,
              highlightElevation: 0,
              backgroundColor: colorScheme.primaryContainer,
              foregroundColor: colorScheme.onPrimaryContainer,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              child: const Icon(Icons.add),
            ),
    );
  }

  Widget _buildMaterialSourceTile(
    AudioSourceConfig config,
    ThemeData theme,
    bool isActive,
  ) {
    final colorScheme = theme.colorScheme;
    return MD3SettingsTile(
      leading: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: isActive
              ? colorScheme.primaryContainer
              : colorScheme.surfaceContainerHigh,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Icon(
          config.type == AudioSourceType.lxmusic
              ? Icons.music_note
              : Icons.link,
          color: isActive
              ? colorScheme.onPrimaryContainer
              : colorScheme.onSurfaceVariant,
          size: 20,
        ),
      ),
      title: config.name,
      subtitle:
          '${_getSourceTypeName(config.type)}${config.author.isNotEmpty ? " • ${config.author}" : ""}${config.version.isNotEmpty ? " • v${config.version}" : ""} • ${isActive ? "当前使用" : "未开启"}',
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            icon: const Icon(Icons.edit_outlined, size: 20),
            onPressed: _isSourceActionBusy
                ? null
                : () => _showEditSourceDialog(config),
          ),
          IconButton(
            icon: Icon(
              Icons.delete_outline,
              size: 20,
              color: colorScheme.error,
            ),
            onPressed: _isSourceActionBusy
                ? null
                : () => _deleteSource(config.id),
          ),
        ],
      ),
      onTap: isActive || _isSourceActionBusy
          ? null
          : () async {
              await _setActiveSource(config.id);
            },
    );
  }

  Widget _buildMaterialNavidromeTile(
    AudioSourceConfig config,
    ThemeData theme,
    bool isActive,
    bool isConfigured,
  ) {
    final colorScheme = theme.colorScheme;
    final status = isConfigured
        ? (config.url.isNotEmpty ? config.url : '已配置')
        : '未配置';

    return MD3SettingsTile(
      leading: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: isActive
              ? colorScheme.primaryContainer
              : colorScheme.surfaceContainerHigh,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Icon(
          Icons.storage_outlined,
          color: isActive
              ? colorScheme.onPrimaryContainer
              : colorScheme.onSurfaceVariant,
          size: 20,
        ),
      ),
      title: config.name,
      subtitle: 'Navidrome • ${isActive ? "当前使用" : "未开启"} • $status',
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            icon: const Icon(Icons.settings_outlined, size: 20),
            onPressed: _isSourceActionBusy
                ? null
                : () async {
                    await _openNavidromeSettings();
                  },
          ),
          if (!isActive)
            IconButton(
              icon: Icon(
                Icons.check_circle_outline,
                size: 20,
                color: colorScheme.primary,
              ),
              onPressed: _isSourceActionBusy
                  ? null
                  : () async {
                      await _activateNavidrome(
                        openSettingsIfUnconfigured: !isConfigured,
                      );
                    },
            ),
        ],
      ),
      onTap: isActive || _isSourceActionBusy
          ? null
          : () async {
              await _activateNavidrome(
                openSettingsIfUnconfigured: !isConfigured,
              );
            },
    );
  }
}


