import 'structured_log_service.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 歌词样式类型
enum LyricStyle {
  /// 默认样式 (卡拉OK样式)
  defaultStyle,

  /// 流体云样式
  fluidCloud,

  /// 沉浸样式
  immersive,
}

/// 歌词对齐方式
enum LyricAlignment {
  /// 居中
  center,
  /// 顶部
  top,
}

/// 歌词样式服务
/// 管理歌词样式偏好设置
class LyricStyleService extends ChangeNotifier {
  static final LyricStyleService _instance = LyricStyleService._internal();
  factory LyricStyleService() => _instance;
  LyricStyleService._internal();

  static const String _storageKey = 'lyric_style';
  static const String _alignmentStorageKey = 'lyric_alignment';
  static const String _fontSizeKey = 'lyric_font_size';
  static const String _lineHeightKey = 'lyric_line_height';
  static const String _blurSigmaKey = 'lyric_blur_sigma';
  static const String _autoLineHeightKey = 'lyric_auto_line_height';

  LyricStyle _currentStyle = LyricStyle.defaultStyle;
  LyricAlignment _currentAlignment = LyricAlignment.center;

  // 歌词配置项
  double _fontSize = 32.0;
  double _lineHeight = 100.0;
  double _blurSigma = 4.0;
  bool _autoLineHeight = true; // 是否开启字号间距自适应

  /// 获取当前歌词样式
  LyricStyle get currentStyle => _currentStyle;

  /// 获取当前歌词对齐方式
  LyricAlignment get currentAlignment => _currentAlignment;

  /// 获取字号
  double get fontSize => _fontSize;

  /// 获取行高
  double get lineHeight => _lineHeight;

  /// 获取模糊强度
  double get blurSigma => _blurSigma;

  /// 是否自适应行高
  bool get autoLineHeight => _autoLineHeight;

  /// 初始化服务
  Future<void> initialize() async {
    await _loadStyle();
  }

  /// 从本地存储加载样式设置
  Future<void> _loadStyle() async {
    try {
      final prefs = await SharedPreferences.getInstance();

      // 加载样式
      final savedStyleIndex = prefs.getInt(_storageKey);
      if (savedStyleIndex != null && savedStyleIndex >= 0 && savedStyleIndex < LyricStyle.values.length) {
        _currentStyle = LyricStyle.values[savedStyleIndex];
      } else {
        _currentStyle = LyricStyle.fluidCloud;
      }

      // 加载对齐方式
      final savedAlignmentIndex = prefs.getInt(_alignmentStorageKey);
      if (savedAlignmentIndex != null && savedAlignmentIndex >= 0 && savedAlignmentIndex < LyricAlignment.values.length) {
        _currentAlignment = LyricAlignment.values[savedAlignmentIndex];
      } else {
        _currentAlignment = LyricAlignment.center;
      }

      // 加载配置
      _fontSize = prefs.getDouble(_fontSizeKey) ?? 32.0;
      _lineHeight = prefs.getDouble(_lineHeightKey) ?? 100.0;
      _blurSigma = prefs.getDouble(_blurSigmaKey) ?? 4.0;
      _autoLineHeight = prefs.getBool(_autoLineHeightKey) ?? true;

      notifyListeners();
    } catch (e) {
      StructuredLogService.log('❌ [LyricStyleService] 加载歌词配置失败: $e');
      _currentStyle = LyricStyle.fluidCloud;
      _currentAlignment = LyricAlignment.center;
    }
  }

  /// 设置歌词样式
  Future<void> setStyle(LyricStyle style) async {
    if (_currentStyle == style) return;

    _currentStyle = style;
    notifyListeners();

    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(_storageKey, style.index);
      StructuredLogService.log('✅ [LyricStyleService] 歌词样式已保存: ${_getStyleName(style)}');
    } catch (e) {
      StructuredLogService.log('❌ [LyricStyleService] 保存歌词样式失败: $e');
    }
  }

  /// 设置歌词对齐方式
  Future<void> setAlignment(LyricAlignment alignment) async {
    if (_currentAlignment == alignment) return;

    _currentAlignment = alignment;
    notifyListeners();

    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(_alignmentStorageKey, alignment.index);
      StructuredLogService.log('✅ [LyricStyleService] 歌词对齐已保存: ${alignment.name}');
    } catch (e) {
      StructuredLogService.log('❌ [LyricStyleService] 保存歌词对齐失败: $e');
    }
  }

  /// 设置字号
  Future<void> setFontSize(double size) async {
    if ((_fontSize - size).abs() < 0.1) return;
    _fontSize = size;

    // 自适应逻辑：如果开启，则自动按比例调整行高
    if (_autoLineHeight) {
      _lineHeight = size * (100.0 / 32.0); // 保持原有比例
    }

    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setDouble(_fontSizeKey, _fontSize);
      if (_autoLineHeight) {
        await prefs.setDouble(_lineHeightKey, _lineHeight);
      }
    } catch (e) {}
  }

  /// 设置行高
  Future<void> setLineHeight(double height) async {
    if ((_lineHeight - height).abs() < 0.1) return;
    _lineHeight = height;
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setDouble(_lineHeightKey, height);
    } catch (e) {}
  }

  /// 设置模糊强度
  Future<void> setBlurSigma(double sigma) async {
    if ((_blurSigma - sigma).abs() < 0.1) return;
    _blurSigma = sigma;
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setDouble(_blurSigmaKey, sigma);
    } catch (e) {}
  }

  /// 设置自适应间距
  Future<void> setAutoLineHeight(bool auto) async {
    if (_autoLineHeight == auto) return;
    _autoLineHeight = auto;

    if (auto) {
      _lineHeight = _fontSize * (100.0 / 32.0);
    }

    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_autoLineHeightKey, auto);
      if (auto) {
        await prefs.setDouble(_lineHeightKey, _lineHeight);
      }
    } catch (e) {}
  }

  /// 获取样式的显示名称
  String getStyleName(LyricStyle style) => _getStyleName(style);

  static String _getStyleName(LyricStyle style) {
    switch (style) {
      case LyricStyle.defaultStyle:
        return '默认样式';
      case LyricStyle.fluidCloud:
        return '流体云';
      case LyricStyle.immersive:
        return '沉浸样式';
    }
  }

  /// 获取样式的描述
  String getStyleDescription(LyricStyle style) {
    switch (style) {
      case LyricStyle.defaultStyle:
        return '经典卡拉OK效果，从左到右填充';
      case LyricStyle.fluidCloud:
        return '云朵般流动的歌词效果，柔和舒适';
      case LyricStyle.immersive:
        return '简洁的沉浸式体验，突出单行歌词';
    }
  }
}

