import 'dart:async';
import 'package:cyrene_music/models/equalizer_state.dart';
import 'package:cyrene_music/services/android_equalizer_service.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('com.cyrene.music/android_equalizer');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  Future<AndroidEqualizerResult> configure() =>
      AndroidEqualizerService().configure(
        sessionId: 42,
        enabled: true,
        gains: [0, 3],
        frequencies: [100, 10000],
      );
  tearDown(() => messenger.setMockMethodCallHandler(channel, null));

  test('uses actual native bands and gain limits', () async {
    messenger.setMockMethodCallHandler(
      channel,
      (_) async => {
        'status': 'applied',
        'frequencies': [60, 230, 910, 3600, 14000],
        'minGain': -6.0,
        'maxGain': 9.0,
      },
    );
    final result = await configure();
    expect(result.status, EqualizerStatus.applied);
    expect(result.capabilities!.frequencies.length, 5);
    expect(result.capabilities!.minGain, -6);
  });
  test('native exception is isolated from playback caller', () async {
    messenger.setMockMethodCallHandler(
      channel,
      (_) async => throw PlatformException(code: 'unsupported'),
    );
    expect((await configure()).status, EqualizerStatus.failed);
  });
  test(
    'timeout invalidation targets exact request and later retry succeeds',
    () async {
      final pending = Completer<dynamic>();
      final calls = <MethodCall>[];
      messenger.setMockMethodCallHandler(channel, (call) async {
        calls.add(call);
        if (calls.length == 1) return pending.future;
        return {'status': 'bypassed'};
      });
      expect((await configure()).status, EqualizerStatus.failed);
      await Future<void>.delayed(Duration.zero);
      expect(calls[1].method, 'invalidate');
      expect(calls[1].arguments['requestId'], calls[0].arguments['requestId']);
      expect((await configure()).status, EqualizerStatus.bypassed);
      expect(
        calls.last.arguments['requestId'],
        greaterThan(calls.first.arguments['requestId'] as int),
      );
      pending.complete({'status': 'applied'});
    },
  );
}
