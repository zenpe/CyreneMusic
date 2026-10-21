import 'dart:io';
import 'dart:developer' as developer;

import 'package:path/path.dart' as p;

import 'download_file_writer.dart';

/// Downloads into an isolated attempt directory and publishes complete files only.
class UpdatePackageDownloader {
  UpdatePackageDownloader({DownloadFileWriter? writer})
    : _writer = writer ?? DownloadFileWriter();

  final DownloadFileWriter _writer;

  static Uri resolveUrl(String rawUrl, String backendUrl) {
    if (rawUrl.trim().isEmpty) throw const FormatException('更新包地址为空');
    final base = Uri.parse(
      backendUrl.endsWith('/') ? backendUrl : '$backendUrl/',
    );
    final uri = base.resolve(rawUrl.trim());
    if ((uri.scheme != 'https' && uri.scheme != 'http') || uri.host.isEmpty) {
      throw const FormatException('更新包地址必须为 HTTP 或 HTTPS');
    }
    return uri;
  }

  Future<File> download(
    Uri uri,
    Directory directory, {
    void Function(double)? onProgress,
  }) async {
    await directory.create(recursive: true);
    final attempt = await directory.createTemp('attempt-');
    try {
      // Only use a basename; a URL must never choose paths outside the attempt.
      final rawName = uri.pathSegments.isEmpty ? '' : uri.pathSegments.last;
      final name = p.basename(rawName).replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
      final file = File(
        p.join(
          attempt.path,
          name.isEmpty || name == '.' || name == '..' ? 'update.bin' : name,
        ),
      );
      await _writer.write(
        file.path,
        (staged) => _writer.download(
          uri,
          staged,
          headers: const {},
          onProgress: onProgress,
        ),
      );
      return file;
    } catch (_) {
      try {
        await attempt.delete(recursive: true);
      } on FileSystemException catch (error, stack) {
        developer.log('Update cleanup failed', error: error, stackTrace: stack);
      }
      rethrow;
    }
  }
}
