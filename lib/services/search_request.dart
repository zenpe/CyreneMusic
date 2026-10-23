import 'dart:async';

import 'package:dio/dio.dart';

/// Search has one wall-clock deadline, independent of Dio's phase timeouts.
Future<T> runSearchRequest<T>(
  CancelToken parent,
  Future<T> Function(CancelToken token) send, {
  Duration timeout = const Duration(seconds: 15),
}) async {
  if (parent.isCancelled) throw parent.cancelError!;
  final token = CancelToken();
  unawaited(parent.whenCancel.then((error) => token.cancel(error)));
  try {
    return await send(token).timeout(
      timeout,
      onTimeout: () {
        token.cancel('搜索总等待时间已耗尽');
        throw TimeoutException('搜索超时，请重试', timeout);
      },
    );
  } finally {
    token.cancel('搜索请求已结束');
  }
}
