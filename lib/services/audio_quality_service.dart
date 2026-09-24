import 'structured_log_service.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/song_detail.dart';
import 'audio_source_service.dart';
import 'lx_music_runtime_service.dart';

/// 音质服务 - 管理用户选择的音质
class AudioQualityService extends ChangeNotifier {
  static final AudioQualityService _instance = AudioQualityService._internal();
  factory AudioQualityService() => _instance;
  AudioQualityService._internal() {
    _loadQuality();
  }

  AudioQuality _currentQuality = AudioQuality.exhigh; // 默认极高音质
  AudioQuality get currentQuality => _currentQuality;

  static const String _qualityKey = 'audio_quality';

  // ==================== 各音源支持的音质列表 ====================

  /// 音质优先级顺序（从低到高）
  static const List<AudioQuality> _qualityPriority = [
    AudioQuality.standard,   // 128k
    AudioQuality.exhigh,     // 320k
    AudioQuality.lossless,   // flac
    AudioQuality.hires,      // Hi-Res (24bit/96kHz)
    AudioQuality.jyeffect,   // Audio Vivid
    AudioQuality.jymaster,   // 超清母带
  ];

  /// 字符串音质转换为枚举
  static AudioQuality? stringToQuality(String qualityStr) {
    switch (qualityStr) {
      case '128k':
        return AudioQuality.standard;
      case '320k':
        return AudioQuality.exhigh;
      case 'flac':
        return AudioQuality.lossless;
      case 'flac24bit':
      case 'hires':
        return AudioQuality.hires;
      case 'jyeffect':
        return AudioQuality.jyeffect;
      case 'jymaster':
        return AudioQuality.jymaster;
      default:
        return null;
    }
  }

  /// 枚举转换为字符串音质（用于 API 请求）
  static String qualityToString(AudioQuality quality) {
    switch (quality) {
      case AudioQuality.standard:
        return '128k';
      case AudioQuality.exhigh:
        return '320k';
      case AudioQuality.lossless:
        return 'flac';
      case AudioQuality.hires:
        return 'hires';
      case AudioQuality.jyeffect:
        return 'jyeffect';
      case AudioQuality.jymaster:
        return 'jymaster';
      default:
        return '320k';
    }
  }

  /// 根据音源类型获取支持的音质列表
  List<AudioQuality> getSupportedQualities(AudioSourceType sourceType) {
    switch (sourceType) {
      case AudioSourceType.lxmusic:
        // 从洛雪运行时动态获取音质列表
        final runtime = LxMusicRuntimeService();
        if (runtime.isScriptReady && runtime.currentScript != null) {
          final qualityStrings = runtime.currentScript!.supportedQualities;
          if (qualityStrings.isNotEmpty) {
            return qualityStrings
                .map((s) => stringToQuality(s))
                .where((q) => q != null)
                .cast<AudioQuality>()
                .toList();
          }
        }
        // 回退默认值
        return [AudioQuality.standard, AudioQuality.exhigh, AudioQuality.lossless];
      case AudioSourceType.navidrome:
        // Navidrome 以服务端实际文件为准，这里给出全量可选
        return _qualityPriority;
    }
  }

  /// 获取指定平台支持的音质列表（洛雪音源专用）
  /// [lxPlatform] - 洛雪格式的平台代码 (wy, tx, kg, kw)
  List<AudioQuality> getQualitiesForPlatform(String lxPlatform) {
    final runtime = LxMusicRuntimeService();
    if (runtime.isScriptReady && runtime.currentScript != null) {
      final qualityStrings = runtime.currentScript!.getQualitiesForPlatform(lxPlatform);
      if (qualityStrings.isNotEmpty) {
        return qualityStrings
            .map((s) => stringToQuality(s))
            .where((q) => q != null)
            .cast<AudioQuality>()
            .toList();
      }
    }
    return [AudioQuality.standard, AudioQuality.exhigh, AudioQuality.lossless];
  }

  /// 获取降级后的音质
  /// 当用户选择的音质不被当前平台支持时，返回最接近的较低音质
  /// [selectedQuality] - 用户选择的音质
  /// [supportedQualities] - 当前平台支持的音质列表
  AudioQuality getEffectiveQuality(AudioQuality selectedQuality, List<AudioQuality> supportedQualities) {
    // 如果支持的音质列表为空，返回默认音质
    if (supportedQualities.isEmpty) {
      return AudioQuality.exhigh;
    }

    // 如果选择的音质被支持，直接返回
    if (supportedQualities.contains(selectedQuality)) {
      return selectedQuality;
    }

    // 否则降级到最接近的较低音质
    final selectedIndex = _qualityPriority.indexOf(selectedQuality);

    // 从选择的音质向下查找
    for (int i = selectedIndex - 1; i >= 0; i--) {
      if (supportedQualities.contains(_qualityPriority[i])) {
        StructuredLogService.log('⚠️ [AudioQualityService] 音质降级: ${selectedQuality.displayName} -> ${_qualityPriority[i].displayName}');
        return _qualityPriority[i];
      }
    }

    // 如果没有更低的，返回支持列表中的第一个
    return supportedQualities.first;
  }


  /// 加载音质设置
  Future<void> _loadQuality() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final qualityString = prefs.getString(_qualityKey);

      if (qualityString != null) {
        _currentQuality = AudioQuality.values.firstWhere(
          (e) => e.toString() == qualityString,
          orElse: () => AudioQuality.exhigh,
        );
      }

      StructuredLogService.log('🎵 [AudioQualityService] 加载音质设置: ${getQualityName()}');
    } catch (e) {
      StructuredLogService.log('❌ [AudioQualityService] 加载音质设置失败: $e');
      _currentQuality = AudioQuality.exhigh;
    }
    notifyListeners();
  }

  /// 设置音质
  Future<void> setQuality(AudioQuality quality) async {
    if (_currentQuality == quality) return;

    _currentQuality = quality;

    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_qualityKey, quality.toString());
      StructuredLogService.log('🎵 [AudioQualityService] 音质已设置: ${getQualityName()}');
    } catch (e) {
      StructuredLogService.log('❌ [AudioQualityService] 保存音质设置失败: $e');
    }

    notifyListeners();
  }

  /// 获取音质名称
  String getQualityName([AudioQuality? quality]) {
    final q = quality ?? _currentQuality;
    switch (q) {
      case AudioQuality.standard:
        return '标准音质';
      case AudioQuality.exhigh:
        return '高品质';
      case AudioQuality.lossless:
        return '无损音质';
      case AudioQuality.hires:
        return 'Hi-Res';
      case AudioQuality.jyeffect:
        return 'Audio Vivid';
      case AudioQuality.jymaster:
        return '超清母带';
      default:
        return '高品质';
    }
  }

  /// 获取音质短标签（技术标识，如 128kbps, 320, flac, Hi-Res）
  String getShortLabel([AudioQuality? quality]) {
    final q = quality ?? _currentQuality;
    switch (q) {
      case AudioQuality.standard:
        return '128kbps';
      case AudioQuality.exhigh:
        return '320kbps';
      case AudioQuality.lossless:
        return 'flac';
      case AudioQuality.hires:
        return 'Hi-Res';
      case AudioQuality.jyeffect:
        return 'Vivid';
      case AudioQuality.jymaster:
        return 'Master';
      default:
        return '320';
    }
  }

  /// 获取音质描述
  String getQualityDescription([AudioQuality? quality]) {
    final q = quality ?? _currentQuality;
    switch (q) {
      case AudioQuality.standard:
        return 'MP3 128kbps，节省流量';
      case AudioQuality.exhigh:
        return 'MP3 320kbps，推荐';
      case AudioQuality.lossless:
        return 'FLAC 无损，音质优秀';
      case AudioQuality.hires:
        return 'Hi-Res 24bit/96kHz';
      case AudioQuality.jyeffect:
        return 'Audio Vivid，沉浸体验';
      case AudioQuality.jymaster:
        return '超清母带，极致体验';
      default:
        return 'MP3 320kbps，推荐';
    }
  }

  /// 获取QQ音乐的音质键名
  String getQQMusicQualityKey() {
    switch (_currentQuality) {
      case AudioQuality.standard:
        return '128';
      case AudioQuality.exhigh:
        return '320';
      case AudioQuality.lossless:
        return 'flac';
      default:
        return '320';
    }
  }

  /// 从QQ音乐的music_urls中选择最佳可用音质
  /// 优先选择用户设定的音质，如果不存在则降级选择
  String? selectBestQQMusicUrl(Map<String, dynamic> musicUrls) {
    final preferredKey = getQQMusicQualityKey();

    // 音质优先级（从高到低）
    final qualityPriority = ['flac', '320', '128'];

    // 首先尝试用户选择的音质
    if (musicUrls.containsKey(preferredKey)) {
      final urlData = musicUrls[preferredKey];
      if (urlData is Map && urlData['url'] != null && urlData['url'].isNotEmpty) {
        StructuredLogService.log('🎵 [AudioQualityService] QQ音乐使用音质: $preferredKey');
        return urlData['url'];
      }
    }

    // 如果用户选择的音质不可用，按优先级降级
    for (final key in qualityPriority) {
      if (musicUrls.containsKey(key)) {
        final urlData = musicUrls[key];
        if (urlData is Map && urlData['url'] != null && urlData['url'].isNotEmpty) {
          StructuredLogService.log('⚠️ [AudioQualityService] QQ音乐音质降级到: $key');
          return urlData['url'];
        }
      }
    }

  StructuredLogService.log('❌ [AudioQualityService] QQ音乐无可用音质');
    return null;
  }

  /// 根据音质/级别字符串获取文件后缀
  static String getExtensionFromLevel(String? level) {
    if (level == null || level.isEmpty) return 'mp3';

    // 尝试直接通过字符串特征判断（更鲁棒，因为 level 可能包含多种格式）
    final lowerLevel = level.toLowerCase();
    if (lowerLevel.contains('flac') || lowerLevel.contains('hires') || lowerLevel.contains('lossless')) {
      return 'flac';
    }

    // 尝试通过枚举转换
    final quality = stringToQuality(level);
    if (quality != null) {
      return quality.extension;
    }

    return 'mp3';
  }
}
