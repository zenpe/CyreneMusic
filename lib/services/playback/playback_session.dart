/// 协调器当前播放会话的不可变快照。
///
/// [epoch] 是引擎事件归因使用的播放纪元；[requestEpoch] 是用户请求的
/// latest-wins 纪元。两者分工不同，不能混用：一次请求可能在解析阶段
/// 产生多个内部播放会话。
enum PlaybackPhase { idle, resolving, arming, playing, paused, failed }

class PlaybackSession {
  final int epoch;
  final int requestEpoch;
  final String trackKey;
  final PlaybackPhase phase;

  const PlaybackSession({
    required this.epoch,
    required this.requestEpoch,
    required this.trackKey,
    required this.phase,
  });

  PlaybackSession copyWith({PlaybackPhase? phase}) {
    return PlaybackSession(
      epoch: epoch,
      requestEpoch: requestEpoch,
      trackKey: trackKey,
      phase: phase ?? this.phase,
    );
  }
}
