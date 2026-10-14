import 'package:cyrene_music/models/track.dart';
import 'package:cyrene_music/widgets/cupertino/cupertino_home_widgets.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
    'recommendation rows grow with text instead of overflowing 64px',
    (tester) async {
      final tracks = List.generate(
        5,
        (i) => Track(
          id: i,
          name: '歌曲$i',
          artists: '歌手',
          album: '',
          picUrl: '',
          source: MusicSource.netease,
        ),
      );
      for (final scale in [1.0, 1.5, 2.0, 3.0]) {
        await tester.pumpWidget(
          CupertinoApp(
            home: MediaQuery(
              data: MediaQueryData(textScaler: TextScaler.linear(scale)),
              child: CupertinoPageScaffold(
                child: Center(
                  child: SizedBox(
                    width: 320,
                    child: CupertinoGuessYouLikeSection(
                      guessYouLikeFuture: Future.value(tracks),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
        expect(find.text('1. 歌曲0 - 歌手'), findsOneWidget);
        expect(find.text('4. 歌曲3 - 歌手'), findsNothing);
        expect(tester.takeException(), isNull, reason: 'text scale $scale');
      }
    },
  );
}
