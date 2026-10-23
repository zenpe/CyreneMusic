import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart' show ImageProvider;
import '../models/track.dart';
import 'playback/playback_service.dart';
export 'playback/queue_controller.dart' show QueueSource;
import 'playback/queue_controller.dart' show QueueSource;

/// 播放队列服务 — 委托到 PlaybackService
///
/// 保留原有单例和 API 签名，所有方法委托到 PlaybackService。
/// 现有 24 个文件的调用无需改动。
class PlaylistQueueService extends ChangeNotifier {
  static final PlaylistQueueService _instance =
      PlaylistQueueService._internal();
  factory PlaylistQueueService() => _instance;

  final _pb = PlaybackService();

  PlaylistQueueService._internal() {
    _pb.addListener(notifyListeners);
  }

  List<Track> get queue => _pb.queue;
  int get currentIndex => _pb.currentIndex; // 已提交播放项；待加载项不冒充正在播放
  int get pendingIndex => _pb.pendingIndex;
  int? entryIdAt(int index) => _pb.queueEntryIdAt(index);
  QueueSource get source => _pb.source;
  bool get hasQueue => _pb.hasQueue;
  bool get hasNext => _pb.hasNext;
  bool get hasPrevious => _pb.hasPrevious;
  Track? get activeTrack => _pb.activeTrack;
  Track? get pendingTrack => _pb.pendingTrack;
  String? get pendingReason => _pb.pendingReason;

  ImageProvider? getCoverProvider(Track track) => _pb.getCoverProvider(track);
  void updateCoverProvider(Track track, ImageProvider provider) =>
      _pb.updateCoverProvider(track, provider);
  void updateCoverProviders(Map<String, ImageProvider> providers) =>
      _pb.updateCoverProviders(providers);

  /// 设置播放队列
  void setQueue(
    List<Track> tracks,
    int startIndex,
    QueueSource source, {
    Map<String, ImageProvider>? coverProviders,
  }) {
    _pb.setQueueSilent(
      tracks,
      startIndex,
      source,
      coverProviders: coverProviders,
    );
  }

  /// 追加歌曲到当前队列
  void appendToQueue(List<Track> tracks) {
    for (final t in tracks) {
      _pb.addToQueue(t);
    }
  }

  /// 插入为下一首播放
  void insertNext(Track track) {
    _pb.playNext(track);
  }

  /// 移除队列中的歌曲
  void removeAt(int index) {
    _pb.removeAt(index);
  }

  /// 调整队列顺序
  void move(int oldIndex, int newIndex) {
    _pb.reorder(oldIndex, newIndex);
  }

  /// 播放指定曲目（更新当前索引）
  void playTrack(Track track) {
    final index = _pb.queue.indexWhere(
      (t) => t.id.toString() == track.id.toString() && t.source == track.source,
    );
    if (index != -1) {
      _pb.jumpTo(index);
    }
  }

  /// 预测下一首歌曲（不改变当前索引）
  Track? peekNext(dynamic mode) => _pb.peekNext(mode);

  /// 预测上一首歌曲（不改变当前索引）
  Track? peekPrevious(dynamic mode) => _pb.peekPrevious(mode);

  /// 重置洗牌序列
  void resetShuffle() {
    // shuffle 状态在 PlaybackService 内部管理
  }

  /// 清空播放队列
  void clear() {
    _pb.clearQueue();
  }

  /// 获取队列信息
  String getQueueInfo() => _pb.getQueueInfo();
}
