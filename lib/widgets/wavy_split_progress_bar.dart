import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class WavySplitProgressBar extends StatefulWidget {
  final double value; // 0.0 to 1.0
  final ValueChanged<double>? onChanged;
  final Duration? duration;
  final bool isPlaying;
  final Color? activeColor;
  final Color? inactiveColor;
  final double height;
  final double waveAmplitude;
  final double waveFrequency;

  const WavySplitProgressBar({
    super.key,
    required this.value,
    this.onChanged,
    this.duration,
    this.isPlaying = false,
    this.activeColor,
    this.inactiveColor,
    this.height = 40.0,
    this.waveAmplitude = 4.0,
    this.waveFrequency = 0.12, // 增加频率让波浪更多
  });

  @override
  State<WavySplitProgressBar> createState() => _WavySplitProgressBarState();
}

class _WavySplitProgressBarState extends State<WavySplitProgressBar>
    with TickerProviderStateMixin {
  late AnimationController _phaseController;
  late AnimationController _amplitudeController;
  late AnimationController _bubbleController;
  late Animation<double> _bubbleAnimation;
  double? _dragValue;
  int? _lastHapticSecond;

  @override
  void initState() {
    super.initState();
    _phaseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000), // 加快流动速度
    )..repeat();

    _amplitudeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
      value: widget.isPlaying ? 1.0 : 0.0,
    );

    _bubbleController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 180),
    );
    _bubbleAnimation = CurvedAnimation(
      parent: _bubbleController,
      curve: Curves.easeOutCubic,
      reverseCurve: Curves.easeInCubic,
    );
  }

  @override
  void didUpdateWidget(WavySplitProgressBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isPlaying != oldWidget.isPlaying) {
      if (widget.isPlaying) {
        _amplitudeController.forward();
      } else {
        _amplitudeController.reverse();
      }
    }
  }

  @override
  void dispose() {
    _phaseController.dispose();
    _amplitudeController.dispose();
    _bubbleController.dispose();
    super.dispose();
  }

  String _formatBubbleTime(Duration duration) {
    if (duration.inSeconds < 0) return '00:00';
    final hours = duration.inHours;
    final minutes = duration.inMinutes % 60;
    final seconds = duration.inSeconds % 60;
    if (hours > 0) {
      return '$hours:${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
    }
    return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }

  void _handleDragStart(DragStartDetails details, double width) {
    if (width <= 0) return;
    HapticFeedback.selectionClick();
    final newValue = (details.localPosition.dx / width).clamp(0.0, 1.0);
    setState(() {
      _dragValue = newValue;
    });
    if (widget.duration != null && widget.duration!.inMilliseconds > 0) {
      _lastHapticSecond =
          ((newValue * widget.duration!.inMilliseconds).round()) ~/ 1000;
    }
    _bubbleController.forward();
  }

  void _handleDragUpdate(DragUpdateDetails details, double width) {
    if (width <= 0) return;
    final newValue = (details.localPosition.dx / width).clamp(0.0, 1.0);
    setState(() {
      _dragValue = newValue;
    });
    if (widget.duration != null && widget.duration!.inMilliseconds > 0) {
      final currentMs = (newValue * widget.duration!.inMilliseconds).round();
      final currentSecond = currentMs ~/ 1000;
      if (_lastHapticSecond != null &&
          (currentSecond ~/ 5) != (_lastHapticSecond! ~/ 5)) {
        HapticFeedback.selectionClick();
      }
      _lastHapticSecond = currentSecond;
    }
    if (widget.onChanged != null) {
      widget.onChanged!(newValue);
    }
  }

  void _handleDragEnd(DragEndDetails details) {
    HapticFeedback.mediumImpact();
    setState(() {
      _dragValue = null;
      _lastHapticSecond = null;
    });
    _bubbleController.reverse();
  }

  void _handleDragCancel() {
    setState(() {
      _dragValue = null;
      _lastHapticSecond = null;
    });
    _bubbleController.reverse();
  }

  void _handleTapDown(TapDownDetails details, double width) {
    if (width <= 0) return;
    HapticFeedback.selectionClick();
    final newValue = (details.localPosition.dx / width).clamp(0.0, 1.0);
    setState(() {
      _dragValue = newValue;
    });
    if (widget.duration != null && widget.duration!.inMilliseconds > 0) {
      _lastHapticSecond =
          ((newValue * widget.duration!.inMilliseconds).round()) ~/ 1000;
    }
    _bubbleController.forward();
    if (widget.onChanged != null) {
      widget.onChanged!(newValue);
    }
  }

  void _handleTapUp(TapUpDetails details) {
    HapticFeedback.mediumImpact();
    setState(() {
      _dragValue = null;
      _lastHapticSecond = null;
    });
    _bubbleController.reverse();
  }

  @override
  Widget build(BuildContext context) {
    final activeColor = widget.activeColor ?? Theme.of(context).colorScheme.primary;
    final inactiveColor = widget.inactiveColor ?? Theme.of(context).colorScheme.surfaceContainerHighest;

    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final currentValue = _dragValue ?? widget.value;
        final totalDuration = widget.duration ?? Duration.zero;
        final currentTargetMs =
            (currentValue.clamp(0.0, 1.0) * totalDuration.inMilliseconds).round();
        final timeStr = _formatBubbleTime(Duration(milliseconds: currentTargetMs));

        final thumbX = currentValue.clamp(0.0, 1.0) * width;
        final isHour = totalDuration.inHours > 0;
        final bubbleWidth = isHour ? 70.0 : 56.0;
        const bubbleHeight = 26.0;
        const arrowHeight = 4.5;

        final double bubbleLeft =
            (thumbX - bubbleWidth / 2).clamp(0.0, math.max(0.0, width - bubbleWidth)).toDouble();
        final double arrowCenterX =
            (thumbX - bubbleLeft).clamp(8.0, bubbleWidth - 8.0).toDouble();

        return Stack(
          clipBehavior: Clip.none,
          alignment: Alignment.center,
          children: [
            GestureDetector(
              onHorizontalDragStart: (d) => _handleDragStart(d, width),
              onHorizontalDragUpdate: (d) => _handleDragUpdate(d, width),
              onHorizontalDragEnd: _handleDragEnd,
              onHorizontalDragCancel: _handleDragCancel,
              onTapDown: (d) => _handleTapDown(d, width),
              onTapUp: _handleTapUp,
              onTapCancel: _handleDragCancel,
              child: SizedBox(
                width: width,
                height: widget.height,
                child: AnimatedBuilder(
                  animation: Listenable.merge([_phaseController, _amplitudeController]),
                  builder: (context, child) {
                    return CustomPaint(
                      painter: _WavySplitPainter(
                        value: currentValue,
                        phase: _phaseController.value * 2 * math.pi,
                        amplitudeFactor: _amplitudeController.value,
                        activeColor: activeColor,
                        inactiveColor: inactiveColor,
                        waveAmplitude: widget.waveAmplitude,
                        waveFrequency: widget.waveFrequency,
                      ),
                    );
                  },
                ),
              ),
            ),

            // 悬浮时间气泡
            Positioned(
              top: -30,
              left: bubbleLeft,
              child: IgnorePointer(
                child: AnimatedBuilder(
                  animation: _bubbleAnimation,
                  builder: (context, _) {
                    if (_bubbleAnimation.value <= 0.001) {
                      return const SizedBox.shrink();
                    }
                    return Opacity(
                      opacity: _bubbleAnimation.value,
                      child: Transform.scale(
                        scale: 0.75 + 0.25 * _bubbleAnimation.value,
                        alignment: Alignment.bottomCenter,
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Container(
                              width: bubbleWidth,
                              height: bubbleHeight,
                              decoration: BoxDecoration(
                                color: const Color(0xF21C1D26),
                                borderRadius: BorderRadius.circular(13),
                                border: Border.all(
                                  color: Colors.white.withValues(alpha: 0.22),
                                  width: 0.8,
                                ),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withValues(alpha: 0.45),
                                    blurRadius: 8,
                                    offset: const Offset(0, 3),
                                  ),
                                ],
                              ),
                              alignment: Alignment.center,
                              child: Text(
                                timeStr,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                  fontFamily: 'Consolas',
                                  letterSpacing: 0.4,
                                ),
                              ),
                            ),
                            Padding(
                              padding: EdgeInsets.only(
                                left: math.max(0.0, arrowCenterX - 4.5).toDouble(),
                              ),
                              child: CustomPaint(
                                size: const Size(9, arrowHeight),
                                painter: _WavyBubbleArrowPainter(
                                  color: const Color(0xF21C1D26),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _WavyBubbleArrowPainter extends CustomPainter {
  final Color color;
  const _WavyBubbleArrowPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;
    final path = Path()
      ..moveTo(0, 0)
      ..lineTo(size.width, 0)
      ..lineTo(size.width / 2, size.height)
      ..close();
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _WavyBubbleArrowPainter oldDelegate) =>
      color != oldDelegate.color;
}

class _WavySplitPainter extends CustomPainter {
  final double value;
  final double phase;
  final double amplitudeFactor;
  final Color activeColor;
  final Color inactiveColor;
  final double waveAmplitude;
  final double waveFrequency;

  _WavySplitPainter({
    required this.value,
    required this.phase,
    required this.amplitudeFactor,
    required this.activeColor,
    required this.inactiveColor,
    required this.waveAmplitude,
    required this.waveFrequency,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final centerY = size.height / 2;
    final progressX = size.width * value;
    final trackHeight = 6.0;
    final thumbWidth = 4.0;
    final thumbHeight = 16.0;
    final gap = 6.0; // 分割间隙

    final paint = Paint()
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..strokeWidth = trackHeight;

    // 1. 绘制已播放部分 (左侧)
    if (progressX > 0) {
      canvas.save();
      // 裁剪区域，防止波浪由于 strokeWidth 或计算误差溢出到滑块右侧
      final clipRect = Rect.fromLTWH(0, centerY - waveAmplitude - 10, progressX - thumbWidth / 2, (waveAmplitude + 10) * 2);
      canvas.clipRect(clipRect);

      final playedPath = Path();
      const step = 1.0; 
      final endX = progressX; 
      
      final startY = centerY + math.sin((0 - progressX) * waveFrequency + phase) * waveAmplitude * amplitudeFactor;
      playedPath.moveTo(0, startY);
      
      for (double x = step; x <= endX; x += step) {
        final y = centerY + math.sin((x - progressX) * waveFrequency + phase) * waveAmplitude * amplitudeFactor;
        playedPath.lineTo(x, y);
      }
      
      paint.color = activeColor;
      paint.style = PaintingStyle.stroke;
      canvas.drawPath(playedPath, paint);
      canvas.restore();
    }

    // 2. 绘制分割线 (Thumb)
    final thumbPaint = Paint()
      ..color = activeColor
      ..style = PaintingStyle.fill;
    
    final thumbRect = RRect.fromRectAndRadius(
      Rect.fromCenter(center: Offset(progressX, centerY), width: thumbWidth, height: thumbHeight),
      const Radius.circular(2),
    );
    canvas.drawRRect(thumbRect, thumbPaint);

    // 绘制未播放部分 (右侧) - 保持 gap
    if (progressX < size.width - gap) {
      final startX = progressX + gap;
      paint.color = inactiveColor;
      paint.style = PaintingStyle.stroke;
      canvas.drawLine(Offset(startX, centerY), Offset(size.width, centerY), paint);
    }
  }

  @override
  bool shouldRepaint(covariant _WavySplitPainter oldDelegate) {
    return oldDelegate.value != value ||
        oldDelegate.phase != phase ||
        oldDelegate.amplitudeFactor != amplitudeFactor ||
        oldDelegate.activeColor != activeColor ||
        oldDelegate.inactiveColor != inactiveColor;
  }
}
