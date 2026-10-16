import 'package:typed_graphql/typed_graphql.dart';
import 'package:typed_graphql_server/typed_graphql_server.dart';

import 'tick_source.dart';

/// The schema the client's hand-written test operations run against.
final class TestSchema {
  /// Creates the description.
  const TestSchema();

  /// The code of the error the `broken` field fails with.
  static const String brokenCode = 'BROKEN';

  /// Builds the schema: `hello`, `greet(name:)`, a `broken` field that
  /// fails, the mutation `rename(name:)` and the subscription `ticks`, whose
  /// events come from [ticks] (a fresh [TickSource] when null).
  ExecutableSchema<Object?> build({TickSource? ticks}) {
    final source = ticks ?? TickSource();
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
    final subscription = b.object<Object?>(
      'Subscription',
      fields: (t) => [
        t
            .field('ticks', b.int)
            .subscribe((parent, args, context, info) => source.stream()),
      ],
    );
    return b.build(
      query: query,
      mutation: mutation,
      subscription: subscription,
    );
  }
}
