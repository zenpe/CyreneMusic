import 'package:cyrene_music/models/netease_discover.dart';
import 'package:cyrene_music/widgets/cupertino/cupertino_discover_widgets.dart';
import 'package:cyrene_music/widgets/discover_playlist_card_layout.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('two-line playlist cards fit narrow grids and enlarged text', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1200, 1600));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final playlist = NeteasePlaylistSummary(
      id: 1,
      name: '这是一份需要显示两行的很长的歌单标题，测试字体放大的布局',
      coverImgUrl: '',
      creatorNickname: '创建者名字比较长',
      trackCount: 100,
      playCount: 12345,
    );
    for (final width in [320.0, 568.0, 800.0, 1200.0]) {
      for (final scale in [1.0, 1.5, 2.0, 3.0]) {
        await tester.pumpWidget(
          CupertinoApp(
            home: MediaQuery(
              data: MediaQueryData(textScaler: TextScaler.linear(scale)),
              child: CupertinoPageScaffold(
                child: Align(
                  alignment: Alignment.topLeft,
                  child: SizedBox(
                    width: width,
                    child: LayoutBuilder(
                      builder: (context, constraints) => GridView.builder(
                        gridDelegate: DiscoverPlaylistCardLayout.gridDelegate(
                          context,
                          width: constraints.maxWidth,
                          columns: width >= 800 ? 4 : 2,
                          crossAxisSpacing: 16,
                          mainAxisSpacing: 16,
                          cupertino: true,
                        ),
                        itemCount: 2,
                        itemBuilder: (context, index) =>
                            CupertinoDiscoverPlaylistCard(summary: playlist),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pump();
        expect(find.text(playlist.creatorNickname), findsNWidgets(2));
        expect(
          tester.takeException(),
          isNull,
          reason: '$width px, scale $scale',
        );
      }
    }
  });
}
