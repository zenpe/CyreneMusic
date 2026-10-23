import 'dart:convert';
import 'dart:io';

const _baselinePath = 'tool/analyzer_baseline.json';

Future<void> main(List<String> arguments) async {
  final analyzer = await _runAnalyzer();
  final diagnostics = analyzer.lines;
  final current = _countDiagnostics(diagnostics);

  if (analyzer.exitCode != 0 && current.isEmpty) {
    stderr.writeln('Analyzer failed without producing diagnostics.');
    for (final line in diagnostics.where((line) => line.trim().isNotEmpty)) {
      stderr.writeln(line);
    }
    exitCode = analyzer.exitCode;
    return;
  }

  if (arguments.contains('--print-current')) {
    stdout.writeln(const JsonEncoder.withIndent('  ').convert(current));
    if (current.isEmpty && diagnostics.isNotEmpty) {
      stdout.writeln('Unparsed analyzer output sample:');
      for (final line in diagnostics.take(10)) {
        stdout.writeln(jsonEncode(line));
      }
    }
    return;
  }

  final baselineFile = File(_baselinePath);
  if (!baselineFile.existsSync()) {
    stderr.writeln('Analyzer baseline not found: $_baselinePath');
    exitCode = 2;
    return;
  }

  final baseline = (jsonDecode(await baselineFile.readAsString()) as Map).map(
    (key, value) => MapEntry(key.toString(), value as int),
  );
  final regressions = <String>[];

  for (final entry in current.entries) {
    final allowed = baseline[entry.key] ?? 0;
    if (entry.value > allowed) {
      regressions.add('${entry.key}: ${entry.value} (baseline $allowed)');
    }
  }

  final errorCount = current.entries
      .where((entry) => entry.key.startsWith('ERROR:'))
      .fold<int>(0, (sum, entry) => sum + entry.value);
  if (errorCount > 0) {
    regressions.add('Analyzer reported $errorCount error(s)');
  }

  if (regressions.isNotEmpty) {
    stderr.writeln('Analyzer baseline regression:');
    for (final regression in regressions) {
      stderr.writeln('  $regression');
    }
    exitCode = 1;
    return;
  }

  final warningCount = _severityTotal(current, 'WARNING:');
  final infoCount = _severityTotal(current, 'INFO:');
  stdout.writeln(
    'Analyzer baseline passed: $warningCount warnings, $infoCount infos.',
  );
}

Future<({List<String> lines, int exitCode})> _runAnalyzer() async {
  ProcessResult result;
  try {
    result = await Process.run('flutter', ['analyze', '--machine', '--no-pub']);
  } on ProcessException {
    result = await Process.run('puro', [
      'flutter',
      'analyze',
      '--machine',
      '--no-pub',
    ]);
  }

  return (
    lines: [
      ...const LineSplitter().convert(result.stdout.toString()),
      ...const LineSplitter().convert(result.stderr.toString()),
    ],
    exitCode: result.exitCode,
  );
}

Map<String, int> _countDiagnostics(List<String> lines) {
  final counts = <String, int>{};
  for (final line in lines) {
    final fields = line.split('|');
    String? severity;
    String? code;
    if (fields.length >= 3 &&
        const {'ERROR', 'WARNING', 'INFO'}.contains(fields[0])) {
      severity = fields[0];
      // Flutter's pipe-delimited machine output places the analyzer rule
      // code in fields[2]. The trailing field is the human-readable message.
      code = fields[2].trim();
    } else {
      final humanMatch = RegExp(
        r'^\s*(error|warning|info) - .* - ([a-z0-9_]+)$',
      ).firstMatch(line);
      if (humanMatch != null) {
        severity = humanMatch.group(1)!.toUpperCase();
        code = humanMatch.group(2)!;
      }
    }
    if (severity == null || code == null) continue;
    final key = '$severity:$code';
    counts.update(key, (value) => value + 1, ifAbsent: () => 1);
  }
  return Map.fromEntries(
    counts.entries.toList()..sort((a, b) => a.key.compareTo(b.key)),
  );
}

int _severityTotal(Map<String, int> counts, String prefix) => counts.entries
    .where((entry) => entry.key.startsWith(prefix))
    .fold(0, (sum, entry) => sum + entry.value);
