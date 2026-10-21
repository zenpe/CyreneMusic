import 'package:cyrene_music/widgets/wavy_split_progress_bar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
    'disabling seek clears an active drag and blocks further gestures',
    (tester) async {
      var enabled = true;
      final changes = <double>[];
      late StateSetter update;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: StatefulBuilder(
              builder: (context, setState) {
                update = setState;
                return Center(
                  child: SizedBox(
                    width: 300,
                    child: WavySplitProgressBar(
                      value: 0.2,
                      duration: const Duration(minutes: 3),
                      onChanged: enabled ? changes.add : null,
                    ),
                  ),
                );
              },
            ),
          ),
        ),
      );
      final bar = find.byType(WavySplitProgressBar);
      final gesture = await tester.startGesture(tester.getCenter(bar));
      await gesture.moveBy(const Offset(40, 0));
      await gesture.moveBy(const Offset(10, 0));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));
      expect(changes, isNotEmpty);
      expect(
        find.descendant(of: bar, matching: find.byType(Text)),
        findsOneWidget,
      );

      update(() => enabled = false);
      await tester.pump();
      expect(
        find.descendant(of: bar, matching: find.byType(Text)),
        findsNothing,
      );
      final before = changes.length;
      await gesture.moveBy(const Offset(15, 0));
      await gesture.up();
      await tester.tap(bar);
      await tester.pump(const Duration(milliseconds: 200));
      expect(changes.length, before);
      expect(
        find.descendant(of: bar, matching: find.byType(Text)),
        findsNothing,
      );

      update(() => enabled = true);
      await tester.pump();
      await tester.tap(bar);
      expect(changes.length, greaterThan(before));
      expect(tester.takeException(), isNull);
    },
  );
}
