import 'dart:async';

import 'package:test/test.dart';
import 'package:typed_graphql/typed_graphql.dart';
import 'package:typed_graphql_server/typed_graphql_server.dart';

import '../support/execution_port.dart';
import '../support/list_field_schema.dart';

// Ported from graphql-js src/execution/__tests__/lists-test.ts;
// mapping/execution.csv says which tests are adapted or skipped, and why.
void main() {
  const port = ExecutionPort();
  const schemas = ListFieldSchema();
  const int_ = NamedType(Name('Int'));
  final types = {
    '[Int]': const ListType(int_),
    '[Int]!': const NonNullType(ListType(int_)),
    '[Int!]': const ListType(NonNullType(int_)),
    '[Int!]!': const NonNullType(ListType(NonNullType(int_))),
  };

  Map<String, Object?> error(String message, List<Object> path) => {
    'message': message,
    'locations': [
      {'line': 1, 'column': 3},
    ],
    'path': path,
  };

  Future<Map<String, Object?>> executeQuery(
    TypeRef type,
    FutureOr<Object?> Function() read,
  ) => port.json(schemas.build(type, read), '{ listField }');

  // The value as the resolver gives it, then in a future: both must give
  // the same response (graphql-js also wraps every item in a promise, which
  // a typed list cannot hold). A GraphQLException stands for the Error.
  Future<Map<String, Object?>> complete(Object? listField, String as) async {
    final type = types[as]!;
    final result = await executeQuery(type, () {
      if (listField is GraphQLException) {
        throw listField;
      }
      return listField;
    });
    final fromFuture = await executeQuery(
      type,
      () => listField is GraphQLException
          ? Future<Object?>.error(listField)
          : Future<Object?>.value(listField),
    );
    expect(fromFuture, equals(result));
    return result;
  }

  group('Execute: Handles list nullability', () {
    test('Contains values', () async {
      const listField = [1, 2];

      for (final as in types.keys) {
        expect(
          await complete(listField, as),
          equals({
            'data': {'listField': listField},
          }),
          reason: as,
        );
      }
    });

    test('Contains null', () async {
      const listField = [1, null, 2];
      final errors = [
        error('Cannot return null for non-nullable field Query.listField.', [
          'listField',
          1,
        ]),
      ];

      expect(
        await complete(listField, '[Int]'),
        equals({
          'data': {'listField': listField},
        }),
      );
      expect(
        await complete(listField, '[Int]!'),
        equals({
          'data': {'listField': listField},
        }),
      );
      expect(
        await complete(listField, '[Int!]'),
        equals({
          'data': {'listField': null},
          'errors': errors,
        }),
      );
      expect(
        await complete(listField, '[Int!]!'),
        equals({'data': null, 'errors': errors}),
      );
    });

    test('Returns null', () async {
      const Object? listField = null;
      final errors = [
        error('Cannot return null for non-nullable field Query.listField.', [
          'listField',
        ]),
      ];

      expect(
        await complete(listField, '[Int]'),
        equals({
          'data': {'listField': null},
        }),
      );
      expect(
        await complete(listField, '[Int]!'),
        equals({'data': null, 'errors': errors}),
      );
      expect(
        await complete(listField, '[Int!]'),
        equals({
          'data': {'listField': null},
        }),
      );
      expect(
        await complete(listField, '[Int!]!'),
        equals({'data': null, 'errors': errors}),
      );
    });

    test('Results in error', () async {
      const listField = GraphQLException('bad');
      final errors = [
        error('bad', ['listField']),
      ];

      expect(
        await complete(listField, '[Int]'),
        equals({
          'data': {'listField': null},
          'errors': errors,
        }),
      );
      expect(
        await complete(listField, '[Int]!'),
        equals({'data': null, 'errors': errors}),
      );
      expect(
        await complete(listField, '[Int!]'),
        equals({
          'data': {'listField': null},
          'errors': errors,
        }),
      );
      expect(
        await complete(listField, '[Int!]!'),
        equals({'data': null, 'errors': errors}),
      );
    });
  });
}
