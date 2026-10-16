import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:cached_network_image/cached_network_image.dart';

import 'package:cyrene_music/models/track.dart';
import 'package:cyrene_music/services/search_service.dart';
import 'package:cyrene_music/services/url_service.dart';
import 'package:cyrene_music/utils/theme_manager.dart';
import 'package:cyrene_music/widgets/search_widget.dart';
import 'package:fluent_ui/fluent_ui.dart' as fluent;
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _RealHttp extends HttpOverrides {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  for (final framework in [ThemeFramework.material, ThemeFramework.fluent]) {
    testWidgets(
      '${framework.name} lazily appends and preserves per-platform scrolling',
      (tester) async {
        SharedPreferences.setMockInitialValues({});
        // Cover IO is independent of pagination; serve it from Flutter's cache.
        const coverUrl = 'https://example.invalid/pagination-cover.png';
        final recorder = ui.PictureRecorder();
        ui.Canvas(recorder);
        final picture = recorder.endRecording();
        final image = picture.toImageSync(2, 2);
        picture.dispose();
        for (final provider in <ImageProvider>[
          const CachedNetworkImageProvider(coverUrl),
          ResizeImage.resizeIfNeeded(
            128,
            128,
            const CachedNetworkImageProvider(coverUrl),
          ),
        ]) {
          final key = await provider.obtainKey(const ImageConfiguration());
          PaintingBinding.instance.imageCache.putIfAbsent(
            key,
            () => OneFrameImageStreamCompleter(
              SynchronousFuture(ImageInfo(image: image.clone())),
            ),
          );
        }
        image.dispose();
        late HttpServer server;
        final service = SearchService();
        var calls = 0;
        await tester.runAsync(() async {
          server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
          server.listen((request) async {
            calls++;
            final params = request.method == 'POST'
                ? Uri.splitQueryString(await utf8.decoder.bind(request).join())
                : request.uri.queryParameters;
            final page = int.parse(params['page']!);
            request.response.headers.contentType = ContentType.json;
            request.response.write(
              jsonEncode({
                'status': 200,
                'page': page,
                'hasMore': true,
                'resultKind': 'full',
                'pageFingerprint': 'page-$page',
                'result': List.generate(20, (index) {
                  final id = (page - 1) * 20 + index;
                  return {
                    'id': id,
                    'mid': '$id',
                    'hash': '$id',
                    'name': 'song-$id',
                    'artists': 'Singer',
                    'singer': 'Singer',
                    'album': '',
                    'pic': coverUrl,
                    'picUrl': coverUrl,
                  };
                }),
              }),
            );
            await request.response.close();
          });
          await UrlService().initialize();
          UrlService().useCustomSource('http://127.0.0.1:${server.port}');
          await ThemeManager().ensureSettingsLoaded();
          await HttpOverrides.runZoned(
            () => service.search('test', saveHistory: false),
            createHttpClient: _RealHttp().createHttpClient,
          );
        });
        addTearDown(() async {
          service.clear();
          await server.close(force: true);
        });
        ThemeManager().setThemeFramework(framework);
        final search = SearchWidget(onClose: () {});
        await tester.pumpWidget(
          framework == ThemeFramework.fluent
              ? fluent.FluentApp(home: Material(child: search))
              : MaterialApp(home: Scaffold(body: search)),
        );
        await tester.pump();
        await tester.pump(const Duration(seconds: 1));
        expect(find.text('song-19'), findsNothing);
        final list = find.byType(ListView);
        await tester.drag(list, const Offset(0, -700));
        await tester.pump();
        await tester.pump(const Duration(seconds: 1));
        ScrollPosition position() => tester
            .state<ScrollableState>(
              find
                  .descendant(
                    of: find.byType(ListView),
                    matching: find.byType(Scrollable),
                  )
                  .first,
            )
            .position;
        final offset = position().pixels;
        expect(offset, greaterThan(0));
        await tester.runAsync(
          () => HttpOverrides.runZoned(
            () => service.loadMore(MusicSource.netease),
            createHttpClient: _RealHttp().createHttpClient,
          ),
        );
        await tester.pump();
        await tester.pump(const Duration(seconds: 1));
        expect(service.searchResult.neteaseResults.length, 40);
        expect(position().pixels, closeTo(offset, 1));

        final tabs = find.byWidgetPredicate(
          (widget) =>
              widget.runtimeType.toString() ==
              (framework == ThemeFramework.fluent
                  ? '_FluentPivotTabs'
                  : '_SearchExpressiveTabs'),
        );
        final buttons = find.descendant(
          of: tabs,
          matching: framework == ThemeFramework.fluent
              ? find.byType(fluent.HoverButton)
              : find.byType(GestureDetector),
        );
        await tester.tap(buttons.at(1));
        await tester.pump();
        await tester.pump(const Duration(seconds: 1));
        expect(position().pixels, 0);
        await tester.tap(buttons.at(0));
        await tester.pump();
        await tester.pump(const Duration(seconds: 1));
        expect(position().pixels, closeTo(offset, 1));
        expect(calls, 4);

        await tester.runAsync(
          () => HttpOverrides.runZoned(
            () => service.search('test', saveHistory: false),
            createHttpClient: _RealHttp().createHttpClient,
          ),
        );
        await tester.pump();
        await tester.pump(const Duration(seconds: 1));
        expect(position().pixels, 0);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
        await tester.pump(const Duration(seconds: 1));
        PaintingBinding.instance.imageCache.clear();
        PaintingBinding.instance.imageCache.clearLiveImages();
      },
    );
  }
}
