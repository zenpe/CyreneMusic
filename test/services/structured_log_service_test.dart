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
        'message': 'failed at https://example.test/audio token=abc',
      },
    );

    final payload = jsonDecode(lines.single) as Map<String, dynamic>;
    expect(payload['transaction_id'], 7);
    expect(payload['url'], '<redacted>');
    expect(payload['message'], contains('<url>'));
    expect(payload['message'], contains('token=<redacted>'));
    expect(lines.single, isNot(contains('abc')));
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
}
