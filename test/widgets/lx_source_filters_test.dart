import 'package:cyrene_music/widgets/lx_source_filters.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
    'directory hierarchy expands, searches deep paths and selects a parent',
    (tester) async {
      String? selected;
      var query = '';
      await tester.pumpWidget(
        CupertinoApp(
          home: CupertinoPageScaffold(
            child: StatefulBuilder(
              builder: (context, setState) => LxSourceFilters(
                directories: const ['公益', '公益/网易', '公益/网易/备用', '备用'],
                selectedDirectory: selected,
                onQueryChanged: (value) => query = value,
                onDirectoryChanged: (value) => setState(() => selected = value),
              ),
            ),
          ),
        ),
      );
      await tester.enterText(
        find.byType(CupertinoSearchTextField).first,
        'HYW',
      );
      expect(query, 'HYW');
      await tester.tap(find.text('目录：全部音源 ▾'));
      await tester.pump();
      expect(find.text('网易'), findsNothing);
      await tester.tap(find.byIcon(CupertinoIcons.chevron_right).first);
      await tester.pump();
      expect(find.text('网易'), findsOneWidget);
      await tester.tap(find.text('公益'));
      await tester.pump();
      expect(selected, '公益');
      await tester.tap(find.text('目录：公益 ▾'));
      await tester.pump();
      await tester.enterText(
        find.byType(CupertinoSearchTextField).last,
        '网易/备用',
      );
      await tester.pump();
      await tester.ensureVisible(find.text('公益/网易/备用'));
      await tester.tap(find.text('公益/网易/备用'));
      await tester.pump();
      expect(selected, '公益/网易/备用');
      expect(tester.takeException(), isNull);
    },
  );
}
