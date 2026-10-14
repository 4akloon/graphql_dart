@TestOn('vm')
library;

import 'dart:io';

import 'package:test/test.dart';

import 'support/csv_table.dart';
import 'support/graphql_js_suite.dart';

/// The graphql-js language test files whose every test has a row (R10.3).
/// A port task adds its file here with its rows.
const Set<String> portedFiles = {
  'lexer-test.ts',
  'blockString-test.ts',
  'parser-test.ts',
  'schema-parser-test.ts',
  'printer-test.ts',
  'schema-printer-test.ts',
  'printString-test.ts',
  'visitor-test.ts',
  'schemaCoordinateLexer-test.ts',
  'printLocation-test.ts',
  'source-test.ts',
  'predicates-test.ts',
  'kind-test.ts',
  'diagnostics-test.ts',
};

void main() {
  final table = CsvTable.parse(
    File('mapping/language.csv').readAsStringSync(),
  );

  test('has the documented columns', () {
    expect(table.header, [
      'graphql_js_file',
      'group',
      'test',
      'status',
      'dart_file',
      'reason',
    ]);
  });

  test('every row has a known status', () {
    for (final row in table.rows) {
      expect(row['status'], isIn(['ported', 'adapted', 'skipped']));
    }
  });

  test('adapted and skipped rows give a reason', () {
    for (final row in table.rows.where((row) => row['status'] != 'ported')) {
      expect(row['reason'], isNotEmpty, reason: '$row');
    }
  });

  test('no graphql-js test has two rows', () {
    final keys = [
      for (final row in table.rows)
        (row['graphql_js_file'], row['group'], row['test']),
    ];
    expect(keys.toSet(), hasLength(keys.length));
  });

  test('ported and adapted rows name a Dart test that exists', () {
    // `name(` and the quoted argument, with any whitespace between: the
    // formatter moves a long name to its own line.
    RegExp call(String name, String argument) =>
        RegExp('$name\\(\\s*${RegExp.escape("'$argument'")}');
    for (final row in table.rows.where((row) => row['status'] != 'skipped')) {
      final file = File('${row['dart_file']}');
      expect(file.existsSync(), isTrue, reason: '$row');
      final text = file.readAsStringSync();
      for (final group in '${row['group']}'.split(' > ')) {
        expect(text, contains(call('group', group)), reason: '$row');
      }
      expect(text, contains(call('test', '${row['test']}')), reason: '$row');
    }
  });

  group('rows cover every test of', () {
    for (final file in portedFiles) {
      test(file, skip: !GraphqlJsSuite.isAvailable, () {
        final mapped = {
          for (final row in table.rows)
            if (row['graphql_js_file'] == file) (row['group'], row['test']),
        };
        expect(mapped, GraphqlJsSuite.read(file).tests.toSet());
      });
    }
  });
}
