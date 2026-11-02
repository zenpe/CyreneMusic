import 'dart:io';
import 'package:cyrene_music/services/lx_music_source_parser.dart';
import 'package:cyrene_music/services/url_service.dart';
import 'package:cyrene_music/services/api/auth_token_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class RealHttpOverrides extends HttpOverrides {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'catalog download uses current host and port, encodes paths and sends no token',
    () async {
      SharedPreferences.setMockInitialValues({});
      await UrlService().initialize();
      const path = '公益/中文 + &?#.js';
      final real = RealHttpOverrides();
      await HttpOverrides.runZoned(() async {
        final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
        final subscription = server.listen((request) async {
          expect(request.uri.path, '/lx/script');
          expect(request.uri.queryParameters['path'], path);
          expect(request.headers.value('authorization'), isNull);
          request.response.headers.contentType = ContentType(
            'application',
            'javascript',
            charset: 'utf-8',
          );
          request.response.write(
            '/* @name 测试音源 */\nconst apiUrl = "https://external.example";',
          );
          await request.response.close();
        });
        try {
          UrlService().useCustomSource('http://127.0.0.1:${server.port}');
          AuthTokenStore.token = 'must-not-leak';
          final config = await LxMusicSourceParser().parseFromCatalogPath(path);
          expect(config!.scriptContent, contains('测试音源'));
          expect(config.source, path);
        } finally {
          AuthTokenStore.token = null;
          await subscription.cancel();
          await server.close(force: true);
        }
      }, createHttpClient: real.createHttpClient);
    },
  );
}
