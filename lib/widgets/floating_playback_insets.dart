import 'package:flutter/widgets.dart';

/// Geometry shared by the floating dock and content embedded underneath it.
/// Store only the space above the system inset: a descendant SafeArea may
/// already have consumed that inset before a scroll footer is built.
class FloatingPlaybackInsets extends InheritedWidget {
  static const dockHeight = 60.0;
  static const playerGap = 6.0;

  static double dockBottom(double systemBottom) =>
      systemBottom > 0 ? systemBottom : 16.0;

  final double extraBottom;

  const FloatingPlaybackInsets({
    super.key,
    required this.extraBottom,
    required super.child,
  });

  FloatingPlaybackInsets.cupertino({
    super.key,
    required double systemBottom,
    double? miniPlayerHeight,
    required super.child,
  }) : extraBottom =
           dockBottom(systemBottom) -
           systemBottom +
           dockHeight +
           (miniPlayerHeight == null ? 0 : playerGap + miniPlayerHeight);

  static double bottomPadding(
    BuildContext context, {
    double spacing = 16,
    double fallback = 16,
  }) {
    final insets = context
        .dependOnInheritedWidgetOfExactType<FloatingPlaybackInsets>();
    return MediaQuery.paddingOf(context).bottom +
        (insets == null ? fallback : insets.extraBottom + spacing);
  }

  @override
  bool updateShouldNotify(FloatingPlaybackInsets oldWidget) =>
      extraBottom != oldWidget.extraBottom;
}

/// Resolve padding at the footer itself, including inside descendant SafeAreas.
class FloatingPlaybackBottomSpacer extends StatelessWidget {
  final double spacing;
  final double fallback;

  const FloatingPlaybackBottomSpacer({
    super.key,
    this.spacing = 16,
    this.fallback = 16,
  });

  @override
  Widget build(BuildContext context) => SizedBox(
    height: FloatingPlaybackInsets.bottomPadding(
      context,
      spacing: spacing,
      fallback: fallback,
    ),
  );
}
