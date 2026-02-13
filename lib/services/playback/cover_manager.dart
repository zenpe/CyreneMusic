import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';

import '../color_extraction_service.dart';
import '../player_background_service.dart';
import 'dart:ui' as ui;
import 'dart:async';

/// 封面管理器
/// 从 PlayerService 提取的封面加载、缓存、主题色提取逻辑
class CoverManager extends ChangeNotifier {
  ImageProvider? _currentCover;
  String? _currentUrl;
  final Map<String, Color> _themeColorCache = {};
  final ValueNotifier<Color?> themeColorNotifier = ValueNotifier<Color?>(null);

  ImageProvider? get currentCover => _currentCover;
  String? get currentUrl => _currentUrl;

  /// 设置封面（由外部直接提供 provider）
  void setCover(ImageProvider? provider, {String? url, bool notify = true}) {
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

  /// 从 URL 更新封面
  Future<void> updateCover(String? imageUrl, {bool notify = true, bool force = false}) async {
    if (imageUrl == null || imageUrl.isEmpty) {
      if (_currentCover != null) {
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

    _currentUrl = imageUrl;

    try {
      final isNetwork = imageUrl.startsWith('http://') || imageUrl.startsWith('https://');
      ImageProvider provider;
      if (isNetwork) {
        provider = CachedNetworkImageProvider(imageUrl);
      } else {
        final file = File(imageUrl);
        if (!await file.exists()) {
          setCover(null, notify: notify);
          return;
        }
        provider = FileImage(file);
      }
      // 预热缓存
      provider.resolve(const ImageConfiguration());
      setCover(provider, url: imageUrl, notify: notify);
    } catch (e) {
      print('[CoverManager] 预加载封面失败: $e');
      setCover(null, notify: notify);
    }
  }

  /// 后台提取主题色
  Future<void> extractThemeColor(String imageUrl) async {
    if (imageUrl.isEmpty) {
      themeColorNotifier.value = Colors.grey[700]!;
      return;
    }

    try {
      // 检查缓存
      final cachedResult = ColorExtractionService().getCachedColors(imageUrl);
      if (cachedResult != null && cachedResult.themeColor != null) {
        themeColorNotifier.value = cachedResult.themeColor!;
        return;
      }

      themeColorNotifier.value = Colors.grey[700]!;

      // 跳过后台提取
      final isAppInBackground = WidgetsBinding.instance.lifecycleState == AppLifecycleState.paused ||
          WidgetsBinding.instance.lifecycleState == AppLifecycleState.inactive;
      if (isAppInBackground) return;

      final isMobileGradientMode = Platform.isAndroid &&
          PlayerBackgroundService().enableGradient &&
          PlayerBackgroundService().backgroundType == PlayerBackgroundType.adaptive;

      Color? themeColor;
      if (isMobileGradientMode) {
        themeColor = await _extractColorFromBottomRegion(imageUrl);
      } else {
        final result = await ColorExtractionService().extractColorsFromUrl(imageUrl);
        themeColor = result?.themeColor;
      }

      if (themeColor != null) {
        themeColorNotifier.value = themeColor;
        _themeColorCache[imageUrl] = themeColor;
      }
    } catch (e) {
      print('[CoverManager] 主题色提取失败: $e');
    }
  }

  /// 预缓存下一首封面的主题色
  Future<void> precacheThemeColor(String imageUrl) async {
    if (_themeColorCache.containsKey(imageUrl)) return;

    try {
      final result = await ColorExtractionService().extractColorsFromCachedImage(
        imageUrl,
        sampleSize: 64,
        timeout: const Duration(seconds: 3),
      );
      if (result?.themeColor != null) {
        _themeColorCache[imageUrl] = result!.themeColor!;
      }
    } catch (e) {
      print('[CoverManager] 预加载主题色异常: $e');
    }
  }

  Future<Color?> _extractColorFromBottomRegion(String imageUrl) async {
    try {
      final ImageProvider imageProvider = imageUrl.startsWith('http')
          ? CachedNetworkImageProvider(imageUrl)
          : FileImage(File(imageUrl));

      final Completer<ui.Image> completer = Completer();
      final ImageStream stream = imageProvider.resolve(const ImageConfiguration());
      late ImageStreamListener listener;
      listener = ImageStreamListener((info, _) {
        completer.complete(info.image);
        stream.removeListener(listener);
      }, onError: (e, s) {
        completer.completeError(e, s);
        stream.removeListener(listener);
      });
      stream.addListener(listener);

      final image = await completer.future.timeout(const Duration(seconds: 3));
      final region = Rect.fromLTWH(0, image.height * 0.7, image.width.toDouble(), image.height * 0.3);

      final result = await ColorExtractionService().extractColorsFromRegion(
        imageUrl,
        region: region,
        sampleSize: 64,
      );
      return result?.themeColor;
    } catch (e) {
      print('[CoverManager] 从底部区域提取颜色失败: $e');
      return null;
    }
  }

  @override
  void dispose() {
    themeColorNotifier.dispose();
    super.dispose();
  }
}
