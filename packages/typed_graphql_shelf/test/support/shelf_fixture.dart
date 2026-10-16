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
    schema = b.build(query: query, mutation: mutation);
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
