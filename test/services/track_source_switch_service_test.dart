import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:cyrene_music/models/playlist.dart';
import 'package:cyrene_music/models/track.dart';
import 'package:cyrene_music/services/track_source_switch_service.dart';
import 'package:cyrene_music/services/url_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _RealHttp extends HttpOverrides {}

PlaylistTrack track(String name) => PlaylistTrack.fromTrack(
  Track(id: name, name: name, artists: 'artist', album: '', picUrl: ''),
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  for (final restart in [false, true]) {
    test(
      'cancelled search cannot write after clear (restart=$restart)',
      () async {
        SharedPreferences.setMockInitialValues({});
        final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
        final started = Completer<void>();
        final release = Completer<void>();
        var oldRequests = 0;
        final subscription = server.listen((request) async {
          final keyword = request.uri.queryParameters['keywords']!;
          if (keyword.startsWith('old')) {
            oldRequests++;
            if (!started.isCompleted) started.complete();
            await release.future;
          }
          try {
            request.response.headers.contentType = ContentType.json;
            request.response.write(
              jsonEncode({
                'status': 200,
                'result': [
                  {
                    'mid': keyword,
                    'name': keyword,
                    'singer': 'artist',
                    'album': '',
                    'pic': '',
                  },
                ],
              }),
            );
            await request.response.close();
          } on IOException {
            /* The cancelled client has closed its connection. */
          }
        });
        await HttpOverrides.runZoned(() async {
          await UrlService().initialize();
          UrlService().useCustomSource('http://127.0.0.1:${server.port}');
          final service = TrackSourceSwitchService()..clear();
          try {
            final old = service.startSourceSwitch([
              track('old'),
              track('old2'),
            ], MusicSource.qq);
            await started.future.timeout(const Duration(seconds: 5));
            service.cancel();
            service.clear();
            await old.timeout(const Duration(seconds: 2));
            expect(service.isProcessing, false);
            if (restart) {
              await service.startSourceSwitch([track('new')], MusicSource.qq);
            }
            release.complete();
            await Future<void>.delayed(const Duration(milliseconds: 30));
            expect(oldRequests, 1);
            expect(service.isProcessing, false);
            if (restart) {
              expect(service.results.single.originalTrack.name, 'new');
              expect(service.results.single.selectedTrack?.id, 'new artist');
            } else {
              expect(service.results, isEmpty);
            }
          } finally {
            if (!release.isCompleted) release.complete();
            service.clear();
            await subscription.cancel();
            await server.close(force: true);
          }
        }, createHttpClient: _RealHttp().createHttpClient);
      },
    );
  }
}
