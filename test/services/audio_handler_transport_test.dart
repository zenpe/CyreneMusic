import 'dart:async';
import 'dart:io';

import 'package:audio_service/audio_service.dart';
import 'package:cyrene_music/models/song_detail.dart';
import 'package:cyrene_music/models/track.dart';
import 'package:cyrene_music/services/audio_handler_service.dart';
import 'package:cyrene_music/services/player_service.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  SharedPreferences.setMockInitialValues({});
  late TransportPlayer player;
  late CyreneAudioHandler handler;
  setUp(() {
    player = TransportPlayer();
    handler = CyreneAudioHandler(player: player);
  });
  tearDown(() async {
    await handler.onTaskRemoved();
    handler.dispose();
    player.dispose();
  });

  test(
    'intent-only pause updates controls before the engine acknowledges',
    () async {
      player.phase = PlaybackSwitchPhase.playing;
      player.changed();
      expect(handler.playbackState.value.playing, isTrue);
      player.pendingPlaybackIntent = false;
      player.desired = false;
      player.changed();
      expect(handler.playbackState.value.playing, isFalse);
      expect(handler.playbackState.value.controls[2].label, '播放');
      expect(
        handler.playbackState.value.controls[2].action,
        MediaAction.playPause,
      );

      // The periodic fallback must not undo the intent-only publication.
      await Future<void>.delayed(const Duration(milliseconds: 1100));
      expect(handler.playbackState.value.playing, isFalse);
      expect(handler.playbackState.value.controls[2].label, '播放');
    },
  );

  test(
    'loading toggle pauses; paused toggle resumes; explicit actions stay explicit',
    () async {
      player.phase = PlaybackSwitchPhase.loadingSource;
      player.changed();
      expect(handler.playbackState.value.playing, isTrue);
      expect(
        handler.playbackState.value.processingState,
        AudioProcessingState.loading,
      );
      await handler.click();
      expect(player.pauseCalls, 1);
      expect(handler.playbackState.value.controls[2].label, '播放');
      await handler.click();
      expect(player.resumeCalls, 1);
      await handler.play();
      expect(player.resumeCalls, 2);
      await handler.pause();
      expect(player.pauseCalls, 2);
    },
  );

  test('system pause remains visible despite retained play intent', () async {
    player.phase = PlaybackSwitchPhase.paused;
    player.desired = true;
    player.pendingPlaybackIntent = null;
    player.changed();
    expect(handler.playbackState.value.playing, isFalse);
    await handler.click();
    expect(player.resumeCalls, 1);
    expect(player.pauseCalls, 0);
  });

  test(
    'slow artwork cannot delay pause or publish an old media item',
    () async {
      const channel = MethodChannel('plugins.flutter.io/path_provider');
      final cacheGate = Completer<String>();
      final cacheEntered = Completer<void>();
      final dir = await Directory.systemTemp.createTemp('cyrene_media_test_');
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(channel, (_) {
        if (!cacheEntered.isCompleted) cacheEntered.complete();
        return cacheGate.future;
      });
      final publishedIds = <String>[];
      final sub = handler.mediaItem.listen((item) {
        if (item != null) publishedIds.add(item.id);
      });
      try {
        player.track = Track(
          id: 1,
          name: 'A',
          artists: 'Artist',
          album: '',
          picUrl: '',
        );
        player.cover = 'content://test/artwork';
        player.phase = PlaybackSwitchPhase.playing;
        player.changed();
        await cacheEntered.future.timeout(const Duration(seconds: 2));
        await handler.pause();
        expect(handler.playbackState.value.playing, isFalse);
        player.track = Track(
          id: 2,
          name: 'B',
          artists: 'Artist',
          album: '',
          picUrl: '',
        );
        player.cover = null;
        player.changed();
        final newMedia = handler.mediaItem.firstWhere(
          (item) => item?.id == '2',
        );
        cacheGate.complete(dir.path);
        await newMedia.timeout(const Duration(seconds: 2));
        expect(publishedIds, isNot(contains('1')));
      } finally {
        if (!cacheGate.isCompleted) cacheGate.complete(dir.path);
        await sub.cancel();
        messenger.setMockMethodCallHandler(channel, null);
        await dir.delete(recursive: true);
      }
    },
  );

  test(
    'pause retains ready session; stop publishes idle; speed changes publish',
    () async {
      player.phase = PlaybackSwitchPhase.playing;
      player.changed();
      player.playbackSpeed = 1.5;
      player.changed();
      expect(handler.playbackState.value.speed, 1.5);
      player.phase = PlaybackSwitchPhase.paused;
      player.changed();
      expect(
        handler.playbackState.value.processingState,
        AudioProcessingState.ready,
      );
      player.phase = PlaybackSwitchPhase.idle;
      player.changed();
      expect(
        handler.playbackState.value.processingState,
        AudioProcessingState.idle,
      );
      expect(handler.playbackState.value.playing, isFalse);
    },
  );

  test(
    'task removal keeps background transport synchronization alive',
    () async {
      player.phase = PlaybackSwitchPhase.playing;
      player.changed();
      expect(handler.playbackState.value.playing, isTrue);

      await handler.onTaskRemoved();
      player.phase = PlaybackSwitchPhase.paused;
      player.changed();

      expect(handler.playbackState.value.playing, isFalse);
      expect(
        handler.playbackState.value.processingState,
        AudioProcessingState.ready,
      );
    },
  );

  test('dispose detaches transport synchronization', () {
    player.phase = PlaybackSwitchPhase.playing;
    player.changed();
    expect(handler.playbackState.value.playing, isTrue);

    handler.dispose();
    player.phase = PlaybackSwitchPhase.paused;
    player.changed();

    expect(handler.playbackState.value.playing, isTrue);
  });
}

class TransportPlayer extends ChangeNotifier implements PlayerService {
  PlaybackSwitchPhase phase = PlaybackSwitchPhase.paused;
  bool desired = true;
  int pauseCalls = 0;
  int resumeCalls = 0;
  Track? track;
  String? cover;
  @override
  bool? pendingPlaybackIntent;
  @override
  double playbackSpeed = 1;
  void changed() => notifyListeners();
  @override
  PlaybackViewState get viewState => PlaybackViewState(
    generation: 1,
    track: null,
    song: null,
    switchPhase: phase,
    desiredPlaying: desired,
    enginePlaying: phase == PlaybackSwitchPhase.playing,
    position: position,
    duration: duration,
    bufferedPosition: bufferedPosition,
    lyricState: LyricLoadState.empty,
    lyricSnapshot: null,
  );
  @override
  PlayerState get state => switch (phase) {
    PlaybackSwitchPhase.idle => PlayerState.idle,
    PlaybackSwitchPhase.playing => PlayerState.playing,
    PlaybackSwitchPhase.paused => PlayerState.paused,
    PlaybackSwitchPhase.failed => PlayerState.error,
    _ => PlayerState.loading,
  };
  @override
  Track? get activeTrack => track;
  @override
  String? get currentCoverUrl => cover;
  @override
  SongDetail? get activeSong => null;
  @override
  int? get activeQueueEntryId => null;
  @override
  Duration get position => Duration.zero;
  @override
  Duration get duration => const Duration(minutes: 3);
  @override
  Duration get bufferedPosition => const Duration(seconds: 20);
  @override
  Future<void> pause() async {
    pauseCalls++;
    pendingPlaybackIntent = false;
    desired = false;
    changed();
  }

  @override
  Future<void> resume() async {
    resumeCalls++;
    pendingPlaybackIntent = true;
    desired = true;
    changed();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
