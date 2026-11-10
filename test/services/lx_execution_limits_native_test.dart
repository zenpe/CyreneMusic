import 'dart:io';

import 'package:cyrene_music/services/lx_music_runtime_service.dart';
import 'package:cyrene_music/services/lx_quickjs_runtime.dart';
import 'package:flutter_js/flutter_js.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final native = Platform.environment['CYRENE_LX_NATIVE_TEST'] == '1';
  for (final code in [
    'while (true) {}',
    '/(a+)+\$/.test("a".repeat(100) + "!")',
  ]) {
    test('native deadline interrupts and recovers: $code', () async {
      final runtime = QuickJsRuntime2(timeout: 100);
      addTearDown(runtime.dispose);
      for (var i = 0; i < 2; i++) {
        final watch = Stopwatch()..start();
        final result = runtime.evaluate(code);
        expect(result.isError, isTrue);
        expect(result.stringResult, contains('interrupted'));
        expect(watch.elapsedMilliseconds, lessThan(2000));
        await Future<void>.delayed(const Duration(milliseconds: 150));
        expect(runtime.evaluate('1 + 1').stringResult, '2');
      }
    }, skip: !native);
  }
  test('an endless Promise queue shares one execution budget', () {
    final runtime = QuickJsRuntime2(timeout: 100);
    addTearDown(runtime.dispose);
    runtime.evaluate(
      'function loop() { Promise.resolve().then(loop); } loop();',
    );
    final watch = Stopwatch()..start();
    expect(runtime.executePendingJob, throwsA(isA<JSError>()));
    expect(watch.elapsedMilliseconds, lessThan(2000));
  }, skip: !native);
  test('memory exhaustion returns an error instead of crashing the host', () {
    final runtime = QuickJsRuntime2(timeout: 200, memoryLimit: 8 * 1024 * 1024);
    addTearDown(runtime.dispose);
    final result = runtime.evaluate('new ArrayBuffer(32 * 1024 * 1024)');
    expect(result.isError, isTrue);
    expect(runtime.evaluate('1 + 1').stringResult, '2');
  }, skip: !native);
  test('an interrupted candidate preserves the active source', () async {
    final host = LxMusicRuntimeService.withFactory(LxQuickJsRuntime.new);
    addTearDown(host.dispose);
    const working = '''
      lx.on(lx.EVENT_NAMES.request, () => 'https://example.com/old.mp3');
      lx.send(lx.EVENT_NAMES.inited, {sources: {tx: {qualitys: ['128k']}}});
    ''';
    await host.loadScript(working);
    await expectLater(host.prepareScript('while (true) {}'), throwsStateError);
    expect(
      await host.getMusicUrl(source: 'tx', songId: '1', quality: '128k'),
      'https://example.com/old.mp3',
    );
    final candidate = await host.prepareScript(
      working.replaceAll('old.mp3', 'new.mp3'),
    );
    candidate.commit();
    expect(
      await host.getMusicUrl(source: 'tx', songId: '2', quality: '128k'),
      'https://example.com/new.mp3',
    );
  }, skip: !native);
}
