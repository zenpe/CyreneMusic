import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:cyrene_music/models/track.dart';
import 'package:cyrene_music/services/auth_service.dart';
import 'package:cyrene_music/services/playback/playback_service.dart';
import 'package:cyrene_music/services/playback/queue_controller.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'logged-out media commands cannot start playback or replace the queue',
    () async {
      SharedPreferences.setMockInitialValues({});
      final auth = AuthService();
      await auth.ensureInitialized();
      await auth.logout();
      final playback = PlaybackService();
      final track = Track(
        id: '1',
        name: 'song',
        artists: 'artist',
        album: '',
        picUrl: '',
        source: MusicSource.netease,
      );
      try {
        await playback.playNow([track], 0, QueueSource.none);
        await playback.resume();
        await playback.next();
        await playback.previous();
        await playback.jumpTo(0);
        await playback.retryCurrentTrack();
        await playback.playRadioStream('https://example.invalid/audio', track);
        expect(playback.queue, isEmpty);
        expect(playback.state, PBState.idle);
        expect(playback.isPlaying, isFalse);
        expect(playback.currentTrack, isNull);
        // Exercise the real logout callback, with an idle engine: no native
        // initialization or network operation is needed to revoke the session.
        await auth.logout();
        expect(playback.state, PBState.idle);
      } finally {
        playback.dispose();
      }
    },
  );
}
