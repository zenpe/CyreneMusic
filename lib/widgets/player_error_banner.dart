import 'package:flutter/material.dart';

class PlayerErrorBanner extends StatelessWidget {
  final String? message;
  final String? details;
  final EdgeInsetsGeometry? margin;

  const PlayerErrorBanner({
    super.key,
    required this.message,
    this.details,
    this.margin,
  });

  @override
  Widget build(BuildContext context) {
    final text = message?.trim() ?? '';
    if (text.isEmpty) return const SizedBox.shrink();

    return Tooltip(
      message: details ?? text,
      child: Padding(
        padding: margin ?? EdgeInsets.zero,
        child: Row(
          children: [
            const Icon(
              Icons.info_outline_rounded,
              size: 16,
              color: Colors.white70,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                text,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: Colors.white70, fontSize: 12),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
