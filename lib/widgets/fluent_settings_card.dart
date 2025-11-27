import 'package:fluent_ui/fluent_ui.dart' as fluent_ui;
import 'package:flutter/material.dart';

/// Windows 11 风格的设置分组标题
class FluentSettingsGroup extends StatelessWidget {
  final String title;
  final List<Widget> children;

  const FluentSettingsGroup({
    super.key,
    required this.title,
    required this.children,
  });

  @override
  Widget build(BuildContext context) {
    final theme = fluent_ui.FluentTheme.of(context);
    
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 分组标题
        Padding(
          padding: const EdgeInsets.only(bottom: 8.0, left: 4.0),
          child: Text(
            title,
            style: theme.typography.bodyStrong?.copyWith(
              fontSize: 14,
            ),
          ),
        ),
        
        // 每个选项都是独立的卡片，使用 2px 间距
        ...children.map((child) => Padding(
          padding: const EdgeInsets.only(bottom: 2.0),
          child: child,
        )),
      ],
    );
  }
}

/// Windows 11 风格的独立设置卡片（横向长条）
/// 
/// 特点：
/// - 圆角卡片（4px 圆角）
/// - 悬停时有微妙的背景色变化
/// - 左侧图标 + 标题/副标题，右侧操作控件
/// - 固定高度，保持一致性
class FluentSettingsTile extends StatefulWidget {
  final IconData icon;
  final String title;
  final String? subtitle;
  final Widget? trailing;
  final VoidCallback? onTap;
  final bool enabled;

  const FluentSettingsTile({
    super.key,
    required this.icon,
    required this.title,
    this.subtitle,
    this.trailing,
    this.onTap,
    this.enabled = true,
  });

  @override
  State<FluentSettingsTile> createState() => _FluentSettingsTileState();
}

class _FluentSettingsTileState extends State<FluentSettingsTile> {
  bool _isHovered = false;
  bool _isPressed = false;

  @override
  Widget build(BuildContext context) {
    final theme = fluent_ui.FluentTheme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    
    // Windows 11 设置页面的卡片背景色（更微妙的效果）
    final baseColor = theme.resources.cardBackgroundFillColorDefault;
    Color backgroundColor;
    if (!widget.enabled) {
      backgroundColor = baseColor;
    } else if (_isPressed) {
      // 按下时稍微变暗/变亮
      backgroundColor = isDark 
          ? Color.lerp(baseColor, Colors.white, 0.02)!
          : Color.lerp(baseColor, Colors.black, 0.02)!;
    } else if (_isHovered) {
      // 悬停时非常轻微的变化
      backgroundColor = isDark 
          ? Color.lerp(baseColor, Colors.white, 0.03)!
          : Color.lerp(baseColor, Colors.black, 0.015)!;
    } else {
      backgroundColor = baseColor;
    }

    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      cursor: widget.enabled && widget.onTap != null 
          ? SystemMouseCursors.click 
          : SystemMouseCursors.basic,
      child: GestureDetector(
        onTapDown: (_) => setState(() => _isPressed = true),
        onTapUp: (_) => setState(() => _isPressed = false),
        onTapCancel: () => setState(() => _isPressed = false),
        onTap: widget.enabled ? widget.onTap : null,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          curve: Curves.easeOut,
          decoration: BoxDecoration(
            color: backgroundColor,
            borderRadius: BorderRadius.circular(4),
            border: Border.all(
              color: theme.resources.cardStrokeColorDefault.withOpacity(0.1),
              width: 1,
            ),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            children: [
              // 图标
              Icon(
                widget.icon, 
                size: 20,
                color: widget.enabled 
                    ? theme.resources.textFillColorPrimary
                    : theme.resources.textFillColorDisabled,
              ),
              const SizedBox(width: 16),
              
              // 标题和副标题
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      widget.title,
                      style: theme.typography.body?.copyWith(
                        color: widget.enabled 
                            ? theme.resources.textFillColorPrimary
                            : theme.resources.textFillColorDisabled,
                      ),
                    ),
                    if (widget.subtitle != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        widget.subtitle!,
                        style: theme.typography.caption?.copyWith(
                          color: theme.resources.textFillColorSecondary,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              
              // 右侧控件
              if (widget.trailing != null) ...[
                const SizedBox(width: 12),
                widget.trailing!,
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Windows 11 风格的独立开关卡片（横向长条）
class FluentSwitchTile extends StatefulWidget {
  final IconData icon;
  final String title;
  final String? subtitle;
  final bool value;
  final ValueChanged<bool>? onChanged;

  const FluentSwitchTile({
    super.key,
    required this.icon,
    required this.title,
    this.subtitle,
    required this.value,
    this.onChanged,
  });

  @override
  State<FluentSwitchTile> createState() => _FluentSwitchTileState();
}

class _FluentSwitchTileState extends State<FluentSwitchTile> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final theme = fluent_ui.FluentTheme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    
    // Windows 11 设置页面的卡片背景色（更微妙的效果）
    final baseColor = theme.resources.cardBackgroundFillColorDefault;
    Color backgroundColor;
    if (_isHovered) {
      backgroundColor = isDark 
          ? Color.lerp(baseColor, Colors.white, 0.03)!
          : Color.lerp(baseColor, Colors.black, 0.015)!;
    } else {
      backgroundColor = baseColor;
    }

    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        curve: Curves.easeOut,
        decoration: BoxDecoration(
          color: backgroundColor,
          borderRadius: BorderRadius.circular(4),
          border: Border.all(
            color: theme.resources.cardStrokeColorDefault.withOpacity(0.1),
            width: 1,
          ),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            // 图标
            Icon(
              widget.icon, 
              size: 20,
              color: theme.resources.textFillColorPrimary,
            ),
            const SizedBox(width: 16),
            
            // 标题和副标题
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    widget.title,
                    style: theme.typography.body?.copyWith(
                      color: theme.resources.textFillColorPrimary,
                    ),
                  ),
                  if (widget.subtitle != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      widget.subtitle!,
                      style: theme.typography.caption?.copyWith(
                        color: theme.resources.textFillColorSecondary,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            
            // 开关
            const SizedBox(width: 12),
            fluent_ui.ToggleSwitch(
              checked: widget.value,
              onChanged: widget.onChanged,
            ),
          ],
        ),
      ),
    );
  }
}

/// Windows 11 风格的滑块设置卡片
class FluentSliderTile extends StatefulWidget {
  final IconData icon;
  final String title;
  final String? subtitle;
  final double value;
  final double min;
  final double max;
  final int? divisions;
  final String? valueLabel;
  final ValueChanged<double>? onChanged;

  const FluentSliderTile({
    super.key,
    required this.icon,
    required this.title,
    this.subtitle,
    required this.value,
    this.min = 0,
    this.max = 100,
    this.divisions,
    this.valueLabel,
    this.onChanged,
  });

  @override
  State<FluentSliderTile> createState() => _FluentSliderTileState();
}

class _FluentSliderTileState extends State<FluentSliderTile> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final theme = fluent_ui.FluentTheme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    
    // Windows 11 设置页面的卡片背景色（更微妙的效果）
    final baseColor = theme.resources.cardBackgroundFillColorDefault;
    Color backgroundColor;
    if (_isHovered) {
      backgroundColor = isDark 
          ? Color.lerp(baseColor, Colors.white, 0.03)!
          : Color.lerp(baseColor, Colors.black, 0.015)!;
    } else {
      backgroundColor = baseColor;
    }

    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        curve: Curves.easeOut,
        decoration: BoxDecoration(
          color: backgroundColor,
          borderRadius: BorderRadius.circular(4),
          border: Border.all(
            color: theme.resources.cardStrokeColorDefault.withOpacity(0.1),
            width: 1,
          ),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 标题行
            Row(
              children: [
                Icon(
                  widget.icon, 
                  size: 20,
                  color: theme.resources.textFillColorPrimary,
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        widget.title,
                        style: theme.typography.body?.copyWith(
                          color: theme.resources.textFillColorPrimary,
                        ),
                      ),
                      if (widget.subtitle != null) ...[
                        const SizedBox(height: 2),
                        Text(
                          widget.subtitle!,
                          style: theme.typography.caption?.copyWith(
                            color: theme.resources.textFillColorSecondary,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                if (widget.valueLabel != null)
                  Text(
                    widget.valueLabel!,
                    style: theme.typography.body?.copyWith(
                      color: theme.resources.textFillColorSecondary,
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            // 滑块
            fluent_ui.Slider(
              value: widget.value,
              min: widget.min,
              max: widget.max,
              divisions: widget.divisions,
              onChanged: widget.onChanged,
            ),
          ],
        ),
      ),
    );
  }
}
