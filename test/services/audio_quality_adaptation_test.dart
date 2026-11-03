import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:cyrene_music/models/song_detail.dart';
import 'package:cyrene_music/models/track.dart';
import 'package:cyrene_music/services/audio_quality_service.dart';
import 'package:cyrene_music/services/lx_music_runtime_service.dart';
import 'package:cyrene_music/services/lx_runtime_interface.dart';
import '../support/fake_lx_runtime.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'platform fallback preserves the preferred quality for other sources',
    () async {
      SharedPreferences.setMockInitialValues({});
      final runtime = FakeLxRuntime()
        ..script = const LxScriptInfo(
          name: 'Test',
          version: '1',
          script: 'script',
          supportedSources: ['wy', 'tx'],
          platformQualities: {
            'wy': ['128k', 'flac'],
            'tx': ['128k'],
          },
        );
      LxMusicRuntimeService().useRuntimeForTesting(runtime);
      final service = AudioQualityService();
      await Future<void>.delayed(Duration.zero);
      await service.setQuality(AudioQuality.lossless);
      expect(
        service.effectiveQualityFor(MusicSource.qq),
        AudioQuality.standard,
      );
      expect(
        service.effectiveQualityFor(MusicSource.netease),
        AudioQuality.lossless,
      );
      expect(service.currentQuality, AudioQuality.lossless);
      expect(
        service.effectiveQualityFor(MusicSource.local),
        AudioQuality.lossless,
      );
    },
  );
  test(
    'request token matches the script alias instead of a hardcoded mapping',
    () {
      final runtime = FakeLxRuntime()
        ..script = const LxScriptInfo(
          name: 'Test',
          version: '1',
          script: 'script',
          supportedSources: ['wy'],
          platformQualities: {
            'wy': ['128k', 'hires'],
          },
        );
      LxMusicRuntimeService().useRuntimeForTesting(runtime);
      expect(
        AudioQualityService().requestQualityFor(
          MusicSource.netease,
          AudioQuality.hires,
        ),
        'hires',
      );
      expect(
        () => AudioQualityService().requestQualityFor(
          MusicSource.netease,
          AudioQuality.lossless,
        ),
        throwsUnsupportedError,
      );
    },
  );
}
