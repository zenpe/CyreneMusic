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

/// 计算字符串相似度（0-1之间，1表示完全相同）

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
