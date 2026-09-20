/// 引擎纪元闸门：单播放器实例下的"源头纪元捕获 + 切换窗口闸门"。
///
/// 核心不变量：
/// 1. [beginArm] 与 [beginStop] 都是源头操作，各自捕获调用时刻的纪元状态；
/// 2. arm 窗口（从 [beginArm] 到 [commitArm] 之前）内到达的引擎流事件，
///    其真实来源只可能是旧音源（新源尚未装入播放器）——此时
///    [streamEventEpoch] 返回旧纪元，协调器按代次不匹配将其丢弃，
///    从而抑制旧歌的错误/完成/状态事件污染新歌；
/// 3. [beginStop] 之后产生的流事件（idle/completed 等）永久归属被停止
///    的纪元，即使它们在新的 arm 开始之后才分发；
/// 4. arm 抛出的同步异常（setAudioSource 失败）不经过本闸门归属判断：
///    它由实现层直接以新纪元上报——那是"新源加载失败"，必须参与重试。
///
/// 实现层（JustAudioEngine / MediaKitEngine）在装载成功后调用 [commitArm]
/// 翻转纪元；此后流事件按新纪元分发，直到下一次 arm/stop。
class EngineEpochGate {
  int _armedEpoch = 0;
  int? _pendingEpoch;
  int? _stoppedEpoch;

  /// 是否有 arm 正在进行（切换窗口打开中）。
  bool get armInFlight => _pendingEpoch != null;

  /// 已提交到原生播放器的纪元。
  int get armedEpoch => _armedEpoch;

  /// arm 开始：打开切换窗口，窗口内流事件归属 [armedEpoch]（旧纪元）。
  /// 返回本次 arm 的纪元，供实现层在 commit/abandon 与异常上报时使用。
  int beginArm(int epoch) {
    _stoppedEpoch = null;
    _pendingEpoch = epoch;
    return epoch;
  }

  /// 装载成功：纪元翻转，窗口关闭。此后的流事件归属新纪元。
  void commitArm(int epoch) {
    if (_pendingEpoch == epoch) {
      _armedEpoch = epoch;
      _pendingEpoch = null;
      _stoppedEpoch = null;
    }
  }

  /// 装载失败：窗口关闭但纪元不翻转（错误已由实现层以新纪元直接上报）。
  void abandonArm(int epoch) {
    if (_pendingEpoch == epoch) {
      _pendingEpoch = null;
    }
  }

  /// stop 开始：此后到下一次 [beginArm] 之前的流事件归属被停止的纪元。
  void beginStop() {
    if (_pendingEpoch == null) {
      _stoppedEpoch = _armedEpoch;
    }
  }

  /// 当前时刻到达的流事件应归属的纪元（源头捕获）。
  int get streamEventEpoch {
    final stopped = _stoppedEpoch;
    if (stopped != null) return stopped;
    return _armedEpoch;
  }
}
