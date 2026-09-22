import '../services/structured_log_service.dart';
import 'dart:io';
import 'dart:convert';
import 'dart:typed_data';

/// 专门用于解析音频文件（MP3/FLAC）内嵌元数据的实用工具
class MetadataReader {
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
    final bytes = await file.readAsBytes();
    if (bytes.length < 4 || utf8.decode(bytes.sublist(0, 4)) != 'fLaC') return null;

    int offset = 4;
    while (offset < bytes.length) {
      final header = bytes[offset];
      final isLastBlock = (header & 0x80) != 0;
      final blockType = header & 0x7F;
      final blockLength = (bytes[offset + 1] << 16) | (bytes[offset + 2] << 8) | bytes[offset + 3];

      if (blockType == 4) { // VORBIS_COMMENT
        final commentBlock = bytes.sublist(offset + 4, offset + 4 + blockLength);
        return _parseVorbisComment(commentBlock);
      }

      if (isLastBlock) break;
      offset += 4 + blockLength;
    }
    return null;
  }

  /// 解析 Vorbis Comment 块寻找 LYRICS 或 UNSYNCEDLYRICS
  static String? _parseVorbisComment(Uint8List block) {
    try {
      int offset = 0;

      // Vendor string
      final vendorLength = block[offset] | (block[offset + 1] << 8) | (block[offset + 2] << 16) | (block[offset + 3] << 24);
      offset += 4 + vendorLength;

      // User comment list length
      final commentListLength = block[offset] | (block[offset + 1] << 8) | (block[offset + 2] << 16) | (block[offset + 3] << 24);
      offset += 4;

      for (int i = 0; i < commentListLength; i++) {
        final commentLength = block[offset] | (block[offset + 1] << 8) | (block[offset + 2] << 16) | (block[offset + 3] << 24);
        offset += 4;

        final comment = utf8.decode(block.sublist(offset, offset + commentLength), allowMalformed: true);
        offset += commentLength;

        final upperComment = comment.toUpperCase();
        if (upperComment.startsWith('LYRICS=') || upperComment.startsWith('UNSYNCEDLYRICS=')) {
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
    final bytes = await file.readAsBytes();
    if (bytes.length < 10 || bytes[0] != 0x49 || bytes[1] != 0x44 || bytes[2] != 0x33) return null;

    // ID3v2 头部大小计算 (syncsafe)
    final tagSize = ((bytes[6] & 0x7F) << 21) | ((bytes[7] & 0x7F) << 14) | ((bytes[8] & 0x7F) << 7) | (bytes[9] & 0x7F);

    int offset = 10;
    final end = 10 + tagSize;

    while (offset + 10 < end) {
      final frameId = utf8.decode(bytes.sublist(offset, offset + 4), allowMalformed: true);
      final frameSize = (bytes[offset + 4] << 24) | (bytes[offset + 5] << 16) | (bytes[offset + 6] << 8) | bytes[offset + 7];

      if (frameId == 'USLT') {
        final frameContent = bytes.sublist(offset + 10, offset + 10 + frameSize);
        return _parseUsltFrame(frameContent);
      }

      if (frameSize <= 0) break; // 避免死循环
      offset += 10 + frameSize;
    }
    return null;
  }

  /// 解析 USLT 帧内容
  static String? _parseUsltFrame(Uint8List content) {
    try {
      if (content.isEmpty) return null;
      final encoding = content[0];
      // 1-3 bytes: language ('eng' etc.)
      const langSize = 3;

      // 寻找内容描述符后的结束符 (0x00)
      int lyricsStart = 1 + langSize;
      while (lyricsStart < content.length && content[lyricsStart] != 0) {
        lyricsStart++;
      }
      lyricsStart++; // 跳过结束符

      if (lyricsStart >= content.length) return null;

      final lyricsData = content.sublist(lyricsStart);
      if (encoding == 0x00) { // ISO-8859-1
        return Latin1Decoder().convert(lyricsData);
      } else if (encoding == 0x03) { // UTF-8
        return utf8.decode(lyricsData, allowMalformed: true);
      } else { // UTF-16
        return String.fromCharCodes(lyricsData.buffer.asUint16List());
      }
    } catch (e) {
      StructuredLogService.log('❌ [MetadataReader] 解析 USLT 帧失败: $e');
    }
    return null;
  }
}
