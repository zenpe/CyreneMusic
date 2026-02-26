import 'dart:io';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../services/player_background_service.dart';
import '../../services/player_service.dart';
import '../../services/color_extraction_service.dart';
import '../../widgets/video_background_player.dart';
import '../../widgets/flowing_light_background.dart';

/// 动态背景颜色缓存管理器（全局单例）
/// 现在使用 ColorExtractionService 的缓存，这里只保留接口兼容
class _DynamicColorCache {
  static final _DynamicColorCache _instance = _DynamicColorCache._internal();
  factory _DynamicColorCache() => _instance;
  _DynamicColorCache._internal();

  List<Color>? getColors(String imageUrl) {
    final result = ColorExtractionService().getCachedColors(imageUrl);
    return result?.dynamicColors;
  }
}

/// 流体云播放器专用背景组件
/// 
/// 自适应模式下的行为：
/// - 开启封面渐变：显示专辑封面到主题色的渐变效果
/// - 关闭封面渐变：显示专辑封面 100% 填充（保持长宽比）
/// - 动态背景：基于封面提取3个颜色的动态渐变动画
/// - 用户仍可自定义纯色、视频或图片背景
class PlayerFluidCloudBackground extends StatefulWidget {
  const PlayerFluidCloudBackground({super.key});

  @override
  State<PlayerFluidCloudBackground> createState() => _PlayerFluidCloudBackgroundState();
}

class _PlayerFluidCloudBackgroundState extends State<PlayerFluidCloudBackground> {
  // 动态背景颜色
  String? _currentImageUrl;
  bool _isFirstBuild = true;
  
  // 防抖计时器
  int _pendingExtractionId = 0;
  
  // 记录最后一次调度的图片URL，防止PlayerService频繁通知（如进度更新）导致防抖计时器不断重置
  String? _lastScheduledImageUrl;

  @override
  void initState() {
    super.initState();
    // 只监听背景设置变化，不监听 PlayerService（避免频繁触发）
    PlayerBackgroundService().addListener(_onBackgroundChanged);
    
    // 监听 PlayerService 以获取歌曲变化
    // 注意：PlayerService 会发送进度更新等频繁通知，所以在处理时必须进行过滤
    PlayerService().addListener(_onPlayerServiceChanged);
  }

  @override
  void dispose() {
    PlayerBackgroundService().removeListener(_onBackgroundChanged);
    PlayerService().removeListener(_onPlayerServiceChanged);
    super.dispose();
  }

  void _onPlayerServiceChanged() {
    if (mounted && PlayerBackgroundService().backgroundType == PlayerBackgroundType.dynamic) {
      // 尝试调度颜色提取
      // _scheduleColorExtraction 内部会处理去重，避免频繁的进度更新导致重复计算
      // _scheduleColorExtraction();
    }
  }

  void _onBackgroundChanged() {
    if (mounted) {
      setState(() {});
      if (PlayerBackgroundService().backgroundType == PlayerBackgroundType.dynamic) {
      // _scheduleColorExtraction();
      }
    }
  }

  /// 延迟调度颜色提取（带防抖）
  void _scheduleColorExtraction() {
    final backgroundService = PlayerBackgroundService();
    if (backgroundService.backgroundType != PlayerBackgroundType.dynamic) {
      return;
    }

    final imageUrl = PlayerService().currentCoverUrl ?? '';

    // 1. 如果没有图片，或者当前已经在显示这张图片的颜色，直接返回
    if (imageUrl.isEmpty || imageUrl == _currentImageUrl) return;

    // 2. 如果已经调度了这张图片的提取任务（正在防抖等待中），直接返回
    // 这一步至关重要，因为PlayerService的进度更新频率很高（每秒多次）
    // 如果不加这个检查，每次进度更新都会重置防抖计时器，导致永远无法触发提取
    if (imageUrl == _lastScheduledImageUrl) return;

    // 记录这次调度的URL
    _lastScheduledImageUrl = imageUrl;

    // 检查缓存 - 如果有缓存立即使用
    final cachedColors = _DynamicColorCache().getColors(imageUrl);
    if (cachedColors != null) {
      _currentImageUrl = imageUrl;
      if (mounted) {
        setState(() {
        });
      }
      return;
    }

    // 防抖：取消之前的提取请求
    _pendingExtractionId++;
    final currentId = _pendingExtractionId;

    // 延迟200ms后提取（使用 isolate 后可以更快触发）
    Future.delayed(const Duration(milliseconds: 200), () {
      // 如果ID不匹配，说明有新的请求，取消当前请求
      if (currentId != _pendingExtractionId || !mounted) return;
      _extractColorsFromImage(imageUrl);
    });
  }

  /// 从图片中提取颜色（使用 isolate，不阻塞主线程）
  Future<void> _extractColorsFromImage(String imageUrl) async {
    // 再次检查缓存（可能在等待期间已经被其他地方提取）
    final cachedColors = _DynamicColorCache().getColors(imageUrl);
    if (cachedColors != null) {
      _currentImageUrl = imageUrl;
      if (mounted) {
      }
      return;
    }
    
    _currentImageUrl = imageUrl;

    try {
      // 使用 ColorExtractionService 在 isolate 中提取颜色
      final result = await ColorExtractionService().extractColorsFromUrl(
        imageUrl,
        sampleSize: 64, // 增加采样尺寸以提升准确率
        timeout: const Duration(seconds: 3),
      );

      if (result != null && mounted && _currentImageUrl == imageUrl) {
        setState(() {
        });
      }
    } catch (e) {
      // 静默失败，保持当前颜色
      debugPrint('⚠️ [FluidCloudBackground] 颜色提取失败: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    // 首次构建时，延迟调度颜色提取
    if (_isFirstBuild) {
      _isFirstBuild = false;
      WidgetsBinding.instance.addPostFrameCallback((_) {
      // _scheduleColorExtraction();
      });
    }
    return _buildBackground();
  }

  /// 构建背景（根据设置选择背景类型）
  Widget _buildBackground() {
    final backgroundService = PlayerBackgroundService();
    final greyColor = Colors.grey[900] ?? const Color(0xFF212121);
    
    switch (backgroundService.backgroundType) {
      case PlayerBackgroundType.adaptive:
        // 自适应模式：专辑封面在左侧，向右渐变到主题色
        return _buildAdaptiveBackground(greyColor);
        
      case PlayerBackgroundType.solidColor:
        // 纯色背景
        return _buildSolidColorBackground(backgroundService, greyColor);
        
      case PlayerBackgroundType.image:
        // 图片背景
        return _buildImageBackground(backgroundService, greyColor);
        
      case PlayerBackgroundType.video:
        // 视频背景
        return _buildVideoBackground(backgroundService, greyColor);
        
      case PlayerBackgroundType.dynamic:
        // 动态背景
        return _buildDynamicBackground(greyColor);
    }
  }

  /// 构建动态背景（新版流体云效果）
  Widget _buildDynamicBackground(Color greyColor) {
    // 使用 ListenableBuilder 监听 PlayerService，确保歌曲切换时封面也会更新
    return ListenableBuilder(
      listenable: PlayerService(),
      builder: (context, _) {
        // 获取当前封面图片的 Provider
        final player = PlayerService();
        // 优先使用缓存的 Provider
        ImageProvider? imageProvider = player.currentCoverImageProvider;
        
        // 如果没有 Provider，尝试从 URL 构建
        if (imageProvider == null) {
            final song = player.currentSong;
            final track = player.currentTrack;
            final imageUrl = song?.pic ?? track?.picUrl;
            
            if (imageUrl != null && imageUrl.isNotEmpty) {
               if (imageUrl.startsWith('http')) {
                 imageProvider = CachedNetworkImageProvider(imageUrl);
               } else {
                 imageProvider = FileImage(File(imageUrl));
               }
            }
        }

        return RepaintBoundary(
          child: FlowingLightBackground(
            imageProvider: imageProvider,
            useDesktopProcessing: true,
            // 使用与移动端一致的半透明遮罩
            child: Container(color: Colors.black.withOpacity(0.15)), 
          ),
        );
      },
    );
  }

  /// 构建自适应背景
  /// 专辑封面在左侧，渐变过渡到右侧的主题色
  Widget _buildAdaptiveBackground(Color greyColor) {
    // 使用 ListenableBuilder 监听 PlayerService，确保歌曲切换时封面也会更新
    return ListenableBuilder(
      listenable: PlayerService(),
      builder: (context, _) {
        final song = PlayerService().currentSong;
        final track = PlayerService().currentTrack;
        final imageUrl = song?.pic ?? track?.picUrl ?? '';
        
        return ValueListenableBuilder<Color?>(
          valueListenable: PlayerService().themeColorNotifier,
          builder: (context, themeColor, child) {
            final color = themeColor ?? Colors.grey[700]!;
            
            return RepaintBoundary(
              child: Stack(
                children: [
                  // 底层纯主题色背景
                  Positioned.fill(
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 500),
                      color: color,
                    ),
                  ),
                  
                  // 专辑封面层 - 等比例放大至占满高度，位于左侧
                  if (imageUrl.isNotEmpty)
                    Positioned(
                      left: 0,
                      top: 0,
                      bottom: 0,
                      child: AspectRatio(
                        aspectRatio: 1.2, // 稍微加宽一点比例 (1.1 -> 1.2)
                        child: Stack(
                          children: [
                            // 封面图片（支持网络 URL 和本地文件）
                            _buildCoverImage(imageUrl, greyColor),
                            // 封面右侧渐变遮罩 - 让封面边缘自然融入背景
                            Positioned.fill(
                              child: AnimatedContainer(
                                duration: const Duration(milliseconds: 500),
                                decoration: BoxDecoration(
                                  gradient: LinearGradient(
                                    begin: Alignment.centerLeft,
                                    end: Alignment.centerRight,
                                    colors: [
                                      Colors.transparent,  // 左侧和中间保持透明，显示封面
                                      Colors.transparent,
                                      color.withOpacity(0.3),  // 右侧开始融合主题色
                                      color.withOpacity(0.9),  // 最右侧更多主题色
                                    ],
                                    stops: const [0.0, 0.5, 0.8, 1.0], // 调整渐变点，显示更多封面
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  
                  // 渐变遮罩层 - 从封面到主题色的丝滑渐变
                  Positioned.fill(
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 500),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.centerLeft,
                          end: Alignment.centerRight,
                          colors: [
                            Colors.transparent,        // 左侧完全透明
                            color.withOpacity(0.2),    // 开始融合
                            color.withOpacity(0.8),   // 主题色更明显
                            color,                      // 右侧完全不透明的主题色
                          ],
                          stops: const [0.0, 0.4, 0.7, 0.9],  // 调整渐变，让左侧更清晰
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }



  /// 构建默认背景（无封面时使用）
  Widget _buildDefaultBackground(Color greyColor) {
    return RepaintBoundary(
      child: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              greyColor,
              Color.lerp(greyColor, Colors.black, 0.5)!,
              Colors.black,
            ],
            stops: const [0.0, 0.5, 1.0],
          ),
        ),
      ),
    );
  }

  Widget _buildCoverImage(String imageUrl, Color greyColor, {bool fullCover = false}) {
    // 性能优化：优先使用 PlayerService 已经稳定的 Provider
    final player = PlayerService();
    if (player.currentCoverUrl == imageUrl && player.currentCoverImageProvider != null) {
      return Image(
        image: player.currentCoverImageProvider!,
        fit: BoxFit.cover,
        width: fullCover ? double.infinity : null,
        height: fullCover ? double.infinity : null,
        filterQuality: FilterQuality.medium,
      );
    }

    // 判断是网络 URL 还是本地文件路径
    final isNetwork = imageUrl.startsWith('http://') || imageUrl.startsWith('https://');
    
    if (isNetwork) {
      return CachedNetworkImage(
        imageUrl: imageUrl,
        fit: BoxFit.cover,
        width: fullCover ? double.infinity : null,
        height: fullCover ? double.infinity : null,
        memCacheWidth: fullCover ? 1920 : 1024,
        memCacheHeight: fullCover ? 1080 : 1024,
        filterQuality: FilterQuality.medium,
        placeholder: (context, url) => fullCover 
            ? _buildDefaultBackground(greyColor) 
            : Container(color: greyColor),
        errorWidget: (context, url, error) => fullCover 
            ? _buildDefaultBackground(greyColor) 
            : Container(color: greyColor),
      );
    } else {
      // 本地文件
      return Image.file(
        File(imageUrl),
        fit: BoxFit.cover,
        width: fullCover ? double.infinity : null,
        height: fullCover ? double.infinity : null,
        cacheWidth: fullCover ? 1920 : 1024,
        cacheHeight: fullCover ? 1080 : 1024,
        filterQuality: FilterQuality.medium,
        errorBuilder: (context, error, stackTrace) => fullCover 
            ? _buildDefaultBackground(greyColor) 
            : Container(color: greyColor),
      );
    }
  }

  /// 构建纯色背景
  Widget _buildSolidColorBackground(PlayerBackgroundService backgroundService, Color greyColor) {
    final topColor = backgroundService.solidColor;
    
    return RepaintBoundary(
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 500),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            // 增加插值点以提高精度
            colors: [
              topColor,
              Color.lerp(topColor, greyColor, 0.25)!,
              Color.lerp(topColor, greyColor, 0.5)!,
              Color.lerp(topColor, greyColor, 0.75)!,
              greyColor,
            ],
            stops: const [0.0, 0.25, 0.5, 0.75, 1.0],
          ),
        ),
      ),
    );
  }

  /// 构建图片背景
  Widget _buildImageBackground(PlayerBackgroundService backgroundService, Color greyColor) {
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
    return _buildDefaultBackground(greyColor);
  }
  
  /// 构建视频背景
  Widget _buildVideoBackground(PlayerBackgroundService backgroundService, Color greyColor) {
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
    return _buildDefaultBackground(greyColor);
  }
}
