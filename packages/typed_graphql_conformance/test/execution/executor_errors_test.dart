import 'dart:async';

import 'package:test/test.dart';
import 'package:typed_graphql/typed_graphql.dart';
import 'package:typed_graphql_server/typed_graphql_server.dart';

import '../support/execution_port.dart';
import '../support/unchecked_ref.dart';

// Ported from graphql-js src/execution/__tests__/executor-test.ts;
// mapping/execution.csv says which tests are adapted or skipped, and why.
void main() {
  const port = ExecutionPort();

  group('Execute: Handles basic execution tasks', () {
    test('nulls out error subtrees', () async {
      final b = ExecutableSchemaBuilder<Object?>();
      final schema = b.build(
        query: b.object<Object?>(
          'Type',
          fields: (t) => [
            t.field('sync', b.string.nullable).pure((_) => 'sync'),
            t
                .field('syncError', b.string.nullable)
                .pure(
                  (_) =>
                      throw const GraphQLException('Error getting syncError'),
                ),
            t
                .field('async', b.string.nullable)
                .resolve((_, args, context, info) => Future.value('async')),
            t
                .field('asyncReject', b.string.nullable)
                .resolve(
                  (_, args, context, info) => Future<String?>.error(
                    const GraphQLException('Error getting asyncReject'),
                  ),
                ),
            t.field('asyncError', b.string.nullable).resolve((
              _,
              args,
              context,
              info,
            ) async {
              await Future<void>.value();
              throw const GraphQLException('Error getting asyncError');
            }),
            t
                .field('asyncErrorWithExtensions', b.string.nullable)
                .resolve(
                  (_, args, context, info) => Future<String?>.error(
                    GraphQLException(
                      'Error getting asyncErrorWithExtensions',
                      extensions: JsonObject({'foo': const JsonString('bar')}),
                    ),
                  ),
                ),
          ],
        ),
      );

      final result = await port.json(schema, '''

      {
        sync
        syncError
        async
        asyncReject
        asyncError
        asyncErrorWithExtensions
      }
    ''');

      expect(
        result,
        equals({
          'data': {
            'sync': 'sync',
            'syncError': null,
            'async': 'async',
            'asyncReject': null,
            'asyncError': null,
            'asyncErrorWithExtensions': null,
          },
          'errors': [
            {
              'message': 'Error getting syncError',
              'locations': [
                {'line': 4, 'column': 9},
              ],
              'path': ['syncError'],
            },
            {
              'message': 'Error getting asyncReject',
              'locations': [
                {'line': 6, 'column': 9},
              ],
              'path': ['asyncReject'],
            },
            {
              'message': 'Error getting asyncError',
              'locations': [
                {'line': 7, 'column': 9},
              ],
              'path': ['asyncError'],
            },
            {
              'message': 'Error getting asyncErrorWithExtensions',
              'locations': [
                {'line': 8, 'column': 9},
              ],
              'path': ['asyncErrorWithExtensions'],
              'extensions': {'foo': 'bar'},
            },
          ],
        }),
      );
    });

    test('nulls error subtree for promise rejection #1071', () async {
      final b = ExecutableSchemaBuilder<Object?>();
      final food = b.object<Object?>(
        'Food',
        fields: (t) => [
          t.field('name', b.string.nullable).pure((_) => null),
        ],
      );
      final schema = b.build(
        query: b.object<Object?>(
          'Query',
          fields: (t) => [
            t
                .field('foods', b.list(food.nullable).nullable)
                .resolve(
                  (_, args, context, info) => Future<List<Object?>>.error(
                    const GraphQLException('Oops'),
                  ),
                ),
          ],
        ),
      );

      final result = await port.json(schema, '''

      query {
        foods {
          name
        }
      }
    ''');

      expect(
        result,
        equals({
          'data': {'foods': null},
          'errors': [
            {
              'locations': [
                {'column': 9, 'line': 3},
              ],
              'message': 'Oops',
              'path': ['foods'],
            },
          ],
        }),
      );
    });

    test('handles sync errors combined with rejections', () async {
      final b = ExecutableSchemaBuilder<Object?>();
      var isAsyncResolverFinished = false;
      final nonNullString = UncheckedRef(
        const NonNullType(NamedType(Name('String'))),
        b.string,
      );
      final schema = b.build(
        query: b.object<Object?>(
          'Query',
          fields: (t) => [
            t.field('syncNullError', nonNullString).pure((_) => null),
            t.field('asyncNullError', nonNullString).resolve((
              _,
              args,
              context,
              info,
            ) async {
              await Future<void>.value();
              await Future<void>.value();
              await Future<void>.value();
              isAsyncResolverFinished = true;
              return null;
            }),
          ],
        ),
      );

      // Order is important here, as the promise has to be created before the
      // synchronous error is thrown.
      final result = port.json(schema, '''

      {
        asyncNullError
        syncNullError
      }
    ''');

      expect(
        await result,
        equals({
          'data': null,
          'errors': [
            {
              'message':
                  'Cannot return null for non-nullable field '
                  'Query.syncNullError.',
              'locations': [
                {'line': 4, 'column': 9},
              ],
              'path': ['syncNullError'],
            },
            {
              'message':
                  'Cannot return null for non-nullable field '
                  'Query.asyncNullError.',
              'locations': [
                {'line': 3, 'column': 9},
              ],
              'path': ['asyncNullError'],
            },
          ],
        }),
      );
      // graphql-js answers before the started resolver is done and drops its
      // error; this executor waits for it, so no late error is lost.
      expect(isAsyncResolverFinished, isTrue);
    });

    test(
      'handles async bubbling errors combined with non-bubbling errors',
      () async {
        final b = ExecutableSchemaBuilder<Object?>();
        final nonNullString = UncheckedRef(
          const NonNullType(NamedType(Name('String'))),
          b.string,
        );
        final schema = b.build(
          query: b.object<Object?>(
            'Query',
            fields: (t) => [
              t.field('asyncNonNullError', nonNullString).resolve((
                _,
                args,
                context,
                info,
              ) async {
                await Future<void>.value();
                return null;
              }),
              t.field('asyncError', b.string.nullable).resolve((
                _,
                args,
                context,
                info,
              ) async {
                await Future<void>.value();
                throw const GraphQLException('Oops');
              }),
            ],
          ),
        );

        // Order is important here, as the nullable error should resolve
        // first.
        final result = await port.json(schema, '''

      {
        asyncError
        asyncNonNullError
      }
    ''');

        expect(
          result,
          equals({
            'data': null,
            'errors': [
              {
                'message': 'Oops',
                'locations': [
                  {'line': 3, 'column': 9},
                ],
                'path': ['asyncError'],
              },
              {
                'message':
                    'Cannot return null for non-nullable field '
                    'Query.asyncNonNullError.',
                'locations': [
                  {'line': 4, 'column': 9},
                ],
                'path': ['asyncNonNullError'],
              },
            ],
          }),
        );
      },
    );

    test('Full response path is included for non-nullable fields', () async {
      final b = ExecutableSchemaBuilder<Object?>();
      late final ObjectTypeDef<Object?> a;
      a = b.object<Object?>(
        'A',
        fields: (t) => [
          t.field('nullableA', a.nullable).pure((_) => const Object()),
          t.field('nonNullA', a).pure((_) => const Object()),
          t
              .field('throws', b.string)
              .pure((_) => throw const GraphQLException('Catch me if you can')),
        ],
      );
      final schema = b.build(
        query: b.object<Object?>(
          'query',
          fields: (t) => [
            t.field('nullableA', a.nullable).pure((_) => const Object()),
          ],
        ),
      );

      final result = await port.json(schema, '''

      query {
        nullableA {
          aliasedA: nullableA {
            nonNullA {
              anotherA: nonNullA {
                throws
              }
            }
          }
        }
      }
    ''');

      expect(
        result,
        equals({
          'data': {
            'nullableA': {'aliasedA': null},
          },
          'errors': [
            {
              'message': 'Catch me if you can',
              'locations': [
                {'line': 7, 'column': 17},
              ],
              'path': [
                'nullableA',
                'aliasedA',
                'nonNullA',
                'anotherA',
                'throws',
              ],
            },
          ],
        }),
      );
    });
  });
}
