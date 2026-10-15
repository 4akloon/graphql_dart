import 'package:typed_graphql/typed_graphql.dart';
import 'package:typed_graphql_server/src/coercion/coercion_environment.dart';
import 'package:typed_graphql_server/src/plan/operation_plan.dart';
import 'package:typed_graphql_server/src/plan/operation_planner.dart';
import 'package:typed_graphql_server/src/plan/plan_cache.dart';
import 'package:typed_graphql_server/src/plan/plan_node.dart';
import 'package:typed_graphql_server/src/plan/plan_result.dart';
import 'package:typed_graphql_server/typed_graphql_server.dart';

sealed class Animal {
  const Animal();
}

final class Cat extends Animal {
  const Cat();
}

final class Dog extends Animal {
  const Dog();
}

/// A schema with an interface, a union and arguments, and parsing helpers.
final class PlanFixture {
  PlanFixture({int planCacheSize = 1000}) {
    final b = ExecutableSchemaBuilder<Object?>();
    final pet = b.interface<Animal>(
      'Pet',
      fields: (t) => [t.field('name', b.string).declareOnly()],
    );
    final dog = b.object<Dog>(
      'Dog',
      interfaces: [pet],
      fields: (t) => [
        t.field('name', b.string).pure((_) => 'rex'),
        t.field('barks', b.boolean).pure((_) => true),
      ],
    );
    final cat = b.object<Cat>(
      'Cat',
      interfaces: [pet],
      fields: (t) => [
        t.field('name', b.string).pure((_) => 'tom'),
        t.field('meows', b.boolean).pure((_) => true),
      ],
    );
    final found = b.union<Animal>('Found', members: [dog, cat]);
    final query = b.object<Object?>(
      'Query',
      fields: (t) => [
        for (final name in ['a', 'b', 'c'])
          t.field(name, b.string).pure((_) => name),
        t.field('pet', pet).pure((_) => const Dog()),
        t.field('found', found).pure((_) => const Cat()),
        t
            .field('user', b.string, args: [Arg('id', b.int)])
            .resolve((parent, args, context, info) => 'u'),
        t
            .field('tagged', b.string, args: [Arg('tag', b.string)])
            .resolve((parent, args, context, info) => 't'),
      ],
    );
    final built = b.build(
      query: query,
      options: BuildOptions(
        includesDeferAndStream: true,
        planCacheSize: planCacheSize,
      ),
    );
    environment = CoercionEnvironment(built.schema.schema, built.bindings);
    cache = PlanCache(planCacheSize);
    planner = OperationPlanner(environment, cache);
  }

  late final CoercionEnvironment environment;
  late final PlanCache cache;
  late final OperationPlanner planner;

  Document parse(String text) => const Parser(
    options: ParserOptions(maxTokens: null, maxDepth: null),
  ).parse(Source(text)).requireDocument();

  PlanResult result(Document document, [String? name]) =>
      planner.plan(document, name);

  OperationPlan plan(String text, [String? name]) =>
      switch (result(parse(text), name)) {
        PlanReady(:final plan) => plan,
        PlanRejected(:final error) => throw StateError(error.message),
      };

  /// The root node of [text] with the given boolean variables.
  PlanNode root(String text, [Map<String, Object?> variables = const {}]) {
    final operationPlan = plan(text);
    return operationPlan.rootFor(operationPlan.keyFor(variables));
  }

  /// The response keys of [node], in order.
  List<String> keys(PlanNode node) => [
    for (final field in node.fields) field.responseKey,
  ];

  ObjectType objectType(String name) =>
      environment.schema.typeNamed(name)! as ObjectType;
}
