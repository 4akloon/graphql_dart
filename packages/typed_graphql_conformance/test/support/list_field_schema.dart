import 'dart:async';

import 'package:typed_graphql/typed_graphql.dart';
import 'package:typed_graphql_server/typed_graphql_server.dart';

import 'unchecked_ref.dart';

/// graphql-js's `buildSchema('type Query { listField: <as> }')` of the list
/// tests: one field whose GraphQL type is [type] and whose Dart value is
/// whatever [read] returns, since a typed resolver could not return the
/// values those tests use.
final class ListFieldSchema {
  /// Creates the builder of the schema; it keeps no state.
  const ListFieldSchema();

  /// The schema with `listField` of type [type] over the scalar named
  /// [scalarName] (`Int` or `String`).
  ExecutableSchema<Object?> build(
    TypeRef type,
    FutureOr<Object?> Function() read, {
    String scalarName = 'Int',
  }) {
    final b = ExecutableSchemaBuilder<Object?>();
    final scalar = scalarName == 'Int' ? b.int : b.string;
    return b.build(
      query: b.object<Object?>(
        'Query',
        fields: (t) => [
          t
              .field('listField', UncheckedRef(type, scalar))
              .resolve((_, args, context, info) => read()),
        ],
      ),
    );
  }
}
