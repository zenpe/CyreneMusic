import 'package:fluent_ui/fluent_ui.dart' as fluent;
import 'package:flutter/widgets.dart';

/// 描述面包屑节点
class HomeBreadcrumbItem {
  final String label;
  final VoidCallback? onTap;
  final bool isCurrent;
  final bool isEmphasized;

  const HomeBreadcrumbItem({
    required this.label,
    this.onTap,
    this.isCurrent = false,
    this.isEmphasized = false,
  });
}

/// Fluent UI 首页面包屑导航条
class FluentHomeBreadcrumbs extends StatelessWidget {
  final List<HomeBreadcrumbItem> items;
  final EdgeInsetsGeometry padding;

  const FluentHomeBreadcrumbs({
    super.key,
    required this.items,
    this.padding = const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
  });

  @override
  Widget build(BuildContext context) {
    final theme = fluent.FluentTheme.of(context);
    final typography = theme.typography;
    final resources = theme.resources;

    final emphasizedStyle =
        (typography.subtitle ??
                const TextStyle(fontSize: 24, fontWeight: FontWeight.w600))
            .copyWith(color: resources.textFillColorPrimary);

    final baseStyle =
        (typography.body ??
                const TextStyle(fontSize: 15, fontWeight: FontWeight.w500))
            .copyWith(color: resources.textFillColorSecondary);

    TextStyle _resolveStyle(HomeBreadcrumbItem item) {
      if (item.isCurrent) {
        return emphasizedStyle;
      }
      if (item.isEmphasized) {
        return emphasizedStyle.copyWith(
          color: resources.textFillColorSecondary,
        );
      }
      return baseStyle;
    }

    final children = <Widget>[];
    bool hasDisplayedFirst = false;

    for (var i = 0; i < items.length; i++) {
      final item = items[i];
      if (item.label.trim().isEmpty) continue;

      if (hasDisplayedFirst) {
        children.add(
          Icon(
            fluent.FluentIcons.chevron_right,
            size: 10,
            color: resources.textFillColorTertiary,
          ),
        );
      }

      final style = _resolveStyle(item);
      final hasTap = item.onTap != null && !item.isCurrent;

      if (hasTap) {
        final decoration = item.isEmphasized
            ? TextDecoration.none
            : TextDecoration.underline;
        children.add(
          fluent.HyperlinkButton(
            onPressed: item.onTap,
            style: fluent.ButtonStyle(
              padding: WidgetStatePropertyAll(EdgeInsets.zero),
            ),
            child: Text(
              item.label,
              style: style.copyWith(decoration: decoration),
            ),
          ),
        );
      } else {
        children.add(Text(item.label, style: style));
      }

      hasDisplayedFirst = true;
    }

    return Container(
      padding: padding,
      child: Wrap(
        spacing: 8,
        runSpacing: 6,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: children,
      ),
    );
  }
}
