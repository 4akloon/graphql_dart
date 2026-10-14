@TestOn('vm')
library;

import 'dart:io';

import 'package:test/test.dart';

import 'support/csv_table.dart';
import 'support/graphql_js_suite.dart';

void main() {
  void checkRows(CsvTable table) {
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
  }

  // A row names its graphql-js file relative to `prefix`, under `src/`;
  // `covered` lists the files whose every test must have a row.
  final tables = [
    (
      path: 'mapping/language.csv',
      prefix: 'language/__tests__/',
      covered: GraphqlJsSuite.filesIn('language/__tests__'),
    ),
    (
      path: 'mapping/schema.csv',
      prefix: '',
      covered: const [
        'type/__tests__/validation-test.ts',
        'utilities/__tests__/buildASTSchema-test.ts',
        'utilities/__tests__/extendSchema-test.ts',
        'utilities/__tests__/getIntrospectionQuery-test.ts',
        'utilities/__tests__/introspectionFromSchema-test.ts',
        'utilities/__tests__/printSchema-test.ts',
      ],
    ),
  ];
  for (final (:path, :prefix, :covered) in tables) {
    group(path, () {
      final table = CsvTable.parse(File(path).readAsStringSync());
      checkRows(table);
      test('names only graphql-js files that exist', () {
        for (final row in table.rows) {
          final file =
              '${GraphqlJsSuite.sourceDirectory}/'
              '$prefix${row['graphql_js_file']}';
          expect(File(file).existsSync(), isTrue, reason: '$row');
        }
      }, skip: !GraphqlJsSuite.isAvailable);
      // Spec §8 of M2, §11 of M3: every covered file has a row for each of
      // its tests, so a new upstream file or test fails here.
      group('rows cover every test of', () {
        for (final file in covered) {
          test(file, () {
            final mapped = {
              for (final row in table.rows)
                if (row['graphql_js_file'] == file) (row['group'], row['test']),
            };
            expect(mapped, GraphqlJsSuite.read('$prefix$file').tests.toSet());
          });
        }
      }, skip: !GraphqlJsSuite.isAvailable);
    });
  }
}
