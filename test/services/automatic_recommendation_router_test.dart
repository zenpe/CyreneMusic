import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:cyrene_music/services/automatic_recommendation_router.dart';
import 'package:cyrene_music/services/lx_quickjs_runtime.dart';
import 'package:cyrene_music/services/lx_runtime_interface.dart';
import 'package:cyrene_music/services/audio_source_service.dart';
import 'package:cyrene_music/services/lx_music_source_parser.dart';
import 'package:cyrene_music/models/audio_source_config.dart';
import 'package:cyrene_music/models/track.dart';
import 'package:cyrene_music/models/song_detail.dart';
import 'package:cyrene_music/services/playback/track_resolver.dart';
import 'package:cyrene_music/services/audio_cache_identity.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/fake_lx_runtime.dart';

AutomaticTarget target(String text) => AutomaticTarget(
  '$text.js',
  sha256.convert(utf8.encode(text)).toString(),
  text,
);
AutomaticPlan plan(String revision, Map<String, String> scripts) =>
    AutomaticPlan(
      'p-${revision * 32}',
      scripts.map((k, v) => MapEntry(k, target(v))),
    );

class ServerFixture {
  AutomaticPlan desired = plan('a', {'qq': 'qq-a', 'netease': 'wy-a'});
  final Map<String, String> scripts = {};
  final Set<String> fail = {};
  final List<String> conditional = [];
  final Map<String, Completer<void>> gates = {};
  void publish(AutomaticPlan value) {
    desired = value;
    for (final t in value.targets.values) {
      scripts[t.hash] = t.name;
    }
  }

  Future<AutomaticHttpResponse> fetch(
    String url,
    Map<String, String> headers,
    int limit,
  ) async {
    if (url.endsWith('/recommendation-plan')) {
      conditional.add(headers['If-None-Match'] ?? '');
      if (headers['If-None-Match'] == '"${desired.id}"') {
        return const AutomaticHttpResponse(304, []);
      }
      return AutomaticHttpResponse(
        200,
        utf8.encode(jsonEncode(desired.toJson())),
      );
    }
    if (url.endsWith('/recommendation-status')) {
      return AutomaticHttpResponse(
        200,
        utf8.encode('{"format":1,"platforms":{}}'),
      );
    }
    final hash = Uri.parse(url).pathSegments.last.replaceFirst('.js', '');
    final gate = gates[hash];
    if (gate != null) await gate.future;
    if (fail.contains(hash)) return const AutomaticHttpResponse(503, []);
    return AutomaticHttpResponse(200, utf8.encode(scripts[hash] ?? 'invalid'));
  }
}

class _OnlyQQ extends FakeLxRuntime {
  @override
  Future<LxScriptInfo?> loadScript(String content) async =>
      script = LxScriptInfo(
        name: content,
        version: '1',
        script: content,
        supportedSources: const ['tx'],
        supportedQualities: const ['128k'],
      );
}

class _ChangingCapabilities extends FakeLxRuntime {
  bool qqOnly = false;

  @override
  Future<LxScriptInfo?> loadScript(String content) async {
    if (!qqOnly) return super.loadScript(content);
    return script = await _OnlyQQ().loadScript(content);
  }
}

class _FailSelectionStore extends InMemorySharedPreferencesStore {
  _FailSelectionStore(super.data) : super.withData();
  @override
  Future<bool> setValue(String type, String key, Object value) async {
    if (key == 'flutter.audio_source_active_id' &&
        '$value'.startsWith('automatic_')) {
      return false;
    }
    return super.setValue(type, key, value);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory directory;
  late ServerFixture server;
  final routers = <AutomaticRecommendationRouter>[];
  final hosts = <AudioSourceService>[];
  AudioSourceService host() {
    final result = AudioSourceService.withDependencies(
      runtime: FakeLxRuntime(),
      parser: LxMusicSourceParser(),
      automaticFactory:
          ({required isCurrent, required selectionEpoch, required commit}) =>
              AutomaticRecommendationRouter(
                fetch: server.fetch,
                directory: () async => directory,
                runtimeFactory: FakeLxRuntime.new,
                isCurrent: isCurrent,
                selectionEpoch: selectionEpoch,
                commit: commit,
              ),
    );
    hosts.add(result);
    return result;
  }

  AutomaticRecommendationRouter router({LxRuntime Function()? factory}) {
    final result = AutomaticRecommendationRouter(
      fetch: server.fetch,
      directory: () async => directory,
      runtimeFactory: factory ?? FakeLxRuntime.new,
    );
    routers.add(result);
    return result;
  }

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    directory = await Directory.systemTemp.createTemp('automatic-router-');
    server = ServerFixture()
      ..publish(plan('a', {'qq': 'qq-a', 'netease': 'wy-a'}));
  });
  tearDown(() async {
    for (final h in hosts) {
      h.dispose();
    }
    hosts.clear();
    for (final r in routers) {
      r.dispose();
    }
    routers.clear();
    await Future<void>.delayed(Duration.zero);
    await directory.delete(recursive: true);
  });

  test('ordinary check recovers a shared runtime and rechecks each platform', () async {
    server.publish(plan('a', {'qq': 'shared', 'netease': 'shared'}));
    final runtime = _ChangingCapabilities();
    final r = router(factory: () => runtime);
    await r.start('https://backend.example');
    expect(runtime.isScriptReady, isTrue);
    expect(r.platforms, containsAll(['qq', 'netease']));
    runtime.qqOnly = true;
    runtime.script = null;
    expect(r.isReady, isFalse);
    await r.check();
    expect(server.conditional.last, '"${server.desired.id}"');
    expect(runtime.isScriptReady, isTrue);
    expect(r.platforms, ['qq']);
    expect(r.routeFor('netease'), isNull);
    expect(r.routes.keys, ['qq']);
    expect(r.platformErrors, contains('netease'));
    final requests = server.conditional.length;
    await r.check();
    expect(server.conditional.length, requests);
  });

  test('host selection persists, target updates preserve revision, manual selection retires automatic mode', () async {
    final h = host();
    await h.useAutomaticSource();
    final id = h.activeSource!.id;
    final revision = h.lxSourceRevision;
    server.publish(plan('b', {'qq': 'qq-b', 'netease': 'wy-a'}));
    await h.automaticRouter!.check(force: true);
    expect(h.lxSourceRevision, revision);
    expect(h.activeSource!.id, id);
    expect(
      h.automaticRouteFor(MusicSource.qq)!.target.hash,
      target('qq-b').hash,
    );
    final cold = host();
    await cold.initialize();
    expect(cold.activeSource!.id, id);
    expect(
      cold.automaticRouteFor(MusicSource.qq)!.target.hash,
      target('qq-b').hash,
    );
    await cold.automaticRouter!.check(force: true);
    await h.addSource(
      AudioSourceConfig(
        id: 'manual',
        type: AudioSourceType.lxmusic,
        name: 'manual',
        url: '',
        scriptContent: 'manual script',
      ),
    );
    final lease = h.automaticRouteFor(MusicSource.qq)!.acquire();
    await h.setActiveSource('manual');
    expect(h.isAutomaticActive, isFalse);
    expect(h.automaticRouter, isNull);
    expect(lease.runtime.isScriptReady, isTrue);
    lease.release();
    await Future<void>.delayed(Duration.zero);
    expect(lease.runtime.isScriptReady, isFalse);
  });

  test(
    'failed host selection persistence restores previous source and selection',
    () async {
      final h = host();
      await h.addSource(
        AudioSourceConfig(
          id: 'manual',
          type: AudioSourceType.lxmusic,
          name: 'manual',
          url: '',
          scriptContent: 'manual script',
        ),
      );
      final previous = SharedPreferencesStorePlatform.instance;
      final values = await previous.getAll();
      SharedPreferencesStorePlatform.instance = _FailSelectionStore(values);
      try {
        await expectLater(h.useAutomaticSource(), throwsStateError);
        expect(h.activeSource!.id, 'manual');
        expect(h.automaticRouter, isNull);
        final prefs = await SharedPreferences.getInstance();
        expect(prefs.getString('audio_source_active_id'), 'manual');
        expect(
          prefs.getString('audio_source_recommendation_rollback_v1'),
          isNull,
        );
      } finally {
        SharedPreferencesStorePlatform.instance = previous;
      }
    },
  );

  test('one platform commits while the other fails; 304 retries unapplied target and restores offline', () async {
    server.fail.add(target('wy-a').hash);
    final r = router();
    await r.start('https://backend.example');
    expect(r.platforms, ['qq']);
    expect(r.desired!.targets.length, 2);
    expect(r.platformErrors['netease'], isNotNull);
    server.fail.clear();
    await r.check(force: true);
    expect(server.conditional.last, '"${server.desired.id}"');
    expect(r.platforms.toSet(), {'qq', 'netease'});
    expect(r.platformErrors, isEmpty);
    r.stop();
    final restored = router();
    await restored.start('https://backend.example', remote: false);
    expect(restored.platforms.toSet(), {'qq', 'netease'});
    expect(restored.routeFor('netease')!.target.hash, target('wy-a').hash);
    final otherBackend = router();
    await otherBackend.start('https://other.example', remote: false);
    expect(otherBackend.isReady, isFalse);
  });

  test('QQ update preserves the NetEase identity and leases keep old contexts alive', () async {
    final r = router();
    await r.start('https://backend.example');
    final qq = r.routeFor('qq')!, wy = r.routeFor('netease')!;
    final old = qq.acquire();
    server.publish(plan('b', {'qq': 'qq-b', 'netease': 'wy-a'}));
    await r.check(force: true);
    expect(r.routeFor('qq')!.fingerprint, isNot(qq.fingerprint));
    expect(r.routeFor('netease')!.fingerprint, wy.fingerprint);
    expect(r.routeFor('netease')!.planId, wy.planId);
    expect(old.runtime.isScriptReady, isTrue);
    old.release();
    await Future<void>.delayed(Duration.zero);
    expect(old.runtime.isScriptReady, isFalse);
  });

  test(
    'late download after selection cancellation cannot apply or reactivate',
    () async {
      final r = router();
      await r.start('https://backend.example');
      server.publish(plan('b', {'qq': 'qq-b', 'netease': 'wy-a'}));
      final gate = Completer<void>();
      server.gates[target('qq-b').hash] = gate;
      final pending = r.check(force: true);
      while (server.conditional.length < 2) {
        await Future<void>.delayed(Duration.zero);
      }
      r.stop();
      gate.complete();
      await pending;
      expect(r.isReady, isFalse);
      expect(r.routes, isEmpty);
      final restored = router();
      await restored.start('https://backend.example', remote: false);
      expect(restored.routeFor('qq')!.target.hash, target('qq-a').hash);
    },
  );

  test(
    'hash mismatch and invalid capability preserve applied target',
    () async {
      final r = router(factory: _OnlyQQ.new);
      await r.start('https://backend.example');
      expect(r.platforms, ['qq']);
      expect(r.platformErrors['netease'], contains('标准音质'));
      final old = r.routeFor('qq')!;
      server.publish(plan('b', {'qq': 'qq-b'}));
      server.scripts[target('qq-b').hash] = 'corrupt';
      await r.check(force: true);
      expect(r.routeFor('qq')!.fingerprint, old.fingerprint);
      expect(r.platformErrors['qq'], contains('完整性验证失败'));
    },
  );

  test(
    'four-context bound defers updates until an old lease releases',
    () async {
      server.publish(plan('a', {'qq': 'one'}));
      final instances = <FakeLxRuntime>[];
      final r = router(
        factory: () {
          final instance = FakeLxRuntime();
          instances.add(instance);
          return instance;
        },
      );
      await r.start('https://backend.example');
      final leases = <AutomaticLease>[];
      for (final entry in {'b': 'two', 'c': 'three', 'd': 'four'}.entries) {
        leases.add(r.routeFor('qq')!.acquire());
        server.publish(plan(entry.key, {'qq': entry.value}));
        await r.check(force: true);
      }
      server.publish(plan('e', {'qq': 'five'}));
      await r.check(force: true);
      expect(instances.length, 4);
      expect(r.routeFor('qq')!.target.name, 'four');
      leases.removeAt(0).release();
      await Future<void>.delayed(Duration.zero);
      await r.check(force: true);
      expect(r.routeFor('qq')!.target.name, 'five');
      for (final lease in leases) {
        lease.release();
      }
    },
  );

  test('one immutable script is shared between platforms and valid rollback removes only new requests', () async {
    var count = 0;
    server.publish(plan('a', {'qq': 'shared', 'netease': 'shared'}));
    final r = router(
      factory: () {
        count++;
        return FakeLxRuntime();
      },
    );
    await r.start('https://backend.example');
    expect(count, 1);
    final lease = r.routeFor('netease')!.acquire();
    server.publish(plan('b', {'qq': 'shared'}));
    await r.check(force: true);
    expect(r.routeFor('netease'), isNull);
    expect(lease.runtime.isScriptReady, isTrue);
    lease.release();
    expect(r.routeFor('qq'), isNotNull);
  });

  test('restart after interrupted removal never revives the omitted platform on 304', () async {
    final r = router();
    await r.start('https://backend.example');
    r.stop();
    server.publish(plan('b', {'qq': 'qq-a'}));
    final prefs = await SharedPreferences.getInstance();
    final key = prefs.getKeys().singleWhere(
      (k) => k.startsWith('automatic_recommendation_v1_'),
    );
    final state = jsonDecode(prefs.getString(key)!) as Map<String, dynamic>;
    // Reproduce a process interruption after desired was saved but before an
    // older implementation removed its applied mapping.
    state['desired'] = server.desired.toJson();
    await prefs.setString(key, jsonEncode(state));
    final restored = router();
    await restored.start('https://backend.example', remote: false);
    expect(restored.routeFor('netease'), isNull);
    expect(restored.routeFor('qq'), isNotNull);
    await restored.check(force: true);
    expect(server.conditional.last, '"${server.desired.id}"');
    expect(restored.routeFor('netease'), isNull);
  });

  test('corrupt desired state restores applied targets and requests an unconditional plan', () async {
    final r = router();
    await r.start('https://backend.example');
    r.stop();
    final prefs = await SharedPreferences.getInstance();
    final key = prefs.getKeys().singleWhere(
      (k) => k.startsWith('automatic_recommendation_v1_'),
    );
    final state = jsonDecode(prefs.getString(key)!) as Map<String, dynamic>;
    state['desired'] = {'format': 99};
    await prefs.setString(key, jsonEncode(state));
    final restored = router();
    await restored.start('https://backend.example', remote: false);
    expect(restored.platforms.toSet(), {'qq', 'netease'});
    expect(restored.desired, isNull);
    await restored.check(force: true);
    expect(server.conditional.last, isEmpty);
  });

  test('resolver pins old work and isolates URL cache while retaining complete audio', () async {
    final r = router();
    await r.start('https://backend.example');
    final gate = Completer<void>(), started = Completer<void>();
    LxRuntime? oldRuntime;
    var calls = 0;
    final resolver = TrackResolver(
      automaticRouteFor: (source) => r.routeFor(source.name),
      fetcher:
          ({
            required songId,
            required quality,
            required source,
            required title,
            required artist,
            String album = '',
            int? durationMs,
            LxMusicMetadata lxMetadata = const LxMusicMetadata(),
            required sourceIds,
            required fetchLyrics,
            onLxFailure,
            requestTimeout,
          }) async {
            calls++;
            expect(quality, AudioQuality.standard);
            final lease = AutomaticLease.current!;
            final label = lease.route.target.name;
            if (calls == 1) {
              oldRuntime = lease.runtime;
              started.complete();
              await gate.future;
            }
            return SongDetail(
              id: songId,
              name: title,
              pic: '',
              arName: artist,
              alName: album,
              level: '128k',
              size: '0',
              url: 'https://example.test/$label.mp3',
              lyric: '',
              tlyric: '',
              source: source,
            );
          },
    );
    Future<TrackResolutionResult> resolve() => resolver.resolve(
      songId: 'song',
      quality: AudioQuality.lossless,
      source: MusicSource.qq,
      title: 'song',
      artist: 'artist',
      timeout: const Duration(seconds: 2),
    );
    String audioKey() => completeAudioCacheKey(
      buildAudioCacheIdentity(
        source: 'qq',
        songId: 'song',
        quality: 'standard',
        resolverFingerprint: r.routeFor('qq')!.fingerprint,
      ),
    );
    final oldKey = audioKey();
    final old = resolve();
    await started.future;
    server.publish(plan('b', {'qq': 'qq-b', 'netease': 'wy-a'}));
    await r.check(force: true);
    expect(oldRuntime!.isScriptReady, isTrue);
    expect(audioKey(), oldKey);
    expect((await resolve()).detail!.url, contains('qq-b'));
    gate.complete();
    expect((await old).detail!.url, contains('qq-a'));
    expect(oldRuntime!.isScriptReady, isFalse);
    expect((await resolve()).isL1CacheHit, isTrue);
    expect(calls, 2);
  });

  test(
    'synchronous resolver exception releases the automatic context lease',
    () async {
      final r = router();
      await r.start('https://backend.example');
      LxRuntime? used;
      final resolver = TrackResolver(
        automaticRouteFor: (s) => r.routeFor(s.name),
        fetcher:
            ({
              required songId,
              required quality,
              required source,
              required title,
              required artist,
              String album = '',
              int? durationMs,
              LxMusicMetadata lxMetadata = const LxMusicMetadata(),
              required sourceIds,
              required fetchLyrics,
              onLxFailure,
              requestTimeout,
            }) {
              used = AutomaticLease.current!.runtime;
              throw StateError('fixture synchronous failure');
            },
      );
      await resolver.resolve(
        songId: 'song',
        quality: AudioQuality.standard,
        source: MusicSource.qq,
        title: 'song',
        artist: 'artist',
        timeout: const Duration(seconds: 1),
      );
      r.stop();
      await Future<void>.delayed(Duration.zero);
      expect(used!.isScriptReady, isFalse);
    },
  );

  test(
    'native independent QuickJS contexts route to the right script',
    () async {
      String script(String source, String label) =>
          '''
lx.on(lx.EVENT_NAMES.request, () => Promise.resolve('https://example.com/$label.mp3'));
lx.send(lx.EVENT_NAMES.inited, {sources: {$source: {qualitys: ['128k']}}});
''';
      final qq = script('tx', 'qq'), wy = script('wy', 'wy');
      final qTarget = AutomaticTarget(
        'qq.js',
        sha256.convert(utf8.encode(qq)).toString(),
        'qq',
      );
      final wTarget = AutomaticTarget(
        'wy.js',
        sha256.convert(utf8.encode(wy)).toString(),
        'wy',
      );
      server.desired = AutomaticPlan('p-${'f' * 32}', {
        'qq': qTarget,
        'netease': wTarget,
      });
      server.scripts[qTarget.hash] = qq;
      server.scripts[wTarget.hash] = wy;
      final r = router(factory: LxQuickJsRuntime.new);
      await r.start('https://backend.example');
      final q = r.routeFor('qq')!.acquire(),
          w = r.routeFor('netease')!.acquire();
      try {
        expect(
          await q.runtime.getMusicUrl(
            source: 'tx',
            songId: 'song',
            quality: '128k',
          ),
          'https://example.com/qq.mp3',
        );
        expect(
          await w.runtime.getMusicUrl(source: 'wy', songId: 1, quality: '128k'),
          'https://example.com/wy.mp3',
        );
      } finally {
        q.release();
        w.release();
      }
    },
    skip: Platform.environment['CYRENE_LX_NATIVE_TEST'] != '1',
  );
}
