import 'package:test/test.dart';
import 'package:typed_graphql/typed_graphql.dart';
import 'package:typed_graphql_server/typed_graphql_server.dart';

import '../support/execution_port.dart';

// Ported from graphql-js src/execution/__tests__/nonnull-test.ts;
// mapping/execution.csv says which tests are adapted or skipped, and why.
void main() {
  const port = ExecutionPort();

  group('Execute: handles non-nullable types', () {
    group('Handles non-null argument', () {
      final b = ExecutableSchemaBuilder<Object?>();
      final cannotBeNull = Arg('cannotBeNull', b.string);
      final schemaWithNonNullArg = b.build(
        query: b.object<Object?>(
          'Query',
          fields: (t) => [
            t
                .field(
                  'withNonNullArg',
                  b.string.nullable,
                  args: [cannotBeNull],
                )
                .resolve(
                  (_, args, context, info) =>
                      'Passed: ${args.get(cannotBeNull)}',
                ),
          ],
        ),
      );

      Future<Map<String, Object?>> run(
        String query, {
        JsonObject? variables,
      }) => port.json(schemaWithNonNullArg, query, variables: variables);

      Map<String, Object?> fieldError(String message, int line, int column) => {
        'data': {'withNonNullArg': null},
        'errors': [
          {
            'message': message,
            'locations': [
              {'line': line, 'column': column},
            ],
            'path': ['withNonNullArg'],
          },
        ],
      };

      test('succeeds when passed non-null literal value', () async {
        final result = await run('''

          query {
            withNonNullArg (cannotBeNull: "literal value")
          }
        ''');

        expect(
          result,
          equals({
            'data': {'withNonNullArg': 'Passed: literal value'},
          }),
        );
      });

      test('succeeds when passed non-null variable value', () async {
        final result = await run(
          r'''

          query ($testVar: String!) {
            withNonNullArg (cannotBeNull: $testVar)
          }
        ''',
          variables: JsonObject({
            'testVar': const JsonString('variable value'),
          }),
        );

        expect(
          result,
          equals({
            'data': {'withNonNullArg': 'Passed: variable value'},
          }),
        );
      });

      test('succeeds when missing variable has default value', () async {
        final result = await run(
          r'''

          query ($testVar: String = "default value") {
            withNonNullArg (cannotBeNull: $testVar)
          }
        ''',
          variables: JsonObject({}),
        );

        expect(
          result,
          equals({
            'data': {'withNonNullArg': 'Passed: default value'},
          }),
        );
      });

      test('field error when missing non-null arg', () async {
        // Validation should identify this issue first (missing args rule)
        // however execution should still protect against this.
        final result = await run('''

          query {
            withNonNullArg
          }
        ''');

        expect(
          result,
          equals(
            fieldError(
              'Argument "Query.withNonNullArg(cannotBeNull:)" of required '
              'type "String!" was not provided.',
              3,
              13,
            ),
          ),
        );
      });

      test('field error when non-null arg provided null', () async {
        // Validation should identify this issue first (values of correct
        // type rule) however execution should still protect against this.
        final result = await run('''

          query {
            withNonNullArg(cannotBeNull: null)
          }
        ''');

        expect(
          result,
          equals(
            fieldError(
              'Argument "Query.withNonNullArg(cannotBeNull:)" has invalid '
              'value: Expected value of non-null type "String!" not to be '
              'null.',
              3,
              42,
            ),
          ),
        );
      });

      test(
        'field error when non-null arg not provided variable value',
        () async {
          // Validation should identify this issue first (variables in allowed
          // position rule) however execution should still protect against this.
          final result = await run(
            r'''

          query ($testVar: String) {
            withNonNullArg(cannotBeNull: $testVar)
          }
        ''',
            variables: JsonObject({}),
          );

          expect(
            result,
            equals(
              fieldError(
                'Argument "Query.withNonNullArg(cannotBeNull:)" has invalid '
                r'value: Expected variable "$testVar" provided to type '
                '"String!" to provide a runtime value.',
                3,
                42,
              ),
            ),
          );
        },
      );

      test(
        'field error when non-null arg provided variable with explicit null value',
        () async {
          final result = await run(
            r'''

          query ($testVar: String = "default value") {
            withNonNullArg (cannotBeNull: $testVar)
          }
        ''',
            variables: JsonObject({'testVar': const JsonNull()}),
          );

          expect(
            result,
            equals(
              fieldError(
                'Argument "Query.withNonNullArg(cannotBeNull:)" has invalid '
                r'value: Expected variable "$testVar" provided to non-null '
                'type "String!" not to be null.',
                3,
                43,
              ),
            ),
          );
        },
      );
    });
  });
}
