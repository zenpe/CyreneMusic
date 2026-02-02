import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'player_service.dart';
import 'android_sleep_timer_service.dart';

/// 睡眠定时器模式
enum SleepTimerMode {
  duration,  // 播放指定时长后停止
  time,      // 播放到指定时间停止
}

/// 睡眠定时器服务
class SleepTimerService extends ChangeNotifier {
  static final SleepTimerService _instance = SleepTimerService._internal();
  factory SleepTimerService() => _instance;
  SleepTimerService._internal() {
    // 初始化原生服务监听
    if (defaultTargetPlatform == TargetPlatform.android) {
        AndroidSleepTimerService().init(onCancelled: () {
            print('🔄 [SleepTimerService] 收到原生取消事件，停止 Dart 端计时器');
            // 此时原生通知已经关闭，我们需要关闭 Dart 端的计时器
            // 这里调用 cancel() 会再次调用 stop()，但这是安全的
            cancel(); 
        });
    }
  }

  Timer? _timer;
  DateTime? _endTime; // 定时结束时间
  SleepTimerMode? _mode; // 当前模式
  int? _durationMinutes; // 时长模式的分钟数
  TimeOfDay? _targetTime; // 时间模式的目标时间

  bool get isActive => _timer != null && _timer!.isActive;
  DateTime? get endTime => _endTime;
  SleepTimerMode? get mode => _mode;
  int? get durationMinutes => _durationMinutes;
  TimeOfDay? get targetTime => _targetTime;

  /// 获取剩余时间（秒）
  int get remainingSeconds {
    if (_endTime == null) return 0;
    final remaining = _endTime!.difference(DateTime.now()).inSeconds;
    return remaining > 0 ? remaining : 0;
  }

  /// 获取剩余时间的格式化字符串
  String get remainingTimeString {
    final seconds = remainingSeconds;
    if (seconds <= 0) return '00:00:00';

    final hours = seconds ~/ 3600;
    final minutes = (seconds % 3600) ~/ 60;
    final secs = seconds % 60;

    if (hours > 0) {
      return '${hours.toString().padLeft(2, '0')}:${minutes.toString().padLeft(2, '0')}:${secs.toString().padLeft(2, '0')}';
    } else {
      return '${minutes.toString().padLeft(2, '0')}:${secs.toString().padLeft(2, '0')}';
    }
  }

  /// 设置定时器（按时长）
  void setTimerByDuration(int minutes) {
    cancel(); // 先取消现有定时器

    _mode = SleepTimerMode.duration;
    _durationMinutes = minutes;
    _targetTime = null;
    _endTime = DateTime.now().add(Duration(minutes: minutes));

    _startTimer();
    notifyListeners();
    
    // 启动原生通知
    if (_endTime != null) {
      AndroidSleepTimerService().start(_endTime!);
    }

    print('⏰ [SleepTimerService] 设置定时器: ${minutes}分钟后停止播放');
  }

  /// 设置定时器（按时间点）
  void setTimerByTime(TimeOfDay time) {
    cancel(); // 先取消现有定时器

    _mode = SleepTimerMode.time;
    _durationMinutes = null;
    _targetTime = time;

    // 计算目标时间
    final now = DateTime.now();
    var targetDateTime = DateTime(
      now.year,
      now.month,
      now.day,
      time.hour,
      time.minute,
    );

    // 如果目标时间已经过了，设置为明天
    if (targetDateTime.isBefore(now)) {
      targetDateTime = targetDateTime.add(const Duration(days: 1));
    }

    _endTime = targetDateTime;
    _startTimer();
    notifyListeners();
    
    // 启动原生通知
    if (_endTime != null) {
      AndroidSleepTimerService().start(_endTime!);
    }

    print('⏰ [SleepTimerService] 设置定时器: ${time.hour}:${time.minute} 停止播放');
  }

  /// 启动定时器
  void _startTimer() {
    // 每秒更新一次，用于UI显示
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_endTime == null) {
        cancel();
        return;
      }

      final now = DateTime.now();
      if (now.isAfter(_endTime!)) {
        // 时间到了，停止播放
        _onTimerEnd();
      } else {
        // 通知监听器更新UI
        notifyListeners();
      }
    });
  }

  /// 定时器结束处理
  void _onTimerEnd() {
    print('⏰ [SleepTimerService] 定时时间到，暂停播放');

    // 暂停播放
    PlayerService().pause();
    
    // 停止原生通知
    AndroidSleepTimerService().stop();

    // 清除定时器
    _timer?.cancel();
    _timer = null;
    _endTime = null;

    notifyListeners();

    print('✅ [SleepTimerService] 定时器已完成');
  }

  /// 取消定时器
  void cancel() {
    if (_timer != null) {
      _timer!.cancel();
      _timer = null;
      _endTime = null;
      _mode = null;
      _durationMinutes = null;
      _targetTime = null;
      
      // 停止原生通知
      AndroidSleepTimerService().stop();

      notifyListeners();

      print('❌ [SleepTimerService] 定时器已取消');
    }
  }

  /// 延长定时器（增加指定分钟数）
  void extend(int minutes) {
    if (_endTime != null) {
      _endTime = _endTime!.add(Duration(minutes: minutes));
      
      // 更新原生通知
      AndroidSleepTimerService().start(_endTime!);
      
      notifyListeners();
      print('⏰ [SleepTimerService] 定时器已延长 ${minutes} 分钟');
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }
}

