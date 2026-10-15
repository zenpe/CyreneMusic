import 'package:flutter/widgets.dart';

/// Reserves text space independently of the square cover's width.
abstract final class DiscoverPlaylistCardLayout {
  static const cupertinoTitle = TextStyle(
    fontSize: 14,
    fontWeight: FontWeight.w600,
    height: 1.2,
  );
  static const cupertinoCreator = TextStyle(fontSize: 11, height: 1.2);
  static const materialTitle = TextStyle(
    fontSize: 13.5,
    fontWeight: FontWeight.w700,
    height: 1.25,
    letterSpacing: -0.1,
  );
  static const materialCreator = TextStyle(
    fontSize: 11.5,
    fontWeight: FontWeight.w500,
    height: 1.2,
  );

  static SliverGridDelegateWithFixedCrossAxisCount gridDelegate(
    BuildContext context, {
    required double width,
    required int columns,
    required double crossAxisSpacing,
    required double mainAxisSpacing,
    required bool cupertino,
  }) {
    double textHeight(TextStyle style, String text) {
      final painter = TextPainter(
        text: TextSpan(
          text: text,
          style: DefaultTextStyle.of(context).style.merge(style),
        ),
        textScaler: MediaQuery.textScalerOf(context),
        textDirection: Directionality.of(context),
        locale: Localizations.maybeLocaleOf(context),
      )..layout();
      final height = painter.height.ceilToDouble();
      painter.dispose();
      return height;
    }

    final coverWidth = (width - crossAxisSpacing * (columns - 1)) / columns;
    final textExtent =
        textHeight(cupertino ? cupertinoTitle : materialTitle, '歌单Ag\n歌单Ag') +
        textHeight(cupertino ? cupertinoCreator : materialCreator, '创建者Ag');
    return SliverGridDelegateWithFixedCrossAxisCount(
      crossAxisCount: columns,
      crossAxisSpacing: crossAxisSpacing,
      mainAxisSpacing: mainAxisSpacing,
      // Cupertino: 20px padding + 6px gap. Material: 8px + 3px gaps.
      // Round up with a small allowance for fallback-font metrics.
      mainAxisExtent: coverWidth + textExtent + (cupertino ? 26 : 11) + 4,
    );
  }
}
