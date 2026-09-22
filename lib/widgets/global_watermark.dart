import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import '../features/auth/auth_feature.dart';
import 'package:intl/intl.dart';

/// 全局隐水印组件
///
/// 用于在应用最顶层绘制肉眼几乎不可见的倾斜密铺水印
class GlobalWatermark extends StatefulWidget {
  final Widget child;

  const GlobalWatermark({super.key, required this.child});

  @override
  State<GlobalWatermark> createState() => _GlobalWatermarkState();
}

class _GlobalWatermarkState extends State<GlobalWatermark> {
  final AuthFacade _authFacade = AuthFacade();
  Timer? _timer;
  String _currentTime = '';

  @override
  void initState() {
    super.initState();
    _updateTime();
    // 每分钟更新一次水印中的时间戳
    _timer = Timer.periodic(const Duration(minutes: 1), (timer) {
      if (mounted) {
        setState(() {
          _updateTime();
        });
      }
    });

    // 监听认证状态，确保登录后及时更新水印内容
    _authFacade.addAuthStateListener(_onAuthChanged);
  }

  @override
  void dispose() {
    _timer?.cancel();
    _authFacade.removeAuthStateListener(_onAuthChanged);
    super.dispose();
  }

  void _onAuthChanged() {
    if (mounted) setState(() {});
  }

  void _updateTime() {
    _currentTime = DateFormat('yyyy-MM-dd HH:mm').format(DateTime.now());
  }

  @override
  Widget build(BuildContext context) {
    // 如果没有登录，可以显示一个默认占位符或不显示（考虑到追踪目的，登录后显示更有意义）
    final user = _authFacade.currentUser;
    final watermarkText = user != null
        ? '${user.username} | ${user.email} | $_currentTime'
        : 'GUEST | ANONYMOUS | $_currentTime';

    final brightness = Theme.of(context).brightness;

    return Stack(
      children: [
        widget.child,
        // 水印层：IgnorePointer 确保不会拦截任何交互事件
        Positioned.fill(
          child: IgnorePointer(
            child: RepaintBoundary(
              child: CustomPaint(
                painter: _WatermarkPainter(
                  text: watermarkText,
                  // 调回隐形水平 (约 1.5%)
                  // 此数值在 8-bit 色深下仍保持 4-5 级的灰阶差，对比度拉满后清晰可见
                  opacity: 0.015,
                  isDark: brightness == Brightness.dark,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _WatermarkPainter extends CustomPainter {
  final String text;
  final double opacity;
  final bool isDark;

  _WatermarkPainter({
    required this.text,
    required this.opacity,
    required this.isDark,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (size.width == 0 || size.height == 0) return;

    final textPainter = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          color: (isDark ? Colors.white : Colors.black).withValues(alpha: opacity),
          fontSize: 12,
          fontWeight: FontWeight.w400,
        ),
      ),
      textDirection: ui.TextDirection.ltr,
    );

    textPainter.layout();

    final double textWidth = textPainter.width;
    final double textHeight = textPainter.height;

    // 倾斜角度
    const double angle = -math.pi / 10;

    // 间距设定
    final double stepX = textWidth + 120.0;
    final double stepY = textHeight + 120.0;

    canvas.save();

    // 将坐标原点移至屏幕中心并旋转，这样可以更简单地平铺覆盖全屏
    canvas.translate(size.width / 2, size.height / 2);
    canvas.rotate(angle);

    // 计算旋转后需要覆盖的范围（取对角线长度保证溢出覆盖）
    final double diagonal = math.sqrt(size.width * size.width + size.height * size.height);
    final int countX = (diagonal / stepX).ceil() + 2;
    final int countY = (diagonal / stepY).ceil() + 2;

    for (int i = -countX; i <= countX; i++) {
      for (int j = -countY; j <= countY; j++) {
        final double x = i * stepX - textWidth / 2;
        final double y = j * stepY - textHeight / 2;
        textPainter.paint(canvas, Offset(x, y));
      }
    }

    canvas.restore();
  }

  @override
  bool shouldRepaint(_WatermarkPainter oldDelegate) {
    return oldDelegate.text != text ||
           oldDelegate.opacity != opacity ||
           oldDelegate.isDark != isDark;
  }
}
