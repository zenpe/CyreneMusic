import 'dart:convert';
import 'dart:io';

import 'package:cyrene_music/services/lx_script_utils.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final vectors =
      jsonDecode(File('test/support/lx_utils_vectors.json').readAsStringSync())
          as Map;
  test('AES matches Node createCipheriv including PKCS7 and empty input', () {
    final host = LxScriptUtils();
    for (final vector in vectors['aes'] as List) {
      final args = Map<String, dynamic>.from(vector as Map)..remove('value');
      expect(
        host.handle({'operation': 'aes', ...args})['value'],
        vector['value'],
      );
    }
  });
  test(
    'raw RSA matches Node publicEncrypt with PKCS1 and SPKI public keys',
    () {
      final host = LxScriptUtils();
      for (final vector in vectors['rsa'] as List) {
        expect(
          host.handle({
            'operation': 'rsa',
            'key': vector['key'],
            'data': vector['data'],
          })['value'],
          vector['value'],
        );
      }
    },
  );
  test('zlib interoperates with independently compressed Node bytes', () {
    final host = LxScriptUtils();
    final vector = vectors['zlib'] as Map;
    expect(
      host.handle({
        'operation': 'inflate',
        'data': vector['compressed'],
      })['value'],
      vector['data'],
    );
    final encoded = host.handle({
      'operation': 'deflate',
      'data': vector['data'],
    });
    expect(
      ZLibDecoder().convert(base64Decode(encoded['value'] as String)),
      base64Decode(vector['data'] as String),
    );
  });
  test(
    'invalid inputs fail without returning plaintext or pretending success',
    () {
      final host = LxScriptUtils();
      for (final args in [
        {
          'operation': 'aes',
          'mode': 'aes-128-cbc',
          'key': '',
          'iv': '',
          'data': '',
        },
        {
          'operation': 'aes',
          'mode': 'aes-128-unknown',
          'key': '',
          'iv': '',
          'data': '',
        },
        {'operation': 'rsa', 'key': 'private-secret', 'data': ''},
        {
          'operation': 'inflate',
          'data': base64Encode([1, 2, 3]),
        },
        {'operation': 'random', 'size': 65537},
      ]) {
        final result = host.handle(args);
        expect(result.containsKey('value'), isFalse);
        expect(result['error'], isNot(contains('private-secret')));
      }
    },
  );
  test('inflate enforces its output limit during decompression', () {
    final compressed = ZLibEncoder().convert(
      List.filled(LxScriptUtils.maxBytes + 1, 0),
    );
    expect(
      LxScriptUtils()
          .handle({'operation': 'inflate', 'data': base64Encode(compressed)})
          .containsKey('error'),
      isTrue,
    );
  });
  test(
    'secure random returns requested bytes and rejects negative lengths',
    () {
      final host = LxScriptUtils();
      final first =
          host.handle({'operation': 'random', 'size': 32})['value'] as String;
      final second =
          host.handle({'operation': 'random', 'size': 32})['value'] as String;
      expect(base64Decode(first), hasLength(32));
      expect(second, isNot(first));
      expect(
        host.handle({'operation': 'random', 'size': -1}).containsKey('error'),
        isTrue,
      );
    },
  );
}
