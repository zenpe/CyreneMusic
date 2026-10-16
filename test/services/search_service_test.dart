import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:cyrene_music/services/search_service.dart';
import 'package:cyrene_music/services/url_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _RealHttp extends HttpOverrides {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<void> withServer(
    Future<void> Function(HttpRequest) handle,
    Future<void> Function(SearchService) verify,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final subscription = server.listen(handle);
    await HttpOverrides.runZoned(() async {
      await UrlService().initialize();
      UrlService().useCustomSource('http://127.0.0.1:${server.port}');
      final service = SearchService();
      service.clear();
      try {
        await verify(service);
      } finally {
        service.clear();
        await subscription.cancel();
        await server.close(force: true);
      }
    }, createHttpClient: _RealHttp().createHttpClient);
  }

  Future<void> reply(HttpRequest request, {int status = 200}) async {
    request.response.statusCode = status;
    request.response.headers.contentType = ContentType.json;
    request.response.write(
      jsonEncode({
        'status': 200,
        'result': [],
        'data': {'songs': []},
      }),
    );
    await request.response.close();
  }

  test(
    'parallel completion preserves failures and same keyword retries',
    () async {
      var failQQ = true;
      var qqCalls = 0;
      final requestedUris = <Uri>[];
      final failedQQ = Completer<void>();
      await withServer(
        (request) async {
          requestedUris.add(request.uri);
          if (request.uri.path == '/qq/search') {
            qqCalls++;
            await reply(request, status: failQQ ? 503 : 200);
            if (!failedQQ.isCompleted) failedQQ.complete();
          } else {
            await failedQQ.future;
            // Make the other platforms finish after QQ's error has been applied.
            await Future<void>.delayed(const Duration(milliseconds: 40));
            await reply(request);
          }
        },
        (service) async {
          await service.search('same', saveHistory: false);
          expect(service.searchResult.qqError, isNotNull);
          expect(service.searchResult.allCompleted, true);
          expect(service.searchResult.neteaseError, isNull);
          failQQ = false;
          await service.search('same', saveHistory: false);
          expect(qqCalls, 2);
          expect(service.searchResult.hasError, false);
          expect(requestedUris.any((uri) => uri.path == '/kuwo/search'), false);
          expect(
            requestedUris
                .where((uri) => uri.path == '/qq/search')
                .every((uri) => uri.queryParameters['limit'] == '20'),
            true,
          );
        },
      );
    },
  );

  test('late old failures cannot overwrite a new search', () async {
    final oldStarted = Completer<void>();
    final releaseOld = Completer<void>();
    await withServer(
      (request) async {
        if (request.uri.queryParameters['keywords'] == 'old' &&
            request.uri.path == '/qq/search') {
          oldStarted.complete();
          await releaseOld.future;
          await reply(request, status: 503);
        } else {
          await reply(request);
        }
      },
      (service) async {
        final oldSearch = service.search('old', saveHistory: false);
        await oldStarted.future;
        await service.search('new', saveHistory: false);
        releaseOld.complete();
        await oldSearch;
        expect(service.currentKeyword, 'new');
        expect(service.searchResult.allCompleted, true);
        expect(service.searchResult.hasError, false);
      },
    );
  });

  test(
    'QQ degradation survives other results and resets on new search',
    () async {
      await withServer(
        (request) async {
          if (request.uri.path != '/qq/search') {
            await Future<void>.delayed(const Duration(milliseconds: 20));
            await reply(request);
            return;
          }
          request.response.headers.contentType = ContentType.json;
          request.response.write(
            jsonEncode({
              'status': 200,
              'result': [],
              if (request.uri.queryParameters['keywords'] == 'suggestions')
                'resultKind': 'suggestions',
            }),
          );
          await request.response.close();
        },
        (service) async {
          await service.search('suggestions', saveHistory: false);
          expect(service.searchResult.qqSuggestions, true);
          expect(service.searchResult.hasError, false);
          await service.search('full', saveHistory: false);
          expect(service.searchResult.qqSuggestions, false);
        },
      );
    },
  );
}
