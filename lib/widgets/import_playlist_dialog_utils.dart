part of 'import_playlist_dialog.dart';

/// 获取输入提示文本（顶级函数版本）
String _getInputHintTextImpl(MusicPlatform platform) {
  switch (platform) {
    case MusicPlatform.netease:
      return '支持以下两种输入方式：\n• 直接输入歌单ID，如：19723756\n• 粘贴完整URL，如：https://music.163.com/#/playlist?id=19723756';
    case MusicPlatform.qq:
      return '支持以下两种输入方式：\n• 直接输入歌单ID，如：8522515502\n• 粘贴完整URL，如：https://y.qq.com/n/ryqq/playlist/8522515502';
    case MusicPlatform.kuwo:
      return '支持以下两种输入方式：\n• 直接输入歌单ID，如：3567349593\n• 粘贴分享链接，如：https://m.kuwo.cn/newh5app/playlist_detail/3567349593';
    case MusicPlatform.kugou:
      return '';
    case MusicPlatform.apple:
      return '支持以下两种输入方式：\n• 直接输入歌单ID，如：pl.u-55D6ZJ3iDyp2AD\n• 粘贴分享链接，如：https://music.apple.com/cn/playlist/xxx/pl.u-55D6ZJ3iDyp2AD';
  }
}

/// 字符串相似度计算（Levenshtein距离）
int _levenshteinDistance(String s1, String s2) {
  if (s1.isEmpty) return s2.length;
  if (s2.isEmpty) return s1.length;

  final matrix = List.generate(
    s1.length + 1,
    (i) => List.generate(s2.length + 1, (j) => 0),
  );

  for (int i = 0; i <= s1.length; i++) {
    matrix[i][0] = i;
  }
  for (int j = 0; j <= s2.length; j++) {
    matrix[0][j] = j;
  }

  for (int i = 1; i <= s1.length; i++) {
    for (int j = 1; j <= s2.length; j++) {
      final cost = s1[i - 1].toLowerCase() == s2[j - 1].toLowerCase() ? 0 : 1;
      matrix[i][j] = [
        matrix[i - 1][j] + 1,      // deletion
        matrix[i][j - 1] + 1,      // insertion
        matrix[i - 1][j - 1] + cost, // substitution
      ].reduce((a, b) => a < b ? a : b);
    }
  }

  return matrix[s1.length][s2.length];
}

/// 计算字符串相似度（0-1之间，1表示完全相同）
double _similarity(String s1, String s2) {
  if (s1.isEmpty && s2.isEmpty) return 1.0;
  if (s1.isEmpty || s2.isEmpty) return 0.0;

  final distance = _levenshteinDistance(s1, s2);
  final maxLength = s1.length > s2.length ? s1.length : s2.length;
  return 1.0 - (distance / maxLength);
}

/// 检查艺术家是否完全匹配（忽略大小写和空格）
bool _artistsMatch(String trackArtists, String resultSinger) {
  if (trackArtists.isEmpty && resultSinger.isEmpty) return true;
  if (trackArtists.isEmpty || resultSinger.isEmpty) return false;

  // 标准化：转换为小写，移除空格
  final normalize = (String s) => s.toLowerCase().replaceAll(RegExp(r'\s+'), '');

  // 分割艺术家（支持多种分隔符）
  final trackArtistsList = trackArtists.split(RegExp(r'[/、,，\s]+'))
      .map((s) => normalize(s.trim()))
      .where((s) => s.isNotEmpty)
      .toList();
  final resultArtistsList = resultSinger.split(RegExp(r'[/、,，\s]+'))
      .map((s) => normalize(s.trim()))
      .where((s) => s.isNotEmpty)
      .toList();

  if (trackArtistsList.isEmpty || resultArtistsList.isEmpty) return false;

  // 检查是否所有trackArtists都在resultArtistsList中（或反之）
  // 允许部分匹配，但至少要有主要艺术家匹配
  bool hasMatch = false;
  for (final trackArtist in trackArtistsList) {
    for (final resultArtist in resultArtistsList) {
      // 完全匹配或包含关系
      if (trackArtist == resultArtist ||
          trackArtist.contains(resultArtist) ||
          resultArtist.contains(trackArtist)) {
        hasMatch = true;
        break;
      }
    }
    if (hasMatch) break;
  }

  return hasMatch;
}

/// 找到最匹配的搜索结果
/// 要求：至少确保歌手完全一致（或至少有一个主要歌手匹配）
KugouSearchResult? _findBestMatch(String trackName, String trackArtists, List<KugouSearchResult> results) {
  if (results.isEmpty) return null;

  double bestScore = 0.0;
  KugouSearchResult? bestMatch;

  for (final result in results) {
    // 首先检查艺术家是否匹配（必需条件）
    final artistsMatch = _artistsMatch(trackArtists, result.singer);

    // 如果艺术家不匹配，跳过这个结果（除非原歌曲没有艺术家信息）
    if (trackArtists.isNotEmpty && !artistsMatch) {
      continue; // 跳过不匹配的结果
    }

    // 计算歌曲名相似度
    final nameSimilarity = _similarity(trackName, result.name);

    // 计算艺术家相似度（如果艺术家信息存在）
    double artistSimilarity = 0.0;
    if (trackArtists.isNotEmpty && result.singer.isNotEmpty) {
      // 尝试匹配艺术家（支持多个艺术家，用/或、分隔）
      final trackArtistsList = trackArtists.split(RegExp(r'[/、,，]')).map((s) => s.trim()).toList();
      final resultArtistsList = result.singer.split(RegExp(r'[/、,，]')).map((s) => s.trim()).toList();

      // 计算最高艺术家匹配度
      for (final trackArtist in trackArtistsList) {
        for (final resultArtist in resultArtistsList) {
          final sim = _similarity(trackArtist, resultArtist);
          if (sim > artistSimilarity) {
            artistSimilarity = sim;
          }
        }
      }
    } else if (trackArtists.isEmpty && result.singer.isEmpty) {
      // 都没有艺术家信息，给一个基础分
      artistSimilarity = 0.5;
    } else if (artistsMatch) {
      // 艺术家已匹配，给高分
      artistSimilarity = 1.0;
    }

    // 综合评分：歌曲名权重70%，艺术家权重30%
    final score = nameSimilarity * 0.7 + artistSimilarity * 0.3;

    if (score > bestScore) {
      bestScore = score;
      bestMatch = result;
    }
  }

  // 如果最佳匹配的相似度低于0.3，认为匹配失败
  // 或者如果原歌曲有艺术家信息但最佳匹配没有匹配到艺术家，也认为失败
  if (bestScore < 0.3) {
    return null;
  }

  // 如果原歌曲有艺术家信息，必须确保艺术家匹配
  if (trackArtists.isNotEmpty && bestMatch != null) {
    if (!_artistsMatch(trackArtists, bestMatch.singer)) {
      return null; // 艺术家不匹配，返回null
    }
  }

  return bestMatch;
}
