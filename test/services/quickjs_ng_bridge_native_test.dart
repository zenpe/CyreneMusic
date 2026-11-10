import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_js/flutter_js.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final native = Platform.environment['CYRENE_LX_NATIVE_TEST'] == '1';

  group('quickjs-ng native bridge', () {
    late QuickJsRuntime2 runtime;
    setUp(() => runtime = QuickJsRuntime2(timeout: 250, memoryLimit: 64 << 20));
    tearDown(() => runtime.dispose());

    dynamic evaluate(String script) {
      final result = runtime.evaluate(script);
      expect(result.isError, isFalse, reason: result.stringResult);
      return result.rawResult;
    }

    test('loads the pinned native engine', () {
      expect(QuickJsRuntime2.engineVersion, '0.18.0');
    });

    test('converts numeric values independently of internal engine tags', () {
      expect(evaluate('42'), 42);
      expect(evaluate('3.25'), 3.25);
      expect((evaluate('-0') as double).isNegative, isTrue);
      expect((evaluate('NaN') as double).isNaN, isTrue);
      expect(evaluate('Infinity'), double.infinity);
      expect(evaluate('123n'), BigInt.from(123));
      expect(
        evaluate('123456789012345678901234567890n'),
        BigInt.parse('123456789012345678901234567890'),
      );
      final identity = evaluate('(value) => value') as JSInvokable;
      try {
        final large = -BigInt.parse('123456789012345678901234567890');
        expect(identity.invoke([large]), large);
        expect(identity.invoke([BigInt.from(123)]), BigInt.from(123));
      } finally {
        identity.free();
      }
    });

    test('converts rope strings and preserves embedded NUL and Unicode', () {
      final pieces = List.generate(512, (i) => '中文🎵$i\u0000');
      final fn = evaluate(
        '(parts) => parts.reduce((a, b) => a + b, "")',
      ) as JSInvokable;
      try {
        expect(fn.invoke([pieces]), pieces.join());
      } finally {
        fn.free();
      }
      expect(evaluate('"before\\u0000after🎵"'), 'before\u0000after🎵');
    });

    test(
      'round trips buffers and object graphs without pending exceptions',
      () {
        final fn = evaluate(
          '(buffer) => ({buffer, ok: true, empty: null})',
        ) as JSInvokable;
        try {
          final bytes = Uint8List.fromList([0, 127, 128, 255]);
          final result = fn.invoke([bytes]) as Map;
          expect(result['buffer'], bytes);
          expect(result['ok'], isTrue);
          expect(result['empty'], isNull);
          expect(evaluate('({nested: [true, false, null, "ok", 1.5]})'), {
            'nested': [true, false, null, 'ok', 1.5],
          });
          expect(evaluate('1 + 1'), 2);
        } finally {
          fn.free();
        }
      },
    );

    test('preserves array proxy behavior and reports revoked proxies', () {
      expect(evaluate('new Proxy(new Proxy([1, "two"], {}), {})'), [1, 'two']);
      expect(
        () => runtime.evaluate('''
          (() => {
            const {proxy, revoke} = Proxy.revocable([], {});
            revoke();
            return proxy;
          })()
        '''),
        throwsA(isA<JSError>()),
      );
      expect(evaluate('1 + 1'), 2);
    });

    test('settles async promises and recovers after rejection', () async {
      final resolved = evaluate('(async () => { await 0; return "ready"; })()');
      runtime.executePendingJob();
      expect(await resolved, 'ready');
      final rejected = evaluate('Promise.reject(new Error("expected"))');
      final observed = expectLater(rejected, throwsA(isA<JSError>()));
      runtime.executePendingJob();
      await observed;
      expect(evaluate('2 + 2'), 4);
    });

    test('bounds recursive stack use without terminating the process', () {
      final result = runtime.evaluate('function f() { return 1 + f(); } f();');
      expect(result.isError, isTrue);
      expect(result.stringResult, contains('stack'));
      expect(evaluate('1 + 1'), 2);
    });

    test('bounds getters during function result conversion', () {
      final fn =
          evaluate('() => ({get value() { while (true) {} }})') as JSInvokable;
      try {
        expect(() => fn.invoke([]), throwsA(isA<JSError>()));
      } finally {
        fn.free();
      }
      // A failed getter must release the partial result and leave the engine
      // usable for the next evaluation and safe to dispose.
      expect(evaluate('1 + 1'), 2);
    });

    test('releases callbacks across repeated context creation', () {
      for (var i = 0; i < 25; i++) {
        final other = QuickJsRuntime2(timeout: 250);
        try {
          other.onMessage('test', (args) => args);
          expect(
            other.evaluate(r'sendMessage("test", "{\"value\":42}")').rawResult,
            {'value': 42},
          );
        } finally {
          other.dispose();
        }
      }
      expect(evaluate('1 + 1'), 2);
    });
  }, skip: !native);
}
