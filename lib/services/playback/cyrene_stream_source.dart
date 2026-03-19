import 'dart:io';

import 'package:just_audio/just_audio.dart' as ja;

import '../cache_service.dart';

class CyreneStreamSource extends ja.StreamAudioSource {
  final String filePath;
  final int payloadOffset;
  final int audioLength;
  final String contentType;

  CyreneStreamSource({
    required this.filePath,
    required this.payloadOffset,
    required this.audioLength,
    required this.contentType,
    super.tag,
  });

  @override
  Future<ja.StreamAudioResponse> request([int? start, int? end]) async {
    final normalizedStart = _normalizeStart(start);
    final normalizedEnd = _normalizeEnd(end, normalizedStart);

    return ja.StreamAudioResponse(
      rangeRequestsSupported: true,
      sourceLength: audioLength,
      contentLength: normalizedEnd - normalizedStart,
      offset: normalizedStart,
      contentType: contentType,
      stream: _openDecryptedStream(
        fileStart: payloadOffset + normalizedStart,
        fileEnd: payloadOffset + normalizedEnd,
        audioOffsetStart: normalizedStart,
      ),
    );
  }

  int _normalizeStart(int? start) {
    final value = start ?? 0;
    if (value <= 0) return 0;
    if (value >= audioLength) return audioLength;
    return value;
  }

  int _normalizeEnd(int? end, int normalizedStart) {
    final value = end ?? audioLength;
    if (value <= normalizedStart) return normalizedStart;
    if (value >= audioLength) return audioLength;
    return value;
  }

  Stream<List<int>> _openDecryptedStream({
    required int fileStart,
    required int fileEnd,
    required int audioOffsetStart,
  }) async* {
    if (fileEnd <= fileStart) {
      return;
    }

    final file = File(filePath);
    var audioOffset = audioOffsetStart;
    await for (final chunk in file.openRead(fileStart, fileEnd)) {
      final decrypted = CacheService.decryptAudioBytes(
        chunk,
        startOffset: audioOffset,
      );
      audioOffset += chunk.length;
      yield decrypted;
    }
  }
}
