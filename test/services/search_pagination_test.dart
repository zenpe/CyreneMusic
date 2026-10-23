import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:cyrene_music/models/track.dart';
import 'package:cyrene_music/services/search_service.dart';
import 'package:cyrene_music/services/url_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _RealHttp extends HttpOverrides {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Map<String, dynamic> song(String id) => {
    'mid': id,
    'id': int.tryParse(id) ?? 1,
    'hash': id,
    'name': id,
    'singer': 'Singer',
    'artists': 'Singer',
    'album': '',
    'pic': '',
    'picUrl': '',
  };

  Future<void> reply(
    HttpRequest request,
    List<String> ids, {
    int page = 1,
    bool hasMore = false,
    int status = 200,
    String kind = 'full',
    String? fingerprint,
  }) async {
    request.response.statusCode = status;
    request.response.headers.contentType = ContentType.json;
    request.response.write(
      jsonEncode({
        'status': status,
        'result': ids.map(song).toList(),
        'page': page,
        'hasMore': hasMore,
        'resultKind': kind,
        'pageFingerprint': fingerprint ?? ids.join(','),
      }),
    );
    await request.response.close();
  }

  Future<void> withServer(
    Future<void> Function(HttpRequest request, Map<String, dynamic> params)
    handle,
    Future<void> Function(SearchService service, List<String> calls) verify,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final calls = <String>[];
    final subscription = server.listen((request) async {
      final params = request.method == 'POST'
          ? Uri.splitQueryString(await utf8.decoder.bind(request).join())
          : request.uri.queryParameters;
      calls.add('${request.uri.path}:${params['page']}');
      await handle(request, params);
    });
    await HttpOverrides.runZoned(() async {
      await UrlService().initialize();
      UrlService().useCustomSource('http://127.0.0.1:${server.port}');
      final service = SearchService()..clear();
      try {
        await verify(service, calls);
      } finally {
        service.clear();
        await subscription.cancel();
        await server.close(force: true);
      }
    }, createHttpClient: _RealHttp().createHttpClient);
  }

  test(
    'all platforms append independently with stable order and deduplication',
    () async {
      await withServer(
        (request, params) async {
          final page = int.parse(params['page']);
          await reply(
            request,
            page == 1 ? ['1', '2'] : ['2', '3'],
            page: page,
            hasMore: page == 1,
          );
        },
        (service, calls) async {
          await service.search('test', saveHistory: false);
          for (final platform in [
            MusicSource.qq,
            MusicSource.netease,
            MusicSource.kugou,
          ]) {
            await service.loadMore(platform);
            expect(
              service.searchResult
                  .resultsFor(platform)
                  .map((t) => t.id.toString()),
              ['1', '2', '3'],
            );
            expect(service.pageFor(platform).page, 2);
            expect(service.pageFor(platform).hasMore, false);
          }
          expect(calls.length, 6);
        },
      );
    },
  );

  test(
    'failed append keeps rows and retries the same page on only that platform',
    () async {
      var fail = true;
      await withServer(
        (request, params) async {
          final page = int.parse(params['page']);
          await reply(
            request,
            page == 1 ? ['1'] : ['2'],
            page: page,
            hasMore: true,
            status: page == 2 && fail ? 504 : 200,
          );
        },
        (service, calls) async {
          await service.search('test', saveHistory: false);
          await service.loadMore(MusicSource.qq);
          expect(service.pageFor(MusicSource.qq).page, 1);
          expect(service.pageFor(MusicSource.qq).error, isNotNull);
          expect(service.searchResult.qqResults.single.id, '1');
          expect(service.searchResult.qqError, isNull);
          fail = false;
          await service.retryPlatform(MusicSource.qq);
          expect(service.pageFor(MusicSource.qq).page, 2);
          expect(service.pageFor(MusicSource.qq).error, isNull);
          expect(calls.where((c) => c == '/qq/search:2').length, 2);
          expect(calls.where((c) => c.startsWith('/search:')).length, 1);
        },
      );
    },
  );

  test('first page retry does not refetch other platforms', () async {
    var fail = true;
    await withServer(
      (request, params) => reply(request, [
        '1',
      ], status: request.uri.path == '/qq/search' && fail ? 502 : 200),
      (service, calls) async {
        await service.search('test', saveHistory: false);
        expect(service.searchResult.qqError, isNotNull);
        fail = false;
        await service.retryPlatform(MusicSource.qq);
        expect(service.searchResult.qqError, isNull);
        expect(calls.length, 4);
      },
    );
  });

  test(
    'closing during history persistence also clears first-page loading',
    () async {
      await withServer((request, params) => reply(request, []), (
        service,
        calls,
      ) async {
        final pending = service.search('close immediately');
        service.cancelPendingRequests();
        await pending;
        expect(service.searchResult.allCompleted, true);
        expect(service.searchResult.qqError, isNotNull);
        expect(calls, isEmpty);
      });
    },
  );

  test('duplicate clicks send only one pending page request', () async {
    final started = Completer<void>(), release = Completer<void>();
    await withServer(
      (request, params) async {
        final page = int.parse(params['page']);
        if (page == 2) {
          started.complete();
          await release.future;
        }
        await reply(request, [page.toString()], page: page, hasMore: true);
      },
      (service, calls) async {
        await service.search('test', saveHistory: false);
        final pending = service.loadMore(MusicSource.qq);
        await started.future;
        await service.loadMore(MusicSource.qq);
        expect(service.pageFor(MusicSource.qq).loadingMore, true);
        release.complete();
        await pending;
        expect(calls.where((c) => c == '/qq/search:2').length, 1);
      },
    );
  });

  test('new same-keyword session discards a late old page', () async {
    final started = Completer<void>(), release = Completer<void>();
    await withServer(
      (request, params) async {
        final page = int.parse(params['page']);
        if (page == 2) {
          started.complete();
          await release.future;
        }
        await reply(request, [page.toString()], page: page, hasMore: true);
      },
      (service, calls) async {
        await service.search('same', saveHistory: false);
        final pending = service.loadMore(MusicSource.qq);
        await started.future;
        await service.search('same', saveHistory: false);
        release.complete();
        await pending;
        expect(service.pageFor(MusicSource.qq).page, 1);
        expect(service.searchResult.qqResults.single.id, '1');
      },
    );
  });

  test(
    'repeated raw page blocks further requests without adding duplicate rows',
    () async {
      await withServer(
        (request, params) => reply(
          request,
          ['1'],
          page: int.parse(params['page']),
          hasMore: true,
        ),
        (service, calls) async {
          await service.search('test', saveHistory: false);
          await service.loadMore(MusicSource.qq);
          expect(service.pageFor(MusicSource.qq).blocked, true);
          expect(service.pageFor(MusicSource.qq).page, 1);
          await service.loadMore(MusicSource.qq);
          expect(calls.length, 4);
        },
      );
    },
  );

  test('suggestion results never load more', () async {
    await withServer(
      (request, params) =>
          reply(request, ['1'], hasMore: true, kind: 'suggestions'),
      (service, calls) async {
        await service.search('test', saveHistory: false);
        await service.loadMore(MusicSource.qq);
        expect(service.searchResult.qqSuggestions, true);
        expect(calls.length, 3);
      },
    );
  });

  for (final invalid in ['wrong-page', 'suggestions']) {
    test(
      'invalid appended $invalid preserves existing results and page',
      () async {
        await withServer(
          (request, params) async {
            final page = int.parse(params['page']);
            await reply(
              request,
              [page.toString()],
              page: page == 2 && invalid == 'wrong-page' ? 1 : page,
              kind: page == 2 && invalid == 'suggestions'
                  ? 'suggestions'
                  : 'full',
              hasMore: true,
            );
          },
          (service, calls) async {
            await service.search('test', saveHistory: false);
            await service.loadMore(MusicSource.qq);
            expect(service.searchResult.qqResults.single.id, '1');
            expect(service.pageFor(MusicSource.qq).page, 1);
            expect(service.pageFor(MusicSource.qq).error, isNotNull);
            expect(service.searchResult.qqSuggestions, false);
          },
        );
      },
    );
  }

  test(
    'filtered empty and fully deduplicated pages still advance from metadata',
    () async {
      await withServer(
        (request, params) async {
          final page = int.parse(params['page']);
          await reply(
            request,
            page == 1 ? ['1'] : [],
            page: page,
            hasMore: page < 3,
            fingerprint: 'raw-page-$page',
          );
        },
        (service, calls) async {
          await service.search('test', saveHistory: false);
          await service.loadMore(MusicSource.qq);
          expect(service.pageFor(MusicSource.qq).page, 2);
          expect(service.pageFor(MusicSource.qq).hasMore, true);
          expect(service.searchResult.qqResults.single.id, '1');
          await service.loadMore(MusicSource.qq);
          expect(service.pageFor(MusicSource.qq).page, 3);
          expect(service.pageFor(MusicSource.qq).hasMore, false);
        },
      );
    },
  );

  test(
    'closing cancels append, unlocks loading, and allows retry on reopening',
    () async {
      final started = Completer<void>(), release = Completer<void>();
      var hold = true;
      await withServer(
        (request, params) async {
          final page = int.parse(params['page']);
          if (page == 2 && hold) {
            started.complete();
            await release.future;
          }
          await reply(request, [page.toString()], page: page, hasMore: true);
        },
        (service, calls) async {
          await service.search('test', saveHistory: false);
          final pending = service.loadMore(MusicSource.qq);
          await started.future;
          service.cancelPendingRequests();
          expect(service.pageFor(MusicSource.qq).loadingMore, false);
          expect(service.searchResult.qqResults.single.id, '1');
          hold = false;
          release.complete();
          await pending;
          await service.loadMore(MusicSource.qq);
          expect(service.pageFor(MusicSource.qq).page, 2);
        },
      );
    },
  );
}
