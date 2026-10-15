import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:cyrene_music/models/song_detail.dart';
import 'package:cyrene_music/models/audio_source_config.dart';
import 'package:cyrene_music/services/audio_source_service.dart';
import 'package:cyrene_music/models/track.dart';
import 'package:cyrene_music/services/auth_service.dart';
import 'package:cyrene_music/services/cache_service.dart';
import 'package:cyrene_music/services/lx_runtime_interface.dart';
import 'package:cyrene_music/services/lyric/lyric_cache_service.dart';
import 'package:cyrene_music/services/playback/audio_engine.dart';
import 'package:cyrene_music/services/playback/engine_host.dart';
import 'package:cyrene_music/services/playback/playable_source.dart';
import 'package:cyrene_music/services/playback/playback_service.dart';
import 'package:cyrene_music/services/playback/queue_controller.dart';
import 'package:cyrene_music/services/playback/track_resolver.dart';
import 'package:cyrene_music/services/playback/startup_network_gate.dart';
import 'package:cyrene_music/services/playback/playback_transition.dart';
import 'package:cyrene_music/services/structured_log_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/services.dart';
import 'package:just_audio/just_audio.dart' as ja;
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory testDirectory;
  setUpAll(() async {
    testDirectory = await Directory.systemTemp.createTemp('cyrene-navigation-');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (_) async => testDirectory.path,
        );
    SharedPreferences.setMockInitialValues({
      'cache_enabled': false,
      'custom_cache_dir': testDirectory.path,
      'auth_token': 'test-token',
      'current_user': jsonEncode({
        'id': 1,
        'username': 'test',
        'email': 'test@example.invalid',
      }),
    });
    await AuthService().ensureInitialized();
    await LyricCacheService().initialize();
  });
  tearDownAll(() async {
    AuthService().onSessionEnded = null;
    await AuthService().logout();
    await testDirectory.delete(recursive: true);
  });

  test(
    'remote playback writes an uncached song through background cache',
    () async {
      await configureTestSource();
      final cache = CacheService();
      await cache.initialize();
      await cache.setCacheEnabled(true);
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      var downloads = 0;
      server.listen((request) async {
        downloads++;
        request.response.headers.contentType = ContentType('audio', 'mpeg');
        request.response.add([0x49, 0x44, 0x33, 0, 0, 0, 0, 0]);
        await request.response.close();
      });
      final resolver = _Resolver()
        ..playable.add('0')
        ..urlOverride = 'http://127.0.0.1:${server.port}/cache.mp3';
      final engine = _Engine();
      final playback = _createPlayback(resolver, engine: engine);
      final target = _remoteTracks(1).single;
      final realHttp = _RealHttpOverrides();
      await HttpOverrides.runZoned(() async {
        try {
          await playback.playNow([target], 0, QueueSource.none);
          expect(cache.isCached(target), isFalse);
          expect(downloads, 0);
          engine.positionValue = const Duration(seconds: 1);
          engine._positions.add(engine.positionValue);
          for (var i = 0; i < 100 && !cache.isCached(target); i++) {
            await Future<void>.delayed(const Duration(milliseconds: 50));
          }
          expect(cache.isCached(target), isTrue);
          expect(downloads, 1);
          expect(playback.state, PBState.playing);
        } finally {
          playback.dispose();
          await server.close(force: true);
          await cache.clearAllCache();
          await cache.setCacheEnabled(false);
          await AudioSourceService().removeSource('playback-test-source');
        }
      }, createHttpClient: realHttp.createHttpClient);
    },
  );

  test(
    'repeated playing events do not starve next-track preparation',
    () async {
      await configureTestSource();
      final resolver = _Resolver()..playable.addAll(['0', '1']);
      final engine = _Engine();
      final playback = _createPlayback(resolver, engine: engine);
      Timer? repeated;
      try {
        await playback.playNow(_remoteTracks(2), 0, QueueSource.none);
        repeated = Timer.periodic(const Duration(milliseconds: 200), (_) {
          engine._states.add(EngineState.playing);
        });
        await engine.prepared.future.timeout(const Duration(seconds: 4));
        expect(playback.currentTrack?.id, '0');
        expect(playback.state, PBState.playing);
      } finally {
        repeated?.cancel();
        playback.dispose();
        await AudioSourceService().removeSource('playback-test-source');
      }
    },
  );

  test(
    'prepared success waits for activation and records one timing sample',
    () async {
      await configureTestSource();
      final resolver = _Resolver()..playable.addAll(['0', '1']);
      final engine = _Engine()..emitEarlyCommit = true;
      final playback = _createPlayback(resolver, engine: engine);
      final gate = Completer<bool>();
      engine.activationGate = gate;
      final logs = <String>[];
      StructuredLogService.sink = logs.add;
      try {
        await playback.playNow(_remoteTracks(2), 0, QueueSource.none);
        await engine.prepared.future.timeout(const Duration(seconds: 5));
        final baseline = playback.performanceSnapshot.completedSwitches;
        final next = playback.next();
        await engine.activationStarted.future;
        await Future<void>.delayed(const Duration(milliseconds: 25));
        expect(playback.currentTrack?.id, '0');
        expect(playback.performanceSnapshot.completedSwitches, baseline);
        gate.complete(true);
        await next;
        expect(playback.currentTrack?.id, '1');
        expect(playback.performanceSnapshot.completedSwitches, baseline + 1);
        expect(playback.performanceSnapshot.preparedEngineHits, 1);
        expect(playback.performanceSnapshot.preparedActivation.count, 1);
        expect(
          playback.performanceSnapshot.preparedActivation.minMs,
          greaterThanOrEqualTo(25),
        );
        // A duplicate/late source event cannot count another switch.
        engine.commitPrepared();
        await Future<void>.delayed(Duration.zero);
        expect(playback.performanceSnapshot.completedSwitches, baseline + 1);
        final timing = logs
            .map(jsonDecode)
            .where(
              (e) =>
                  e['event'] == 'playback.switch.timing' &&
                  e['prepared_engine_hit'] == true,
            )
            .single;
        expect(timing['activation_ms'], greaterThanOrEqualTo(25));
        expect(timing['generation'], engine.loadedGeneration);
      } finally {
        if (!gate.isCompleted) gate.complete(false);
        StructuredLogService.sink = null;
        playback.dispose();
        await AudioSourceService().removeSource('playback-test-source');
      }
    },
  );

  for (final retryable in [false, true]) {
    test(
      'natural next failure targets next and releases pending (retry=$retryable)',
      () async {
        await configureTestSource();
        final resolver = _Resolver()
          ..refreshUrl = true
          ..playable.addAll(['0', '1', '2']);
        final engine = _Engine();
        final playback = _createPlayback(resolver, engine: engine);
        try {
          await playback.playNow(_remoteTracks(3), 0, QueueSource.none);
          await engine.prepared.future.timeout(const Duration(seconds: 5));
          final failedSlot = engine.preparedSlot!;
          final previousLoadCount = engine.loadedUrls.length;
          engine._playing = false;
          engine._errors.add(
            EngineError(
              type: retryable
                  ? EngineErrorType.accessDenied
                  : EngineErrorType.unsupportedFormat,
              message: 'selected next failed before ready',
              epoch: failedSlot.generation,
              retriable: retryable,
            ),
          );
          if (retryable) {
            await waitUntil(() => playback.currentTrack?.id == '1');
            expect(playback.state, PBState.playing);
            expect(engine.loadedUrls.skip(previousLoadCount), isNotEmpty);
            expect(
              engine.loadedUrls
                  .skip(previousLoadCount)
                  .every((url) => url!.contains('/1-')),
              isTrue,
            );
          } else {
            await waitUntil(() => playback.state == PBState.error);
            expectFinished(playback);
            expect(playback.currentTrack?.id, '0');
            expect(playback.currentProblem?.track.id, '1');
            // A late ready event must not turn this failed item into success.
            engine.commitPrepared();
            await Future<void>.delayed(Duration.zero);
            expect(playback.state, PBState.error);
            await playback.jumpTo(2);
            expect(playback.currentTrack?.id, '2');
            expect(playback.state, PBState.playing);
          }
          expect(playback.isTrackSwitchPending, isFalse);
          final latestTrack = playback.currentTrack;
          // The failed native epoch cannot undo a newer manual/successful load.
          engine._errors.add(
            EngineError(
              type: EngineErrorType.unsupportedFormat,
              message: 'late failure',
              epoch: failedSlot.generation,
            ),
          );
          await Future<void>.delayed(Duration.zero);
          expect(playback.currentTrack, latestTrack);
          expect(playback.state, PBState.playing);
        } finally {
          playback.dispose();
          await AudioSourceService().removeSource('playback-test-source');
        }
      },
    );
  }

  for (final originalError in [false, true]) {
    test(
      'prepared timeout finishes with recoverable error (original=$originalError)',
      () async {
        await configureTestSource();
        final resolver = _Resolver()..playable.addAll(['0', '1']);
        final engine = _Engine()
          ..failActivation = true
          ..activationDelay = const Duration(milliseconds: 10100)
          ..activationError = originalError
              ? EngineError(
                  type: EngineErrorType.unsupportedFormat,
                  message: 'prepared codec rejected',
                  retriable: false,
                )
              : null;
        final playback = _createPlayback(resolver, engine: engine);
        try {
          await playback.playNow(_remoteTracks(2), 0, QueueSource.none);
          await engine.prepared.future.timeout(const Duration(seconds: 5));
          await playback.next();
          expectFinished(playback);
          expect(playback.errorMessage, isNotEmpty);
          expect(playback.currentProblem?.message, playback.errorMessage);
          expect(playback.currentProblem?.track.id, '1');
          expect(playback.performanceSnapshot.preparedEngineHits, 0);
          if (originalError) {
            expect(playback.errorMessage, '播放失败: 当前格式不受支持');
            expect(playback.currentProblem?.canRetry, isFalse);
            await playback.playNow([track(2)], 0, QueueSource.none);
            expectFinished(playback);
            // The next action executes and reports its own failure.
            expect(playback.errorMessage, isNot('播放失败: 当前格式不受支持'));
          } else {
            expect(playback.currentProblem?.canRetry, isTrue);
            await playback.retryCurrentTrack();
            expect(playback.state, PBState.playing);
            expect(playback.currentTrack?.id, '1');
            expect(playback.errorMessage, isNull);
          }
        } finally {
          playback.dispose();
          await AudioSourceService().removeSource('playback-test-source');
        }
      },
    );
  }

  for (final accepted in [false, true]) {
    test(
      'cancelled prepared activation cannot fail or count a newer selection (success=$accepted)',
      () async {
        await configureTestSource();
        final resolver = _Resolver()..playable.addAll(['0', '1', '2']);
        final engine = _Engine();
        final playback = _createPlayback(resolver, engine: engine);
        final gate = Completer<bool>();
        engine.activationGate = gate;
        try {
          await playback.playNow(_remoteTracks(3), 0, QueueSource.none);
          await engine.prepared.future.timeout(const Duration(seconds: 5));
          final old = playback.next();
          await engine.activationStarted.future;
          final latest = playback.jumpTo(2);
          await Future<void>.delayed(const Duration(milliseconds: 10));
          gate.complete(accepted);
          await Future.wait([old, latest]);
          expect(playback.currentTrack?.id, '2');
          expect(playback.state, PBState.playing);
          expect(playback.errorMessage, isNull);
          expect(playback.isTrackSwitchPending, isFalse);
          expect(playback.performanceSnapshot.preparedEngineHits, 0);
        } finally {
          if (!gate.isCompleted) gate.complete(false);
          playback.dispose();
          await AudioSourceService().removeSource('playback-test-source');
        }
      },
    );
  }

  test('rapid remote selections only resolve the latest target', () async {
    await configureTestSource();
    final resolver = _Resolver()..playable.addAll(['0', '1', '2']);
    final playback = _createPlayback(resolver);
    final tracks = List.generate(
      3,
      (i) => track(i, source: MusicSource.netease),
    );
    try {
      final first = playback.playNow(tracks, 0, QueueSource.none);
      await Future<void>.delayed(const Duration(milliseconds: 40));
      final second = playback.jumpTo(1);
      await Future<void>.delayed(const Duration(milliseconds: 40));
      final last = playback.jumpTo(2);
      await Future.wait([first, second, last]);
      expect(resolver.requests, ['2']);
      expect(playback.currentTrack?.id, '2');
      expect(playback.isTrackSwitchPending, isFalse);
      expect(playback.state, PBState.playing);
    } finally {
      playback.dispose();
      await AudioSourceService().removeSource('playback-test-source');
    }
  });

  test(
    'rapid cached URL selections only load the latest native source',
    () async {
      await configureTestSource();
      final resolver = _Resolver()..memoryPlayable.addAll(['0', '1', '2']);
      final engine = _Engine();
      final playback = _createPlayback(resolver, engine: engine);
      final tracks = List.generate(
        3,
        (i) => track(i, source: MusicSource.netease),
      );
      try {
        final first = playback.playNow(tracks, 0, QueueSource.none);
        await Future<void>.delayed(const Duration(milliseconds: 40));
        final second = playback.jumpTo(1);
        await Future<void>.delayed(const Duration(milliseconds: 40));
        final last = playback.jumpTo(2);
        await Future.wait([first, second, last]);
        expect(resolver.urlRequests, isEmpty);
        expect(engine.loadedUrls, hasLength(1));
        expect(playback.currentTrack?.id, '2');
        expect(playback.state, PBState.playing);
      } finally {
        playback.dispose();
        await AudioSourceService().removeSource('playback-test-source');
      }
    },
  );

  test('stop during selection debounce sends no remote request', () async {
    await configureTestSource();
    final resolver = _Resolver()..playable.add('0');
    final playback = _createPlayback(resolver);
    try {
      final selection = playback.playNow(
        [track(0, source: MusicSource.netease)],
        0,
        QueueSource.none,
      );
      await Future<void>.delayed(const Duration(milliseconds: 40));
      await playback.stop();
      await selection;
      expect(resolver.requests, isEmpty);
      expect(playback.state, PBState.idle);
      expect(playback.isTrackSwitchPending, isFalse);
    } finally {
      playback.dispose();
      await AudioSourceService().removeSource('playback-test-source');
    }
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

  for (final cancelAction in ['pause', 'next', 'source']) {
    test('startup offline wait yields to $cancelAction', () async {
      await configureTestSource();
      final events = StreamController<StartupNetworkStatus>.broadcast();
      final resolver = _Resolver()..playable.addAll(['0', '1']);
      final engine = _Engine();
      final playback = _createPlayback(
        resolver,
        engine: engine,
        startupNetworkGateFactory: () => StartupNetworkGate(
          check: () async => StartupNetworkStatus.unavailable,
          changes: events.stream,
          cancellationInterval: const Duration(milliseconds: 5),
        ),
      );
      try {
        final restoring = playback.playNow(
          _remoteTracks(2),
          0,
          QueueSource.none,
          intent: PlaybackRequestIntent.restore,
        );
        await waitUntil(() => playback.errorMessage == '等待网络连接…');
        expect(resolver.requests, isEmpty);
        final observedPending = <bool>[];
        playback.addListener(
          () => observedPending.add(playback.isTrackSwitchPending),
        );
        switch (cancelAction) {
          case 'pause':
            await playback.pause();
          case 'next':
            await playback.next();
          case 'source':
            AudioSourceService().refresh();
        }
        await restoring.timeout(const Duration(seconds: 2));
        expect(playback.isTrackSwitchPending, isFalse);
        expect(playback.errorMessage, isNull);
        expect(observedPending, contains(false));
        events.add(StartupNetworkStatus.available);
        await Future<void>.delayed(const Duration(milliseconds: 20));
        expect(resolver.urlRequests, cancelAction == 'next' ? ['1'] : isEmpty);
        expect(
          engine.loadedUrls,
          cancelAction == 'next' ? hasLength(1) : isEmpty,
        );
        expect(events.hasListener, isFalse);
      } finally {
        playback.dispose();
        await events.close();
      }
    });
  }

  test(
    'startup offline deadline releases UI without calling the source',
    () async {
      await configureTestSource();
      final events = StreamController<StartupNetworkStatus>.broadcast();
      final resolver = _Resolver();
      final playback = _createPlayback(
        resolver,
        startupNetworkGateFactory: () => StartupNetworkGate(
          check: () async => StartupNetworkStatus.unavailable,
          changes: events.stream,
          maxWait: const Duration(milliseconds: 30),
        ),
      );
      try {
        await playback.playNow(
          _remoteTracks(1),
          0,
          QueueSource.none,
          intent: PlaybackRequestIntent.restore,
        );
        expectFinished(playback);
        expect(resolver.requests, isEmpty);
        expect(playback.errorMessage, '网络尚未连接，请联网后重试');
        expect(playback.currentTrack, isNull);
        expect(playback.viewState.track?.id, '0');
        expect(playback.displayTitle, 'Track 0');
        expect(playback.viewState.effectivePlaying, isFalse);
        expect(
          playback.sourceHealthNotifier.value?.consecutiveTransientFailures,
          0,
        );
        expect(
          playback.sourceHealthNotifier.value?.consecutiveSystemicFailures,
          0,
        );
        events.add(StartupNetworkStatus.available);
        await Future<void>.delayed(const Duration(milliseconds: 20));
        expect(resolver.requests, isEmpty);
        expect(playback.state, PBState.error);
        expect(events.hasListener, isFalse);
      } finally {
        playback.dispose();
        await events.close();
      }
    },
  );

  test('startup resumes exactly once when connectivity returns', () async {
    await configureTestSource();
    final events = StreamController<StartupNetworkStatus>.broadcast();
    final resolver = _Resolver()..playable.add('0');
    final engine = _Engine();
    final playback = _createPlayback(
      resolver,
      engine: engine,
      startupNetworkGateFactory: () => StartupNetworkGate(
        check: () async => StartupNetworkStatus.unavailable,
        changes: events.stream,
      ),
    );
    try {
      final restoring = playback.playNow(
        _remoteTracks(1),
        0,
        QueueSource.none,
        intent: PlaybackRequestIntent.restore,
      );
      await waitUntil(() => playback.errorMessage == '等待网络连接…');
      expect(resolver.requests, isEmpty);
      events.add(StartupNetworkStatus.available);
      events.add(StartupNetworkStatus.available);
      await restoring;
      expect(resolver.urlRequests, ['0']);
      expect(engine.loadedUrls, hasLength(1));
      expect(playback.state, PBState.playing);
      expect(playback.errorMessage, isNull);
      expect(playback.isTrackSwitchPending, isFalse);
      expect(events.hasListener, isFalse);
    } finally {
      playback.dispose();
      await events.close();
    }
  });

  test('startup retries an unreachable network only once', () async {
    await configureTestSource();
    final first = Completer<TrackResolutionResult>();
    final resolver = _Resolver()..gates['0'] = first;
    final playback = _createPlayback(
      resolver,
      startupNetworkGateFactory: () => StartupNetworkGate(
        check: () async => StartupNetworkStatus.available,
        changes: const Stream.empty(),
      ),
    );
    try {
      final restoring = playback.playNow(
        _remoteTracks(1),
        0,
        QueueSource.none,
        intent: PlaybackRequestIntent.restore,
      );
      await waitUntil(() => resolver.requests.isNotEmpty);
      first.complete(
        const TrackResolutionResult(
          detail: null,
          lxFailure: LxRuntimeFailure(
            kind: LxRuntimeFailureKind.networkUnavailable,
            message: 'Network is unreachable',
          ),
        ),
      );
      await restoring;
      // The second fixture response is a timeout, which cannot cause a third request.
      expect(resolver.requests, ['0', '0']);
      expectFinished(playback);
      expect(playback.errorMessage, contains('超时'));
    } finally {
      playback.dispose();
    }
  });

  test('startup does not repeat ordinary source failures', () async {
    await configureTestSource();
    final resolver = _Resolver();
    final playback = _createPlayback(
      resolver,
      startupNetworkGateFactory: () => StartupNetworkGate(
        check: () async => StartupNetworkStatus.available,
        changes: const Stream.empty(),
      ),
    );
    try {
      await playback.playNow(
        _remoteTracks(1),
        0,
        QueueSource.none,
        intent: PlaybackRequestIntent.restore,
      );
      expect(resolver.requests, ['0']);
      expectFinished(playback);
    } finally {
      playback.dispose();
    }
  });

  test('unreachable startup retry does not penalize source health', () async {
    await configureTestSource();
    final resolver = _Resolver()
      ..failureResponse = const TrackResolutionResult(
        detail: null,
        lxFailure: LxRuntimeFailure(
          kind: LxRuntimeFailureKind.networkUnavailable,
          message: 'Network is unreachable',
        ),
      );
    final playback = _createPlayback(
      resolver,
      startupNetworkGateFactory: () => StartupNetworkGate(
        check: () async => StartupNetworkStatus.available,
        changes: const Stream.empty(),
      ),
    );
    try {
      await playback.playNow(
        _remoteTracks(1),
        0,
        QueueSource.none,
        intent: PlaybackRequestIntent.restore,
      );
      expect(resolver.urlRequests, ['0', '0']);
      expectFinished(playback);
      expect(playback.errorMessage, '网络尚未连接，请联网后重试');
      expect(
        playback.sourceHealthNotifier.value?.consecutiveTransientFailures,
        0,
      );
      expect(
        playback.sourceHealthNotifier.value?.consecutiveSystemicFailures,
        0,
      );
    } finally {
      playback.dispose();
    }
  });

  test('startup with cached detail never waits for connectivity', () async {
    await configureTestSource();
    final resolver = _Resolver()..memoryPlayable.add('0');
    final playback = _createPlayback(
      resolver,
      startupNetworkGateFactory: () => throw StateError('must use cached URL'),
    );
    try {
      await playback.playNow(
        _remoteTracks(1),
        0,
        QueueSource.none,
        intent: PlaybackRequestIntent.restore,
      );
      expect(resolver.requests, isEmpty);
      expect(playback.currentTrack?.id, '0');
      expect(playback.state, PBState.playing);
    } finally {
      playback.dispose();
    }
  });

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

  for (final count in [1, 2]) {
    test(
      'removing first failed track clears presentation and retry ($count tracks)',
      () async {
        await configureTestSource();
        final resolver = _Resolver();
        final playback = _createPlayback(resolver);
        try {
          await playback.playNow(_remoteTracks(count), 0, QueueSource.none);
          final staleProblem = playback.currentProblem!;
          expect(playback.viewState.track?.id, '0');
          await playback.removeAt(0);
          expect(playback.viewState.track, isNull);
          expect(playback.displayTitle, isEmpty);
          expect(playback.errorMessage, isNull);
          expect(playback.currentProblem, isNull);
          expect(playback.state, PBState.idle);
          expect(playback.isTrackSwitchPending, isFalse);
          resolver.requests.clear();
          await playback.retryCurrentTrack(expectedProblem: staleProblem);
          await playback.retryCurrentTrack();
          expect(resolver.requests, isEmpty);
          if (count > 1) {
            resolver.playable.add('1');
            await playback.next();
            expect(playback.currentTrack?.id, '1');
            expect(playback.state, PBState.playing);
          }
        } finally {
          playback.dispose();
        }
      },
    );
  }

  test(
    'removing a duplicate entry preserves the actual failed target',
    () async {
      await configureTestSource();
      final playback = _createPlayback(_Resolver());
      try {
        final target = _remoteTracks(1).single;
        await playback.playNow([target, target], 0, QueueSource.none);
        final problem = playback.currentProblem;
        await playback.removeAt(1);
        expect(playback.viewState.track?.id, '0');
        expect(playback.currentProblem, same(problem));
        expect(playback.state, PBState.error);
      } finally {
        playback.dispose();
      }
    },
  );

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

  test(
    'late retry cannot restore a deleted failed entry over the next track',
    () async {
      await configureTestSource();
      final resolver = _Resolver();
      final engine = _Engine();
      final playback = _createPlayback(resolver, engine: engine);
      final lateResponse = Completer<TrackResolutionResult>();
      try {
        await playback.playNow(_remoteTracks(2), 0, QueueSource.none);
        resolver.requests.clear();
        resolver.gates['0'] = lateResponse;
        final retrying = playback.retryCurrentTrack();
        await waitUntil(() => resolver.requests.contains('0'));
        await playback.removeAt(0);
        expect(playback.isTrackSwitchPending, isFalse);
        expect(playback.currentProblem, isNull);
        resolver.playable.add('1');
        await playback.next();
        resolver.memoryPlayable.add('0');
        lateResponse.complete(
          resolver.peekResolved(
            songId: '0',
            quality: AudioQuality.standard,
            source: MusicSource.netease,
          ),
        );
        await retrying;
        expect(playback.currentTrack?.id, '1');
        expect(playback.state, PBState.playing);
        expect(playback.errorMessage, isNull);
        expect(engine.loadedUrls, hasLength(1));
      } finally {
        if (!lateResponse.isCompleted) lateResponse.complete(_Resolver.failure);
        playback.dispose();
      }
    },
  );
}

PlaybackService _createPlayback(
  _Resolver resolver, {
  _Engine? engine,
  StartupNetworkGate Function()? startupNetworkGateFactory,
}) => PlaybackService.forTesting(
  engine: EngineHost(engineFactory: () => engine ?? _Engine()),
  resolver: resolver,
  startupNetworkGateFactory: startupNetworkGateFactory,
);

List<Track> _remoteTracks(int count) =>
    List.generate(count, (i) => track(i, source: MusicSource.netease));

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
  final clock = Stopwatch()..start();
  while (!ready() && clock.elapsed < const Duration(seconds: 2)) {
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
  expect(ready(), isTrue);
}

class _RealHttpOverrides extends HttpOverrides {
  @override
  HttpClient createHttpClient(SecurityContext? context) {
    final client = super.createHttpClient(context);
    // This integration fixture may download only from its local server.
    // History/auth side effects must never contact a real backend.
    client.connectionFactory = (uri, proxyHost, proxyPort) {
      if (uri.host != '127.0.0.1') {
        throw const SocketException('External network disabled in test');
      }
      return Socket.startConnect(uri.host, uri.port);
    };
    return client;
  }
}

class _Resolver extends TrackResolver {
  String? urlOverride;
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
  final urlRequests = <String>[];
  final playable = <String>{};
  final gates = <String, Completer<TrackResolutionResult>>{};
  TrackResolutionResult failureResponse = failure;
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
    if (!fetchLyrics) urlRequests.add(id);
    final gate = gates.remove(id);
    if (gate != null) return gate.future;
    if (!playable.contains(id)) return failureResponse;
    return TrackResolutionResult(
      detail: SongDetail(
        id: id,
        name: title,
        pic: '',
        arName: '',
        alName: '',
        level: 'standard',
        size: '',
        url:
            urlOverride ??
            (source == MusicSource.local
                ? File('pubspec.yaml').absolute.path
                : 'https://example.test/$id-${refreshUrl ? requests.length : 0}.mp3'),
        lyric: '',
        tlyric: '',
        source: source,
      ),
    );
  }
}

class _Engine extends Fake implements AudioEngine {
  Duration positionValue = Duration.zero;
  final _positions = StreamController<Duration>.broadcast();
  final prepared = Completer<void>();
  final activationStarted = Completer<void>();
  PreparedPlaybackSlot? preparedSlot;
  Completer<bool>? activationGate;
  Duration activationDelay = Duration.zero;
  bool emitEarlyCommit = false;
  bool failActivation = false;
  EngineError? activationError;
  final _commits = StreamController<EngineSourceCommit>.broadcast();
  final _errors = StreamController<EngineError>.broadcast();
  void commitPrepared() {
    final slot = preparedSlot!;
    _commits.add(
      EngineSourceCommit(key: slot.key, generation: slot.generation),
    );
  }

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
  Duration get position => positionValue;
  @override
  Duration get duration => const Duration(minutes: 3);
  @override
  Duration get bufferedPosition => Duration.zero;
  @override
  Stream<Duration> get positionStream => _positions.stream;
  @override
  Stream<Duration> get durationStream => const Stream.empty();
  @override
  Stream<Duration> get bufferedPositionStream => const Stream.empty();
  @override
  Stream<EngineState> get stateStream => _states.stream;
  @override
  Stream<bool> get completionStream => _completed.stream;
  @override
  Stream<EngineError> get errorStream => _errors.stream;
  @override
  Stream<EngineSourceCommit> get sourceCommitStream => _commits.stream;
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
  Future<void> preparePlaybackWindow(PreparedPlaybackWindow window) async {
    if (window.next != null) {
      preparedSlot = window.next;
      if (!prepared.isCompleted) prepared.complete();
    }
  }

  @override
  Future<bool> activatePreparedSlot(
    String key, {
    required int generation,
    required int queueRevision,
    bool autoPlay = true,
    Duration? initialPosition,
    Duration? loadTimeout,
  }) async {
    if (!activationStarted.isCompleted) activationStarted.complete();
    if (emitEarlyCommit) commitPrepared();
    await Future<void>.delayed(activationDelay);
    final accepted = activationGate == null
        ? !failActivation
        : await activationGate!.future;
    if (accepted) {
      loadedGeneration = generation;
      _playing = autoPlay;
      _states.add(autoPlay ? EngineState.playing : EngineState.paused);
    } else {
      loadedGeneration = null;
      _playing = false;
      final error = activationError;
      if (error != null) _errors.add(error);
      await Future<void>.delayed(Duration.zero);
    }
    return accepted;
  }

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
    await _positions.close();
    await _commits.close();
    await _errors.close();
    await _states.close();
    await _completed.close();
  }
}
