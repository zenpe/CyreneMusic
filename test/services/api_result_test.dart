import 'package:cyrene_music/services/api/api_result.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('rate limit body provides a visible retry delay', () {
    final result = ApiResult(
      statusCode: 429,
      data: {'message': '登录失败次数过多', 'retryAfterSeconds': 123},
    );
    expect(result.message, '登录失败次数过多，请在 123 秒后重试');
    expect(result.ok, false);
  });
  test('existing retry message is not duplicated', () {
    final result = ApiResult(
      statusCode: 429,
      data: {'message': '登录失败次数过多，请在 123 秒后重试', 'retryAfterSeconds': 123},
    );
    expect(result.message, '登录失败次数过多，请在 123 秒后重试');
  });
  test('Retry-After works without a JSON response', () {
    final result = ApiResult(
      statusCode: 429,
      headers: {
        'Retry-After': ['45'],
      },
    );
    expect(result.message, '操作过于频繁，请在 45 秒后重试');
  });
  test('malformed delay and message still provide a usable error', () {
    final result = ApiResult(
      statusCode: 429,
      data: {'message': 123, 'retryAfterSeconds': -1},
      headers: {
        'retry-after': ['invalid'],
      },
    );
    expect(result.message, '操作过于频繁，请稍后重试');
    expect(result.retryAfterSeconds, null);
  });
  test('ordinary response messages remain unchanged', () {
    expect(
      ApiResult(statusCode: 401, data: {'message': '账号或密码错误'}).message,
      '账号或密码错误',
    );
    expect(
      ApiResult(statusCode: 200, data: {'message': '登录成功'}).message,
      '登录成功',
    );
  });
}
