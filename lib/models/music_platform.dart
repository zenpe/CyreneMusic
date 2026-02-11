/// 音乐平台枚举
enum MusicPlatform {
  netease('网易云音乐', '🎵'),
  qq('QQ音乐', '🎶'),
  kugou('酷狗音乐', '🎸'),
  kuwo('酷我音乐', '🎤'),
  apple('Apple Music', '🍎');

  final String name;
  final String icon;
  const MusicPlatform(this.name, this.icon);
}
