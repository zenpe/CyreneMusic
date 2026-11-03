import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:cyrene_music/services/playback/audio_engine.dart';
import 'package:cyrene_music/services/playback/engine_host.dart';
import 'package:cyrene_music/services/playback/playable_source.dart';
import 'package:cyrene_music/services/proxy_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:media_kit/media_kit.dart' as mk;

/// Real libmpv + real loopback HTTP. No NAS credentials or external music API.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  // This native integration test deliberately uses real loopback HTTP.
  HttpOverrides.global = null;
  final library = File('build/windows/x64/runner/Release/libmpv-2.dll');
  test(
    'Windows native proxy playback, HTTP failures and following-song recovery',
    () async {
      mk.MediaKit.ensureInitialized(libmpv: library.absolute.path);
      final data = _wav();
      final origin = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final hungStarted = Completer<void>();
      final releaseHung = Completer<void>();
      origin.listen((request) async {
        if (request.uri.path == '/hang') {
          if (!hungStarted.isCompleted) hungStarted.complete();
          await releaseHung.future;
          return;
        }
        try {
          final status = int.tryParse(request.uri.path.substring(1));
          if (status != null) {
            request.response.statusCode = status;
          } else {
            final match = RegExp(
              r'bytes=(\d+)-',
            ).firstMatch(request.headers.value('range') ?? '');
            final start = match == null ? 0 : int.parse(match[1]!);
            request.response.headers.set('content-type', 'audio/wav');
            request.response.headers.set('accept-ranges', 'bytes');
            if (start >= data.length) {
              request.response.statusCode = 416;
            } else {
              if (match != null) {
                request.response.statusCode = 206;
                request.response.headers.set(
                  'content-range',
                  'bytes $start-${data.length - 1}/${data.length}',
                );
              }
              request.response.contentLength = data.length - start;
              if (request.method != 'HEAD') {
                request.response.add(data.sublist(start));
              }
            }
          }
          await request.response.close();
        } catch (_) {
          /* Cancelled native request. */
        }
      });
      final proxy = ProxyService();
      expect(await proxy.start(), isTrue);
      final host = EngineHost();
      var generation = 0;
      Future<void> play(String path) {
        final original = 'http://127.0.0.1:${origin.port}/$path';
        final local = proxy.getProxyUrl(original, 'qq');
        return host.playSource(
          ProxyHttpPlayableSource(local, originalUrl: original),
          generation: ++generation,
          loadTimeout: const Duration(seconds: 6),
        );
      }

      try {
        await play('audio.wav');
        await Future<void>.delayed(const Duration(milliseconds: 400));
        expect(host.isPlaying, isTrue);
        expect(host.position, greaterThan(Duration.zero));
        for (final status in [404, 429]) {
          await expectLater(
            play('$status'),
            throwsA(
              isA<EngineReportedException>().having(
                (e) => e.error.httpStatus,
                'HTTP status',
                status,
              ),
            ),
          );
          await play('audio.wav');
          expect(host.isPlaying, isTrue);
        }
        final superseded = play('hang');
        await hungStarted.future.timeout(const Duration(seconds: 2));
        await Future.wait([
          superseded,
          play('audio.wav'),
        ]).timeout(const Duration(seconds: 4));
        expect(host.isPlaying, isTrue);
        releaseHung.complete();
        await host.pause();
        expect(host.canResumeSource(generation), isTrue);
        await host.resume();
      } finally {
        if (!releaseHung.isCompleted) releaseHung.complete();
        await host.dispose();
        await proxy.stop();
        await origin.close(force: true);
      }
    },
    skip: !Platform.isWindows || !library.existsSync(),
    timeout: const Timeout(Duration(seconds: 40)),
  );
}

Uint8List _wav() {
  final bytes = Uint8List(44 + 8000 * 2 * 20);
  final header = ByteData.sublistView(bytes);
  void text(int start, String value) =>
      bytes.setRange(start, start + value.length, value.codeUnits);
  text(0, 'RIFF');
  header.setUint32(4, bytes.length - 8, Endian.little);
  text(8, 'WAVEfmt ');
  header.setUint32(16, 16, Endian.little);
  header.setUint16(20, 1, Endian.little);
  header.setUint16(22, 1, Endian.little);
  header.setUint32(24, 8000, Endian.little);
  header.setUint32(28, 16000, Endian.little);
  header.setUint16(32, 2, Endian.little);
  header.setUint16(34, 16, Endian.little);
  text(36, 'data');
  header.setUint32(40, bytes.length - 44, Endian.little);
  return bytes;
}
