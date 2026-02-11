import 'dart:async';
import 'dart:ui' as ui;
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:image/image.dart' as img;
import 'package:cached_network_image/cached_network_image.dart';

/// 颜色提取结果
class ColorExtractionResult {
  final Color? vibrantColor;
  final Color? mutedColor;
  final Color? dominantColor;
  final Color? lightVibrantColor;
  final Color? darkVibrantColor;
  final Color? lightMutedColor;
  final Color? darkMutedColor;

  const ColorExtractionResult({
    this.vibrantColor,
    this.mutedColor,
    this.dominantColor,
    this.lightVibrantColor,
    this.darkVibrantColor,
    this.lightMutedColor,
    this.darkMutedColor,
  });

  /// 获取主题色（优先级：vibrant > dominant > muted）
  Color? get themeColor => vibrantColor ?? dominantColor ?? mutedColor;

  /// 获取动态背景所需的色彩合集 (最少 5 个)
  List<Color> get dynamicColors {
    final colors = <Color>[];
    final candidates = [
      vibrantColor,
      mutedColor,
      dominantColor,
      darkVibrantColor,
      lightVibrantColor,
      darkMutedColor,
      lightMutedColor,
    ];

    for (final c in candidates) {
      if (c != null && !colors.contains(c)) {
        colors.add(c);
      }
    }
    
    // 如果色彩不足 5 个，会在 MeshGradientBackground 的逻辑中进行生成/补偿
    // 这里仅保证尽可能多地提供原始色彩
    return colors;
  }
}

/// 颜色提取服务 - 使用 isolate 避免阻塞主线程
class ColorExtractionService {
  static final ColorExtractionService _instance = ColorExtractionService._internal();
  factory ColorExtractionService() => _instance;
  ColorExtractionService._internal();

  // 缓存已提取的颜色
  final Map<String, ColorExtractionResult> _cache = {};
  
  // 正在提取的 URL 集合
  final Set<String> _extractingUrls = {};
  
  // 缓存大小限制
  static const int _maxCacheSize = 50;

  /// 从网络图片 URL 或本地文件路径提取颜色（异步，不阻塞主线程）
  Future<ColorExtractionResult?> extractColorsFromUrl(
    String imageUrl, {
    int sampleSize = 32,
    Duration timeout = const Duration(seconds: 5),
  }) async {
    if (imageUrl.isEmpty) return null;

    // 检查缓存
    if (_cache.containsKey(imageUrl)) {
      return _cache[imageUrl];
    }

    // 检查是否正在提取
    if (_extractingUrls.contains(imageUrl)) {
      // 等待提取完成
      for (int i = 0; i < 50; i++) {
        await Future.delayed(const Duration(milliseconds: 100));
        if (_cache.containsKey(imageUrl)) {
          return _cache[imageUrl];
        }
        if (!_extractingUrls.contains(imageUrl)) {
          break;
        }
      }
      return _cache[imageUrl];
    }

    _extractingUrls.add(imageUrl);

    try {
      Uint8List imageBytes;
      
      // 判断是网络 URL 还是本地文件路径
      final isNetwork = imageUrl.startsWith('http://') || imageUrl.startsWith('https://');
      
      if (isNetwork) {
        // 1. 下载网络图片数据（在主线程，但使用 http 异步）
        final response = await http.get(Uri.parse(imageUrl)).timeout(timeout);
        if (response.statusCode != 200) {
          debugPrint('⚠️ [ColorExtraction] 图片下载失败: ${response.statusCode}');
          return null;
        }
        imageBytes = response.bodyBytes;
      } else {
        // 本地文件：直接读取文件字节
        final file = File(imageUrl);
        if (!await file.exists()) {
          debugPrint('⚠️ [ColorExtraction] 本地文件不存在: $imageUrl');
          return null;
        }
        imageBytes = await file.readAsBytes();
      }

      // 2. 在 isolate 中解码图片并提取颜色（使用纯 Dart 的 image 包）
      final result = await compute(
        _extractColorsInIsolate,
        _ColorExtractionParams(
          imageBytes: imageBytes,
          sampleSize: sampleSize,
        ),
      );

      if (result != null) {
        // 缓存结果
        _cacheResult(imageUrl, result);
      }

      return result;
    } on TimeoutException {
      debugPrint('⏱️ [ColorExtraction] 图片下载超时: $imageUrl');
      return null;
    } catch (e) {
      debugPrint('⚠️ [ColorExtraction] 颜色提取失败: $e');
      return null;
    } finally {
      _extractingUrls.remove(imageUrl);
    }
  }

  /// 从图片的特定区域提取颜色（异步，不阻塞主线程）
  /// 特别适用于移动端从封面底部提取主题色的场景
  Future<ColorExtractionResult?> extractColorsFromRegion(
    String imageUrl, {
    required Rect region,
    int sampleSize = 32,
    Duration timeout = const Duration(seconds: 5),
  }) async {
    if (imageUrl.isEmpty) return null;

    final cacheKey = '${imageUrl}_region_${region.left}_${region.top}_${region.width}_${region.height}';
    
    // 检查缓存
    if (_cache.containsKey(cacheKey)) {
      return _cache[cacheKey];
    }

    try {
      Uint8List imageBytes;
      
      // 判断是网络 URL 还是本地文件路径
      final isNetwork = imageUrl.startsWith('http://') || imageUrl.startsWith('https://');
      
      if (isNetwork) {
        // 尝试从 CachedNetworkImageProvider 获取已加载的图片，避免重新下载
        // 这对于已经显示的封面非常有效
        final result = await extractColorsFromCachedImage(
          imageUrl, 
          sampleSize: sampleSize, 
          timeout: timeout,
          region: region,
        );
        if (result != null) return result;

        // 如果缓存获取失败，降级到下载
        final response = await http.get(Uri.parse(imageUrl)).timeout(timeout);
        if (response.statusCode != 200) return null;
        imageBytes = response.bodyBytes;
      } else {
        final file = File(imageUrl);
        if (!await file.exists()) return null;
        imageBytes = await file.readAsBytes();
      }

      // 在 isolate 中处理（裁剪 + 缩放 + 提取）
      final result = await compute(
        _extractColorsInIsolate,
        _ColorExtractionParams(
          imageBytes: imageBytes,
          sampleSize: sampleSize,
          region: region,
        ),
      );

      if (result != null) {
        _cacheResult(cacheKey, result);
      }

      return result;
    } catch (e) {
      debugPrint('⚠️ [ColorExtraction] 区域颜色提取失败: $e');
      return null;
    }
  }

  /// 缓存结果
  void _cacheResult(String url, ColorExtractionResult result) {
    // 限制缓存大小
    if (_cache.length >= _maxCacheSize) {
      final keysToRemove = _cache.keys.take(_cache.length - _maxCacheSize + 1).toList();
      for (final key in keysToRemove) {
        _cache.remove(key);
      }
    }
    _cache[url] = result;
  }

  /// 获取缓存的颜色
  ColorExtractionResult? getCachedColors(String imageUrl) {
    return _cache[imageUrl];
  }

  /// 清除缓存
  void clearCache() {
    _cache.clear();
  }

  /// 从已缓存的网络图片提取颜色（利用 CachedNetworkImageProvider 的缓存机制）
  /// 这避免了重复下载图片，特别适合预加载场景
  Future<ColorExtractionResult?> extractColorsFromCachedImage(
    String imageUrl, {
    int sampleSize = 32,
    Duration timeout = const Duration(seconds: 3),
    Rect? region,
  }) async {
    if (imageUrl.isEmpty) return null;

    final cacheKey = region == null 
        ? imageUrl 
        : '${imageUrl}_region_${region.left}_${region.top}_${region.width}_${region.height}';

    // 1. 检查颜色缓存
    if (_cache.containsKey(cacheKey)) {
      return _cache[cacheKey];
    }

    // 判断是否是网络 URL
    final isNetwork = imageUrl.startsWith('http://') || imageUrl.startsWith('https://');
    if (!isNetwork) {
      // 本地文件直接使用原方法
      return extractColorsFromUrl(imageUrl, sampleSize: sampleSize, timeout: timeout);
    }

    try {
      // 2. 使用 CachedNetworkImageProvider 获取图片（会自动使用缓存）
      final provider = CachedNetworkImageProvider(imageUrl);
      final imageInfo = await _loadImageFromProvider(provider, timeout);
      
      if (imageInfo != null) {
        // 🔧 性能优化：使用 rawRgba 格式避免主线程 PNG 编码，速度快数倍
        final byteData = await imageInfo.image.toByteData(format: ui.ImageByteFormat.rawRgba);
        if (byteData == null) {
          debugPrint('⚠️ [ColorExtraction] 无法转换图片为字节数据');
          return null;
        }

        final imageBytes = byteData.buffer.asUint8List();
        final imageWidth = imageInfo.image.width;
        final imageHeight = imageInfo.image.height;
        debugPrint('🎨 [ColorExtraction] 从 ImageProvider 提取颜色 (${imageWidth}x${imageHeight}, ${imageBytes.length} bytes RGBA)');

        final result = await compute(
          _extractColorsInIsolate,
          _ColorExtractionParams(
            imageBytes: imageBytes,
            sampleSize: sampleSize,
            region: region,
            rawRgbaWidth: imageWidth,
            rawRgbaHeight: imageHeight,
          ),
        );

        if (result != null) {
          _cacheResult(cacheKey, result);
        }
        return result;
      } else {
        debugPrint('⚠️ [ColorExtraction] 无法加载图片: $imageUrl');
        return null;
      }
    } on TimeoutException {
      debugPrint('⏱️ [ColorExtraction] 加载图片超时: $imageUrl');
      return null;
    } catch (e) {
      debugPrint('⚠️ [ColorExtraction] 从 ImageProvider 提取颜色失败: $e');
      return null;
    }
  }

  /// 从 ImageProvider 加载图片
  Future<ImageInfo?> _loadImageFromProvider(ImageProvider provider, Duration timeout) async {
    final completer = Completer<ImageInfo?>();
    
    final stream = provider.resolve(const ImageConfiguration());
    late ImageStreamListener listener;
    
    listener = ImageStreamListener(
      (image, synchronousCall) {
        if (!completer.isCompleted) {
          completer.complete(image);
        }
        stream.removeListener(listener);
      },
      onError: (exception, stackTrace) {
        if (!completer.isCompleted) {
          completer.complete(null);
        }
        stream.removeListener(listener);
      },
    );
    
    stream.addListener(listener);
    
    // 添加超时
    return completer.future.timeout(
      timeout,
      onTimeout: () {
        stream.removeListener(listener);
        return null;
      },
    );
  }
}

/// isolate 参数
class _ColorExtractionParams {
  final Uint8List imageBytes;
  final int sampleSize;
  final Rect? region;
  /// 当数据为 rawRgba 格式时的图片宽度（非空表示 RGBA 原始数据）
  final int? rawRgbaWidth;
  /// 当数据为 rawRgba 格式时的图片高度
  final int? rawRgbaHeight;

  const _ColorExtractionParams({
    required this.imageBytes,
    required this.sampleSize,
    this.region,
    this.rawRgbaWidth,
    this.rawRgbaHeight,
  });
}

/// 在 isolate 中执行的颜色提取函数
/// 使用纯 Dart 的 image 包，可以安全地在 isolate 中运行
ColorExtractionResult? _extractColorsInIsolate(_ColorExtractionParams params) {
  try {
    img.Image? image;

    // 🔧 性能优化：支持 rawRgba 格式，直接从像素数据构建图片，避免 PNG 解码开销
    if (params.rawRgbaWidth != null && params.rawRgbaHeight != null) {
      image = img.Image.fromBytes(
        width: params.rawRgbaWidth!,
        height: params.rawRgbaHeight!,
        bytes: params.imageBytes.buffer,
        numChannels: 4,
        order: img.ChannelOrder.rgba,
      );
    } else {
      // 使用 image 包解码图片（纯 Dart，可在 isolate 中运行）
      image = img.decodeImage(params.imageBytes);
    }
    if (image == null) {
      return null;
    }

    // 如果指定了区域，先进行裁剪
    if (params.region != null) {
      final r = params.region!;
      image = img.copyCrop(
        image,
        x: r.left.toInt(),
        y: r.top.toInt(),
        width: r.width.toInt(),
        height: r.height.toInt(),
      );
    }

    // 缩放图片以提高性能
    final resized = img.copyResize(
      image,
      width: params.sampleSize,
      height: params.sampleSize,
      interpolation: img.Interpolation.average,
    );

    final width = resized.width;
    final height = resized.height;

    // 提取颜色
    final colorCounts = <int, int>{};
    final vibrantCandidates = <int, int>{};
    final mutedCandidates = <int, int>{};

    for (int y = 0; y < height; y++) {
      for (int x = 0; x < width; x++) {
        final pixel = resized.getPixel(x, y);
        final r = pixel.r.toInt();
        final g = pixel.g.toInt();
        final b = pixel.b.toInt();
        final a = pixel.a.toInt();

        if (a < 128) continue; // 跳过透明像素

        // 量化颜色以减少颜色数量（使用较小的步长以提高精度）
        final quantizedR = (r ~/ 8) * 8;
        final quantizedG = (g ~/ 8) * 8;
        final quantizedB = (b ~/ 8) * 8;
        final colorValue = (255 << 24) | (quantizedR << 16) | (quantizedG << 8) | quantizedB;

        colorCounts[colorValue] = (colorCounts[colorValue] ?? 0) + 1;

        // 计算饱和度和亮度
        final maxVal = [r, g, b].reduce((a, b) => a > b ? a : b);
        final minVal = [r, g, b].reduce((a, b) => a < b ? a : b);
        final lightness = (maxVal + minVal) / 2 / 255;
        final saturation = maxVal == minVal 
            ? 0.0 
            : (maxVal - minVal) / (255 - (2 * lightness * 255 - 255).abs());

        // 分类颜色
        if (saturation > 0.35 && lightness > 0.2 && lightness < 0.8) {
          vibrantCandidates[colorValue] = (vibrantCandidates[colorValue] ?? 0) + 1;
        } else if (saturation < 0.35 && lightness > 0.2 && lightness < 0.8) {
          mutedCandidates[colorValue] = (mutedCandidates[colorValue] ?? 0) + 1;
        }
      }
    }

    // 找出最常见的颜色
    int? dominantColorValue;
    int? vibrantColorValue;
    int? mutedColorValue;
    int? lightVibrantColorValue;
    int? darkVibrantColorValue;
    int? lightMutedColorValue;
    int? darkMutedColorValue;

    if (colorCounts.isNotEmpty) {
      final sortedColors = colorCounts.entries.toList()
        ..sort((a, b) => b.value.compareTo(a.value));
      dominantColorValue = sortedColors.first.key;
    }

    if (vibrantCandidates.isNotEmpty) {
      final sortedVibrant = vibrantCandidates.entries.toList()
        ..sort((a, b) => b.value.compareTo(a.value));
      vibrantColorValue = sortedVibrant.first.key;
      
      // 找 light 和 dark vibrant
      for (final entry in sortedVibrant) {
        final colorVal = entry.key;
        final lightness = _getLightnessFromValue(colorVal);
        if (lightness > 0.6 && lightVibrantColorValue == null) {
          lightVibrantColorValue = colorVal;
        } else if (lightness < 0.4 && darkVibrantColorValue == null) {
          darkVibrantColorValue = colorVal;
        }
        if (lightVibrantColorValue != null && darkVibrantColorValue != null) break;
      }
    }

    if (mutedCandidates.isNotEmpty) {
      final sortedMuted = mutedCandidates.entries.toList()
        ..sort((a, b) => b.value.compareTo(a.value));
      mutedColorValue = sortedMuted.first.key;
      
      // 找 light 和 dark muted
      for (final entry in sortedMuted) {
        final colorVal = entry.key;
        final lightness = _getLightnessFromValue(colorVal);
        if (lightness > 0.6 && lightMutedColorValue == null) {
          lightMutedColorValue = colorVal;
        } else if (lightness < 0.4 && darkMutedColorValue == null) {
          darkMutedColorValue = colorVal;
        }
        if (lightMutedColorValue != null && darkMutedColorValue != null) break;
      }
    }

    return ColorExtractionResult(
      vibrantColor: vibrantColorValue != null ? Color(vibrantColorValue) : null,
      mutedColor: mutedColorValue != null ? Color(mutedColorValue) : null,
      dominantColor: dominantColorValue != null ? Color(dominantColorValue) : null,
      lightVibrantColor: lightVibrantColorValue != null ? Color(lightVibrantColorValue) : null,
      darkVibrantColor: darkVibrantColorValue != null ? Color(darkVibrantColorValue) : null,
      lightMutedColor: lightMutedColorValue != null ? Color(lightMutedColorValue) : null,
      darkMutedColor: darkMutedColorValue != null ? Color(darkMutedColorValue) : null,
    );
  } catch (e) {
    // 在 isolate 中不能使用 debugPrint，直接返回 null
    return null;
  }
}

/// 从颜色值计算亮度
double _getLightnessFromValue(int colorValue) {
  final r = (colorValue >> 16) & 0xFF;
  final g = (colorValue >> 8) & 0xFF;
  final b = colorValue & 0xFF;
  final maxVal = [r, g, b].reduce((a, b) => a > b ? a : b);
  final minVal = [r, g, b].reduce((a, b) => a < b ? a : b);
  return (maxVal + minVal) / 2 / 255;
}
