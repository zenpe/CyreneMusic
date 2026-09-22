import 'package:flutter/material.dart';

/// 自定义颜色选择器对话框 - Material Expressive 风格重构
class CustomColorPickerDialog extends StatefulWidget {
  final Color currentColor;
  final ValueChanged<Color> onColorSelected;
  final bool isBottomSheet;

  const CustomColorPickerDialog({
    super.key,
    required this.currentColor,
    required this.onColorSelected,
    this.isBottomSheet = false,
  });

  @override
  State<CustomColorPickerDialog> createState() => _CustomColorPickerDialogState();
}

class _CustomColorPickerDialogState extends State<CustomColorPickerDialog> {
  late double _hue;
  late double _saturation;
  late double _value;
  late TextEditingController _hexController;
  bool _isInternalUpdating = false;

  @override
  void initState() {
    super.initState();
    final hsv = HSVColor.fromColor(widget.currentColor);
    _hue = hsv.hue;
    _saturation = hsv.saturation;
    _value = hsv.value;
    _hexController = TextEditingController(text: _colorToHex(_currentColor));
    _hexController.addListener(_onHexChanged);
  }

  @override
  void dispose() {
    _hexController.dispose();
    super.dispose();
  }

  void _onHexChanged() {
    if (_isInternalUpdating) return;

    final text = _hexController.text.replaceAll('#', '');
    if (text.length == 6) {
      try {
        final color = Color(int.parse('FF$text', radix: 16));
        final hsv = HSVColor.fromColor(color);
        setState(() {
          _hue = hsv.hue;
          _saturation = hsv.saturation;
          _value = hsv.value;
        });
      } catch (_) {
        // 无效的 Hex 颜色
      }
    }
  }

  String _colorToHex(Color color) {
    return color.toARGB32().toRadixString(16).substring(2).toUpperCase();
  }

  Color get _currentColor {
    return HSVColor.fromAHSV(1.0, _hue, _saturation.clamp(0.0, 1.0), _value.clamp(0.0, 1.0)).toColor();
  }

  void _updateHexFromHSV() {
    _isInternalUpdating = true;
    _hexController.text = _colorToHex(_currentColor);
    _isInternalUpdating = false;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    final content = SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 颜色预览与 Hex 输入
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: colorScheme.surfaceContainerHigh,
              borderRadius: BorderRadius.circular(24),
            ),
            child: Row(
              children: [
                // 圆形预览
                Hero(
                  tag: 'custom_color_preview',
                  child: Container(
                    width: 80,
                    height: 80,
                    decoration: BoxDecoration(
                      color: _currentColor,
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: _currentColor.withValues(alpha: 0.4),
                          blurRadius: 16,
                          spreadRadius: 2,
                        ),
                      ],
                      border: Border.all(
                        color: Colors.white,
                        width: 4,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 20),
                // Hex 输入框
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '十六进制代码',
                        style: theme.textTheme.labelMedium?.copyWith(
                          color: colorScheme.primary,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        controller: _hexController,
                        decoration: InputDecoration(
                          prefixText: '# ',
                          prefixStyle: TextStyle(
                            color: colorScheme.primary,
                            fontWeight: FontWeight.bold,
                          ),
                          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          filled: true,
                          fillColor: colorScheme.surface,
                        ),
                        style: const TextStyle(
                          fontFamily: 'monospace',
                          fontWeight: FontWeight.bold,
                          letterSpacing: 1.2,
                        ),
                        maxLength: 6,
                        buildCounter: (context, {required currentLength, required isFocused, maxLength}) => null,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 32),

          // 色相滑块
          _buildExpressiveSlider(
            label: '色相 (Hue)',
            value: _hue,
            max: 360,
            onChanged: (value) {
              setState(() => _hue = value);
              _updateHexFromHSV();
            },
            gradient: LinearGradient(
              colors: [
                for (int i = 0; i <= 360; i += 60)
                  HSVColor.fromAHSV(1.0, i.toDouble(), 1.0, 1.0).toColor(),
              ],
            ),
          ),

          const SizedBox(height: 24),

          // 饱和度滑块
          _buildExpressiveSlider(
            label: '饱和度 (Saturation)',
            value: _saturation,
            max: 1.0,
            onChanged: (value) {
              setState(() => _saturation = value);
              _updateHexFromHSV();
            },
            gradient: LinearGradient(
              colors: [
                HSVColor.fromAHSV(1.0, _hue, 0.0, _value).toColor(),
                HSVColor.fromAHSV(1.0, _hue, 1.0, _value).toColor(),
              ],
            ),
          ),

          const SizedBox(height: 24),

          // 亮度滑块
          _buildExpressiveSlider(
            label: '亮度 (Value)',
            value: _value,
            max: 1.0,
            onChanged: (value) {
              setState(() => _value = value);
              _updateHexFromHSV();
            },
            gradient: LinearGradient(
              colors: [
                Colors.black,
                HSVColor.fromAHSV(1.0, _hue, _saturation, 1.0).toColor(),
              ],
            ),
          ),

          const SizedBox(height: 24),

          // 操作按钮 (针对 BottomSheet 模式的内容内部)
          if (widget.isBottomSheet)
            Padding(
              padding: const EdgeInsets.only(top: 8, bottom: 16),
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.pop(context),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                      ),
                      child: const Text('取消'),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: FilledButton(
                      onPressed: () {
                        widget.onColorSelected(_currentColor);
                        Navigator.pop(context);
                      },
                      style: FilledButton.styleFrom(
                        backgroundColor: _currentColor,
                        foregroundColor: _currentColor.computeLuminance() > 0.5 ? Colors.black : Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                        elevation: 4,
                      ),
                      child: const Text('应用色彩'),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );

    if (widget.isBottomSheet) {
      return content;
    }

    return AlertDialog(
      title: const Text('自定义主题色'),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 400),
        child: content,
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: () {
            widget.onColorSelected(_currentColor);
            Navigator.pop(context);
          },
          style: FilledButton.styleFrom(
            backgroundColor: _currentColor,
            foregroundColor: _currentColor.computeLuminance() > 0.5 ? Colors.black : Colors.white,
          ),
          child: const Text('确定'),
        ),
      ],
    );
  }

  Widget _buildExpressiveSlider({
    required String label,
    required double value,
    required double max,
    required ValueChanged<double> onChanged,
    required Gradient gradient,
  }) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              label,
              style: theme.textTheme.labelLarge?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            Text(
              max == 360 ? '${value.round()}°' : '${(value * 100).round()}%',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.primary,
                fontWeight: FontWeight.bold,
                fontFamily: 'monospace',
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Container(
          height: 12,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(6),
            gradient: gradient,
          ),
          child: SliderTheme(
            data: SliderThemeData(
              trackHeight: 12,
              trackShape: const _ExpressiveSliderTrackShape(),
              thumbShape: _ExpressiveSliderThumbShape(color: _currentColor),
              overlayShape: const RoundSliderOverlayShape(overlayRadius: 20),
              activeTrackColor: Colors.transparent,
              inactiveTrackColor: Colors.transparent,
            ),
            child: Slider(
              value: value,
              max: max,
              onChanged: onChanged,
            ),
          ),
        ),
      ],
    );
  }
}

class _ExpressiveSliderTrackShape extends SliderTrackShape with BaseSliderTrackShape {
  const _ExpressiveSliderTrackShape();

  @override
  void paint(
    PaintingContext context,
    Offset offset, {
    required RenderBox parentBox,
    required SliderThemeData sliderTheme,
    required Animation<double> enableAnimation,
    required TextDirection textDirection,
    required Offset thumbCenter,
    Offset? secondaryOffset,
    bool isDiscrete = false,
    bool isEnabled = false,
    double additionalActiveTrackHeight = 2,
  }) {
    // 渐变已经在 Container 中绘制，这里不需要重复绘制 Track
  }
}

class _ExpressiveSliderThumbShape extends SliderComponentShape {
  final Color color;
  const _ExpressiveSliderThumbShape({required this.color});

  @override
  Size getPreferredSize(bool isEnabled, bool isDiscrete) => const Size(24, 24);

  @override
  void paint(
    PaintingContext context,
    Offset center, {
    required Animation<double> activationAnimation,
    required Animation<double> enableAnimation,
    required bool isDiscrete,
    required TextPainter labelPainter,
    required RenderBox parentBox,
    required SliderThemeData sliderTheme,
    required TextDirection textDirection,
    required double value,
    required double textScaleFactor,
    required Size sizeWithOverflow,
  }) {
    final Canvas canvas = context.canvas;

    // 外白圈
    final fillPaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.fill;

    // 投影
    final shadowPaint = Paint()
      ..color = Colors.black.withValues(alpha: 0.2)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4);

    canvas.drawCircle(center, 12, shadowPaint);
    canvas.drawCircle(center, 12, fillPaint);

    // 内色圈
    final colorPaint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;

    canvas.drawCircle(center, 8, colorPaint);

    // 描边
    final borderPaint = Paint()
      ..color = Colors.black.withValues(alpha: 0.1)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;

    canvas.drawCircle(center, 12, borderPaint);
  }
}
