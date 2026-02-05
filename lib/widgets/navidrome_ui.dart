import 'package:flutter/material.dart';
import '../models/navidrome_models.dart';
import '../models/track.dart';
import '../services/color_extraction_service.dart';
import '../services/navidrome_api.dart';
import '../services/player_service.dart';
import '../services/playlist_queue_service.dart';

/// Navidrome 设计规范颜色
class NavidromeColors {
  static const Color background = Color(0xFF0A0A0A);
  static const Color cardBackground = Color(0xFF1C1C1E);
  static const Color cardBorder = Color(0xFF2C2C2E);
  static const Color activeBlue = Color(0xFF0A84FF);
  static const Color radioOrange = Color(0xFFFF9500);
  static const Color textPrimary = Color(0xFFFFFFFF);
  static const Color textSecondary = Color(0xFF8E8E93);
  static const Color textTertiary = Color(0xFF5A5A5E);

  // Light scheme (from bak1 mockups)
  static const Color lightBackground = Color(0xFFF2F2F7);
  static const Color lightCardBackground = Color(0xFFFFFFFF);
  static const Color lightBorder = Color(0xFFD1D1D6);
  static const Color lightDivider = Color(0xFFE5E5EA);
  static const Color lightBottomBar = Color(0xFFFAFAFA);
  static const Color lightTextPrimary = Color(0xFF000000);
  static const Color lightTextTertiary = Color(0xFFC7C7CC);
}

class NavidromeThemeData {
  final bool isDark;
  final Color background;
  final Color surface;
  final Color card;
  final Color cardBorder;
  final Color divider;
  final Color textPrimary;
  final Color textSecondary;
  final Color textTertiary;
  final Color chipSelectedBackground;
  final Color chipSelectedForeground;
  final Color chipUnselectedBackground;
  final Color chipUnselectedForeground;
  final Color chipBorder;
  final Color bottomBarBackground;
  final Color bottomBarBorder;
  final Color miniPlayerBackground;
  final Color miniPlayerBorder;
  final Color progressTrack;
  final Color progressActive;
  final List<BoxShadow> cardShadow;

  const NavidromeThemeData({
    required this.isDark,
    required this.background,
    required this.surface,
    required this.card,
    required this.cardBorder,
    required this.divider,
    required this.textPrimary,
    required this.textSecondary,
    required this.textTertiary,
    required this.chipSelectedBackground,
    required this.chipSelectedForeground,
    required this.chipUnselectedBackground,
    required this.chipUnselectedForeground,
    required this.chipBorder,
    required this.bottomBarBackground,
    required this.bottomBarBorder,
    required this.miniPlayerBackground,
    required this.miniPlayerBorder,
    required this.progressTrack,
    required this.progressActive,
    required this.cardShadow,
  });

  factory NavidromeThemeData.dark() {
    return const NavidromeThemeData(
      isDark: true,
      background: NavidromeColors.background,
      surface: NavidromeColors.background,
      card: NavidromeColors.cardBackground,
      cardBorder: NavidromeColors.cardBorder,
      divider: NavidromeColors.cardBorder,
      textPrimary: NavidromeColors.textPrimary,
      textSecondary: NavidromeColors.textSecondary,
      textTertiary: NavidromeColors.textTertiary,
      chipSelectedBackground: NavidromeColors.activeBlue,
      chipSelectedForeground: Colors.white,
      chipUnselectedBackground: NavidromeColors.cardBackground,
      chipUnselectedForeground: NavidromeColors.textSecondary,
      chipBorder: NavidromeColors.cardBorder,
      bottomBarBackground: Color(0xFF0F0F0F),
      bottomBarBorder: NavidromeColors.cardBorder,
      miniPlayerBackground: NavidromeColors.cardBackground,
      miniPlayerBorder: NavidromeColors.cardBorder,
      progressTrack: NavidromeColors.cardBorder,
      progressActive: NavidromeColors.activeBlue,
      cardShadow: [],
    );
  }

  factory NavidromeThemeData.light() {
    return const NavidromeThemeData(
      isDark: false,
      background: NavidromeColors.lightBackground,
      surface: NavidromeColors.lightBackground,
      card: NavidromeColors.lightCardBackground,
      cardBorder: NavidromeColors.lightBorder,
      divider: NavidromeColors.lightDivider,
      textPrimary: NavidromeColors.lightTextPrimary,
      textSecondary: NavidromeColors.textSecondary,
      textTertiary: NavidromeColors.lightTextTertiary,
      chipSelectedBackground: NavidromeColors.activeBlue,
      chipSelectedForeground: Colors.white,
      chipUnselectedBackground: NavidromeColors.lightCardBackground,
      chipUnselectedForeground: NavidromeColors.lightTextPrimary,
      chipBorder: NavidromeColors.lightBorder,
      bottomBarBackground: NavidromeColors.lightBottomBar,
      bottomBarBorder: NavidromeColors.lightDivider,
      miniPlayerBackground: NavidromeColors.lightCardBackground,
      miniPlayerBorder: NavidromeColors.lightDivider,
      progressTrack: NavidromeColors.lightDivider,
      progressActive: NavidromeColors.activeBlue,
      cardShadow: [
        BoxShadow(
          color: Color(0x0F000000),
          blurRadius: 6,
          offset: Offset(0, 2),
        ),
      ],
    );
  }
}

class NavidromeTheme {
  static NavidromeThemeData of(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return isDark ? NavidromeThemeData.dark() : NavidromeThemeData.light();
  }
}

class NavidromeLayout {
  static const double compactWidth = 600;
  static const double tabletWidth = 900;
  static const double desktopWidth = 1200;

  static bool isCompact(double width) => width < compactWidth;
  static bool isTablet(double width) => width >= compactWidth && width < tabletWidth;
  static bool isDesktop(double width) => width >= tabletWidth;

  static int gridColumns(double width) {
    if (width >= desktopWidth) return 5;
    if (width >= tabletWidth) return 4;
    if (width >= compactWidth) return 3;
    return 2;
  }

  static double gridAspectRatio(double width) {
    if (width < compactWidth) return 0.72;
    if (width < tabletWidth) return 0.82;
    return 0.9;
  }

  static EdgeInsets pagePadding(double width) {
    final horizontal = width < compactWidth ? 16.0 : 24.0;
    return EdgeInsets.symmetric(horizontal: horizontal, vertical: 8);
  }
}

class NavidromePill extends StatelessWidget {
  final String label;
  final IconData? icon;
  final bool selected;
  final VoidCallback onTap;

  const NavidromePill({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
    this.icon,
  });

  @override
  Widget build(BuildContext context) {
    final navTheme = NavidromeTheme.of(context);

    final background = selected
        ? navTheme.chipSelectedBackground
        : navTheme.chipUnselectedBackground;
    final foreground = selected
        ? navTheme.chipSelectedForeground
        : navTheme.chipUnselectedForeground;
    final borderColor = selected ? Colors.transparent : navTheme.chipBorder;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Ink(
          height: 32,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: background,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: borderColor),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (icon != null) ...[
                Icon(icon, size: 16, color: foreground),
                const SizedBox(width: 6),
              ],
              Text(
                label,
                style: TextStyle(
                  color: foreground,
                  fontSize: 13,
                  fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class NavidromeCard extends StatelessWidget {
  final Widget child;
  final VoidCallback? onTap;
  final EdgeInsets padding;
  final BorderRadius borderRadius;
  final Color? backgroundColor;
  final Color? borderColor;

  const NavidromeCard({
    super.key,
    required this.child,
    this.onTap,
    this.padding = const EdgeInsets.all(12),
    this.borderRadius = const BorderRadius.all(Radius.circular(14)),
    this.backgroundColor,
    this.borderColor,
  });

  @override
  Widget build(BuildContext context) {
    final navTheme = NavidromeTheme.of(context);
    final bg = backgroundColor ?? navTheme.card;
    final border = borderColor ?? (navTheme.isDark ? navTheme.cardBorder : Colors.transparent);
    final shadows = navTheme.cardShadow;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: bg,
        borderRadius: borderRadius,
        border: Border.all(color: border),
        boxShadow: shadows,
      ),
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          onTap: onTap,
          borderRadius: borderRadius,
          child: Padding(
            padding: padding,
            child: child,
          ),
        ),
      ),
    );
  }
}

class NavidromeSectionHeader extends StatelessWidget {
  final String title;
  final String? actionLabel;
  final VoidCallback? onAction;
  final EdgeInsets? padding;

  const NavidromeSectionHeader({
    super.key,
    required this.title,
    this.actionLabel,
    this.onAction,
    this.padding,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final navTheme = NavidromeTheme.of(context);

    return Padding(
      padding: padding ?? const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          Expanded(
            child: Text(
              title,
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w600,
                color: navTheme.textPrimary,
              ),
            ),
          ),
          if (actionLabel != null && onAction != null)
            TextButton(
              onPressed: onAction,
              style: TextButton.styleFrom(
                padding: EdgeInsets.zero,
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              child: Text(
                actionLabel!,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: NavidromeColors.activeBlue,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// 播放状态指示器 - 音波动画
class PlayingIndicator extends StatefulWidget {
  final Color? color;
  final double size;

  const PlayingIndicator({
    super.key,
    this.color,
    this.size = 16,
  });

  @override
  State<PlayingIndicator> createState() => _PlayingIndicatorState();
}

class _PlayingIndicatorState extends State<PlayingIndicator>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final color = widget.color ?? NavidromeColors.activeBlue;
    final barWidth = widget.size / 5;
    final gap = widget.size / 10;

    return SizedBox(
      width: widget.size,
      height: widget.size,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          _buildBar(color, barWidth, 0.4, 1.0, 0),
          SizedBox(width: gap),
          _buildBar(color, barWidth, 0.6, 0.3, 200),
          SizedBox(width: gap),
          _buildBar(color, barWidth, 0.3, 0.8, 400),
        ],
      ),
    );
  }

  Widget _buildBar(Color color, double width, double minHeight, double maxHeight, int delayMs) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        // 添加相位偏移实现错落效果
        final phase = (delayMs / 600.0) % 1.0;
        final value = ((_controller.value + phase) % 1.0);
        final height = minHeight + (maxHeight - minHeight) * value;

        return Container(
          width: width,
          height: widget.size * height,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(width / 2),
          ),
        );
      },
    );
  }
}

/// 带彩色背景的专辑卡片
class NavidromeAlbumCard extends StatefulWidget {
  final String coverUrl;
  final String title;
  final String subtitle;
  final VoidCallback? onTap;
  final double? width;
  final double? height;
  final bool showColorBackground;

  const NavidromeAlbumCard({
    super.key,
    required this.coverUrl,
    required this.title,
    required this.subtitle,
    this.onTap,
    this.width,
    this.height,
    this.showColorBackground = true,
  });

  @override
  State<NavidromeAlbumCard> createState() => _NavidromeAlbumCardState();
}

class _NavidromeAlbumCardState extends State<NavidromeAlbumCard> {
  Color? _extractedColor;
  bool _colorLoaded = false;

  @override
  void initState() {
    super.initState();
    if (widget.showColorBackground && widget.coverUrl.isNotEmpty) {
      _extractColor();
    }
  }

  @override
  void didUpdateWidget(NavidromeAlbumCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.coverUrl != widget.coverUrl) {
      _colorLoaded = false;
      _extractedColor = null;
      if (widget.showColorBackground && widget.coverUrl.isNotEmpty) {
        _extractColor();
      }
    }
  }

  Future<void> _extractColor() async {
    // 先检查缓存
    final cached = ColorExtractionService().getCachedColors(widget.coverUrl);
    if (cached != null) {
      if (mounted) {
        setState(() {
          _extractedColor = _selectBaseColor(cached);
          _colorLoaded = true;
        });
      }
      return;
    }

    // 异步提取颜色
    final result = await ColorExtractionService().extractColorsFromUrl(
      widget.coverUrl,
      sampleSize: 24,
    );

    if (mounted && result != null) {
      setState(() {
        _extractedColor = _selectBaseColor(result);
        _colorLoaded = true;
      });
    }
  }

  Color _selectBaseColor(ColorExtractionResult result) {
    final color = result.dominantColor ??
        result.mutedColor ??
        result.darkMutedColor ??
        result.darkVibrantColor;
    if (color == null) return NavidromeColors.cardBackground;
    return color;
  }

  Color _adjustForDark(Color color) {
    final hsl = HSLColor.fromColor(color);
    if (hsl.lightness > 0.35) {
      return hsl.withLightness(0.2).toColor();
    }
    return color;
  }

  Color _adjustForLight(Color color) {
    final hsl = HSLColor.fromColor(color);
    final lightness = hsl.lightness < 0.8 ? 0.9 : (hsl.lightness < 0.9 ? 0.92 : hsl.lightness);
    final saturation = (hsl.saturation * 0.6).clamp(0.2, 0.7).toDouble();
    return hsl.withLightness(lightness).withSaturation(saturation).toColor();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final navTheme = NavidromeTheme.of(context);

    final backgroundColor = _colorLoaded && _extractedColor != null
        ? (navTheme.isDark
            ? _adjustForDark(_extractedColor!)
            : _adjustForLight(_extractedColor!))
        : (navTheme.isDark
            ? NavidromeColors.cardBackground
            : NavidromeColors.lightCardBackground);

    return InkWell(
      onTap: widget.onTap,
      borderRadius: BorderRadius.circular(12),
      child: SizedBox(
        width: widget.width,
        height: widget.height,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 封面容器（带彩色背景）
            Expanded(
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 300),
                curve: Curves.easeOut,
                decoration: BoxDecoration(
                  color: backgroundColor,
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: navTheme.cardShadow,
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: widget.coverUrl.isNotEmpty
                      ? Image.network(
                          widget.coverUrl,
                          fit: BoxFit.cover,
                          width: double.infinity,
                          height: double.infinity,
                          errorBuilder: (_, __, ___) => _buildPlaceholder(backgroundColor),
                        )
                      : _buildPlaceholder(backgroundColor),
                ),
              ),
            ),
            const SizedBox(height: 8),
            // 标题
            Text(
              widget.title,
              style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w600,
                color: navTheme.textPrimary,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            // 副标题
            Text(
              widget.subtitle,
              style: theme.textTheme.bodySmall?.copyWith(
                color: navTheme.textSecondary,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPlaceholder(Color backgroundColor) {
    // 计算与背景色对比的图标颜色
    final iconColor = HSLColor.fromColor(backgroundColor).lightness > 0.5
        ? Colors.black38
        : Colors.white38;

    return Container(
      color: backgroundColor,
      child: Center(
        child: Icon(
          Icons.album,
          size: 48,
          color: iconColor,
        ),
      ),
    );
  }
}

/// 歌曲列表项（支持播放状态指示）
class NavidromeSongTile extends StatelessWidget {
  final String title;
  final String subtitle;
  final String? coverUrl;
  final String? duration;
  final bool isPlaying;
  final VoidCallback? onTap;

  const NavidromeSongTile({
    super.key,
    required this.title,
    required this.subtitle,
    this.coverUrl,
    this.duration,
    this.isPlaying = false,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final navTheme = NavidromeTheme.of(context);

    final titleColor = isPlaying ? NavidromeColors.activeBlue : navTheme.textPrimary;
    final subtitleColor = navTheme.textSecondary;

    return NavidromeCard(
      onTap: onTap,
      padding: const EdgeInsets.all(12),
      child: Row(
        children: [
          // 封面
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: SizedBox(
              width: 52,
              height: 52,
              child: coverUrl != null && coverUrl!.isNotEmpty
                  ? Image.network(
                      coverUrl!,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => _buildCoverPlaceholder(navTheme.isDark),
                    )
                  : _buildCoverPlaceholder(navTheme.isDark),
            ),
          ),
          const SizedBox(width: 12),
          // 标题和副标题
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodyLarge?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: titleColor,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: subtitleColor,
                  ),
                ),
              ],
            ),
          ),
          // 播放指示器或时长
          if (isPlaying)
            const PlayingIndicator(size: 20)
          else if (duration != null)
            Text(
              duration!,
              style: theme.textTheme.bodySmall?.copyWith(
                color: subtitleColor,
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildCoverPlaceholder(bool isDark) {
    return Container(
      color: isDark ? NavidromeColors.cardBackground : Colors.grey.shade200,
      child: Icon(
        Icons.music_note,
        color: isDark ? NavidromeColors.textSecondary : Colors.grey.shade400,
      ),
    );
  }
}

class NavidromeSongList extends StatelessWidget {
  final List<NavidromeSong> songs;
  final NavidromeApi? api;
  final EdgeInsets padding;
  final ValueChanged<int> onTap;
  final ScrollController? controller;
  final ScrollPhysics? physics;
  final bool shrinkWrap;
  final double separatorHeight;

  const NavidromeSongList({
    super.key,
    required this.songs,
    required this.api,
    required this.padding,
    required this.onTap,
    this.controller,
    this.physics,
    this.shrinkWrap = false,
    this.separatorHeight = 10,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: PlayerService(),
      builder: (context, _) {
        final currentTrack = PlayerService().currentTrack;

        return ListView.separated(
          controller: controller,
          padding: padding,
          physics: physics,
          shrinkWrap: shrinkWrap,
          itemCount: songs.length,
          separatorBuilder: (_, __) => SizedBox(height: separatorHeight),
          itemBuilder: (context, index) {
            final song = songs[index];
            final coverUrl = api?.buildCoverUrl(song.coverArt) ?? '';
            final isPlaying = currentTrack?.id == song.id;

            return NavidromeSongTile(
              title: song.title,
              subtitle: '${song.artist} · ${song.album}',
              coverUrl: coverUrl,
              duration: song.durationFormatted,
              isPlaying: isPlaying,
              onTap: () => onTap(index),
            );
          },
        );
      },
    );
  }
}

Future<void> showNavidromeAlbumSheet({
  required BuildContext context,
  required NavidromeAlbum album,
  required NavidromeApi? api,
  double initialChildSize = 0.78,
  double minChildSize = 0.55,
  double maxChildSize = 0.95,
}) {
  final navTheme = NavidromeTheme.of(context);

  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: navTheme.background,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (context) {
      return SafeArea(
        child: DraggableScrollableSheet(
          expand: false,
          initialChildSize: initialChildSize,
          minChildSize: minChildSize,
          maxChildSize: maxChildSize,
          builder: (context, controller) {
            return NavidromeAlbumSheet(
              album: album,
              api: api,
              controller: controller,
            );
          },
        ),
      );
    },
  );
}

class NavidromeAlbumSheet extends StatefulWidget {
  final NavidromeAlbum album;
  final NavidromeApi? api;
  final ScrollController controller;

  const NavidromeAlbumSheet({
    super.key,
    required this.album,
    required this.api,
    required this.controller,
  });

  @override
  State<NavidromeAlbumSheet> createState() => _NavidromeAlbumSheetState();
}

class _NavidromeAlbumSheetState extends State<NavidromeAlbumSheet> {
  List<NavidromeSong> _songs = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadSongs();
  }

  Future<void> _loadSongs() async {
    final api = widget.api;
    if (api == null) {
      setState(() {
        _loading = false;
        _error = '未配置服务器';
      });
      return;
    }

    try {
      final songs = await api.getAlbumSongs(widget.album.id);
      if (!mounted) return;
      setState(() => _songs = songs);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = '加载失败：$e');
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  void _playSongs(int index) {
    if (_songs.isEmpty) return;
    final api = widget.api;
    if (api == null) return;

    final tracks = _songs
        .map(
          (song) => Track(
            id: song.id,
            name: song.title,
            artists: song.artist,
            album: song.album,
            picUrl: api.buildCoverUrl(song.coverArt),
            source: MusicSource.navidrome,
          ),
        )
        .toList();

    PlaylistQueueService().setQueue(tracks, index, QueueSource.album);
    PlayerService().playTrack(tracks[index]);
  }

  void _playShuffled() {
    if (_songs.isEmpty) return;
    final api = widget.api;
    if (api == null) return;

    final tracks = _songs
        .map(
          (song) => Track(
            id: song.id,
            name: song.title,
            artists: song.artist,
            album: song.album,
            picUrl: api.buildCoverUrl(song.coverArt),
            source: MusicSource.navidrome,
          ),
        )
        .toList();
    tracks.shuffle();
    PlaylistQueueService().setQueue(tracks, 0, QueueSource.album);
    PlayerService().playTrack(tracks[0]);
  }

  Widget _buildCover(String coverUrl, double size) {
    final colorScheme = Theme.of(context).colorScheme;

    if (coverUrl.isEmpty) {
      return Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Icon(
          Icons.album,
          size: size * 0.5,
          color: colorScheme.onSurfaceVariant,
        ),
      );
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: Image.network(
        coverUrl,
        width: size,
        height: size,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => Container(
          width: size,
          height: size,
          color: colorScheme.surfaceContainerHighest,
          child: Icon(
            Icons.album,
            size: size * 0.5,
            color: colorScheme.onSurfaceVariant,
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final navTheme = NavidromeTheme.of(context);
    final coverUrl = widget.api?.buildCoverUrl(widget.album.coverArt) ?? '';

    return Container(
      decoration: BoxDecoration(
        color: navTheme.background,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        children: [
          const SizedBox(height: 8),
          Container(
            width: 36,
            height: 4,
            decoration: BoxDecoration(
              color: navTheme.divider,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
            child: Row(
              children: [
                _buildCover(coverUrl, 72),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.album.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        widget.album.artist,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: navTheme.textSecondary,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '${widget.album.songCount} 首歌曲${widget.album.year != null ? ' · ${widget.album.year}' : ''}',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: navTheme.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                Expanded(
                  child: FilledButton.icon(
                    onPressed: _songs.isNotEmpty ? () => _playSongs(0) : null,
                    icon: const Icon(Icons.play_arrow),
                    label: const Text('播放'),
                    style: FilledButton.styleFrom(shape: const StadiumBorder()),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton.tonalIcon(
                    onPressed: _songs.isNotEmpty ? _playShuffled : null,
                    icon: const Icon(Icons.shuffle),
                    label: const Text('随机'),
                    style: FilledButton.styleFrom(shape: const StadiumBorder()),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _error != null
                    ? Center(child: Text(_error!))
                    : NavidromeSongList(
                        songs: _songs,
                        api: widget.api,
                        controller: widget.controller,
                        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                        onTap: _playSongs,
                      ),
          ),
        ],
      ),
    );
  }
}
