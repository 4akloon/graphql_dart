import 'dart:async';

import 'package:typed_graphql_server/typed_graphql_server.dart';

/// A small executable schema and the server over it, for the adapter tests.
final class ShelfFixture {
  ShelfFixture() {
    final b = ExecutableSchemaBuilder<Object?>();
    final query = b.object<Object?>(
      'Query',
      fields: (t) => [t.field('hello', b.string).pure((_) => 'world')],
    );
    final mutation = b.object<Object?>(
      'Mutation',
      fields: (t) => [t.field('bump', b.string).pure((_) => 'bumped')],
    );
    final subscription = b.object<Object?>(
      'Subscription',
      fields: (t) => [
        t
            .field('ticks', b.string)
            .subscribeWith<int>(
              (parent, args, context, info) => Stream.fromIterable([1, 2]),
              (event, args, context, info) => 'tick $event',
            ),
      ],
    );
    schema = b.build(
      query: query,
      mutation: mutation,
      subscription: subscription,
    );
  }

  // Set by the constructor body, before anything reads it.
  late final ExecutableSchema<Object?> schema;

  GraphQLServer<Object?> server({
    ServerProfile profile = ServerProfile.development,
  }) => GraphQLServer<Object?>(
    schema: schema,
    contextFactory: (_) => null,
    profile: profile,
  );
}
