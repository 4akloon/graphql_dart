import 'dart:async';

import 'package:typed_graphql/typed_graphql.dart';
import 'package:typed_graphql_server/typed_graphql_server.dart';

enum Sorting { asc, desc }

sealed class Animal {
  const Animal();
}

final class Dog extends Animal {
  const Dog();
}

final class Cat extends Animal {
  const Cat();
}

final class Person {
  const Person();
}

/// A schema whose root fields keep the `FieldInfo` they are called with, so
/// a test reads the look-ahead of the field it ran.
final class LookAheadFixture {
  LookAheadFixture() {
    final b = ExecutableSchemaBuilder<Object?>();
    final sorting = b.enumType<Sorting>('Sorting', Sorting.values);
    final comment = b.object<Object?>(
      'Comment',
      fields: (t) => [t.field('body', b.string).pure((_) => 'b')],
    );
    final post = b.object<Object?>(
      'Post',
      fields: (t) => [
        t.field('title', b.string).pure((_) => 't'),
        t.field('comments', b.list(comment)).pure((_) => const []),
      ],
    );
    late final ObjectTypeDef<Person> person;
    person = b.object<Person>(
      'User',
      fields: (t) => [
        t.field('name', b.string).pure((_) => 'n'),
        t
            .field(
              'posts',
              b.list(post),
              args: [
                Arg('first', b.int.nullable),
                Arg('order', sorting.nullable),
              ],
            )
            .resolve((parent, args, context, info) => const []),
        t.field('friend', person.nullable).pure((_) => null),
      ],
    );
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
    late final ObjectTypeDef<Object?> deep;
    deep = b.object<Object?>(
      'Deep',
      fields: (t) => [
        t.field('deep', deep.nullable).pure((_) => null),
        t.field('leaf', b.string).pure((_) => 'l'),
      ],
    );
    final query = b.object<Object?>(
      'Query',
      fields: (t) => [
        t
            .field(
              'user',
              person.nullable,
              args: [
                Arg('id', b.int.nullable),
                Arg('tags', b.inputList(b.string).nullable),
              ],
            )
            .resolve(
              (parent, args, context, info) =>
                  _keep('user', info, const Person()),
            ),
        t
            .field('pet', pet)
            .resolve(
              (parent, args, context, info) => _keep('pet', info, const Dog()),
            ),
        t
            .field('found', found)
            .resolve(
              (parent, args, context, info) =>
                  _keep('found', info, const Cat()),
            ),
        t
            .field('deep', deep.nullable)
            .resolve(
              (parent, args, context, info) => _keep('deep', info, 'deep'),
            ),
        t.field('plain', b.string).resolve((p, a, c, info) {
          _infos['plain'] = info;
          return 'p';
        }),
      ],
    );
    built = b.build(query: query);
  }

  late final ExecutableSchema<Object?> built;
  final Map<String, FieldInfo> _infos = {};

  T _keep<T>(String field, FieldInfo info, T value) {
    _infos[field] = info;
    return value;
  }

  Document parse(String text) => const Parser(
    options: ParserOptions(maxTokens: null, maxDepth: null),
  ).parse(Source(text)).requireDocument();

  /// Runs [text] and returns the `FieldInfo` of the root field [field].
  Future<FieldInfo> infoOf(
    String field,
    String text, {
    JsonObject? variables,
  }) async {
    _infos.clear();
    final payload = await built.execute(
      ValidDocument.assumeValid(built.schema, parse(text)),
      context: null,
      variables: variables,
    );
    final info = _infos[field];
    if (info == null) {
      throw StateError('"$field" did not run: ${payload.toJson()}');
    }
    return info;
  }

  /// The selection under the root field [field] of [text].
  Future<FieldSelection> selection(
    String field,
    String text, {
    JsonObject? variables,
  }) async => (await infoOf(field, text, variables: variables)).selection;
}
