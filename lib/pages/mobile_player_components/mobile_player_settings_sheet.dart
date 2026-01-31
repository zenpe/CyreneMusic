import 'package:flutter/material.dart';
import '../../models/track.dart';
import 'settings_sections/settings_sections.dart';

/// 移动端播放器设置底部弹出板 - Material Design Expressive 风格
/// 从底部弹出，包含播放顺序、播放器样式、背景、睡眠定时器等设置
class MobilePlayerSettingsSheet extends StatefulWidget {
  final Track? currentTrack;
  
  const MobilePlayerSettingsSheet({
    super.key,
    this.currentTrack,
  });

  /// 显示设置底部弹出板
  static void show(BuildContext context, {Track? currentTrack}) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => MobilePlayerSettingsSheet(currentTrack: currentTrack),
    );
  }

  @override
  State<MobilePlayerSettingsSheet> createState() => _MobilePlayerSettingsSheetState();
}

class _MobilePlayerSettingsSheetState extends State<MobilePlayerSettingsSheet>
    with SingleTickerProviderStateMixin {
  late AnimationController _animController;
  late Animation<double> _scaleAnimation;
  // 性能优化：动画完成后停止使用 ScaleTransition
  bool _animationCompleted = false;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      duration: const Duration(milliseconds: 400),
      vsync: this,
    );
    _scaleAnimation = CurvedAnimation(
      parent: _animController,
      curve: Curves.elasticOut,
    );
    
    // 监听动画完成
    _animController.addStatusListener(_onAnimationStatus);
    _animController.forward();
  }

  void _onAnimationStatus(AnimationStatus status) {
    if (status == AnimationStatus.completed && mounted) {
      setState(() => _animationCompleted = true);
    }
  }

  @override
  void dispose() {
    _animController.removeStatusListener(_onAnimationStatus);
    _animController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;
    
    return DraggableScrollableSheet(
      initialChildSize: 0.6,
      minChildSize: 0.3,
      maxChildSize: 0.9,
      expand: false,
      builder: (context, scrollController) {
        // 构建主内容
        final content = Container(
          decoration: BoxDecoration(
            // Expressive 渐变背景
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                colorScheme.surfaceContainerHigh,
                colorScheme.surfaceContainerHighest.withOpacity(isDark ? 0.95 : 0.98),
              ],
            ),
            // 超大圆角
            borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
            // 柔和阴影
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(isDark ? 0.4 : 0.15),
                blurRadius: 30,
                offset: const Offset(0, -10),
              ),
            ],
          ),
            child: Column(
              children: [
                // Expressive 拖动指示器
                _buildDragHandle(colorScheme),
                
                // Expressive 标题栏
                _buildTitleBar(colorScheme, isDark),
                
                // 分隔线
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: Container(
                    height: 1,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          colorScheme.outlineVariant.withOpacity(0),
                          colorScheme.outlineVariant.withOpacity(0.5),
                          colorScheme.outlineVariant.withOpacity(0),
                        ],
                      ),
                    ),
                  ),
                ),
                
                // 设置列表
                Expanded(
                  child: ListView(
                    controller: scrollController,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    physics: const BouncingScrollPhysics(),
                    // 性能优化：缓存更多的内容避免频繁重建
                    cacheExtent: 500,
                    // 子组件使用 RepaintBoundary 隔离重绘
                    children: [
                      // 播放顺序
                      RepaintBoundary(child: PlaybackModeSection()),
                      
                      SizedBox(height: 24),
                      
                      // 播放器样式
                      RepaintBoundary(child: PlayerStyleSection()),
                      
                      SizedBox(height: 24),

                      // 均衡器
                      RepaintBoundary(child: EqualizerSection()),
                      
                      SizedBox(height: 24),

                      // 歌词细节设置
                      RepaintBoundary(child: LyricDetailSection()),

                      SizedBox(height: 24),
                      
                      // 播放器背景
                      RepaintBoundary(child: BackgroundSection()),
                      
                      SizedBox(height: 24),

                      // 自动折叠控制栏
                      RepaintBoundary(child: InteractionSection()),

                      SizedBox(height: 24),
                      
                      // 睡眠定时器
                      RepaintBoundary(child: SleepTimerSection()),
                      
                      SizedBox(height: 48),
                    ],
                  ),
                ),
              ],
            ),
          );
        
        // 性能优化：动画完成后不使用 ScaleTransition
        if (_animationCompleted) {
          return content;
        }
        
        return ScaleTransition(
          scale: Tween<double>(begin: 0.95, end: 1.0).animate(_scaleAnimation),
          child: content,
        );
      },
    );
  }

  /// Expressive 风格拖动指示器
  Widget _buildDragHandle(ColorScheme colorScheme) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      child: Container(
        padding: const EdgeInsets.only(top: 14, bottom: 10),
        child: Container(
          width: 48,
          height: 5,
          decoration: BoxDecoration(
            color: colorScheme.outline.withOpacity(0.4),
            borderRadius: BorderRadius.circular(3),
          ),
        ),
      ),
    );
  }

  /// Expressive 风格标题栏
  Widget _buildTitleBar(ColorScheme colorScheme, bool isDark) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 4, 16, 16),
      child: Row(
        children: [
          // 图标容器 - 渐变背景
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  colorScheme.primary.withOpacity(0.2),
                  colorScheme.primary.withOpacity(0.1),
                ],
              ),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(
              Icons.tune_rounded,
              color: colorScheme.primary,
              size: 24,
            ),
          ),
          const SizedBox(width: 14),
          // 标题文字 - Expressive 大字号
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '播放器设置',
                  style: TextStyle(
                    color: colorScheme.onSurface,
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.5,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '自定义您的听歌体验',
                  style: TextStyle(
                    color: colorScheme.onSurfaceVariant.withOpacity(0.7),
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
          // 关闭按钮 - FilledTonal 风格
          Material(
            color: colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(14),
            child: InkWell(
              onTap: () => Navigator.pop(context),
              borderRadius: BorderRadius.circular(14),
              child: Container(
                width: 44,
                height: 44,
                alignment: Alignment.center,
                child: Icon(
                  Icons.close_rounded,
                  color: colorScheme.onSurfaceVariant,
                  size: 22,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
