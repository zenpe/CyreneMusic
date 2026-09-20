import 'package:flutter_test/flutter_test.dart';

import 'package:cyrene_music/services/playback/engine_epoch_gate.dart';

void main() {
  group('EngineEpochGate', () {
    test('初始状态：纪元 0，无 arm 进行中', () {
      final gate = EngineEpochGate();
      expect(gate.armedEpoch, 0);
      expect(gate.armInFlight, isFalse);
      expect(gate.streamEventEpoch, 0);
    });

    test('arm 窗口内流事件归属旧纪元，commit 后归属新纪元', () {
      final gate = EngineEpochGate();
      gate.beginArm(5);
      expect(gate.armInFlight, isTrue);
      // 切换窗口：新源尚未装入，事件只可能来自旧音源。
      expect(gate.streamEventEpoch, 0);
      gate.commitArm(5);
      expect(gate.armInFlight, isFalse);
      expect(gate.streamEventEpoch, 5);
    });

    test('abandonArm 关闭窗口但不翻转纪元', () {
      final gate = EngineEpochGate();
      gate.beginArm(5);
      gate.commitArm(5);

      gate.beginArm(6);
      gate.abandonArm(6);
      expect(gate.armInFlight, isFalse);
      expect(gate.armedEpoch, 5);
      expect(gate.streamEventEpoch, 5);
    });

    test('不匹配的 commit 被忽略', () {
      final gate = EngineEpochGate();
      gate.beginArm(5);
      gate.commitArm(99);
      expect(gate.armInFlight, isTrue);
      expect(gate.armedEpoch, 0);
      gate.commitArm(5);
      expect(gate.armedEpoch, 5);
    });

    test('stop 后到下一次 arm 前的事件归属被停止的纪元', () {
      final gate = EngineEpochGate();
      gate.beginArm(5);
      gate.commitArm(5);

      gate.beginStop();
      expect(gate.streamEventEpoch, 5);

      // stop 之后新 arm 开始：窗口内事件仍归属旧纪元（被停止的 5）。
      gate.beginArm(6);
      expect(gate.streamEventEpoch, 5);
      gate.commitArm(6);
      expect(gate.streamEventEpoch, 6);
    });

    test('arm 优先于 stop 标记：beginArm 清除 stop 残留', () {
      final gate = EngineEpochGate();
      gate.beginArm(5);
      gate.commitArm(5);
      gate.beginStop();
      gate.beginArm(7);
      gate.abandonArm(7);
      // abandon 后回到 armed 纪元（stop 标记已被 beginArm 清除）。
      expect(gate.streamEventEpoch, 5);
    });

    test('连续两次 arm：每次窗口内都归属前一个已提交纪元', () {
      final gate = EngineEpochGate();
      gate.beginArm(1);
      gate.commitArm(1);
      gate.beginArm(2);
      expect(gate.streamEventEpoch, 1);
      gate.commitArm(2);
      gate.beginArm(3);
      expect(gate.streamEventEpoch, 2);
      gate.commitArm(3);
      expect(gate.streamEventEpoch, 3);
    });
  });
}
