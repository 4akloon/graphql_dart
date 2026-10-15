import 'package:test/test.dart';
import 'package:typed_graphql_server/typed_graphql_server.dart';

import '../support/execution_port.dart';

// Ported from graphql-js src/execution/__tests__/executor-test.ts;
// mapping/execution.csv says which tests are adapted or skipped, and why.
void main() {
  const port = ExecutionPort();

  // A root whose field `name` reads the key of the root value.
  ObjectTypeDef<Object?> root(
    ExecutableSchemaBuilder<Object?> b,
    String typeName,
    List<String> names,
  ) => b.object<Object?>(
    typeName,
    fields: (t) => [
      for (final name in names)
        t
            .field(name, b.string.nullable)
            .pure((rootValue) => (rootValue as Map<String, String>?)?[name]),
    ],
  );

  ExecutableSchema<Object?> querySchema() {
    final b = ExecutableSchemaBuilder<Object?>();
    return b.build(query: root(b, 'Type', ['a']));
  }

  const rootValue = ExecutionOptions(
    maskErrors: false,
    rootValue: <String, String>{'a': 'b', 'c': 'd'},
  );

  group('Execute: Handles basic execution tasks', () {
    test(
      'uses the inline operation if no operation name is provided',
      () async {
        expect(
          await port.json(
            querySchema(),
            '{ a }',
            options: const ExecutionOptions(
              maskErrors: false,
              rootValue: <String, String>{'a': 'b'},
            ),
          ),
          equals({
            'data': {'a': 'b'},
          }),
        );
      },
    );

    test('uses the only operation if no operation name is provided', () async {
      expect(
        await port.json(
          querySchema(),
          'query Example { a }',
          options: const ExecutionOptions(
            maskErrors: false,
            rootValue: <String, String>{'a': 'b'},
          ),
        ),
        equals({
          'data': {'a': 'b'},
        }),
      );
    });

    test('uses the named operation if operation name is provided', () async {
      expect(
        await port.json(
          querySchema(),
          '''
      query Example { first: a }
      query OtherExample { second: a }
    ''',
          operationName: 'OtherExample',
          options: const ExecutionOptions(
            maskErrors: false,
            rootValue: <String, String>{'a': 'b'},
          ),
        ),
        equals({
          'data': {'second': 'b'},
        }),
      );
    });

    test('provides error if no operation is provided', () async {
      expect(
        await port.json(querySchema(), 'fragment Example on Type { a }'),
        equals({
          'errors': [
            {'message': 'Must provide an operation.'},
          ],
        }),
      );
    });

    test(
      'errors if no op name is provided with multiple operations',
      () async {
        expect(
          await port.json(querySchema(), '''
      query Example { a }
      query OtherExample { a }
    '''),
          equals({
            'errors': [
              {
                'message':
                    'Must provide operation name if query contains multiple '
                    'operations.',
              },
            ],
          }),
        );
      },
    );

    test('errors if unknown operation name is provided', () async {
      expect(
        await port.json(
          querySchema(),
          '''
      query Example { a }
      query OtherExample { a }
    ''',
          operationName: 'UnknownExample',
        ),
        equals({
          'errors': [
            {'message': 'Unknown operation named "UnknownExample".'},
          ],
        }),
      );
    });

    test('errors if empty string is provided as operation name', () async {
      expect(
        await port.json(querySchema(), '{ a }', operationName: ''),
        equals({
          'errors': [
            {'message': 'Unknown operation named "".'},
          ],
        }),
      );
    });

    test('uses the query schema for queries', () async {
      final b = ExecutableSchemaBuilder<Object?>();
      final schema = b.build(
        query: root(b, 'Q', ['a']),
        mutation: root(b, 'M', ['c']),
        subscription: root(b, 'S', ['a']),
      );
      expect(
        await port.json(
          schema,
          '''
      query Q { a }
      mutation M { c }
      subscription S { a }
    ''',
          operationName: 'Q',
          options: rootValue,
        ),
        equals({
          'data': {'a': 'b'},
        }),
      );
    });

    test('uses the mutation schema for mutations', () async {
      final b = ExecutableSchemaBuilder<Object?>();
      final schema = b.build(
        query: root(b, 'Q', ['a']),
        mutation: root(b, 'M', ['c']),
      );
      expect(
        await port.json(
          schema,
          '''
      query Q { a }
      mutation M { c }
    ''',
          operationName: 'M',
          options: rootValue,
        ),
        equals({
          'data': {'c': 'd'},
        }),
      );
    });

    test('uses the subscription schema for subscriptions', () async {
      final b = ExecutableSchemaBuilder<Object?>();
      final schema = b.build(
        query: root(b, 'Q', ['a']),
        subscription: root(b, 'S', ['a']),
      );
      expect(
        await port.json(
          schema,
          '''
      query Q { a }
      subscription S { a }
    ''',
          operationName: 'S',
          options: rootValue,
        ),
        equals({
          'data': {'a': 'b'},
        }),
      );
    });

    test('resolves to an error if schema does not support operation', () async {
      final schema = querySchema();
      const text = '''

      query Q { __typename }
      mutation M { __typename }
      subscription S { __typename }
    ''';

      expect(
        await port.json(schema, text, operationName: 'Q'),
        equals({
          'data': {'__typename': 'Type'},
        }),
      );
      expect(
        await port.json(schema, text, operationName: 'M'),
        equals({
          'errors': [
            {
              'message':
                  'Schema is not configured to execute mutation operation.',
            },
          ],
        }),
      );
      expect(
        await port.json(schema, text, operationName: 'S'),
        equals({
          'errors': [
            {
              'message':
                  'Schema is not configured to execute subscription operation.',
            },
          ],
        }),
      );
    });
  });
}
