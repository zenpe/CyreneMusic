import 'package:flutter/material.dart';
import '../../../services/auto_collapse_service.dart';

/// 交互体验设置区域 - Material Design Expressive 风格
/// 卡片式开关布局
class InteractionSection extends StatelessWidget {
  const InteractionSection({super.key});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return AnimatedBuilder(
      animation: AutoCollapseService(),
      builder: (context, _) {
        final service = AutoCollapseService();
        final isEnabled = service.isAutoCollapseEnabled;

        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: GestureDetector(
            onTap: () => service.setAutoCollapseEnabled(!isEnabled),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 300),
              curve: Curves.easeOutCubic,
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                gradient: isEnabled
                    ? LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [
                          colorScheme.primaryContainer.withValues(alpha: 0.7),
                          colorScheme.primaryContainer.withValues(alpha: 0.4),
                        ],
                      )
                    : null,
                color: isEnabled
                    ? null
                    : colorScheme.surfaceContainerHighest.withValues(alpha: isDark ? 0.6 : 0.8),
                borderRadius: BorderRadius.circular(28),
                border: Border.all(
                  color: isEnabled
                      ? colorScheme.primary.withValues(alpha: 0.5)
                      : colorScheme.outlineVariant.withValues(alpha: 0.3),
                  width: isEnabled ? 2 : 1,
                ),
                boxShadow: isEnabled
                    ? [
                        BoxShadow(
                          color: colorScheme.primary.withValues(alpha: 0.15),
                          blurRadius: 16,
                          offset: const Offset(0, 6),
                        ),
                      ]
                    : null,
              ),
              child: Row(
                children: [
                  // 图标容器
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    width: 52,
                    height: 52,
                    decoration: BoxDecoration(
                      gradient: isEnabled
                          ? LinearGradient(
                              colors: [
                                colorScheme.primary.withValues(alpha: 0.3),
                                colorScheme.primary.withValues(alpha: 0.1),
                              ],
                            )
                          : null,
                      color: isEnabled ? null : colorScheme.surfaceContainerHigh,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Icon(
                      isEnabled
                          ? Icons.visibility_off_rounded
                          : Icons.visibility_rounded,
                      color: isEnabled
                          ? colorScheme.primary
                          : colorScheme.onSurfaceVariant.withValues(alpha: 0.6),
                      size: 26,
                    ),
                  ),
                  const SizedBox(width: 16),

                  // 文字区域
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '沉浸模式',
                          style: TextStyle(
                            color: isEnabled
                                ? colorScheme.onPrimaryContainer
                                : colorScheme.onSurface,
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            letterSpacing: -0.3,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '自动隐藏控制按钮，点击屏幕呼出',
                          style: TextStyle(
                            color: isEnabled
                                ? colorScheme.onPrimaryContainer.withValues(alpha: 0.7)
                                : colorScheme.onSurfaceVariant.withValues(alpha: 0.7),
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),

                  // 开关
                  Transform.scale(
                    scale: 1.1,
                    child: Switch(
                      value: isEnabled,
                      onChanged: (value) => service.setAutoCollapseEnabled(value),
                      activeThumbColor: colorScheme.primary,
                      activeTrackColor: colorScheme.primary.withValues(alpha: 0.3),
                      inactiveThumbColor: colorScheme.outline,
                      inactiveTrackColor: colorScheme.surfaceContainerHighest,
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
