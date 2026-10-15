import 'dart:async';

import 'package:typed_graphql/typed_graphql.dart';
import 'package:typed_graphql_server/typed_graphql_server.dart';

import 'unchecked_ref.dart';

/// graphql-js's `throwingData` and `nullingData` of `nonnull-test.ts`: an
/// object whose fields return `null` or throw, each one sync or in a
/// future, and whose nested fields return the object itself.
final class NonNullData {
  /// Data whose leaf fields throw when [isThrowing], else return `null`.
  ///
  /// [syncNonNullOverride] and [promiseOverride] replace the answers of the
  /// `syncNonNull` and `promise` leaves.
  const NonNullData({
    required this.isThrowing,
    this.syncNonNullOverride,
    this.promiseOverride,
  });

  /// Whether a leaf throws instead of returning `null`.
  final bool isThrowing;

  /// The answer of `syncNonNull`, when the test controls it.
  final Future<Object?> Function()? syncNonNullOverride;

  /// The answer of `promise`, when the test controls it.
  final Future<String?> Function()? promiseOverride;

  /// The `sync` field.
  String? sync() => isThrowing ? throw const GraphQLException('sync') : null;

  /// The `syncNonNull` field.
  FutureOr<Object?> syncNonNull() {
    if (syncNonNullOverride case final override?) {
      return override();
    }
    return isThrowing ? throw const GraphQLException('syncNonNull') : null;
  }

  /// The `promise` field.
  Future<String?> promise() {
    if (promiseOverride case final override?) {
      return override();
    }
    return isThrowing
        ? Future<String?>.error(const GraphQLException('promise'))
        : Future<String?>.value();
  }

  /// The `promiseNonNull` field.
  Future<Object?> promiseNonNull() => isThrowing
      ? Future<Object?>.error(const GraphQLException('promiseNonNull'))
      : Future<Object?>.value();

  /// The `promiseNest` field.
  Future<NonNullData> asFuture() => Future.value(this);
}

/// The schema of `nonnull-test.ts`: `DataType` is the query type.
final class NonNullSchema {
  /// Creates the builder of the schema; it keeps no state.
  const NonNullSchema();

  /// The schema.
  ExecutableSchema<Object?> build() {
    final b = ExecutableSchemaBuilder<Object?>();
    final nonNullString = UncheckedRef(
      const NonNullType(NamedType(Name('String'))),
      b.string,
    );
    // The fields refer to their own type; the thunk runs after the
    // assignment.
    late final ObjectTypeDef<NonNullData> dataType;
    dataType = b.object<NonNullData>(
      'DataType',
      fields: (t) => [
        t.field('sync', b.string.nullable).pure((data) => data.sync()),
        t
            .field('syncNonNull', nonNullString)
            .resolve((data, args, context, info) => data.syncNonNull()),
        t
            .field('promise', b.string.nullable)
            .resolve((data, args, context, info) => data.promise()),
        t
            .field('promiseNonNull', nonNullString)
            .resolve((data, args, context, info) => data.promiseNonNull()),
        t.field('syncNest', dataType.nullable).pure((data) => data),
        t.field('syncNonNullNest', dataType).pure((data) => data),
        t
            .field('promiseNest', dataType.nullable)
            .resolve((data, args, context, info) => data.asFuture()),
        t
            .field('promiseNonNullNest', dataType)
            .resolve((data, args, context, info) => data.asFuture()),
      ],
    );
    return b.build(query: dataType);
  }
}
