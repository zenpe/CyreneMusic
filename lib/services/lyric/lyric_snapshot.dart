import 'dart:collection';

import 'package:flutter/foundation.dart';

import '../../models/lyric_line.dart';

enum LyricLoadState { idle, loading, ready, empty, failed }

extension LyricLoadStateDisplay on LyricLoadState {
  String get displayText {
    switch (this) {
      case LyricLoadState.failed:
        return '歌词加载失败';
      case LyricLoadState.empty:
        return '暂无歌词';
      case LyricLoadState.ready:
        return '';
      case LyricLoadState.loading:
      case LyricLoadState.idle:
        return '歌词加载中';
    }
  }
}

@immutable
class LyricSnapshot {
  final String trackKey;
  final int playbackToken;
  final LyricLoadState state;
  final List<LyricLine> lines;
  final String lyric;
  final String tlyric;
  final String yrc;
  final String ytlrc;
  final String qrc;
  final String qrcTrans;
  final DateTime updatedAt;
  final String? error;

  LyricSnapshot({
    required this.trackKey,
    required this.playbackToken,
    required this.state,
    required List<LyricLine> lines,
    required this.lyric,
    required this.tlyric,
    required this.yrc,
    required this.ytlrc,
    required this.qrc,
    required this.qrcTrans,
    required this.updatedAt,
    this.error,
  }) : lines = UnmodifiableListView<LyricLine>(List<LyricLine>.from(lines));

  bool get hasPayload =>
      lyric.isNotEmpty ||
      tlyric.isNotEmpty ||
      yrc.isNotEmpty ||
      ytlrc.isNotEmpty ||
      qrc.isNotEmpty ||
      qrcTrans.isNotEmpty;

  bool get hasLines => lines.isNotEmpty;

  String get signature => Object.hashAll([
    trackKey,
    playbackToken,
    state,
    lyric,
    tlyric,
    yrc,
    ytlrc,
    qrc,
    qrcTrans,
    error,
  ]).toString();
}
