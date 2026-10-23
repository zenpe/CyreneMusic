import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cyrene_music/services/playback/playback_stability_tracker.dart';

void main() {
  group('PlaybackStabilityTracker', () {
    test('playing 持续满阈值且进度前进后才判定稳定', () {
      fakeAsync((async) {
        var playing = true;
        var position = Duration.zero;
        var stableCount = 0;

        final tracker = PlaybackStabilityTracker(
          isPlaying: () => playing,
          position: () => position,
        );
        tracker.onStable = () => stableCount++;

        tracker.onPlaybackStarted(1);
        async.elapse(const Duration(milliseconds: 2999));
        expect(stableCount, 0, reason: '未满 3 秒不应判定稳定');

        position = const Duration(seconds: 3);
        async.elapse(const Duration(milliseconds: 1));
        expect(stableCount, 1);
        expect(tracker.isStable, isTrue);
      });
    });

    test('进度未前进时给一次探测机会，仍未前进则不判定', () {
      fakeAsync((async) {
        var playing = true;
        const position = Duration.zero;
        var stableCount = 0;

        final tracker = PlaybackStabilityTracker(
          isPlaying: () => playing,
          position: () => position,
        );
        tracker.onStable = () => stableCount++;

        tracker.onPlaybackStarted(1);
        async.elapse(const Duration(seconds: 3));
        expect(stableCount, 0, reason: '第一次判定时进度未动，应进入探测');

        async.elapse(const Duration(seconds: 2));
        expect(stableCount, 0, reason: '探测后进度仍未动，不应判定稳定');
      });
    });

    test('探测期间进度前进则判定稳定', () {
      fakeAsync((async) {
        var playing = true;
        var position = Duration.zero;
        var stableCount = 0;

        final tracker = PlaybackStabilityTracker(
          isPlaying: () => playing,
          position: () => position,
        );
        tracker.onStable = () => stableCount++;

        tracker.onPlaybackStarted(1);
        async.elapse(const Duration(seconds: 3));
        expect(stableCount, 0);

        position = const Duration(milliseconds: 500);
        async.elapse(const Duration(seconds: 2));
        expect(stableCount, 1);
      });
    });

    test('非 playing 状态下不判定稳定', () {
      fakeAsync((async) {
        var playing = false;
        var position = const Duration(seconds: 10);
        var stableCount = 0;

        final tracker = PlaybackStabilityTracker(
          isPlaying: () => playing,
          position: () => position,
        );
        tracker.onStable = () => stableCount++;

        tracker.onPlaybackStarted(1);
        async.elapse(const Duration(seconds: 10));
        expect(stableCount, 0);
      });
    });

    test('播放被中断会取消未决判定；恢复后重新计时', () {
      fakeAsync((async) {
        var playing = true;
        var position = const Duration(seconds: 1);
        var stableCount = 0;

        final tracker = PlaybackStabilityTracker(
          isPlaying: () => playing,
          position: () => position,
        );
        tracker.onStable = () => stableCount++;

        tracker.onPlaybackStarted(1);
        async.elapse(const Duration(seconds: 2));
        tracker.onPlaybackInterrupted();

        async.elapse(const Duration(seconds: 5));
        expect(stableCount, 0, reason: '中断应取消未决的稳定判定');

        // 恢复播放（同一代次，如暂停后 resume）：重新计时。
        tracker.onPlaybackStarted(1);
        position = const Duration(seconds: 2);
        async.elapse(const Duration(seconds: 3));
        expect(stableCount, 1);
      });
    });

    test('新代次开始会重置稳定状态，重新门控', () {
      fakeAsync((async) {
        var position = const Duration(seconds: 1);
        var stableCount = 0;

        final tracker = PlaybackStabilityTracker(
          isPlaying: () => true,
          position: () => position,
        );
        tracker.onStable = () => stableCount++;

        tracker.onPlaybackStarted(1);
        position = const Duration(seconds: 2);
        async.elapse(const Duration(seconds: 3));
        expect(stableCount, 1);

        // 切歌：新代次。
        tracker.onPlaybackStarted(2);
        async.elapse(const Duration(seconds: 2));
        expect(tracker.isStable, isFalse, reason: '新代次应重新进入不稳定窗口');
        expect(stableCount, 1);

        position = const Duration(seconds: 3);
        async.elapse(const Duration(seconds: 1));
        expect(stableCount, 2);
      });
    });

    test('同一代次内已稳定后再次 onPlaybackStarted 不重复触发', () {
      fakeAsync((async) {
        var position = const Duration(seconds: 1);
        var stableCount = 0;

        final tracker = PlaybackStabilityTracker(
          isPlaying: () => true,
          position: () => position,
        );
        tracker.onStable = () => stableCount++;

        tracker.onPlaybackStarted(1);
        position = const Duration(seconds: 2);
        async.elapse(const Duration(seconds: 3));
        expect(stableCount, 1);

        // 暂停后恢复同一首歌（代次未变）。
        tracker.onPlaybackStarted(1);
        async.elapse(const Duration(seconds: 5));
        expect(stableCount, 1, reason: '已判定稳定后不应重复触发');
      });
    });
  });
}
