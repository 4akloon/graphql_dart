import 'dart:async';

import 'package:typed_graphql/typed_graphql.dart';
import 'package:typed_graphql_server/typed_graphql_server.dart';

enum Mood { happy, sad }

sealed class Animal {
  const Animal();
}

final class Dog extends Animal {
  const Dog();
}

final class Cat extends Animal {
  const Cat();
}

final class Item {
  const Item(this.id);
  final int id;
}

final class Ctx {
  final List<String> log = [];
}

final class WeirdCodec implements ScalarCodec<String> {
  const WeirdCodec();

  @override
  DecodeResult<String> decode(JsonValue json) => const DecodeFailure('no');

  @override
  JsonValue encode(String value) => const JsonNull();
}

/// A reference with the GraphQL type [typeRef] whatever the Dart value is,
/// to reach the errors a typed resolver cannot cause.
final class UncheckedRef implements OutputRef<Object?> {
  UncheckedRef(this.typeRef, this.namedType);

  @override
  final TypeRef typeRef;

  @override
  final NamedTypeDef namedType;

  @override
  OutputRef<Object?> get nullable => throw UnimplementedError();
}

/// A schema of resolvers that succeed, fail, wait and nest, and helpers to
/// run queries against it.
final class ExecutionFixture {
  ExecutionFixture() {
    final b = ExecutableSchemaBuilder<Ctx>();
    final name = Arg('name', b.string, defaultValue: 'you');
    final weird = b.scalar<String>('Weird', const WeirdCodec());
    final mood = b.enumType<Mood>('Mood', [Mood.happy]);
    final pet = b.interface<Animal>(
      'Pet',
      fields: (t) => [t.field('name', b.string).declareOnly()],
    );
    final dog = b.object<Dog>(
      'Dog',
      interfaces: [pet],
      fields: (t) => [t.field('name', b.string).pure((_) => 'rex')],
    );
    final cat = b.object<Cat>(
      'Cat',
      interfaces: [pet],
      fields: (t) => [t.field('name', b.string).pure((_) => 'tom')],
    );
    final found = b.union<Animal>('Found', members: [dog, cat]);
    final item = b.object<Item>(
      'Item',
      fields: (t) => [
        t.field('id', b.int).pure((item) => item.id),
        t
            .field('label', b.string)
            .pure((item) => item.id == 2 ? throw StateError('bad') : 'i'),
        t
            .field('maybe', b.string.nullable)
            .pure((item) => item.id == 2 ? throw StateError('bad') : 'm'),
      ],
    );
    late final ObjectTypeDef<Object?> query;
    query = b.object<Object?>(
      'Query',
      fields: (t) => [
        t.field('hello', b.string).pure((_) => 'world'),
        t
            .field(
              'greet',
              b.string,
              args: [name],
            )
            .resolve((parent, args, context, info) => 'hi ${args.get(name)}'),
        t.field('slow', b.string).resolve((parent, args, context, info) async {
          await Future<void>.delayed(const Duration(milliseconds: 20));
          return 'slow';
        }),
        t
            .field('quick', b.string)
            .resolve((parent, args, context, info) => Future.value('quick')),
        t.field('fail', b.string.nullable).pure((_) => throw StateError('x')),
        t
            .field('failNonNull', b.string)
            .pure((_) => throw StateError('secret detail')),
        t
            .field('failLater', b.string.nullable)
            .resolve(
              (parent, args, context, info) =>
                  Future<String?>.error(StateError('later')),
            ),
        t
            .field('failLaterNonNull', b.string)
            .resolve(
              (parent, args, context, info) =>
                  Future<String>.error(StateError('later')),
            ),
        t
            .field('exception', b.string.nullable)
            .pure(
              (_) => throw GraphQLException(
                'custom',
                extensions: JsonObject({'k': const JsonString('v')}),
              ),
            ),
        t
            .field(
              'forced',
              UncheckedRef(
                const NonNullType(NamedType(Name('String'))),
                b.string,
              ),
            )
            .pure((_) => null),
        t.field('weird', weird).pure((_) => 'x'),
        t.field('strings', b.list(b.string)).pure((_) => ['a', 'b']),
        t
            .field('items', b.list(item))
            .pure((_) => const [Item(1), Item(2), Item(3)]),
        t
            .field('numbers', b.list(b.int.nullable).nullable)
            .pure((_) => [1, null, 3]),
        t.field('lazy', b.list(b.int).nullable).pure((_) => throwingIterable()),
        t
            .field(
              'notAList',
              UncheckedRef(
                const ListType(NonNullType(NamedType(Name('Int')))),
                b.int,
              ),
            )
            .pure((_) => 'text'),
        t.field('overflow', b.int.nullable).pure((_) => 3000000000),
        t.field('nan', b.float.nullable).pure((_) => double.nan),
        t.field('mood', mood.nullable).pure((_) => Mood.sad),
        t.field('pet', pet).pure((_) => const Dog()),
        t
            .field('found', b.list(found))
            .pure((_) => const <Animal>[Dog(), Cat()]),
        t.field('self', query).pure((_) => const Object()),
        t
            .field('selfNullable', query.nullable)
            .pure((parent) => throw StateError('no')),
        t
            .field('useContext', b.string)
            .resolve((parent, args, context, info) => context.log.join(',')),
        t
            .field('where', b.string)
            .resolve(
              (parent, args, context, info) =>
                  '${info.path}|${info.parentTypeName}|${info.fieldName}',
            ),
      ],
    );
    final mutation = b.object<Object?>(
      'Mutation',
      fields: (t) => [
        t.field('first', b.string).resolve((parent, args, context, info) async {
          await Future<void>.delayed(const Duration(milliseconds: 20));
          context.log.add('first');
          return 'first';
        }),
        t.field('second', b.string).resolve((parent, args, context, info) {
          context.log.add('second');
          return 'second';
        }),
        t.field('third', b.string).resolve((parent, args, context, info) async {
          await Future<void>.delayed(const Duration(milliseconds: 5));
          context.log.add('third');
          return 'third';
        }),
        t.field('boom', b.string).resolve((parent, args, context, info) {
          context.log.add('boom');
          throw StateError('boom');
        }),
      ],
    );
    built = b.build(query: query, mutation: mutation);
  }

  late final ExecutableSchema<Ctx> built;

  static List<Object?> errorsOf(Map<String, Object?> json) =>
      json['errors']! as List<Object?>;

  static String codeOf(Object? error) =>
      ((error! as Map<String, Object?>)['extensions']!
              as Map<String, Object?>)['code']!
          as String;

  static Iterable<int> throwingIterable() sync* {
    yield 1;
    throw StateError('lazy');
  }

  Document parse(String text) => const Parser(
    options: ParserOptions(maxTokens: null, maxDepth: null),
  ).parse(Source(text)).requireDocument();

  ValidDocument validDocument(String text) => ValidDocument.assumeValid(
    built.schema,
    parse(text),
  );

  /// Executes [text]; the result is a future only when a resolver waited.
  FutureOr<ResponsePayload> run(
    String text, {
    Ctx? context,
    String? operationName,
    JsonObject? variables,
    ExecutionOptions options = const ExecutionOptions(),
  }) => built.execute(
    validDocument(text),
    context: context ?? Ctx(),
    operationName: operationName,
    variables: variables,
    options: options,
  );

  /// The JSON of the response to [text].
  Future<Map<String, Object?>> json(
    String text, {
    Ctx? context,
    JsonObject? variables,
    ExecutionOptions options = const ExecutionOptions(),
  }) async {
    final payload = await run(
      text,
      context: context,
      variables: variables,
      options: options,
    );
    return payload.toJson().toJson();
  }
}
