import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:fluent_ui/fluent_ui.dart' as fluent;
import '../utils/theme_manager.dart';

/// 音源未配置状态下的精美配置提示组件
/// 适配 iOS Cupertino、Material Design 3 和 Fluent UI 三种主题
class AudioSourcePrompt extends StatefulWidget {
  final VoidCallback onConfigurePressed;
  final String? title;
  final String? subtitle;

  const AudioSourcePrompt({
    super.key,
    required this.onConfigurePressed,
    this.title,
    this.subtitle,
  });

  @override
  State<AudioSourcePrompt> createState() => _AudioSourcePromptState();
}

class _AudioSourcePromptState extends State<AudioSourcePrompt>
    with SingleTickerProviderStateMixin {
  late AnimationController _animationController;
  late Animation<double> _fadeAnimation;
  late Animation<Offset> _slideAnimation;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );
    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _animationController, curve: Curves.easeOut),
    );
    _slideAnimation = Tween<Offset>(
      begin: const Offset(0, 0.1),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _animationController, curve: Curves.easeOutCubic));
    _animationController.forward();
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  String get _title => widget.title ?? '配置音源后开始使用';
  String get _subtitle => widget.subtitle ?? '应用需要先导入洛雪音源才能播放在线音乐';

  @override
  Widget build(BuildContext context) {
    final themeManager = ThemeManager();
    final isMobile = Platform.isIOS || Platform.isAndroid;

    if (themeManager.isFluentFramework) {
      return _buildFluentPrompt(context);
    }

    if (isMobile && themeManager.isCupertinoFramework) {
      return _buildCupertinoPrompt(context);
    }

    return _buildMaterialPrompt(context);
  }

  /// Material Design 3 风格配置提示
  Widget _buildMaterialPrompt(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return FadeTransition(
      opacity: _fadeAnimation,
      child: SlideTransition(
        position: _slideAnimation,
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // 动画图标区域
                TweenAnimationBuilder<double>(
                  tween: Tween(begin: 0.8, end: 1.0),
                  duration: const Duration(milliseconds: 1200),
                  curve: Curves.elasticOut,
                  builder: (context, value, child) {
                    return Transform.scale(scale: value, child: child);
                  },
                  child: Container(
                    width: 140,
                    height: 140,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [
                          cs.tertiary.withValues(alpha: 0.15),
                          cs.secondary.withValues(alpha: 0.1),
                        ],
                      ),
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: cs.tertiary.withValues(alpha: 0.1),
                          blurRadius: 30,
                          spreadRadius: 5,
                        ),
                      ],
                    ),
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        // 外圈装饰
                        Container(
                          width: 120,
                          height: 120,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: cs.tertiary.withValues(alpha: 0.3),
                              width: 2,
                            ),
                          ),
                        ),
                        // 音源图标
                        Icon(
                          Icons.speaker_group_rounded,
                          size: 60,
                          color: cs.tertiary,
                        ),
                        // 设置图标叠加
                        Positioned(
                          right: 25,
                          bottom: 25,
                          child: Container(
                            padding: const EdgeInsets.all(6),
                            decoration: BoxDecoration(
                              color: cs.surfaceContainerHighest,
                              shape: BoxShape.circle,
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withValues(alpha: 0.1),
                                  blurRadius: 8,
                                ),
                              ],
                            ),
                            child: Icon(
                              Icons.settings_outlined,
                              size: 20,
                              color: cs.onSurfaceVariant,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 40),
                // 标题
                Text(
                  _title,
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: cs.onSurface,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 16),
                // 副标题
                Container(
                  constraints: const BoxConstraints(maxWidth: 320),
                  child: Text(
                    _subtitle,
                    style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                      color: cs.onSurfaceVariant,
                      height: 1.5,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
                const SizedBox(height: 40),
                // 功能亮点
                Container(
                  constraints: const BoxConstraints(maxWidth: 400),
                  child: Wrap(
                    spacing: 12,
                    runSpacing: 12,
                    alignment: WrapAlignment.center,
                    children: [
                      _buildFeatureChip(context, Icons.cloud_outlined, '洛雪音源', cs),
                      _buildFeatureChip(context, Icons.music_note, '多平台支持', cs),
                      _buildFeatureChip(context, Icons.high_quality, '音质可选', cs),
                    ],
                  ),
                ),
                const SizedBox(height: 48),
                // 配置按钮
                FilledButton.icon(
                  onPressed: widget.onConfigurePressed,
                  icon: const Icon(Icons.tune_rounded),
                  label: const Text('配置音源'),
                  style: FilledButton.styleFrom(
                    backgroundColor: cs.tertiary,
                    foregroundColor: cs.onTertiary,
                    padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
                    textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildFeatureChip(BuildContext context, IconData icon, String label, ColorScheme cs) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: cs.outline.withValues(alpha: 0.2)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 18, color: cs.tertiary),
          const SizedBox(width: 8),
          Text(label, style: TextStyle(color: cs.onSurface, fontWeight: FontWeight.w500)),
        ],
      ),
    );
  }

  /// iOS Cupertino 风格配置提示
  Widget _buildCupertinoPrompt(BuildContext context) {
    final isDark = CupertinoTheme.brightnessOf(context) == Brightness.dark;

    return FadeTransition(
      opacity: _fadeAnimation,
      child: SlideTransition(
        position: _slideAnimation,
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // 动画图标区域
                TweenAnimationBuilder<double>(
                  tween: Tween(begin: 0.8, end: 1.0),
                  duration: const Duration(milliseconds: 1200),
                  curve: Curves.elasticOut,
                  builder: (context, value, child) {
                    return Transform.scale(scale: value, child: child);
                  },
                  child: Container(
                    width: 140,
                    height: 140,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [
                          CupertinoColors.systemPurple.withValues(alpha: 0.15),
                          CupertinoColors.systemIndigo.withValues(alpha: 0.1),
                        ],
                      ),
                      shape: BoxShape.circle,
                    ),
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        // 外圈装饰
                        Container(
                          width: 120,
                          height: 120,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: CupertinoColors.systemPurple.withValues(alpha: 0.3),
                              width: 2,
                            ),
                          ),
                        ),
                        // 音源图标
                        Icon(
                          CupertinoIcons.speaker_3,
                          size: 60,
                          color: CupertinoColors.systemPurple,
                        ),
                        // 设置图标叠加
                        Positioned(
                          right: 25,
                          bottom: 25,
                          child: Container(
                            padding: const EdgeInsets.all(6),
                            decoration: BoxDecoration(
                              color: isDark ? const Color(0xFF2C2C2E) : CupertinoColors.white,
                              shape: BoxShape.circle,
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withValues(alpha: 0.1),
                                  blurRadius: 8,
                                ),
                              ],
                            ),
                            child: Icon(
                              CupertinoIcons.gear,
                              size: 18,
                              color: CupertinoColors.systemGrey,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 40),
                // 标题
                Text(
                  _title,
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    color: isDark ? CupertinoColors.white : CupertinoColors.black,
                    letterSpacing: -0.5,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 16),
                // 副标题
                Container(
                  constraints: const BoxConstraints(maxWidth: 320),
                  child: Text(
                    _subtitle,
                    style: TextStyle(
                      fontSize: 16,
                      color: CupertinoColors.systemGrey,
                      height: 1.5,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
                const SizedBox(height: 32),
                // 功能亮点
                Container(
                  constraints: const BoxConstraints(maxWidth: 360),
                  child: Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    alignment: WrapAlignment.center,
                    children: [
                      _buildCupertinoFeatureChip(CupertinoIcons.cloud, '洛雪音源', isDark),
                      _buildCupertinoFeatureChip(CupertinoIcons.music_note, '多平台', isDark),
                      _buildCupertinoFeatureChip(CupertinoIcons.waveform, '高音质', isDark),
                    ],
                  ),
                ),
                const SizedBox(height: 48),
                // 配置按钮
                CupertinoButton.filled(
                  onPressed: widget.onConfigurePressed,
                  borderRadius: BorderRadius.circular(12),
                  child: const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 16),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(CupertinoIcons.gear_alt_fill, size: 20),
                        SizedBox(width: 8),
                        Text('配置音源', style: TextStyle(fontWeight: FontWeight.w600)),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildCupertinoFeatureChip(IconData icon, String label, bool isDark) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF2C2C2E) : CupertinoColors.systemGrey6,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: CupertinoColors.systemPurple),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              fontSize: 14,
              color: isDark ? CupertinoColors.white : CupertinoColors.black,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  /// Fluent UI 风格配置提示
  Widget _buildFluentPrompt(BuildContext context) {
    final theme = fluent.FluentTheme.of(context);

    return FadeTransition(
      opacity: _fadeAnimation,
      child: SlideTransition(
        position: _slideAnimation,
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(40),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // 动画图标区域
                TweenAnimationBuilder<double>(
                  tween: Tween(begin: 0.8, end: 1.0),
                  duration: const Duration(milliseconds: 1200),
                  curve: Curves.elasticOut,
                  builder: (context, value, child) {
                    return Transform.scale(scale: value, child: child);
                  },
                  child: Container(
                    width: 140,
                    height: 140,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [
                          theme.accentColor.withValues(alpha: 0.15),
                          theme.accentColor.withValues(alpha: 0.05),
                        ],
                      ),
                      shape: BoxShape.circle,
                    ),
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        // 外圈装饰
                        Container(
                          width: 120,
                          height: 120,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: theme.accentColor.withValues(alpha: 0.3),
                              width: 2,
                            ),
                          ),
                        ),
                        // 音源图标
                        Icon(
                          fluent.FluentIcons.volume3,
                          size: 56,
                          color: theme.accentColor,
                        ),
                        // 设置图标叠加
                        Positioned(
                          right: 25,
                          bottom: 25,
                          child: Container(
                            padding: const EdgeInsets.all(6),
                            decoration: BoxDecoration(
                              color: theme.resources.controlAltFillColorSecondary,
                              shape: BoxShape.circle,
                            ),
                            child: Icon(
                              fluent.FluentIcons.settings,
                              size: 16,
                              color: theme.resources.textFillColorSecondary,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 40),
                // 标题
                Text(
                  _title,
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    color: theme.resources.textFillColorPrimary,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 16),
                // 副标题
                Container(
                  constraints: const BoxConstraints(maxWidth: 360),
                  child: Text(
                    _subtitle,
                    style: TextStyle(
                      fontSize: 14,
                      color: theme.resources.textFillColorSecondary,
                      height: 1.6,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
                const SizedBox(height: 32),
                // 功能亮点
                Container(
                  constraints: const BoxConstraints(maxWidth: 440),
                  child: Wrap(
                    spacing: 12,
                    runSpacing: 12,
                    alignment: WrapAlignment.center,
                    children: [
                      _buildFluentFeatureChip(fluent.FluentIcons.cloud, '洛雪音源', theme),
                      _buildFluentFeatureChip(fluent.FluentIcons.music_in_collection, '多平台支持', theme),
                      _buildFluentFeatureChip(fluent.FluentIcons.equalizer, '音质可选', theme),
                    ],
                  ),
                ),
                const SizedBox(height: 48),
                // 配置按钮
                fluent.FilledButton(
                  onPressed: widget.onConfigurePressed,
                  style: fluent.ButtonStyle(
                    padding: WidgetStatePropertyAll(
                      const EdgeInsets.symmetric(horizontal: 32, vertical: 12),
                    ),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(fluent.FluentIcons.settings, size: 16),
                      SizedBox(width: 8),
                      Text('配置音源', style: TextStyle(fontWeight: FontWeight.w600)),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildFluentFeatureChip(IconData icon, String label, fluent.FluentThemeData theme) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: theme.resources.controlAltFillColorSecondary,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: theme.resources.controlStrokeColorDefault),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: theme.accentColor),
          const SizedBox(width: 8),
          Text(
            label,
            style: TextStyle(
              color: theme.resources.textFillColorPrimary,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}
