import 'package:test/test.dart';
import 'package:typed_graphql/typed_graphql.dart';
import 'package:typed_graphql_server/typed_graphql_server.dart';

import '../support/execution_port.dart';

// Ported from graphql-js src/execution/__tests__/oneof-test.ts;
// mapping/execution.csv says which tests are adapted or skipped, and why.
void main() {
  const port = ExecutionPort();

  // The schema of graphql-js's `buildSchema`, rebuilt with the builder; the
  // field `test` answers its input as an object of the same fields.
  final b = ExecutableSchemaBuilder<Object?>();
  final inputA = Arg.optional('a', b.string.nullable);
  final inputB = Arg.optional('b', b.int.nullable);
  final testInput = b.oneOfInputObject<Map<String, Object?>>(
    'TestInputObject',
    fields: () => [inputA, inputB],
    decode: (values) => {
      if (values.get(inputA) case Present(:final value)) 'a': value,
      if (values.get(inputB) case Present(:final value)) 'b': value,
    },
  );
  final testObject = b.object<Map<String, Object?>>(
    'TestObject',
    fields: (t) => [
      t.field('a', b.string.nullable).pure((parent) => parent['a'] as String?),
      t.field('b', b.int.nullable).pure((parent) => parent['b'] as int?),
    ],
  );
  final input = Arg('input', testInput);
  final schema = b.build(
    query: b.object<Object?>(
      'Query',
      fields: (t) => [
        t
            .field('test', testObject.nullable, args: [input])
            .resolve((parent, args, context, info) => args.get(input)),
      ],
    ),
  );

  Future<Map<String, Object?>> run(
    String query, [
    Map<String, Object?>? variables,
  ]) => port.json(
    schema,
    query,
    variables: variables == null ? null : port.variablesOf(variables),
  );

  const badOneOf =
      'Within OneOf Input Object type "TestInputObject", exactly one field must be specified, and the value for that field must be non-null.';

  group('Execute: Handles OneOf Input Objects', () {
    group('OneOf Input Objects', () {
      const operation = r'''

        query ($input: TestInputObject!) {
          test(input: $input) {
            a
            b
          }
        }
      ''';

      Map<String, Object?> variableError(String where, String message) => {
        'errors': [
          {
            'message': 'Variable "\$input" has invalid value$where: $message',
            'locations': [
              {'line': 2, 'column': 16},
            ],
          },
        ],
      };

      test('accepts a good default value', () async {
        final result = await run(r'''
        query ($input: TestInputObject! = {a: "abc"}) {
          test(input: $input) {
            a
            b
          }
        }
      ''');

        expect(result, {
          'data': {
            'test': {'a': 'abc', 'b': null},
          },
        });
      });

      test('rejects a bad default value', () async {
        final result = await run(r'''

        query ($input: TestInputObject! = {a: "abc", b: 123}) {
          test(input: $input) {
            a
            b
          }
        }
      ''');

        expect(result, {
          'errors': [
            {
              'locations': [
                {'column': 16, 'line': 2},
              ],
              'message':
                  'Variable "\$input" has invalid default value: $badOneOf',
            },
          ],
        });
      });

      test('accepts a good variable', () async {
        final result = await run(operation, {
          'input': {'a': 'abc'},
        });

        expect(result, {
          'data': {
            'test': {'a': 'abc', 'b': null},
          },
        });
      });

      test('accepts a good variable with an undefined key', () async {
        final result = await run(operation, {
          'input': {'a': 'abc'},
        });

        expect(result, {
          'data': {
            'test': {'a': 'abc', 'b': null},
          },
        });
      });

      test('rejects a variable with a nulled key', () async {
        final result = await run(operation, {
          'input': {'a': null},
        });

        expect(result, variableError(' at .a', badOneOf));
      });

      test('rejects a variable with multiple non-null keys', () async {
        final result = await run(operation, {
          'input': {'a': 'abc', 'b': 123},
        });

        expect(result, variableError('', badOneOf));
      });

      test('rejects a variable with multiple nullable keys', () async {
        final result = await run(operation, {
          'input': {'a': 'abc', 'b': null},
        });

        expect(result, variableError('', badOneOf));
      });

      Map<String, Object?> fieldError(String message, int line) => {
        'data': {'test': null},
        'errors': [
          {
            'message':
                'Argument "Query.test(input:)" has invalid value: $message',
            'locations': [
              {'line': line, 'column': 23},
            ],
            'path': ['test'],
          },
        ],
      };

      test('errors with nulled variable for field', () async {
        final result = await run(
          r'''

        query ($a: String) {
          test(input: { a: $a }) {
            a
            b
          }
        }
      ''',
          {'a': null},
        );

        expect(
          result,
          fieldError(
            r'Expected variable "$a" provided to field "a" for OneOf Input Object type "TestInputObject" not to be null.',
            3,
          ),
        );
      });

      test('errors with missing variable for field', () async {
        final result = await run(r'''

        query ($a: String) {
          test(input: { a: $a }) {
            a
            b
          }
        }
      ''');

        expect(
          result,
          fieldError(
            r'Expected variable "$a" provided to field "a" for OneOf Input Object type "TestInputObject" to provide a runtime value.',
            3,
          ),
        );
      });

      test('errors with missing variable as an additional field', () async {
        final result = await run(
          r'''

        query ($a: String, $b: Int) {
          test(input: { a: $a, b: $b }) {
            a
            b
          }
        }
      ''',
          {'a': 'abc'},
        );

        expect(
          result,
          fieldError(
            r'Expected variable "$b" provided to field "b" for OneOf Input Object type "TestInputObject" to provide a runtime value.',
            3,
          ),
        );
      });
    });
  });
}
