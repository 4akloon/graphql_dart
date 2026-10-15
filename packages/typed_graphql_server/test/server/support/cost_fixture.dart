import 'package:typed_graphql/typed_graphql.dart';
import 'package:typed_graphql_server/typed_graphql_server.dart';

import 'server_fixture.dart';

/// A schema with `items(first: Int): [Item]` sized by `@listSize`, and the
/// servers to test the cost limit on it.
///
/// An `Item` weighs 1 and a scalar 0, so `{ items(first: n) { name } }` has a
/// field cost of 1 and a type cost of `n + 1`.
final class CostFixture {
  CostFixture() {
    final b = ExecutableSchemaBuilder<Ctx>();
    final first = Arg('first', b.int.nullable);
    final item = b.object<Object?>(
      'Item',
      fields: (t) => [t.field('name', b.string).pure((_) => 'item')],
    );
    final query = b.object<Object?>(
      'Query',
      fields: (t) => [
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
            .resolve(
              (parent, args, context, info) => const [Object(), Object()],
            ),
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

  // Late: the constructor body builds it, before any reader can run.
  late final ExecutableSchema<Ctx> schema;

  /// A server limiting the cost to [maxCost]; null is no limit.
  GraphQLServer<Ctx> server(
    double? maxCost,
    ContextFactory<Ctx> factory, {
    List<ValidationRule> validationRules = DocumentValidator.recommendedRules,
  }) => GraphQLServer<Ctx>(
    schema: schema,
    contextFactory: factory,
    profile: ServerProfile.development.withLimits(
      ServerLimits(maxCost: maxCost),
    ),
    validationRules: validationRules,
  );
}
