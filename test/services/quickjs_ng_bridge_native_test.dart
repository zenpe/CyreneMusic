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

    test('preserves arbitrary thrown values without Dart type errors', () {
      for (final entry in {
        '"原始错误"': '原始错误',
        '({code: 520, message: "upstream failed"})':
            '{code: 520, message: upstream failed}',
        'null': 'null',
        'undefined': 'null',
        '42': '42',
        'false': 'false',
      }.entries) {
        final result = runtime.evaluate('throw ${entry.key}');
        expect(result.isError, isTrue);
        expect(result.rawResult, isA<JSError>());
        expect((result.rawResult as JSError).message, entry.value);
        expect(result.stringResult, isNot(contains('TypeError')));
        expect(evaluate('1 + 1'), 2);
      }

      final result = runtime.evaluate(
        'function fail() { throw new Error("original"); } fail();',
      );
      expect(result.isError, isTrue);
      final error = result.rawResult as JSError;
      expect(error.message, contains('original'));
      expect(error.stack, contains('fail'));
    });

    test('bounds getters while describing thrown exceptions', () {
      for (final script in [
        'throw {get value() { while (true) {} }}',
        '''
          const error = new Error('hostile stack');
          Object.defineProperty(error, 'stack', {
            get() { while (true) {} }
          });
          throw error;
        ''',
        '''
          (() => {
            const error = new Error();
            Object.defineProperty(error, 'message', {
              get() { while (true) {} }
            });
            throw error;
          })();
        ''',
      ]) {
        final elapsed = Stopwatch()..start();
        final result = runtime.evaluate(script);
        expect(result.isError, isTrue);
        expect(result.rawResult, isA<JSError>());
        expect(
          result.stringResult.toLowerCase(),
          anyOf(contains('interrupt'), contains('timed out')),
        );
        expect(elapsed.elapsed, lessThan(const Duration(seconds: 3)));
        expect(evaluate('1 + 1'), 2);
      }
    });

    test('preserves ordinary Promise rejection reasons', () async {
      for (final entry in <String, Matcher>{
        '"original rejection"': equals('original rejection'),
        '({code: 520})': equals({'code': 520}),
        '42': equals(42),
        'false': equals(false),
        for (final reason in ['null', 'undefined'])
          reason: isA<JSError>().having(
            (error) => error.message,
            'message',
            'Promise rejected with null or undefined',
          ),
      }.entries) {
        final rejected = evaluate('Promise.reject(${entry.key})');
        final observed = expectLater(rejected, throwsA(entry.value));
        runtime.executePendingJob();
        await observed;
        expect(evaluate('1 + 1'), 2);
      }
    });

    test('bounds getters while reporting unhandled Promise rejection', () {
      runtime.dispose();
      final reasons = <dynamic>[];
      runtime = QuickJsRuntime2(
        timeout: 250,
        memoryLimit: 64 << 20,
        hostPromiseRejectionHandler: reasons.add,
      );
      evaluate('''
        void Promise.resolve().then(() => {
          throw {get value() { while (true) {} }};
        });
      ''');
      final elapsed = Stopwatch()..start();
      expect(() => runtime.executePendingJob(), throwsA(isA<JSError>()));
      expect(elapsed.elapsed, lessThan(const Duration(seconds: 3)));
      expect(reasons, hasLength(1));
      expect(reasons.single, isA<JSError>());
      expect((reasons.single as JSError).message, 'Script execution timed out');
      expect(evaluate('1 + 1'), 2);
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
