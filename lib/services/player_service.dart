import 'package:flutter/material.dart';
import '../models/song_detail.dart';
import '../models/track.dart';
import 'equalizer_service.dart';
import 'playback/playback_service.dart';
import 'playlist_queue_service.dart';
import 'playback_state_service.dart';

/// 播放状态枚举
enum PlayerState {
  idle,     // 空闲
  loading,  // 加载中
  playing,  // 播放中
  paused,   // 暂停
  error,    // 错误
}

/// 音乐播放器服务 — 委托到 PlaybackService
///
/// 保留原有单例和 API 签名，所有方法委托到 PlaybackService。
/// 现有 70 个文件的调用无需改动。
class PlayerService extends ChangeNotifier {
  static final PlayerService _instance = PlayerService._internal();
  factory PlayerService() => _instance;

  final _pb = PlaybackService();

  PlayerService._internal() {
    // 转发 PlaybackService 的变更通知
    _pb.addListener(notifyListeners);
    _pb.coverManager.addListener(notifyListeners);
  }

  // ══════════════════════════════════════════════════════
  // 状态 getter（全部委托）
  // ══════════════════════════════════════════════════════

  PlayerState get state {
    switch (_pb.state) {
      case PBState.idle: return PlayerState.idle;
      case PBState.loading: return PlayerState.loading;
      case PBState.playing: return PlayerState.playing;
      case PBState.paused: return PlayerState.paused;
      case PBState.error: return PlayerState.error;
    }
  }

  SongDetail? get currentSong => _pb.currentSong;
  Track? get currentTrack => _pb.currentTrack;
  Duration get duration => _pb.duration;
  Duration get position => _pb.position;
  Duration get bufferedPosition => _pb.bufferedPosition;
  String? get errorMessage => _pb.errorMessage;
  bool get isPlaying => _pb.isPlaying;
  bool get isPaused => _pb.isPaused;
  bool get isLoading => _pb.isLoading;
  double get volume => _pb.volume;
  double get playbackSpeed => _pb.playbackSpeed;
  bool get isAudioSourceNotConfigured => _pb.isAudioSourceNotConfigured;
  bool get hasNext => _pb.hasNext;
  bool get hasPrevious => _pb.hasPrevious;

  ImageProvider? get currentCoverImageProvider => _pb.coverManager.currentCover;
  String? get currentCoverUrl => _pb.coverManager.currentUrl;
  ValueNotifier<Color?> get themeColorNotifier => _pb.coverManager.themeColorNotifier;
  ValueNotifier<Duration> get positionNotifier => _pb.positionNotifier;
  ValueNotifier<Duration> get bufferedPositionNotifier =>
      _pb.bufferedPositionNotifier;

  // 均衡器
  static List<int> get kEqualizerFrequencies => EqualizerService.kEqualizerFrequencies;
  List<double> get equalizerGains => _pb.equalizerGains;
  bool get equalizerEnabled => _pb.equalizerEnabled;
  bool get isEqualizerAvailable => _pb.isEqualizerAvailable;

  // 音源配置回调
  void Function()? get onAudioSourceNotConfigured => _pb.onAudioSourceNotConfigured;
  set onAudioSourceNotConfigured(void Function()? callback) {
    _pb.onAudioSourceNotConfigured = callback;
  }

  // ══════════════════════════════════════════════════════
  // 播放控制（全部委托）
  // ══════════════════════════════════════════════════════

  Future<void> initialize() => _pb.initialize();

  Future<void> playTrack(
    Track track, {
    AudioQuality? quality,
    ImageProvider? coverProvider,
    bool fromPlaylist = false,
  }) async {
    // 如果有封面，先设置
    if (coverProvider != null) {
      _pb.coverManager.setCover(coverProvider, url: track.picUrl, notify: false);
      _pb.updateCoverProvider(track, coverProvider);
    }
    // 单曲播放：如果有队列，直接跳转或重建
    if (_pb.hasQueue) {
      // 检查 track 是否已在队列中
      final idx = _pb.queue.indexWhere(
        (t) => t.id.toString() == track.id.toString() && t.source == track.source,
      );
      if (idx != -1) {
        await _pb.jumpTo(idx);
        return;
      }
    }
    await _pb.playNow([track], 0, QueueSource.none);
  }

  Future<void> pause() => _pb.pause();
  Future<void> resume() => _pb.resume();
  Future<void> seek(Duration position) => _pb.seek(position);
  Future<void> playNext() => _pb.next();
  Future<void> playPrevious() => _pb.previous();
  Future<void> retryCurrent() => _pb.retryCurrentTrack();
  Future<void> stop() => _pb.stop();
  Future<void> togglePlayPause() => _pb.togglePlayPause();
  Future<void> setVolume(double volume) => _pb.setVolume(volume);
  Future<void> setPlaybackSpeed(double speed) => _pb.setPlaybackSpeed(speed);
  Future<void> clearSession() => _pb.clearSession();

  Future<void> playRadioStream(String streamUrl, Track radioTrack) =>
      _pb.playRadioStream(streamUrl, radioTrack);

  Future<void> preloadTrack(Track track, {ImageProvider? coverProvider}) =>
      _pb.preload(track, coverProvider: coverProvider);

  Future<void> resumeFromSavedState(PlaybackState state) =>
      _pb.resumeFromSavedState(state);

  /// 设置封面（兼容旧代码）
  void setCurrentCoverImageProvider(
    ImageProvider? provider, {
    bool shouldNotify = false,
    String? imageUrl,
  }) {
    _pb.coverManager.setCover(provider, url: imageUrl, notify: shouldNotify);
  }

  /// 手动更新悬浮歌词（供后台服务调用）
  Future<void> updateFloatingLyricManually() =>
      _pb.updateFloatingLyricManually();

  // 均衡器
  Future<void> updateEqualizer(List<double> gains) => _pb.updateEqualizer(gains);
  Future<void> setEqualizerEnabled(bool enabled) => _pb.setEqualizerEnabled(enabled);

  // 资源释放
  Future<void> forceDispose() => _pb.forceDispose();
}
