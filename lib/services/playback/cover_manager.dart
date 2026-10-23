import '../structured_log_service.dart';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';

import '../color_extraction_service.dart';
import '../player_background_service.dart';
import '../../utils/image_utils.dart';
import '../../utils/image_stream_utils.dart';
import 'dart:async';

/// 封面管理器
/// 从 PlayerService 提取的封面加载、缓存、主题色提取逻辑
class CoverManager extends ChangeNotifier {
  ImageProvider? _currentCover;
  String? _currentUrl;
  final Map<String, Color> _themeColorCache = {};
  final ValueNotifier<Color?> themeColorNotifier = ValueNotifier<Color?>(null);
  int _coverRequestId = 0;
  int _themeRequestId = 0;
  bool _disposed = false;

  ImageProvider? get currentCover => _currentCover;
  String? get currentUrl => _currentUrl;

  /// 设置封面（由外部直接提供 provider）
  void setCover(ImageProvider? provider, {String? url, bool notify = true}) {
    if (_disposed) return;
    _currentCover = provider;
    if (provider == null) {
      _currentUrl = null;
    } else if (provider is CachedNetworkImageProvider) {
      _currentUrl = url ?? provider.url;
    } else {
      _currentUrl = url;
    }
    if (notify) notifyListeners();
  }

  /// 直接设置封面，并使之前未完成的封面请求失效。
  void setCoverImmediate(
    ImageProvider? provider, {
    String? url,
    bool notify = true,
  }) {
    if (_disposed) return;
    _coverRequestId++;
    setCover(provider, url: url, notify: notify);
  }

  /// 从 URL 更新封面
  Future<void> updateCover(
    String? imageUrl, {
    bool notify = true,
    bool force = false,
    bool warmUp = true,
  }) async {
    if (_disposed) return;
    final requestId = ++_coverRequestId;
    if (imageUrl == null || imageUrl.isEmpty) {
      if (requestId == _coverRequestId && _currentCover != null) {
        setCover(null, notify: notify);
      }
      return;
    }

    // 如果没有 force 且已有 provider，且 URL 匹配，则跳过
    if (!force && _currentCover != null && _currentUrl != null) {
      if (_currentUrl == imageUrl) return;
      // 保守策略：如果已有 provider 且非 force，不覆盖
      return;
    }

    try {
      final provider = await _createProvider(imageUrl);
      if (_disposed || requestId != _coverRequestId) return;
      if (provider == null) {
        if (requestId == _coverRequestId) {
          setCover(null, notify: notify);
        }
        return;
      }

      if (warmUp) {
        // 主动监听图片流，拦截 403 等异步加载错误，避免冒泡成全局 FlutterError。
        await _warmUpProvider(provider);
        if (requestId != _coverRequestId) return;
        setCover(provider, url: imageUrl, notify: notify);
        return;
      }

      if (requestId != _coverRequestId) return;
      setCover(provider, url: imageUrl, notify: notify);
      unawaited(
        _warmUpProvider(provider).catchError((error, stackTrace) {
          StructuredLogService.log('[CoverManager] 后台预热封面失败: $error');
          if (requestId == _coverRequestId &&
              _currentUrl == imageUrl &&
              identical(_currentCover, provider)) {
            setCover(null, notify: notify);
          }
        }),
      );
    } catch (e) {
      StructuredLogService.log('[CoverManager] 预加载封面失败: $e');
      if (requestId == _coverRequestId) {
        setCover(null, notify: notify);
      }
    }
  }

  /// 非阻塞更新封面，用于切歌热路径。
  void updateCoverNonBlocking(
    String? imageUrl, {
    bool notify = true,
    bool force = false,
  }) {
    unawaited(
      updateCover(imageUrl, notify: notify, force: force, warmUp: false),
    );
  }

  Future<ImageProvider?> _createProvider(String imageUrl) async {
    final isNetwork =
        imageUrl.startsWith('http://') || imageUrl.startsWith('https://');
    if (isNetwork) {
      return CachedNetworkImageProvider(
        imageUrl,
        headers: getImageHeaders(imageUrl),
      );
    }

    final file = File(imageUrl);
    if (!await file.exists()) {
      return null;
    }
    return FileImage(file);
  }

  Future<void> _warmUpProvider(ImageProvider provider) async {
    final info = await loadFirstImage(
      provider,
      timeout: const Duration(seconds: 5),
    );
    info.dispose();
  }

  void resetThemeColor([Color? fallback]) {
    if (_disposed) return;
    _themeRequestId++;
    themeColorNotifier.value = fallback ?? Colors.grey[700]!;
  }

  /// 后台提取主题色
  Future<void> extractThemeColor(String imageUrl) async {
    if (_disposed) return;
    final requestId = ++_themeRequestId;
    if (imageUrl.isEmpty) {
      if (requestId == _themeRequestId) {
        themeColorNotifier.value = Colors.grey[700]!;
      }
      return;
    }

    try {
      // 检查缓存
      final cachedResult = ColorExtractionService().getCachedColors(imageUrl);
      if (cachedResult != null && cachedResult.themeColor != null) {
        if (requestId == _themeRequestId) {
          themeColorNotifier.value = cachedResult.themeColor!;
        }
        return;
      }

      if (requestId == _themeRequestId) {
        themeColorNotifier.value = Colors.grey[700]!;
      }

      // 跳过后台提取
      final isAppInBackground =
          WidgetsBinding.instance.lifecycleState == AppLifecycleState.paused ||
          WidgetsBinding.instance.lifecycleState == AppLifecycleState.inactive;
      if (isAppInBackground) return;

      final isMobileGradientMode =
          Platform.isAndroid &&
          PlayerBackgroundService().enableGradient &&
          PlayerBackgroundService().backgroundType ==
              PlayerBackgroundType.adaptive;

      Color? themeColor;
      if (isMobileGradientMode) {
        themeColor = await _extractColorFromBottomRegion(imageUrl);
      } else {
        final result = await ColorExtractionService().extractColorsFromUrl(
          imageUrl,
        );
        themeColor = result?.themeColor;
      }

      if (themeColor != null && requestId == _themeRequestId) {
        themeColorNotifier.value = themeColor;
        _themeColorCache[imageUrl] = themeColor;
      }
    } catch (e) {
      StructuredLogService.log('[CoverManager] 主题色提取失败: $e');
    }
  }

  void extractThemeColorNonBlocking(String imageUrl) {
    unawaited(extractThemeColor(imageUrl));
  }

  /// 预缓存下一首封面的主题色
  Future<void> precacheThemeColor(String imageUrl) async {
    if (_disposed) return;
    if (_themeColorCache.containsKey(imageUrl)) return;

    try {
      final result = await ColorExtractionService()
          .extractColorsFromCachedImage(
            imageUrl,
            sampleSize: 64,
            timeout: const Duration(seconds: 3),
          );
      if (!_disposed && result?.themeColor != null) {
        _themeColorCache[imageUrl] = result!.themeColor!;
      }
    } catch (e) {
      StructuredLogService.log('[CoverManager] 预加载主题色异常: $e');
    }
  }

  Future<Color?> _extractColorFromBottomRegion(String imageUrl) async {
    try {
      final ImageProvider imageProvider = imageUrl.startsWith('http')
          ? CachedNetworkImageProvider(
              imageUrl,
              headers: getImageHeaders(imageUrl),
            )
          : FileImage(File(imageUrl));

      final info = await loadFirstImage(
        imageProvider,
        timeout: const Duration(seconds: 3),
      );
      late final Rect region;
      try {
        final image = info.image;
        region = Rect.fromLTWH(
          0,
          image.height * 0.7,
          image.width.toDouble(),
          image.height * 0.3,
        );
      } finally {
        info.dispose();
      }
      if (_disposed) return null;

      final result = await ColorExtractionService().extractColorsFromRegion(
        imageUrl,
        region: region,
        sampleSize: 64,
      );
      return result?.themeColor;
    } catch (e) {
      StructuredLogService.log('[CoverManager] 从底部区域提取颜色失败: $e');
      return null;
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _coverRequestId++;
    _themeRequestId++;
    themeColorNotifier.dispose();
    super.dispose();
  }
}
