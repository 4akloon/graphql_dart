import 'dart:async';

import 'package:test/test.dart';
import 'package:typed_graphql_server/typed_graphql_server.dart';

import '../support/execution_port.dart';
import '../support/non_null_schema.dart';

// Ported from graphql-js src/execution/__tests__/nonnull-test.ts;
// mapping/execution.csv says which tests are adapted or skipped, and why.
void main() {
  const port = ExecutionPort();
  final schema = const NonNullSchema().build();
  const throwingData = NonNullData(isThrowing: true);

  Map<String, Object?> error(
    String message,
    List<Object> path,
    int line,
    int column,
  ) => {
    'message': message,
    'path': path,
    'locations': [
      {'line': line, 'column': column},
    ],
  };

  Future<Map<String, Object?>> executeQuery(
    String query,
    NonNullData data,
  ) => port.json(schema, query, options: ExecutionOptions(rootValue: data));

  group('Execute: handles non-nullable types', () {
    group('Handles multiple errors for a single response position', () {
      test(
        'nullable and non-nullable root fields throw nested errors',
        () async {
          final result = await executeQuery('''

        {
          promiseNonNullNest {
            syncNonNull
          }
          promiseNest {
            syncNonNull
          }
        }
      ''', throwingData);

          expect(
            result,
            equals({
              'data': null,
              'errors': [
                error(
                  'syncNonNull',
                  ['promiseNonNullNest', 'syncNonNull'],
                  4,
                  13,
                ),
                error('syncNonNull', ['promiseNest', 'syncNonNull'], 7, 13),
              ],
            }),
          );
        },
      );

      test(
        'a nullable root field throws a slower nested error after a non-nullable root field throws a nested error',
        () async {
          final result = await executeQuery('''

        {
          promiseNonNullNest {
            syncNonNull
          }
          promiseNest {
            promiseNonNull
          }
        }
      ''', throwingData);

          expect(
            result,
            equals({
              'data': null,
              'errors': [
                error(
                  'syncNonNull',
                  ['promiseNonNullNest', 'syncNonNull'],
                  4,
                  13,
                ),
                error(
                  'promiseNonNull',
                  ['promiseNest', 'promiseNonNull'],
                  7,
                  13,
                ),
              ],
            }),
          );
        },
      );

      test(
        'nullable and non-nullable nested fields throw nested errors',
        () async {
          final result = await executeQuery('''

        {
          syncNest {
            promiseNonNullNest {
              syncNonNull
            }
            promiseNest {
              syncNonNull
            }
          }
        }
      ''', throwingData);

          expect(
            result,
            equals({
              'data': {'syncNest': null},
              'errors': [
                error(
                  'syncNonNull',
                  ['syncNest', 'promiseNonNullNest', 'syncNonNull'],
                  5,
                  15,
                ),
                error(
                  'syncNonNull',
                  ['syncNest', 'promiseNest', 'syncNonNull'],
                  8,
                  15,
                ),
              ],
            }),
          );
        },
      );

      test(
        'a nullable nested field throws a slower nested error after a non-nullable nested field throws a nested error',
        () async {
          final result = await executeQuery('''

        {
          syncNest {
            promiseNonNullNest {
              syncNonNull
            }
            promiseNest {
              promiseNest {
                promiseNest {
                  promiseNonNull
                }
              }
            }
          }
        }
      ''', throwingData);

          expect(
            result,
            equals({
              'data': {'syncNest': null},
              'errors': [
                error(
                  'syncNonNull',
                  ['syncNest', 'promiseNonNullNest', 'syncNonNull'],
                  5,
                  15,
                ),
                error(
                  'promiseNonNull',
                  [
                    'syncNest',
                    'promiseNest',
                    'promiseNest',
                    'promiseNest',
                    'promiseNonNull',
                  ],
                  10,
                  19,
                ),
              ],
            }),
          );
        },
      );

      test('suppresses a later error after a parent has been nulled', () async {
        final nonNullDeferred = Completer<Object?>();
        final promiseDeferred = Completer<String?>();
        final data = NonNullData(
          isThrowing: false,
          syncNonNullOverride: () => nonNullDeferred.future,
          promiseOverride: () => promiseDeferred.future,
        );

        final resultPromise = executeQuery('''

        {
          syncNest {
            syncNonNull
            promise
          }
        }
      ''', data);

        nonNullDeferred.completeError(const GraphQLException('syncNonNull'));

        // Give the first error a chance to null out the parent position.
        await Future<void>.delayed(Duration.zero);
        await Future<void>.delayed(Duration.zero);
        await Future<void>.delayed(Duration.zero);

        promiseDeferred.completeError(const GraphQLException('promise'));

        expect(
          await resultPromise,
          equals({
            'data': {'syncNest': null},
            'errors': [
              error('syncNonNull', ['syncNest', 'syncNonNull'], 4, 13),
              error('promise', ['syncNest', 'promise'], 5, 13),
            ],
          }),
        );
      });
    });
  });
}
