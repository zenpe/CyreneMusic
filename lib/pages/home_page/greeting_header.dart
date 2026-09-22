import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import '../../utils/theme_manager.dart';
import '../../services/weather_service.dart';

/// 区块标题组件
class SectionTitle extends StatelessWidget {
  final String title;
  final VoidCallback? onViewAll;
  const SectionTitle({super.key, required this.title, this.onViewAll});

  @override
  Widget build(BuildContext context) {
    final themeManager = ThemeManager();
    final isCupertino = (Platform.isIOS || Platform.isAndroid) && themeManager.isCupertinoFramework;
    final cs = Theme.of(context).colorScheme;

    return Padding(
      padding: EdgeInsets.only(bottom: isCupertino ? 12.0 : 16.0),
      child: Row(
        children: [
          Expanded(
            child: Text(
              title,
              style: isCupertino
                  ? const TextStyle(fontSize: 22, fontWeight: FontWeight.bold, letterSpacing: -0.5)
                  : Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800, letterSpacing: -0.5),
            ),
          ),
          if (onViewAll != null)
            TextButton(
              onPressed: onViewAll,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('查看全部', style: TextStyle(color: cs.primary)),
                  const SizedBox(width: 4),
                  Icon(Icons.arrow_forward_ios, size: 12, color: cs.primary),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// 顶部问候语组件
class GreetingHeader extends StatelessWidget {
  const GreetingHeader({super.key});

  String _greetText(TimeOfDay now) {
    final minutes = now.hour * 60 + now.minute;
    if (minutes < 6 * 60) return '夜深了';
    if (minutes < 9 * 60) return '早上好';
    if (minutes < 12 * 60) return '上午好';
    if (minutes < 14 * 60) return '中午好';
    if (minutes < 18 * 60) return '下午好';
    return '晚上好';
  }

  String _subGreeting(TimeOfDay now) {
    final h = now.hour;
    if (h < 6) return '注意休息，音乐轻声一点';
    if (h < 9) return '新的一天，从此开始好心情';
    if (h < 12) return '愿音乐伴你高效工作';
    if (h < 14) return '午后小憩，来点轻松的旋律';
    if (h < 18) return '忙碌之余，听听喜欢的歌';
    return '夜色温柔，音乐更动听';
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final themeManager = ThemeManager();
    final isCupertino = (Platform.isIOS || Platform.isAndroid) && themeManager.isCupertinoFramework;
    final now = TimeOfDay.now();

    return Padding(
      padding: const EdgeInsets.only(top: 8.0, bottom: 8.0),
      child: Row(
        children: [
          Icon(
            isCupertino ? CupertinoIcons.sun_max_fill : Icons.wb_twilight_rounded,
            color: isCupertino ? ThemeManager.iosBlue : cs.primary,
            size: isCupertino ? 24 : 28,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _greetText(now),
                  style: isCupertino
                      ? const TextStyle(fontSize: 22, fontWeight: FontWeight.bold, letterSpacing: -0.5)
                      : Theme.of(context).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w900, letterSpacing: -1.0),
                ),
                const SizedBox(height: 4),
                Text(
                  _subGreeting(now),
                  style: isCupertino
                      ? TextStyle(fontSize: 14, color: CupertinoColors.systemGrey)
                      : Theme.of(context).textTheme.bodyLarge?.copyWith(
                          color: cs.onSurfaceVariant.withValues(alpha: 0.8),
                          fontWeight: FontWeight.w500,
                        ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          FutureBuilder<String?>(
            future: WeatherService().fetchWeatherText(),
            builder: (context, snap) {
              final txt = snap.data?.toString();
              if (txt == null || txt.isEmpty) return const SizedBox.shrink();
              return Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(isCupertino ? CupertinoIcons.sun_max : Icons.wb_sunny_rounded,
                    size: 16, color: isCupertino ? CupertinoColors.systemGrey : cs.onSurfaceVariant),
                  const SizedBox(width: 6),
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 220),
                    child: Text(txt, maxLines: 1, overflow: TextOverflow.ellipsis,
                      style: isCupertino
                          ? TextStyle(fontSize: 14, color: CupertinoColors.systemGrey)
                          : Theme.of(context).textTheme.bodyMedium?.copyWith(color: cs.onSurfaceVariant)),
                  ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}
