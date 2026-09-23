import 'audio_engine.dart';

/// EngineHost 对外暴露的唯一事件协议。
///
/// 每个事件都在引擎边界捕获 epoch。协调器不得从没有归属信息的原生
/// stream 推断当前歌曲，否则 stop/load 交错时无法证明事件来自哪一代。
sealed class EngineEvent {
  final int epoch;

  const EngineEvent(this.epoch);
}

final class EngineStateEvent extends EngineEvent {
  final EngineState state;

  const EngineStateEvent(super.epoch, this.state);
}

final class EnginePositionEvent extends EngineEvent {
  final Duration position;

  const EnginePositionEvent(super.epoch, this.position);
}

final class EngineDurationEvent extends EngineEvent {
  final Duration duration;

  const EngineDurationEvent(super.epoch, this.duration);
}

final class EngineBufferedPositionEvent extends EngineEvent {
  final Duration position;

  const EngineBufferedPositionEvent(super.epoch, this.position);
}

/// The native player selected and prepared a source for playback.
///
/// This is intentionally stronger than a raw currentIndex notification:
/// consumers may update now-playing presentation only after this event.
final class EngineSourceCommittedEvent extends EngineEvent {
  final String? key;

  const EngineSourceCommittedEvent(super.epoch, this.key);
}

final class EngineCompletedEvent extends EngineEvent {
  const EngineCompletedEvent(super.epoch);
}

final class EngineFailureEvent extends EngineEvent {
  final EngineError error;

  const EngineFailureEvent(super.epoch, this.error);
}
