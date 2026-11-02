import 'package:cyrene_music/services/playback_mode_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'saving a current mode marks its enum migrated for the next launch',
    () async {
      SharedPreferences.setMockInitialValues({});
      final modes = PlaybackModeService();
      await modes.setMode(PlaybackMode.sequential);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getInt('playback_mode'), PlaybackMode.sequential.index);
      expect(prefs.getBool('playback_mode_migrated_v2'), isTrue);
      final revision = modes.revision;
      await modes.setMode(PlaybackMode.sequential);
      expect(modes.revision, greaterThan(revision));
      expect(prefs.getInt('playback_mode'), PlaybackMode.sequential.index);
    },
  );
}
