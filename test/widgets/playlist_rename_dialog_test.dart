import 'dart:async';

import 'package:cyrene_music/widgets/playlist_rename_dialog.dart';
import 'package:fluent_ui/fluent_ui.dart' as fluent;
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final style in PlaylistRenameStyle.values) {
    testWidgets(
      'rename trims input, blocks duplicate submits and closes on success ($style)',
      (tester) async {
        final pending = Completer<bool>();
        final names = <String>[];
        bool? saved;
        await _open(tester, style, (name) {
          names.add(name);
          return pending.future;
        }, (value) => saved = value);
        expect(find.text('原名称'), findsOneWidget);
        await tester.enterText(find.byType(EditableText), '  新名称  ');
        await tester.pump();
        await tester.tap(find.text('保存'));
        await tester.pump();
        expect(names, ['新名称']);
        expect(find.text('保存中…'), findsOneWidget);
        await tester.tap(find.text('保存中…'));
        await tester.tap(find.text('取消'));
        await tester.pump();
        expect(names, ['新名称']);
        expect(find.text('重命名歌单'), findsOneWidget);
        pending.complete(true);
        await tester.pumpAndSettle();
        expect(saved, isTrue);
        expect(find.text('重命名歌单'), findsNothing);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('failure retains input and allows retry', (tester) async {
    var attempts = 0;
    await _open(
      tester,
      PlaylistRenameStyle.material,
      (_) async => ++attempts > 1,
      (_) {},
    );
    await tester.enterText(find.byType(EditableText), '新名称');
    await tester.pump();
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();
    expect(find.text('保存失败，请稍后重试'), findsOneWidget);
    expect(find.text('新名称'), findsOneWidget);
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();
    expect(attempts, 2);
    expect(find.text('重命名歌单'), findsNothing);
  });

  testWidgets(
    'unchanged and blank names do not submit; cancel makes no request',
    (tester) async {
      var calls = 0;
      await _open(tester, PlaylistRenameStyle.material, (_) async {
        calls++;
        return true;
      }, (_) {});
      await tester.tap(find.text('保存'));
      await tester.enterText(find.byType(EditableText), '   ');
      await tester.pump();
      await tester.tap(find.text('保存'));
      expect(calls, 0);
      await tester.tap(find.text('取消'));
      await tester.pumpAndSettle();
      expect(calls, 0);
      expect(find.text('重命名歌单'), findsNothing);
    },
  );
}

Future<void> _open(
  WidgetTester tester,
  PlaylistRenameStyle style,
  Future<bool> Function(String) save,
  void Function(bool?) result,
) async {
  final body = Builder(
    builder: (context) => Center(
      child: GestureDetector(
        onTap: () async => result(
          await PlaylistRenameDialog.show(
            context,
            name: '原名称',
            onSave: save,
            style: style,
          ),
        ),
        child: const Text('打开'),
      ),
    ),
  );
  await tester.pumpWidget(switch (style) {
    PlaylistRenameStyle.material => MaterialApp(home: Scaffold(body: body)),
    PlaylistRenameStyle.cupertino => CupertinoApp(
      home: CupertinoPageScaffold(child: body),
    ),
    PlaylistRenameStyle.fluent => fluent.FluentApp(
      home: fluent.ScaffoldPage(content: body),
    ),
  });
  await tester.tap(find.text('打开'));
  await tester.pumpAndSettle();
}
