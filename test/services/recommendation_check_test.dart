import 'dart:async';

import 'package:cyrene_music/services/api/api_result.dart';
import 'package:cyrene_music/services/source_recommendation_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  SourceRecommendationService service(
    Future<ApiResult<dynamic>> Function() request,
  ) => SourceRecommendationService.withDependencies(
    json: (_) async => throw StateError('must not read plan'),
    bytes: (_, _) async => throw StateError('must not download script'),
    checkRequest: request,
  );

  test(
    'requests coalesce without fetching a plan or selecting a source',
    () async {
      var calls = 0;
      final pending = Completer<ApiResult<dynamic>>();
      final s = service(() {
        calls++;
        return pending.future;
      });
      final first = s.requestAutomaticCheck();
      final second = s.requestAutomaticCheck();
      expect(calls, 1);
      pending.complete(ApiResult(statusCode: 202, data: {'code': 'accepted'}));
      expect(await first, contains('已请求后台巡检'));
      expect(await second, contains('满足推荐条件'));
      await s.requestAutomaticCheck();
      expect(calls, 2);
    },
  );

  for (final entry in <(int, String, String)>[
    (401, '', '请先登录当前后端'),
    (404, '', '暂不支持'),
    (405, '', '暂不支持'),
    (200, 'already_running', '正在检测'),
    (200, 'already_requested', '已安排巡检'),
    (409, 'disabled', '未启用'),
    (409, 'paused', '已暂停'),
    (409, 'busy', '手动检测'),
    (503, '', '请求未确认'),
    (200, 'accepted', '请求未确认'),
    (0, '', '请求未确认'),
  ]) {
    test('HTTP ${entry.$1} ${entry.$2}', () async {
      final s = service(
        () async => ApiResult(statusCode: entry.$1, data: {'code': entry.$2}),
      );
      expect(await s.requestAutomaticCheck(), contains(entry.$3));
    });
  }

  test('cooldown uses server Retry-After', () async {
    final s = service(
      () async => ApiResult(
        statusCode: 429,
        headers: {
          'retry-after': ['123'],
        },
      ),
    );
    expect(await s.requestAutomaticCheck(), contains('123 秒'));
  });

  test('transport exceptions release single flight for retry', () async {
    var calls = 0;
    final s = service(() async {
      if (++calls == 1) throw StateError('network');
      return ApiResult(statusCode: 200, data: {'code': 'already_running'});
    });
    await expectLater(s.requestAutomaticCheck(), throwsStateError);
    expect(await s.requestAutomaticCheck(), contains('正在检测'));
  });
}
