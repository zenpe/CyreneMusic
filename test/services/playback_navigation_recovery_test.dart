import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:cyrene_music/models/song_detail.dart';
import 'package:cyrene_music/models/audio_source_config.dart';
import 'package:cyrene_music/services/audio_source_service.dart';
import 'package:cyrene_music/models/track.dart';
import 'package:cyrene_music/services/auth_service.dart';
import 'package:cyrene_music/services/lx_runtime_interface.dart';
import 'package:cyrene_music/services/playback/audio_engine.dart';
import 'package:cyrene_music/services/playback/engine_host.dart';
import 'package:cyrene_music/services/playback/playable_source.dart';
import 'package:cyrene_music/services/playback/playback_service.dart';
import 'package:cyrene_music/services/playback/queue_controller.dart';
import 'package:cyrene_music/services/playback/track_resolver.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_audio/just_audio.dart' as ja;
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({
      'auth_token': 'test-token',
      'current_user': jsonEncode({
        'id': 1,
        'username': 'test',
        'email': 'test@example.invalid',
      }),
    });
    await AuthService().ensureInitialized();
  });
  tearDownAll(() async {
    AuthService().onSessionEnded = null;
    await AuthService().logout();
  });

  test(
    'ordinary remote player failure does not re-query the resolver',
    () async {
      await configureTestSource();
      final resolver = _Resolver()..playable.add('0');
      final engine = _Engine()..nextError = EngineErrorType.sourceLoad;
      final playback = _createPlayback(resolver, engine: engine);
      try {
        await playback.playNow(
          [track(0, source: MusicSource.netease)],
          0,
          QueueSource.none,
        );
        expect(resolver.requests, ['0']);
        expect(engine.loadedUrls, hasLength(1));
        expectFinished(playback);
        await playback.retryCurrentTrack();
        expect(playback.state, PBState.playing);
        expect(playback.isTrackSwitchPending, isFalse);
      } finally {
        playback.dispose();
        await AudioSourceService().removeSource('playback-test-source');
      }
    },
  );

  for (final refreshed in [false, true]) {
    test(
      'audio 403 refresh is bounded and checks URL identity (new=$refreshed)',
      () async {
        await configureTestSource();
        final resolver = _Resolver()
          ..playable.add('0')
          ..refreshUrl = refreshed;
        final engine = _Engine()..nextError = EngineErrorType.accessDenied;
        final playback = _createPlayback(resolver, engine: engine);
        try {
          await playback.playNow(
            [track(0, source: MusicSource.netease)],
            0,
            QueueSource.none,
          );
          expect(resolver.requests, ['0', '0']);
          expect(engine.loadedUrls, hasLength(refreshed ? 2 : 1));
          if (refreshed) {
            expect(engine.loadedUrls.toSet(), hasLength(2));
            expect(playback.state, PBState.playing);
            expect(playback.isTrackSwitchPending, isFalse);
          } else {
            expectFinished(playback);
            await playback.retryCurrentTrack();
            expect(playback.state, PBState.playing);
          }
        } finally {
          playback.dispose();
          await AudioSourceService().removeSource('playback-test-source');
        }
      },
    );
  }

  test(
    'Android source-read failure refreshes once without claiming HTTP status',
    () async {
      await configureTestSource();
      final resolver = _Resolver()..playable.add('0');
      final engine = _Engine()
        ..nextError = EngineErrorType.sourceLoad
        ..nextErrorCause = ja.PlayerException(0, 'Source error', 0);
      final playback = _createPlayback(resolver, engine: engine);
      try {
        await playback.playNow(
          [track(0, source: MusicSource.netease)],
          0,
          QueueSource.none,
        );
        expect(resolver.requests, ['0', '0']);
        expect(engine.loadedUrls, hasLength(1));
        expectFinished(playback);
      } finally {
        playback.dispose();
        await AudioSourceService().removeSource('playback-test-source');
      }
    },
  );

  test(
    'navigation spends requests on distinct tracks and preserves the actual failure target',
    () async {
      final resolver = _Resolver();
      final playback = _createPlayback(resolver);
      final tracks = List.generate(6, track);
      try {
        await playback.playNow(tracks, 0, QueueSource.none);
        expect(resolver.requests, [
          '0',
          '0',
        ]); // Explicit selection retries once.
        resolver.requests.clear();
        await playback.next();
        expect(resolver.requests, ['1', '2']);
        expectFinished(playback);
        expect(playback.problemNotifier.value?.track.id, '2');
        resolver.requests.clear();
        await playback.retryCurrentTrack();
        expect(resolver.requests, [
          '2',
          '2',
        ]); // Unrequested 3/4/5 are not failed.
        resolver.requests.clear();
        await playback.next();
        expect(resolver.requests, ['3', '4']);
        expectFinished(playback);
        resolver.requests.clear();
        await playback.previous();
        expect(resolver.requests, ['3', '2']);
      } finally {
        playback.dispose();
      }
    },
  );

  test(
    'a failed candidate is skipped and the next playable track commits',
    () async {
      final resolver = _Resolver()..playable.add('2');
      final playback = _createPlayback(resolver);
      try {
        await playback.playNow(List.generate(3, track), 0, QueueSource.none);
        resolver.requests.clear();
        await playback.next();
        expect(resolver.requests, ['1', '2']);
        expect(playback.currentTrack?.id, '2');
        expect(playback.isTrackSwitchPending, isFalse);
        expect(playback.errorMessage, isNull);
      } finally {
        playback.dispose();
      }
    },
  );

  test(
    'memory URL remains playable after the remote request allowance is spent',
    () async {
      final resolver = _Resolver()..memoryPlayable.add('3');
      final playback = _createPlayback(resolver);
      try {
        await playback.playNow(List.generate(4, track), 0, QueueSource.none);
        resolver.requests.clear();
        await playback.next();
        expect(resolver.requests, ['1', '2']);
        expect(playback.currentTrack?.id, '3');
        expect(playback.state, PBState.playing);
        expect(playback.isTrackSwitchPending, isFalse);
      } finally {
        playback.dispose();
      }
    },
  );

  test(
    'automatic completion skips an unavailable song without retrying it',
    () async {
      final resolver = _Resolver()..playable.addAll(['0', '2']);
      final engine = _Engine();
      final playback = _createPlayback(resolver, engine: engine);
      try {
        await playback.playNow(List.generate(3, track), 0, QueueSource.none);
        resolver.requests.clear();
        engine.complete();
        await waitUntil(() => playback.currentTrack?.id == '2');
        expect(resolver.requests, ['1', '2']);
        expect(playback.state, PBState.playing);
        expect(playback.isTrackSwitchPending, isFalse);
        expect(playback.errorMessage, isNull);
      } finally {
        playback.dispose();
      }
    },
  );

  test(
    'failed navigation preserves audio and later next starts after failure',
    () async {
      final resolver = _Resolver()..playable.add('0');
      final playback = _createPlayback(resolver);
      try {
        await playback.playNow(List.generate(6, track), 0, QueueSource.none);
        resolver.requests.clear();
        await playback.next();
        expect(resolver.requests, ['1', '2']);
        expect(playback.currentTrack?.id, '0');
        expect(playback.state, PBState.playing);
        expect(playback.isTrackSwitchPending, isFalse);
        expect(playback.currentProblem?.track.id, '2');
        resolver.playable.add('3');
        resolver.requests.clear();
        await playback.next();
        expect(resolver.requests, ['3']);
        expect(playback.currentTrack?.id, '3');
      } finally {
        playback.dispose();
      }
    },
  );

  test('reordering retains the failed entry identity for navigation', () async {
    final resolver = _Resolver();
    final playback = _createPlayback(resolver);
    try {
      await playback.playNow(List.generate(5, track), 0, QueueSource.none);
      await playback.jumpTo(1);
      await playback.reorder(1, 3);
      resolver.playable.add('4');
      resolver.requests.clear();
      await playback.next();
      expect(resolver.requests, ['4']);
      expect(playback.currentTrack?.id, '4');
    } finally {
      playback.dispose();
    }
  });

  test(
    'next during a slow request starts after pending target; late failure cannot overwrite it',
    () async {
      final resolver = _Resolver()..playable.add('2');
      final gate = Completer<TrackResolutionResult>();
      resolver.gates['1'] = gate;
      final playback = _createPlayback(resolver);
      try {
        final tracks = List.generate(3, track);
        await playback.playNow(tracks, 0, QueueSource.none);
        resolver.requests.clear();
        final old = playback.jumpTo(1);
        await waitUntil(() => resolver.requests.contains('1'));
        await playback.next();
        expect(resolver.requests, ['1', '2']);
        expect(playback.currentTrack?.id, '2');
        gate.complete(_Resolver.failure);
        await old;
        expect(resolver.requests, ['1', '2']);
        expect(playback.currentTrack?.id, '2');
        expect(playback.errorMessage, isNull);
        expect(playback.isTrackSwitchPending, isFalse);
      } finally {
        if (!gate.isCompleted) gate.complete(_Resolver.failure);
        playback.dispose();
      }
    },
  );

  test(
    'resume after a failed load and cancelled navigation reloads displayed track',
    () async {
      final resolver = _Resolver()..playable.addAll(['0', '1']);
      final engine = _Engine();
      final playback = _createPlayback(resolver, engine: engine);
      final gate = Completer<TrackResolutionResult>();
      try {
        await playback.playNow(List.generate(3, track), 0, QueueSource.none);
        engine.failNextLoad = true;
        await playback.next();
        expectFinished(playback);
        expect(playback.currentTrack?.id, '0');
        resolver.gates['1'] = gate;
        resolver.requests.clear();
        final switching = playback.jumpTo(1);
        await waitUntil(() => resolver.requests.contains('1'));
        await playback.pause();
        gate.complete(_Resolver.failure);
        await switching;
        expect(playback.state, PBState.paused);
        expect(playback.isTrackSwitchPending, isFalse);
        resolver.requests.clear();
        await playback.resume();
        expect(resolver.requests, ['0']);
        expect(engine.resumeCount, 0);
        expect(playback.currentTrack?.id, '0');
        expect(playback.state, PBState.playing);
        expect(playback.isTrackSwitchPending, isFalse);
      } finally {
        if (!gate.isCompleted) gate.complete(_Resolver.failure);
        playback.dispose();
      }
    },
  );

  test('valid paused source resumes without resolving again', () async {
    final resolver = _Resolver()..playable.add('0');
    final engine = _Engine();
    final playback = _createPlayback(resolver, engine: engine);
    try {
      await playback.playNow([track(0)], 0, QueueSource.none);
      await playback.pause();
      await waitUntil(() => playback.state == PBState.paused);
      resolver.requests.clear();
      await playback.resume();
      await waitUntil(() => playback.state == PBState.playing);
      expect(resolver.requests, isEmpty);
      expect(engine.resumeCount, 1);
    } finally {
      playback.dispose();
    }
  });

  test(
    'removing a failed entry falls back to the current queue and replacement clears failure target',
    () async {
      final resolver = _Resolver();
      final playback = _createPlayback(resolver);
      try {
        await playback.playNow(List.generate(4, track), 0, QueueSource.none);
        await playback.jumpTo(1);
        await playback.removeAt(1);
        resolver.requests.clear();
        await playback.next();
        expect(resolver.requests, ['2', '3']);
        await playback.playNow([track(10), track(11)], 0, QueueSource.none);
        resolver.requests.clear();
        await playback.next();
        expect(resolver.requests.first, '11');
        expectFinished(playback);
      } finally {
        playback.dispose();
      }
    },
  );
}

PlaybackService _createPlayback(_Resolver resolver, {_Engine? engine}) =>
    PlaybackService.forTesting(
      engine: EngineHost(engineFactory: () => engine ?? _Engine()),
      resolver: resolver,
    );

Future<void> configureTestSource() => AudioSourceService().addSource(
  AudioSourceConfig(
    id: 'playback-test-source',
    type: AudioSourceType.lxmusic,
    name: 'Test resolver',
    url: '',
    supportedPlatforms: const ['netease'],
  ),
);

Track track(int id, {MusicSource source = MusicSource.local}) => Track(
  id: '$id',
  name: 'Track $id',
  artists: '',
  album: '',
  picUrl: '',
  source: source,
);

void expectFinished(PlaybackService playback) {
  expect(playback.state, PBState.error);
  expect(playback.isTrackSwitchPending, isFalse);
  expect(playback.viewState.isSwitching, isFalse);
  expect(playback.pendingPlaybackIntent, isNull);
}

Future<void> waitUntil(bool Function() ready) async {
  for (var i = 0; i < 100 && !ready(); i++) {
    await Future<void>.delayed(const Duration(milliseconds: 1));
  }
  expect(ready(), isTrue);
}

class _Resolver extends TrackResolver {
  bool refreshUrl = false;
  final memoryPlayable = <String>{};

  @override
  TrackResolutionResult? peekResolved({
    required dynamic songId,
    required AudioQuality quality,
    required MusicSource source,
    bool fetchLyrics = false,
    String? resolverFingerprint,
  }) => memoryPlayable.contains(songId.toString())
      ? TrackResolutionResult(
          detail: SongDetail(
            id: songId.toString(),
            name: 'Memory track',
            pic: '',
            arName: '',
            alName: '',
            level: 'standard',
            size: '',
            url: File('pubspec.yaml').absolute.path,
            lyric: '',
            tlyric: '',
            source: source,
          ),
          isL1CacheHit: true,
        )
      : null;
  final requests = <String>[];
  final playable = <String>{};
  final gates = <String, Completer<TrackResolutionResult>>{};
  static const failure = TrackResolutionResult(
    detail: null,
    lxFailure: LxRuntimeFailure(
      kind: LxRuntimeFailureKind.timeout,
      message: 'test timeout',
    ),
  );

  @override
  Future<TrackLookupResult> lookupLocalOrCache({
    required Track track,
    required String quality,
    String? resolverFingerprint,
    bool skipCache = false,
  }) async => const TrackLookupResult(
    resolvedDetail: null,
    cacheInfo: null,
    isCached: false,
    localFileMissing: false,
    shouldRefreshCachedMetadata: false,
  );

  @override
  Future<TrackResolutionResult> resolve({
    required dynamic songId,
    required AudioQuality quality,
    required MusicSource source,
    required String title,
    required String artist,
    TrackSourceIds sourceIds = const TrackSourceIds(),
    required Duration timeout,
    bool fetchLyrics = true,
    String? resolverFingerprint,
    bool skipMemoryCache = false,
    bool Function()? acceptResult,
  }) async {
    final id = songId.toString();
    requests.add(id);
    final gate = gates.remove(id);
    if (gate != null) return gate.future;
    if (!playable.contains(id)) return failure;
    return TrackResolutionResult(
      detail: SongDetail(
        id: id,
        name: title,
        pic: '',
        arName: '',
        alName: '',
        level: 'standard',
        size: '',
        url: source == MusicSource.local
            ? File('pubspec.yaml').absolute.path
            : 'https://example.test/$id-${refreshUrl ? requests.length : 0}.mp3',
        lyric: '',
        tlyric: '',
        source: source,
      ),
    );
  }
}

class _Engine extends Fake implements AudioEngine {
  EngineErrorType? nextError;
  Object? nextErrorCause;
  final loadedUrls = <String?>[];
  bool failNextLoad = false;
  int resumeCount = 0;
  int? loadedGeneration;
  @override
  bool canResumeSource(int generation) => loadedGeneration == generation;
  bool _playing = false;
  final _states = StreamController<EngineState>.broadcast();
  final _completed = StreamController<bool>.broadcast();

  void complete() {
    _playing = false;
    _completed.add(true);
  }

  @override
  bool get isPlaying => _playing;
  @override
  Duration get position => Duration.zero;
  @override
  Duration get duration => const Duration(minutes: 3);
  @override
  Duration get bufferedPosition => Duration.zero;
  @override
  Stream<Duration> get positionStream => const Stream.empty();
  @override
  Stream<Duration> get durationStream => const Stream.empty();
  @override
  Stream<Duration> get bufferedPositionStream => const Stream.empty();
  @override
  Stream<EngineState> get stateStream => _states.stream;
  @override
  Stream<bool> get completionStream => _completed.stream;
  @override
  Stream<EngineError> get errorStream => const Stream.empty();
  @override
  Stream<EngineSourceCommit> get sourceCommitStream => const Stream.empty();
  @override
  EngineStartupTiming? get lastStartupTiming => null;
  @override
  Future<void> playSource(
    PlayableSource source, {
    required int generation,
    bool autoPlay = true,
    Duration? initialPosition,
    bool preload = true,
    Duration? loadTimeout,
  }) async {
    loadedUrls.add(source.sourceUrl);
    final error = nextError;
    nextError = null;
    if (error != null) {
      loadedGeneration = null;
      _playing = false;
      throw EngineReportedException(
        EngineError(
          type: error,
          message: 'test stream failure',
          sourceUrl: source.sourceUrl,
          cause: nextErrorCause,
          retriable: error != EngineErrorType.accessDenied,
          epoch: generation,
        ),
      );
    }
    if (failNextLoad) {
      failNextLoad = false;
      loadedGeneration = null;
      _playing = false;
      throw EngineReportedException(
        EngineError(
          type: EngineErrorType.networkTimeout,
          message: 'native load timeout',
          cause: NativePlaybackTimeout('load_source', TimeoutException('test')),
          epoch: generation,
        ),
      );
    }
    loadedGeneration = generation;
    _playing = autoPlay;
    _states.add(autoPlay ? EngineState.playing : EngineState.paused);
  }

  @override
  Future<void> invalidatePreparedSlots() async {}
  @override
  Future<void> bindCurrentPreparedSlot(PreparedPlaybackSlot slot) async {}
  @override
  Future<void> stop() async {
    loadedGeneration = null;
    _playing = false;
  }

  @override
  Future<void> pause() async {
    _playing = false;
    _states.add(EngineState.paused);
  }

  @override
  Future<void> resume() async {
    resumeCount++;
    _playing = true;
    _states.add(EngineState.playing);
  }

  @override
  Future<void> dispose() async {
    await _states.close();
    await _completed.close();
  }
}
