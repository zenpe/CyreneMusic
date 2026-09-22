import '../services/structured_log_service.dart';
import 'dart:io';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

/// 桌面平台视频背景播放器（Windows/macOS/Linux）
/// 使用 media_kit
class VideoBackgroundPlayerDesktop extends StatefulWidget {
  final String videoPath;
  final double blurAmount;
  final double opacity;

  const VideoBackgroundPlayerDesktop({
    super.key,
    required this.videoPath,
    this.blurAmount = 0.0,
    this.opacity = 1.0,
  });

  @override
  State<VideoBackgroundPlayerDesktop> createState() => _VideoBackgroundPlayerDesktopState();
}

class _VideoBackgroundPlayerDesktopState extends State<VideoBackgroundPlayerDesktop> {
  Player? _player;
  VideoController? _controller;
  bool _isInitialized = false;
  bool _hasError = false;

  @override
  void initState() {
    super.initState();
    _initializeVideo();
  }

  @override
  void didUpdateWidget(VideoBackgroundPlayerDesktop oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.videoPath != widget.videoPath) {
      _disposeController();
      _initializeVideo();
    }
  }

  Future<void> _initializeVideo() async {
    try {
      final file = File(widget.videoPath);
      if (!await file.exists()) {
        StructuredLogService.log('❌ [VideoBackground] 视频文件不存在: ${widget.videoPath}');
        setState(() {
          _hasError = true;
        });
        return;
      }

      // 创建播放器实例（配置为背景视频模式）
      _player = Player(
        configuration: const PlayerConfiguration(
          title: 'Background Video',
          ready: null,
        ),
      );
      _controller = VideoController(_player!);

      // 先设置静音和循环，再打开视频
      await _player!.setVolume(0.0);  // 静音
      await _player!.setPlaylistMode(PlaylistMode.loop);  // 循环播放

      // 打开并播放视频
      await _player!.open(Media(widget.videoPath));
      await _player!.play();

      setState(() {
        _isInitialized = true;
        _hasError = false;
      });

      StructuredLogService.log('✅ [VideoBackground] 视频已初始化 (media_kit, 静音模式): ${widget.videoPath}');
    } catch (e) {
      StructuredLogService.log('❌ [VideoBackground] 初始化视频失败: $e');
      setState(() {
        _hasError = true;
      });
    }
  }

  void _disposeController() {
    _player?.dispose();
    _player = null;
    _controller = null;
    _isInitialized = false;
  }

  @override
  void dispose() {
    _disposeController();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_hasError || !_isInitialized || _controller == null) {
      return Container(
        color: Colors.black,
        child: _hasError
            ? const Center(
                child: Icon(
                  Icons.error_outline,
                  color: Colors.white54,
                  size: 48,
                ),
              )
            : const Center(
                child: CircularProgressIndicator(
                  color: Colors.white54,
                ),
              ),
      );
    }

    Widget videoWidget = RepaintBoundary(
      child: Video(
        controller: _controller!,
        fit: BoxFit.cover,
        controls: null,
      ),
    );

    if (widget.blurAmount > 0 || widget.opacity < 1.0) {
      return RepaintBoundary(
        child: Stack(
          fit: StackFit.expand,
          children: [
            videoWidget,
            BackdropFilter(
              filter: ImageFilter.blur(
                sigmaX: widget.blurAmount,
                sigmaY: widget.blurAmount,
              ),
              child: Container(
                color: Colors.black.withValues(alpha: 1 - widget.opacity),
              ),
            ),
          ],
        ),
      );
    }

    return videoWidget;
  }
}

