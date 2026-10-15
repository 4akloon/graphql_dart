import 'dart:convert';

import 'package:test/test.dart';
import 'package:typed_graphql/typed_graphql.dart';
import 'package:typed_graphql_server/typed_graphql_server.dart';

import '../support/execution_port.dart';
import '../support/non_null_schema.dart';

// Ported from graphql-js src/execution/__tests__/nonnull-test.ts;
// mapping/execution.csv says which tests are adapted or skipped, and why.
void main() {
  const port = ExecutionPort();
  final schema = const NonNullSchema().build();
  const nullingData = NonNullData(isThrowing: false);
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

  String patch(String text) => text
      .replaceAll(RegExp(r'\bsync\b'), 'promise')
      .replaceAll(RegExp(r'\bsyncNonNull\b'), 'promiseNonNull');

  Future<Map<String, Object?>> executeQuery(String query, NonNullData data) =>
      port.json(schema, query, options: ExecutionOptions(rootValue: data));

  // graphql-js's executeSync: the first run must not wait; the second run,
  // with every sync leaf as a promise, must give the same response.
  Future<Map<String, Object?>> executeSyncAndAsync(
    String query,
    NonNullData data,
  ) async {
    final syncResult = port.payload<Object?>(
      schema,
      query,
      context: null,
      options: ExecutionOptions(rootValue: data, maskErrors: false),
    );
    expect(syncResult, isA<ResponsePayload>());
    final syncJson = port.withoutCodes(syncResult as ResponsePayload);
    final asyncResult = await executeQuery(patch(query), data);
    expect(asyncResult, equals(jsonDecode(patch(jsonEncode(syncJson)))));
    return syncJson;
  }

  group('Execute: handles non-nullable types', () {
    group('nulls a nullable field', () {
      const query = '''

      {
        sync
      }
    ''';

      test('that returns null', () async {
        final result = await executeSyncAndAsync(query, nullingData);
        expect(
          result,
          equals({
            'data': {'sync': null},
          }),
        );
      });

      test('that throws', () async {
        final result = await executeSyncAndAsync(query, throwingData);
        expect(
          result,
          equals({
            'data': {'sync': null},
            'errors': [
              error('sync', ['sync'], 3, 9),
            ],
          }),
        );
      });
    });

    group('nulls a returned object that contains a non-nullable field', () {
      const query = '''

      {
        syncNest {
          syncNonNull,
        }
      }
    ''';

      test('that returns null', () async {
        final result = await executeSyncAndAsync(query, nullingData);
        expect(
          result,
          equals({
            'data': {'syncNest': null},
            'errors': [
              error(
                'Cannot return null for non-nullable field '
                'DataType.syncNonNull.',
                ['syncNest', 'syncNonNull'],
                4,
                11,
              ),
            ],
          }),
        );
      });

      test('that throws', () async {
        final result = await executeSyncAndAsync(query, throwingData);
        expect(
          result,
          equals({
            'data': {'syncNest': null},
            'errors': [
              error('syncNonNull', ['syncNest', 'syncNonNull'], 4, 11),
            ],
          }),
        );
      });
    });

    group('nulls a complex tree of nullable fields, each', () {
      const query = '''

      {
        syncNest {
          sync
          promise
          syncNest { sync promise }
          promiseNest { sync promise }
        }
        promiseNest {
          sync
          promise
          syncNest { sync promise }
          promiseNest { sync promise }
        }
      }
    ''';
      const leaves = {'sync': null, 'promise': null};
      const nest = {
        'sync': null,
        'promise': null,
        'syncNest': leaves,
        'promiseNest': leaves,
      };
      const data = {'syncNest': nest, 'promiseNest': nest};

      test('that returns null', () async {
        final result = await executeQuery(query, nullingData);
        expect(result, equals({'data': data}));
      });

      test('that throws', () async {
        final result = await executeQuery(query, throwingData);
        expect(
          result,
          equals({
            'data': data,
            'errors': [
              // graphql-js lists these by completion time; this executor
              // lists them in document order.
              error('sync', ['syncNest', 'sync'], 4, 11),
              error('promise', ['syncNest', 'promise'], 5, 11),
              error('sync', ['syncNest', 'syncNest', 'sync'], 6, 22),
              error('promise', ['syncNest', 'syncNest', 'promise'], 6, 27),
              error('sync', ['syncNest', 'promiseNest', 'sync'], 7, 25),
              error('promise', ['syncNest', 'promiseNest', 'promise'], 7, 30),
              error('sync', ['promiseNest', 'sync'], 10, 11),
              error('promise', ['promiseNest', 'promise'], 11, 11),
              error('sync', ['promiseNest', 'syncNest', 'sync'], 12, 22),
              error('promise', ['promiseNest', 'syncNest', 'promise'], 12, 27),
              error('sync', ['promiseNest', 'promiseNest', 'sync'], 13, 25),
              error(
                'promise',
                ['promiseNest', 'promiseNest', 'promise'],
                13,
                30,
              ),
            ],
          }),
        );
      });
    });

    group('nulls the first nullable object after a field in a long chain of non-null fields', () {
      const query = '''

      {
        syncNest {
          syncNonNullNest {
            promiseNonNullNest {
              syncNonNullNest {
                promiseNonNullNest {
                  syncNonNull
                }
              }
            }
          }
        }
        promiseNest {
          syncNonNullNest {
            promiseNonNullNest {
              syncNonNullNest {
                promiseNonNullNest {
                  syncNonNull
                }
              }
            }
          }
        }
        anotherNest: syncNest {
          syncNonNullNest {
            promiseNonNullNest {
              syncNonNullNest {
                promiseNonNullNest {
                  promiseNonNull
                }
              }
            }
          }
        }
        anotherPromiseNest: promiseNest {
          syncNonNullNest {
            promiseNonNullNest {
              syncNonNullNest {
                promiseNonNullNest {
                  promiseNonNull
                }
              }
            }
          }
        }
      }
    ''';
      const data = {
        'syncNest': null,
        'promiseNest': null,
        'anotherNest': null,
        'anotherPromiseNest': null,
      };

      List<Object> chain(String root, String leaf) => [
        root,
        'syncNonNullNest',
        'promiseNonNullNest',
        'syncNonNullNest',
        'promiseNonNullNest',
        leaf,
      ];

      test('that returns null', () async {
        final result = await executeQuery(query, nullingData);
        expect(
          result,
          equals({
            'data': data,
            'errors': [
              error(
                'Cannot return null for non-nullable field '
                'DataType.syncNonNull.',
                chain('syncNest', 'syncNonNull'),
                8,
                19,
              ),
              error(
                'Cannot return null for non-nullable field '
                'DataType.syncNonNull.',
                chain('promiseNest', 'syncNonNull'),
                19,
                19,
              ),
              error(
                'Cannot return null for non-nullable field '
                'DataType.promiseNonNull.',
                chain('anotherNest', 'promiseNonNull'),
                30,
                19,
              ),
              error(
                'Cannot return null for non-nullable field '
                'DataType.promiseNonNull.',
                chain('anotherPromiseNest', 'promiseNonNull'),
                41,
                19,
              ),
            ],
          }),
        );
      });

      test('that throws', () async {
        final result = await executeQuery(query, throwingData);
        expect(
          result,
          equals({
            'data': data,
            'errors': [
              error('syncNonNull', chain('syncNest', 'syncNonNull'), 8, 19),
              error('syncNonNull', chain('promiseNest', 'syncNonNull'), 19, 19),
              error(
                'promiseNonNull',
                chain('anotherNest', 'promiseNonNull'),
                30,
                19,
              ),
              error(
                'promiseNonNull',
                chain('anotherPromiseNest', 'promiseNonNull'),
                41,
                19,
              ),
            ],
          }),
        );
      });
    });

    group('nulls the top level if non-nullable field', () {
      const query = '''

      {
        syncNonNull
      }
    ''';

      test('that returns null', () async {
        final result = await executeSyncAndAsync(query, nullingData);
        expect(
          result,
          equals({
            'data': null,
            'errors': [
              error(
                'Cannot return null for non-nullable field '
                'DataType.syncNonNull.',
                ['syncNonNull'],
                3,
                9,
              ),
            ],
          }),
        );
      });

      test('that throws', () async {
        final result = await executeSyncAndAsync(query, throwingData);
        expect(
          result,
          equals({
            'data': null,
            'errors': [
              error('syncNonNull', ['syncNonNull'], 3, 9),
            ],
          }),
        );
      });
    });
  });
}
