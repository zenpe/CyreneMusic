import 'dart:async';
import 'dart:io';

import 'package:cyrene_music/models/track.dart';
import 'package:cyrene_music/services/download_file_writer.dart';
import 'package:cyrene_music/utils/audio_request_headers.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory directory;
  late HttpServer server;
  late DownloadFileWriter writer;
  late String target;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('cyrene_download_test_');
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    writer = DownloadFileWriter(
      connectionTimeout: const Duration(milliseconds: 300),
      idleTimeout: const Duration(milliseconds: 150),
    );
    target = '${directory.path}/song.mp3';
  });
  tearDown(() async {
    await server.close(force: true);
    await directory.delete(recursive: true);
  });

  Future<void> download({void Function(double)? onProgress}) => writer.write(
    target,
    (file) => writer.download(
      Uri.parse('http://${server.address.address}:${server.port}/audio'),
      file,
      headers: buildAudioRequestHeaders(MusicSource.qq),
      onProgress: onProgress,
    ),
  );

  test(
    'publishes complete audio with platform headers and removes staging',
    () async {
      final payload = List<int>.generate(1024, (i) => i % 256);
      final headersChecked = Completer<void>();
      server.listen((request) async {
        expect(request.headers.value('referer'), 'https://y.qq.com/');
        expect(request.headers.value('origin'), 'https://y.qq.com');
        expect(request.headers.value('user-agent'), contains('Mozilla'));
        expect(request.headers.value('accept-encoding'), 'identity');
        headersChecked.complete();
        request.response.contentLength = payload.length;
        request.response.add(payload);
        await request.response.close();
      });
      final progress = <double>[];
      await download(onProgress: progress.add);
      await headersChecked.future;
      expect(await File(target).readAsBytes(), payload);
      expect(progress.last, 1);
      expect(await directory.list().length, 1);
    },
  );

  test('stream interruption leaves no final file and retry succeeds', () async {
    var calls = 0;
    server.listen((request) async {
      calls++;
      if (calls == 1) {
        final socket = await request.response.detachSocket(writeHeaders: false);
        socket.write('HTTP/1.1 200 OK\r\nContent-Length: 100\r\n\r\n');
        socket.add([1, 2, 3]);
        await socket.flush();
        socket.destroy();
      } else {
        request.response.add([4, 5, 6]);
        await request.response.close();
      }
    });
    await expectLater(download(), throwsA(isA<Exception>()));
    expect(await directory.list().toList(), isEmpty);
    await download();
    expect(await File(target).readAsBytes(), [4, 5, 6]);
    expect(calls, 2);
  });

  test('header timeout closes request and releases target for retry', () async {
    var calls = 0;
    server.listen((request) async {
      if (++calls == 1) return;
      request.response.add([1]);
      await request.response.close();
    });
    await expectLater(download(), throwsA(isA<TimeoutException>()));
    expect(await directory.list().toList(), isEmpty);
    await download();
    expect(await File(target).readAsBytes(), [1]);
  });

  test('idle body times out and removes partial data', () async {
    server.listen((request) async {
      request.response.add([1, 2, 3]);
      await request.response.flush();
    });
    await expectLater(download(), throwsA(isA<TimeoutException>()));
    expect(await directory.list().toList(), isEmpty);
  });

  test('ongoing transfer may exceed idle timeout in total', () async {
    writer = DownloadFileWriter(
      connectionTimeout: const Duration(seconds: 2),
      idleTimeout: const Duration(milliseconds: 600),
    );
    server.listen((request) async {
      request.response.bufferOutput = false;
      for (var i = 0; i < 8; i++) {
        request.response.add([i]);
        await request.response.flush();
        await Future<void>.delayed(const Duration(milliseconds: 100));
      }
      await request.response.close();
    });
    await download();
    expect(await File(target).readAsBytes(), [0, 1, 2, 3, 4, 5, 6, 7]);
  });

  test('duplicate pending target sends only one request', () async {
    final started = Completer<void>();
    final release = Completer<void>();
    var calls = 0;
    server.listen((request) async {
      calls++;
      started.complete();
      await release.future;
      request.response.add([1]);
      await request.response.close();
    });
    final pending = download();
    await started.future;
    await expectLater(download(), throwsA(isA<FileSystemException>()));
    release.complete();
    await pending;
    expect(calls, 1);
  });

  test('existing file is never populated or overwritten', () async {
    await File(target).writeAsBytes([7, 8]);
    var populated = false;
    await expectLater(
      writer.write(target, (_) async {
        populated = true;
      }),
      throwsA(isA<FileSystemException>()),
    );
    expect(populated, isFalse);
    expect(await File(target).readAsBytes(), [7, 8]);
  });

  test('file created during transfer is preserved', () async {
    await expectLater(
      writer.write(target, (file) async {
        await file.writeAsBytes([1]);
        await File(target).writeAsBytes([9]);
      }),
      throwsA(isA<FileSystemException>()),
    );
    expect(await File(target).readAsBytes(), [9]);
    expect(await directory.list().length, 1);
  });

  test('HTTP rejection and empty responses never publish files', () async {
    var calls = 0;
    server.listen((request) async {
      request.response.statusCode = ++calls == 1 ? 403 : 200;
      await request.response.close();
    });
    await expectLater(download(), throwsA(isA<HttpException>()));
    await expectLater(download(), throwsA(isA<HttpException>()));
    expect(await directory.list().toList(), isEmpty);
  });
}
