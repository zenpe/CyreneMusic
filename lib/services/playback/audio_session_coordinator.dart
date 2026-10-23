import 'dart:async';

import 'package:audio_session/audio_session.dart';

import '../structured_log_service.dart';

/// Configures the process-wide music session without implementing a second
/// interruption policy. just_audio remains the sole focus executor.
class AudioSessionCoordinator {
  StreamSubscription<AudioInterruptionEvent>? _interruptionSubscription;
  StreamSubscription<void>? _becomingNoisySubscription;
  bool _initialized = false;

  Future<void> initialize() async {
    if (_initialized) return;
    _initialized = true;
    try {
      final session = await AudioSession.instance;
      await session.configure(AudioSessionConfiguration.music());
      _interruptionSubscription = session.interruptionEventStream.listen(
        (event) {
          StructuredLogService.event(
            'audio_session.interruption',
            fields: {'begin': event.begin, 'type': event.type.name},
          );
        },
        onError: (Object error, StackTrace stackTrace) {
          StructuredLogService.event(
            'audio_session.interruption_stream_error',
            level: LogLevel.warning,
            error: error,
          );
        },
      );
      _becomingNoisySubscription = session.becomingNoisyEventStream.listen(
        (_) {
          StructuredLogService.event('audio_session.becoming_noisy');
        },
        onError: (Object error, StackTrace stackTrace) {
          StructuredLogService.event(
            'audio_session.noisy_stream_error',
            level: LogLevel.warning,
            error: error,
          );
        },
      );
      StructuredLogService.event('audio_session.configured');
    } catch (error) {
      await _interruptionSubscription?.cancel();
      await _becomingNoisySubscription?.cancel();
      _interruptionSubscription = null;
      _becomingNoisySubscription = null;
      StructuredLogService.event(
        'audio_session.configuration_failed',
        level: LogLevel.warning,
        error: error,
      );
    }
  }

  Future<void> dispose() async {
    await _interruptionSubscription?.cancel();
    await _becomingNoisySubscription?.cancel();
    _interruptionSubscription = null;
    _becomingNoisySubscription = null;
    _initialized = false;
  }
}
