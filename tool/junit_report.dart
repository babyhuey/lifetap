// Converts a `flutter test --machine` JSON-lines event stream into a JUnit XML
// report. Dependency-free (dart:io, dart:convert) so it runs under a bare Dart
// SDK in CI.
//
//   dart run tool/junit_report.dart <machine.jsonl> <out.xml>

import 'dart:convert';
import 'dart:io';

class _Test {
  _Test({required this.name, required this.suiteId, required this.startMs});

  final String name;
  final int? suiteId;
  final int startMs;

  int? endMs;
  String result = 'success';
  bool hidden = false;
  bool skipped = false;
  final List<String> errors = [];
}

void main(List<String> args) {
  if (args.length < 2) {
    stderr.writeln(
      'usage: dart run tool/junit_report.dart <machine.jsonl> <out.xml>',
    );
    exit(64);
  }

  final lines = File(args[0]).readAsLinesSync();
  final suites = <int, String>{};
  final tests = <int, _Test>{};

  for (final line in lines) {
    final trimmed = line.trim();
    if (trimmed.isEmpty) continue;

    Object? decoded;
    try {
      decoded = jsonDecode(trimmed);
    } on FormatException {
      continue; // Non-JSON line (e.g. plain stdout) — skip gracefully.
    }
    if (decoded is! Map) continue;

    switch (decoded['type']) {
      case 'suite':
        final suite = decoded['suite'];
        if (suite is Map && suite['id'] is int) {
          suites[suite['id'] as int] = (suite['path'] as String?) ?? '';
        }
      case 'testStart':
        final test = decoded['test'];
        if (test is Map && test['id'] is int) {
          final id = test['id'] as int;
          tests[id] = _Test(
            name: (test['name'] as String?) ?? 'test $id',
            suiteId: test['suiteID'] as int?,
            startMs: (decoded['time'] as int?) ?? 0,
          );
        }
      case 'testDone':
        final t = tests[decoded['testID']];
        if (t != null) {
          t.hidden = decoded['hidden'] == true;
          t.skipped = decoded['skipped'] == true;
          t.result = (decoded['result'] as String?) ?? 'success';
          t.endMs = decoded['time'] as int?;
        }
      case 'error':
        final t = tests[decoded['testID']];
        if (t != null) {
          final err = (decoded['error'] as String?) ?? '';
          final stack = (decoded['stackTrace'] as String?) ?? '';
          t.errors.add([err, stack].where((s) => s.isNotEmpty).join('\n'));
        }
    }
  }

  final cases = tests.values.where((t) => !t.hidden).toList();
  final xml = _renderJunit(cases, suites);
  File(args[1]).writeAsStringSync(xml);
  stdout.writeln('Wrote ${args[1]} (${cases.length} testcases)');
}

String _renderJunit(List<_Test> cases, Map<int, String> suites) {
  var failures = 0;
  var errors = 0;
  var totalTime = 0.0;
  final body = StringBuffer();

  for (final t in cases) {
    final time = ((t.endMs ?? t.startMs) - t.startMs) / 1000.0;
    totalTime += time;
    final classname = suites[t.suiteId] ?? 'flutter';
    final open =
        '    <testcase classname="${_esc(classname)}" '
        'name="${_esc(t.name)}" time="${time.toStringAsFixed(3)}"';

    if (t.skipped) {
      body.writeln('$open>');
      body.writeln('      <skipped/>');
      body.writeln('    </testcase>');
    } else if (t.result == 'success') {
      body.writeln('$open/>');
    } else {
      final isError = t.result == 'error';
      if (isError) {
        errors++;
      } else {
        failures++;
      }
      final tag = isError ? 'error' : 'failure';
      final detail = t.errors.join('\n\n');
      final message = t.errors.isEmpty
          ? t.result
          : t.errors.first.split('\n').first;
      body.writeln('$open>');
      body.writeln(
        '      <$tag message="${_esc(message)}">${_esc(detail)}</$tag>',
      );
      body.writeln('    </testcase>');
    }
  }

  final total = cases.length;
  final time = totalTime.toStringAsFixed(3);
  final out = StringBuffer();
  out.writeln('<?xml version="1.0" encoding="UTF-8"?>');
  out.writeln(
    '<testsuites tests="$total" failures="$failures" '
    'errors="$errors" time="$time">',
  );
  out.writeln(
    '  <testsuite name="flutter test" tests="$total" '
    'failures="$failures" errors="$errors" time="$time">',
  );
  out.write(body);
  out.writeln('  </testsuite>');
  out.writeln('</testsuites>');
  return out.toString();
}

String _esc(String s) => s
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
    .replaceAll('"', '&quot;')
    .replaceAll("'", '&apos;');
