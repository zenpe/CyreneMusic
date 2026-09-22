import 'structured_log_service.dart';
import 'dart:async';
import 'package:flutter/services.dart';

/// 节奏律动服务 - 桥接 Windows 原生音频捕获
class RhythmService {
  static final RhythmService _instance = RhythmService._internal();
  factory RhythmService() => _instance;

  RhythmService._internal();

  static const MethodChannel _methodChannel = MethodChannel('com.cyrene.music/rhythm_method');
  static const EventChannel _eventChannel = EventChannel('com.cyrene.music/rhythm_event');

  StreamSubscription? _subscription;
  final _bandsController = StreamController<List<double>>.broadcast();

  /// 实时频段数据流 (16 个频段)
  Stream<List<double>> get bandsStream => _bandsController.stream;

  bool _isStarted = false;
  bool get isStarted => _isStarted;

  // 平滑处理后的数据
  List<double> _smoothedBands = List.filled(16, 0.0);
  static const double _lerpFactor = 0.2; // 平滑因子，越小越丝滑但延迟越高

  /// 开始捕获
  Future<void> start() async {
    if (_isStarted) return;
    try {
      await _methodChannel.invokeMethod('start');
      _subscription = _eventChannel.receiveBroadcastStream().listen((dynamic event) {
        if (event is List) {
          final List<double> rawBands = event.cast<double>();
          _processBands(rawBands);
        }
      });
      _isStarted = true;
    } catch (e) {
      StructuredLogService.log('RhythmService Error starting: $e');
    }
  }

  /// 停止捕获
  Future<void> stop() async {
    if (!_isStarted) return;
    try {
      await _methodChannel.invokeMethod('stop');
      await _subscription?.cancel();
      _subscription = null;
      _isStarted = false;

      // 重置数据
      _smoothedBands = List.filled(16, 0.0);
      _bandsController.add(_smoothedBands);
    } catch (e) {
      StructuredLogService.log('RhythmService Error stopping: $e');
    }
  }

  void _processBands(List<double> rawBands) {
    if (rawBands.length != _smoothedBands.length) return;

    // 应用平滑算法
    for (int i = 0; i < rawBands.length; i++) {
      _smoothedBands[i] = _smoothedBands[i] + (rawBands[i] - _smoothedBands[i]) * _lerpFactor;
    }

    _bandsController.add(List.from(_smoothedBands));
  }

  /// 获取低频强度 (Bass) - 通常是前 3 个频段
  double get bassIntensity {
    if (_smoothedBands.isEmpty) return 0.0;
    return (_smoothedBands[0] + _smoothedBands[1] + _smoothedBands[2]) / 3.0;
  }
}
