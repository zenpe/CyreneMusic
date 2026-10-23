import 'dart:async';

/// 播放稳定性判定器。
///
/// "引擎进入 playing" 不等于 "本次播放成功"——弱网下常见起播约 1 秒即中断。
/// 所有依赖 "播放成功" 这一事实的副作用（清零失败计数、丢弃重试标记、
/// 触发后台缓存写、预载下一首、记录播放历史）都必须等播放持续满
/// [stabilityThreshold] 且进度确实前进后才允许发生，否则会形成
/// "每首播 1 秒失败一次但计数被清零" 的连跳循环。
///
/// 稳定性按 [onPlaybackStarted] 传入的代次隔离：
/// 新代次开始会重新进入不稳定窗口；同一代次内暂停后恢复不重新门控。
class PlaybackStabilityTracker {
  /// 播放持续多久才视为稳定成功。
  final Duration stabilityThreshold;

  /// 进度尚未前进时的二次探测等待时长（流可能在缓冲，稍后再查一次）。
  final Duration progressProbeDelay;
  final Duration minimumProgress;

  final bool Function() _isPlaying;
  final Duration Function() _position;

  /// 首次达到稳定时回调一次；同一代次内不会重复触发。
  void Function()? onStable;

  Timer? _timer;
  bool _stable = false;
  bool _awaitingProgress = false;
  int _stableGeneration = -1;
  Duration _startPosition = Duration.zero;

  PlaybackStabilityTracker({
    this.stabilityThreshold = const Duration(seconds: 3),
    this.progressProbeDelay = const Duration(seconds: 2),
    this.minimumProgress = const Duration(milliseconds: 250),
    required bool Function() isPlaying,
    required Duration Function() position,
  }) : _isPlaying = isPlaying,
       _position = position;

  /// 当前代次是否已判定为稳定。
  bool get isStable => _stable;

  /// 引擎进入 playing 时调用。[generation] 用于区分不同播放会话。
  void onPlaybackStarted(int generation) {
    if (_stable && _stableGeneration == generation) {
      // 同一首歌暂停后恢复：已判定过稳定，不重新门控。
      return;
    }
    _cancelTimer();
    _stable = false;
    _awaitingProgress = false;
    _stableGeneration = generation;
    _startPosition = _position();
    _timer = Timer(stabilityThreshold, _evaluate);
  }

  /// 播放被暂停/停止/出错打断时调用，取消未决的稳定判定。
  void onPlaybackInterrupted() {
    _cancelTimer();
  }

  void dispose() {
    _cancelTimer();
  }

  void _evaluate() {
    _timer = null;
    if (!_isPlaying()) {
      _awaitingProgress = false;
      return;
    }
    final progressed = _position() - _startPosition >= minimumProgress;
    if (!progressed) {
      if (_awaitingProgress) {
        // 探测后进度仍为零：视为卡死流，不判定稳定。
        // 若后续真的出错，由引擎错误路径处理；若只是位置流迟滞，
        // 错误不会到来，也不应触发成功副作用。
        _awaitingProgress = false;
        return;
      }
      // playing 但进度未动：可能在缓冲，给一次探测机会。
      _awaitingProgress = true;
      _timer = Timer(progressProbeDelay, _evaluate);
      return;
    }
    _stable = true;
    _awaitingProgress = false;
    onStable?.call();
  }

  void _cancelTimer() {
    _timer?.cancel();
    _timer = null;
  }
}
