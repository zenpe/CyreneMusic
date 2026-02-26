import 'dart:io' show Platform;
import 'dart:math' as math;
import 'dart:ui' as ui;
import 'dart:async';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import '../services/rhythm_service.dart';

/// 动态网格渐变背景组件 (Apple Music 风格重写版)
/// 通过多层随机位移的色块 + 深度高斯模糊实现丝滑液态效果
class MeshGradientBackground extends StatefulWidget {
  final List<Color> colors;
  final double speed;
  final Color backgroundColor;
  final bool animate;
  /// 是否使用模拟节奏（非 Windows 平台自动启用）
  final bool? simulateRhythm;

  const MeshGradientBackground({
    super.key,
    required this.colors,
    this.speed = 0.35,
    this.backgroundColor = Colors.black,
    this.animate = true,
    this.simulateRhythm,
  });

  @override
  State<MeshGradientBackground> createState() => _MeshGradientBackgroundState();
}

class _MeshGradientBackgroundState extends State<MeshGradientBackground>
    with TickerProviderStateMixin {
  late Ticker _ticker;
  
  // 性能优化：使用 ValueNotifier 替代 setState，避免整个 Widget 树重建
  final ValueNotifier<_MeshPaintData> _paintDataNotifier = ValueNotifier(
    _MeshPaintData(time: 0.0, colors: [], bassIntensity: 0.0),
  );
  
  double _time = 0.0;
  
  // 用于色彩平滑过渡的控制器
  late AnimationController _colorController;
  List<Color> _previousColors = [];
  List<Color> _currentColors = [];
  List<Color> _targetColors = [];

  // 律动相关
  StreamSubscription? _rhythmSubscription;
  double _bassIntensity = 0.0;
  double _extraTime = 0.0; // 用于根据节奏加速时间

  // 判断是否应该使用模拟节奏
  bool get _shouldSimulateRhythm {
    if (widget.simulateRhythm != null) return widget.simulateRhythm!;
    // 非 Windows 平台自动启用模拟模式
    if (kIsWeb) return true;
    return !Platform.isWindows;
  }

  @override
  void initState() {
    super.initState();
    _currentColors = _ensureMinColors(widget.colors);
    _previousColors = List.from(_currentColors);
    _targetColors = List.from(_currentColors);

    _colorController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    );

    _ticker = createTicker(_onTick);
    if (widget.animate) {
      _ticker.start();
      if (!_shouldSimulateRhythm) {
        _setupRhythmListener();
      }
    }
  }

  void _setupRhythmListener() {
    _rhythmSubscription?.cancel();
    _rhythmSubscription = RhythmService().bandsStream.listen((bands) {
      if (!mounted) return;
      setState(() {
        _bassIntensity = RhythmService().bassIntensity;
      });
    });
    // Windows 平台默认启动捕获
    RhythmService().start();
  }

  List<Color> _ensureMinColors(List<Color> colors) {
    if (colors.isEmpty) return DynamicBackgroundColorExtractor.getDefaultColors();
    List<Color> result = List.from(colors);
    // 补齐到至少 5 个颜色以保证丰富度
    while (result.length < 5) {
      result.add(result[result.length % result.length].withOpacity(0.8));
    }
    return result;
  }

  @override
  void didUpdateWidget(MeshGradientBackground oldWidget) {
    super.didUpdateWidget(oldWidget);
    
    if (!_colorsEqual(oldWidget.colors, widget.colors)) {
      _previousColors = List.from(_currentColors);
      _targetColors = _ensureMinColors(widget.colors);
      _colorController.forward(from: 0.0);
    } else if (widget.colors.isNotEmpty && _currentColors.isEmpty) {
      // 容错处理：如果当前颜色为空但新传入了颜色，强制初始化
      _targetColors = _ensureMinColors(widget.colors);
      _currentColors = List.from(_targetColors);
    }
    
    if (widget.animate != oldWidget.animate) {
      if (widget.animate) {
        _ticker.start();
        _setupRhythmListener();
      } else {
        _ticker.stop();
        _rhythmSubscription?.cancel();
        RhythmService().stop();
      }
    }
  }

  bool _colorsEqual(List<Color> a, List<Color> b) {
    if (a.length != b.length) return false;
    for (int i = 0; i < a.length; i++) {
      if (a[i].toARGB32() != b[i].toARGB32()) return false;
    }
    return true;
  }

  void _onTick(Duration elapsed) {
    if (!mounted) return;
    
    // 模拟节奏模式：使用正弦波生成平滑的强度变化
    if (_shouldSimulateRhythm) {
      final elapsedSeconds = elapsed.inMilliseconds / 1000.0;
      // 多重正弦波叠加，模拟自然的节奏感
      _bassIntensity = 0.25 + 
          0.15 * math.sin(elapsedSeconds * 2.5) + 
          0.10 * math.sin(elapsedSeconds * 1.7 + 0.5) +
          0.08 * math.sin(elapsedSeconds * 4.1 + 1.2);
      _bassIntensity = _bassIntensity.clamp(0.0, 0.8);
    }
    
    // 根据重低音强度增加额外的时间偏移，产生动态加速感
    _extraTime += _bassIntensity * 0.03;
    
    _time = (elapsed.inMilliseconds / 1000.0 * widget.speed) + _extraTime;
    
    // 更新当前色彩（平滑过渡）
    if (_colorController.isAnimating) {
      final t = Curves.easeInOut.transform(_colorController.value);
      _currentColors = List.generate(_targetColors.length, (i) {
        final startColor = i < _previousColors.length ? _previousColors[i] : _previousColors.last;
        return Color.lerp(startColor, _targetColors[i], t)!;
      });
    }
    
    // 性能优化：使用 ValueNotifier 通知重绘，而不是通过 setState 触发整个 Widget 树重建
    _paintDataNotifier.value = _MeshPaintData(
      time: _time,
      colors: List.from(_currentColors),
      bassIntensity: _bassIntensity,
    );
  }

  @override
  void dispose() {
    _ticker.dispose();
    _colorController.dispose();
    _paintDataNotifier.dispose();
    _rhythmSubscription?.cancel();
    // 注意：这里不全局停止 RhythmService，因为可能有多个背景引用，或者全局生命周期管理
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: Stack(
        children: [
          // 核心绘制层 - 使用 ValueListenableBuilder 优化重绘
          ValueListenableBuilder<_MeshPaintData>(
            valueListenable: _paintDataNotifier,
            builder: (context, data, child) {
              return CustomPaint(
                painter: _MeshGradientPainter(
                  colors: data.colors.isEmpty ? _currentColors : data.colors,
                  time: data.time,
                  backgroundColor: widget.backgroundColor,
                  bassIntensity: data.bassIntensity,
                ),
                size: Size.infinite,
              );
            },
          ),
          // 质感杂色层 (Grain/Noise) - 使用缓存优化
          const Positioned.fill(child: _CachedGrainTexture()),
        ],
      ),
    );
  }
}

class _MeshGradientPainter extends CustomPainter {
  final List<Color> colors;
  final double time;
  final Color backgroundColor;
  final double bassIntensity;

  _MeshGradientPainter({
    required this.colors,
    required this.time,
    required this.backgroundColor,
    required this.bassIntensity,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (size.width <= 0 || size.height <= 0 || colors.isEmpty) return;

    final paint = Paint()
      ..style = PaintingStyle.fill
      ..isAntiAlias = true;

    // 1. 绘制底层渐变 (参考 bg.html linear-gradient(40deg, #1a0b2e, #2e1a47))
    final bgHSL = HSLColor.fromColor(backgroundColor);
    final bgDarker = bgHSL.withLightness((bgHSL.lightness * 0.8).clamp(0.0, 1.0)).toColor();
    final bgLighter = bgHSL.withLightness((bgHSL.lightness * 1.2).clamp(0.0, 1.0)).toColor();

    final bgGradient = ui.Gradient.linear(
      Offset(0, size.height),
      Offset(size.width, 0),
      [bgDarker, bgLighter],
      [0.0, 1.0],
    );
    canvas.drawRect(Offset.zero & size, paint..shader = bgGradient);
    paint.shader = null;

    final double shortestSide = size.shortestSide;

    // 2. 绘制 5 个动态光斑 (参考 bg.html)
    // 映射颜色：确保至少有 5 个颜色
    
    // ✅ 优化 0：配置静态化，消除每帧分配
    final blobConfigs = _blobConfigs;

    // ✅ 优化 1：根据平台自动调整绘制的光斑数量
    // 移动端通常只绘制前 3 个光斑，足以覆盖大部分视野并具有良好的运动感
    final bool isMobile = Platform.isAndroid || Platform.isIOS;
    final int blobCount = isMobile ? 3 : 5;
    
    // ✅ 优化 2：预先提取颜色 HSL 提升效率
    final List<Color> boostedColors = colors.map((color) {
      final hsl = HSLColor.fromColor(color);
      return hsl
          .withSaturation((hsl.saturation + 0.1).clamp(0.4, 1.0))
          .withLightness((hsl.lightness + 0.05).clamp(0.3, 0.9))
          .toColor();
    }).toList();

    for (int i = 0; i < blobCount; i++) {
      final config = blobConfigs[i];
      final color = boostedColors[i % boostedColors.length];
      
      // ✅ 优化 3：使用内联数学公式替代闭包函数调用，消除每帧函数开销
      final double dx = config.moveFactor.dx * math.sin(time * config.moveSpeed.dx);
      final double dy = config.moveFactor.dy * math.cos(time * config.moveSpeed.dy);
      
      final centerX = size.width * (config.basePos.dx + dx);
      final centerY = size.height * (config.basePos.dy + dy);
      
      // 这里的 sizeRatio 在 mobile 上适当减小以降低像素填充率
      double radius = shortestSide * config.sizeRatio * (isMobile ? 0.8 : 1.0);
      
      final double scale = config.scaleBase + config.scaleRange * math.sin(time * config.scaleSpeed);
      radius *= scale;
      
      // 律动加成
      radius += (shortestSide * 0.1) * bassIntensity;
      
      if (radius < 10) radius = 10;

      final paintBlob = Paint()
        ..blendMode = config.blendMode
        // ✅ 优化 4：严格限制移动端的模糊半径上限，平衡视觉与性能
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, (radius * 0.35).clamp(15.0, isMobile ? 45.0 : 80.0));

      final gradient = ui.Gradient.radial(
        Offset(centerX, centerY),
        radius,
        [
          color.withOpacity(config.opacity),
          color.withOpacity(config.opacity * 0.5),
          color.withOpacity(0.0),
        ],
        const [0.0, 0.4, 1.0],
      );

      paintBlob.shader = gradient;

      canvas.save();
      if (config.rotateSpeed != 0) {
        canvas.translate(centerX, centerY);
        canvas.rotate(time * config.rotateSpeed);
        canvas.translate(-centerX, -centerY);
      }
      canvas.drawCircle(Offset(centerX, centerY), radius, paintBlob);
      canvas.restore();
    }
  }

  static const List<_BlobConfig> _blobConfigs = [
    _BlobConfig(
      basePos: Offset(-0.1, -0.1),
      sizeRatio: 0.6,
      speed: 1.0,
      blendMode: BlendMode.screen,
      moveFactor: Offset(0.2, 0.2),
      moveSpeed: Offset(0.3, 0.2),
      scaleBase: 1.0,
      scaleRange: 0.2,
      scaleSpeed: 0.4,
    ),
    _BlobConfig(
      basePos: Offset(-0.1, 1.1),
      sizeRatio: 0.7,
      speed: 0.8,
      blendMode: BlendMode.screen,
      moveFactor: Offset(0.25, -0.2),
      moveSpeed: Offset(0.25, 0.3),
      rotateSpeed: 0.2,
    ),
    _BlobConfig(
      basePos: Offset(1.1, -0.2),
      sizeRatio: 0.65,
      speed: 0.9,
      blendMode: BlendMode.screen,
      moveFactor: Offset(-0.2, 0.25),
      moveSpeed: Offset(0.35, 0.2),
      scaleBase: 1.0,
      scaleRange: 0.3,
      scaleSpeed: 0.3,
    ),
    _BlobConfig(
      basePos: Offset(1.2, 1.2),
      sizeRatio: 0.8,
      speed: 0.7,
      blendMode: BlendMode.screen,
      moveFactor: Offset(-0.25, -0.25),
      moveSpeed: Offset(0.2, 0.25),
      scaleBase: 0.8,
      scaleRange: 0.2,
      scaleSpeed: 0.3,
    ),
    _BlobConfig(
      basePos: Offset(0.5, 0.5),
      sizeRatio: 0.5,
      speed: 1.25,
      blendMode: BlendMode.overlay,
      moveFactor: Offset(0.2, -0.2),
      moveSpeed: Offset(0.5, 0.4),
      scaleBase: 1.0,
      scaleRange: 0.4,
      scaleSpeed: 0.5,
      opacity: 0.6,
    ),
  ];

  @override
  bool shouldRepaint(_MeshGradientPainter oldDelegate) => 
      oldDelegate.time != time || 
      oldDelegate.colors != colors ||
      oldDelegate.bassIntensity != bassIntensity;
}

class _BlobConfig {
  final Offset basePos;
  final double sizeRatio;
  final double speed;
  final BlendMode blendMode;
  // 优化：将闭包改为结构化参数
  final Offset moveFactor;
  final Offset moveSpeed;
  final double scaleBase;
  final double scaleRange;
  final double scaleSpeed;
  final double rotateSpeed;
  final double opacity;

  const _BlobConfig({
    required this.basePos,
    required this.sizeRatio,
    required this.speed,
    required this.blendMode,
    this.moveFactor = const Offset(0.2, 0.2),
    this.moveSpeed = const Offset(0.3, 0.3),
    this.scaleBase = 1.0,
    this.scaleRange = 0.0,
    this.scaleSpeed = 0.0,
    this.rotateSpeed = 0.0,
    this.opacity = 0.8,
  });
}

/// 性能优化：ValueNotifier 用于传递绘制数据，避免 setState 触发整个 Widget 树重建
class _MeshPaintData {
  final double time;
  final List<Color> colors;
  final double bassIntensity;
  
  _MeshPaintData({
    required this.time,
    required this.colors,
    required this.bassIntensity,
  });
}

/// 性能优化：缓存噪点图像的杂色层
/// 只在首次绘制时生成噪点，之后复用缓存的图像
class _CachedGrainTexture extends StatefulWidget {
  const _CachedGrainTexture();

  @override
  State<_CachedGrainTexture> createState() => _CachedGrainTextureState();
}

class _CachedGrainTextureState extends State<_CachedGrainTexture> {
  // 静态缓存，所有实例共享
  static ui.Image? _cachedGrainImage;
  static Size? _cachedSize;
  static bool _isGenerating = false;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final size = Size(constraints.maxWidth, constraints.maxHeight);
        
        // 检查是否需要重新生成缓存（尺寸变化）
        if (_cachedGrainImage == null || 
            _cachedSize == null ||
            (_cachedSize!.width < size.width || _cachedSize!.height < size.height)) {
          _generateGrainImage(size);
        }
        
        if (_cachedGrainImage != null) {
          return Opacity(
            opacity: 0.04,
            child: RawImage(
              image: _cachedGrainImage,
              fit: BoxFit.cover,
              width: size.width,
              height: size.height,
            ),
          );
        }
        
        // 生成中显示空白
        return const SizedBox.shrink();
      },
    );
  }

  void _generateGrainImage(Size size) async {
    if (_isGenerating) return;
    _isGenerating = true;
    
    try {
      // 使用固定的较大尺寸生成噪点图，避免频繁重新生成
      final targetSize = Size(
        math.max(size.width, 1920).ceilToDouble(),
        math.max(size.height, 1080).ceilToDouble(),
      );
      
      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder);
      
      final random = math.Random(123); // 固定种子确保一致性
      final paint = Paint()
        ..color = Colors.white.withOpacity(0.08)
        ..style = PaintingStyle.fill;
      
      // 根据尺寸调整噪点数量
      final pointCount = ((targetSize.width * targetSize.height) / 1000).clamp(1000, 3000).toInt();
      
      for (int i = 0; i < pointCount; i++) {
        final x = random.nextDouble() * targetSize.width;
        final y = random.nextDouble() * targetSize.height;
        final dotSize = 0.5 + random.nextDouble() * 0.8;
        canvas.drawRect(Rect.fromLTWH(x, y, dotSize, dotSize), paint);
      }
      
      final picture = recorder.endRecording();
      final image = await picture.toImage(
        targetSize.width.toInt(),
        targetSize.height.toInt(),
      );
      
      _cachedGrainImage = image;
      _cachedSize = targetSize;
      
      if (mounted) {
        setState(() {});
      }
    } finally {
      _isGenerating = false;
    }
  }
}

class DynamicBackgroundColorExtractor {
  static List<Color> extractColors({
    Color? vibrantColor,
    Color? mutedColor,
    Color? dominantColor,
    Color? lightVibrantColor,
    Color? darkVibrantColor,
    Color? lightMutedColor,
    Color? darkMutedColor,
  }) {
    final List<Color> result = [];
    
    // 候选池：按优先级排序
    final List<Color?> candidates = [
      vibrantColor,
      mutedColor,
      dominantColor,
      darkVibrantColor,
      lightVibrantColor,
      darkMutedColor,
      lightMutedColor,
    ];

    // 1. 基础筛选与去重
    for (final color in candidates) {
      if (color != null && !_isSimilarColor(color, result)) {
        result.add(color);
      }
    }
    
    // 3. 增强逻辑：如果颜色少于 3 个，通过色相旋转生成互补/邻近色，确保背景丰富度
    if (result.length < 3) {
      if (result.isEmpty) {
        result.addAll(getDefaultColors());
      } else {
        final baseColor = result[0];
        final hsl = HSLColor.fromColor(baseColor);
        
        // 如果只有一个颜色，生成三元色 (Triadic) + 更大的明度差异
        if (result.length == 1) {
          // 第二色：色相 +120°，明度略微调暗
          final color2 = hsl
              .withHue((hsl.hue + 120) % 360)
              .withSaturation(math.max(hsl.saturation, 0.55))
              .withLightness((hsl.lightness - 0.15).clamp(0.2, 0.75))
              .toColor();
          // 第三色：色相 +240°，明度略微调亮
          final color3 = hsl
              .withHue((hsl.hue + 240) % 360)
              .withSaturation(math.max(hsl.saturation, 0.55))
              .withLightness((hsl.lightness + 0.15).clamp(0.25, 0.8))
              .toColor();
          result.add(color2);
          result.add(color3);
        } 
        // 如果有两个颜色，生成一个互补色（色相 +180°）
        else if (result.length == 2) {
          final color3 = hsl
              .withHue((hsl.hue + 180) % 360)
              .withSaturation(math.max(hsl.saturation, 0.5))
              .withLightness((hsl.lightness + 0.1).clamp(0.25, 0.75))
              .toColor();
          result.add(color3);
        }
      }
    }
    
    // 4. 最终补齐到 5 个（通过更大的色相偏移和明度变化防止单调）
    int fillIndex = 0;
    while (result.length < 5) {
      final base = result[fillIndex % result.length];
      final hsl = HSLColor.fromColor(base);
      // 交替使用不同的偏移策略
      final hueOffset = (fillIndex % 2 == 0) ? 45.0 : -30.0;
      final lightnessOffset = (fillIndex % 2 == 0) ? 0.18 : -0.12;
      result.add(hsl
          .withHue((hsl.hue + hueOffset) % 360)
          .withLightness((hsl.lightness + lightnessOffset).clamp(0.15, 0.85))
          .toColor());
      fillIndex++;
    }
    
    return result.take(5).toList();
  }
  
  /// 色彩相似度判定 (基于 HSL 颜色空间)
  /// 使用色相、饱和度、明度三个维度综合判断，比 RGB 欧几里得距离更符合人眼感知
  static bool _isSimilarColor(Color color, List<Color> existingColors) {
    final hsl = HSLColor.fromColor(color);
    
    for (final existing in existingColors) {
      final existingHsl = HSLColor.fromColor(existing);
      
      // 计算色相差（考虑色环的循环特性，0° 和 360° 是同一个颜色）
      double hueDiff = (hsl.hue - existingHsl.hue).abs();
      if (hueDiff > 180) hueDiff = 360 - hueDiff;
      
      // 明度差
      final lightnessDiff = (hsl.lightness - existingHsl.lightness).abs();
      
      // 饱和度差
      final saturationDiff = (hsl.saturation - existingHsl.saturation).abs();
      
      // 判定规则：
      // - 色相差 < 25° 且 明度差 < 0.12 且 饱和度差 < 0.2 => 认为相似
      // - 任一维度超出阈值则认为不同
      if (hueDiff < 25 && lightnessDiff < 0.12 && saturationDiff < 0.2) {
        return true;
      }
    }
    return false;
  }

  static Color _adjustBrightness(Color color, double amount) {
    final hsl = HSLColor.fromColor(color);
    return hsl.withLightness((hsl.lightness + amount).clamp(0.0, 1.0)).toColor();
  }

  static List<Color> getDefaultColors() => const [
    Color(0xFF60A5FA), Color(0xFF1E3A5F), Color(0xFF3B82F6),
    Color(0xFF6366F1), Color(0xFF1E1B4B),
  ];
}
