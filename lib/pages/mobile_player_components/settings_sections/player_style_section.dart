import 'package:flutter/material.dart';
import '../../../services/lyric_style_service.dart';

/// 播放器样式设置区域 - Material Design Expressive 风格
/// 采用大型视觉化卡片选择器
class PlayerStyleSection extends StatelessWidget {
  const PlayerStyleSection({super.key});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return AnimatedBuilder(
      animation: LyricStyleService(),
      builder: (context, _) {
        final styleService = LyricStyleService();
        final currentStyle = styleService.currentStyle;
        final alignmentIndex = styleService.currentAlignment == LyricAlignment.center ? 0 : 1;

        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: colorScheme.surfaceContainerHighest.withValues(alpha: isDark ? 0.6 : 0.8),
              borderRadius: BorderRadius.circular(28),
              border: Border.all(
                color: colorScheme.outlineVariant.withValues(alpha: 0.3),
                width: 1,
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 标题
                Row(
                  children: [
                    Icon(
                      Icons.palette_outlined,
                      color: colorScheme.primary,
                      size: 20,
                    ),
                    const SizedBox(width: 10),
                    Text(
                      '播放器样式',
                      style: TextStyle(
                        color: colorScheme.onSurface,
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        letterSpacing: -0.3,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 18),

                // 样式卡片选择
                Row(
                  children: [
                    _buildStyleCard(
                      context: context,
                      icon: Icons.water_drop_rounded,
                      label: '流体云',
                      description: '多行渐进',
                      isSelected: currentStyle == LyricStyle.fluidCloud,
                      onTap: () => styleService.setStyle(LyricStyle.fluidCloud),
                      colorScheme: colorScheme,
                      isDark: isDark,
                    ),
                    const SizedBox(width: 10),
                    _buildStyleCard(
                      context: context,
                      icon: Icons.fullscreen_rounded,
                      label: '沉浸',
                      description: '全屏横向',
                      isSelected: currentStyle == LyricStyle.immersive,
                      onTap: () => styleService.setStyle(LyricStyle.immersive),
                      colorScheme: colorScheme,
                      isDark: isDark,
                    ),
                    const SizedBox(width: 10),
                    _buildStyleCard(
                      context: context,
                      icon: Icons.music_note_rounded,
                      label: '经典',
                      description: '卡拉OK',
                      isSelected: currentStyle == LyricStyle.defaultStyle,
                      onTap: () => styleService.setStyle(LyricStyle.defaultStyle),
                      colorScheme: colorScheme,
                      isDark: isDark,
                    ),
                  ],
                ),

                const SizedBox(height: 20),

                // 歌词对齐 - 分段控制器风格
                Text(
                  '歌词对齐',
                  style: TextStyle(
                    color: colorScheme.onSurfaceVariant,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 12),

                // 分段选择器
                Container(
                  height: 48,
                  decoration: BoxDecoration(
                    color: colorScheme.surfaceContainerHigh,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      final tabWidth = constraints.maxWidth / 2;

                      return Stack(
                        children: [
                          // 滑块指示器
                          AnimatedPositioned(
                            duration: const Duration(milliseconds: 300),
                            curve: Curves.easeOutCubic,
                            left: alignmentIndex * tabWidth + 4,
                            top: 4,
                            bottom: 4,
                            width: tabWidth - 8,
                            child: Container(
                              decoration: BoxDecoration(
                                color: colorScheme.secondaryContainer,
                                borderRadius: BorderRadius.circular(12),
                                boxShadow: [
                                  BoxShadow(
                                    color: colorScheme.shadow.withValues(alpha: 0.1),
                                    blurRadius: 8,
                                    offset: const Offset(0, 2),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          // 选项按钮
                          Row(
                            children: [
                              _buildAlignmentOption(
                                context: context,
                                icon: Icons.format_align_center_rounded,
                                label: '居中显示',
                                isSelected: alignmentIndex == 0,
                                onTap: () => styleService.setAlignment(LyricAlignment.center),
                                colorScheme: colorScheme,
                              ),
                              _buildAlignmentOption(
                                context: context,
                                icon: Icons.vertical_align_top_rounded,
                                label: '顶部显示',
                                isSelected: alignmentIndex == 1,
                                onTap: () => styleService.setAlignment(LyricAlignment.top),
                                colorScheme: colorScheme,
                              ),
                            ],
                          ),
                        ],
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  /// 构建样式选择卡片
  Widget _buildStyleCard({
    required BuildContext context,
    required IconData icon,
    required String label,
    required String description,
    required bool isSelected,
    required VoidCallback onTap,
    required ColorScheme colorScheme,
    required bool isDark,
  }) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOutCubic,
          padding: const EdgeInsets.all(18),
          transform: Matrix4.identity()..scaleByDouble(isSelected ? 1.0 : 0.98, isSelected ? 1.0 : 0.98, 1.0, 1.0),
          transformAlignment: Alignment.center,
          decoration: BoxDecoration(
            gradient: isSelected
                ? LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      colorScheme.primaryContainer,
                      colorScheme.primaryContainer.withValues(alpha: 0.7),
                    ],
                  )
                : null,
            color: isSelected ? null : colorScheme.surfaceContainerHigh,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(
              color: isSelected
                  ? colorScheme.primary.withValues(alpha: 0.5)
                  : colorScheme.outlineVariant.withValues(alpha: 0.3),
              width: isSelected ? 2 : 1,
            ),
            boxShadow: isSelected
                ? [
                    BoxShadow(
                      color: colorScheme.primary.withValues(alpha: 0.2),
                      blurRadius: 16,
                      offset: const Offset(0, 6),
                    ),
                  ]
                : null,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 图标
              AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  gradient: isSelected
                      ? LinearGradient(
                          colors: [
                            colorScheme.primary.withValues(alpha: 0.3),
                            colorScheme.primary.withValues(alpha: 0.1),
                          ],
                        )
                      : null,
                  color: isSelected ? null : colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(
                  icon,
                  color: isSelected
                      ? colorScheme.primary
                      : colorScheme.onSurfaceVariant.withValues(alpha: 0.6),
                  size: 26,
                ),
              ),
              const SizedBox(height: 14),
              // 标签
              Text(
                label,
                style: TextStyle(
                  color: isSelected
                      ? colorScheme.onPrimaryContainer
                      : colorScheme.onSurface,
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.3,
                ),
              ),
              const SizedBox(height: 4),
              // 描述
              Text(
                description,
                style: TextStyle(
                  color: isSelected
                      ? colorScheme.onPrimaryContainer.withValues(alpha: 0.7)
                      : colorScheme.onSurfaceVariant.withValues(alpha: 0.7),
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 构建对齐选项
  Widget _buildAlignmentOption({
    required BuildContext context,
    required IconData icon,
    required String label,
    required bool isSelected,
    required VoidCallback onTap,
    required ColorScheme colorScheme,
  }) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: Container(
          alignment: Alignment.center,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                child: Icon(
                  icon,
                  color: isSelected
                      ? colorScheme.onSecondaryContainer
                      : colorScheme.onSurfaceVariant.withValues(alpha: 0.6),
                  size: 18,
                ),
              ),
              const SizedBox(width: 8),
              AnimatedDefaultTextStyle(
                duration: const Duration(milliseconds: 200),
                style: TextStyle(
                  color: isSelected
                      ? colorScheme.onSecondaryContainer
                      : colorScheme.onSurfaceVariant.withValues(alpha: 0.6),
                  fontSize: 13,
                  fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                ),
                child: Text(label),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
