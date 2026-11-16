import 'package:flutter_test/flutter_test.dart';

import '../../tool/check_analyzer_baseline.dart';

void main() {
  test('counts machine, Windows and Linux analyzer diagnostics', () {
    expect(
      countAnalyzerDiagnostics([
        'INFO|LINT|use_null_aware_elements|file.dart|1|1|1|Message',
        '   info - lib/file.dart:1:1 - Message - use_null_aware_elements',
        '   info • Message • lib/file.dart:1:1 • use_null_aware_elements',
        '  error • Message • lib/file.dart:2:1 • undefined_identifier',
        'warning - lib/file.dart:3:1 - Message - unused_import',
        '3 issues found. (ran in 1.0s)',
      ]),
      {
        'INFO:use_null_aware_elements': 3,
        'ERROR:undefined_identifier': 1,
        'WARNING:unused_import': 1,
      },
    );
  });

  test('counts colored diagnostics without mistaking summaries for issues', () {
    expect(
      countAnalyzerDiagnostics([
        '\x1b[31m  error • Message • lib/file.dart:2:1 • undefined_identifier\x1b[0m',
        'Running build hooks...',
        '1 issue found.',
      ]),
      {'ERROR:undefined_identifier': 1},
    );
  });
}
