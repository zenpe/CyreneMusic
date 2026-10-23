import 'package:cyrene_music/main.dart';
import 'package:cyrene_music/utils/toast_utils.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluttertoast/fluttertoast.dart';

void main() {
  testWidgets(
    'error toast follows the current app after its navigator is rebuilt',
    (tester) async {
      Widget app() => MaterialApp(
        navigatorKey: MyApp.navigatorKey,
        builder: FToastBuilder(),
        home: const Scaffold(body: Text('home')),
      );

      await tester.pumpWidget(app());
      ToastUtils.error('first failure');
      await tester.pump();
      expect(find.text('first failure'), findsOneWidget);
      await tester.pump(const Duration(seconds: 4));
      await tester.pump(const Duration(seconds: 1));
      await tester.pumpWidget(const SizedBox());
      await tester.pumpWidget(app());

      ToastUtils.error('network unavailable');
      await tester.pump();
      expect(find.text('network unavailable'), findsOneWidget);
      expect(tester.takeException(), isNull);

      // Also replace the app while a toast's entry/timer is still active.
      await tester.pumpWidget(const SizedBox());
      await tester.pumpWidget(app());
      ToastUtils.error('retry failed');
      await tester.pump();
      expect(find.text('retry failed'), findsOneWidget);
      expect(tester.takeException(), isNull);
      FToast().removeQueuedCustomToasts();
      await tester.pump();
    },
  );
}
