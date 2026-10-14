import 'dart:async';

import 'package:cyrene_music/models/toplist.dart';
import 'package:cyrene_music/models/track.dart';
import 'package:cyrene_music/pages/home_page/toplist_detail_loader.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Toplist chart(int count, {int id = 1}) => Toplist(
  id: id,
  name: '榜单',
  nameEn: 'chart',
  coverImgUrl: '',
  creator: '',
  trackCount: 100,
  description: '',
  tracks: List.generate(
    count,
    (i) => Track(
      id: i,
      name: '歌曲$i',
      artists: '',
      album: '',
      picUrl: '',
      source: MusicSource.netease,
    ),
  ),
);

void main() {
  testWidgets('summary is not shown as full list; fetched full queue is used', (
    tester,
  ) async {
    final result = Completer<Toplist>();
    await tester.pumpWidget(
      MaterialApp(
        home: ToplistDetailLoader(
          preview: chart(12),
          fetcher: (_, _) => result.future,
          builder: (detail) => Text('完整曲目 ${detail.tracks.length}'),
        ),
      ),
    );
    expect(find.text('完整曲目 12'), findsNothing);
    result.complete(chart(100));
    await tester.pumpAndSettle();
    expect(find.text('完整曲目 100'), findsOneWidget);
  });

  testWidgets('failure can retry and dismiss cancels the active request', (
    tester,
  ) async {
    var requests = 0;
    CancelToken? active;
    final second = Completer<Toplist>();
    await tester.pumpWidget(
      MaterialApp(
        home: ToplistDetailLoader(
          preview: chart(12),
          fetcher: (_, token) {
            active = token;
            return ++requests == 1
                ? Future.error(Exception('offline'))
                : second.future;
          },
          builder: (_) => const Text('complete'),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('完整榜单加载失败，请重试'), findsOneWidget);
    await tester.tap(find.text('重试'));
    await tester.pump();
    expect(requests, 2);
    await tester.pumpWidget(const SizedBox());
    expect(active!.isCancelled, isTrue);
    second.complete(chart(100));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('late old chart cannot replace a newer chart', (tester) async {
    final old = Completer<Toplist>();
    final newer = Completer<Toplist>();
    CancelToken? oldToken;
    Widget screen(int id) => MaterialApp(
      home: ToplistDetailLoader(
        preview: chart(12, id: id),
        fetcher: (preview, token) {
          if (preview.id == 1) {
            oldToken = token;
            return old.future;
          }
          return newer.future;
        },
        builder: (detail) => Text('chart ${detail.id}'),
      ),
    );
    await tester.pumpWidget(screen(1));
    await tester.pumpWidget(screen(2));
    expect(oldToken!.isCancelled, isTrue);
    newer.complete(chart(100, id: 2));
    await tester.pumpAndSettle();
    old.complete(chart(100));
    await tester.pumpAndSettle();
    expect(find.text('chart 2'), findsOneWidget);
    expect(find.text('chart 1'), findsNothing);
  });
}
