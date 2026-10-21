import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:dio/dio.dart';
import 'package:cyrene_music/services/lyric/lyric_fetch_result.dart';
import 'package:cyrene_music/services/lyric/lyric_request_coordinator.dart';

const ready = LyricFetchResult(
  LyricFetchKind.ready,
  payload: LyricPayload(lyric: '[00:00.00]Lyrics'),
);
const temporary = LyricFetchResult(LyricFetchKind.unavailable, retryable: true);

void main() {
  late LyricRequestCoordinator coordinator;
  setUp(
    () => coordinator = LyricRequestCoordinator(
      attemptTimeout: const Duration(milliseconds: 30),
      retryDelay: Duration.zero,
      totalTimeout: const Duration(milliseconds: 100),
    ),
  );
  tearDown(() => coordinator.clear());

  test(
    'foreground adopts pending prefetch and shares one recovery attempt',
    () async {
      final response = Completer<LyricFetchResult>();
      var calls = 0;
      Future<LyricFetchResult> fetch(
        CancelToken token,
        Duration timeout,
        bool bypass,
      ) async {
        calls++;
        if (calls == 1) return response.future;
        expect(bypass, isTrue);
        return ready;
      }

      final prefetch = coordinator.request(
        'same',
        fetch: fetch,
        foreground: false,
        isValid: () => true,
      );
      final foreground = coordinator.request(
        'same',
        fetch: fetch,
        foreground: true,
        isValid: () => true,
      );
      response.complete(temporary);
      expect((await foreground).kind, LyricFetchKind.ready);
      expect((await prefetch).kind, LyricFetchKind.ready);
      expect(calls, 2);
    },
  );

  test(
    'background never retries, foreground can use its remaining attempt',
    () async {
      var calls = 0;
      Future<LyricFetchResult> fetch(CancelToken t, Duration d, bool b) async {
        calls++;
        return calls == 1 ? temporary : ready;
      }

      await coordinator.request(
        'same',
        fetch: fetch,
        foreground: false,
        isValid: () => true,
      );
      expect(calls, 1);
      expect(
        (await coordinator.request(
          'same',
          fetch: fetch,
          foreground: true,
          isValid: () => true,
        )).kind,
        LyricFetchKind.ready,
      );
      expect(calls, 2);
    },
  );

  test('hung transports are aborted with bounded attempts', () async {
    final tokens = <CancelToken>[];
    final result = await coordinator.request(
      'hung',
      foreground: true,
      isValid: () => true,
      fetch: (token, timeout, bypass) {
        tokens.add(token);
        return Completer<LyricFetchResult>().future;
      },
    );
    expect(result.kind, LyricFetchKind.unavailable);
    expect(tokens, hasLength(2));
    expect(tokens.every((token) => token.isCancelled), isTrue);
  });

  test(
    'new selection cancels old request without waiting for its response',
    () async {
      final lateResponse = Completer<LyricFetchResult>();
      late CancelToken token;
      final old = coordinator.request(
        'old',
        foreground: true,
        isValid: () => true,
        fetch: (t, d, b) {
          token = t;
          return lateResponse.future;
        },
      );
      coordinator.retain('new');
      expect((await old).kind, LyricFetchKind.cancelled);
      expect(token.isCancelled, isTrue);
      lateResponse.complete(ready);
      expect(
        (await coordinator.request(
          'new',
          foreground: true,
          isValid: () => true,
          fetch: (t, d, b) async => ready,
        )).kind,
        LyricFetchKind.ready,
      );
    },
  );

  test(
    'terminal results do not retry; manual clicks share a running request',
    () async {
      var calls = 0;
      final response = Completer<LyricFetchResult>();
      Future<LyricFetchResult> fetch(CancelToken t, Duration d, bool b) {
        calls++;
        return response.future;
      }

      final first = coordinator.request(
        'key',
        foreground: true,
        fetch: fetch,
        isValid: () => true,
      );
      final second = coordinator.request(
        'key',
        foreground: true,
        force: true,
        fetch: fetch,
        isValid: () => true,
      );
      response.complete(const LyricFetchResult(LyricFetchKind.empty));
      expect((await first).kind, LyricFetchKind.empty);
      expect((await second).kind, LyricFetchKind.empty);
      expect(calls, 1);
    },
  );

  test('rate limit blocks manual retry until Retry-After', () async {
    var calls = 0;
    Future<LyricFetchResult> fetch(CancelToken t, Duration d, bool b) async {
      calls++;
      return const LyricFetchResult(
        LyricFetchKind.unavailable,
        retryAfter: Duration(minutes: 1),
      );
    }

    await coordinator.request(
      'key',
      foreground: true,
      fetch: fetch,
      isValid: () => true,
    );
    await coordinator.request(
      'key',
      foreground: true,
      force: true,
      fetch: fetch,
      isValid: () => true,
    );
    expect(calls, 1);
  });

  test('invalid context cannot start a new attempt', () async {
    var valid = true;
    var calls = 0;
    final result = await coordinator.request(
      'key',
      foreground: true,
      isValid: () => valid,
      fetch: (t, d, b) async {
        calls++;
        valid = false;
        return temporary;
      },
    );
    expect(result.kind, LyricFetchKind.cancelled);
    expect(calls, 1);
  });
}
