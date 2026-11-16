import 'dart:async';
import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:cyrene_music/services/source_recommendation_service.dart';
import 'package:cyrene_music/services/api/api_result.dart';

import 'package:cyrene_music/services/audio_source_service.dart';
import 'package:cyrene_music/models/audio_source_config.dart';
import 'package:cyrene_music/models/lx_source_candidate.dart';
import 'package:cyrene_music/services/url_service.dart';
import 'package:cyrene_music/services/lx_music_source_parser.dart';
import 'package:cyrene_music/services/lx_runtime_interface.dart';
import 'package:cyrene_music/services/lx_music_runtime_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';

class _FailingPreferences extends InMemorySharedPreferencesStore {
  _FailingPreferences(super.data, this.target) : super.withData();
  final String target;
  bool fail = true;
  @override
  Future<bool> setValue(String valueType, String key, Object value) async {
    if (fail && key == 'flutter.$target') {
      fail = false;
      return false;
    }
    return super.setValue(valueType, key, value);
  }
}

class _JournalCleanupPreferences extends InMemorySharedPreferencesStore {
  _JournalCleanupPreferences(super.data, {this.throwOnRemove = false})
    : super.withData();
  final bool throwOnRemove;
  int failures = 1;
  int removeAttempts = 0;
  int writes = 0;

  @override
  Future<bool> remove(String key) async {
    if (key == 'flutter.audio_source_recommendation_rollback_v1') {
      removeAttempts++;
      if (failures > 0) {
        failures--;
        if (throwOnRemove) throw StateError('storage unavailable');
        return false;
      }
    }
    return super.remove(key);
  }

  @override
  Future<bool> setValue(String valueType, String key, Object value) async {
    writes++;
    return super.setValue(valueType, key, value);
  }
}

class _Parser extends LxMusicSourceParser {
  final scripts = <String, String?>{};
  final downloads = <String>[];

  @override
  Future<LxMusicSourceConfig?> parseFromCatalogPath(String path) =>
      parseFromUrl(path);

  @override
  Future<LxMusicSourceConfig?> parseFromUrl(String scriptUrl) async {
    downloads.add(scriptUrl);
    final script = scripts[scriptUrl];
    if (script == null) return null;
    return LxMusicSourceConfig(
      name: 'Source',
      version: '1',
      apiUrl: '',
      apiKey: '',
      source: scriptUrl,
      scriptContent: script,
    );
  }
}

class _Runtime implements LxRuntime {
  final loads = <String>[];
  final rejectedScripts = <String>{'bad'};
  Completer<void>? gate;
  Completer<void>? started;
  bool _initialized = false;
  bool _ready = false;
  LxScriptInfo? _script;

  @override
  bool get isInitialized => _initialized;
  @override
  bool get isScriptReady => _ready;
  @override
  bool get isAvailable => true;
  @override
  LxScriptInfo? get currentScript => _script;
  @override
  LxRuntimeFailure? get lastFailure => null;
  @override
  Future<void> initialize() async => _initialized = true;
  @override
  Future<void> dispose() async {
    _initialized = false;
    _ready = false;
    _script = null;
  }

  @override
  Future<LxScriptInfo?> loadScript(String scriptContent) async {
    loads.add(scriptContent);
    _ready = false;
    _script = null;
    started?.complete();
    started = null;
    final waiting = gate;
    gate = null;
    if (waiting != null) await waiting.future;
    if (rejectedScripts.contains(scriptContent)) return null;
    _initialized = true;
    _ready = true;
    _script = LxScriptInfo(
      name: 'Source',
      version: '1',
      script: scriptContent,
      supportedSources: scriptContent == 'new' ? ['tx'] : ['wy'],
      supportedQualities: ['128k'],
      platformQualities: {
        scriptContent == 'new' ? 'tx' : 'wy': ['128k'],
      },
    );
    return _script;
  }

  @override
  Future<String?> getMusicUrl({
    required String source,
    required dynamic songId,
    required String quality,
    Map<String, dynamic>? musicInfo,
    Duration? timeout,
  }) async => 'https://example.com/audio.mp3';
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const url = 'https://api.example/lx/scripts/source.js';
  late _Parser parser;
  late _Runtime runtime;
  late AudioSourceService service;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    parser = _Parser();
    runtime = _Runtime();
    service = AudioSourceService.withDependencies(
      runtime: runtime,
      parser: parser,
    );
  });

  test('isolated candidate failure keeps the exact old context alive', () async {
    final contexts = <_Runtime>[];
    final host = LxMusicRuntimeService.withFactory(() {
      final context = _Runtime();
      contexts.add(context);
      return context;
    });
    addTearDown(host.dispose);
    service = AudioSourceService.withDependencies(
      runtime: host,
      parser: parser,
    );
    parser.scripts[url] = 'old';
    await service.useLxSource(url);
    final oldContext = contexts.last;
    final revision = service.lxSourceRevision;
    final oldConfig = service.activeSource;
    // Reinitializing the old script would now fail. Rollback must not need it.
    oldContext.rejectedScripts.add('old');
    parser.scripts[url] = 'bad';
    await expectLater(service.useLxSource(url), throwsStateError);
    expect(oldContext.loads, ['old']);
    expect(oldContext.isScriptReady, isTrue);
    expect(contexts.last.isInitialized, isFalse);
    expect(host.currentScript, same(oldContext.currentScript));
    expect(service.activeSource, same(oldConfig));
    expect(service.lxSourceRevision, revision);
    expect(service.loadState, AudioSourceLoadState.ready);
  });

  test('old resolution remains available until candidate commit', () async {
    final contexts = <_Runtime>[];
    Completer<void>? gate;
    Completer<void>? started;
    final host = LxMusicRuntimeService.withFactory(() {
      final context = _Runtime()
        ..gate = gate
        ..started = started;
      contexts.add(context);
      return context;
    });
    addTearDown(host.dispose);
    service = AudioSourceService.withDependencies(
      runtime: host,
      parser: parser,
    );
    parser.scripts[url] = 'old';
    await service.useLxSource(url);
    final oldContext = contexts.last;
    gate = Completer<void>();
    started = Completer<void>();
    parser.scripts[url] = 'new';
    final replacing = service.useLxSource(url);
    await started.future;
    try {
      await service.initializeLxRuntime().timeout(const Duration(seconds: 1));
      expect(host.currentScript, same(oldContext.currentScript));
      expect(
        await host.getMusicUrl(source: 'wy', songId: '1', quality: '128k'),
        'https://example.com/audio.mp3',
      );
      expect(service.activeSource!.scriptContent, 'old');
    } finally {
      gate.complete();
    }
    await replacing;
    expect(oldContext.isInitialized, isFalse);
    expect(host.currentScript!.script, 'new');
    expect(service.activeSource!.scriptContent, 'new');
    await service.clear();
    expect(host.isScriptReady, isFalse);
    expect(contexts.every((context) => !context.isInitialized), isTrue);
  });

  test('disposing host invalidates a candidate that finishes late', () async {
    final gate = Completer<void>();
    final started = Completer<void>();
    final contexts = <_Runtime>[];
    final host = LxMusicRuntimeService.withFactory(() {
      final context = _Runtime();
      if (contexts.isNotEmpty) {
        context.gate = gate;
        context.started = started;
      }
      contexts.add(context);
      return context;
    });
    final preparing = host.prepareScript('new');
    final check = expectLater(preparing, throwsStateError);
    await started.future;
    await host.dispose();
    gate.complete();
    await check;
    expect(host.isScriptReady, isFalse);
    expect(contexts.every((context) => !context.isInitialized), isTrue);
  });

  test(
    'backend changes discard isolated candidate without replacing old context',
    () async {
      final contexts = <_Runtime>[];
      Completer<void>? gate;
      Completer<void>? started;
      final host = LxMusicRuntimeService.withFactory(() {
        final context = _Runtime()
          ..gate = gate
          ..started = started;
        contexts.add(context);
        return context;
      });
      addTearDown(host.dispose);
      service = AudioSourceService.withDependencies(
        runtime: host,
        parser: parser,
      );
      parser.scripts[url] = 'old';
      await service.useLxSource(url);
      final old = contexts.last;
      final prefs = await SharedPreferences.getInstance();
      final stored = prefs.getString('audio_source_list');
      parser.scripts['staged.js'] = 'new';
      gate = Completer<void>();
      started = Completer<void>();
      final updating = service.useLxSource('', catalogPath: 'staged.js');
      final check = expectLater(updating, throwsException);
      await started.future;
      UrlService().useCustomSource('https://staged-change.example');
      gate.complete();
      await check;
      expect(host.currentScript, same(old.currentScript));
      expect(old.loads, ['old']);
      expect(contexts.last.isInitialized, isFalse);
      expect(prefs.getString('audio_source_list'), stored);
      expect(service.activeSource!.scriptContent, 'old');
    },
  );

  test(
    'catalog refresh migrates legacy URL and keeps the stable local ID',
    () async {
      const path = '公益/中文 + &?#.js';
      final legacy = AudioSourceConfig.fromJson({
        'id': 'legacy',
        'type': 'lxmusic',
        'name': 'Source',
        'url': '',
        'scriptSource': Uri.https('old.example', '/lx/script', {
          'path': path,
        }).toString(),
        'scriptContent': 'old',
      });
      await service.addSource(legacy);
      parser.scripts[path] = 'new';
      await service.useLxSource('', catalogPath: path);
      expect(service.sources, hasLength(1));
      expect(service.activeSource!.id, 'legacy');
      expect(service.activeSource!.catalogPath, path);
      expect(service.activeSource!.scriptSource, isEmpty);
      expect(service.activeSource!.scriptContent, 'new');
      final prefs = await SharedPreferences.getInstance();
      final restored = AudioSourceConfig.fromJson(
        Map<String, dynamic>.from(
          jsonDecode(prefs.getString('audio_source_list')!).single,
        ),
      );
      expect(restored.catalogPath, path);
      expect(restored.id, 'legacy');
    },
  );

  test(
    'server switch during initialization rolls back candidate and runtime',
    () async {
      parser.scripts[url] = 'old';
      await service.useLxSource(url);
      final previous = service.activeSource;
      final prefs = await SharedPreferences.getInstance();
      final stored = prefs.getString('audio_source_list');
      parser.scripts['candidate.js'] = 'new';
      runtime.gate = Completer<void>();
      runtime.started = Completer<void>();
      final started = runtime.started!;
      final gate = runtime.gate!;
      final pending = service.useLxSource('', catalogPath: 'candidate.js');
      final assertion = expectLater(pending, throwsException);
      await started.future;
      UrlService().useCustomSource('https://changed.example');
      gate.complete();
      await assertion;
      expect(service.activeSource, same(previous));
      expect(prefs.getString('audio_source_list'), stored);
      expect(runtime.currentScript!.script, 'old');
    },
  );

  test(
    'successful import persists selection and initialized capabilities',
    () async {
      parser.scripts[url] = 'old';
      await service.useLxSource(url);
      expect(service.sources.length, 1);
      expect(service.activeSource!.scriptContent, 'old');
      expect(service.activeSource!.supportedPlatforms, ['netease']);
      final prefs = await SharedPreferences.getInstance();
      expect(
        prefs.getString('audio_source_active_id'),
        service.activeSource!.id,
      );
      expect(
        jsonDecode(prefs.getString('audio_source_list')!)
            .single['scriptContent'],
        'old',
      );
    },
  );

  test('same-name replacement keeps ID and updates script capabilities without duplicates', () async {
    parser.scripts[url] = 'old';
    await service.useLxSource(url);
    final id = service.activeSource!.id;
    final revision = service.lxSourceRevision;
    parser.scripts[url] = 'new';
    await service.useLxSource(url);
    expect(service.sources.length, 1);
    expect(service.activeSource!.id, id);
    expect(service.activeSource!.scriptContent, 'new');
    expect(service.activeSource!.supportedPlatforms, ['qq']);
    expect(service.lxSourceRevision, greaterThan(revision));
  });

  test(
    'failed download leaves saved configuration and runtime untouched',
    () async {
      parser.scripts[url] = 'old';
      await service.useLxSource(url);
      final previous = service.activeSource;
      final prefs = await SharedPreferences.getInstance();
      final stored = prefs.getString('audio_source_list');
      parser.scripts[url] = null;
      await expectLater(service.useLxSource(url), throwsException);
      expect(service.activeSource, same(previous));
      expect(runtime.loads, ['old']);
      expect(prefs.getString('audio_source_list'), stored);
    },
  );

  test(
    'invalid replacement restores old runtime and never persists bad content',
    () async {
      parser.scripts[url] = 'old';
      await service.useLxSource(url);
      final previous = service.activeSource;
      final prefs = await SharedPreferences.getInstance();
      final stored = prefs.getString('audio_source_list');
      parser.scripts[url] = 'bad';
      await expectLater(service.useLxSource(url), throwsException);
      expect(service.activeSource, same(previous));
      expect(runtime.loads, ['old', 'bad', 'old']);
      expect(runtime.isScriptReady, isTrue);
      expect(prefs.getString('audio_source_list'), stored);
    },
  );

  test(
    'failed recovery is reported honestly while old configuration remains',
    () async {
      parser.scripts[url] = 'old';
      await service.useLxSource(url);
      runtime.rejectedScripts.add('old');
      parser.scripts[url] = 'bad';
      await expectLater(
        service.useLxSource(url),
        throwsA(predicate((error) => error.toString().contains('恢复未完成'))),
      );
      expect(service.activeSource!.scriptContent, 'old');
      expect(runtime.isScriptReady, isFalse);
    },
  );

  test('playback initialization waits for replacement instead of loading old content', () async {
    parser.scripts[url] = 'old';
    await service.useLxSource(url);
    parser.scripts[url] = 'new';
    final gate = Completer<void>();
    final started = Completer<void>();
    runtime.gate = gate;
    runtime.started = started;
    final update = service.useLxSource(url);
    await started.future;
    var finished = false;
    final initialization = service.initializeLxRuntime().then(
      (_) => finished = true,
    );
    await Future<void>.delayed(Duration.zero);
    expect(finished, isFalse);
    expect(service.activeSource!.scriptContent, 'old');
    gate.complete();
    await update;
    await initialization;
    expect(runtime.loads, ['old', 'new']);
    expect(service.activeSource!.scriptContent, 'new');
  });

  test('concurrent candidate operations are serialized and do not duplicate records', () async {
    parser.scripts[url] = 'old';
    await Future.wait([service.useLxSource(url), service.useLxSource(url)]);
    expect(service.sources.length, 1);
    expect(runtime.loads, ['old', 'old']);
  });

  test(
    'first invalid import does not create a saved source or selection',
    () async {
      parser.scripts[url] = 'bad';
      await expectLater(service.useLxSource(url), throwsException);
      expect(service.sources, isEmpty);
      expect(service.activeSource, isNull);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.containsKey('audio_source_list'), isFalse);
      expect(prefs.containsKey('audio_source_active_id'), isFalse);
    },
  );
  test(
    'saved-source activation failure keeps the original selection and revision',
    () async {
      parser.scripts[url] = 'old';
      await service.useLxSource(url);
      final old = service.activeSource!;
      final revision = service.lxSourceRevision;
      await service.addSource(
        AudioSourceConfig(
          id: 'bad',
          type: AudioSourceType.lxmusic,
          name: 'Bad',
          url: '',
          scriptContent: 'bad',
        ),
      );
      await expectLater(service.setActiveSource('bad'), throwsException);
      expect(service.activeSource, same(old));
      expect(service.lxSourceRevision, revision);
      expect(service.loadState, AudioSourceLoadState.ready);
      expect(runtime.currentScript!.script, 'old');
    },
  );

  test('cold concurrent initialization loads the saved script once', () async {
    parser.scripts[url] = 'old';
    await service.useLxSource(url);
    await runtime.dispose();
    runtime.loads.clear();
    runtime.gate = Completer<void>();
    final gate = runtime.gate!;
    runtime.started = Completer<void>();
    final started = runtime.started!;
    final first = service.initializeLxRuntime();
    await started.future;
    final second = service.initializeLxRuntime();
    gate.complete();
    await Future.wait([first, second]);
    expect(runtime.loads, ['old']);
  });

  test(
    'local reload never downloads and active edit is transactional',
    () async {
      parser.scripts[url] = 'old';
      await service.useLxSource(url);
      await service.reloadActiveSource();
      expect(parser.downloads, [url]);
      final old = service.activeSource!;
      await expectLater(
        service.updateSource(old.copyWith(scriptContent: 'bad')),
        throwsException,
      );
      expect(service.activeSource, same(old));
      expect(runtime.currentScript!.script, 'old');
    },
  );

  test(
    'inactive edits and refresh do not change active revision or runtime',
    () async {
      parser.scripts[url] = 'old';
      await service.useLxSource(url);
      final revision = service.lxSourceRevision;
      final other = AudioSourceConfig(
        id: 'other',
        type: AudioSourceType.lxmusic,
        name: 'Other',
        url: '',
        scriptContent: 'new',
      );
      await service.addSource(other);
      await service.updateSource(other.copyWith(name: 'Renamed'));
      service.refresh();
      expect(service.lxSourceRevision, revision);
      expect(runtime.loads, ['old']);
    },
  );
  group('recommended source lifecycle', () {
    late String currentScript;
    late String release;
    late SourceRecommendationService recommendations;
    late List<String> downloadedHashes;
    Completer<List<int>>? downloadGate;
    bool offline = false;
    Map<String, dynamic> descriptor() => {
      'releaseId': release,
      'scriptSha256': sha256.convert(utf8.encode(currentScript)).toString(),
      'resolvedName': 'Source $currentScript',
      'health': <String, dynamic>{},
    };
    setUp(() {
      currentScript = 'old';
      release = 'r-${'1' * 32}';
      downloadedHashes = [];
      downloadGate = null;
      offline = false;
      recommendations = SourceRecommendationService.withDependencies(
        json: (_) async => offline
            ? ApiResult(statusCode: 503)
            : ApiResult(
                statusCode: 200,
                data: {'recommendation': descriptor()},
              ),
        bytes: (_, query) async {
          downloadedHashes.add(query['sha256'] as String);
          final bytes = downloadGate == null
              ? utf8.encode(currentScript)
              : await downloadGate!.future;
          return ApiResult(statusCode: 200, data: bytes);
        },
      );
      service = AudioSourceService.withDependencies(
        runtime: runtime,
        parser: parser,
        recommendations: recommendations,
        recommendationStartupBudget: const Duration(milliseconds: 20),
      );
    });
    for (final field in ['audio_source_list', 'audio_source_active_id']) {
      test(
        'failed $field save preserves active script and persistent selection',
        () async {
          await service.useRecommendedSource();
          final before = service.activeSource!;
          final prefs = await SharedPreferences.getInstance();
          final values = {
            for (final key in prefs.getKeys()) 'flutter.$key': prefs.get(key)!,
          };
          final previousStore = SharedPreferencesStorePlatform.instance;
          final store = _FailingPreferences(values, field);
          SharedPreferencesStorePlatform.instance = store;
          addTearDown(
            () => SharedPreferencesStorePlatform.instance = previousStore,
          );
          currentScript = 'new';
          release = 'r-${'2' * 32}';
          await expectLater(service.useRecommendedSource(), throwsException);
          expect(service.activeSource!.scriptSha256, before.scriptSha256);
          expect(runtime.currentScript!.script, 'old');
          expect(
            (jsonDecode(
              prefs.getString('audio_source_list')!,
            ) as List).single['scriptSha256'],
            before.scriptSha256,
          );
          expect(
            prefs.containsKey('audio_source_recommendation_rollback_v1'),
            isFalse,
          );
        },
      );
    }
    Future<void> seed() async {
      await service.useRecommendedSource();
      await runtime.dispose();
    }

    AudioSourceService cold(_Runtime r) => AudioSourceService.withDependencies(
      runtime: r,
      parser: parser,
      recommendations: recommendations,
      recommendationStartupBudget: const Duration(milliseconds: 20),
    );

    Future<_JournalCleanupPreferences> failJournalCleanup({
      bool throwOnRemove = false,
    }) async {
      final prefs = await SharedPreferences.getInstance();
      final store = _JournalCleanupPreferences({
        for (final key in prefs.getKeys()) 'flutter.$key': prefs.get(key)!,
      }, throwOnRemove: throwOnRemove);
      final previousStore = SharedPreferencesStorePlatform.instance;
      SharedPreferencesStorePlatform.instance = store;
      addTearDown(
        () => SharedPreferencesStorePlatform.instance = previousStore,
      );
      return store;
    }

    for (final throwsOnRemove in [false, true]) {
      test(
        'cold recovery cleanup failure loads old settings and preserves later import (throws=$throwsOnRemove)',
        () async {
          await seed();
          final prefs = await SharedPreferences.getInstance();
          final oldList = prefs.getString('audio_source_list')!;
          final oldId = prefs.getString('audio_source_active_id')!;
          await prefs.setString(
            'audio_source_recommendation_rollback_v1',
            jsonEncode({'sources': oldList, 'activeId': oldId}),
          );
          await prefs.setString('audio_source_list', '[]');
          await prefs.setString('audio_source_active_id', 'unfinished');
          final store = await failJournalCleanup(throwOnRemove: throwsOnRemove);
          offline = true;
          final r = _Runtime();
          final app = cold(r);
          await app.initialize();
          expect(app.activeSource!.id, oldId);
          expect(r.currentScript!.script, 'old');
          expect(store.removeAttempts, 1);
          expect(
            (await store.getAll()).containsKey(
              'flutter.audio_source_recommendation_rollback_v1',
            ),
            isTrue,
          );
          store.failures = 1;
          final before = await store.getAll();
          await expectLater(app.clear(), throwsStateError);
          expect(app.activeSource!.id, oldId);
          expect(await store.getAll(), before);
          parser.scripts[url] = 'imported';
          await app.useLxSource(url);
          final importedId = app.activeSource!.id;
          expect(app.sources.length, 2);
          await prefs.reload();
          final restart = cold(_Runtime());
          await restart.initialize();
          expect(restart.activeSource!.id, importedId);
          expect(restart.activeSource!.scriptContent, 'imported');
          expect(restart.sources.map((s) => s.id), contains(oldId));
        },
      );
    }

    for (final field in ['audio_source_list', 'audio_source_active_id']) {
      test(
        'partial cold recovery blocks further writes until restart ($field)',
        () async {
          await seed();
          final prefs = await SharedPreferences.getInstance();
          final oldId = prefs.getString('audio_source_active_id')!;
          await prefs.setString(
            'audio_source_recommendation_rollback_v1',
            jsonEncode({
              'sources': prefs.getString('audio_source_list'),
              'activeId': oldId,
            }),
          );
          await prefs.setString('audio_source_list', '[]');
          await prefs.setString('audio_source_active_id', 'unfinished');
          final previous = SharedPreferencesStorePlatform.instance;
          final store = _FailingPreferences({
            for (final key in prefs.getKeys()) 'flutter.$key': prefs.get(key)!,
          }, field);
          SharedPreferencesStorePlatform.instance = store;
          addTearDown(() => SharedPreferencesStorePlatform.instance = previous);
          offline = true;
          final app = cold(_Runtime());
          await app.initialize();
          expect(app.loadError, contains('恢复失败'));
          final before = await store.getAll();
          await expectLater(app.clear(), throwsStateError);
          await expectLater(app.useLxSource(url), throwsStateError);
          expect(await store.getAll(), before);
          await prefs.reload();
          final restart = cold(_Runtime());
          await restart.initialize();
          expect(restart.activeSource!.id, oldId);
          expect(restart.activeSource!.scriptContent, 'old');
        },
      );
    }

    for (final inactive in [false, true]) {
      test(
        'manual import detaches recommendation metadata and stays local after restart (inactive=$inactive)',
        () async {
          await service.useRecommendedSource();
          final original = service.activeSource!;
          if (inactive) {
            parser.scripts[url] = 'ordinary';
            await service.useLxSource(url);
          }
          final selectedId = service.activeSource!.id;
          final edited = original.asImportedSource().copyWith(
            scriptContent: 'imported',
            scriptSource: 'https://example.test/imported.js',
          );
          await service.updateSource(edited);
          final saved = service.sources.firstWhere((s) => s.id == original.id);
          expect(saved.isRecommendation, isFalse);
          expect([
            saved.catalogPath,
            saved.catalogKind,
            saved.backendOrigin,
            saved.releaseId,
            saved.scriptSha256,
            saved.scriptContentHash,
            saved.resolvedName,
          ], everyElement(isEmpty));
          expect(saved.scriptSource, 'https://example.test/imported.js');
          if (inactive) {
            expect(service.activeSource!.id, selectedId);
            await service.setActiveSource(saved.id);
          }
          expect(runtime.currentScript!.script, 'imported');
          currentScript = 'bad';
          release = 'r-${'2' * 32}';
          final requests = downloadedHashes.length;
          await (await SharedPreferences.getInstance()).reload();
          final restart = cold(_Runtime());
          await restart.initialize();
          expect(restart.activeSource!.id, original.id);
          expect(restart.activeSource!.scriptContent, 'imported');
          expect(downloadedHashes.length, requests);
        },
      );
    }

    for (final action in ['switch', 'delete', 'import']) {
      test('journal cleanup failure does not undo later $action on restart', () async {
        await service.useRecommendedSource();
        final recommendationId = service.activeSource!.id;
        final ordinary = AudioSourceConfig(
          id: 'ordinary',
          type: AudioSourceType.lxmusic,
          name: 'Ordinary',
          url: '',
          scriptContent: 'ordinary',
        );
        await service.addSource(ordinary);
        final store = await failJournalCleanup();
        currentScript = 'new';
        release = 'r-${'2' * 32}';
        parser.scripts[url] = 'imported';

        // Queue the user action before the update completes. Its cleanup check
        // must run after the earlier transaction, not when it is enqueued.
        final update = service.useRecommendedSource();
        final later = switch (action) {
          'switch' => service.setActiveSource(ordinary.id),
          'delete' => service.removeSource(recommendationId),
          _ => service.useLxSource(url),
        };
        await Future.wait([update, later]);
        expect(store.removeAttempts, 2);
        expect(
          (await store.getAll()).containsKey(
            'flutter.audio_source_recommendation_rollback_v1',
          ),
          isFalse,
        );
        if (action == 'switch') {
          expect(service.activeSource!.id, ordinary.id);
        } else if (action == 'delete') {
          expect(service.activeSource, isNull);
          expect(service.sources.map((s) => s.id), [ordinary.id]);
        } else {
          expect(service.activeSource!.scriptContent, 'imported');
        }

        final selectedId = service.activeSource?.id;
        final ids = service.sources.map((s) => s.id).toList();
        // Reload from the platform store to simulate losing SharedPreferences'
        // optimistic cache on a real process restart.
        await (await SharedPreferences.getInstance()).reload();
        offline = true;
        final restart = cold(_Runtime());
        await restart.initialize();
        expect(restart.activeSource?.id, selectedId);
        expect(restart.sources.map((s) => s.id), ids);
      });
    }

    for (final throwsOnRemove in [false, true]) {
      test(
        'unresolved cleanup blocks writes until storage recovers (throws=$throwsOnRemove)',
        () async {
          await service.useRecommendedSource();
          final store = await failJournalCleanup(throwOnRemove: throwsOnRemove);
          store.failures = 10;
          currentScript = 'new';
          release = 'r-${'2' * 32}';
          await service.useRecommendedSource();
          final selected = service.activeSource!;
          final before = await store.getAll();
          final writes = store.writes;
          final loads = runtime.loads.toList();
          expect(
            before.containsKey(
              'flutter.audio_source_recommendation_rollback_v1',
            ),
            isTrue,
          );
          await expectLater(
            service.removeSource(selected.id),
            throwsA(
              isA<StateError>().having(
                (e) => e.message,
                'message',
                contains('本次操作未保存'),
              ),
            ),
          );
          expect(service.activeSource, same(selected));
          expect(service.sources.single, same(selected));
          expect(runtime.loads, loads);
          expect(store.writes, writes);
          expect(await store.getAll(), before);

          store.failures = 0;
          await service.removeSource(selected.id);
          await (await SharedPreferences.getInstance()).reload();
          offline = true;
          final restart = cold(_Runtime());
          await restart.initialize();
          expect(restart.activeSource, isNull);
          expect(restart.sources, isEmpty);
        },
      );
    }

    test('saved recommendations from other servers remain selectable and removable offline', () async {
      final original = UrlService().baseUrl;
      addTearDown(() => UrlService().useCustomSource(original));
      UrlService().useCustomSource('https://server-a.example');
      await service.useRecommendedSource();
      final a = service.activeSource!;
      UrlService().useCustomSource('https://server-b.example');
      currentScript = 'new';
      release = 'r-${'2' * 32}';
      await service.useRecommendedSource();
      final b = service.activeSource!;
      expect(b.id, isNot(a.id));
      const candidates = [
        LxSourceCandidate(
          path: SourceRecommendation.catalogPath,
          name: '推荐音源',
          directory: '推荐',
          kind: 'recommendation',
        ),
      ];
      List<AudioSourceConfig> visible() => service.sources
          .where(
            (s) => !s.matchesCatalog(
              candidates,
              backendOrigin: SourceRecommendationService.currentOrigin,
            ),
          )
          .toList();
      expect(visible().map((s) => s.id), [a.id]);

      offline = true;
      final requests = downloadedHashes.length;
      await service.setActiveSource(a.id);
      expect(service.activeSource!.id, a.id);
      expect(runtime.currentScript!.script, 'old');
      expect(downloadedHashes.length, requests);
      await service.setActiveSource(b.id);
      await service.removeSource(a.id);
      expect(service.sources.map((s) => s.id), [b.id]);
      await (await SharedPreferences.getInstance()).reload();
      final restart = cold(_Runtime());
      await restart.initialize();
      expect(restart.activeSource!.id, b.id);
      expect(restart.sources.single.id, b.id);
    });
    test(
      'same bytes with a new opaque release update metadata without reloading',
      () async {
        await service.useRecommendedSource();
        final initial = runtime.loads.length;
        release = 'r-${'2' * 32}';
        await service.useRecommendedSource();
        expect(runtime.loads.length, initial);
        expect(service.activeSource!.releaseId, release);
        expect(downloadedHashes.length, 1);
      },
    );
    test(
      'late startup bytes are cached and never committed to a running session',
      () async {
        await seed();
        currentScript = 'new';
        release = 'r-${'2' * 32}';
        downloadGate = Completer<List<int>>();
        final r = _Runtime();
        final app = cold(r);
        await app.initialize();
        expect(app.activeSource!.scriptContent, 'old');
        expect(r.loads, ['old']);
        downloadGate!.complete(utf8.encode('new'));
        await Future<void>.delayed(const Duration(milliseconds: 20));
        expect(r.loads, ['old']);
        expect(app.activeSource!.scriptContent, 'old');
        expect(app.recommendationPendingName, 'Source new');
        downloadGate = null;
        final restart = cold(_Runtime());
        await restart.initialize();
        expect(restart.activeSource!.scriptContent, 'new');
        expect(restart.activeSource!.releaseId, release);
      },
    );
    test(
      'cached new bytes are not auto-applied while backend is unreachable',
      () async {
        await seed();
        currentScript = 'new';
        release = 'r-${'2' * 32}';
        await recommendations.download(
          SourceRecommendationService.currentOrigin,
        );
        offline = true;
        final app = cold(_Runtime());
        await app.initialize();
        expect(app.activeSource!.scriptContent, 'old');
        expect(app.recommendationUpdateError, isNotNull);
      },
    );
    test(
      'startup preparation is awaited past the network selection budget',
      () async {
        await seed();
        currentScript = 'new';
        release = 'r-${'2' * 32}';
        final r = _Runtime()
          ..gate = Completer<void>()
          ..started = Completer<void>();
        final gate = r.gate!, started = r.started!;
        final app = cold(r);
        var ready = false;
        final boot = app.initialize().then((_) => ready = true);
        await started.future;
        await Future<void>.delayed(const Duration(milliseconds: 35));
        expect(ready, isFalse);
        var playbackReady = false;
        final playback = app.initializeLxRuntime().then(
          (_) => playbackReady = true,
        );
        await Future<void>.delayed(Duration.zero);
        expect(playbackReady, isFalse);
        gate.complete();
        await boot;
        await playback;
        expect(r.loads, ['new']);
        expect(app.activeSource!.scriptContent, 'new');
      },
    );
    test(
      'invalid new script restores local source before startup completes',
      () async {
        await seed();
        currentScript = 'bad';
        release = 'r-${'2' * 32}';
        final r = _Runtime();
        final app = cold(r);
        await app.initialize();
        expect(app.activeSource!.scriptContent, 'old');
        expect(r.currentScript!.script, 'old');
        expect(app.recommendationUpdateError, isNotNull);
        final prefs = await SharedPreferences.getInstance();
        expect(
          prefs.containsKey('audio_source_recommendation_rollback_v1'),
          isFalse,
        );
      },
    );
    test('explicit playback closes a pending startup network window', () async {
      await seed();
      currentScript = 'new';
      release = 'r-${'2' * 32}';
      downloadGate = Completer<List<int>>();
      final r = _Runtime();
      final app = cold(r);
      final boot = app.initialize();
      while (downloadedHashes.length < 2) {
        await Future<void>.delayed(Duration.zero);
      }
      await app.initializeLxRuntime();
      await boot;
      expect(app.activeSource!.scriptContent, 'old');
      downloadGate!.complete(utf8.encode('new'));
      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect(r.loads, ['old']);
    });
    test(
      'interrupted multi-key save restores previous selection on cold start',
      () async {
        await seed();
        final prefs = await SharedPreferences.getInstance();
        final old = prefs.getString('audio_source_list');
        final id = prefs.getString('audio_source_active_id');
        await prefs.setString(
          'audio_source_recommendation_rollback_v1',
          jsonEncode({'sources': old, 'activeId': id}),
        );
        await prefs.setString('audio_source_list', '[]');
        await prefs.setString('audio_source_active_id', 'unfinished');
        offline = true;
        final app = cold(_Runtime());
        await app.initialize();
        expect(app.activeSource!.id, id);
        expect(app.activeSource!.scriptContent, 'old');
        expect(
          prefs.containsKey('audio_source_recommendation_rollback_v1'),
          isFalse,
        );
      },
    );
    test(
      'ordinary manual selection does not follow later recommendation',
      () async {
        await service.useRecommendedSource();
        parser.scripts[url] = 'new';
        await service.useLxSource(url);
        currentScript = 'bad';
        release = 'r-${'2' * 32}';
        final requests = downloadedHashes.length;
        final app = cold(_Runtime());
        await app.initialize();
        expect(app.activeSource!.isRecommendation, isFalse);
        expect(app.activeSource!.scriptContent, 'new');
        expect(downloadedHashes.length, requests);
      },
    );
    test('changing backend invalidates a candidate before commit', () async {
      await service.useRecommendedSource();
      currentScript = 'new';
      release = 'r-${'2' * 32}';
      runtime.gate = Completer<void>();
      runtime.started = Completer<void>();
      final gate = runtime.gate!, started = runtime.started!;
      final original = UrlService().baseUrl;
      final update = service.useRecommendedSource();
      final assertion = expectLater(update, throwsStateError);
      await started.future;
      UrlService().useCustomSource('https://changed.example/prefix');
      gate.complete();
      await assertion;
      expect(service.activeSource!.scriptContent, 'old');
      UrlService().useCustomSource(original);
    });
  });
}
