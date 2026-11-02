import 'dart:async';
import 'dart:convert';

import 'package:cyrene_music/services/audio_source_service.dart';
import 'package:cyrene_music/models/audio_source_config.dart';
import 'package:cyrene_music/services/url_service.dart';
import 'package:cyrene_music/services/lx_music_source_parser.dart';
import 'package:cyrene_music/services/lx_runtime_interface.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

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
        jsonDecode(
          prefs.getString('audio_source_list')!,
        ).single['scriptContent'],
        'old',
      );
    },
  );

  test(
    'same-name replacement keeps ID and updates script capabilities without duplicates',
    () async {
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
    },
  );

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

  test(
    'playback initialization waits for replacement instead of loading old content',
    () async {
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
    },
  );

  test(
    'concurrent candidate operations are serialized and do not duplicate records',
    () async {
      parser.scripts[url] = 'old';
      await Future.wait([service.useLxSource(url), service.useLxSource(url)]);
      expect(service.sources.length, 1);
      expect(runtime.loads, ['old', 'old']);
    },
  );

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
}
