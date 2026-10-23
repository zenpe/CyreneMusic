import 'package:cyrene_music/widgets/mini_player.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('floating height accommodates scaled title and artist', (
    tester,
  ) async {
    for (final scale in [1.0, 1.5, 2.0, 3.0]) {
      late double height;
      await tester.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: MediaQueryData(textScaler: TextScaler.linear(scale)),
            child: Builder(
              builder: (context) {
                height = MiniPlayer.cupertinoHeight(context);
                return Center(
                  child: SizedBox(
                    width: 320,
                    height: height,
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(10, 4, 10, 8),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Text(
                            '歌曲标题 Title',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(fontSize: 13.5, height: 1.2),
                          ),
                          const SizedBox(height: 1.5),
                          const Text(
                            '歌手 Artist',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(fontSize: 11.5, height: 1.2),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ),
      );
      expect(height, greaterThanOrEqualTo(52));
      expect(tester.takeException(), isNull, reason: 'text scale $scale');
    }
  });
}
