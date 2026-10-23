import 'dart:async';
import 'dart:io';

import 'package:cyrene_music/models/song_detail.dart';
import 'package:cyrene_music/models/track.dart';
import 'package:cyrene_music/services/download_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory directory;
  late DownloadService service;

  setUpAll(() async {
    directory = await Directory.systemTemp.createTemp(
      'cyrene_download_service_',
    );
    SharedPreferences.setMockInitialValues({'download_path': directory.path});
    service = DownloadService();
    await service.setDownloadPath(directory.path);
  });
  tearDownAll(() async {
    await directory.delete(recursive: true);
  });

  test(
    'same track cannot start a second download under another filename',
    () async {
      await HttpOverrides.runZoned(() async {
        final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
        final started = Completer<void>();
        final release = Completer<void>();
        var calls = 0;
        server.listen((request) async {
          calls++;
          started.complete();
          await release.future;
          request.response.add([1, 2, 3]);
          await request.response.close();
        });
        try {
          final track = _track('one', 'First');
          final detail = _detail(track, server);
          final pending = service.downloadSong(track, detail);
          await started.future;
          expect(service.isDownloading(track), isTrue);
          expect(await service.isDownloaded(track, 'standard'), isFalse);
          expect(
            await service.getDownloadedFilePath(track, 'standard'),
            isNull,
          );
          expect(
            await service.downloadSong(_track('one', 'Alias'), detail),
            isFalse,
          );
          release.complete();
          expect(await pending, isTrue);
          expect(service.isDownloading(track), isFalse);
          expect(calls, 1);
          final file = File(
            (await service.getDownloadedFilePath(track, 'standard'))!,
          );
          expect((await file.readAsBytes()).reversed.take(3).toList(), [
            3,
            2,
            1,
          ]);
          expect(await service.downloadSong(track, detail), isFalse);
          expect(calls, 1);
        } finally {
          if (!release.isCompleted) release.complete();
          await server.close(force: true);
        }
      }, createHttpClient: _RealHttpOverrides().createHttpClient);
    },
  );

  test('failed attempt timer cannot remove a pending retry', () async {
    await HttpOverrides.runZoned(() async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final retryStarted = Completer<void>();
      final release = Completer<void>();
      var calls = 0;
      server.listen((request) async {
        if (++calls == 1) {
          request.response.statusCode = 403;
        } else {
          retryStarted.complete();
          await release.future;
          request.response.add([4, 5]);
        }
        await request.response.close();
      });
      try {
        final track = _track('two', 'Retry');
        final detail = _detail(track, server);
        expect(await service.downloadSong(track, detail), isFalse);
        expect(service.isDownloading(track), isFalse);
        expect(service.downloadTasks['qq_two']!.isFailed, isTrue);
        expect(await service.isDownloaded(track, 'standard'), isFalse);
        final pending = service.downloadSong(track, detail);
        await retryStarted.future;
        expect(service.isDownloading(track), isTrue);
        final retryTask = service.downloadTasks['qq_two'];
        await Future<void>.delayed(const Duration(milliseconds: 5200));
        expect(service.downloadTasks['qq_two'], same(retryTask));
        expect(retryTask!.isFailed, isFalse);
        release.complete();
        expect(await pending, isTrue);
        expect(retryTask.isCompleted, isTrue);
        expect(service.isDownloading(track), isFalse);
        expect(await service.isDownloaded(track, 'standard'), isTrue);
      } finally {
        if (!release.isCompleted) release.complete();
        await server.close(force: true);
      }
    }, createHttpClient: _RealHttpOverrides().createHttpClient);
  });

  test(
    'downloading FLAC does not hide an existing MP3 of the same track',
    () async {
      await HttpOverrides.runZoned(() async {
        final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
        final started = Completer<void>();
        final release = Completer<void>();
        server.listen((request) async {
          started.complete();
          await release.future;
          request.response.statusCode = 403;
          await request.response.close();
        });
        try {
          final track = _track('qualities', 'MultipleQualities');
          final mp3 = File(
            '${directory.path}${Platform.pathSeparator}MultipleQualities - Artist.mp3',
          );
          await mp3.writeAsBytes([7, 8, 9]);
          final pending = service.downloadSong(
            track,
            _detail(track, server, level: 'flac'),
          );
          await started.future;
          expect(service.isDownloading(track), isTrue);
          expect(await service.isDownloaded(track, 'standard'), isTrue);
          expect(
            await service.getDownloadedFilePath(track, 'standard'),
            mp3.path,
          );
          expect(await service.isDownloaded(track, 'flac'), isFalse);
          expect(await service.getDownloadedFilePath(track, 'flac'), isNull);
          expect(await mp3.readAsBytes(), [7, 8, 9]);
          release.complete();
          expect(await pending, isFalse);
          expect(await service.isDownloaded(track, 'standard'), isTrue);
        } finally {
          if (!release.isCompleted) release.complete();
          await server.close(force: true);
        }
      }, createHttpClient: _RealHttpOverrides().createHttpClient);
    },
  );

  test(
    'cover timeout closes its connection and preserves downloaded audio',
    () async {
      await HttpOverrides.runZoned(() async {
        final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
        final disconnected = Completer<void>();
        Socket? coverSocket;
        server.listen((request) async {
          if (request.uri.path == '/cover') {
            final socket = await request.response.detachSocket(
              writeHeaders: false,
            );
            coverSocket = socket;
            socket.write('HTTP/1.1 200 OK\r\nContent-Length: 100\r\n\r\n');
            socket.add([1]);
            await socket.flush();
            socket.listen(
              (_) {},
              onDone: () {
                if (!disconnected.isCompleted) disconnected.complete();
              },
              onError: (Object _) {
                if (!disconnected.isCompleted) disconnected.complete();
              },
            );
          } else {
            request.response.add([8, 9]);
            await request.response.close();
          }
        });
        try {
          final track = _track('cover', 'CoverTimeout');
          final detail = _detail(track, server, withCover: true);
          expect(await service.downloadSong(track, detail), isTrue);
          await disconnected.future.timeout(const Duration(seconds: 2));
          final path = await service.getDownloadedFilePath(track, 'standard');
          expect(await File(path!).readAsBytes(), [8, 9]);
          expect(service.isDownloading(track), isFalse);
        } finally {
          coverSocket?.destroy();
          await server.close(force: true);
        }
      }, createHttpClient: _RealHttpOverrides().createHttpClient);
    },
  );
}

class _RealHttpOverrides extends HttpOverrides {}

Track _track(String id, String name) => Track(
  id: id,
  name: name,
  artists: 'Artist',
  album: 'Album',
  picUrl: '',
  source: MusicSource.qq,
);

SongDetail _detail(
  Track track,
  HttpServer server, {
  bool withCover = false,
  String level = 'standard',
}) => SongDetail(
  id: track.id,
  name: track.name,
  pic: withCover ? 'http://${server.address.address}:${server.port}/cover' : '',
  arName: track.artists,
  alName: track.album,
  level: level,
  size: '',
  url: 'http://${server.address.address}:${server.port}/audio',
  lyric: '',
  tlyric: '',
  source: track.source,
);
