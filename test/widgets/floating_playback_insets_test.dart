import 'package:cyrene_music/widgets/floating_playback_insets.dart';
import 'package:cyrene_music/widgets/mini_player.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final size in [const Size(390, 800), const Size(800, 390)]) {
    for (final systemBottom in [0.0, 34.0]) {
      for (final safeArea in [false, true]) {
        testWidgets(
          'last item stays tappable $size inset=$systemBottom safe=$safeArea',
          (tester) async {
            tester.view.physicalSize = size;
            tester.view.devicePixelRatio = 1;
            addTearDown(tester.view.resetPhysicalSize);
            addTearDown(tester.view.resetDevicePixelRatio);
            final scroll = ScrollController();
            addTearDown(scroll.dispose);
            var taps = 0;
            // Exercise appearing/disappearing playback and accessibility resizing.
            for (final state in [
              (false, 1.0),
              (true, 1.0),
              (true, 3.0),
              (false, 3.0),
            ]) {
              await tester.pumpWidget(
                MaterialApp(
                  home: MediaQuery(
                    data: MediaQueryData(
                      size: size,
                      padding: EdgeInsets.only(bottom: systemBottom),
                      textScaler: TextScaler.linear(state.$2),
                    ),
                    child: Builder(
                      builder: (context) {
                        final height = state.$1
                            ? MiniPlayer.cupertinoHeight(context)
                            : null;
                        final covered =
                            FloatingPlaybackInsets.dockBottom(systemBottom) +
                            FloatingPlaybackInsets.dockHeight +
                            (height == null
                                ? 0
                                : FloatingPlaybackInsets.playerGap + height);
                        final list = SingleChildScrollView(
                          controller: scroll,
                          padding: EdgeInsets.zero,
                          child: Column(
                            children: [
                              const SizedBox(height: 1600),
                              TextButton(
                                key: const ValueKey('last-item'),
                                onPressed: () => taps++,
                                child: const Text('最后一首'),
                              ),
                              const FloatingPlaybackBottomSpacer(),
                            ],
                          ),
                        );
                        return Scaffold(
                          body: Stack(
                            children: [
                              Positioned.fill(
                                child: FloatingPlaybackInsets.cupertino(
                                  systemBottom: systemBottom,
                                  miniPlayerHeight: height,
                                  child: safeArea
                                      ? SafeArea(child: list)
                                      : list,
                                ),
                              ),
                              Positioned(
                                bottom: 0,
                                left: 0,
                                right: 0,
                                height: covered,
                                child: const ColoredBox(
                                  key: ValueKey('overlay'),
                                  color: Colors.blue,
                                ),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                  ),
                ),
              );
              await tester.pump();
              scroll.jumpTo(scroll.position.maxScrollExtent);
              await tester.pump();
              final item = find.byKey(const ValueKey('last-item'));
              final overlay = find.byKey(const ValueKey('overlay'));
              expect(
                tester.getBottomLeft(item).dy,
                closeTo(tester.getTopLeft(overlay).dy - 16, 0.01),
              );
              final before = taps;
              await tester.tap(item);
              expect(taps, before + 1);
              expect(tester.takeException(), isNull);
            }
          },
        );
      }
    }
  }

  testWidgets('standalone routes reserve no floating dock', (tester) async {
    await tester.pumpWidget(
      const MediaQuery(
        data: MediaQueryData(padding: EdgeInsets.only(bottom: 34)),
        child: Center(child: FloatingPlaybackBottomSpacer()),
      ),
    );
    expect(
      tester.getSize(find.byType(FloatingPlaybackBottomSpacer)).height,
      50,
    );
  });
}
