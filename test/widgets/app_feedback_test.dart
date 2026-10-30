import 'dart:ui';
import 'package:cyrene_music/utils/app_feedback.dart';
import 'package:cyrene_music/widgets/feedback_boundary.dart';
import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late BuildContext page;
  final navigator = GlobalKey<NavigatorState>();
  Widget app({Widget? child, MediaQueryData? media, ThemeData? theme}) =>
      MaterialApp(
        navigatorKey: navigator,
        theme: theme,
        navigatorObservers: [FeedbackNavigatorObserver()],
        builder: media == null
            ? null
            : (_, child) => MediaQuery(data: media, child: child!),
        home: Scaffold(
          body: Builder(
            builder: (context) {
              page = context;
              return child ?? const Text('page');
            },
          ),
        ),
      );
  tearDown(AppFeedback.dismissAll);
  testWidgets('rapid ordinary feedback replaces, never drains a queue', (
    tester,
  ) async {
    await tester.pumpWidget(app());
    for (var i = 0; i < 10; i++) {
      AppFeedback.of(page).info('message $i');
    }
    await tester.pump();
    expect(find.text('message 9'), findsOneWidget);
    expect(find.text('message 0'), findsNothing);
    await tester.pump(const Duration(seconds: 3));
    expect(find.byKey(const ValueKey('app-feedback-surface')), findsNothing);
    await tester.pump(const Duration(seconds: 30));
    expect(find.byKey(const ValueKey('app-feedback-surface')), findsNothing);
  });
  testWidgets(
    'duplicate does not extend lifetime; changed operation result replaces',
    (tester) async {
      await tester.pumpWidget(app());
      AppFeedback.of(page).info('one', operationKey: 'mode');
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      AppFeedback.of(page).info('one', operationKey: 'mode');
      await tester.pump(const Duration(milliseconds: 1100));
      expect(find.text('one'), findsNothing);
      AppFeedback.of(page).info('one', operationKey: 'mode');
      await tester.pump();
      AppFeedback.of(page).info('two', operationKey: 'mode');
      await tester.pump();
      expect(find.text('two'), findsOneWidget);
    },
  );
  testWidgets('ordinary messages cannot hide a recoverable error', (
    tester,
  ) async {
    var retries = 0;
    await tester.pumpWidget(app());
    AppFeedback.of(page).error(
      'failed',
      onRetry: () {
        retries++;
      },
    );
    await tester.pump();
    AppFeedback.of(page).info('copied');
    await tester.pump();
    expect(find.text('failed'), findsOneWidget);
    expect(find.text('copied'), findsNothing);
    await tester.tap(find.text('重试'));
    await tester.pump();
    expect(retries, 1);
    expect(find.text('failed'), findsNothing);
  });
  testWidgets('error without action lasts five seconds and can be dismissed', (
    tester,
  ) async {
    await tester.pumpWidget(app());
    AppFeedback.of(page).error('failed');
    await tester.pump();
    await tester.pump(const Duration(seconds: 3));
    expect(find.text('failed'), findsOneWidget);
    await tester.tap(find.byTooltip('关闭提示'));
    await tester.pump();
    expect(find.text('failed'), findsNothing);
  });
  testWidgets('route navigation clears feedback', (tester) async {
    await tester.pumpWidget(app());
    AppFeedback.of(page).info('old page');
    await tester.pump();
    navigator.currentState!.push(
      MaterialPageRoute<void>(
        builder: (_) => const Scaffold(body: Text('next')),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('old page'), findsNothing);
    navigator.currentState!.pop();
    await tester.pumpAndSettle();
  });
  testWidgets('notifications are nonmodal and do not block page interaction', (
    tester,
  ) async {
    var taps = 0;
    await tester.pumpWidget(
      app(
        child: Center(
          child: TextButton(
            onPressed: () {
              taps++;
            },
            child: const Text('underlying'),
          ),
        ),
      ),
    );
    AppFeedback.of(page).info('notice');
    await tester.pump();
    await tester.tap(find.text('underlying'));
    expect(taps, 1);
    expect(navigator.currentState!.canPop(), isFalse);
  });
  testWidgets('accessibility keeps message until explicitly dismissed', (
    tester,
  ) async {
    await tester.pumpWidget(
      app(
        media: const MediaQueryData(
          size: Size(800, 600),
          accessibleNavigation: true,
        ),
      ),
    );
    AppFeedback.of(page).info('accessible');
    await tester.pump();
    await tester.pump(const Duration(seconds: 30));
    expect(find.text('accessible'), findsOneWidget);
    await tester.tap(find.byTooltip('关闭提示'));
    await tester.pump();
    expect(find.text('accessible'), findsNothing);
  });
  testWidgets('pointer hover pauses timeout', (tester) async {
    await tester.pumpWidget(app());
    AppFeedback.of(page).info('hover');
    await tester.pump();
    final pointer = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await pointer.addPointer(location: Offset.zero);
    await pointer.moveTo(tester.getCenter(find.text('hover')));
    await tester.pump(const Duration(seconds: 5));
    expect(find.text('hover'), findsOneWidget);
    await pointer.moveTo(Offset.zero);
    await tester.pump(const Duration(seconds: 3));
    expect(find.text('hover'), findsNothing);
    await pointer.removePointer();
  });
  testWidgets(
    'real player geometry and keyboard stay clear at large text scale',
    (tester) async {
      tester.view.physicalSize = const Size(320, 760);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        app(
          media: const MediaQueryData(
            size: Size(320, 760),
            textScaler: TextScaler.linear(2),
          ),
          child: const Align(
            alignment: Alignment.bottomCenter,
            child: FeedbackAvoidance(
              child: SizedBox(key: ValueKey('dock'), width: 320, height: 140),
            ),
          ),
        ),
      );
      await tester.pump();
      AppFeedback.of(
        page,
      ).error('This is a longer recoverable message that must wrap safely.');
      await tester.pump();
      final surface = find.byKey(const ValueKey('app-feedback-surface'));
      expect(
        tester.getBottomLeft(surface).dy,
        lessThan(tester.getTopLeft(find.byKey(const ValueKey('dock'))).dy),
      );
      expect(tester.takeException(), isNull);
      AppFeedback.dismissAll();
      await tester.pumpWidget(
        app(
          media: const MediaQueryData(
            size: Size(320, 760),
            viewInsets: EdgeInsets.only(bottom: 300),
          ),
        ),
      );
      AppFeedback.of(page).info('keyboard');
      await tester.pump();
      expect(tester.getBottomLeft(surface).dy, lessThanOrEqualTo(460));
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets('Cupertino toast does not open a route or modal barrier', (
    tester,
  ) async {
    await tester.pumpWidget(
      CupertinoApp(
        navigatorObservers: [FeedbackNavigatorObserver()],
        home: CupertinoPageScaffold(
          child: Builder(
            builder: (context) {
              page = context;
              return const Text('cupertino');
            },
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final barriers = find.byType(ModalBarrier).evaluate().length;
    AppFeedback.of(page).info('nonmodal');
    await tester.pump();
    expect(find.text('nonmodal'), findsOneWidget);
    expect(find.byType(ModalBarrier).evaluate().length, barriers);
    expect(tester.takeException(), isNull);
  });
}
