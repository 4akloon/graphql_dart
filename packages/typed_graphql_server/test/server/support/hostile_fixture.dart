import 'package:typed_graphql/typed_graphql.dart';
import 'package:typed_graphql_server/typed_graphql_server.dart';

import 'server_fixture.dart';

/// The text a hostile test throws, searched for in responses.
const String hostileSecret = 'secret-token-4711';

/// A schema whose resolvers and context factory count their calls, to prove
/// that a refusal comes before any work, and the servers over it.
final class HostileFixture {
  HostileFixture() {
    final b = ExecutableSchemaBuilder<Ctx>();
    final first = Arg('first', b.int.nullable);
    final item = b.object<Object?>(
      'Item',
      fields: (t) => [t.field('name', b.string).pure((_) => 'item')],
    );
    late final ObjectTypeDef<Object?> query;
    query = b.object<Object?>(
      'Query',
      fields: (t) => [
        t.field('hello', b.string).resolve((parent, args, context, info) {
          resolved++;
          return 'world';
        }),
        t.field('self', query).resolve((parent, args, context, info) {
          resolved++;
          return const Object();
        }),
        t.field('boom', b.string.nullable).resolve((
          parent,
          args,
          context,
          info,
        ) {
          resolved++;
          throw StateError(hostileSecret);
        }),
        t
            .field('items', b.list(item).nullable, args: [first])
            .withDirectives([
              AppliedDirective(
                'listSize',
                arguments: [
                  Argument(
                    const Name('slicingArguments'),
                    ListValue([const StringValue('first')]),
                  ),
                ],
              ),
            ])
            .resolve((parent, args, context, info) {
              resolved++;
              return const <Object>[];
            }),
      ],
    );
    final mutation = b.object<Object?>(
      'Mutation',
      fields: (t) => [t.field('bump', b.string).pure((_) => 'bumped')],
    );
    schema = b.build(
      query: query,
      mutation: mutation,
      options: BuildOptions<Ctx>(
        directives: [const BuiltIns().listSize, const BuiltIns().cost],
      ),
    );
  }

  late final ExecutableSchema<Ctx> schema;

  /// The contexts built so far.
  int built = 0;

  /// The resolvers called so far.
  int resolved = 0;

  /// A server over the schema whose context factory counts [built] unless
  /// [contextFactory] is given.
  GraphQLServer<Ctx> server({
    ServerProfile profile = ServerProfile.production,
    ContextFactory<Ctx>? contextFactory,
    List<ValidationRule> validationRules = DocumentValidator.recommendedRules,
    ErrorHook? onError,
    int documentCacheSize = 1000,
    List<ServerExtension<Ctx>> extensions = const [],
  }) => GraphQLServer<Ctx>(
    schema: schema,
    contextFactory:
        contextFactory ??
        (_) {
          built++;
          return const Ctx('hostile');
        },
    profile: profile,
    validationRules: validationRules,
    onError: onError,
    documentCacheSize: documentCacheSize,
    extensions: extensions,
  );

  /// `{ a0: hello a1: hello ... }` with [count] aliases.
  String aliases(int count) =>
      '{ ${[for (var index = 0; index < count; index++) 'a$index: hello'].join(' ')} }';

  /// `{ hello @skip(if: false) ... }` with [count] directives.
  String directives(int count) =>
      '{ ${List.filled(count, 'hello @skip(if: false)').join(' ')} }';

  /// A document of [count] fragments, each spreading the next one twice; the
  /// last selects `hello`. Expanded naively it has 2^count spreads.
  String fanOut(int count) {
    final fragments = [
      for (var index = 0; index < count - 1; index++)
        'fragment f$index on Query { ...f${index + 1} ...f${index + 1} }',
      'fragment f${count - 1} on Query { hello }',
    ];
    return '{ ...f0 } ${fragments.join(' ')}';
  }
}
