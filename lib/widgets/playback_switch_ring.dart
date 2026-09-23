import 'package:flutter/material.dart';

/// Adds a subtle loading ring without replacing or moving the playback icon.
///
/// The ring is painted inside the child's bounds so the control keeps the
/// same layout size while switching tracks.
class PlaybackSwitchRing extends StatelessWidget {
  final Widget child;
  final bool isVisible;
  final Color color;
  final double strokeWidth;
  final double inset;

  const PlaybackSwitchRing({
    super.key,
    required this.child,
    required this.isVisible,
    required this.color,
    this.strokeWidth = 2,
    this.inset = 2,
  });

  @override
  Widget build(BuildContext context) {
    return Stack(
      alignment: Alignment.center,
      children: [
        child,
        Positioned.fill(
          child: IgnorePointer(
            child: AnimatedOpacity(
              opacity: isVisible ? 1 : 0,
              duration: const Duration(milliseconds: 160),
              curve: Curves.easeOut,
              child: Padding(
                padding: EdgeInsets.all(inset),
                child: CircularProgressIndicator(
                  strokeWidth: strokeWidth,
                  color: color,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
