import 'dart:async';
import 'dart:math' as math;
import 'dart:ui';
import 'package:flutter/material.dart';
import '../../services/player_service.dart';
import '../../models/lyric_line.dart';

/// 移动端流体云样式歌词组件
/// 适配移动端的触摸交互和屏幕尺寸
class MobilePlayerFluidCloudLyric extends StatefulWidget {
  final List<LyricLine> lyrics;
  final int currentLyricIndex;
  final bool showTranslation;
  final VoidCallback? onTap;

  const MobilePlayerFluidCloudLyric({
    super.key,
    required this.lyrics,
    required this.currentLyricIndex,
    this.showTranslation = true,
    this.onTap,
  });

  @override
  State<MobilePlayerFluidCloudLyric> createState() => _MobilePlayerFluidCloudLyricState();
}

class _MobilePlayerFluidCloudLyricState extends State<MobilePlayerFluidCloudLyric> 
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
  
  // QQ弹弹效果动画控制器
  late AnimationController _bounceAnimationController;
  late Animation<double> _bounceAnimation;
  
  // 滚动速度追踪
  double _scrollVelocity = 0.0;
  int _lastLyricIndex = -1;

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
    _bounceAnimationController.dispose();
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
    
    // QQ弹弹效果动画
    _bounceAnimationController = AnimationController(
      duration: const Duration(milliseconds: 600),
      vsync: this,
    );
    
    _bounceAnimation = Tween<double>(
      begin: 0.95,
      end: 1.0,
    ).animate(CurvedAnimation(
      parent: _bounceAnimationController,
      curve: Curves.elasticOut, // 弹性曲线
    ));
  }

  @override
  void didUpdateWidget(MobilePlayerFluidCloudLyric oldWidget) {
    super.didUpdateWidget(oldWidget);
    
    // 如果当前播放索引变化且不处于手动模式，则滚动
    if (widget.currentLyricIndex != oldWidget.currentLyricIndex && !_isManualMode) {
      // 触发QQ弹弹效果
      if (_lastLyricIndex != widget.currentLyricIndex) {
        _lastLyricIndex = widget.currentLyricIndex;
        _bounceAnimationController.forward(from: 0.0);
      }
      _scrollToCurrentLyric();
    }
  }

  /// 滚动到当前歌词
  void _scrollToCurrentLyric() {
    if (!_scrollController.hasClients) return;
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
            behavior: SnackBarBehavior.floating,
            margin: const EdgeInsets.only(bottom: 100, left: 20, right: 20),
          ),
        );
      }
    }
    
    _exitManualMode();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: widget.onTap, // 支持点击进入全屏歌词页（如果需要）
      child: Container(
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
                right: 16,
                top: 0,
                bottom: 0,
                child: Center(child: _buildTimeCapsule()),
              ),
          ],
        ),
      ),
    );
  }

  /// 构建无歌词提示
  Widget _buildNoLyric() {
    return Center(
      child: Text(
        '暂无歌词',
        style: TextStyle(
          color: Colors.white.withOpacity(0.5),
          fontSize: 16,
        ),
      ),
    );
  }

  /// 构建流体云样式歌词列表
  Widget _buildFluidCloudLyricList() {
    return RepaintBoundary(
      child: LayoutBuilder(
        builder: (context, constraints) {
          // 移动端可视行数 - 动态调整以实现弹性间距
          const int baseVisibleLines = 6;
          // 根据滚动速度动态调整间距（速度越快，间距稍微增大，产生拉伸效果）
          final velocityFactor = (1.0 + (_scrollVelocity.abs() * 0.0001)).clamp(1.0, 1.15);
          final itemHeight = (constraints.maxHeight / baseVisibleLines) * velocityFactor;
          final viewportHeight = constraints.maxHeight;
          
          // 确保在非手动模式下滚动到正确位置
          if (!_isManualMode && _scrollController.hasClients) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
               if (_scrollController.hasClients && mounted) {
                 final targetOffset = widget.currentLyricIndex * itemHeight;
                 if ((_scrollController.offset - targetOffset).abs() > viewportHeight * 2) {
                    _scrollController.jumpTo(targetOffset);
                 } else {
                    // 使用弹性曲线，让滚动更丝滑
                    _scrollController.animateTo(
                      targetOffset,
                      duration: const Duration(milliseconds: 800), // 增加动画时间
                      curve: Curves.easeOutCubic, // 使用平滑的缓出曲线
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
                // 追踪滚动速度用于动态间距
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
                // 滚动结束，重置速度
                setState(() {
                  _scrollVelocity = 0.0;
                });
              }
              return false;
            },
            child: ListView.builder(
              controller: _scrollController,
              itemCount: widget.lyrics.length,
              itemExtent: itemHeight,
              padding: EdgeInsets.symmetric(
                vertical: (viewportHeight - itemHeight) / 2
              ),
              physics: const BouncingScrollPhysics(),
              itemBuilder: (context, index) {
                final lyric = widget.lyrics[index];
                final isActuallyPlaying = index == widget.currentLyricIndex;
                
                final displayIndex = _isManualMode && _selectedLyricIndex != null 
                    ? _selectedLyricIndex! 
                    : widget.currentLyricIndex;
                
                final distance = (index - displayIndex).abs();
                
                // 视觉参数调整 - 更柔和的过渡
                final opacity = (1.0 - (distance * 0.18)).clamp(0.15, 1.0); // 更柔和的不透明度衰减
                final scale = (1.0 - (distance * 0.04)).clamp(0.90, 1.0); // 更柔和的缩放衰减
                final blur = distance == 0 ? 0.0 : (distance * 0.5).clamp(0.0, 1.2); // 渐进式模糊
                
                return Center(
                  child: AnimatedBuilder(
                    animation: _bounceAnimation,
                    builder: (context, child) {
                      // 只对当前播放的歌词应用弹跳效果
                      final bounceScale = isActuallyPlaying ? _bounceAnimation.value : 1.0;
                      
                      return Transform.scale(
                        scale: scale * bounceScale,
                        child: Opacity(
                          opacity: opacity,
                          child: ImageFiltered(
                            imageFilter: ImageFilter.blur(sigmaX: blur, sigmaY: blur),
                            child: isActuallyPlaying
                                ? _buildFluidCloudLyricLine(
                                    lyric, 
                                    itemHeight, 
                                    true
                                  )
                                : _buildNormalLyricLine(
                                    lyric, 
                                    itemHeight
                                  ),
                          ),
                        ),
                      );
                    },
                  ),
                );
              },
            ),
          );
        },
      ),
    );
  }

  /// 构建流体云样式的歌词行（当前歌词）
  Widget _buildFluidCloudLyricLine(
    LyricLine lyric, 
    double itemHeight, 
    bool isActuallyPlaying
  ) {
    return AnimatedBuilder(
      animation: _fluidAnimation,
      builder: (context, child) {
        final isSelected = _isManualMode && !isActuallyPlaying; 
        
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              _buildFluidCloudText(
                text: lyric.text,
                fontSize: 22, // 移动端字体略小
                isSelected: isSelected,
                isPlaying: isActuallyPlaying,
              ),
              
              if (widget.showTranslation && 
                  lyric.translation != null && 
                  lyric.translation!.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    lyric.translation!,
                    textAlign: TextAlign.center,
                    maxLines: 1, // 限制为1行防止溢出
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.7),
                      fontSize: 13,
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
  Widget _buildNormalLyricLine(LyricLine lyric, double itemHeight) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Text(
            lyric.text,
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 18, // 普通行字体
              fontWeight: FontWeight.w600,
              height: 1.2,
              fontFamily: 'Microsoft YaHei',
            ),
          ),
          if (widget.showTranslation && 
              lyric.translation != null && 
              lyric.translation!.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(
                lyric.translation!,
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: Colors.white.withOpacity(0.5),
                  fontSize: 12,
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
    required bool isSelected,
    required bool isPlaying,
  }) {
    final fluidValue = _fluidAnimation.value;
    final actualFontSize = fontSize * 1.2; 
    
    // 移动端使用更鲜艳的渐变
    final gradient = LinearGradient(
      begin: Alignment.centerLeft,
      end: Alignment.centerRight,
      colors: isSelected 
        ? [
            Colors.orange.withOpacity(0.6),
            Colors.orange,
            Colors.deepOrange,
            Colors.orange,
            Colors.orange.withOpacity(0.6),
          ]
        : [
            Colors.white,
            Colors.white, 
            Colors.white.withOpacity(0.9), // 高亮部分略有不同
            Colors.white,
            Colors.white,
          ],
      stops: [
        0.0,
        math.max(0.0, fluidValue - 0.4),
        fluidValue,
        math.min(1.0, fluidValue + 0.4),
        1.0,
      ],
    );
    
    return ShaderMask(
      shaderCallback: (bounds) => gradient.createShader(
        Rect.fromLTWH(0, 0, bounds.width, bounds.height),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: Colors.white,
          fontSize: actualFontSize,
          fontWeight: FontWeight.w800,
          fontFamily: 'Microsoft YaHei',
          height: 1.2,
          shadows: isSelected 
            ? [
                Shadow(
                  color: Colors.orange.withOpacity(0.6),
                  blurRadius: 12,
                  offset: const Offset(0, 0),
                ),
              ]
            : [
                Shadow(
                  color: Colors.white.withOpacity(0.5),
                  blurRadius: 12,
                  offset: const Offset(0, 0),
                ),
              ],
        ),
        textAlign: TextAlign.center,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
      ),
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
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.2),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
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

