import 'dart:io';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../services/player_service.dart';
import '../../services/player_background_service.dart';
import '../../models/track.dart';
import '../../models/song_detail.dart';
import '../../widgets/video_background_player.dart';

/// 移动端播放器背景组件
/// 根据设置显示不同类型的背景（自适应、纯色、图片、视频）
class MobilePlayerBackground extends StatelessWidget {
  const MobilePlayerBackground({super.key});

  @override
  Widget build(BuildContext context) {
    // 同时监听 PlayerBackgroundService 和 PlayerService
    // 以便在切换歌曲时刷新封面
    return AnimatedBuilder(
      animation: Listenable.merge([PlayerBackgroundService(), PlayerService()]),
      builder: (context, child) {
        return _buildBackground();
      },
    );
  }

  /// 构建背景
  Widget _buildBackground() {
    final backgroundService = PlayerBackgroundService();
    final player = PlayerService();
    final song = player.currentSong;
    final track = player.currentTrack;
    
    switch (backgroundService.backgroundType) {
      case PlayerBackgroundType.adaptive:
        // 自适应背景 - 检查是否启用封面渐变效果
        if (backgroundService.enableGradient) {
          return _buildCoverGradientBackground(song, track);
        } else {
          return _buildColorGradientBackground();
        }
        
      case PlayerBackgroundType.solidColor:
        // 纯色背景
        return _buildSolidColorBackground(backgroundService);
        
      case PlayerBackgroundType.image:
        // 图片背景
        return _buildImageBackground(backgroundService);
        
      case PlayerBackgroundType.video:
        // 视频背景
        return _buildVideoBackground(backgroundService);
    }
  }

  /// 构建封面渐变背景（新样式：移动端顶部封面，向下渐变）
  Widget _buildCoverGradientBackground(SongDetail? song, Track? track) {
    final imageUrl = song?.pic ?? track?.picUrl ?? '';
    
    return ValueListenableBuilder<Color?>(
      valueListenable: PlayerService().themeColorNotifier,
      builder: (context, themeColor, child) {
        // 确保总是有颜色显示，优先使用提取的主题色，回退到深紫色
        final color = themeColor ?? Colors.grey[700]!;
        
         return Stack(
           children: [
             // 底层纯主题色背景
             Positioned.fill(
               child: AnimatedContainer(
                 duration: const Duration(milliseconds: 500),
                 color: color,  // 整个背景使用主题色
               ),
             ),
             
             // 专辑封面层 - 等比例放大至占满宽度，位于顶部，带渐变融合效果
             if (imageUrl.isNotEmpty)
               Positioned(
                 left: 0,
                 right: 0,
                 top: 0,
                 child: AspectRatio(
                   aspectRatio: 1.0, // 保持正方形比例
                   child: Stack(
                     children: [
                       // 封面图片
                       CachedNetworkImage(
                         imageUrl: imageUrl,
                         fit: BoxFit.cover,
                         placeholder: (context, url) => Container(
                           color: Colors.grey[900],
                         ),
                         errorWidget: (context, url, error) => Container(
                           color: Colors.grey[900],
                         ),
                       ),
                       // 封面底部渐变遮罩 - 提前开始渐变，避免突兀过渡
                       Positioned.fill(
                         child: AnimatedContainer(
                           duration: const Duration(milliseconds: 500),
                           decoration: BoxDecoration(
                             gradient: LinearGradient(
                               begin: Alignment.topCenter,
                               end: Alignment.bottomCenter,
                               colors: [
                                 Colors.transparent,           // 顶部完全透明，显示原封面
                                 Colors.transparent,           // 上1/4保持透明
                                 color.withOpacity(0.05),     // 提前开始轻微融合
                                 color.withOpacity(0.12),     // 渐进增加透明度
                                 color.withOpacity(0.25),     // 四分之一透明度
                                 color.withOpacity(0.45),     // 接近一半透明度
                                 color.withOpacity(0.65),     // 较强融合
                                 color.withOpacity(0.85),     // 非常强的融合
                                 color,                       // 最底部完全融入主题色
                               ],
                               stops: const [0.0, 0.25, 0.35, 0.45, 0.55, 0.65, 0.75, 0.90, 1.0],
                             ),
                           ),
                         ),
                       ),
                     ],
                   ),
                 ),
               ),
           ],
         );
      },
    );
  }

  /// 构建颜色渐变背景（原有样式）
  Widget _buildColorGradientBackground() {
    return ValueListenableBuilder<Color?>(
      valueListenable: PlayerService().themeColorNotifier,
      builder: (context, themeColor, child) {
        // 使用提取的主题色，回退到深紫色
        final color = themeColor ?? Colors.grey[700]!;
        
        return Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                color.withOpacity(0.3),
                Colors.black,
                Colors.black,
              ],
            ),
          ),
        );
      },
    );
  }

  /// 构建纯色背景
  Widget _buildSolidColorBackground(PlayerBackgroundService backgroundService) {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            backgroundService.solidColor,
            Colors.grey[900]!,
            Colors.black,
          ],
        ),
      ),
    );
  }

  /// 构建图片背景
  Widget _buildImageBackground(PlayerBackgroundService backgroundService) {
    if (backgroundService.mediaPath != null) {
      final mediaFile = File(backgroundService.mediaPath!);
      if (mediaFile.existsSync()) {
        // 性能优化：RepaintBoundary 隔离重绘区域
        return RepaintBoundary(
          child: Stack(
            children: [
              // 图片层
              Positioned.fill(
                child: Image.file(
                  mediaFile,
                  fit: BoxFit.cover,
                  // 性能优化：限制解码尺寸，避免大图片阻塞主线程
                  cacheWidth: 1920,
                  cacheHeight: 1080,
                  isAntiAlias: true,
                  filterQuality: FilterQuality.medium,
                ),
              ),
              // 模糊层（性能优化：限制模糊程度避免GPU过载）
              if (backgroundService.blurAmount > 0 && backgroundService.blurAmount <= 40)
                Positioned.fill(
                  child: BackdropFilter(
                    filter: ImageFilter.blur(
                      sigmaX: backgroundService.blurAmount,
                      sigmaY: backgroundService.blurAmount,
                    ),
                    child: Container(
                      color: Colors.black.withOpacity(0.3), // 添加半透明遮罩
                    ),
                  ),
                )
              else if (backgroundService.blurAmount == 0)
                // 无模糊时也添加浅色遮罩以确保文字可读
                Positioned.fill(
                  child: Container(
                    color: Colors.black.withOpacity(0.2),
                  ),
                ),
            ],
          ),
        );
      }
    }
    
    // 如果没有设置图片，使用默认背景
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Colors.grey[900]!,
            Colors.black,
            Colors.black,
          ],
        ),
      ),
    );
  }
  
  /// 构建视频背景
  Widget _buildVideoBackground(PlayerBackgroundService backgroundService) {
    if (backgroundService.mediaPath != null) {
      final mediaFile = File(backgroundService.mediaPath!);
      if (mediaFile.existsSync()) {
        return Stack(
          children: [
            // 视频层
            Positioned.fill(
              child: VideoBackgroundPlayer(
                videoPath: backgroundService.mediaPath!,
                blurAmount: backgroundService.blurAmount,
                opacity: 1.0,
              ),
            ),
            // 半透明遮罩确保文字可读
            if (backgroundService.blurAmount == 0)
              Positioned.fill(
                child: Container(
                  color: Colors.black.withOpacity(0.2),
                ),
              ),
          ],
        );
      }
    }
    
    // 如果没有设置视频，使用默认背景
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Colors.grey[900]!,
            Colors.black,
            Colors.black,
          ],
        ),
      ),
    );
  }
}
