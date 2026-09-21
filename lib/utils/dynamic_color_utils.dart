import 'package:flutter/material.dart';

/// 动态色彩自适应工具类 (Apple Music 风格流光联动)
class DynamicColorUtils {
  /// 默认品牌强调色（青绿 fallback）
  static const Color defaultBrandAccent = Color(0xFF0D9488);

  /// 计算适合作为前景/交互控件（播放按钮、进度条、高光胶囊等）的强调色
  /// 自动根据深浅色模式与对比度阈值调整亮度与饱和度，确保文字和图标永远高对比清晰
  static Color resolveAccent(
    Color? extractedColor,
    ColorScheme colorScheme, {
    required bool isDark,
  }) {
    if (extractedColor == null) {
      return colorScheme.primary;
    }

    final hsl = HSLColor.fromColor(extractedColor);

    // 如果提取出的颜色饱和度极低或过黑/过白（如黑白单色封面《河流》）
    if (hsl.saturation < 0.12 ||
        (!isDark && hsl.lightness < 0.15) ||
        (isDark && hsl.lightness > 0.85)) {
      return colorScheme.primary;
    }

    // 保证在亮色和暗色模式下都有出色的对比度与视觉张力
    if (isDark) {
      final safeL = hsl.lightness.clamp(0.48, 0.76);
      final safeS = hsl.saturation.clamp(0.40, 1.0);
      return hsl.withLightness(safeL).withSaturation(safeS).toColor();
    } else {
      final safeL = hsl.lightness.clamp(0.28, 0.50);
      final safeS = hsl.saturation.clamp(0.50, 1.0);
      return hsl.withLightness(safeL).withSaturation(safeS).toColor();
    }
  }

  /// 计算适合作为大面积环境流光/底座微弱背景的光晕色
  /// 避免在浅色模式下出现脏灰或死黑污渍感
  static Color resolveAmbient(
    Color? extractedColor,
    ColorScheme colorScheme, {
    required bool isDark,
  }) {
    if (extractedColor == null) {
      return colorScheme.primary;
    }

    final hsl = HSLColor.fromColor(extractedColor);
    if (!isDark && hsl.lightness < 0.35) {
      // 浅色模式下，过深颜色提亮为柔和雅致色调，防止在白色背景上发灰发黑
      final safeS = (hsl.saturation * 1.2).clamp(0.25, 0.85);
      return hsl.withLightness(0.52).withSaturation(safeS).toColor();
    } else if (isDark && hsl.lightness > 0.8) {
      // 深色模式下，过浅颜色适当压暗
      return hsl.withLightness(0.45).toColor();
    }
    return extractedColor;
  }
}
