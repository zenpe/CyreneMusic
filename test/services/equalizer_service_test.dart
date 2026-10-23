import 'dart:async';
import 'dart:io';

import 'package:cyrene_music/models/equalizer_state.dart';
import 'package:cyrene_music/services/equalizer_service.dart';
import 'package:cyrene_music/services/persistent_storage_service.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class TestEqualizer implements EqualizerCapable {
  final calls = <List<double>>[];
  Completer<void>? blocker;
  bool fail = false;
  @override
  bool get supportsEqualizer => true;
  @override
  Future<void> applyEqualizer(
    bool enabled,
    List<double> gains,
    List<int> frequencies,
  ) async {
    calls.add(List.of(gains));
    await blocker?.future;
    if (fail) throw StateError('effect unavailable');
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('plugins.flutter.io/path_provider');
  final storage = PersistentStorageService();
  late Directory directory;
  late EqualizerService service;
  late TestEqualizer backend;
  setUpAll(() async {
    directory = await Directory.systemTemp.createTemp('cyrene_eq_test_');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (_) async => directory.path);
    SharedPreferences.setMockInitialValues({});
    await storage.initialize();
  });
  setUp(() {
    service = EqualizerService.forTest();
    backend = TestEqualizer();
    service.setBackend(backend);
  });
  tearDown(() async {
    service.dispose();
    await storage.clear();
  });
  tearDownAll(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
    await directory.delete(recursive: true);
  });

  test('curve interpolation uses logarithmic frequency and device range', () {
    expect(
      mapEqualizerCurve(
        [100, 400],
        [-8, 8],
        const EqualizerCapabilities([50, 200, 800], -6, 6),
      ),
      [-6, 0, 6],
    );
  });

  test('malformed curves and capabilities are rejected', () {
    for (final frequencies in [
      [100, 100],
      [400, 100],
      [0, 100],
    ]) {
      expect(
        () => mapEqualizerCurve(frequencies, [
          0,
          1,
        ], EqualizerCapabilities.standard),
        throwsFormatException,
      );
    }
    expect(
      () => mapEqualizerCurve(
        [100],
        [double.nan],
        EqualizerCapabilities.standard,
      ),
      throwsFormatException,
    );
    expect(
      () => EqualizerCapabilities.fromMap({
        'frequencies': [100, 50],
        'minGain': -12,
        'maxGain': 12,
      }),
      throwsFormatException,
    );
  });

  test(
    'legacy migration preserves frequencies and sanitizes invalid gains',
    () async {
      await storage.setStringList('player_eq_gains', [
        'NaN',
        'Infinity',
        '20',
        '-20',
        '1',
        '2',
        '3',
        '4',
        '5',
        '6',
      ]);
      service.loadSettings();
      await service.flushSettings();
      expect(service.equalizerGains, [0, 0, 12, -12, 1, 2, 3, 4, 5, 6]);
      expect(storage.getString('player_eq_curve_v2'), contains('16000'));
    },
  );

  test('device changes resample without destroying stored curve', () async {
    final curve = List.generate(10, (i) => i.toDouble());
    await service.applyPreset(curve);
    service.report(
      backend,
      EqualizerStatus.bypassed,
      capabilities: const EqualizerCapabilities(
        [60, 230, 910, 3600, 14000],
        -6,
        6,
      ),
    );
    expect(service.equalizerGains.length, 5);
    expect(service.equalizerGains.last, 6);
    service.report(
      backend,
      EqualizerStatus.applied,
      capabilities: EqualizerCapabilities.standard,
    );
    expect(service.equalizerGains, curve);
    await service.flushSettings();
    final restored = EqualizerService.forTest()..setBackend(backend);
    restored.loadSettings();
    expect(restored.equalizerGains, curve);
    restored.dispose();
  });

  test('failed application does not lose user settings', () async {
    backend.fail = true;
    await service.updateEqualizer(List.filled(10, 3));
    await service.applyEqualizer();
    await service.flushSettings();
    expect(service.canRetry, isTrue);
    expect(storage.getString('player_eq_curve_v2'), contains('3.0'));
    expect(service.equalizerGains, List.filled(10, 3));
  });

  test(
    'rapid changes coalesce and only latest pending curve applies',
    () async {
      backend.blocker = Completer<void>();
      await service.updateEqualizer(List.filled(10, 1));
      final work = service.applyEqualizer();
      await Future<void>.delayed(Duration.zero);
      await service.updateEqualizer(List.filled(10, 2));
      await service.updateEqualizer(List.filled(10, 3));
      backend.blocker!.complete();
      await work;
      expect(backend.calls.map((g) => g.first), [1, 3]);
    },
  );

  test('old backend cannot hold new backend or report stale status', () async {
    backend.blocker = Completer<void>();
    final oldWork = service.applyEqualizer();
    await Future<void>.delayed(Duration.zero);
    final replacement = TestEqualizer();
    service.setBackend(replacement);
    await service.applyEqualizer();
    expect(replacement.calls.length, 1);
    service.report(replacement, EqualizerStatus.bypassed);
    service.report(backend, EqualizerStatus.failed);
    expect(service.canRetry, isFalse);
    backend.blocker!.complete();
    await oldWork;
    expect(replacement.calls.length, 1);
  });

  test(
    'late result from older settings cannot overwrite current intent',
    () async {
      final oldRevision = service.revision;
      await service.updateEqualizer(List.filled(10, 4));
      service.report(backend, EqualizerStatus.failed, revision: oldRevision);
      expect(service.canRetry, isFalse);
      expect(service.statusText, '正在应用音效…');
    },
  );

  test('queued old work cannot start on a replacement backend', () async {
    final obsolete = service.applyEqualizer();
    final replacement = TestEqualizer();
    service.setBackend(replacement);
    await service.applyEqualizer();
    await obsolete;
    expect(backend.calls, isEmpty);
    expect(replacement.calls.length, 1);
  });

  test('Android settings remain accessible before device discovery', () {
    service.setBackend(TestEqualizer(), capabilities: null);
    expect(service.canConfigure, isTrue);
    expect(service.isEqualizerAvailable, isFalse);
    expect(service.frequencies, isEmpty);
  });

  test(
    'hung effect returns bounded failure without starting duplicate work',
    () async {
      backend.blocker = Completer<void>();
      await service.applyEqualizer();
      expect(service.canRetry, isTrue);
      final retry = service.applyEqualizer();
      backend.blocker!.complete();
      await retry;
      expect(backend.calls.length, 1);
    },
  );
}
