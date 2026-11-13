import 'dart:convert';

import 'package:cyrene_music/services/structured_log_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  tearDown(() => StructuredLogService.sink = null);

  test('redacts sensitive fields and URLs', () {
    final lines = <String>[];
    StructuredLogService.sink = lines.add;

    StructuredLogService.event(
      'playback.resolve',
      fields: {
        'transaction_id': 7,
        'url': 'https://example.test/audio?token=abc',
        'resolver_fp': 'source script and credential',
        'message': 'failed at https://example.test/audio token=abc key=credential card_key=credential',
      },
    );

    final payload = jsonDecode(lines.single) as Map<String, dynamic>;
    expect(payload['transaction_id'], 7);
    expect(payload['url'], '<redacted>');
    expect(payload['message'], contains('<url>'));
    expect(payload['message'], contains('token=<redacted>'));
    expect(lines.single, isNot(contains('abc')));
    expect(lines.single, isNot(contains('credential')));
  });

  test('operation trace emits stage and total latency', () {
    final lines = <String>[];
    StructuredLogService.sink = lines.add;
    final trace = OperationTrace(
      'playback.switch',
      context: {'transaction_id': 9},
    );
    trace.mark('resolved', fields: {'cache': 'hit'});

    final payload = jsonDecode(lines.last) as Map<String, dynamic>;
    expect(payload['event'], 'playback.switch.resolved');
    expect(payload['transaction_id'], 9);
    expect(payload['cache'], 'hit');
    expect(payload['stage_ms'], isA<int>());
    expect(payload['total_ms'], isA<int>());
  });

  test(
    'observers receive redacted asynchronous context without owning sink',
    () async {
      final seen = <Map<String, Object?>>[];
      final lines = <String>[];
      final stop = StructuredLogService.listen(seen.add);
      addTearDown(stop);
      StructuredLogService.sink = lines.add;
      await StructuredLogService.inContext(
        fields: {'playback_tx': 42},
        detailed: true,
        action: () async {
          await Future<void>.delayed(Duration.zero);
          StructuredLogService.event(
            'lx.http_response',
            fields: {'message': 'token="private"'},
          );
        },
      );
      expect(seen.single['playback_tx'], 42);
      expect(lines.single, isNot(contains('private')));
      stop();
      StructuredLogService.event('outside');
      expect(seen, hasLength(1));
      expect(jsonDecode(lines.last)['playback_tx'], isNull);
    },
  );

  test('worker relay tolerates malformed input and throwing observers', () {
    final seen = <Map<String, Object?>>[];
    final first = StructuredLogService.listen((_) => throw StateError('view'));
    final second = StructuredLogService.listen(seen.add);
    addTearDown(first);
    addTearDown(second);
    StructuredLogService.relay('invalid');
    StructuredLogService.relay(
      jsonEncode({
        'event': 'lx.http_response',
        'business_message': 'authorization: Bearer private',
      }),
    );
    expect(seen, hasLength(1));
    expect(seen.single['business_message'], isNot(contains('private')));
  });
}
