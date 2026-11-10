import 'package:cyrene_music/services/developer_mode_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  Future<DeveloperModeService> create({bool enabled = true}) async {
    SharedPreferences.setMockInitialValues({'developer_mode': enabled});
    final service = DeveloperModeService.forTesting();
    await service.initialize();
    addTearDown(service.dispose);
    return service;
  }

  testWidgets('ordinary mode neither collects nor prepares detailed logs', (
    tester,
  ) async {
    final service = await create(enabled: false);
    var settingsEvents = 0, logEvents = 0, prepared = 0;
    service.addListener(() => settingsEvents++);
    service.logChanges.addListener(() => logEvents++);
    service.addLog('ignored');
    service.addLogLazy(() {
      prepared++;
      return 'expensive diagnostics';
    });
    await tester.pump(const Duration(seconds: 1));
    expect(service.logs, isEmpty);
    expect(prepared, 0);
    expect(logEvents, 0);
    expect(settingsEvents, 0);
  });

  testWidgets(
    'log bursts rebuild only the log view and settings still update the root',
    (tester) async {
      final service = await create();
      var rootBuilds = 0, logBuilds = 0;
      final logView = AnimatedBuilder(
        animation: service.logChanges,
        builder: (_, _) {
          logBuilds++;
          return Text(service.logs.last, textDirection: TextDirection.ltr);
        },
      );
      await tester.pumpWidget(
        AnimatedBuilder(
          animation: service,
          child: logView,
          builder: (_, child) {
            rootBuilds++;
            return child!;
          },
        ),
      );
      for (var i = 0; i < 100; i++) {
        service.addLog('request $i');
      }
      await tester.pump(const Duration(milliseconds: 99));
      expect(rootBuilds, 1);
      expect(logBuilds, 1);
      await tester.pump(const Duration(milliseconds: 1));
      expect(rootBuilds, 1);
      expect(logBuilds, 2);
      expect(find.textContaining('request 99'), findsOneWidget);
      await service.togglePerformanceOverlay(true);
      await tester.pump();
      expect(rootBuilds, 2);
      expect(service.showPerformanceOverlay, isTrue);
      await tester.pump(const Duration(milliseconds: 100));
      expect(logBuilds, 3);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'retains the latest 1000 entries in order and returns immutable snapshots',
    (tester) async {
      final service = await create();
      for (var i = 0; i < 1200; i++) {
        service.addLog('entry $i');
      }
      final snapshot = service.logs;
      expect(snapshot, hasLength(1000));
      expect(snapshot.first, endsWith('entry 200'));
      expect(snapshot.last, endsWith('entry 1199'));
      expect(() => snapshot.add('mutation'), throwsUnsupportedError);
      service.addLogLazy(() => 'next entry');
      expect(snapshot.last, endsWith('entry 1199'));
      expect(service.logs.last, endsWith('next entry'));
      // No log view is mounted: collection must not request a frame.
      expect(tester.binding.hasScheduledFrame, isFalse);
    },
  );

  testWidgets(
    'clear batches with pending logs without notifying settings listeners',
    (tester) async {
      final service = await create();
      var settingsEvents = 0, logEvents = 0;
      service.addListener(() => settingsEvents++);
      service.logChanges.addListener(() => logEvents++);
      service.addLog('old');
      service.clearLogs();
      await tester.pump(const Duration(milliseconds: 100));
      expect(service.logs, hasLength(1));
      expect(service.logs.single, contains('日志已清除'));
      expect(logEvents, 1);
      expect(settingsEvents, 0);
    },
  );

  testWidgets(
    'disable releases buffered logs and stops collection immediately',
    (tester) async {
      final service = await create();
      var settingsEvents = 0, logEvents = 0;
      service.addListener(() => settingsEvents++);
      service.logChanges.addListener(() => logEvents++);
      service.addLog('pending');
      final disabling = service.disableDeveloperMode();
      expect(service.isDeveloperMode, isFalse);
      expect(service.logs, isEmpty);
      service.addLog('late request');
      await disabling;
      await tester.pump(const Duration(milliseconds: 100));
      expect(settingsEvents, 1);
      expect(logEvents, 1);
      expect(service.logs, isEmpty);
      expect(
        (await SharedPreferences.getInstance()).getBool('developer_mode'),
        isFalse,
      );
      await tester.pump(const Duration(seconds: 1));
      expect(logEvents, 1);
    },
  );

  testWidgets(
    'disposing with a pending refresh does not notify released listeners',
    (tester) async {
      SharedPreferences.setMockInitialValues({'developer_mode': true});
      final service = DeveloperModeService.forTesting();
      await service.initialize();
      var events = 0;
      service.logChanges.addListener(() => events++);
      service.addLog('pending');
      service.dispose();
      await tester.pump(const Duration(seconds: 1));
      expect(events, 0);
      expect(tester.takeException(), isNull);
    },
  );
}
