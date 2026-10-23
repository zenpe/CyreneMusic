import 'dart:async';
import 'package:cyrene_music/widgets/terms_consent.dart';
import 'package:flutter/material.dart';
import 'package:fluent_ui/fluent_ui.dart' as fluent;
import 'package:flutter_test/flutter_test.dart';

void main() {
  Future<void> mount(
    WidgetTester tester, {
    bool accepted = false,
    bool fluentStyle = false,
    required Future<void> Function() save,
    required VoidCallback submit,
  }) async {
    final body = TermsConsentScope(
      initiallyAccepted: accepted,
      saveAcceptance: save,
      child: Builder(
        builder: (context) => Column(
          children: [
            TermsConsentTile(fluentStyle: fluentStyle),
            if (fluentStyle)
              fluent.FilledButton(
                onPressed: () async {
                  if (await TermsConsentScope.ensureAccepted(context)) submit();
                },
                child: const Text('提交'),
              )
            else
              FilledButton(
                onPressed: () async {
                  if (await TermsConsentScope.ensureAccepted(context)) submit();
                },
                child: const Text('提交'),
              ),
          ],
        ),
      ),
    );
    await tester.pumpWidget(
      fluentStyle
          ? fluent.FluentApp(home: fluent.ScaffoldPage(content: body))
          : MaterialApp(home: Scaffold(body: body)),
    );
  }

  for (final fluentStyle in [false, true]) {
    testWidgets('unchecked agreement blocks submission (fluent=$fluentStyle)', (
      tester,
    ) async {
      var saves = 0;
      var submits = 0;
      await mount(
        tester,
        fluentStyle: fluentStyle,
        save: () async {
          saves++;
        },
        submit: () => submits++,
      );
      await tester.tap(find.text('提交'));
      await tester.pumpAndSettle();
      expect(saves, 0);
      expect(submits, 0);
      expect(find.text('请先阅读并同意使用协议'), findsOneWidget);
    });
  }

  testWidgets('consent is saved only on submit and failure is retryable', (
    tester,
  ) async {
    var saves = 0;
    var submits = 0;
    await mount(
      tester,
      save: () async {
        if (++saves == 1) throw StateError('storage unavailable');
      },
      submit: () => submits++,
    );
    await tester.tap(find.byType(Checkbox));
    await tester.pump();
    expect(saves, 0);
    await tester.tap(find.text('提交'));
    await tester.pump();
    expect(submits, 0);
    expect(find.text('协议确认保存失败，请重试'), findsOneWidget);
    await tester.tap(find.text('提交'));
    await tester.pump();
    expect(saves, 2);
    expect(submits, 1);
  });

  testWidgets('existing acceptance needs no new checkbox or storage write', (
    tester,
  ) async {
    var saves = 0;
    var submits = 0;
    await mount(
      tester,
      accepted: true,
      save: () async {
        saves++;
      },
      submit: () => submits++,
    );
    await tester.tap(find.text('提交'));
    await tester.pump();
    expect(saves, 0);
    expect(submits, 1);
    expect(find.text('已确认'), findsOneWidget);
  });

  testWidgets('pending consent save blocks duplicate submissions', (
    tester,
  ) async {
    final saved = Completer<void>();
    var saves = 0;
    var submits = 0;
    await mount(
      tester,
      save: () {
        saves++;
        return saved.future;
      },
      submit: () => submits++,
    );
    await tester.tap(find.byType(Checkbox));
    await tester.pump();
    await tester.tap(find.text('提交'));
    await tester.pump();
    await tester.tap(find.text('提交'));
    await tester.pump();
    expect(saves, 1);
    expect(submits, 0);
    saved.complete();
    await tester.pump();
    expect(submits, 1);
  });

  testWidgets('reading agreement does not accept it', (tester) async {
    var saves = 0;
    await mount(
      tester,
      save: () async {
        saves++;
      },
      submit: () {},
    );
    await tester.tap(find.text('使用协议'));
    await tester.pumpAndSettle();
    expect(find.text('关闭'), findsOneWidget);
    expect(saves, 0);
    await tester.tap(find.text('关闭'));
    await tester.pumpAndSettle();
    expect(tester.widget<Checkbox>(find.byType(Checkbox)).value, false);
  });
}
