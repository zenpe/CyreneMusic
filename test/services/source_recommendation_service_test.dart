import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:cyrene_music/services/source_recommendation_service.dart';
import 'package:cyrene_music/services/api/api_result.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));
  test('raw byte hashing happens before BOM decoding and preserves CRLF', () {
    final bytes = [
      0xef,
      0xbb,
      0xbf,
      ...utf8.encode('/* test */\r\nconst a=1;\r\n'),
    ];
    final hash = sha256.convert(bytes).toString();
    expect(
      SourceRecommendationService.verifiedScript(bytes, hash),
      '/* test */\r\nconst a=1;\r\n',
    );
    expect(
      () => SourceRecommendationService.verifiedScript(
        utf8.encode('/* test */\nconst a=1;\n'),
        hash,
      ),
      throwsFormatException,
    );
  });
  test(
    'hash eviction refreshes descriptor at most once and pins each download',
    () async {
      var descriptors = 0;
      final queries = <String>[];
      const text = 'script';
      final hash = sha256.convert(utf8.encode(text)).toString();
      final s = SourceRecommendationService.withDependencies(
        json: (_) async {
          descriptors++;
          return ApiResult(
            statusCode: 200,
            data: {
              'recommendation': {
                'releaseId': 'r-${'a' * 32}',
                'scriptSha256': hash,
                'resolvedName': 'A',
              },
            },
          );
        },
        bytes: (_, q) async {
          queries.add(q['sha256'] as String);
          return ApiResult(statusCode: 410);
        },
      );
      await expectLater(
        s.download('https://example.com/prefix'),
        throwsException,
      );
      expect(descriptors, 2);
      expect(queries, [hash, hash]);
    },
  );
  test(
    'corrupt cached bytes are downloaded again, with backend isolation',
    () async {
      const script = 'content';
      final hash = sha256.convert(utf8.encode(script)).toString();
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        'audio_source_recommendation_pending_v1',
        jsonEncode({
          'origin': 'https://a.example',
          'sha256': hash,
          'bytes': base64Encode(utf8.encode('corrupt')),
        }),
      );
      var count = 0;
      final s = SourceRecommendationService.withDependencies(
        json: (_) async => ApiResult(
          statusCode: 200,
          data: {
            'recommendation': {
              'releaseId': 'r-${'a' * 32}',
              'scriptSha256': hash,
              'resolvedName': 'A',
            },
          },
        ),
        bytes: (origin, q) async {
          count++;
          return ApiResult(statusCode: 200, data: utf8.encode(script));
        },
      );
      await s.download('https://a.example');
      expect(count, 1);
      await s.download('https://a.example');
      expect(count, 1);
      await s.download('https://b.example/prefix');
      expect(count, 2);
    },
  );
}
