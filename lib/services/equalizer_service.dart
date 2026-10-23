import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import '../models/equalizer_state.dart';
import 'persistent_storage_service.dart';
import 'structured_log_service.dart';

abstract class EqualizerCapable {
  bool get supportsEqualizer;
  Future<void> applyEqualizer(
    bool enabled,
    List<double> gains,
    List<int> frequencies,
  );
}

class EqualizerService extends ChangeNotifier {
  static final EqualizerService _instance = EqualizerService._();
  factory EqualizerService() => _instance;
  EqualizerService._();
  @visibleForTesting
  EqualizerService.forTest();

  static const kEqualizerFrequencies = [
    31,
    63,
    125,
    250,
    500,
    1000,
    2000,
    4000,
    8000,
    16000,
  ];
  List<int> _curveFrequencies = List.of(kEqualizerFrequencies);
  List<double> _curveGains = List.filled(10, 0);
  bool _enabled = true;
  EqualizerCapable? _backend;
  EqualizerCapabilities? _capabilities;
  EqualizerStatus _status = EqualizerStatus.waiting;
  Timer? _applyTimer;
  Timer? _saveTimer;
  Future<void> _saving = Future.value();
  Future<void>? _applying;
  int _revision = 0;
  int _backendGeneration = 0;
  int get revision => _revision;

  List<int> get frequencies =>
      List.unmodifiable(_capabilities?.frequencies ?? const <int>[]);
  double get minGain => _capabilities?.minGain ?? -12;
  double get maxGain => _capabilities?.maxGain ?? 12;
  List<double> get equalizerGains => _capabilities == null
      ? const []
      : List.unmodifiable(
          mapEqualizerCurve(_curveFrequencies, _curveGains, _capabilities!),
        );
  bool get equalizerEnabled => _enabled;
  bool get isEqualizerAvailable =>
      (_backend?.supportsEqualizer ?? false) && _capabilities != null;
  bool get canRetry => _status == EqualizerStatus.failed;
  bool get canConfigure => _backend?.supportsEqualizer ?? false;
  String get statusText => switch (_status) {
    EqualizerStatus.unavailable => '当前平台暂不支持均衡器',
    EqualizerStatus.waiting => '播放歌曲后获取设备频段并应用设置',
    EqualizerStatus.applying => '正在应用音效…',
    EqualizerStatus.applied => '音效已应用',
    EqualizerStatus.bypassed => '平直曲线，未启用音效处理',
    EqualizerStatus.disabled => '均衡器已关闭',
    EqualizerStatus.failed => '音效未确认生效，播放不受影响，可重试',
  };

  void setBackend(
    EqualizerCapable? backend, {
    EqualizerCapabilities? capabilities = EqualizerCapabilities.standard,
  }) {
    if (identical(_backend, backend)) return;
    _backend = backend;
    _backendGeneration++;
    _applying = null;
    _revision++;
    _capabilities = backend?.supportsEqualizer == true ? capabilities : null;
    _status = backend?.supportsEqualizer == true
        ? EqualizerStatus.waiting
        : EqualizerStatus.unavailable;
    notifyListeners();
  }

  void report(
    EqualizerCapable owner,
    EqualizerStatus status, {
    EqualizerCapabilities? capabilities,
    int? revision,
  }) {
    if (!identical(owner, _backend)) return;
    if (revision != null && revision != _revision) return;
    if (capabilities != null) _capabilities = capabilities;
    _status = status;
    notifyListeners();
  }

  void loadSettings() {
    final storage = PersistentStorageService();
    _enabled = storage.getBool('player_eq_enabled') ?? true;
    var restored = false;
    try {
      final raw = storage.getString('player_eq_curve_v2');
      if (raw != null) {
        final points = (jsonDecode(raw) as List).cast<Map<String, dynamic>>();
        final frequencies = points
            .map((p) => (p['frequency'] as num).toInt())
            .toList();
        final gains = points.map((p) => (p['gain'] as num).toDouble()).toList();
        mapEqualizerCurve(frequencies, gains, EqualizerCapabilities.standard);
        _curveFrequencies = frequencies;
        _curveGains = gains
            .map((g) => g.clamp(-12.0, 12.0).toDouble())
            .toList();
        restored = true;
      }
    } catch (_) {
      /* Fall back to the legacy curve or a flat curve. */
    }
    if (!restored) {
      _curveFrequencies = List.of(kEqualizerFrequencies);
      final legacy = storage.getStringList('player_eq_gains');
      _curveGains = List.generate(10, (i) {
        final gain = legacy?.length == 10 ? double.tryParse(legacy![i]) : null;
        return gain != null && gain.isFinite
            ? gain.clamp(-12.0, 12.0).toDouble()
            : 0.0;
      });
      if (legacy != null) unawaited(flushSettings());
    }
    _revision++;
    notifyListeners();
  }

  List<double> mapPreset(List<double> gains) => _capabilities == null
      ? const []
      : mapEqualizerCurve(kEqualizerFrequencies, gains, _capabilities!);

  Future<void> applyPreset(List<double> gains) async {
    mapEqualizerCurve(
      kEqualizerFrequencies,
      gains,
      EqualizerCapabilities.standard,
    );
    _curveFrequencies = List.of(kEqualizerFrequencies);
    _curveGains = gains.map((g) => g.clamp(-12.0, 12.0).toDouble()).toList();
    _changed();
  }

  Future<void> updateEqualizer(List<double> gains) async {
    if (!isEqualizerAvailable ||
        gains.length != frequencies.length ||
        gains.any((g) => !g.isFinite)) {
      return;
    }
    _curveFrequencies = frequencies;
    _curveGains = gains
        .map((g) => g.clamp(minGain, maxGain).toDouble())
        .toList();
    _changed();
  }

  Future<void> setEqualizerEnabled(bool enabled) async {
    if (_enabled == enabled) return;
    _enabled = enabled;
    _changed();
    await flushSettings();
  }

  void _changed() {
    _revision++;
    _status = EqualizerStatus.applying;
    notifyListeners();
    _saveTimer?.cancel();
    _saveTimer = Timer(
      const Duration(milliseconds: 250),
      () => unawaited(flushSettings()),
    );
    _applyTimer?.cancel();
    _applyTimer = Timer(
      const Duration(milliseconds: 50),
      () => unawaited(applyEqualizer()),
    );
  }

  Future<void> flushSettings() {
    _saveTimer?.cancel();
    final enabled = _enabled;
    final curve = jsonEncode(
      List.generate(
        _curveFrequencies.length,
        (i) => {'frequency': _curveFrequencies[i], 'gain': _curveGains[i]},
      ),
    );
    return _saving = _saving.then((_) async {
      await PersistentStorageService().setString('player_eq_curve_v2', curve);
      await PersistentStorageService().setBool('player_eq_enabled', enabled);
    });
  }

  Future<void> applyEqualizer() async {
    _applyTimer?.cancel();
    final backend = _backend;
    final revision = _revision;
    if (_applying == null) {
      final generation = _backendGeneration;
      final work = Future<void>.microtask(() => _applyLatest(generation));
      _applying = work;
      unawaited(
        work.whenComplete(() {
          if (identical(_applying, work)) _applying = null;
        }),
      );
    }
    await _applying!.timeout(
      const Duration(milliseconds: 750),
      onTimeout: () {
        if (backend != null && revision == _revision) {
          report(backend, EqualizerStatus.failed);
        }
      },
    );
  }

  Future<void> _applyLatest(int generation) async {
    int revision;
    do {
      if (generation != _backendGeneration) return;
      revision = _revision;
      final backend = _backend;
      if (backend == null || !backend.supportsEqualizer) return;
      try {
        await backend.applyEqualizer(
          _enabled,
          List.of(_curveGains),
          List.of(_curveFrequencies),
        );
      } catch (error) {
        if (identical(backend, _backend) && revision == _revision) {
          report(backend, EqualizerStatus.failed);
        }
        StructuredLogService.event(
          'equalizer.apply_failed',
          level: LogLevel.warning,
          error: error,
        );
      }
      if (generation != _backendGeneration) return;
    } while (revision != _revision);
  }

  @override
  void dispose() {
    _applyTimer?.cancel();
    _saveTimer?.cancel();
    super.dispose();
  }
}
