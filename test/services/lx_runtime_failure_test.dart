import 'dart:async';

import 'package:cyrene_music/services/lx_runtime_interface.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('classifies script integrity rejection as a source-level failure', () {
    final failure = classifyLxRuntimeFailure('脚本完整性验证失败');

    expect(failure.kind, LxRuntimeFailureKind.scriptRejected);
  });

  test('classifies timeout separately from source rejection', () {
    final failure = classifyLxRuntimeFailure(TimeoutException('请求超时'));

    expect(failure.kind, LxRuntimeFailureKind.timeout);
  });

  test('keeps unknown request failures generic', () {
    final failure = classifyLxRuntimeFailure(StateError('bad response'));

    expect(failure.kind, LxRuntimeFailureKind.requestFailed);
  });

  test('classifies runtime readiness failures separately', () {
    final failure = classifyLxRuntimeFailure(Exception('洛雪音源脚本未就绪'));

    expect(failure.kind, LxRuntimeFailureKind.notReady);
  });
}
