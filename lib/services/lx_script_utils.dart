import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:pointycastle/export.dart';
import 'package:pointycastle/asn1/asn1_parser.dart';
import 'package:pointycastle/asn1/primitives/asn1_bit_string.dart';
import 'package:pointycastle/asn1/primitives/asn1_integer.dart';
import 'package:pointycastle/asn1/primitives/asn1_sequence.dart';

/// Synchronous utilities executed beside the engine, never on the UI isolate.
/// Bytes cross the JS bridge as base64, preserving typed-array slice boundaries.
class LxScriptUtils {
  static const maxBytes = 8 * 1024 * 1024;
  final Random _random = Random.secure();

  Map<String, Object?> handle(dynamic arguments) {
    try {
      final args = Map<String, dynamic>.from(arguments as Map);
      final operation = args['operation'];
      Uint8List bytes(String key) {
        final value = args[key] as String;
        if (value.length > (maxBytes + 2) ~/ 3 * 4) {
          throw const FormatException('音源工具输入过大');
        }
        final result = base64Decode(value);
        if (result.length > maxBytes) {
          throw const FormatException('音源工具输入过大');
        }
        return result;
      }

      final Uint8List output;
      switch (operation) {
        case 'random':
          final size = args['size'] as int;
          if (size < 0 || size > 65536) {
            throw const FormatException('随机字节长度无效');
          }
          output = Uint8List.fromList(
            List.generate(size, (_) => _random.nextInt(256)),
          );
        case 'aes':
          final mode = args['mode'] as String;
          final match = RegExp(
            r'^aes-(128|192|256)-(ecb|cbc)$',
          ).firstMatch(mode);
          if (match == null) throw const FormatException('不支持的 AES 模式');
          final key = bytes('key');
          final iv = bytes('iv');
          if (key.length * 8 != int.parse(match.group(1)!)) {
            throw const FormatException('AES 密钥长度无效');
          }
          final cbc = match.group(2) == 'cbc';
          if (iv.length != (cbc ? 16 : 0)) {
            throw const FormatException('AES IV 长度无效');
          }
          final cipher = BlockCipher('AES/${cbc ? 'CBC' : 'ECB'}');
          cipher.init(
            true,
            cbc ? ParametersWithIV(KeyParameter(key), iv) : KeyParameter(key),
          );
          final data = bytes('data');
          final padding = 16 - data.length % 16;
          final padded = Uint8List(data.length + padding)..setAll(0, data);
          padded.fillRange(data.length, padded.length, padding);
          output = Uint8List(padded.length);
          for (var offset = 0; offset < padded.length; offset += 16) {
            cipher.processBlock(padded, offset, output, offset);
          }
        case 'rsa':
          final pem = args['key'] as String;
          if (pem.length > 16384) throw const FormatException('RSA 公钥过大');
          final match = RegExp(
            r'-----BEGIN (RSA PUBLIC KEY|PUBLIC KEY)-----([\s\S]+?)-----END \1-----',
          ).firstMatch(pem);
          if (match == null) throw const FormatException('RSA 公钥格式无效');
          var sequence =
              ASN1Parser(
                    base64Decode(match.group(2)!.replaceAll(RegExp(r'\s'), '')),
                  ).nextObject()
                  as ASN1Sequence;
          if (match.group(1) == 'PUBLIC KEY') {
            sequence =
                ASN1Parser(
                      Uint8List.fromList(
                        (sequence.elements![1] as ASN1BitString).stringValues!,
                      ),
                    ).nextObject()
                    as ASN1Sequence;
          }
          final modulus = (sequence.elements![0] as ASN1Integer).integer!;
          final exponent = (sequence.elements![1] as ASN1Integer).integer!;
          // LX's public API prepends zeroes to a 128-byte block and uses
          // RSA_NO_PADDING. Do not silently substitute OAEP or PKCS1 padding.
          if (modulus.bitLength != 1024 ||
              exponent <= BigInt.one ||
              exponent.bitLength > 32) {
            throw const FormatException('LX RSA 需要 1024 位公钥');
          }
          final data = bytes('data');
          if (data.length > 128) throw const FormatException('RSA 输入过长');
          final block = Uint8List(128)..setRange(128 - data.length, 128, data);
          final engine = RSAEngine()
            ..init(
              true,
              PublicKeyParameter<RSAPublicKey>(RSAPublicKey(modulus, exponent)),
            );
          output = engine.process(block);
        case 'inflate':
        case 'deflate':
          final sink = _BoundedBytes(maxBytes);
          final converter = operation == 'inflate'
              ? ZLibDecoder().startChunkedConversion(sink)
              : ZLibEncoder().startChunkedConversion(sink);
          final input = bytes('data');
          // Bound decompressed output while it is produced, before allocating
          // a complete inflated buffer (including deliberately tiny zip bombs).
          try {
            for (var offset = 0; offset < input.length; offset += 1024) {
              converter.add(
                input.sublist(offset, min(offset + 1024, input.length)),
              );
            }
          } finally {
            converter.close();
          }
          output = sink.bytes.takeBytes();
        default:
          throw const FormatException('未知音源工具操作');
      }
      if (output.length > maxBytes) throw const FormatException('音源工具输出过大');
      return {'value': base64Encode(output)};
    } catch (_) {
      // Inputs can contain secrets. Never include them or a native stack in
      // the script error, and never log arguments from this bridge.
      return {'error': '音源工具调用失败，请检查算法、密钥和数据格式'};
    }
  }
}

class _BoundedBytes implements Sink<List<int>> {
  _BoundedBytes(this.limit);
  final int limit;
  final bytes = BytesBuilder(copy: false);
  @override
  void add(List<int> data) {
    if (bytes.length + data.length > limit) {
      throw const FormatException('解压结果过大');
    }
    bytes.add(data);
  }

  @override
  void close() {}
}
