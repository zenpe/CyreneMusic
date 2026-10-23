import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:fluent_ui/fluent_ui.dart' as fluent;
import '../utils/theme_manager.dart';

/// 温和空态/错误状态类型
enum WarmStateType {
  error,
  empty,
  network,
}

/// 优雅的温和情感化空态与错误状态组件
/// 用于替代生硬的感叹号与冷冰冰的错误代码提示
class WarmStateCard extends StatefulWidget {
  final WarmStateType type;
  final String? title;
  final String? message;
  final String? technicalDetails;
  final String retryText;
  final VoidCallback? onRetry;
  final VoidCallback? onSecondaryAction;
  final String? secondaryActionText;
  final EdgeInsetsGeometry margin;
  final EdgeInsetsGeometry padding;

  const WarmStateCard({
    super.key,
    this.type = WarmStateType.error,
    this.title,
    this.message,
    this.technicalDetails,
    this.retryText = '重新连接',
    this.onRetry,
    this.onSecondaryAction,
    this.secondaryActionText,
    this.margin = const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
    this.padding = const EdgeInsets.all(28),
  });

  @override
  State<WarmStateCard> createState() => _WarmStateCardState();
}

class _WarmStateCardState extends State<WarmStateCard>
    with SingleTickerProviderStateMixin {
  late AnimationController _pulseController;
  late Animation<double> _scaleAnimation;
  bool _showDetails = false;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2400),
    )..repeat(reverse: true);

    _scaleAnimation = Tween<double>(begin: 0.96, end: 1.04).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOutCubic),
    );
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  void _handleRetry() {
    HapticFeedback.lightImpact();
    widget.onRetry?.call();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;

    final defaultTitle = switch (widget.type) {
      WarmStateType.error => '未能连接到音乐星球',
      WarmStateType.network => '网络似乎开了小差',
      WarmStateType.empty => '这里空空如也',
    };

    final defaultMessage = switch (widget.type) {
      WarmStateType.error => '服务器或连接未就绪，轻触下方按钮可立即自愈重试',
      WarmStateType.network => '暂时无法获取最新榜单，请检查网络设置或稍后刷新',
      WarmStateType.empty => '暂时还没有歌曲或榜单，轻触重新获取最新推荐',
    };

    final titleText = widget.title ?? defaultTitle;
    final messageText = widget.message ?? defaultMessage;

    return Center(
      child: Container(
        margin: widget.margin,
        padding: widget.padding,
        decoration: BoxDecoration(
          color: isDark
              ? const Color(0xFF1E1F28).withValues(alpha: 0.85)
              : Colors.white.withValues(alpha: 0.95),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(
            color: isDark
                ? Colors.white.withValues(alpha: 0.08)
                : cs.outlineVariant.withValues(alpha: 0.4),
            width: 1,
          ),
          boxShadow: [
            BoxShadow(
              color: isDark
                  ? Colors.black.withValues(alpha: 0.35)
                  : cs.primary.withValues(alpha: 0.06),
              blurRadius: 24,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // 微拟物情感化插画
            _buildIllustration(cs, isDark),
            const SizedBox(height: 20),

            // 标题
            Text(
              titleText,
              textAlign: TextAlign.center,
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
                fontSize: 17,
                color: cs.onSurface,
                letterSpacing: 0.3,
              ),
            ),
            const SizedBox(height: 8),

            // 暖心文案
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 320),
              child: Text(
                messageText,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: cs.onSurfaceVariant.withValues(alpha: 0.85),
                  fontSize: 13,
                  height: 1.45,
                ),
              ),
            ),

            // 技术细节折叠区 (避免粗暴红字代码吓到用户，但方便诊断)
            if (widget.technicalDetails != null &&
                widget.technicalDetails!.isNotEmpty) ...[
              const SizedBox(height: 12),
              InkWell(
                onTap: () {
                  HapticFeedback.selectionClick();
                  setState(() => _showDetails = !_showDetails);
                },
                borderRadius: BorderRadius.circular(12),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        _showDetails ? '收起诊断信息' : '查看诊断信息',
                        style: TextStyle(
                          fontSize: 11,
                          color: cs.primary.withValues(alpha: 0.85),
                        ),
                      ),
                      Icon(
                        _showDetails
                            ? Icons.keyboard_arrow_up
                            : Icons.keyboard_arrow_down,
                        size: 14,
                        color: cs.primary.withValues(alpha: 0.85),
                      ),
                    ],
                  ),
                ),
              ),
              if (_showDetails)
                Container(
                  margin: const EdgeInsets.only(top: 8),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: isDark
                        ? Colors.black.withValues(alpha: 0.35)
                        : Colors.grey.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    widget.technicalDetails!,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontFamily: 'Consolas',
                      fontSize: 11,
                      color: isDark ? const Color(0xFFEF9A9A) : Colors.red[800],
                    ),
                  ),
                ),
            ],

            const SizedBox(height: 22),

            // 自愈操作按钮组
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (widget.onSecondaryAction != null) ...[
                  TextButton(
                    onPressed: () {
                      HapticFeedback.lightImpact();
                      widget.onSecondaryAction!();
                    },
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 10,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(20),
                      ),
                    ),
                    child: Text(
                      widget.secondaryActionText ?? '切换音源',
                      style: TextStyle(
                        fontSize: 13,
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                ],

                if (widget.onRetry != null)
                  ThemeManager().isFluentFramework
                      ? fluent.FilledButton(
                          onPressed: _handleRetry,
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(fluent.FluentIcons.refresh, size: 14),
                              const SizedBox(width: 6),
                              Text(widget.retryText),
                            ],
                          ),
                        )
                      : ElevatedButton.icon(
                          onPressed: _handleRetry,
                          icon: const Icon(Icons.refresh_rounded, size: 16),
                          label: Text(
                            widget.retryText,
                            style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: cs.primary,
                            foregroundColor: cs.onPrimary,
                            elevation: 0,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 20,
                              vertical: 11,
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(22),
                            ),
                            shadowColor: cs.primary.withValues(alpha: 0.35),
                          ),
                        ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  /// 构建微拟物黑胶唱片/音符插画
  Widget _buildIllustration(ColorScheme cs, bool isDark) {
    return ScaleTransition(
      scale: _scaleAnimation,
      child: Stack(
        alignment: Alignment.center,
        children: [
          // 柔和弥散光晕
          Container(
            width: 80,
            height: 80,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: (widget.type == WarmStateType.empty
                          ? cs.primary
                          : const Color(0xFFFF8A65))
                      .withValues(alpha: 0.22),
                  blurRadius: 36,
                  spreadRadius: 8,
                ),
              ],
            ),
          ),

          // 黑胶/音符拟物圆盘
          Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: isDark
                    ? [
                        const Color(0xFF2C2D3A),
                        const Color(0xFF181922),
                      ]
                    : [
                        Colors.grey[100]!,
                        Colors.grey[200]!,
                      ],
              ),
              border: Border.all(
                color: isDark
                    ? Colors.white.withValues(alpha: 0.12)
                    : Colors.white,
                width: 2,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.18),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Stack(
              alignment: Alignment.center,
              children: [
                // 唱片同心圆凹槽纹理
                Container(
                  width: 50,
                  height: 50,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: isDark
                          ? Colors.white.withValues(alpha: 0.05)
                          : Colors.black.withValues(alpha: 0.04),
                      width: 1,
                    ),
                  ),
                ),
                Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: cs.primary.withValues(alpha: 0.15),
                  ),
                ),
                // 核心图标
                Icon(
                  widget.type == WarmStateType.empty
                      ? Icons.music_note_rounded
                      : (widget.type == WarmStateType.network
                          ? Icons.wifi_off_rounded
                          : Icons.radio_rounded),
                  size: 28,
                  color: widget.type == WarmStateType.empty
                      ? cs.primary
                      : const Color(0xFFFFAB91),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// 适用于紧凑区域（如首页“猜你喜欢”或卡片占位）的温和微卡片
class WarmCompactEmptyCard extends StatelessWidget {
  final String title;
  final String subtitle;
  final IconData icon;
  final VoidCallback? onTap;
  final String actionLabel;

  const WarmCompactEmptyCard({
    super.key,
    required this.title,
    required this.subtitle,
    this.icon = Icons.auto_awesome_rounded,
    this.onTap,
    this.actionLabel = '探索榜单',
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () {
          HapticFeedback.lightImpact();
          onTap?.call();
        },
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(
            color: isDark
                ? const Color(0xFF1E1F29).withValues(alpha: 0.6)
                : cs.surfaceContainer.withValues(alpha: 0.5),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: isDark
                  ? Colors.white.withValues(alpha: 0.06)
                  : cs.outlineVariant.withValues(alpha: 0.3),
            ),
          ),
          child: Row(
            children: [
              // 微光图标胶囊
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: cs.primary.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: cs.primary, size: 22),
              ),
              const SizedBox(width: 14),

              // 文案
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                        color: cs.onSurface,
                        fontSize: 13,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 3),
                    Text(
                      subtitle,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: cs.onSurfaceVariant.withValues(alpha: 0.8),
                        fontSize: 11,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),

              // 胶囊动作提示
              if (onTap != null) ...[
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 5,
                  ),
                  decoration: BoxDecoration(
                    color: cs.primary.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    actionLabel,
                    style: TextStyle(
                      color: cs.primary,
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// 猜你喜欢专属的微光骨架屏（Shimmer 占位）
class GuessYouLikeShimmerSkeleton extends StatefulWidget {
  const GuessYouLikeShimmerSkeleton({super.key});

  @override
  State<GuessYouLikeShimmerSkeleton> createState() =>
      _GuessYouLikeShimmerSkeletonState();
}

class _GuessYouLikeShimmerSkeletonState
    extends State<GuessYouLikeShimmerSkeleton>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final baseColor = isDark
        ? const Color(0xFF282835)
        : const Color(0xFFE4E4E8);
    final highlightColor = isDark
        ? const Color(0xFF383848)
        : const Color(0xFFF4F4F8);

    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        final gradient = LinearGradient(
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
          colors: [baseColor, highlightColor, baseColor],
          stops: [
            (_controller.value - 0.3).clamp(0.0, 1.0),
            _controller.value.clamp(0.0, 1.0),
            (_controller.value + 0.3).clamp(0.0, 1.0),
          ],
        );

        return Row(
          children: [
            // 封面占位骨架
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                gradient: gradient,
              ),
            ),
            const SizedBox(width: 14),

            // 歌曲条目骨架 (3 条)
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: List.generate(3, (index) {
                  final widths = [0.85, 0.65, 0.75];
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4.0),
                    child: Container(
                      height: 12,
                      width: MediaQuery.of(context).size.width * widths[index],
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(6),
                        gradient: gradient,
                      ),
                    ),
                  );
                }),
              ),
            ),
          ],
        );
      },
    );
  }
}
