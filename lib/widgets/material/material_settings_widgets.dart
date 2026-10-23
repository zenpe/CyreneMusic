import 'package:flutter/material.dart';

/// MD3 风格的设置分组容器
class MD3SettingsSection extends StatelessWidget {
  final String? title;
  final List<Widget> children;
  final EdgeInsetsGeometry? margin;

  const MD3SettingsSection({
    super.key,
    this.title,
    required this.children,
    this.margin,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (title != null)
          Padding(
            padding: const EdgeInsets.only(left: 28, top: 16, bottom: 8, right: 28),
            child: Text(
              title!,
              style: theme.textTheme.labelLarge?.copyWith(
                color: colorScheme.primary,
                fontWeight: FontWeight.bold,
                letterSpacing: 0.1,
              ),
            ),
          ),
        Container(
          margin: margin ?? const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
          decoration: BoxDecoration(
            color: colorScheme.surfaceContainerLow,
            borderRadius: BorderRadius.circular(24),
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(
            children: children,
          ),
        ),
      ],
    );
  }
}

/// MD3 风格的设置项
class MD3SettingsTile extends StatelessWidget {
  final Widget? leading;
  final String title;
  final String? subtitle;
  final Widget? trailing;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final bool enabled;

  const MD3SettingsTile({
    super.key,
    this.leading,
    required this.title,
    this.subtitle,
    this.trailing,
    this.onTap,
    this.onLongPress,
    this.enabled = true,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return ListTile(
      leading: leading != null
          ? IconTheme.merge(
              data: IconThemeData(
                color: enabled ? colorScheme.onSurfaceVariant : colorScheme.onSurface.withValues(alpha: 0.38),
                size: 24,
              ),
              child: leading!,
            )
          : null,
      title: Text(
        title,
        style: theme.textTheme.bodyLarge?.copyWith(
          color: enabled ? colorScheme.onSurface : colorScheme.onSurface.withValues(alpha: 0.38),
          fontWeight: FontWeight.w500,
        ),
      ),
      subtitle: subtitle != null
          ? Text(
              subtitle!,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: enabled ? colorScheme.onSurfaceVariant : colorScheme.onSurface.withValues(alpha: 0.38),
              ),
            )
          : null,
      trailing: trailing != null
          ? IconTheme.merge(
              data: IconThemeData(
                color: enabled ? colorScheme.onSurfaceVariant : colorScheme.onSurface.withValues(alpha: 0.38),
                size: 18,
              ),
              child: trailing!,
            )
          : null,
      onTap: enabled ? onTap : null,
      onLongPress: enabled ? onLongPress : null,
      contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      minVerticalPadding: 16,
      enabled: enabled,
    );
  }
}

/// MD3 风格的开关设置项
class MD3SwitchTile extends StatelessWidget {
  final Widget? leading;
  final String title;
  final String? subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;
  final bool enabled;

  const MD3SwitchTile({
    super.key,
    this.leading,
    required this.title,
    this.subtitle,
    required this.value,
    required this.onChanged,
    this.enabled = true,
  });

  @override
  Widget build(BuildContext context) {
    return MD3SettingsTile(
      leading: leading,
      title: title,
      subtitle: subtitle,
      enabled: enabled,
      trailing: Switch(
        value: value,
        onChanged: enabled ? onChanged : null,
        thumbIcon: WidgetStateProperty.resolveWith<Icon?>((Set<WidgetState> states) {
          if (states.contains(WidgetState.selected)) {
            return const Icon(Icons.check);
          }
          return null;
        }),
      ),
      onTap: enabled ? () => onChanged(!value) : null,
    );
  }
}
