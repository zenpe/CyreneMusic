import 'package:flutter/material.dart';

class FixedNavigationDockItem {
  final IconData icon;
  final IconData selectedIcon;
  final String label;

  const FixedNavigationDockItem({
    required this.icon,
    required this.selectedIcon,
    required this.label,
  });
}

/// Shared fixed navigation used by tablet and desktop layouts.
class FixedNavigationDock extends StatelessWidget {
  final List<FixedNavigationDockItem> items;
  final int selectedIndex;
  final ValueChanged<int> onSelected;
  final double? width;
  final Color? backgroundColor;
  final Color? selectedBackgroundColor;
  final Color? foregroundColor;
  final Color? selectedForegroundColor;
  final Color? dividerColor;

  const FixedNavigationDock({
    super.key,
    required this.items,
    required this.selectedIndex,
    required this.onSelected,
    this.width,
    this.backgroundColor,
    this.selectedBackgroundColor,
    this.foregroundColor,
    this.selectedForegroundColor,
    this.dividerColor,
  });

  static double widthFor(BuildContext context) {
    final windowWidth = MediaQuery.sizeOf(context).width;
    return (windowWidth * 0.09).clamp(96.0, 128.0).toDouble();
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final dockWidth = width ?? widthFor(context);
    final background = backgroundColor ?? colorScheme.surfaceContainerLow;
    final selectedBackground =
        selectedBackgroundColor ?? colorScheme.secondaryContainer;
    final foreground = foregroundColor ?? colorScheme.onSurfaceVariant;
    final selectedForeground =
        selectedForegroundColor ?? colorScheme.onSecondaryContainer;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: background,
        border: dividerColor == null
            ? null
            : Border(right: BorderSide(color: dividerColor!)),
      ),
      child: SafeArea(
        right: false,
        child: SizedBox(
          width: dockWidth,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
            child: Column(
              children: [
                for (var index = 0; index < items.length; index++)
                  _buildItem(
                    context,
                    item: items[index],
                    index: index,
                    itemWidth: dockWidth - 20,
                    foreground: foreground,
                    selectedForeground: selectedForeground,
                    selectedBackground: selectedBackground,
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildItem(
    BuildContext context, {
    required FixedNavigationDockItem item,
    required int index,
    required double itemWidth,
    required Color foreground,
    required Color selectedForeground,
    required Color selectedBackground,
  }) {
    final isSelected = selectedIndex == index;
    final itemForeground = isSelected ? selectedForeground : foreground;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Material(
        color: isSelected ? selectedBackground : Colors.transparent,
        borderRadius: BorderRadius.circular(18),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => onSelected(index),
          child: SizedBox(
            width: itemWidth,
            height: 62,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  isSelected ? item.selectedIcon : item.icon,
                  color: itemForeground,
                  size: 24,
                ),
                const SizedBox(height: 3),
                Text(
                  item.label,
                  maxLines: 1,
                  overflow: TextOverflow.fade,
                  softWrap: false,
                  style: TextStyle(
                    color: itemForeground,
                    fontSize: 11,
                    height: 1.1,
                    fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
