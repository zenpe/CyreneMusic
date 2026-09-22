import 'package:flutter/material.dart';
import '../../../services/sleep_timer_service.dart';
import '../mobile_player_dialogs.dart';

/// 睡眠定时器设置区域 - Material Design Expressive 风格
/// 胶囊形时间按钮 + 环形进度指示器
class SleepTimerSection extends StatelessWidget {
  const SleepTimerSection({super.key});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return AnimatedBuilder(
      animation: SleepTimerService(),
      builder: (context, _) {
        final timer = SleepTimerService();
        final isActive = timer.isActive;

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
                // 标题行
                Row(
                  children: [
                    Icon(
                      Icons.bedtime_rounded,
                      color: colorScheme.primary,
                      size: 20,
                    ),
                    const SizedBox(width: 10),
                    Text(
                      '睡眠定时器',
                      style: TextStyle(
                        color: colorScheme.onSurface,
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        letterSpacing: -0.3,
                      ),
                    ),
                    if (isActive) ...[
                      const Spacer(),
                      // 活跃状态指示器
                      _buildActiveIndicator(timer, colorScheme),
                    ],
                  ],
                ),
                const SizedBox(height: 18),

                if (isActive)
                  // 定时器运行中
                  _buildActiveState(context, timer, colorScheme)
                else
                  // 定时器未运行
                  _buildInactiveState(context, timer, colorScheme, isDark),
              ],
            ),
          ),
        );
      },
    );
  }

  /// 活跃状态指示器
  Widget _buildActiveIndicator(SleepTimerService timer, ColorScheme colorScheme) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0.8, end: 1.0),
      duration: const Duration(milliseconds: 800),
      curve: Curves.easeInOut,
      builder: (context, scale, child) {
        return Transform.scale(
          scale: scale,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  Colors.green.withValues(alpha: 0.25),
                  Colors.green.withValues(alpha: 0.15),
                ],
              ),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: Colors.green.withValues(alpha: 0.4),
                width: 1,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: Colors.green,
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: Colors.green.withValues(alpha: 0.5),
                        blurRadius: 6,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  timer.remainingTimeString,
                  style: const TextStyle(
                    color: Colors.green,
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  /// 活跃状态布局
  Widget _buildActiveState(
    BuildContext context,
    SleepTimerService timer,
    ColorScheme colorScheme,
  ) {
    return Row(
      children: [
        // 延长按钮
        Expanded(
          child: _buildActionButton(
            context: context,
            icon: Icons.add_rounded,
            label: '+15分钟',
            onTap: () {
              timer.extend(15);
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: const Text('已延长15分钟'),
                  behavior: SnackBarBehavior.floating,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              );
            },
            colorScheme: colorScheme,
            isPrimary: true,
          ),
        ),
        const SizedBox(width: 12),
        // 取消按钮
        Expanded(
          child: _buildActionButton(
            context: context,
            icon: Icons.close_rounded,
            label: '取消',
            onTap: () {
              timer.cancel();
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: const Text('定时器已取消'),
                  behavior: SnackBarBehavior.floating,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              );
            },
            colorScheme: colorScheme,
            isDestructive: true,
          ),
        ),
      ],
    );
  }

  /// 非活跃状态布局
  Widget _buildInactiveState(
    BuildContext context,
    SleepTimerService timer,
    ColorScheme colorScheme,
    bool isDark,
  ) {
    final timeOptions = [15, 30, 45, 60, 90];

    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: timeOptions.map((minutes) {
        return _buildTimePill(
          context: context,
          minutes: minutes,
          onTap: () {
            timer.setTimerByDuration(minutes);
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('定时器已设置: ${minutes}分钟后停止播放'),
                behavior: SnackBarBehavior.floating,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            );
          },
          colorScheme: colorScheme,
          isDark: isDark,
        );
      }).toList()..add(
        _buildTimePill(
          context: context,
          minutes: 0,
          label: '自定义',
          icon: Icons.edit_calendar_rounded,
          onTap: () {
            MobilePlayerDialogs.showSleepTimer(context);
          },
          colorScheme: colorScheme,
          isDark: isDark,
          isCustom: true,
        ),
      ),
    );
  }

  /// 时间胶囊按钮
  Widget _buildTimePill({
    required BuildContext context,
    required int minutes,
    required VoidCallback onTap,
    required ColorScheme colorScheme,
    required bool isDark,
    String? label,
    IconData? icon,
    bool isCustom = false,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: isCustom
                  ? [
                      colorScheme.tertiaryContainer.withValues(alpha: 0.8),
                      colorScheme.tertiaryContainer.withValues(alpha: 0.5),
                    ]
                  : [
                      colorScheme.surfaceContainerHigh,
                      colorScheme.surfaceContainerHigh.withValues(alpha: 0.7),
                    ],
            ),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: isCustom
                  ? colorScheme.tertiary.withValues(alpha: 0.3)
                  : colorScheme.outlineVariant.withValues(alpha: 0.3),
              width: 1,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon ?? Icons.timer_outlined,
                color: isCustom ? colorScheme.tertiary : colorScheme.primary,
                size: 16,
              ),
              const SizedBox(width: 6),
              Text(
                label ?? '$minutes分钟',
                style: TextStyle(
                  color: isCustom ? colorScheme.onTertiaryContainer : colorScheme.onSurface,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 操作按钮
  Widget _buildActionButton({
    required BuildContext context,
    required IconData icon,
    required String label,
    required VoidCallback onTap,
    required ColorScheme colorScheme,
    bool isPrimary = false,
    bool isDestructive = false,
  }) {
    final bgColor = isDestructive
        ? colorScheme.errorContainer
        : (isPrimary ? colorScheme.primaryContainer : colorScheme.surfaceContainerHigh);
    final fgColor = isDestructive
        ? colorScheme.onErrorContainer
        : (isPrimary ? colorScheme.onPrimaryContainer : colorScheme.onSurface);

    return Material(
      color: bgColor,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 14),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, color: fgColor, size: 20),
              const SizedBox(width: 8),
              Text(
                label,
                style: TextStyle(
                  color: fgColor,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
