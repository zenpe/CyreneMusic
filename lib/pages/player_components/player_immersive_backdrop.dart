import 'dart:ui';

import 'package:flutter/material.dart';

import 'player_fluid_cloud_background.dart';

class PlayerImmersiveBackdrop extends StatelessWidget {
  final bool reducedEffects;

  const PlayerImmersiveBackdrop({super.key, required this.reducedEffects});

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: Stack(
        fit: StackFit.expand,
        children: [
          PlayerFluidCloudBackground(reducedEffects: reducedEffects),
          BackdropFilter(
            filter: ImageFilter.blur(
              sigmaX: reducedEffects ? 8 : 30,
              sigmaY: reducedEffects ? 8 : 30,
            ),
            child: ColoredBox(color: Colors.black.withOpacity(0.3)),
          ),
        ],
      ),
    );
  }
}
