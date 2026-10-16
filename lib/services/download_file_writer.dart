import 'dart:async';
import 'dart:developer' as developer;
import 'dart:io';

import 'package:path/path.dart' as p;

/// Owns a download's staging files and publishes only complete files.
class DownloadFileWriter {
  DownloadFileWriter({
    this.connectionTimeout = const Duration(seconds: 15),
    this.idleTimeout = const Duration(seconds: 30),
  });

  final Duration connectionTimeout;
  final Duration idleTimeout;
  final Set<String> _activePaths = {};

  String _pathKey(String outputPath) {
    final normalized = p.normalize(File(outputPath).absolute.path);
    return Platform.isWindows ? normalized.toLowerCase() : normalized;
  }

  bool isWriting(String outputPath) =>
      _activePaths.contains(_pathKey(outputPath));

  Future<void> write(
    String outputPath,
    Future<void> Function(File stagedFile) populate,
  ) async {
    final target = File(outputPath).absolute;
    final key = _pathKey(outputPath);
    if (!_activePaths.add(key)) {
      throw const FileSystemException('该文件正在下载');
    }
    Directory? staging;
    try {
      if (await target.exists()) {
        throw const FileSystemException('文件已存在');
      }
      // Same filesystem as the target; keep its extension for metadata writers.
      staging = await target.parent.createTemp('.cyrene-download.part-');
      final stagedFile = File(p.join(staging.path, p.basename(outputPath)));
      await populate(stagedFile);
      if (!await stagedFile.exists() || await stagedFile.length() == 0) {
        throw const FileSystemException('下载内容为空');
      }
      // Internal writers share the path lock. Recheck before publishing, but
      // do not claim protection against another process racing this rename.
      if (await target.exists()) {
        throw const FileSystemException('文件已存在');
      }
      await stagedFile.rename(target.path);
    } finally {
      try {
        if (staging != null && await staging.exists()) {
          await staging.delete(recursive: true);
        }
      } on FileSystemException catch (error, stack) {
        // Do not hide transfer failures or report a published file as failed.
        developer.log(
          'Download staging cleanup failed',
          error: error,
          stackTrace: stack,
        );
      } finally {
        _activePaths.remove(key);
      }
    }
  }

  Future<void> download(
    Uri url,
    File stagedFile, {
    required Map<String, String> headers,
    void Function(double progress)? onProgress,
  }) async {
    final client = HttpClient()..connectionTimeout = connectionTimeout;
    RandomAccessFile? output;
    try {
      final response = await (() async {
        final request = await client.getUrl(url);
        headers.forEach(request.headers.set);
        // Compare the received byte count with the wire Content-Length.
        request.headers.set(HttpHeaders.acceptEncodingHeader, 'identity');
        return request.close();
      })().timeout(connectionTimeout);
      if (response.statusCode != HttpStatus.ok) {
        throw HttpException('HTTP ${response.statusCode}');
      }
      output = await stagedFile.open(mode: FileMode.write);
      final expectedLength =
          response.compressionState ==
              HttpClientResponseCompressionState.decompressed
          ? -1
          : response.contentLength;
      var downloaded = 0;
      await for (final chunk in response.timeout(idleTimeout)) {
        await output.writeFrom(chunk);
        downloaded += chunk.length;
        if (expectedLength > 0) {
          onProgress?.call((downloaded / expectedLength).clamp(0, 1));
        }
      }
      if (downloaded == 0 ||
          (expectedLength >= 0 && downloaded != expectedLength)) {
        throw const HttpException('下载内容不完整');
      }
      await output.flush();
    } finally {
      client.close(force: true);
      await output?.close();
    }
  }
}
