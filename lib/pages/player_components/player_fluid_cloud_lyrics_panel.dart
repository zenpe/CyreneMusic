import 'dart:async';
import 'dart:ui'; // 导入 dart:ui 以使用 ImageFilter
import 'package:flutter/material.dart';
import '../../services/player_service.dart';
import '../../models/lyric_line.dart';

/// 流体云样式歌词面板
/// 云朵般柔和流动的歌词效果
class PlayerFluidCloudLyricsPanel extends StatefulWidget {
  final List<LyricLine> lyrics;
  final int currentLyricIndex;
  final bool showTranslation;

  const PlayerFluidCloudLyricsPanel({
    super.key,
    required this.lyrics,
    required this.currentLyricIndex,
    required this.showTranslation,
  });

  @override
  State<PlayerFluidCloudLyricsPanel> createState() => _PlayerFluidCloudLyricsPanelState();
}

class _PlayerFluidCloudLyricsPanelState extends State<PlayerFluidCloudLyricsPanel> 
    with TickerProviderStateMixin {
  final ScrollController _scrollController = ScrollController();
  int? _selectedLyricIndex; // 手动选择的歌词索引
  bool _isManualMode = false; // 是否处于手动模式
  Timer? _autoResetTimer; // 自动回退定时器
  AnimationController? _timeCapsuleAnimationController;
  Animation<double>? _timeCapsuleFadeAnimation;
  
  // 流体动画控制器
  late AnimationController _fluidAnimationController;
  late Animation<double> _fluidAnimation;
  
  // Apple Music 风格切换动画控制器
  late AnimationController _transitionAnimationController;
  late Animation<double> _transitionAnimation;
  
  // 滚动速度追踪
  double _scrollVelocity = 0.0;
  int _lastLyricIndex = -1;
  
  // 记录上一个歌词索引，用于过渡动画
  int _previousLyricIndex = -1;

  @override
  void initState() {
    super.initState();
    _initializeAnimations();
  }

  @override
  void dispose() {
    _autoResetTimer?.cancel();
    _timeCapsuleAnimationController?.dispose();
    _fluidAnimationController.dispose();
    _transitionAnimationController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  /// 初始化动画
  void _initializeAnimations() {
    // 时间胶囊动画
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
    
    // 流体动画（持续循环）- 使用更柔和的曲线
    _fluidAnimationController = AnimationController(
      duration: const Duration(milliseconds: 2500),
      vsync: this,
    )..repeat(reverse: true);
    
    _fluidAnimation = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(
      parent: _fluidAnimationController,
      curve: Curves.easeInOutSine, // 更柔和的正弦曲线
    ));
    
    // Apple Music 风格切换动画
    // 0.0 = 切换开始（旧歌词状态）
    // 1.0 = 切换完成（新歌词状态）
    _transitionAnimationController = AnimationController(
      duration: const Duration(milliseconds: 400),
      vsync: this,
    );
    
    _transitionAnimation = CurvedAnimation(
      parent: _transitionAnimationController,
      curve: Curves.easeOutCubic,
    );
  }

  @override
  void didUpdateWidget(PlayerFluidCloudLyricsPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    
    // 如果当前播放索引变化且不处于手动模式，则滚动
    if (widget.currentLyricIndex != oldWidget.currentLyricIndex && !_isManualMode) {
      // 触发 Apple Music 风格切换动画
      if (_lastLyricIndex != widget.currentLyricIndex) {
        _previousLyricIndex = _lastLyricIndex;
        _lastLyricIndex = widget.currentLyricIndex;
        _transitionAnimationController.forward(from: 0.0);
      }
      _scrollToCurrentLyric();
    }
  }

  /// 滚动到当前歌词
  void _scrollToCurrentLyric() {
    if (!_scrollController.hasClients) return;
    
    // 简单的滚动计算，具体在 ListView 的 itemExtent 配合下会更准
    // 这里我们将在 LayoutBuilder 中计算 itemHeight 后再执行精确滚动
    // 但由于 didUpdateWidget 在 build 之前，可能拿不到最新的 itemHeight
    // 所以我们在 build 中也会检查滚动
    setState(() {}); // 触发 build 以重新计算滚动位置
  }

  /// 开始手动模式
  void _startManualMode() {
    if (_isManualMode) {
      _resetAutoTimer();
      return;
    }

    setState(() {
      _isManualMode = true;
    });
    
    _timeCapsuleAnimationController?.forward();
    _resetAutoTimer();
  }

  /// 重置自动回退定时器
  void _resetAutoTimer() {
    _autoResetTimer?.cancel();
    _autoResetTimer = Timer(const Duration(seconds: 4), _exitManualMode);
  }

  /// 退出手动模式
  void _exitManualMode() {
    if (!mounted) return;
    
    setState(() {
      _isManualMode = false;
      _selectedLyricIndex = null;
    });
    
    _timeCapsuleAnimationController?.reverse();
    _autoResetTimer?.cancel();
    
    // 退出手动模式后，立即滚回当前歌词
    _scrollToCurrentLyric();
  }

  /// 跳转到选中的歌词时间
  void _seekToSelectedLyric() {
    if (_selectedLyricIndex != null && 
        _selectedLyricIndex! >= 0 && 
        _selectedLyricIndex! < widget.lyrics.length) {
      
      final selectedLyric = widget.lyrics[_selectedLyricIndex!];
      if (selectedLyric.startTime != null) {
        PlayerService().seek(selectedLyric.startTime!);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('已跳转到: ${selectedLyric.text}'),
            duration: const Duration(seconds: 1),
          ),
        );
      }
    }
    
    _exitManualMode();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.zero, 
      child: Stack(
        children: [
          // 主要歌词区域
          widget.lyrics.isEmpty
              ? _buildNoLyric()
              : _buildFluidCloudLyricList(),
          
          // 时间胶囊组件 (当手动模式开启且选中的索引有效时显示)
          if (_isManualMode && _selectedLyricIndex != null)
            Positioned(
              right: 0,
              top: 0,
              bottom: 0,
              child: _buildTimeCapsule(),
            ),
        ],
      ),
    );
  }

  /// 构建无歌词提示
  Widget _buildNoLyric() {
    return ValueListenableBuilder<Color?>(
      valueListenable: PlayerService().themeColorNotifier,
      builder: (context, themeColor, child) {
        final textColor = _getAdaptiveLyricColor(themeColor, false).withOpacity(0.5);
        return Center(
          child: Text(
            '暂无歌词',
            style: TextStyle(
              color: textColor,
              fontSize: 16,
            ),
          ),
        );
      },
    );
  }

  /// 构建流体云样式歌词列表
  Widget _buildFluidCloudLyricList() {
    return RepaintBoundary(
      child: ValueListenableBuilder<Color?>(
        valueListenable: PlayerService().themeColorNotifier,
        builder: (context, themeColor, child) {
          return LayoutBuilder(
            builder: (context, constraints) {
              // 桌面端可视行数
              const int baseVisibleLines = 7;
              // 根据滚动速度动态调整间距（速度越快，间距稍微增大，产生拉伸效果）
              final velocityFactor = (1.0 + (_scrollVelocity.abs() * 0.0001)).clamp(1.0, 1.15);
              // itemHeight 不受间距动画影响，保持滚动位置稳定
              final itemHeight = (constraints.maxHeight / baseVisibleLines) * velocityFactor;
              final viewportHeight = constraints.maxHeight;
              
              // 确保在非手动模式下滚动到正确位置
              // 使用 addPostFrameCallback 避免在 build 过程中调用 scroll
              if (!_isManualMode && _scrollController.hasClients) {
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (_scrollController.hasClients) {
                    // 由于设置了 padding 使得首行居中，所以直接滚动到 index * itemHeight 即可让对应行居中
                    final targetOffset = widget.currentLyricIndex * itemHeight;
                    
                    // 如果距离太远，直接跳转，否则动画
                    if ((_scrollController.offset - targetOffset).abs() > viewportHeight * 2) {
                      _scrollController.jumpTo(targetOffset);
                    } else {
                      // 使用平滑的缓出曲线，让滚动更丝滑
                      _scrollController.animateTo(
                        targetOffset,
                        duration: const Duration(milliseconds: 800),
                        curve: Curves.easeOutCubic,
                      );
                    }
                  }
                });
              }
              
              return NotificationListener<ScrollNotification>(
                onNotification: (notification) {
                  if (notification is ScrollStartNotification && 
                      notification.dragDetails != null) {
                    _startManualMode();
                  } else if (notification is ScrollUpdateNotification) {
                    if (notification.scrollDelta != null) {
                      setState(() {
                        _scrollVelocity = notification.scrollDelta!;
                      });
                    }
                    
                    if (_isManualMode) {
                      final centerOffset = _scrollController.offset + (viewportHeight / 2);
                      final index = (centerOffset / itemHeight).floor();
                      
                      if (index >= 0 && index < widget.lyrics.length && index != _selectedLyricIndex) {
                        setState(() {
                          _selectedLyricIndex = index;
                        });
                      }
                      _resetAutoTimer();
                    }
                  } else if (notification is ScrollEndNotification) {
                    setState(() {
                      _scrollVelocity = 0.0;
                    });
                  }
                  return false;
                },
                child: AnimatedBuilder(
                  animation: _transitionAnimation,
                  builder: (context, child) {
                    final transitionProgress = _transitionAnimation.value;
                    
                    return ListView.builder(
                      controller: _scrollController,
                      itemCount: widget.lyrics.length,
                      itemExtent: itemHeight,
                      padding: EdgeInsets.symmetric(
                        vertical: (viewportHeight - itemHeight) / 2
                      ),
                      physics: const BouncingScrollPhysics(),
                      itemBuilder: (context, index) {
                        final lyric = widget.lyrics[index];
                        final isCurrentPlaying = index == widget.currentLyricIndex;
                        final wasPreviousPlaying = index == _previousLyricIndex;
                        
                        final displayIndex = _isManualMode && _selectedLyricIndex != null 
                            ? _selectedLyricIndex! 
                            : widget.currentLyricIndex;
                        
                        final distance = (index - displayIndex).abs();
                        
                        // Apple Music 风格视觉参数
                        // 当前歌词：完全高亮，大字体
                        // 其他歌词：根据距离逐渐变暗变小
                        double opacity;
                        double scale;
                        double blur;
                        
                        if (isCurrentPlaying) {
                          // 当前播放的歌词：从上一个状态过渡到高亮状态
                          if (wasPreviousPlaying) {
                            // 如果是同一行，保持高亮
                            opacity = 1.0;
                            scale = 1.0;
                            blur = 0.0;
                          } else {
                            // 新的当前歌词：从暗淡过渡到高亮
                            final prevDistance = (_previousLyricIndex >= 0) 
                                ? (index - _previousLyricIndex).abs() 
                                : 1;
                            final startOpacity = (1.0 - (prevDistance * 0.3)).clamp(0.3, 0.7);
                            final startScale = (1.0 - (prevDistance * 0.03)).clamp(0.94, 0.97);
                            final startBlur = (prevDistance * 0.8).clamp(0.0, 2.0);
                            
                            opacity = startOpacity + (1.0 - startOpacity) * transitionProgress;
                            scale = startScale + (1.0 - startScale) * transitionProgress;
                            blur = startBlur * (1.0 - transitionProgress);
                          }
                        } else if (wasPreviousPlaying && _previousLyricIndex >= 0) {
                          // 上一个播放的歌词：从高亮过渡到暗淡
                          final targetOpacity = (1.0 - (distance * 0.3)).clamp(0.3, 0.7);
                          final targetScale = (1.0 - (distance * 0.03)).clamp(0.94, 0.97);
                          final targetBlur = (distance * 0.8).clamp(0.0, 2.0);
                          
                          opacity = 1.0 - (1.0 - targetOpacity) * transitionProgress;
                          scale = 1.0 - (1.0 - targetScale) * transitionProgress;
                          blur = targetBlur * transitionProgress;
                        } else {
                          // 其他歌词：保持静态的距离衰减效果
                          opacity = (1.0 - (distance * 0.3)).clamp(0.3, 0.7);
                          scale = (1.0 - (distance * 0.03)).clamp(0.94, 0.97);
                          blur = (distance * 0.8).clamp(0.0, 2.0);
                        }
                        
                        return Center(
                          child: Transform.scale(
                            scale: scale,
                            child: Opacity(
                              opacity: opacity,
                              child: ImageFiltered(
                                imageFilter: ImageFilter.blur(sigmaX: blur, sigmaY: blur),
                                child: isCurrentPlaying
                                    ? _buildFluidCloudLyricLine(
                                        lyric, 
                                        themeColor, 
                                        itemHeight, 
                                        true
                                      )
                                    : _buildNormalLyricLine(
                                        lyric, 
                                        themeColor, 
                                        itemHeight
                                      ),
                              ),
                            ),
                          ),
                        );
                      },
                    );
                  },
                ),
              );
            },
          );
        },
      ),
    );
  }

  /// 构建流体云样式的歌词行（当前歌词）
  Widget _buildFluidCloudLyricLine(
    LyricLine lyric, 
    Color? themeColor, 
    double itemHeight, 
    bool isActuallyPlaying
  ) {
    return AnimatedBuilder(
      animation: Listenable.merge([PlayerService(), _fluidAnimation]),
      builder: (context, child) {
        final isSelected = _isManualMode && !isActuallyPlaying; 
        
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.center, // 居中
            children: [
              // 原文歌词 - 流体云效果
              _buildFluidCloudText(
                text: lyric.text,
                fontSize: 20,
                themeColor: themeColor,
                isSelected: isSelected,
                isPlaying: isActuallyPlaying,
              ),
              
              // 翻译歌词
              if (widget.showTranslation && 
                  lyric.translation != null && 
                  lyric.translation!.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    lyric.translation!,
                    textAlign: TextAlign.center, // 居中
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: _getAdaptiveLyricColor(themeColor, false)
                          .withOpacity(0.7),
                      fontSize: 14,
                      fontFamily: 'Microsoft YaHei',
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  /// 构建普通歌词行（非当前歌词）
  Widget _buildNormalLyricLine(
    LyricLine lyric, 
    Color? themeColor, 
    double itemHeight
  ) {
    final lyricColor = _getAdaptiveLyricColor(themeColor, false);
    final translationColor = lyricColor.withOpacity(0.5);
    
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center, // 居中
        children: [
          // 原文歌词
          Text(
            lyric.text,
            textAlign: TextAlign.center, // 居中
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: lyricColor,
              fontSize: 22,
              fontWeight: FontWeight.w600,
              height: 1.2,
              fontFamily: 'Microsoft YaHei',
            ),
          ),
          // 翻译歌词
          if (widget.showTranslation && 
              lyric.translation != null && 
              lyric.translation!.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(
                lyric.translation!,
                textAlign: TextAlign.center, // 居中
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: translationColor,
                  fontSize: 13,
                  fontFamily: 'Microsoft YaHei',
                ),
              ),
            ),
        ],
      ),
    );
  }

  /// 构建流体云文字效果
  Widget _buildFluidCloudText({
    required String text,
    required double fontSize,
    required Color? themeColor,
    required bool isSelected,
    required bool isPlaying,
  }) {
    final baseColor = _getAdaptiveLyricColor(themeColor, false);
    final highlightColor = _getAdaptiveLyricColor(themeColor, true);
    
    // Windows 端不需要左右移动的光效，直接使用纯色或简单的渐变
    // 如果是播放中状态，使用高亮色；如果是选中状态(手动模式)，使用橙色高亮
    
    final Color textColor;
    if (isSelected) {
      textColor = Colors.orange;
    } else if (isPlaying) {
      textColor = highlightColor;
    } else {
      textColor = baseColor;
    }

    return Text(
      text,
      style: TextStyle(
        color: textColor,
        fontSize: fontSize * 1.4, // 保持字体放大倍数
        fontWeight: FontWeight.w800,
        fontFamily: 'Microsoft YaHei',
        height: 1.2,
        shadows: isSelected 
          ? [
              Shadow(
                color: Colors.orange.withOpacity(0.6),
                blurRadius: 16,
                offset: const Offset(0, 0),
              ),
            ]
          : (isPlaying ? [
              Shadow(
                color: highlightColor.withOpacity(0.4),
                blurRadius: 16,
                offset: const Offset(0, 0),
              ),
            ] : []),
      ),
      textAlign: TextAlign.center,
      maxLines: 3,
      overflow: TextOverflow.ellipsis,
    );
  }

  /// 构建时间胶囊组件
  Widget _buildTimeCapsule() {
    if (_selectedLyricIndex == null || 
        _selectedLyricIndex! < 0 || 
        _selectedLyricIndex! >= widget.lyrics.length) {
      return const SizedBox.shrink();
    }

    final selectedLyric = widget.lyrics[_selectedLyricIndex!];
    final timeText = selectedLyric.startTime != null 
        ? _formatDuration(selectedLyric.startTime!)
        : '00:00';

    return FadeTransition(
      opacity: _timeCapsuleFadeAnimation!,
      child: Center(
        child: MouseRegion(
          cursor: SystemMouseCursors.click,
          child: GestureDetector(
            onTap: _seekToSelectedLyric,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              decoration: BoxDecoration(
                color: Colors.orange.withOpacity(0.9),
                borderRadius: BorderRadius.circular(24),
                border: Border.all(
                  color: Colors.white.withOpacity(0.3),
                  width: 1,
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.orange.withOpacity(0.4),
                    blurRadius: 16,
                    offset: const Offset(0, 6),
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // 时间显示
                  Text(
                    timeText,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1.2,
                    ),
                  ),
                  const SizedBox(height: 6),
                  // 跳转提示
                  const Text(
                    '点击跳转',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// 格式化时间显示
  String _formatDuration(Duration duration) {
    final minutes = duration.inMinutes;
    final seconds = duration.inSeconds % 60;
    return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }

  /// 根据背景色亮度判断应该使用深色还是浅色文字
  bool _shouldUseDarkText(Color backgroundColor) {
    final luminance = backgroundColor.computeLuminance();
    return luminance > 0.5;
  }

  /// 获取自适应的歌词颜色
  Color _getAdaptiveLyricColor(Color? themeColor, bool isCurrent) {
    final color = themeColor ?? Colors.grey[700]!;
    final useDarkText = _shouldUseDarkText(color);
    
    if (useDarkText) {
      // 亮色背景，使用深色文字
      return isCurrent 
          ? Colors.black87 
          : Colors.black54;
    } else {
      // 暗色背景，使用浅色文字
      return isCurrent 
          ? Colors.white 
          : Colors.white.withOpacity(0.45);
    }
  }
}
