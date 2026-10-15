import 'package:test/test.dart';
import 'package:typed_graphql_server/typed_graphql_server.dart';

import '../support/execution_port.dart';

// Ported from graphql-js src/execution/__tests__/errorPropagation-test.ts;
// mapping/execution.csv says which tests are adapted or skipped, and why.
void main() {
  const port = ExecutionPort();
  final b = ExecutableSchemaBuilder<Object?>();
  final schema = b.build(
    query: b.object<Object?>(
      'Query',
      fields: (t) => [
        t.field('foo', b.int).pure((_) => throw const GraphQLException('bar')),
      ],
    ),
  );

  group('Execute: handles errors', () {
    test(
      'with `@experimental_disableErrorPropagation returns null',
      () async {
        // The directive is not supported; ErrorBehavior.nullValue is the
        // same behaviour for the whole request.
        final result = await port.json(
          schema,
          '''

      query getFoo @experimental_disableErrorPropagation {
        foo
      }
    ''',
          options: const ExecutionOptions(
            errorBehavior: ErrorBehavior.nullValue,
            maskErrors: false,
          ),
        );

        expect(
          result,
          equals({
            'data': {'foo': null},
            'errors': [
              {
                'message': 'bar',
                'path': ['foo'],
                'locations': [
                  {'line': 3, 'column': 9},
                ],
              },
            ],
          }),
        );
      },
    );

    test(
      'without `experimental_disableErrorPropagation` propagates the error',
      () async {
        final result = await port.json(schema, '''

      query getFoo {
        foo
      }
    ''');

        expect(
          result,
          equals({
            'data': null,
            'errors': [
              {
                'message': 'bar',
                'path': ['foo'],
                'locations': [
                  {'line': 3, 'column': 9},
                ],
              },
            ],
          }),
        );
      },
    );
  });
}
