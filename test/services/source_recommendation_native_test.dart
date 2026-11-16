import 'dart:convert';
import 'dart:io';

import 'package:cyrene_music/services/audio_source_service.dart';
import 'package:cyrene_music/services/lx_music_runtime_service.dart';
import 'package:cyrene_music/services/lx_quickjs_runtime.dart';
import 'package:cyrene_music/services/lx_music_source_parser.dart';
import 'package:cyrene_music/services/url_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

// Opt-in against the isolated Go admin fixture; never uses production data.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'Go publication -> verified client download -> Windows QuickJS -> startup update and rollback',
    () async {
      final overrides = HttpOverrides.current;
      HttpOverrides.global = null;
      addTearDown(() => HttpOverrides.global = overrides);
      SharedPreferences.setMockInitialValues({});
      final origin = Platform.environment['CYRENE_RECOMMENDATION_TEST_ORIGIN']!;
      UrlService().useCustomSource(origin);
      final http = HttpClient();
      addTearDown(() => http.close(force: true));
      String? token;
      Future<Map<String, dynamic>> request(
        String path, {
        Map<String, dynamic>? body,
      }) async {
        final r = await http.openUrl(
          body == null ? 'GET' : 'POST',
          Uri.parse('$origin$path'),
        );
        if (token != null) r.headers.set('Authorization', 'Bearer $token');
        if (body != null) {
          r.headers.contentType = ContentType.json;
          r.write(jsonEncode(body));
        }
        final response = await r.close();
        final data = jsonDecode(
          await utf8.decoder.bind(response).join(),
        ) as Map<String, dynamic>;
        expect(
          response.statusCode,
          inInclusiveRange(200, 299),
          reason: '$path: $data',
        );
        return data;
      }

      final login = await request(
        '/auth/login',
        body: {'account': 'admintest', 'password': 'TestOnlySourceCheck456!'},
      );
      token = login['data']['token'] as String;
      final overview = await request('/admin/source-checks/overview');
      final rows = (overview['sources'] as List).cast<Map>();
      Future<Map> publish(String name) async {
        final state = await request('/admin/source-recommendations');
        final row = rows.firstWhere((x) => x['name'] == name);
        final result = await request(
          '/admin/source-recommendations',
          body: {
            'expectedReleaseId': state['current']['releaseId'] ?? '',
            'generation': row['generation'],
            'path': row['path'],
            'sha256': row['sha256'],
            'note': 'isolated native integration $name',
          },
        );
        return result['release'] as Map;
      }

      LxMusicRuntimeService host() {
        final h = LxMusicRuntimeService.withFactory(LxQuickJsRuntime.new);
        addTearDown(h.dispose);
        return h;
      }

      AudioSourceService app(LxMusicRuntimeService h) =>
          AudioSourceService.withDependencies(
            runtime: h,
            parser: LxMusicSourceParser(),
            recommendationStartupBudget: const Duration(seconds: 3),
          );
      Future<String?> resolve(LxMusicRuntimeService h) => h.getMusicUrl(
        source: 'tx',
        songId: '002X3Bu82FiBhb',
        quality: '128k',
      );
      final a = await publish('A');
      final first = host(), client = app(first);
      await client.initialize();
      await client.useRecommendedSource();
      expect(client.activeSource!.releaseId, a['releaseId']);
      expect(await resolve(first), 'https://example.com/A.mp3');
      final b = await publish('B');
      await client.cacheRecommendedUpdate();
      expect(await resolve(first), 'https://example.com/A.mp3');
      expect(client.recommendationPendingName, 'B');
      final second = host(), restart = app(second);
      await restart.initialize();
      expect(restart.activeSource!.releaseId, b['releaseId']);
      expect(await resolve(second), 'https://example.com/B.mp3');
      final state = await request('/admin/source-recommendations');
      final rolled = await request(
        '/admin/source-recommendations',
        body: {
          'expectedReleaseId': state['current']['releaseId'],
          'fromReleaseId': a['releaseId'],
          'sha256': a['scriptSha256'],
          'note': 'native rollback',
        },
      );
      expect(rolled['release']['releaseId'], isNot(a['releaseId']));
      final third = host(), rollback = app(third);
      await rollback.initialize();
      expect(rollback.activeSource!.scriptSha256, a['scriptSha256']);
      expect(await resolve(third), 'https://example.com/A.mp3');
      await publish('Broken');
      final last = host(), fallback = app(last);
      final clock = Stopwatch()..start();
      await fallback.initialize();
      expect(fallback.activeSource!.scriptSha256, a['scriptSha256']);
      expect(await resolve(last), 'https://example.com/A.mp3');
      expect(fallback.recommendationUpdateError, isNotNull);
      // ignore: avoid_print -- record elapsed time for this opt-in integration test.
      print(
        'native failed-update startup fallback elapsedMs=${clock.elapsedMilliseconds}',
      );
    },
    skip: Platform.environment['CYRENE_RECOMMENDATION_TEST_ORIGIN'] == null,
    timeout: const Timeout(Duration(seconds: 90)),
  );
}
