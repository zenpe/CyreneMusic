import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final fixture in ['lx_sandbox_http_contract', 'lx_sandbox_lifecycle']) {
    test('production sandbox: $fixture', () async {
      final result = await Process.run('node', ['test/support/$fixture.cjs']);
      expect(result.exitCode, 0, reason: '${result.stdout}\n${result.stderr}');
    });
  }
}
