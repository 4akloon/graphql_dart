import 'package:typed_graphql/typed_graphql.dart';
import 'package:typed_graphql_server/typed_graphql_server.dart';

/// The schema the client's hand-written test operations run against.
final class TestSchema {
  /// Creates the description.
  const TestSchema();

  /// The code of the error the `broken` field fails with.
  static const String brokenCode = 'BROKEN';

  /// Builds the schema: `hello`, `greet(name:)`, a `broken` field that
  /// fails, and the mutation `rename(name:)`.
  ExecutableSchema<Object?> build() {
    final b = ExecutableSchemaBuilder<Object?>();
    final name = Arg('name', b.string);
    final query = b.object<Object?>(
      'Query',
      fields: (t) => [
        t.field('hello', b.string).pure((_) => 'hello'),
        t
            .field('greet', b.string, args: [name])
            .resolve(
              (parent, args, context, info) => 'Hello, ${args.get(name)}!',
            ),
        t
            .field('broken', b.string.nullable)
            .resolve(
              (parent, args, context, info) => throw GraphQLException(
                'It is broken.',
                extensions: JsonObject({'code': const JsonString(brokenCode)}),
              ),
            ),
      ],
    );
    final mutation = b.object<Object?>(
      'Mutation',
      fields: (t) => [
        t
            .field('rename', b.string, args: [name])
            .resolve((parent, args, context, info) => args.get(name)),
      ],
    );
    return b.build(query: query, mutation: mutation);
  }
}
