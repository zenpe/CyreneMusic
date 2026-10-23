import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import '../utils/theme_manager.dart';

/// iOS 26 液态玻璃容器
/// 参考 Apple 的 Liquid Glass 设计语言，支持自定义圆角、高度与环境氛围光反射
class LiquidGlassContainer extends StatelessWidget {
  final Widget child;
  final double borderRadius;
  final double? height;
  final bool isDark;
  final Color? ambientColor;

  const LiquidGlassContainer({
    super.key,
    required this.child,
    required this.borderRadius,
    this.height,
    required this.isDark,
    this.ambientColor,
  });

  @override
  Widget build(BuildContext context) {
    final glowColor = ambientColor ?? ThemeManager.iosBlue;

    return Container(
      height: height,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(borderRadius),
        // 外部阴影
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.45 : 0.12),
            blurRadius: 28,
            offset: const Offset(0, 10),
            spreadRadius: -4,
          ),
          // 底部环境光反射
          BoxShadow(
            color: glowColor.withValues(alpha: isDark ? 0.22 : 0.12),
            blurRadius: 22,
            offset: const Offset(0, 6),
            spreadRadius: -6,
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(borderRadius),
        child: BackdropFilter(
          // 极致背景模糊
          filter: ui.ImageFilter.blur(sigmaX: 50, sigmaY: 50),
          child: CustomPaint(
            painter: LiquidGlassPainter(
              borderRadius: borderRadius,
              isDark: isDark,
            ),
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(borderRadius),
                // 半透明背景 - 增加噪点纹理与环境色渗透感
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    (isDark ? const Color(0xFF38383B) : Colors.white)
                        .withValues(alpha: isDark ? 0.72 : 0.72),
                    (isDark ? const Color(0xFF1C1C1E) : Colors.white)
                        .withValues(alpha: isDark ? 0.54 : 0.45),
                  ],
                ),
              ),
              child: Stack(
                children: [
                  // 环境氛围色微妙渗透
                  if (ambientColor != null)
                    Positioned.fill(
                      child: Container(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.centerLeft,
                            end: Alignment.centerRight,
                            colors: [
                              ambientColor!.withValues(alpha: isDark ? 0.14 : 0.08),
                              Colors.transparent,
                            ],
                          ),
                        ),
                      ),
                    ),
                  // 顶部高光 (光泽感)
                  Positioned(
                    top: 0,
                    left: 0,
                    right: 0,
                    height: (height != null && height! > 0) ? height! / 2 : 28,
                    child: Container(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            Colors.white.withValues(alpha: isDark ? 0.12 : 0.38),
                            Colors.white.withValues(alpha: 0),
                          ],
                        ),
                        borderRadius: BorderRadius.vertical(
                          top: Radius.circular(borderRadius),
                        ),
                      ),
                    ),
                  ),
                  // 实际内容
                  child,
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 液态玻璃内阴影与精细微光边框绘制器
class LiquidGlassPainter extends CustomPainter {
  final double borderRadius;
  final bool isDark;

  LiquidGlassPainter({required this.borderRadius, required this.isDark});

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Rect.fromLTWH(0, 0, size.width, size.height);
    final rrect = RRect.fromRectAndRadius(rect, Radius.circular(borderRadius));

    // 1. 绘制细腻的渐变边框
    final borderPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0
      ..shader = LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          Colors.white.withValues(alpha: isDark ? 0.32 : 0.75),
          Colors.white.withValues(alpha: isDark ? 0.06 : 0.12),
          Colors.white.withValues(alpha: isDark ? 0.06 : 0.12),
          Colors.white.withValues(alpha: isDark ? 0.22 : 0.40),
        ],
        stops: const [0.0, 0.35, 0.65, 1.0],
      ).createShader(rect);

    canvas.drawRRect(rrect.deflate(0.5), borderPaint);

    // 2. 绘制内部反光 (Inset Light)
    final innerGlowPaint = Paint()
      ..shader = RadialGradient(
        center: const Alignment(0, -0.8),
        radius: 1.0,
        colors: [
          Colors.white.withValues(alpha: isDark ? 0.12 : 0.22),
          Colors.transparent,
        ],
        stops: const [0.0, 0.7],
      ).createShader(rect);

    canvas.save();
    canvas.clipRRect(rrect);
    canvas.drawRect(rect, innerGlowPaint);
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant LiquidGlassPainter oldDelegate) {
    return oldDelegate.isDark != isDark ||
        oldDelegate.borderRadius != borderRadius;
  }
}
