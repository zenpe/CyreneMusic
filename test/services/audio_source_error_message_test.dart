import 'package:cyrene_music/services/audio_source_error_message.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('native resource failures remain readable', () {
    expect(
      audioSourceErrorMessage(
        'Bad state: TimeoutException: 音源脚本执行超时，已中止，请更换音源',
      ),
      '音源脚本执行超时，已中止，请更换音源',
    );
    expect(
      audioSourceErrorMessage(
        'Bad state: Exception: InternalError: out of memory',
      ),
      '音源脚本占用内存过多，已中止，请更换音源',
    );
  });
  test('removes wrappers and stack traces but keeps actionable messages', () {
    expect(
      audioSourceErrorMessage(
        'Exception: Bad state: Exception: 请更新音源\n at eval:42',
      ),
      '请更新音源',
    );
    expect(
      audioSourceErrorMessage('Exception: SyntaxError: Unexpected token <'),
      contains('内容格式异常'),
    );
    expect(
      audioSourceErrorMessage('Exception: <html>proxy error</html>'),
      contains('返回内容异常'),
    );
    expect(
      audioSourceErrorMessage('Exception: \uFFFD\u0000'),
      contains('返回内容异常'),
    );
    expect(
      audioSourceErrorMessage('Exception: ${'x' * 1000}').length,
      lessThan(100),
    );
  });
}
