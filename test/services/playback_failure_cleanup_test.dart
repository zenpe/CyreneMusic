import 'dart:convert';
import 'dart:io';

import 'package:cyrene_music/models/track.dart';
import 'package:cyrene_music/services/auth_service.dart';
import 'package:cyrene_music/services/playback/playback_service.dart';
import 'package:cyrene_music/services/playback/playback_view_state.dart';
import 'package:cyrene_music/services/playback/queue_controller.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'terminal selection, navigation and retry failures release pending UI',
    () async {
      SharedPreferences.setMockInitialValues({
        'auth_token': 'local-test-token',
        'current_user': jsonEncode({
          'id': 1,
          'email': 'test@example.invalid',
          'username': 'test',
        }),
      });
      final auth = AuthService();
      await auth.ensureInitialized();
      final playback = PlaybackService();
      final tracks = List.generate(
        3,
        (index) => Track(
          id: '${Directory.systemTemp.path}/cyrene-missing-${DateTime.now().microsecondsSinceEpoch}-$index.mp3',
          name: 'missing $index',
          artists: '',
          album: '',
          picUrl: '',
          source: MusicSource.local,
        ),
      );
      final failures = <Track>[];
      playback.onPlaybackFailure = (problem) => failures.add(problem.track);
      void expectFinished() {
        expect(playback.state, PBState.error);
        expect(playback.isTrackSwitchPending, isFalse);
        expect(playback.viewState.isSwitching, isFalse);
        expect(playback.viewState.switchPhase, PlaybackSwitchPhase.failed);
      }

      try {
        await playback.playNow(tracks, 0, QueueSource.none);
        expectFinished();
        await playback.next();
        expectFinished();
        expect(failures, hasLength(2));
        final failedTrack = failures.last;
        failures.clear();
        await playback.retryCurrentTrack();
        expectFinished();
        expect(failures.single, same(failedTrack));
        // Both lookups are asynchronous. The first request becomes stale before
        // it returns and must not clear or report failure for the newer target.
        failures.clear();
        await Future.wait([playback.jumpTo(0), playback.jumpTo(1)]);
        expectFinished();
        expect(failures, [tracks[1]]);
      } finally {
        playback.onPlaybackFailure = null;
        await auth.logout();
        playback.dispose();
      }
    },
  );
}
