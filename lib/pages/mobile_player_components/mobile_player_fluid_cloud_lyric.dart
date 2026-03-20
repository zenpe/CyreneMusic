import 'dart:async';
import 'dart:math' as math;
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import '../../services/player_service.dart';
import '../../services/lyric_font_service.dart';
import '../../services/lyric_style_service.dart';
import '../../models/lyric_line.dart';

/// 移动端流体云样式歌词组件 (v2 - 移植桌面端新版动画)
/// 核心改进：Stack 布局 + 弹性间距动画 + 波浪式延迟
class MobilePlayerFluidCloudLyric extends StatefulWidget {
  final List<LyricLine> lyrics;
  final int currentLyricIndex;
  final LyricLoadState lyricState;
  final bool showTranslation;
  final VoidCallback? onTap;

  const MobilePlayerFluidCloudLyric({
    super.key,
    required this.lyrics,
    required this.currentLyricIndex,
    this.lyricState = LyricLoadState.idle,
    this.showTranslation = true,
    this.onTap,
  });

  @override
  State<MobilePlayerFluidCloudLyric> createState() => _MobilePlayerFluidCloudLyricState();
}

class _MobilePlayerFluidCloudLyricState extends State<MobilePlayerFluidCloudLyric>
    with TickerProviderStateMixin {
  // 核心变量 - 移动端行高适配
  final double _lineHeight = 48.0;

  // 滚动/拖拽相关
  double _dragOffset = 0.0;
  bool _isDragging = false;
  Timer? _dragResetTimer;
  int? _selectedLyricIndex;
  
  // 时间胶囊动画
  AnimationController? _timeCapsuleAnimationController;
  Animation<double>? _timeCapsuleFadeAnimation;

  // 布局缓存
  final Map<String, double> _heightCache = {};
  double? _lastViewportWidth;
  String? _lastFontFamily;
  bool? _lastShowTranslation;

  @override
  void initState() {
    super.initState();
    _timeCapsuleAnimationController = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );
    _timeCapsuleFadeAnimation = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(
      parent: _timeCapsuleAnimationController!,
      curve: Curves.easeInOut,
    ));
  }

  @override
  void dispose() {
    _dragResetTimer?.cancel();
    _timeCapsuleAnimationController?.dispose();
    super.dispose();
  }

  // 拖拽手势处理
  void _onDragStart(DragStartDetails details) {
    setState(() {
      _isDragging = true;
      _dragResetTimer?.cancel();
    });
    _timeCapsuleAnimationController?.forward();
  }

  void _onDragUpdate(DragUpdateDetails details) {
    setState(() {
      _dragOffset += details.delta.dy;
      // 计算当前选中的歌词索引
      if (widget.lyrics.isNotEmpty) {
        final estimatedIndex = widget.currentLyricIndex - (_dragOffset / _lineHeight).round();
        _selectedLyricIndex = estimatedIndex.clamp(0, widget.lyrics.length - 1);
      }
    });
  }

  void _onDragEnd(DragEndDetails details) {
    _dragResetTimer = Timer(const Duration(milliseconds: 2000), () {
      if (mounted) {
        setState(() {
          _isDragging = false;
          _dragOffset = 0.0;
          _selectedLyricIndex = null;
        });
        _timeCapsuleAnimationController?.reverse();
      }
    });
  }

  void _seekToSelectedLyric() {
    if (_selectedLyricIndex != null &&
        _selectedLyricIndex! >= 0 &&
        _selectedLyricIndex! < widget.lyrics.length) {
      final selectedLyric = widget.lyrics[_selectedLyricIndex!];
      PlayerService().seek(selectedLyric.startTime);
    }
    // 立即退出拖拽模式
    _dragResetTimer?.cancel();
    setState(() {
      _isDragging = false;
      _dragOffset = 0.0;
      _selectedLyricIndex = null;
    });
    _timeCapsuleAnimationController?.reverse();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.lyrics.isEmpty) {
      return _buildNoLyric();
    }

    return GestureDetector(
      onTap: widget.onTap,
      child: Stack(
        children: [
          // 主歌词面板
          AnimatedBuilder(
            animation: LyricStyleService(),
            builder: (context, _) {
              return LayoutBuilder(
                builder: (context, constraints) {
                  final viewportHeight = constraints.maxHeight;
                  final viewportWidth = constraints.maxWidth;

                  // 根据对齐设置动态计算中心点偏移
                  final lyricStyle = LyricStyleService();
                  final centerY = lyricStyle.currentAlignment == LyricAlignment.center
                      ? viewportHeight * 0.5
                      : viewportHeight * 0.30;

                  // 可视区域计算
                  const visibleBuffer = 5;
                  final visibleLines = (viewportHeight / _lineHeight).ceil();
                  final minIndex = math.max(0, widget.currentLyricIndex - visibleBuffer - (visibleLines ~/ 2));
                  final maxIndex = math.min(widget.lyrics.length - 1, widget.currentLyricIndex + visibleBuffer + (visibleLines ~/ 2));

                  // 动态高度计算
                  final Map<int, double> heights = {};
                  final textMaxWidth = viewportWidth - 32; // horizontal padding 16 * 2

                  for (int i = minIndex; i <= maxIndex; i++) {
                    heights[i] = _measureLyricItemHeight(i, textMaxWidth);
                  }

                  // 计算偏移量（相对于 activeIndex 中心）
                  final Map<int, double> offsets = {};
                  offsets[widget.currentLyricIndex] = 0;

                  // 向下累加
                  double currentOffset = 0;
                  double prevHalfHeight = (heights[widget.currentLyricIndex] ?? _lineHeight) / 2;

                  for (int i = widget.currentLyricIndex + 1; i <= maxIndex; i++) {
                    final h = heights[i] ?? _lineHeight;
                    currentOffset += prevHalfHeight + (h / 2);
                    offsets[i] = currentOffset;
                    prevHalfHeight = h / 2;
                  }

                  // 向上累加
                  currentOffset = 0;
                  double nextHalfHeight = (heights[widget.currentLyricIndex] ?? _lineHeight) / 2;

                  for (int i = widget.currentLyricIndex - 1; i >= minIndex; i--) {
                    final h = heights[i] ?? _lineHeight;
                    currentOffset -= (nextHalfHeight + h / 2);
                    offsets[i] = currentOffset;
                    nextHalfHeight = h / 2;
                  }

                  List<Widget> children = [];
                  for (int i = minIndex; i <= maxIndex; i++) {
                    children.add(_buildLyricItem(i, centerY, offsets[i] ?? 0.0, heights[i] ?? _lineHeight));
                  }

                  return GestureDetector(
                    onVerticalDragStart: _onDragStart,
                    onVerticalDragUpdate: _onDragUpdate,
                    onVerticalDragEnd: _onDragEnd,
                    behavior: HitTestBehavior.translucent,
                    child: Stack(
                      fit: StackFit.expand,
                      children: children,
                    ),
                  );
                },
              );
            },
          ),
          // 时间胶囊组件
          if (_isDragging && _selectedLyricIndex != null)
            Positioned(
              right: 16,
              top: 0,
              bottom: 0,
              child: Center(child: _buildTimeCapsule()),
            ),
        ],
      ),
    );
  }

  /// 估算歌词项高度
  double _measureLyricItemHeight(int index, double maxWidth) {
    if (index < 0 || index >= widget.lyrics.length) return _lineHeight;
    final lyric = widget.lyrics[index];
    final fontFamily = LyricFontService().currentFontFamily ?? 'Microsoft YaHei';

    // 检查缓存
    final cacheKey = '${lyric.startTime.inMilliseconds}_${lyric.text.hashCode}_$maxWidth';
    if (_lastViewportWidth == maxWidth &&
        _lastFontFamily == fontFamily &&
        _lastShowTranslation == widget.showTranslation &&
        _heightCache.containsKey(cacheKey)) {
      return _heightCache[cacheKey]!;
    }

    const fontSize = 18.0; // 移动端字号

    // 测量原文高度
    final textPainter = TextPainter(
      text: TextSpan(
        text: lyric.text,
        style: TextStyle(
          fontFamily: fontFamily,
          fontSize: fontSize,
          fontWeight: FontWeight.w800,
          height: 1.2,
        ),
      ),
      textDirection: TextDirection.ltr,
    );
    textPainter.layout(maxWidth: maxWidth);
    double h = textPainter.height; // 使用更准确的 textPainter 高阶高度测量，不再依赖魔数因子

    // 测量翻译高度
    if (widget.showTranslation && lyric.translation != null && lyric.translation!.isNotEmpty) {
      final transPainter = TextPainter(
        text: TextSpan(
          text: lyric.translation,
          style: TextStyle(
            fontFamily: fontFamily,
            fontSize: 14,
            fontWeight: FontWeight.w600,
            height: 1.1,
          ),
        ),
        textDirection: TextDirection.ltr,
      );
      transPainter.layout(maxWidth: maxWidth);
      h += 4.0;
      h += transPainter.height * 1.1;
    }

    h += 8.0; // 基础 Padding

    final result = math.max(h, _lineHeight);

    // 更新缓存
    _lastViewportWidth = maxWidth;
    _lastFontFamily = fontFamily;
    _lastShowTranslation = widget.showTranslation;
    _heightCache[cacheKey] = result;

    return result;
  }

  Widget _buildLyricItem(int index, double centerYOffset, double relativeOffset, double itemHeight) {
    final activeIndex = widget.currentLyricIndex;
    final diff = index - activeIndex;

    // 1. 基础位移
    final double baseTranslation = relativeOffset;

    // 2. 正弦偏移（果冻弹性效果）- 移动端略微减弱
    final double sineOffset = math.sin(diff * 0.8) * 12.0;

    // 3. 最终Y坐标
    double targetY = centerYOffset + baseTranslation + sineOffset - (itemHeight / 2);

    // 叠加拖拽偏移
    if (_isDragging) {
      targetY += _dragOffset;
    }

    // 4. 缩放逻辑 - 移动端略微调整
    double targetScale;
    if (diff == 0) {
      targetScale = 1.10; // 移动端缩放略小
    } else if (diff.abs() < 3) {
      targetScale = 1.0 - diff.abs() * 0.08;
    } else {
      targetScale = 0.76;
    }

    // 5. 透明度逻辑
    double targetOpacity;
    if (diff.abs() > 4) {
      targetOpacity = 0.0;
    } else {
      targetOpacity = 1.0 - diff.abs() * 0.20;
    }
    targetOpacity = targetOpacity.clamp(0.0, 1.0);

    // 6. 延迟逻辑
    final int delayMs = (diff.abs() * 40).toInt();

    // 7. 模糊逻辑
    double targetBlur = 3.0;
    if (diff == 0) targetBlur = 0.0;
    else if (diff.abs() == 1) targetBlur = 0.8;

    final bool isActive = (diff == 0);

    return _MobileElasticLyricLine(
      key: ValueKey(index),
      text: widget.lyrics[index].text,
      translation: widget.lyrics[index].translation,
      lyric: widget.lyrics[index],
      lyrics: widget.lyrics,
      index: index,
      lineHeight: _lineHeight,
      targetY: targetY,
      targetScale: targetScale,
      targetOpacity: targetOpacity,
      targetBlur: targetBlur,
      isActive: isActive,
      delay: Duration(milliseconds: delayMs),
      isDragging: _isDragging,
      showTranslation: widget.showTranslation,
    );
  }

  Widget _buildNoLyric() {
    final fontFamily = LyricFontService().currentFontFamily ?? 'Microsoft YaHei';
    final message = widget.lyricState.displayText;
    return Center(
      child: Text(
        message,
        style: TextStyle(
          color: Colors.white.withOpacity(0.5),
          fontSize: 16,
          fontFamily: fontFamily,
        ),
      ),
    );
  }

  Widget _buildTimeCapsule() {
    if (_selectedLyricIndex == null ||
        _selectedLyricIndex! < 0 ||
        _selectedLyricIndex! >= widget.lyrics.length) {
      return const SizedBox.shrink();
    }

    final selectedLyric = widget.lyrics[_selectedLyricIndex!];
    final timeText = _formatDuration(selectedLyric.startTime);

    return FadeTransition(
      opacity: _timeCapsuleFadeAnimation!,
      child: GestureDetector(
        onTap: _seekToSelectedLyric,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.2),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: Colors.white.withOpacity(0.3),
              width: 0.5,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.play_arrow_rounded, color: Colors.white, size: 16),
              const SizedBox(width: 4),
              Text(
                timeText,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _formatDuration(Duration duration) {
    final minutes = duration.inMinutes;
    final seconds = duration.inSeconds % 60;
    return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }
}

/// 移动端弹性歌词行组件 - 移植桌面端动画系统
class _MobileElasticLyricLine extends StatefulWidget {
  final String text;
  final String? translation;
  final LyricLine lyric;
  final List<LyricLine> lyrics;
  final int index;
  final double lineHeight;

  final double targetY;
  final double targetScale;
  final double targetOpacity;
  final double targetBlur;
  final bool isActive;
  final Duration delay;
  final bool isDragging;
  final bool showTranslation;

  const _MobileElasticLyricLine({
    Key? key,
    required this.text,
    this.translation,
    required this.lyric,
    required this.lyrics,
    required this.index,
    required this.lineHeight,
    required this.targetY,
    required this.targetScale,
    required this.targetOpacity,
    required this.targetBlur,
    required this.isActive,
    required this.delay,
    required this.isDragging,
    required this.showTranslation,
  }) : super(key: key);

  @override
  State<_MobileElasticLyricLine> createState() => _MobileElasticLyricLineState();
}

class _MobileElasticLyricLineState extends State<_MobileElasticLyricLine> with TickerProviderStateMixin {
  late double _y;
  late double _scale;
  late double _opacity;
  late double _blur;

  AnimationController? _controller;
  Animation<double>? _yAnim;
  Animation<double>? _scaleAnim;
  Animation<double>? _opacityAnim;
  Animation<double>? _blurAnim;

  Timer? _delayTimer;

  // 弹性曲线 - 来自桌面端
  static const Curve elasticCurve = Cubic(0.34, 1.56, 0.64, 1.0);
  static const Duration animDuration = Duration(milliseconds: 700); // 移动端略快

  @override
  void initState() {
    super.initState();
    _y = widget.targetY;
    _scale = widget.targetScale;
    _opacity = widget.targetOpacity;
    _blur = widget.targetBlur;
  }

  @override
  void didUpdateWidget(_MobileElasticLyricLine oldWidget) {
    super.didUpdateWidget(oldWidget);

    const double epsilon = 0.05;

    bool positionChanged = (oldWidget.targetY - widget.targetY).abs() > epsilon;
    bool scaleChanged = (oldWidget.targetScale - widget.targetScale).abs() > 0.001;
    bool opacityChanged = (oldWidget.targetOpacity - widget.targetOpacity).abs() > 0.01;
    bool blurChanged = (oldWidget.targetBlur - widget.targetBlur).abs() > 0.1;

    if (positionChanged || scaleChanged || opacityChanged || blurChanged) {
      _startAnimation();
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    _delayTimer?.cancel();
    super.dispose();
  }

  void _startAnimation() {
    _delayTimer?.cancel();

    if (widget.isDragging) {
      _controller?.stop();
      setState(() {
        _y = widget.targetY;
        _scale = widget.targetScale;
        _opacity = widget.targetOpacity;
        _blur = widget.targetBlur;
      });
      return;
    }

    void play() {
      _controller?.dispose();
      _controller = AnimationController(
        vsync: this,
        duration: animDuration,
      );

      _yAnim = Tween<double>(begin: _y, end: widget.targetY).animate(
        CurvedAnimation(parent: _controller!, curve: elasticCurve),
      );
      _scaleAnim = Tween<double>(begin: _scale, end: widget.targetScale).animate(
        CurvedAnimation(parent: _controller!, curve: elasticCurve),
      );
      _opacityAnim = Tween<double>(begin: _opacity, end: widget.targetOpacity).animate(
        CurvedAnimation(parent: _controller!, curve: Curves.ease),
      );
      _blurAnim = Tween<double>(begin: _blur, end: widget.targetBlur).animate(
        CurvedAnimation(parent: _controller!, curve: Curves.ease),
      );

      _controller!.addListener(() {
        if (!mounted) return;
        setState(() {
          _y = _yAnim!.value;
          _scale = _scaleAnim!.value;
          _opacity = _opacityAnim!.value;
          _blur = _blurAnim!.value;
        });
      });

      _controller!.forward();
    }

    if (widget.delay == Duration.zero) {
      play();
    } else {
      _delayTimer = Timer(widget.delay, play);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_opacity < 0.01) return const SizedBox();

    return Positioned(
      top: _y,
      left: 0,
      right: 0,
      child: Transform.scale(
        scale: _scale,
        alignment: Alignment.center, // 移动端居中对齐
        child: Opacity(
          opacity: _opacity,
          child: _MobileOptionalBlur(
            blur: _blur,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              alignment: Alignment.center,
              child: _buildInnerContent(),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildInnerContent() {
    final fontFamily = LyricFontService().currentFontFamily ?? 'Microsoft YaHei';
    const double textFontSize = 18.0;

    Color textColor;
    if (widget.isActive) {
      textColor = Colors.white;
    } else {
      textColor = Colors.white.withOpacity(0.35);
    }

    // 构建文本 Widget
    Widget textWidget;
    if (widget.isActive && widget.lyric.hasWordByWord) {
      textWidget = _MobileKaraokeText(
        text: widget.text,
        lyric: widget.lyric,
        lyrics: widget.lyrics,
        index: widget.index,
        originalTextStyle: TextStyle(
          fontFamily: fontFamily,
          fontSize: textFontSize,
          fontWeight: FontWeight.w800,
          color: Colors.white,
          height: 1.25, // 增加行高防止裁断
        ),
      );
    } else if (widget.isActive) {
      // 无逐字数据时，使用整行渐变动画
      textWidget = _MobileLineGradientText(
        text: widget.text,
        lyric: widget.lyric,
        lyrics: widget.lyrics,
        index: widget.index,
        textStyle: TextStyle(
          fontFamily: fontFamily,
          fontSize: textFontSize,
          fontWeight: FontWeight.w800,
          color: Colors.white,
          height: 1.25,
        ),
      );
    } else {
      textWidget = Text(
        widget.text,
        textAlign: TextAlign.center,
        style: TextStyle(
          fontFamily: fontFamily,
          fontSize: textFontSize,
          fontWeight: FontWeight.w800,
          color: textColor,
          height: 1.25,
        ),
      );
    }

    // 翻译
    if (widget.showTranslation && widget.translation != null && widget.translation!.isNotEmpty) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          textWidget,
          Padding(
            padding: const EdgeInsets.only(top: 6.0),
            child: Text(
              widget.translation!,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontFamily: fontFamily,
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: Colors.white.withOpacity(0.35),
                height: 1.2,
              ),
            ),
          )
        ],
      );
    }

    return textWidget;
  }
}

/// 模糊优化组件
class _MobileOptionalBlur extends StatelessWidget {
  final double blur;
  final Widget child;

  const _MobileOptionalBlur({required this.blur, required this.child});

  @override
  Widget build(BuildContext context) {
    if (blur < 0.5) return child;
    return ImageFiltered(
      imageFilter: ImageFilter.blur(sigmaX: blur, sigmaY: blur),
      child: child,
    );
  }
}

/// 整行渐变文本组件 - 无逐字数据时使用
class _MobileLineGradientText extends StatefulWidget {
  final String text;
  final LyricLine lyric;
  final List<LyricLine> lyrics;
  final int index;
  final TextStyle textStyle;

  const _MobileLineGradientText({
    required this.text,
    required this.lyric,
    required this.lyrics,
    required this.index,
    required this.textStyle,
  });

  @override
  State<_MobileLineGradientText> createState() => _MobileLineGradientTextState();
}

class _MobileLineGradientTextState extends State<_MobileLineGradientText> with SingleTickerProviderStateMixin {
  late Ticker _ticker;
  double _lineProgress = 0.0;
  late Duration _duration;

  @override
  void initState() {
    super.initState();
    _calculateDuration();
    _ticker = createTicker(_onTick);
    _ticker.start();
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  void _calculateDuration() {
    if (widget.index < widget.lyrics.length - 1) {
      _duration = widget.lyrics[widget.index + 1].startTime - widget.lyric.startTime;
    } else {
      _duration = const Duration(seconds: 5);
    }
    if (_duration.inMilliseconds == 0) _duration = const Duration(seconds: 3);
  }

  void _onTick(Duration elapsed) {
    if (!mounted) return;
    final currentPos = PlayerService().position;
    final elapsedFromStart = currentPos - widget.lyric.startTime;
    final newProgress = (elapsedFromStart.inMilliseconds / _duration.inMilliseconds).clamp(0.0, 1.0);

    if ((newProgress - _lineProgress).abs() > 0.005) {
      setState(() {
        _lineProgress = newProgress;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: ShaderMask(
        shaderCallback: (bounds) {
          return LinearGradient(
            begin: Alignment.centerLeft,
            end: Alignment.centerRight,
            colors: const [Colors.white, Color(0x99FFFFFF)],
            stops: [_lineProgress, _lineProgress],
            tileMode: TileMode.clamp,
          ).createShader(bounds);
        },
        blendMode: BlendMode.srcIn,
        child: Text(
          widget.text,
          textAlign: TextAlign.center,
          style: widget.textStyle,
        ),
      ),
    );
  }
}

/// 移动端卡拉OK文本组件 - 升级版（移植桌面端）
class _MobileKaraokeText extends StatefulWidget {
  final String text;
  final LyricLine lyric;
  final List<LyricLine> lyrics;
  final int index;
  final TextStyle originalTextStyle;

  const _MobileKaraokeText({
    required this.text,
    required this.lyric,
    required this.lyrics,
    required this.index,
    required this.originalTextStyle,
  });

  @override
  State<_MobileKaraokeText> createState() => _MobileKaraokeTextState();
}

class _MobileKaraokeTextState extends State<_MobileKaraokeText> with SingleTickerProviderStateMixin {
  late Ticker _ticker;

  // 共享进度通知器
  final ValueNotifier<Duration> _positionNotifier = ValueNotifier(Duration.zero);

  late Duration _duration;

  @override
  void initState() {
    super.initState();
    _calculateDuration();
    _ticker = createTicker(_onTick);
    _ticker.start();
  }

  @override
  void dispose() {
    _ticker.dispose();
    _positionNotifier.dispose();
    super.dispose();
  }

  void _calculateDuration() {
    if (widget.index < widget.lyrics.length - 1) {
      _duration = widget.lyrics[widget.index + 1].startTime - widget.lyric.startTime;
    } else {
      _duration = const Duration(seconds: 5);
    }
    if (_duration.inMilliseconds == 0) _duration = const Duration(seconds: 3);
  }

  void _onTick(Duration elapsed) {
    if (!mounted) return;
    final currentPos = PlayerService().position;
    _positionNotifier.value = currentPos;
  }

  @override
  Widget build(BuildContext context) {
    final style = widget.originalTextStyle;

    if (widget.lyric.hasWordByWord && widget.lyric.words != null && widget.lyric.words!.isNotEmpty) {
      return _buildWordByWordEffect(style);
    }

    return const SizedBox(); // 不应到达这里
  }

  Widget _buildWordByWordEffect(TextStyle style) {
    final words = widget.lyric.words!;
    return Wrap(
      alignment: WrapAlignment.center,
      crossAxisAlignment: WrapCrossAlignment.center,
      runSpacing: 2.0,
      children: List.generate(words.length, (index) {
        final word = words[index];
        return _MobileWordFillWidget(
          key: ValueKey('${widget.index}_$index'),
          text: word.text,
          word: word,
          style: style,
          positionNotifier: _positionNotifier,
        );
      }),
    );
  }
}

/// 移动端单字填充组件 - 升级版（移植桌面端特性）
class _MobileWordFillWidget extends StatefulWidget {
  final String text;
  final LyricWord word;
  final TextStyle style;
  final ValueNotifier<Duration> positionNotifier;

  const _MobileWordFillWidget({
    Key? key,
    required this.text,
    required this.word,
    required this.style,
    required this.positionNotifier,
  }) : super(key: key);

  @override
  State<_MobileWordFillWidget> createState() => _MobileWordFillWidgetState();
}

class _MobileWordFillWidgetState extends State<_MobileWordFillWidget> with TickerProviderStateMixin {
  late AnimationController _floatController;
  late Animation<double> _floatOffset;
  double _progress = 0.0;
  bool? _isAsciiCached;

  static const double fadeRatio = 0.3;
  static const double maxFloatOffset = -2.5; // 移动端上浮略小

  @override
  void initState() {
    super.initState();

    _floatController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 450),
    );
    _floatOffset = Tween<double>(begin: 0.0, end: maxFloatOffset).animate(
      CurvedAnimation(parent: _floatController, curve: Curves.easeOutBack),
    );

    _updateProgress(widget.positionNotifier.value);
    widget.positionNotifier.addListener(_onPositionUpdate);

    const double threshold = 0.5;
    if (_progress >= threshold) {
      _floatController.value = 1.0;
    }
  }

  void _onPositionUpdate() {
    if (!mounted) return;
    final oldProgress = _progress;
    _updateProgress(widget.positionNotifier.value);

    const double threshold = 0.5;

    if (_progress >= threshold && oldProgress < threshold) {
      _floatController.forward();
    } else if (_progress < threshold && oldProgress >= threshold) {
      _floatController.reverse();
    }

    final isAscii = _isAsciiText();
    final thresholdVal = isAscii ? 0.001 : 0.005;

    if ((oldProgress - _progress).abs() > thresholdVal ||
        (_progress >= 1.0 && oldProgress < 1.0) ||
        (_progress <= 0.0 && oldProgress > 0.0)) {
      setState(() {});
    }
  }

  @override
  void didUpdateWidget(_MobileWordFillWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.positionNotifier != widget.positionNotifier) {
      oldWidget.positionNotifier.removeListener(_onPositionUpdate);
      widget.positionNotifier.addListener(_onPositionUpdate);
    }
    _updateProgress(widget.positionNotifier.value);

    const double threshold = 0.5;
    if (_progress >= threshold) {
      if (!_floatController.isAnimating && _floatController.value < 1.0) {
        _floatController.forward();
      }
    } else {
      if (!_floatController.isAnimating && _floatController.value > 0.0) {
        _floatController.reverse();
      }
    }
  }

  void _updateProgress(Duration currentPos) {
    if (currentPos < widget.word.startTime) {
      _progress = 0.0;
    } else if (currentPos >= widget.word.endTime) {
      _progress = 1.0;
    } else {
      final wordDuration = widget.word.duration.inMilliseconds;
      if (wordDuration <= 0) {
        _progress = 1.0;
      } else {
        final wordElapsed = currentPos - widget.word.startTime;
        _progress = (wordElapsed.inMilliseconds / wordDuration).clamp(0.0, 1.0);
      }
    }
  }

  @override
  void dispose() {
    widget.positionNotifier.removeListener(_onPositionUpdate);
    _floatController.dispose();
    super.dispose();
  }

  bool _isAsciiText() {
    if (_isAsciiCached != null) return _isAsciiCached!;
    if (widget.text.isEmpty) {
      _isAsciiCached = false;
      return false;
    }
    int asciiCount = 0;
    for (final char in widget.text.runes) {
      if ((char >= 65 && char <= 90) || (char >= 97 && char <= 122)) asciiCount++;
    }
    _isAsciiCached = asciiCount > widget.text.length / 2;
    return _isAsciiCached!;
  }

  @override
  Widget build(BuildContext context) {
    final useLetterAnimation = _isAsciiText() && widget.text.length > 1;

    return RepaintBoundary(
      child: AnimatedBuilder(
        animation: _floatOffset,
        builder: (context, child) {
          final double effectiveY = useLetterAnimation ? 0.0 : _floatOffset.value;
          return Transform.translate(
            offset: Offset(0, effectiveY),
            child: child,
          );
        },
        child: _buildInner(),
      ),
    );
  }

  Widget _buildInner() {
    if (_isAsciiText() && widget.text.length > 1) return _buildLetterByLetterEffect();
    return _buildWholeWordEffect();
  }

  Widget _buildWholeWordEffect() {
    List<Color> gradientColors;
    List<double> gradientStops;

    if (_progress <= 0.0) {
      gradientColors = const [Color(0x99FFFFFF), Color(0x99FFFFFF)];
      gradientStops = const [0.0, 1.0];
    } else if (_progress >= 1.0) {
      gradientColors = const [Colors.white, Colors.white];
      gradientStops = const [0.0, 1.0];
    } else {
      const double glowWidth = 0.05;
      gradientColors = [
        Colors.white.withOpacity(0.9),
        Colors.white,
        Colors.white,
        const Color(0x99FFFFFF),
        const Color(0x99FFFFFF),
      ];
      gradientStops = [
        0.0,
        (_progress - glowWidth).clamp(0.0, 1.0),
        _progress,
        (_progress + fadeRatio).clamp(0.0, 1.0),
        1.0,
      ];
    }

    return ShaderMask(
      shaderCallback: (bounds) => LinearGradient(
        colors: gradientColors,
        stops: gradientStops,
      ).createShader(bounds),
      blendMode: BlendMode.srcIn,
      child: Text(widget.text, style: widget.style.copyWith(color: Colors.white)),
    );
  }

  Widget _buildLetterByLetterEffect() {
    final letters = widget.text.split('');
    final letterCount = letters.length;

    const double rippleWidth = 1.2;
    const double maxLetterFloat = 0.0; // 临时禁用上浮动画以测试间距

    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: List.generate(letterCount, (index) {
        final letter = letters[index];
        final baseWidth = 1.0 / letterCount;

        // 填充进度
        final fillStart = index * baseWidth;
        final fillEnd = (index + 1) * baseWidth;
        final fillProgress = ((_progress - fillStart) / (fillEnd - fillStart)).clamp(0.0, 1.0);

        // 上浮偏移
        double currentLetterOffset = 0.0;

        if (_progress <= 0.0) {
          currentLetterOffset = 0.0;
        } else if (_progress >= fillEnd) {
          currentLetterOffset = maxLetterFloat;
        } else {
          final startTrigger = (fillStart - (baseWidth * rippleWidth)).clamp(0.001, 1.0);
          if (_progress > startTrigger) {
            final t = ((_progress - startTrigger) / (fillEnd - startTrigger)).clamp(0.0, 1.0);
            currentLetterOffset = Curves.easeOut.transform(t) * maxLetterFloat;
          }
        }

        // ShaderMask
        List<Color> lColors;
        List<double> lStops;

        if (fillProgress <= 0.0) {
          lColors = const [Color(0x99FFFFFF), Color(0x99FFFFFF)];
          lStops = const [0.0, 1.0];
        } else if (fillProgress >= 1.0) {
          lColors = const [Colors.white, Colors.white];
          lStops = const [0.0, 1.0];
        } else {
          const double glowW = 0.15;
          lColors = [
            Colors.white.withOpacity(0.9),
            Colors.white,
            Colors.white,
            const Color(0x99FFFFFF),
            const Color(0x99FFFFFF),
          ];
          lStops = [
            0.0,
            (fillProgress - glowW).clamp(0.0, 1.0),
            fillProgress,
            (fillProgress + fadeRatio).clamp(0.0, 1.0),
            1.0,
          ];
        }

        return Transform.translate(
          offset: Offset(0, currentLetterOffset),
          child: ShaderMask(
            shaderCallback: (bounds) => LinearGradient(
              colors: lColors,
              stops: lStops,
            ).createShader(bounds),
            blendMode: BlendMode.srcIn,
            child: Padding(
              padding: EdgeInsets.zero,
              child: Text(letter, style: widget.style.copyWith(color: Colors.white)),
            ),
          ),
        );
      }),
    );
  }
}
