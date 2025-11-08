import 'package:fluent_ui/fluent_ui.dart' as fluent;
import 'package:flutter/widgets.dart';

/// 面包屑节点定义
class DiscoverBreadcrumbItem {
  final String label;
  final VoidCallback? onTap;
  final bool isCurrent;
  final bool isEmphasized;

  const DiscoverBreadcrumbItem({
    required this.label,
    this.onTap,
    this.isCurrent = false,
    this.isEmphasized = false,
  });
}

/// Fluent UI 风格的发现页面包屑组件
class FluentDiscoverBreadcrumbs extends StatelessWidget {
  final List<DiscoverBreadcrumbItem> items;
  final EdgeInsetsGeometry padding;

  const FluentDiscoverBreadcrumbs({
    super.key,
    required this.items,
    this.padding = const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
  });

  @override
  Widget build(BuildContext context) {
    final theme = fluent.FluentTheme.of(context);
    final typography = theme.typography;
    final resources = theme.resources;

    final emphasizedStyle =
        (typography?.subtitle ??
                const TextStyle(fontSize: 24, fontWeight: FontWeight.w600))
            .copyWith(color: resources.textFillColorPrimary);

    final baseStyle =
        (typography?.body ??
                const TextStyle(fontSize: 15, fontWeight: FontWeight.w500))
            .copyWith(color: resources.textFillColorSecondary);

    TextStyle _resolveStyle(DiscoverBreadcrumbItem item) {
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
    bool hasDisplayed = false;

    for (final item in items) {
      final label = item.label.trim();
      if (label.isEmpty) continue;

      if (hasDisplayed) {
        children.add(
          fluent.Icon(
            fluent.FluentIcons.chevron_right,
            size: 10,
            color: resources.textFillColorTertiary,
          ),
        );
      }

      final style = _resolveStyle(item);
      if (item.onTap != null && !item.isCurrent) {
        final decoration =
            item.isEmphasized ? TextDecoration.none : TextDecoration.underline;
        children.add(
          fluent.HyperlinkButton(
            onPressed: item.onTap,
            style: fluent.ButtonStyle(
              padding: fluent.ButtonState.all(EdgeInsets.zero),
            ),
            child: Text(
              label,
              style: style.copyWith(decoration: decoration),
            ),
          ),
        );
      } else {
        children.add(Text(label, style: style));
      }

      hasDisplayed = true;
    }

    return Container(
      padding: padding,
      alignment: Alignment.centerLeft,
      child: Wrap(
        spacing: 8,
        runSpacing: 6,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: children,
      ),
    );
  }
}

