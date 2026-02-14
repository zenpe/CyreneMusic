import 'package:flutter/material.dart';

class PlayerErrorBanner extends StatelessWidget {
  final String? message;
  final VoidCallback? onRetry;
  final VoidCallback? onSkip;
  final bool showSkip;
  final EdgeInsetsGeometry? margin;

  const PlayerErrorBanner({
    super.key,
    required this.message,
    this.onRetry,
    this.onSkip,
    this.showSkip = false,
    this.margin,
  });

  @override
  Widget build(BuildContext context) {
    final text = message?.trim() ?? '';
    if (text.isEmpty) return const SizedBox.shrink();

    return Container(
      width: double.infinity,
      margin: margin,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.redAccent.withOpacity(0.2),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.redAccent.withOpacity(0.45)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              text,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 11,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          if (onRetry != null) ...[
            const SizedBox(width: 8),
            TextButton(
              onPressed: onRetry,
              style: TextButton.styleFrom(
                foregroundColor: Colors.white,
                minimumSize: const Size(40, 30),
                padding: const EdgeInsets.symmetric(horizontal: 8),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              child: const Text('重试'),
            ),
          ],
          if (showSkip && onSkip != null) ...[
            const SizedBox(width: 2),
            TextButton(
              onPressed: onSkip,
              style: TextButton.styleFrom(
                foregroundColor: Colors.white70,
                minimumSize: const Size(40, 30),
                padding: const EdgeInsets.symmetric(horizontal: 8),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              child: const Text('下一首'),
            ),
          ],
        ],
      ),
    );
  }
}
