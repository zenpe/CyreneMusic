import 'package:flutter/material.dart';

class PlayerSpeedSelector extends StatelessWidget {
  final double speed;
  final ValueChanged<double> onSelected;
  final bool compact;
  final Color textColor;
  final Color menuColor;
  final Color borderColor;
  final Color fillColor;
  final double fontSize;

  const PlayerSpeedSelector({
    super.key,
    required this.speed,
    required this.onSelected,
    this.compact = false,
    this.textColor = Colors.white,
    this.menuColor = const Color(0xD9000000),
    this.borderColor = const Color(0x3DFFFFFF),
    this.fillColor = Colors.transparent,
    this.fontSize = 12,
  });

  static const List<double> _speedOptions = [0.75, 1.0, 1.25, 1.5, 2.0];

  String _formatSpeed(double value) {
    return value.toStringAsFixed(value == value.roundToDouble() ? 0 : 2);
  }

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<double>(
      tooltip: '播放速度',
      onSelected: onSelected,
      color: menuColor,
      itemBuilder: (context) => _speedOptions
          .map(
            (value) => PopupMenuItem(
              value: value,
              child: Text(
                '${_formatSpeed(value)}x',
                style: const TextStyle(color: Colors.white),
              ),
            ),
          )
          .toList(),
      child: Container(
        padding: EdgeInsets.symmetric(
          horizontal: compact ? 6 : 8,
          vertical: compact ? 2 : 4,
        ),
        decoration: BoxDecoration(
          color: fillColor,
          border: Border.all(color: borderColor),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(
          '${_formatSpeed(speed)}x',
          style: TextStyle(
            color: textColor,
            fontSize: fontSize,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}
