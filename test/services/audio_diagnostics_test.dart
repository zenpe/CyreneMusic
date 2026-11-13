import 'package:cyrene_music/services/audio_diagnostics.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('shows HTTP success and business failure as distinct facts', () {
    final line = AudioDiagnostics.format({
      'event': 'lx.http_response',
      'playback_tx': 42,
      'playback_request': 7,
      'source_name': '独家音源',
      'request_id': 'http_1',
      'host': 'source.example',
      'status': 200,
      'business_code': 2,
      'business_message': 'Object trans failure: 140017.',
      'elapsed_ms': 123,
      'body_type': 'object',
    });
    expect(line, contains('tx=42 request=7'));
    expect(line, contains('音源=独家音源'));
    expect(line, contains('HTTP=200 业务码=2'));
    expect(line, contains('140017'));
    expect(line, contains('123ms'));
    expect(line, contains('HTTP成功不代表业务成功'));
  });

  test('does not print stacks, full responses or unrelated events', () {
    expect(
      AudioDiagnostics.compact('get music url failed\n at <eval>:15'),
      'get music url failed',
    );
    expect(
      AudioDiagnostics.businessMessage({
        'data': {'token': 'private'},
      }),
      isNull,
    );
    expect(
      AudioDiagnostics.businessCode({
        'code': {'token': 'private'},
      }),
      isNull,
    );
    expect(
      AudioDiagnostics.businessCode({'code': 'APP_UPGRADE_REQUIRED'}),
      'APP_UPGRADE_REQUIRED',
    );
    expect(
      AudioDiagnostics.businessMessage({
        'msg': {'token': 'private'},
      }),
      isNull,
    );
    expect(AudioDiagnostics.format({'event': 'diagnostic.message'}), isNull);
    expect(
      AudioDiagnostics.format({
        'event': 'lx.http_transport_ended',
        'outcome': 'success',
      }),
      isNull,
    );
    expect(AudioDiagnostics.compact('a' * 1000).length, lessThan(250));
  });

  test('bounds and redacts upstream messages before they cross isolates', () {
    final message = AudioDiagnostics.businessMessage({
      'message':
          '需要认证 token=private api_key="credential" '
          'https://source.example/audio?vkey=private Bearer private',
    });
    expect(message, contains('需要认证'));
    expect(message, isNot(contains('private')));
    expect(message, isNot(contains('credential')));
    expect(message, isNot(contains('source.example')));
  });
}
