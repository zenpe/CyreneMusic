import 'dart:async';

import 'package:cyrene_music/services/search_request.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('deadline cancels underlying IO and ignores a late success', () async {
    final reply = Completer<String>();
    late CancelToken child;
    final parent = CancelToken();
    final result = runSearchRequest(parent, (token) {
      child = token;
      return reply.future;
    }, timeout: const Duration(milliseconds: 20));
    await expectLater(result, throwsA(isA<TimeoutException>()));
    expect(child.isCancelled, true);
    expect(parent.isCancelled, false);
    reply.complete('too late');
  });

  test('cancelling an old search cancels its IO', () async {
    final parent = CancelToken();
    late CancelToken child;
    final result = runSearchRequest(parent, (token) async {
      child = token;
      throw await token.whenCancel;
    });
    parent.cancel('new query');
    await expectLater(result, throwsA(isA<DioException>()));
    expect(child.isCancelled, true);
  });

  test('already cancelled search never starts a request', () async {
    var calls = 0;
    await expectLater(
      runSearchRequest(CancelToken()..cancel(), (_) async => calls++),
      throwsA(isA<DioException>()),
    );
    expect(calls, 0);
  });

  test('success does not cancel the other platform requests', () async {
    final parent = CancelToken();
    final waiting = Completer<String>();
    late CancelToken other;
    final second = runSearchRequest(parent, (token) {
      other = token;
      return waiting.future;
    });
    expect(await runSearchRequest(parent, (_) async => 'done'), 'done');
    expect(parent.isCancelled, false);
    expect(other.isCancelled, false);
    waiting.complete('second');
    expect(await second, 'second');
  });
}
