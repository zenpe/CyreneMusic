import 'dart:io';

import 'audio_engine.dart';
import 'audio_transport_failure.dart';

/// Shared by thrown loads, asynchronous engine errors and manual navigation.
/// The coordinator remains the sole owner of retry counts and elapsed budget.
class EngineFailurePolicy {
  const EngineFailurePolicy();

  bool canRetry(EngineError error, {required bool isLocal}) {
    if (error.cause is NativePlaybackTimeout) return false;
    final status = error.httpStatus;
    if (status != null) {
      return !isLocal &&
          (status == 401 ||
              status == 403 ||
              status == 404 ||
              status == 410 ||
              status >= 500);
    }
    if (error.isSourceReadFailure) return !isLocal;
    return switch (error.type) {
      EngineErrorType.networkTimeout => true,
      EngineErrorType.accessDenied => !isLocal,
      EngineErrorType.unsupportedFormat => false,
      _ => error.retriable && isLocal,
    };
  }

  bool shouldRefreshUrl(EngineError error) =>
      error.cause is! NativePlaybackTimeout &&
      (error.type == EngineErrorType.accessDenied ||
          error.httpStatus == 404 ||
          error.httpStatus == 410 ||
          (!Platform.isAndroid && error.isSourceReadFailure));

  String message(EngineError error) {
    final status = error.httpStatus;
    if (status == 429) return '播放请求受到限流，请稍后重试';
    if (status == 404 || status == 410) {
      return '播放失败：音频资源不存在或链接已失效，请重试或切换音源';
    }
    if (status != null && status >= 500) {
      return '播放失败：音频服务暂时不可用，请稍后重试';
    }
    if (error.cause is NativePlaybackTimeout) {
      return '播放失败：播放器响应超时，请重试';
    }
    final transport = error.cause;
    if (transport is AudioTransportFailure) {
      if (transport.stage == AudioTransportStage.local) {
        return '播放失败：本地音频连接异常，请重试';
      }
      if (transport.timedOut) return '播放失败：音频连接超时，请检查网络后重试';
      if (transport.statusCode == null) return '播放失败：音频连接中断，请检查网络后重试';
    }
    return switch (error.type) {
      EngineErrorType.unsupportedFormat => '播放失败: 当前格式不受支持',
      EngineErrorType.accessDenied => '播放失败：音频资源访问受限，请重试或切换音源',
      EngineErrorType.networkTimeout => '播放失败：音频连接超时，请检查网络后重试',
      EngineErrorType.sourceLoad => '播放失败：无法读取音频，请重试或切换音源',
      _ => '播放失败：播放器发生异常，请重试',
    };
  }
}
