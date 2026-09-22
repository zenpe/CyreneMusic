import 'package:flutter/material.dart';
import '../../../services/playback_mode_service.dart';

/// 播放顺序设置区域 - Material Design Expressive 风格
/// 采用分段选择器风格，带弹性滑动底部指示器
class PlaybackModeSection extends StatelessWidget {
  const PlaybackModeSection({super.key});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return AnimatedBuilder(
      animation: PlaybackModeService(),
      builder: (context, _) {
        final modeService = PlaybackModeService();
        final currentMode = modeService.currentMode;

        // 获取当前选中索引
        final currentIndex = _getModeIndex(currentMode);

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
                      Icons.shuffle_rounded,
                      color: colorScheme.primary,
                      size: 20,
                    ),
                    const SizedBox(width: 10),
                    Text(
                      '播放顺序',
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

                // 分段选择器
                LayoutBuilder(
                  builder: (context, constraints) {
                    final totalWidth = constraints.maxWidth;
                    final tabWidth = totalWidth / 4;
                    const height = 88.0;

                    return SizedBox(
                      height: height,
                      child: Stack(
                        children: [
                          // 底部弹性滑动指示器
                          AnimatedPositioned(
                            duration: const Duration(milliseconds: 400),
                            curve: Curves.elasticOut,
                            bottom: 0,
                            left: currentIndex * tabWidth + (tabWidth - 32) / 2,
                            width: 32,
                            height: 4,
                            child: Container(
                              decoration: BoxDecoration(
                                color: colorScheme.primary,
                                borderRadius: BorderRadius.circular(2),
                                boxShadow: [
                                  BoxShadow(
                                    color: colorScheme.primary.withValues(alpha: 0.4),
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
                              _buildModeItem(
                                context: context,
                                icon: Icons.arrow_forward_rounded,
                                label: '顺序',
                                isSelected: currentMode == PlaybackMode.sequential,
                                onTap: () => modeService.setMode(PlaybackMode.sequential),
                                colorScheme: colorScheme,
                              ),
                              _buildModeItem(
                                context: context,
                                icon: Icons.repeat_rounded,
                                label: '循环',
                                isSelected: currentMode == PlaybackMode.loopAll,
                                onTap: () => modeService.setMode(PlaybackMode.loopAll),
                                colorScheme: colorScheme,
                              ),
                              _buildModeItem(
                                context: context,
                                icon: Icons.shuffle_rounded,
                                label: '随机',
                                isSelected: currentMode == PlaybackMode.shuffle,
                                onTap: () => modeService.setMode(PlaybackMode.shuffle),
                                colorScheme: colorScheme,
                              ),
                              _buildModeItem(
                                context: context,
                                icon: Icons.repeat_one_rounded,
                                label: '单曲',
                                isSelected: currentMode == PlaybackMode.repeatOne,
                                onTap: () => modeService.setMode(PlaybackMode.repeatOne),
                                colorScheme: colorScheme,
                              ),
                            ],
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  int _getModeIndex(PlaybackMode mode) {
    switch (mode) {
      case PlaybackMode.sequential:
        return 0;
      case PlaybackMode.loopAll:
        return 1;
      case PlaybackMode.shuffle:
        return 2;
      case PlaybackMode.repeatOne:
        return 3;
    }
  }

  /// 构建单个模式选项
  Widget _buildModeItem({
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
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOutCubic,
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // 图标容器
              AnimatedContainer(
                duration: const Duration(milliseconds: 250),
                curve: Curves.easeOutCubic,
                width: 44,
                height: 44,
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
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: isSelected
                      ? [
                          BoxShadow(
                            color: colorScheme.primary.withValues(alpha: 0.2),
                            blurRadius: 12,
                            offset: const Offset(0, 4),
                          ),
                        ]
                      : null,
                ),
                child: Icon(
                  icon,
                  color: isSelected
                      ? colorScheme.onPrimaryContainer
                      : colorScheme.onSurfaceVariant.withValues(alpha: 0.7),
                  size: 24,
                ),
              ),
              const SizedBox(height: 6),
              // 标签
              AnimatedDefaultTextStyle(
                duration: const Duration(milliseconds: 200),
                curve: Curves.easeOutCubic,
                style: TextStyle(
                  color: isSelected
                      ? colorScheme.primary
                      : colorScheme.onSurfaceVariant.withValues(alpha: 0.7),
                  fontSize: isSelected ? 13 : 12,
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
