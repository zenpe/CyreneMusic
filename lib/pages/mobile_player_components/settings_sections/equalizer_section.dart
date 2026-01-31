import 'package:flutter/material.dart';
import '../mobile_player_settings_sheet.dart';
import '../../settings_page/equalizer_page.dart';

class EqualizerSection extends StatelessWidget {
  const EqualizerSection({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
          child: Text(
            '音效',
            style: TextStyle(
              color: colorScheme.primary,
              fontSize: 14,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        ListTile(
          contentPadding: const EdgeInsets.symmetric(horizontal: 24),
          leading: Icon(Icons.graphic_eq, color: colorScheme.onSurfaceVariant),
          title: const Text('均衡器'),
          subtitle: const Text('自定义音频频率响应'),
          trailing: const Icon(Icons.chevron_right),
          onTap: () {
            // 关闭底部弹出板
            Navigator.pop(context);
            // 跳转到均衡器页面
            Navigator.push(
              context, 
              MaterialPageRoute(builder: (_) => const EqualizerPage())
            );
          },
        ),
      ],
    );
  }
}
