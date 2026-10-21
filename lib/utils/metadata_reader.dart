import '../services/structured_log_service.dart';
import 'dart:io';
import 'dart:convert';
import 'dart:typed_data';

/// 专门用于解析音频文件（MP3/FLAC）内嵌元数据的实用工具
class MetadataReader {
  static const int _maxLyricsBytes = 4 * 1024 * 1024;

  /// 从音频文件中提取嵌入的歌词
  static Future<String?> extractLyrics(String filePath) async {
    try {
      final file = File(filePath);
      if (!await file.exists()) return null;

      final extension = filePath.toLowerCase().split('.').last;
      if (extension == 'flac') {
        return await _extractFlacLyrics(file);
      } else if (extension == 'mp3') {
        return await _extractMp3Lyrics(file);
      }
    } catch (e) {
      StructuredLogService.log('❌ [MetadataReader] 提取歌词失败: $e');
    }
    return null;
  }

  /// 提取 FLAC 内嵌歌词 (VORBIS_COMMENT)
  static Future<String?> _extractFlacLyrics(File file) async {
    final input = await file.open();
    try {
      final signature = await input.read(4);
      if (signature.length != 4 || latin1.decode(signature) != 'fLaC') {
        return null;
      }
      final length = await input.length();
      var offset = 4;
      while (offset + 4 <= length) {
        final header = await input.read(4);
        if (header.length != 4) return null;
        final size = (header[1] << 16) | (header[2] << 8) | header[3];
        offset += 4;
        if (offset + size > length) return null;
        if ((header[0] & 0x7f) == 4) {
          if (size > _maxLyricsBytes) return null;
          return _parseVorbisComment(await input.read(size));
        }
        if ((header[0] & 0x80) != 0) return null;
        offset += size;
        await input.setPosition(offset);
      }
      return null;
    } finally {
      await input.close();
    }
  }

  /// 解析 Vorbis Comment 块寻找 LYRICS 或 UNSYNCEDLYRICS
  static String? _parseVorbisComment(Uint8List block) {
    try {
      int offset = 0;

      // Vendor string
      final vendorLength =
          block[offset] |
          (block[offset + 1] << 8) |
          (block[offset + 2] << 16) |
          (block[offset + 3] << 24);
      offset += 4 + vendorLength;

      // User comment list length
      final commentListLength =
          block[offset] |
          (block[offset + 1] << 8) |
          (block[offset + 2] << 16) |
          (block[offset + 3] << 24);
      offset += 4;

      for (int i = 0; i < commentListLength; i++) {
        final commentLength =
            block[offset] |
            (block[offset + 1] << 8) |
            (block[offset + 2] << 16) |
            (block[offset + 3] << 24);
        offset += 4;

        final comment = utf8.decode(
          block.sublist(offset, offset + commentLength),
          allowMalformed: true,
        );
        offset += commentLength;

        final upperComment = comment.toUpperCase();
        if (upperComment.startsWith('LYRICS=') ||
            upperComment.startsWith('UNSYNCEDLYRICS=')) {
          return comment.substring(comment.indexOf('=') + 1);
        }
      }
    } catch (e) {
      StructuredLogService.log('❌ [MetadataReader] 解析 VorbisComment 失败: $e');
    }
    return null;
  }

  /// 提取 MP3 内嵌歌词 (ID3v2 USLT)
  static Future<String?> _extractMp3Lyrics(File file) async {
    final input = await file.open();
    try {
      final header = await input.read(10);
      if (header.length != 10 || latin1.decode(header.sublist(0, 3)) != 'ID3') {
        return null;
      }
      final version = header[3];
      if (version != 3 && version != 4) return null;
      final end = 10 + _syncSafe(header, 6);
      if (end > await input.length()) return null;
      var offset = 10;
      if ((header[5] & 0x40) != 0) {
        final extended = await input.read(4);
        if (extended.length != 4) return null;
        final size = version == 4
            ? _syncSafe(extended, 0)
            : _bigEndian(extended, 0) + 4;
        if (size < 4 || offset + size > end) return null;
        offset += size;
        await input.setPosition(offset);
      }
      while (offset + 10 <= end) {
        final frame = await input.read(10);
        if (frame.length != 10) return null;
        final size = version == 4 ? _syncSafe(frame, 4) : _bigEndian(frame, 4);
        offset += 10;
        if (size <= 0 || offset + size > end) return null;
        if (latin1.decode(frame.sublist(0, 4)) == 'USLT') {
          if (size > _maxLyricsBytes) return null;
          // Compressed/encrypted frames need a decoder; do not interpret them as text.
          if ((frame[9] & (version == 4 ? 0x0c : 0xc0)) != 0) return null;
          return _parseUsltFrame(await input.read(size));
        }
        offset += size;
        await input.setPosition(offset);
      }
      return null;
    } finally {
      await input.close();
    }
  }

  static int _syncSafe(List<int> bytes, int offset) =>
      ((bytes[offset] & 0x7f) << 21) |
      ((bytes[offset + 1] & 0x7f) << 14) |
      ((bytes[offset + 2] & 0x7f) << 7) |
      (bytes[offset + 3] & 0x7f);

  static int _bigEndian(List<int> bytes, int offset) =>
      (bytes[offset] << 24) |
      (bytes[offset + 1] << 16) |
      (bytes[offset + 2] << 8) |
      bytes[offset + 3];

  /// 解析 USLT 帧内容
  static String? _parseUsltFrame(Uint8List content) {
    try {
      if (content.length < 5) return null;
      final encoding = content[0];
      // 1-3 bytes: language ('eng' etc.)
      const langSize = 3;

      // 寻找内容描述符后的结束符 (0x00)
      int lyricsStart = 1 + langSize;
      final utf16 = encoding == 1 || encoding == 2;
      final step = utf16 ? 2 : 1;
      while (lyricsStart + step <= content.length) {
        if (content[lyricsStart] == 0 &&
            (!utf16 || content[lyricsStart + 1] == 0)) {
          break;
        }
        lyricsStart += step;
      }
      lyricsStart += step;

      if (lyricsStart >= content.length) return null;

      final lyricsData = content.sublist(lyricsStart);
      if (encoding == 0x00) {
        // ISO-8859-1
        return Latin1Decoder().convert(lyricsData);
      } else if (encoding == 0x03) {
        // UTF-8
        return utf8.decode(lyricsData, allowMalformed: true);
      } else if (utf16) {
        var start = 0;
        var endian = encoding == 2
            ? Endian.big
            : (content[4] == 0xfe && content[5] == 0xff
                  ? Endian.big
                  : Endian.little);
        if (lyricsData.length >= 2 &&
            ((lyricsData[0] == 0xff && lyricsData[1] == 0xfe) ||
                (lyricsData[0] == 0xfe && lyricsData[1] == 0xff))) {
          endian = lyricsData[0] == 0xfe ? Endian.big : Endian.little;
          start = 2;
        }
        final data = ByteData.sublistView(lyricsData);
        return String.fromCharCodes([
          for (var i = start; i + 1 < lyricsData.length; i += 2)
            data.getUint16(i, endian),
        ]);
      }
    } catch (e) {
      StructuredLogService.log('❌ [MetadataReader] 解析 USLT 帧失败: $e');
    }
    return null;
  }
}
