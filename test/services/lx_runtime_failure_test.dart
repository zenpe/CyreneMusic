import 'dart:async';

import 'package:cyrene_music/models/track.dart';
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

  test('classifies native and JS-bridged unreachable network errors', () {
    for (final message in [
      'SocketException: Network is unreachable (OS Error, errno = 101)',
      'Error: ClientException with SocketException: No route to host',
      'SocketException: Network is down',
    ]) {
      expect(
        classifyLxRuntimeFailure(message).kind,
        LxRuntimeFailureKind.networkUnavailable,
      );
    }
    for (final message in [
      'HTTP 403',
      'HTTP 429',
      'empty URL',
      'Connection refused',
    ]) {
      expect(
        classifyLxRuntimeFailure(message).kind,
        LxRuntimeFailureKind.requestFailed,
      );
    }
  });

  test('classifies runtime readiness failures separately', () {
    final failure = classifyLxRuntimeFailure(Exception('洛雪音源脚本未就绪'));

    expect(failure.kind, LxRuntimeFailureKind.notReady);
  });

  test('classifies missing track identifiers separately', () {
    final failure = classifyLxRuntimeFailure(
      const MissingTrackSourceIdentifierException('歌曲标识不完整，请重新搜索或同步'),
    );

    expect(failure.kind, LxRuntimeFailureKind.invalidTrackIdentifier);
  });
}
