import 'structured_log_service.dart';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:dynamic_color/dynamic_color.dart';

/// 系统主题色服务 - 获取系统级别的主题色
///
/// 支持平台：
/// - Android 12+ (Material You 动态颜色)
/// - Windows 11+ (系统强调色)
/// - 其他平台返回默认颜色
class SystemThemeColorService {
  static final SystemThemeColorService _instance = SystemThemeColorService._internal();
  factory SystemThemeColorService() => _instance;
  SystemThemeColorService._internal();

  /// 获取系统主题色
  ///
  /// 返回值：
  /// - Android 12+: Material You 动态颜色
  /// - Windows: 系统强调色（如果可用）
  /// - 其他: null（表示不支持）
  Future<Color?> getSystemThemeColor(BuildContext context) async {
    try {
      if (Platform.isAndroid) {
        return await _getAndroidDynamicColor(context);
      } else if (Platform.isWindows) {
        return await _getWindowsAccentColor();
      } else {
        StructuredLogService.log('ℹ️ [SystemThemeColor] 当前平台不支持获取系统主题色');
        return null;
      }
    } catch (e) {
      StructuredLogService.log('❌ [SystemThemeColor] 获取系统主题色失败: $e');
      return null;
    }
  }

  /// 获取 Android 动态颜色 (Material You)
  Future<Color?> _getAndroidDynamicColor(BuildContext context) async {
    try {
      StructuredLogService.log('🎨 [SystemThemeColor] 尝试获取 Android 动态颜色...');

      // 使用 dynamic_color 插件获取系统颜色
      final corePalette = await DynamicColorPlugin.getCorePalette();

      if (corePalette != null) {
        // 获取主色调（primary）
        final primaryColor = Color(corePalette.primary.get(40)); // 40 是标准亮度
        StructuredLogService.log('✅ [SystemThemeColor] 获取到 Android 动态颜色: 0x${primaryColor.toARGB32().toRadixString(16)}');
        return primaryColor;
      } else {
        StructuredLogService.log('⚠️ [SystemThemeColor] Android 动态颜色不可用（可能是 Android 12 以下版本）');
        return null;
      }
    } catch (e) {
      StructuredLogService.log('❌ [SystemThemeColor] 获取 Android 动态颜色失败: $e');
      return null;
    }
  }

  /// 获取 Windows 系统强调色
  Future<Color?> _getWindowsAccentColor() async {
    try {
      StructuredLogService.log('🎨 [SystemThemeColor] 尝试获取 Windows 系统强调色...');

      // 首先尝试获取 DWM AccentColor
      try {
        final result = await Process.run(
          'powershell',
          [
            '-Command',
            'Get-ItemProperty -Path "HKCU:\\Software\\Microsoft\\Windows\\DWM" -Name "AccentColor" -ErrorAction SilentlyContinue | Select-Object -ExpandProperty AccentColor'
          ],
        );

        if (result.exitCode == 0 && result.stdout.toString().trim().isNotEmpty) {
          final colorStr = result.stdout.toString().trim();
          final colorValue = int.tryParse(colorStr);

          if (colorValue != null && colorValue > 0) {
            // Windows 存储的是 ABGR 格式，需要转换为 ARGB
            final b = (colorValue >> 16) & 0xFF;
            final g = (colorValue >> 8) & 0xFF;
            final r = colorValue & 0xFF;
            final a = (colorValue >> 24) & 0xFF;

            final argbColor = (a << 24) | (r << 16) | (g << 8) | b;
            final color = Color(argbColor);

            StructuredLogService.log('✅ [SystemThemeColor] 成功获取 AccentColor: 0x${argbColor.toRadixString(16).toUpperCase()}');
            StructuredLogService.log('   原始值 (ABGR): 0x${colorValue.toRadixString(16).toUpperCase()}');
            StructuredLogService.log('   转换后 (ARGB): A=$a, R=$r, G=$g, B=$b');

            return color;
          }
        }
      } catch (e) {
        StructuredLogService.log('⚠️ [SystemThemeColor] AccentColor 获取失败: $e');
      }

      // 如果 AccentColor 获取失败，尝试获取 ColorizationColor
      try {
        final result = await Process.run(
          'powershell',
          [
            '-Command',
            'Get-ItemProperty -Path "HKCU:\\Software\\Microsoft\\Windows\\DWM" -Name "ColorizationColor" -ErrorAction SilentlyContinue | Select-Object -ExpandProperty ColorizationColor'
          ],
        );

        if (result.exitCode == 0 && result.stdout.toString().trim().isNotEmpty) {
          final colorStr = result.stdout.toString().trim();
          final colorValue = int.tryParse(colorStr);

          if (colorValue != null && colorValue > 0) {
            // Windows ColorizationColor 也是 ABGR 格式
            final b = (colorValue >> 16) & 0xFF;
            final g = (colorValue >> 8) & 0xFF;
            final r = colorValue & 0xFF;
            final a = (colorValue >> 24) & 0xFF;

            final argbColor = (a << 24) | (r << 16) | (g << 8) | b;
            final color = Color(argbColor);

            StructuredLogService.log('✅ [SystemThemeColor] 成功获取 ColorizationColor: 0x${argbColor.toRadixString(16).toUpperCase()}');
            StructuredLogService.log('   原始值 (ABGR): 0x${colorValue.toRadixString(16).toUpperCase()}');
            StructuredLogService.log('   转换后 (ARGB): A=$a, R=$r, G=$g, B=$b');

            return color;
          }
        }
      } catch (e) {
        StructuredLogService.log('⚠️ [SystemThemeColor] ColorizationColor 获取失败: $e');
      }

      // 如果都失败了，返回默认蓝色
      StructuredLogService.log('⚠️ [SystemThemeColor] 无法获取系统强调色，使用默认值');
      return const Color(0xFF0078D4);
    } catch (e) {
      StructuredLogService.log('❌ [SystemThemeColor] 获取 Windows 系统强调色失败: $e');
      return const Color(0xFF0078D4);
    }
  }

  /// 检查当前平台是否支持系统主题色
  bool isPlatformSupported() {
    return Platform.isAndroid || Platform.isWindows;
  }

  /// 获取平台支持说明
  String getPlatformSupportMessage() {
    if (Platform.isAndroid) {
      return 'Android 12+ 支持 Material You 动态颜色';
    } else if (Platform.isWindows) {
      return 'Windows 支持系统强调色（从注册表读取）';
    } else {
      return '当前平台暂不支持系统主题色';
    }
  }
}


