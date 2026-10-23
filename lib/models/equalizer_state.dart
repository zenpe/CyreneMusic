import 'dart:math' as math;

enum EqualizerStatus {
  unavailable,
  waiting,
  applying,
  applied,
  bypassed,
  disabled,
  failed,
}

class EqualizerCapabilities {
  final List<int> frequencies;
  final double minGain;
  final double maxGain;
  const EqualizerCapabilities(this.frequencies, this.minGain, this.maxGain);
  static const standard = EqualizerCapabilities(
    [31, 63, 125, 250, 500, 1000, 2000, 4000, 8000, 16000],
    -12,
    12,
  );

  factory EqualizerCapabilities.fromMap(Map<dynamic, dynamic> value) {
    final frequencies = (value['frequencies'] as List)
        .cast<num>()
        .map((v) => v.toInt())
        .toList();
    final min = (value['minGain'] as num).toDouble();
    final max = (value['maxGain'] as num).toDouble();
    if (frequencies.isEmpty ||
        frequencies.any((f) => f <= 0) ||
        !min.isFinite ||
        !max.isFinite ||
        min >= max ||
        min > 0 ||
        max < 0) {
      throw const FormatException('无效的设备均衡器参数');
    }
    for (var i = 1; i < frequencies.length; i++) {
      if (frequencies[i] <= frequencies[i - 1]) {
        throw const FormatException('无效频段顺序');
      }
    }
    return EqualizerCapabilities(
      List.unmodifiable(frequencies),
      math.max(-12, min),
      math.min(12, max),
    );
  }
}

List<double> mapEqualizerCurve(
  List<int> frequencies,
  List<double> gains,
  EqualizerCapabilities target,
) {
  if (frequencies.length != gains.length ||
      frequencies.isEmpty ||
      gains.any((g) => !g.isFinite) ||
      frequencies.any((f) => f <= 0)) {
    throw const FormatException('无效的均衡器曲线');
  }
  for (var i = 1; i < frequencies.length; i++) {
    if (frequencies[i] <= frequencies[i - 1]) {
      throw const FormatException('无效频段顺序');
    }
  }
  return target.frequencies.map((frequency) {
    double gain;
    if (frequency <= frequencies.first) {
      gain = gains.first;
    } else if (frequency >= frequencies.last) {
      gain = gains.last;
    } else {
      final upper = frequencies.indexWhere((f) => f >= frequency);
      final lower = upper - 1;
      final ratio =
          math.log(frequency / frequencies[lower]) /
          math.log(frequencies[upper] / frequencies[lower]);
      gain = gains[lower] + (gains[upper] - gains[lower]) * ratio;
    }
    return gain.clamp(target.minGain, target.maxGain).toDouble();
  }).toList();
}
