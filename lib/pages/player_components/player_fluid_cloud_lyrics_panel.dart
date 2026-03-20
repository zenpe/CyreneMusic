import 'dart:async';
import 'dart:math';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import '../../services/player_service.dart';
import '../../services/lyric_font_service.dart';
import '../../services/lyric_style_service.dart';
import '../../models/lyric_line.dart';

/// 核心：弹性间距动画 + 波浪式延迟 (1:1 复刻 HTML)
enum _VirtualEntryType { lyric, dots }

class _VirtualLyricEntry {
  final _VirtualEntryType type;
  final int? lyricIndex; 
  final Duration startTime;
  final Duration? endTime; // New: for dots duration
  final String key;

  _VirtualLyricEntry({
    required this.type,
    this.lyricIndex,
    required this.startTime,
    this.endTime,
    required this.key,
  });
}

// --- 动画常量 (与 Mobile 保持一致) ---
const Curve kSineElastic = Cubic(0.44, 0.05, 0.55, 0.95);
const Duration kScrollDuration = Duration(milliseconds: 800);
const Duration kShrinkDelay = Duration(milliseconds: 400);
const Duration kShrinkDuration = Duration(milliseconds: 500);

class PlayerFluidCloudLyricsPanel extends StatefulWidget {
  final List<LyricLine> lyrics;
  final int currentLyricIndex;
  final bool showTranslation;
  final LyricLoadState lyricState;
  final int visibleLineCount;

  const PlayerFluidCloudLyricsPanel({
    super.key,
    required this.lyrics,
    required this.currentLyricIndex,
    required this.showTranslation,
    required this.lyricState,
    this.visibleLineCount = 7,
  });

  @override
  State<PlayerFluidCloudLyricsPanel> createState() => _PlayerFluidCloudLyricsPanelState();
}

class _PlayerFluidCloudLyricsPanelState extends State<PlayerFluidCloudLyricsPanel> {
  
  // 核心变量 (从 Service 获取)
  double get _lineHeight => LyricStyleService().lineHeight;

  static const double _maxActiveScale = 1.0; // 1.1 -> 1.0
  // HTML 中是 80px，这里我们也用 80 逻辑像素
  
  // 滚动/拖拽相关
  double _dragOffset = 0.0;
  bool _isDragging = false;
  Timer? _dragResetTimer;

  // [New] 布局缓存
  final Map<String, double> _heightCache = {};
  double? _lastViewportWidth;
  String? _lastFontFamily;
  bool? _lastShowTranslation;

  @override
  void dispose() {
    _dragResetTimer?.cancel();
    super.dispose();
  }

  // 简单的拖拽手势处理，允许用户微调查看
  void _onDragStart(DragStartDetails details) {
    setState(() {
      _isDragging = true;
      _dragResetTimer?.cancel();
    });
  }

  void _onDragUpdate(DragUpdateDetails details) {
    setState(() {
      _dragOffset += details.delta.dy;
    });
  }

  void _onDragEnd(DragEndDetails details) {
     // 拖拽结束后，延时回弹归位
     _dragResetTimer = Timer(const Duration(milliseconds: 600), () {
       if (mounted) {
         setState(() {
           _isDragging = false;
           _dragOffset = 0.0; 
         });
       }
     });
  }

  @override
  Widget build(BuildContext context) {
    if (widget.lyrics.isEmpty) {
      return _buildNoLyric();
    }

    return AnimatedBuilder(
      animation: LyricStyleService(),
      builder: (context, _) {
        final lyricStyle = LyricStyleService();
        return LayoutBuilder(
          builder: (context, constraints) {
            final viewportHeight = constraints.maxHeight;
            final viewportWidth = constraints.maxWidth;
            final currentPos = PlayerService().position;

            // 1. 构建虚拟项列表 (动态触发)
            final List<_VirtualLyricEntry> virtualEntries = [];
            
            // 检查前奏 dots：只有在距离第一句歌词开始 <= 5s 时才真正“加载”进入队列
            if (widget.lyrics.isNotEmpty) {
              final firstTime = widget.lyrics[0].startTime;
              // 如果距离首句还早（>2s），则加载 dots 项。
              // 无论当前处于前奏的哪个阶段，只要前奏足够长，都显示 Dots。
              if (firstTime > const Duration(seconds: 2)) {
                virtualEntries.add(_VirtualLyricEntry(
                  type: _VirtualEntryType.dots,
                  startTime: Duration.zero,
                  endTime: firstTime,
                  key: 'dots-intro',
                ));
              }
            }

            for (int i = 0; i < widget.lyrics.length; i++) {
              virtualEntries.add(_VirtualLyricEntry(
                type: _VirtualEntryType.lyric,
                lyricIndex: i,
                startTime: widget.lyrics[i].startTime,
                key: 'lyric-$i-${widget.lyrics[i].startTime.inMilliseconds}',
              ));

              // 检查间奏 dots：同样是动态触发
              if (i < widget.lyrics.length - 1) {
                final currentLine = widget.lyrics[i];
                final nextLine = widget.lyrics[i+1];
                
                // 计算当前行结束时间
                Duration lineEndTime = currentLine.startTime + const Duration(seconds: 3); // 默认兜底 3s
                if (currentLine.words != null && currentLine.words!.isNotEmpty) {
                  lineEndTime = currentLine.words!.last.startTime + currentLine.words!.last.duration;
                } else if (currentLine.lineDuration != null) {
                   lineEndTime = currentLine.startTime + currentLine.lineDuration!;
                }

                  // 实际间奏时长
                  final actualGap = nextLine.startTime - lineEndTime;
                  final actualGapSeconds = actualGap.inSeconds;

                  // 只有当播放进度已经到达或超过当前句子的“结束点”，且间奏够长(>2s)，才插入 dots 项
                  if (actualGapSeconds >= 2 && currentPos >= lineEndTime) {
                    // 用户需求：如果间奏大于10秒，要从第二秒开始就渲染dot (即延迟 1s 开始)
                    final dotsStartTime = actualGapSeconds > 10 
                        ? lineEndTime + const Duration(seconds: 1)
                        : lineEndTime;

                    virtualEntries.add(_VirtualLyricEntry(
                      type: _VirtualEntryType.dots,
                      startTime: dotsStartTime,
                      endTime: nextLine.startTime,
                      key: 'dots-${i}-${nextLine.startTime.inMilliseconds}',
                    ));
                  }
              }
            }

            // 2. 找到当前活跃虚拟项索引
            int activeVirtualIndex = 0;
            for (int i = virtualEntries.length - 1; i >= 0; i--) {
              if (currentPos >= virtualEntries[i].startTime) {
                activeVirtualIndex = i;
                break;
              }
            }

            // 根据对齐设置动态计算中心点偏移
            final centerY = lyricStyle.currentAlignment == LyricAlignment.center 
                ? viewportHeight * 0.5 
                : viewportHeight * 0.25;
            
            // 可视区域计算
            final visibleBuffer = 8; 
            final minIdx = max(0, activeVirtualIndex - visibleBuffer);
            final maxIdx = min(virtualEntries.length - 1, activeVirtualIndex + visibleBuffer + 4);

            final layoutWidth = viewportWidth / _maxActiveScale;
            final textMaxWidth = layoutWidth - 80;

            // 3. 计算高度和偏移
            final Map<int, double> heights = {};
            for (int i = minIdx; i <= maxIdx; i++) {
              heights[i] = _measureVirtualEntryHeight(virtualEntries[i], textMaxWidth);
            }

            final Map<int, double> offsets = {};
            offsets[activeVirtualIndex] = 0;

            double currentOffset = 0;
            double prevHalfHeight = (heights[activeVirtualIndex]! * (virtualEntries[activeVirtualIndex].type == _VirtualEntryType.dots ? 1.0 : 1.15)) / 2;
            
            for (int i = activeVirtualIndex + 1; i <= maxIdx; i++) {
              final h = heights[i]!;
              final s = _getScaleSync(i - activeVirtualIndex);
              final scaledHalfHeight = (h * s) / 2;
              currentOffset += prevHalfHeight + scaledHalfHeight; 
              offsets[i] = currentOffset;
              prevHalfHeight = scaledHalfHeight;
            }

            currentOffset = 0;
            double nextHalfHeight = (heights[activeVirtualIndex]! * (virtualEntries[activeVirtualIndex].type == _VirtualEntryType.dots ? 1.0 : 1.15)) / 2;
            
            for (int i = activeVirtualIndex - 1; i >= minIdx; i--) {
              final h = heights[i]!;
              final s = _getScaleSync(i - activeVirtualIndex);
              final scaledHalfHeight = (h * s) / 2;
              currentOffset -= (nextHalfHeight + scaledHalfHeight);
              offsets[i] = currentOffset;
              nextHalfHeight = scaledHalfHeight;
            }

            List<Widget> children = [];
            for (int i = minIdx; i <= maxIdx; i++) {
               children.add(_buildVirtualItem(
                 virtualEntries[i], 
                 i, 
                 activeVirtualIndex, 
                 centerY, 
                 offsets[i] ?? 0.0, 
                 heights[i]!, 
                 layoutWidth
               ));
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
    );
  }

  double _measureVirtualEntryHeight(_VirtualLyricEntry entry, double maxWidth) {
    if (entry.type == _VirtualEntryType.dots) return 40.0;
    return _measureLyricItemHeight(entry.lyricIndex!, maxWidth);
  }

  /// 估算歌词项高度
  double _measureLyricItemHeight(int index, double maxWidth) {
    if (index < 0 || index >= widget.lyrics.length) return _lineHeight;
    final lyric = widget.lyrics[index];
    final fontFamily = LyricFontService().currentFontFamily ?? 'Microsoft YaHei';
    
    // [Optimization] 检查缓存
    final cacheKey = '${lyric.startTime.inMilliseconds}_${lyric.text.hashCode}_$maxWidth';
    if (_lastViewportWidth == maxWidth && 
        _lastFontFamily == fontFamily && 
        _lastShowTranslation == widget.showTranslation &&
        _heightCache.containsKey(cacheKey)) {
      return _heightCache[cacheKey]!;
    }

    final fontSize = LyricStyleService().fontSize; 

    // 测量原文高度 (maxLines: 2)
    final textPainter = TextPainter(
      text: TextSpan(
        text: lyric.text,
        style: TextStyle(
          fontFamily: fontFamily,
          fontSize: fontSize,
          fontWeight: FontWeight.w800,
          height: 1.15,
        ),
      ),
      textDirection: TextDirection.ltr,
      // 移除 maxLines 限制，实现自适应宽度换行后的真实高度测量
    );
    textPainter.layout(maxWidth: maxWidth);
    
    // 计算行数以补偿 _WordFillWidget 内部的 Padding (上下共 12.0)
    int numLines = (textPainter.height / (fontSize * 1.15)).round();
    if (numLines <= 0) numLines = 1;
    double h = textPainter.height + (numLines * 12.0); 

    // 测量翻译高度
    if (widget.showTranslation && lyric.translation != null && lyric.translation!.isNotEmpty) {
      final transPainter = TextPainter(
        text: TextSpan(
          text: lyric.translation,
          style: TextStyle(
            fontFamily: fontFamily,
            fontSize: 18, // 与 _buildInnerContent 保持一致
            fontWeight: FontWeight.w600,
            height: 1.4, // 保持与渲染一致的 height
          ),
        ),
        textDirection: TextDirection.ltr,
      );
      transPainter.layout(maxWidth: maxWidth);
      h += 4.0; // 降低原文与译文之间的间距 (原 8.0)
      h += transPainter.height; // 使用真实高度
    }
    
    // 保证最小高度，避免空行太窄
    final result = max(h, _lineHeight);
    
    // 更新缓存状态
    _lastViewportWidth = maxWidth;
    _lastFontFamily = fontFamily;
    _lastShowTranslation = widget.showTranslation;
    _heightCache[cacheKey] = result;
    
    return result;
  }

  /// 内部辅助方法：计算同步缩放值（用于偏移量预计算）
  double _getScaleSync(int diff) {
    return 1.0;
  }

  Widget _buildVirtualItem(_VirtualLyricEntry item, int index, int activeIndex, double centerYOffset, double relativeOffset, double itemHeight, double layoutWidth) {
    final diff = index - activeIndex;

    // 1. 缩放逻辑
    double targetScale = _getScaleSync(diff);
    if (item.type == _VirtualEntryType.dots) targetScale = 1.0;

    // 2. 最终Y坐标
    double baseTranslation = relativeOffset;
    double sineOffset = sin(diff * 0.8) * 20.0;
    
    // 【核心亮点】占位点原地消失逻辑
    // 如果是占位点，并且已经过期 (diff < 0)
    if (item.type == _VirtualEntryType.dots && diff < 0) {
       // 固定在中心位置附近停留消失，不跟随向上滚动
       baseTranslation = 0; 
       sineOffset = 0;
    }

    double targetY = centerYOffset + baseTranslation + sineOffset - (itemHeight * targetScale / 2);
    if (_isDragging) targetY += _dragOffset;
    
    // 3. 透明度逻辑
    double targetOpacity;
    if (diff.abs() > 4) {
      targetOpacity = 0.0;
    } else {
      targetOpacity = 1.0 - diff.abs() * 0.2;
    }

    // 过期占位符强制 0 透明度 (因为它们不再占用空间)
    if (item.type == _VirtualEntryType.dots && diff < 0) targetOpacity = 0.0;
    


    targetOpacity = targetOpacity.clamp(0.0, 1.0).toDouble();

    final int delayMs = (diff.abs() * 50).toInt();

    final blurSigma = LyricStyleService().blurSigma;
    double targetBlur = blurSigma;
    if (diff == 0) targetBlur = 0.0;
    else if (diff.abs() == 1) targetBlur = blurSigma * 0.25;
    if (item.type == _VirtualEntryType.dots && diff < 0) targetBlur = blurSigma;

    final bool isActive = (diff == 0);

    return _ElasticLyricLine(
      key: ValueKey(item.key),
      text: item.type == _VirtualEntryType.lyric ? widget.lyrics[item.lyricIndex!].text : '',
      translation: item.type == _VirtualEntryType.lyric ? widget.lyrics[item.lyricIndex!].translation : null,
      lyric: item.type == _VirtualEntryType.lyric ? widget.lyrics[item.lyricIndex!] : LyricLine(startTime: item.startTime, text: ''),
      lyrics: widget.lyrics,     
      index: index,             
      lineHeight: _lineHeight,
      viewportWidth: layoutWidth,
      targetY: targetY,
      targetScale: targetScale,
      targetOpacity: targetOpacity,
      targetBlur: targetBlur,
      isActive: isActive,
      delay: Duration(milliseconds: delayMs),
      isDragging: _isDragging,
      showTranslation: widget.showTranslation,
      isDots: item.type == _VirtualEntryType.dots,
      dotsStartTime: item.type == _VirtualEntryType.dots ? item.startTime : null,
      dotsEndTime: item.type == _VirtualEntryType.dots ? item.endTime : null,
    );
  }

  Widget _buildNoLyric() {
    final message = widget.lyricState.displayText;
    return Center(
      child: Text(
        message,
        style: const TextStyle(color: Colors.white54, fontSize: 24),
      ),
    );
  }
}

/// 能够处理延迟和弹性动画的单行歌词组件
/// 对应 HTML .lyric-line 及其 CSS transition
class _ElasticLyricLine extends StatefulWidget {
  final String text;
  final String? translation;
  final LyricLine lyric;
  final List<LyricLine> lyrics;
  final int index;
  final double lineHeight;
  final double viewportWidth;
  
  final double targetY;
  final double targetScale;
  final double targetOpacity;
  final double targetBlur;
  final bool isActive;
  final Duration delay;
  final bool isDragging;
  final bool showTranslation;

  final bool isDots;
  final Duration? dotsStartTime;
  final Duration? dotsEndTime;

  const _ElasticLyricLine({
    Key? key,
    required this.text,
    this.translation,
    required this.lyric,
    required this.lyrics,
    required this.index,
    required this.lineHeight,
    required this.viewportWidth,
    required this.targetY,
    required this.targetScale,
    required this.targetOpacity,
    required this.targetBlur,
    required this.isActive,
    required this.delay,
    required this.isDragging,
    required this.showTranslation,
    this.isDots = false,
    this.dotsStartTime,
    this.dotsEndTime,
  }) : super(key: key);

  @override
  State<_ElasticLyricLine> createState() => _ElasticLyricLineState();
}

class _ElasticLyricLineState extends State<_ElasticLyricLine> with TickerProviderStateMixin {
  // 当前动画值
  late double _y;
  late double _scale;
  late double _opacity;
  late double _blur;
  late Color _textColor;
  
  AnimationController? _controller;
  Animation<double>? _yAnim;
  Animation<double>? _scaleAnim;
  Animation<double>? _opacityAnim;
  Animation<double>? _blurAnim;
  Animation<Color?>? _colorAnim;
  
  Timer? _delayTimer;

  // --- 涟漪效果相关 ---
  final List<_RippleInfo> _ripples = [];
  
  void _addRipple(Offset localPosition) {
    // 占位点不需要涟漪效果
    if (widget.isDots) return;
    
    final ripple = _RippleInfo(
      position: localPosition,
      controller: AnimationController(
        vsync: this,
        duration: const Duration(milliseconds: 800),
      ),
    );
    
    setState(() {
      _ripples.add(ripple);
    });

    ripple.controller.forward().then((_) {
      if (mounted) {
        setState(() {
          _ripples.remove(ripple);
        });
      }
      ripple.controller.dispose();
    });
  }

  static const Duration animDuration = Duration(milliseconds: 800);
  

  @override
  void initState() {
    super.initState();
    _y = widget.targetY;
    _scale = widget.targetScale;
    _opacity = widget.targetOpacity;
    _blur = widget.targetBlur;
    _textColor = widget.isActive ? Colors.white : Colors.white.withOpacity(0.3);
  }

  @override
  void didUpdateWidget(_ElasticLyricLine oldWidget) {
    super.didUpdateWidget(oldWidget);
    
    // 使用 Epsilon 阈值防止微小浮点误差/UI抖动导致的动画频繁重启
    const double epsilon = 0.05;
    
    // 只在变化显著时才触发动画
    bool positionChanged = (oldWidget.targetY - widget.targetY).abs() > epsilon;
    bool scaleChanged = (oldWidget.targetScale - widget.targetScale).abs() > 0.001;
    bool opacityChanged = (oldWidget.targetOpacity - widget.targetOpacity).abs() > 0.01;
    bool blurChanged = (oldWidget.targetBlur - widget.targetBlur).abs() > 0.1;
    
    if (positionChanged || scaleChanged || opacityChanged || blurChanged) {
      _startAnimation(oldWidget);
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    _delayTimer?.cancel();
    // 清理所有涟漪动画控制器
    for (final ripple in _ripples) {
      ripple.controller.dispose();
    }
    super.dispose();
  }

  void _startAnimation(covariant _ElasticLyricLine oldWidget) {
    _delayTimer?.cancel();
    
    // 如果正在拖拽，或者目标一致，则不播放动画
    if (widget.isDragging) {
      _controller?.stop();
      setState(() {
        _y = widget.targetY;
        _scale = widget.targetScale;
        _opacity = widget.targetOpacity;
        _blur = widget.targetBlur;
        _textColor = widget.isActive ? Colors.white : Colors.white.withOpacity(0.3);
      });
      return;
    }

    void play() {
      // 创建新的控制器
      _controller?.dispose();
      _controller = AnimationController(
        vsync: this,
        duration: animDuration, // Fixed 800ms
      );

      _controller!.addListener(() {
        if (!mounted) return;
        setState(() {
          _y = _yAnim!.value;
          _scale = _scaleAnim!.value;
          _opacity = _opacityAnim!.value;
          _blur = _blurAnim!.value;
          if (_colorAnim != null) _textColor = _colorAnim!.value ?? _textColor;
        });
      });

      final targetColor = widget.isActive ? Colors.white : Colors.white.withOpacity(0.3);

      // 同步动画
      _yAnim = Tween<double>(begin: _y, end: widget.targetY).animate(
        CurvedAnimation(parent: _controller!, curve: kSineElastic)
      );
      
      _scaleAnim = Tween<double>(begin: _scale, end: widget.targetScale).animate(
         CurvedAnimation(parent: _controller!, curve: kSineElastic)
      );
      
      _opacityAnim = Tween<double>(begin: _opacity, end: widget.targetOpacity).animate(
        CurvedAnimation(parent: _controller!, curve: Curves.linear)
      );
      
      _blurAnim = Tween<double>(begin: _blur, end: widget.targetBlur).animate(
        CurvedAnimation(parent: _controller!, curve: Curves.linear)
      );

      _colorAnim = ColorTween(begin: _textColor, end: targetColor).animate(
        CurvedAnimation(parent: _controller!, curve: Curves.linear)
      );

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
    // 性能优化：如果透明度极低，不渲染
    if (_opacity < 0.01) return const SizedBox();

    return Positioned(
      top: _y,
      left: 0,
      width: widget.viewportWidth, // [Refactor] 显式设置宽度为缩减后的 layoutWidth
      child: RepaintBoundary(
        child: GestureDetector(
          // 使用 opaque 拦截点击事件，防止冒泡到外部 Layout 触发控制栏显隐
          behavior: HitTestBehavior.opaque,
          onTapDown: (details) {
            _addRipple(details.localPosition);
          },
          onTap: () {
            // 占位点不需要跳转
            if (widget.isDots) return;
            // 跳转到歌词开始时间
            PlayerService().seek(widget.lyric.startTime);
          },
          child: Transform.scale(
            scale: _scale,
            alignment: Alignment.centerLeft, // HTML: transform-origin: left center
            child: Opacity(
              opacity: _opacity,
              child: _OptionalBlur(
                blur: _blur,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12), // 卡片外边距
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(12), // 仿 Apple Music 圆角
                    child: AnimatedBuilder(
                      animation: Listenable.merge(_ripples.map((r) => r.controller).toList()),
                      builder: (context, child) {
                        // 根据涟漪进度计算背景透明度
                        double bgOpacity = 0.0;
                        if (_ripples.isNotEmpty) {
                          final maxProgress = _ripples.map((r) => r.controller.value).reduce((a, b) => a > b ? a : b);
                          bgOpacity = 0.12 * (1.0 - maxProgress);
                        }

                        return Container(
                          // 关键约束：限制渲染宽度与测量宽度一致
                          constraints: BoxConstraints(maxWidth: widget.viewportWidth),
                          padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 10), // 卡片内边距
                          color: Colors.white.withOpacity(bgOpacity),
                          alignment: Alignment.centerLeft, // HTML: display: flex; align-items: center
                          child: Stack(
                            alignment: Alignment.centerLeft,
                            children: [
                              _buildInnerContent(),
                              // 涟漪层 (已在 ClipRRect 内部)
                              ..._ripples.map((ripple) => _buildRipple(ripple)),
                            ],
                          ),
                        );
                      },
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildRipple(_RippleInfo ripple) {
    return AnimatedBuilder(
      animation: ripple.controller,
      builder: (context, child) {
        return CustomPaint(
          painter: _RipplePainter(
            progress: ripple.controller.value,
            center: ripple.position,
          ),
        );
      },
    );
  }
  Widget _buildInnerContent() {
    if (widget.isDots) {
      // Find the shared position notifier from the parent state if possible, or create a temporary one?
      // Since _ElasticLyricLine doesn't have direct access to the parent's notifier, 
      // but we need real-time updates for dots.
      // Ideally _ElasticLyricLine should also have a position notifier or listen to one.
      // However, looking at existing code, _KaraokeText creates its own ticker/notifier.
      // We should probably do the same for _CountdownDots to be self-contained and performant.
      return _CountdownDots(
        startTime: widget.dotsStartTime ?? Duration.zero,
        endTime: widget.dotsEndTime ?? Duration.zero,
      );
    }
    final fontFamily = LyricFontService().currentFontFamily ?? 'Microsoft YaHei';
    final double textFontSize = LyricStyleService().fontSize;

    // 颜色: 使用动画值
    Color textColor = _textColor;
    
    // 构建文本 Widget
    Widget textWidget;
    // 只有当服务端提供了逐字歌词(hasWordByWord)时，才启用卡拉OK动画
    // 否则仅保留基础的变白+放大效果 (由 textColor 和 parent scale控制)
    if (widget.isActive && widget.lyric.hasWordByWord) {
      textWidget = _KaraokeText(
        text: widget.text,
        lyric: widget.lyric,
        lyrics: widget.lyrics,
        index: widget.index,
        originalTextStyle: TextStyle(
             fontFamily: fontFamily,
             fontSize: textFontSize, 
             fontWeight: FontWeight.w800,
             color: textColor, // Use animated color
             height: 1.15, // 缩小行高以修复间距过大问题
        ),
      );
    } else {
      textWidget = Text(
        widget.text,
        style: TextStyle(
          fontFamily: fontFamily,
          fontSize: textFontSize, 
          fontWeight: FontWeight.w800,
          color: textColor,
          height: 1.15, // 缩小行高以修复间距过大问题
        ),
      );
    }
    
    // 如果有翻译
    if (widget.showTranslation && widget.translation != null && widget.translation!.isNotEmpty) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          textWidget,
          Padding(
            padding: const EdgeInsets.only(top: 4.0), // 缩小译文间距 (原 8.0)
            child: Text(
              widget.translation!,
              style: TextStyle(
                fontFamily: fontFamily,
              fontSize: textFontSize * 0.56, // 译文约原文 56% 大小
                fontWeight: FontWeight.w600,
                color: Colors.white.withOpacity(0.3),
                height: 1.4, // 增加行高防止译文本身换行时拥挤
              ),
            ),
          )
        ],
      );
    }
    
    return textWidget;
  }
}

/// 性能优化：模糊组件
class _OptionalBlur extends StatelessWidget {
  final double blur;
  final Widget child;

  const _OptionalBlur({required this.blur, required this.child});

  @override
  Widget build(BuildContext context) {
    // 只有模糊度显着时才渲染滤镜，减少 GPU 合成开销
    if (blur < 1.0) return child;
    return ImageFiltered(
      imageFilter: ImageFilter.blur(sigmaX: blur, sigmaY: blur),
      child: child,
    );
  }
}

/// 卡拉OK文本组件 - 实现逐字填充效果
/// (保留原有逻辑)
class _KaraokeText extends StatefulWidget {
  final String text;
  final LyricLine lyric;
  final List<LyricLine> lyrics;
  final int index;
  final TextStyle originalTextStyle; // 新增：允许外部传入样式

  const _KaraokeText({
    required this.text,
    required this.lyric,
    required this.lyrics,
    required this.index,
    required this.originalTextStyle,
  });

  @override
  State<_KaraokeText> createState() => _KaraokeTextState();
}

class _KaraokeTextState extends State<_KaraokeText> with SingleTickerProviderStateMixin {
  late Ticker _ticker;
  double _lineProgress = 0.0;
  
  // [Performance] 公用进度通知器，供所有 _WordFillWidget 共享
  final ValueNotifier<Duration> _positionNotifier = ValueNotifier(Duration.zero);

  // 缓存
  double _cachedMaxWidth = 0.0;
  TextStyle? _cachedStyle;
  int _cachedLineCount = 1;
  double _line1Width = 0.0;
  double _line2Width = 0.0;
  double _line1Height = 0.0;
  double _line2Height = 0.0;
  double _line1Ratio = 0.5;

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

  Duration _lastSyncPlayerPos = Duration.zero;
  Duration _lastSyncTickerElapsed = Duration.zero;

  void _onTick(Duration elapsed) {
    if (!mounted) return;

    final currentPos = PlayerService().position;
    final isPlaying = PlayerService().isPlaying;

    // --- 核心：进度外推 (Extrapolation) ---
    // 如果播放器进度发生了变化，重置基准点
    if (currentPos != _lastSyncPlayerPos) {
      _lastSyncPlayerPos = currentPos;
      _lastSyncTickerElapsed = elapsed;
    }

    Duration extrapolatedPos = currentPos;
    if (isPlaying) {
      // 根据上次同步后的时间流逝，外推当前进度
      final timeSinceSync = elapsed - _lastSyncTickerElapsed;
      // 限制外推范围，避免跳转导致的瞬间位置异常 (通常外推不超过 500ms)
      if (timeSinceSync.inMilliseconds > 0 && timeSinceSync.inMilliseconds < 500) {
        extrapolatedPos = currentPos + timeSinceSync;
      }
    }

    // 更新广播通知器 (使用外推后的平滑进度)
    _positionNotifier.value = extrapolatedPos;

    // 处理行级进度 (针对非逐字模式)
    if (!widget.lyric.hasWordByWord || widget.lyric.words == null) {
      final elapsedFromStart = extrapolatedPos - widget.lyric.startTime;
      final newProgress = (elapsedFromStart.inMilliseconds / _duration.inMilliseconds).clamp(0.0, 1.0);

      if ((newProgress - _lineProgress).abs() > 0.005) {
        setState(() {
          _lineProgress = newProgress;
        });
      }
    }
  }
  
  // 简化版布局缓存，因为现在是单行/Wrap 为主
  void _updateLayoutCache(BoxConstraints constraints, TextStyle style) {
    if (_cachedMaxWidth == constraints.maxWidth && _cachedStyle == style) return;
    _cachedMaxWidth = constraints.maxWidth;
    _cachedStyle = style;
    
    final textSpan = TextSpan(text: widget.text, style: style);
    final textPainter = TextPainter(
      text: textSpan,
      textDirection: TextDirection.ltr,
    );
    textPainter.layout(maxWidth: constraints.maxWidth);
    
    final metrics = textPainter.computeLineMetrics();
    _cachedLineCount = metrics.length.clamp(1, 2);
    if (metrics.isNotEmpty) {
       _line1Width = metrics[0].width;
       _line1Height = metrics[0].height;
       if (metrics.length > 1) {
           _line2Width = metrics[1].width;
           _line2Height = metrics[1].height;
       }
    }
    
    final totalWidth = _line1Width + _line2Width;
    _line1Ratio = totalWidth > 0 ? _line1Width / totalWidth : 0.5;
    textPainter.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // 使用传入的样式
    final style = widget.originalTextStyle;

    if (widget.lyric.hasWordByWord && widget.lyric.words != null && widget.lyric.words!.isNotEmpty) {
      return _buildWordByWordEffect(style);
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        _updateLayoutCache(constraints, style);
        return _buildLineGradientEffect(style);
      },
    );
  }
  
  Widget _buildWordByWordEffect(TextStyle style) {
    final words = widget.lyric.words!;
    return Wrap(
      alignment: WrapAlignment.start,
      crossAxisAlignment: WrapCrossAlignment.center,
      runSpacing: 0.0, // 将间距归零，以抵消组件内部 Padding 增加带来的空隙
      children: List.generate(words.length, (index) {
        final word = words[index];
        return _WordFillWidget(
          key: ValueKey('${widget.index}_$index'),
          text: word.text,
          word: word,
          style: style,
          positionNotifier: _positionNotifier, // 传递共享通知器
        );
      }),
    );
  }
  
  Widget _buildLineGradientEffect(TextStyle style) {
    if (_cachedLineCount == 1) {
      return RepaintBoundary(
        child: ShaderMask(
          shaderCallback: (bounds) {
            return LinearGradient(
              begin: Alignment.centerLeft, end: Alignment.centerRight,
              colors: const [Colors.white, Color(0x99FFFFFF)],
              stops: [_lineProgress, _lineProgress],
              tileMode: TileMode.clamp,
            ).createShader(bounds);
          },
          blendMode: BlendMode.srcIn,
          child: Text(widget.text, style: style),
        ),
      );
    }
    
    // 多行逻辑：计算每行进度
    double line1Progress = 0.0; 
    double line2Progress = 0.0;
    
    if (_lineProgress <= _line1Ratio) {
      // 正在播放第一行
      if (_line1Ratio > 0) {
        line1Progress = _lineProgress / _line1Ratio;
      }
      line2Progress = 0.0;
    } else {
      // 第一行已播完，正在播放第二行
      line1Progress = 1.0;
      if (_line1Ratio < 1.0) {
        line2Progress = (_lineProgress - _line1Ratio) / (1.0 - _line1Ratio);
      }
    }
    
    final dimText = Text(
      widget.text,
      style: style.copyWith(color: const Color(0x99FFFFFF)),
    );
    
    final brightText = Text(
      widget.text,
      style: style.copyWith(color: Colors.white),
    );
    
    return RepaintBoundary(
      child: Stack(
        children: [
          dimText,
          // 第一行裁剪
          ClipRect(
            clipper: _LineClipper(
              lineIndex: 0,
              progress: line1Progress,
              lineHeight: _line1Height,
              lineWidth: _line1Width,
            ),
            child: brightText,
          ),
          // 第二行裁剪
          if (_cachedLineCount > 1)
            ClipRect(
              clipper: _LineClipper(
                lineIndex: 1,
                progress: line2Progress,
                lineHeight: _line2Height + 10,
                lineWidth: _line2Width,
                yOffset: _line1Height,
              ),
              child: brightText,
            ),
        ],
      ),
    );
  }
}

class _WordFillWidget extends StatefulWidget {
  final String text;
  final LyricWord word;
  final TextStyle style;
  final ValueNotifier<Duration> positionNotifier; // 新增

  const _WordFillWidget({
    Key? key,
    required this.text,
    required this.word,
    required this.style,
    required this.positionNotifier,
  }) : super(key: key);

  @override
  State<_WordFillWidget> createState() => _WordFillWidgetState();
}

class _WordFillWidgetState extends State<_WordFillWidget> with TickerProviderStateMixin {
  // 移除 _ticker，改用父级广播
  late AnimationController _floatController;
  late Animation<double> _floatOffset;
  double _progress = 0.0;
  bool? _isAsciiCached;

  static const double maxFloatOffset = -2.0; 

  @override
  void initState() {
    super.initState();
    
    _floatController = AnimationController(
       vsync: this,
       duration: const Duration(milliseconds: 1000), // Match HTML min duration (1s)
    );
    _floatOffset = Tween<double>(begin: 0.0, end: maxFloatOffset).animate(
      CurvedAnimation(parent: _floatController, curve: Curves.easeOutCubic),
    );

    _updateProgress(widget.positionNotifier.value); 
    
    // 监听父级进度广播
    widget.positionNotifier.addListener(_onPositionUpdate);

    // Initial check
    if (_progress > 0.0) {
      _floatController.forward();
    }
  }

  void _onPositionUpdate() {
     if (!mounted) return;
     final oldProgress = _progress;
     _updateProgress(widget.positionNotifier.value);

     // Trigger float immediately when playback starts for this word
     if (_progress > 0.001 && oldProgress <= 0.001) {
       _floatController.forward();
     } else if (_progress <= 0.001 && oldProgress > 0.001) {
       _floatController.reverse();
     }

     // Redraw if progress changes significantly
     final isAscii = _isAsciiText();
     final thresholdVal = isAscii ? 0.001 : 0.005;

     if ((oldProgress - _progress).abs() > thresholdVal || 
         (_progress >= 1.0 && oldProgress < 1.0) ||
         (_progress <= 0.0 && oldProgress > 0.0)) {
       setState(() {});
     }
  }

  @override
  void didUpdateWidget(_WordFillWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.positionNotifier != widget.positionNotifier) {
      oldWidget.positionNotifier.removeListener(_onPositionUpdate);
      widget.positionNotifier.addListener(_onPositionUpdate);
    }
    _updateProgress(widget.positionNotifier.value);
    
    if (_progress > 0.001) {
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
    final double effectiveY = _floatOffset.value;
          
    return RepaintBoundary(
      child: AnimatedBuilder(
        animation: _floatOffset,
        builder: (context, child) {
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
  
  // 使用固定像素宽度的渐变，而不是相对比例，确保不同长度单词的过渡效果一致
  ShaderCallback _createGradientShader() {
      return (bounds) {
        List<Color> gradientColors;
        List<double> gradientStops;
        
        if (_progress <= 0.0) {
          gradientColors = const [Color(0x99FFFFFF), Color(0x99FFFFFF)];
          gradientStops = const [0.0, 1.0];
        } else if (_progress >= 1.0) {
          gradientColors = const [Colors.white, Colors.white];
          gradientStops = const [0.0, 1.0];
        } else {
          gradientColors = const [
            Colors.white,                  
            Colors.white,                  
            Color(0x99FFFFFF),             
            Color(0x99FFFFFF),             
          ];
          
          final double currentX = bounds.width * _progress;
          // 固定渐变区宽度 (像素)，例如 64px，这样短单词会被更柔和地覆盖，长单词也不会感觉突兀
          const double fadeWidth = 64.0; 
          
          final double fadeStart = currentX / bounds.width;
          final double fadeEnd = (currentX + fadeWidth) / bounds.width;
          
          gradientStops = [
            0.0,
            fadeStart.clamp(0.0, 1.0),    
            fadeEnd.clamp(0.0, 1.0),      
            1.0,
          ];
        }

        return LinearGradient(
          colors: gradientColors,
          stops: gradientStops,
        ).createShader(bounds);
      };
  }
  
  Widget _buildWholeWordEffect() {
    return ShaderMask(
      shaderCallback: _createGradientShader(),
      blendMode: BlendMode.srcIn,
      child: Text(widget.text, style: widget.style.copyWith(color: Colors.white)),
    );
  }

  Widget _buildLetterByLetterEffect() {
    final letters = widget.text.split('');
    final letterCount = letters.length;
    
    return ShaderMask(
      shaderCallback: _createGradientShader(),
      blendMode: BlendMode.srcIn,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.baseline,
        textBaseline: TextBaseline.alphabetic,
        children: List.generate(letterCount, (index) {
          final letter = letters[index];
          return Text(letter, style: widget.style.copyWith(color: Colors.white));
        }),
      ),
    );
  }
}

/// 裁剪器 (保留但可能未被直接使用，防止报错)
class _LineClipper extends CustomClipper<Rect> {
  final int lineIndex;
  final double progress;
  final double lineHeight;
  final double lineWidth;
  final double yOffset;
  _LineClipper({required this.lineIndex, required this.progress, required this.lineHeight, required this.lineWidth, this.yOffset = 0.0});
  @override Rect getClip(Size size) => Rect.fromLTWH(0, yOffset, lineWidth * progress, lineHeight);
  @override bool shouldReclip(_LineClipper oldClipper) => oldClipper.progress != progress;
}

/// 倒计时点组件 - Apple Music 风格 (Ported from HTML)
class _CountdownDots extends StatefulWidget {
  final Duration startTime;
  final Duration endTime;

  const _CountdownDots({
    required this.startTime,
    required this.endTime,
  });

  @override
  State<_CountdownDots> createState() => _CountdownDotsState();
}

class _CountdownDotsState extends State<_CountdownDots> with SingleTickerProviderStateMixin {
  late Ticker _ticker;
  
  // Animation State
  double _scale = 0.0;
  double _dot0Opacity = 0.25;
  double _dot1Opacity = 0.25;
  double _dot2Opacity = 0.25;

  // Extrapolation State
  Duration _lastSyncPlayerPos = Duration.zero;
  Duration _lastSyncTickerElapsed = Duration.zero;

  @override
  void initState() {
    super.initState();
    _ticker = createTicker(_onTick);
    _ticker.start();
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  // Utils ported from HTML
  double _easeOutExpo(double x) {
    return x == 1.0 ? 1.0 : 1.0 - pow(2, -10 * x);
  }

  double _easeInOutBack(double x) {
    const c1 = 1.70158;
    const c2 = c1 * 1.525;
    return x < 0.5
        ? (pow(2 * x, 2) * ((c2 + 1) * 2 * x - c2)) / 2
        : (pow(2 * x - 2, 2) * ((c2 + 1) * (x * 2 - 2) + c2) + 2) / 2;
  }

  void _onTick(Duration elapsed) {
    if (!mounted) return;

    final isPlaying = PlayerService().isPlaying;
    final currentPos = PlayerService().position;

    // --- Extrapolation Logic ---
    if (currentPos != _lastSyncPlayerPos) {
      _lastSyncPlayerPos = currentPos;
      _lastSyncTickerElapsed = elapsed;
    }

    Duration extrapolatedPos = currentPos;
    if (isPlaying) {
      final timeSinceSync = elapsed - _lastSyncTickerElapsed;
      if (timeSinceSync.inMilliseconds > 0 && timeSinceSync.inMilliseconds < 500) {
        extrapolatedPos = currentPos + timeSinceSync;
      }
    }
    // ---------------------------

    final startMs = widget.startTime.inMilliseconds;
    final endMs = widget.endTime.inMilliseconds;
    final interludeDuration = (endMs - startMs).toDouble();
    final currentDuration = (extrapolatedPos.inMilliseconds - startMs).toDouble();

    if (interludeDuration <= 0) {
       _resetState();
       return;
    }

    // Logic from HTML InterludeDots.update
    if (currentDuration <= interludeDuration && currentDuration >= 0) {
      const targetBreatheDuration = 1500.0;
      final breatheDuration = interludeDuration / (interludeDuration / targetBreatheDuration).ceil();
      
      double scale = 1.0;
      double globalOpacity = 1.0;

      // Breathe
      scale *= sin(1.5 * pi - (currentDuration / breatheDuration) * 2) / 20 + 1;

      // Entry
      if (currentDuration < 2000) {
        scale *= _easeOutExpo((currentDuration / 2000).clamp(0.0, 1.0));
      }

      // Global Opacity Entry
      if (currentDuration < 500) {
        globalOpacity = 0.0;
      } else if (currentDuration < 1000) {
        globalOpacity *= (currentDuration - 500) / 500;
      }

      // Exit
      if (interludeDuration - currentDuration < 750) {
        scale *= 1.0 - _easeInOutBack(((750 - (interludeDuration - currentDuration)) / 750 / 2).clamp(0.0, 1.0));
      }
      if (interludeDuration - currentDuration < 375) {
        globalOpacity *= ((interludeDuration - currentDuration) / 375).clamp(0.0, 1.0);
      }

      // Final scale adjustment
      scale = max(0.0, scale) * 0.7; // HTML uses 0.7 multiplier at end

      // Dots Opacity Cascade
      final dotsDuration = max(0.0, interludeDuration - 750);
      
      // Helper to match HTML: clamp(0.25, ..., 1)
      double calcOpacity(double val) => (max(0.0, globalOpacity * val)).clamp(0.25, 1.0);
      // Wait, HTML logic: 
      // this.dot0.style.opacity = clamp(0, Math.max(0, globalOpacity * dot0Opacity), 1);
      // dot0Opacity = clamp(0.25, val, 1);
      // So if globalOpacity is 0, final result is 0.
      // If globalOpacity is 1, final result is [0.25, 1].
      
      double getRawDotOpacity(double t) {
          // ((currentDuration * 3) / dotsDuration) * 0.75
          // Logic:
          // dot0: currentDuration
          // dot1: currentDuration - dotsDuration/3
          // dot2: currentDuration - dotsDuration/3*2
          if (dotsDuration <= 0) return 0.25;
          final val = (t * 3 / dotsDuration) * 0.75;
          return val.clamp(0.25, 1.0);
      }

      double d0 = getRawDotOpacity(currentDuration);
      double d1 = getRawDotOpacity(currentDuration - dotsDuration / 3);
      double d2 = getRawDotOpacity(currentDuration - (dotsDuration / 3) * 2);

      // Apply Global Opacity
      // Formula: clamp(0, max(0, global * dot), 1)
      double finalize(double dotOp) => (max(0.0, globalOpacity * dotOp)).clamp(0.0, 1.0);

      setState(() {
        _scale = scale;
        _dot0Opacity = finalize(d0);
        _dot1Opacity = finalize(d1);
        _dot2Opacity = finalize(d2);
      });

    } else {
      // Out of bounds
      _resetState();
    }
  }

  void _resetState() {
     if (_scale != 0.0 || _dot0Opacity != 0.25) {
        setState(() {
          _scale = 0.0;
          _dot0Opacity = 0.0; 
          _dot1Opacity = 0.0; 
          _dot2Opacity = 0.0;
        });
     }
  }

  @override
  Widget build(BuildContext context) {
    if (_scale <= 0.01) return const SizedBox();

    return Transform.scale(
      scale: _scale,
      child: SizedBox(
        height: 40,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildDot(_dot0Opacity),
            const SizedBox(width: 12), // Doubled gap
            _buildDot(_dot1Opacity),
            const SizedBox(width: 12),
            _buildDot(_dot2Opacity),
          ],
        ),
      ),
    );
  }

  Widget _buildDot(double opacity) {
    return Opacity(
      opacity: opacity,
      child: Container(
        width: 20,
        height: 20,
        decoration: const BoxDecoration(
          color: Colors.white,
          shape: BoxShape.circle,
        ),
      ),
    );
  }
}

/// 涟漪信息类
class _RippleInfo {
  final Offset position;
  final AnimationController controller;
  _RippleInfo({required this.position, required this.controller});
}

/// 涟漪绘制器 - 仿 Apple Music 风格
class _RipplePainter extends CustomPainter {
  final double progress;
  final Offset center;

  _RipplePainter({required this.progress, required this.center});

  @override
  void paint(Canvas canvas, Size size) {
    // 极快扩张，平滑淡出
    final double radius = 300.0 * Curves.easeOutCubic.transform(progress);
    final double opacity = (1.0 - Curves.easeOut.transform(progress)) * 0.25;

    final paint = Paint()
      ..color = Colors.white.withOpacity(opacity)
      ..style = PaintingStyle.fill;

    canvas.drawCircle(center, radius, paint);
  }

  @override
  bool shouldRepaint(_RipplePainter oldDelegate) => oldDelegate.progress != progress;
}
