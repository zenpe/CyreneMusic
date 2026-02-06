import '../models/lyric_line.dart';

/// 歌词解析器
class LyricParser {
  /// 解析网易云音乐 YRC 格式逐字歌词
  /// YRC格式示例: [22310,4300](22310,2880,0)都 (25190,310,0)是(25500,290,0)勇
  /// 注意：字级持续时间单位是百分之一秒（需要×10转换为毫秒）
  static List<LyricLine> parseNeteaseYrcLyric(String yrcLyric, {String? translation}) {
    if (yrcLyric.isEmpty) return [];

    final lines = <LyricLine>[];
    final yrcLines = yrcLyric.split('\n');

    // 解析翻译歌词（如果有）
    final Map<Duration, String> translationMap = {};
    if (translation != null && translation.isNotEmpty) {
      final translationLines = translation.split('\n');
      for (final line in translationLines) {
        final time = LyricLine.parseTime(line);
        if (time != null) {
          final text = line
              .replaceAll(RegExp(r'\[\d+:\d+\.\d+\]'), '')
              .replaceAll(RegExp(r'\[\d+:\d+:\d+\]'), '')
              .replaceAll(RegExp(r'\[\d+:\d+\]'), '')
              .trim();
          if (text.isNotEmpty) {
            translationMap[time] = text;
          }
        }
      }
    }

    // 解析YRC格式歌词
    for (final line in yrcLines) {
      if (line.trim().isEmpty) continue;

      try {
        // 跳过元数据行（JSON格式）
        if (line.startsWith('[{')) {
          continue;
        }

        // YRC格式: [startTime,duration](word1Time,word1Duration,0)word1 (word2Time,word2Duration,0)word2
        final lineTimeMatch = RegExp(r'^\[(\d+),(\d+)\]').firstMatch(line);
        if (lineTimeMatch == null) continue;

        final lineStartMs = int.parse(lineTimeMatch.group(1)!);
        final lineDurationMs = int.parse(lineTimeMatch.group(2)!);
        final lineStartTime = Duration(milliseconds: lineStartMs);
        final lineDuration = Duration(milliseconds: lineDurationMs);

        // 提取逐字歌词
        final words = <LyricWord>[];
        final textBuffer = StringBuffer();

        // 匹配所有 (time,duration,0)word 格式
        final wordPattern = RegExp(r'\((\d+),(\d+),\d+\)([^\(]+)');
        final wordMatches = wordPattern.allMatches(line);

        for (final match in wordMatches) {
          final wordStartMs = int.parse(match.group(1)!);
          final wordDurationMs = int.parse(match.group(2)!); // 持续时间，单位毫秒
          final wordText = match.group(3)!; // 保留空格，不使用 trim()

          if (wordText.isNotEmpty) {
            // YRC 格式中，word startTime 和 duration 都是毫秒
            words.add(LyricWord(
              startTime: Duration(milliseconds: wordStartMs),
              duration: Duration(milliseconds: wordDurationMs),
              text: wordText,
            ));
            textBuffer.write(wordText);
          }
        }

        final fullText = textBuffer.toString().trim();
        if (fullText.isNotEmpty) {
          lines.add(LyricLine(
            startTime: lineStartTime,
            text: fullText,
            translation: translationMap[lineStartTime],
            words: words.isNotEmpty ? words : null,
            lineDuration: lineDuration,
          ));
        }
      } catch (e) {
        // 解析失败，跳过该行
        print('YRC解析失败: $line, 错误: $e');
        continue;
      }
    }

    // 按时间排序
    lines.sort((a, b) => a.startTime.compareTo(b.startTime));

    // 调试日志：确认解析了多少行逐字歌词
    final wordsCount = lines.where((l) => l.hasWordByWord).length;
    print('[YRC解析] 总行数: ${lines.length}, 包含逐字数据: $wordsCount行');
    
    return lines;
  }

  /// 解析网易云音乐 LRC 格式歌词
  /// [translation] - 普通翻译歌词 (tlyric)
  /// [yrcLyric] - YRC 逐字歌词
  /// [yrcTranslation] - YRC 对应的翻译歌词 (ytlrc)，时间戳与 YRC 匹配
  static List<LyricLine> parseNeteaseLyric(String lyric, {String? translation, String? yrcLyric, String? yrcTranslation}) {
    // 如果有YRC逐字歌词，优先使用
    if (yrcLyric != null && yrcLyric.isNotEmpty) {
      // 优先使用 ytlrc（时间戳与 YRC 匹配），否则回退到 tlyric
      final effectiveTranslation = (yrcTranslation != null && yrcTranslation.isNotEmpty) 
          ? yrcTranslation 
          : translation;
      final yrcLines = parseNeteaseYrcLyric(yrcLyric, translation: effectiveTranslation);
      if (yrcLines.isNotEmpty) {
        return yrcLines;
      }
    }

    // 否则使用普通LRC格式
    if (lyric.isEmpty) return [];

    // 如果没有任何时间戳，则按纯文本歌词处理（Navidrome 可能返回无时间戳的歌词）
    final lyricLinesRaw = lyric.split('\n');
    final hasTimestamp = lyricLinesRaw.any((line) => LyricLine.parseTime(line) != null);
    if (!hasTimestamp) {
      return _parsePlainTextLyric(lyricLinesRaw);
    }

    final lines = <LyricLine>[];
    final lyricLines = lyric.split('\n');
    
    // 解析翻译歌词（如果有）
    final Map<Duration, String> translationMap = {};
    if (translation != null && translation.isNotEmpty) {
      final translationLines = translation.split('\n');
      for (final line in translationLines) {
        final time = LyricLine.parseTime(line);
        if (time != null) {
          // 去除时间戳，兼容 [mm:ss.xx] / [mm:ss.xxx] / [mm:ss:SS]
          final text = line
              .replaceAll(RegExp(r'\[\d+:\d+\.\d+\]'), '')
              .replaceAll(RegExp(r'\[\d+:\d+:\d+\]'), '')
              .replaceAll(RegExp(r'\[\d+:\d+\]'), '')
              .trim();
          if (text.isNotEmpty) {
            translationMap[time] = text;
          }
        }
      }
    }

    // 解析原歌词
    for (final line in lyricLines) {
      final time = LyricLine.parseTime(line);
      if (time != null) {
        // 去除时间戳，兼容多种格式
        final text = line
            .replaceAll(RegExp(r'\[\d+:\d+\.\d+\]'), '')
            .replaceAll(RegExp(r'\[\d+:\d+:\d+\]'), '')
            .replaceAll(RegExp(r'\[\d+:\d+\]'), '')
            .trim();
        if (text.isNotEmpty) {
          lines.add(LyricLine(
            startTime: time,
            text: text,
            translation: translationMap[time],
          ));
        }
      }
    }

    // 按时间排序
    lines.sort((a, b) => a.startTime.compareTo(b.startTime));
    
    return lines;
  }

  /// 解析 QQ 音乐歌词（格式类似，但可能有差异）
  static List<LyricLine> parseQQLyric(String lyric, {String? translation}) {
    // QQ音乐格式与网易云类似，暂时使用相同解析方式
    // 后续如有差异可以在这里调整
    return parseNeteaseLyric(lyric, translation: translation);
  }

  static List<LyricLine> _parsePlainTextLyric(List<String> rawLines) {
    final lines = <LyricLine>[];
    var index = 0;
    for (final raw in rawLines) {
      final text = raw.trim();
      if (text.isEmpty) continue;
      lines.add(LyricLine(
        startTime: Duration(seconds: index * 3),
        text: text,
      ));
      index += 1;
    }
    return lines;
  }

  /// 解析酷狗音乐歌词（可能需要特殊处理）
  static List<LyricLine> parseKugouLyric(String lyric, {String? translation}) {
    // 酷狗音乐格式可能有所不同，预留接口
    // 暂时使用相同解析方式
    return parseNeteaseLyric(lyric, translation: translation);
  }

  /// 根据当前播放时间查找当前歌词行索引
  static int findCurrentLineIndex(List<LyricLine> lyrics, Duration currentTime) {
    if (lyrics.isEmpty) return -1;

    for (int i = lyrics.length - 1; i >= 0; i--) {
      if (currentTime >= lyrics[i].startTime) {
        return i;
      }
    }

    return -1;
  }

  /// 获取当前显示的歌词（带前后几行）
  static List<LyricLine> getCurrentDisplayLines(
    List<LyricLine> lyrics,
    int currentIndex, {
    int beforeCount = 3,
    int afterCount = 5,
  }) {
    if (lyrics.isEmpty || currentIndex < 0) return [];

    final startIndex = (currentIndex - beforeCount).clamp(0, lyrics.length);
    final endIndex = (currentIndex + afterCount + 1).clamp(0, lyrics.length);

    return lyrics.sublist(startIndex, endIndex);
  }
}

