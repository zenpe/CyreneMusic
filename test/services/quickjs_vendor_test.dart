import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('vendored quickjs-ng sources match the pinned upstream manifest', () {
    const root = 'third_party/flutter_js/native/quickjs';
    final manifest = jsonDecode(
      File('$root/UPSTREAM.json').readAsStringSync(),
    ) as Map<String, dynamic>;
    expect(manifest['tag'], 'v0.18.0');
    expect(manifest['commit'], 'd7215b0ad3fc2c562e8317fd9bca058fd4863804');
    final files = manifest['files'] as Map<String, dynamic>;
    expect(files, contains('LICENSE'));
    for (final entry in files.entries) {
      expect(
        sha256.convert(File('$root/${entry.key}').readAsBytesSync()).toString(),
        entry.value,
        reason: 'Unexpected upstream source modification: ${entry.key}',
      );
    }
    expect(
      Directory(root).listSync().map((file) => file.uri.pathSegments.last),
      unorderedEquals([...files.keys, 'UPSTREAM.json']),
    );
  });
}
