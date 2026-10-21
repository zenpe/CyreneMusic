import 'package:cyrene_music/widgets/playback_switch_ring.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
    'buffering ring preserves the pause button size and interaction',
    (tester) async {
      var taps = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: PlaybackSwitchRing(
                isVisible: true,
                color: Colors.blue,
                child: SizedBox(
                  width: 48,
                  height: 48,
                  child: IconButton(
                    onPressed: () => taps++,
                    icon: const Icon(Icons.pause),
                    tooltip: '暂停',
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(
        tester.getSize(find.byType(PlaybackSwitchRing)),
        const Size(48, 48),
      );
      await tester.tap(find.byIcon(Icons.pause));
      expect(taps, 1);
    },
  );
}
