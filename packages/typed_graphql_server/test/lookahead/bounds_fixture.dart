import 'dart:async';

import 'package:typed_graphql/typed_graphql.dart';
import 'package:typed_graphql_server/typed_graphql_server.dart';

sealed class Link {
  const Link();
}

final class LinkA extends Link {
  const LinkA();
}

final class LinkB extends Link {
  const LinkB();
}

final class LinkC extends Link {
  const LinkC();
}

final class LinkD extends Link {
  const LinkD();
}

final class LinkE extends Link {
  const LinkE();
}

final class Apple {
  const Apple();
}

final class Pear {
  const Pear();
}

/// A schema built to make look-ahead walks explode: an interface with five
/// implementations that points at itself, a type whose `next` takes an
/// argument, and a union whose members give different fields one alias. The
/// root fields run [onCall] with their `FieldInfo`.
final class BoundsFixture {
  BoundsFixture() {
    final b = ExecutableSchemaBuilder<Object?>();
    late final InterfaceTypeDef<Link> linked;
    linked = b.interface<Link>(
      'Linked',
      fields: (t) => [
        t.field('parent', linked).declareOnly(),
        t.field('id', b.int).declareOnly(),
      ],
    );
    ObjectTypeDef<T> implementation<T extends Link>(String name, T value) =>
        b.object<T>(
          name,
          interfaces: [linked],
          fields: (t) => [
            t.field('parent', linked).pure((_) => value),
            t.field('id', b.int).pure((_) => 1),
          ],
        );
    implementation('LinkA', const LinkA());
    implementation('LinkB', const LinkB());
    implementation('LinkC', const LinkC());
    implementation('LinkD', const LinkD());
    implementation('LinkE', const LinkE());
    late final ObjectTypeDef<Object?> chain;
    chain = b.object<Object?>(
      'Chain',
      fields: (t) => [
        t.field('id', b.int).pure((_) => 1),
        t
            .field('next', chain.nullable, args: [Arg('i', b.int.nullable)])
            .resolve((parent, args, context, info) => null),
      ],
    );
    final apple = b.object<Apple>(
      'Apple',
      fields: (t) => [t.field('weight', b.int).pure((_) => 1)],
    );
    final pear = b.object<Pear>(
      'Pear',
      fields: (t) => [t.field('length', b.int).pure((_) => 2)],
    );
    final fruit = b.union<Object>('Fruit', members: [apple, pear]);
    final query = b.object<Object?>(
      'Query',
      fields: (t) => [
        t
            .field('node', linked)
            .resolve((p, a, c, info) => _call(info, const LinkA())),
        t
            .field('chain', chain.nullable)
            .resolve((p, a, c, info) => _call(info, const Object())),
        t
            .field('fruit', fruit)
            .resolve((p, a, c, info) => _call(info, const Apple())),
      ],
    );
    built = b.build(query: query);
  }

  late final ExecutableSchema<Object?> built;

  /// What the root fields do with their `FieldInfo` before they answer.
  void Function(FieldInfo info) onCall = (_) {};

  T _call<T>(FieldInfo info, T value) {
    onCall(info);
    return value;
  }

  /// Runs [text] and returns the payload.
  FutureOr<ResponsePayload> run(
    String text, {
    ExecutionOptions options = const ExecutionOptions(),
  }) {
    final document = const Parser(
      options: ParserOptions(maxTokens: null, maxDepth: null),
    ).parse(Source(text)).requireDocument();
    return built.execute(
      ValidDocument.assumeValid(built.schema, document),
      context: null,
      options: options,
    );
  }

  /// The selection under the root field [field] of [text].
  Future<FieldSelection> selection(String field, String text) async {
    FieldSelection? found;
    onCall = (info) => found = info.selection;
    final payload = await run(text);
    return found ??
        (throw StateError('"$field" did not run: ${payload.toJson()}'));
  }
}
