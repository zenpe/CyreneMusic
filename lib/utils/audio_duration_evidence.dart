/// Duration metadata uses milliseconds throughout the app. Unknown stays null.
int? validDurationMs(Object? value) {
  if (value is! num || !value.isFinite || value != value.roundToDouble()) {
    return null;
  }
  final ms = value.toInt();
  return ms > 0 && ms <= 86400000 ? ms : null;
}

String? lxInterval(int? durationMs) {
  final ms = validDurationMs(durationMs);
  if (ms == null || ms < 1000) return null;
  final seconds = ms ~/ 1000;
  return '${(seconds ~/ 60).toString().padLeft(2, '0')}:'
      '${(seconds % 60).toString().padLeft(2, '0')}';
}

enum AudioDurationAssessment { unknown, suspectedShort, noShortDetected }

/// Only call with duration evidence belonging to this resource. Passing this
/// check establishes neither song identity nor successful decoding.
AudioDurationAssessment assessAudioDuration({
  required int? expectedMs,
  required int? observedMs,
}) {
  final expected = validDurationMs(expectedMs);
  final observed = validDurationMs(observedMs);
  if (expected == null || observed == null) {
    return AudioDurationAssessment.unknown;
  }
  return observed * 100 < expected * 80 && expected - observed > 15000
      ? AudioDurationAssessment.suspectedShort
      : AudioDurationAssessment.noShortDetected;
}
