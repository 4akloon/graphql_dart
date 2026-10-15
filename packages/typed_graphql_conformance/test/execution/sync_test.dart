import 'dart:async';

import 'package:test/test.dart';
import 'package:typed_graphql/typed_graphql.dart';
import 'package:typed_graphql_server/typed_graphql_server.dart';

import '../support/execution_port.dart';

// Ported from graphql-js src/execution/__tests__/sync-test.ts;
// mapping/execution.csv says which tests are adapted or skipped, and why.
void main() {
  const port = ExecutionPort();

  final b = ExecutableSchemaBuilder<Object?>();
  final schema = b.build(
    query: b.object<Object?>(
      'Query',
      fields: (t) => [
        t
            .field('syncField', b.string.nullable)
            .pure((rootValue) => rootValue as String?),
        t
            .field('asyncField', b.string.nullable)
            .resolve(
              (rootValue, args, context, info) =>
                  Future.value(rootValue as String?),
            ),
      ],
    ),
    mutation: b.object<Object?>(
      'Mutation',
      fields: (t) => [
        t
            .field('syncMutationField', b.string.nullable)
            .pure((rootValue) => rootValue as String?),
      ],
    ),
    options: const BuildOptions<Object?>(includesDeferAndStream: true),
  );
  const withRoot = ExecutionOptions(maskErrors: false, rootValue: 'rootValue');

  group('Execute: synchronously when possible', () {
    test('does not return a Promise for initial errors', () {
      final result = port.run(
        schema,
        'fragment Example on Query { syncField }',
        options: withRoot,
      );
      expect(result, isNot(isA<Future<Object?>>()));
      expect(
        port.withoutCodes(result as ResponsePayload),
        equals({
          'errors': [
            {'message': 'Must provide an operation.'},
          ],
        }),
      );
    });

    test('does not return a Promise if fields are all synchronous', () {
      final result = port.run(
        schema,
        'query Example { syncField }',
        options: withRoot,
      );
      expect(result, isNot(isA<Future<Object?>>()));
      expect(
        port.withoutCodes(result as ResponsePayload),
        equals({
          'data': {'syncField': 'rootValue'},
        }),
      );
    });

    test(
      'does not return a Promise if mutation fields are all synchronous',
      () {
        final result = port.run(
          schema,
          'mutation Example { syncMutationField }',
          options: withRoot,
        );
        expect(result, isNot(isA<Future<Object?>>()));
        expect(
          port.withoutCodes(result as ResponsePayload),
          equals({
            'data': {'syncMutationField': 'rootValue'},
          }),
        );
      },
    );

    test('returns a Promise if any field is asynchronous', () async {
      final result = port.run(
        schema,
        'query Example { syncField, asyncField }',
        options: withRoot,
      );
      expect(result, isA<Future<Object?>>());
      expect(
        port.withoutCodes(await result),
        equals({
          'data': {'syncField': 'rootValue', 'asyncField': 'rootValue'},
        }),
      );
    });

    group('executeSync', () {
      test('does not return a Promise for sync execution', () {
        final result = port.run(
          schema,
          'query Example { syncField }',
          options: withRoot,
        );
        expect(result, isNot(isA<Future<Object?>>()));
        expect(
          port.withoutCodes(result as ResponsePayload),
          equals({
            'data': {'syncField': 'rootValue'},
          }),
        );
      });

      test('throws if encountering async execution', () {
        final result = port.run(
          schema,
          'query Example { syncField, asyncField }',
          options: withRoot,
        );
        expect(result, isA<Future<Object?>>());
      });

      test('throws if encountering async iterable execution', () {
        final result = port.run(
          schema,
          '''
        query Example {
          ...deferFrag @defer(label: "deferLabel")
        }
        fragment deferFrag on Query {
          syncField
        }
      ''',
          options: withRoot,
        );
        expect(result, isNot(isA<Future<Object?>>()));
        expect(
          port.withoutCodes(result as ResponsePayload),
          equals({
            'data': {'syncField': 'rootValue'},
          }),
        );
      });
    });

    group('graphqlSync', () {
      test('does not return a Promise for syntax errors', () async {
        expect(
          await port.respond(
            schema,
            'fragment Example on Query { { { syncField }',
          ),
          equals({
            'errors': [
              {
                'message': 'Syntax Error: Expected Name, found "{".',
                'locations': [
                  {'line': 1, 'column': 29},
                ],
              },
            ],
          }),
        );
      });

      test('does not return a Promise for validation errors', () async {
        const text = 'fragment Example on Query { unknownField }';
        final validationErrors = const DocumentValidator()
            .validate(schema.schema, port.parse(text), source: Source(text))
            .diagnostics;
        expect(
          await port.respond(schema, text),
          equals(port.problems(validationErrors)),
        );
      });

      test('does not return a Promise for sync execution', () async {
        expect(
          await port.respond(
            schema,
            'query Example { syncField }',
            rootValue: 'rootValue',
          ),
          equals({
            'data': {'syncField': 'rootValue'},
          }),
        );
      });
    });
  });
}
