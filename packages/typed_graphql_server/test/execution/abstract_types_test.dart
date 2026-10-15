import 'package:test/test.dart';
import 'package:typed_graphql/typed_graphql.dart';
import 'package:typed_graphql_server/typed_graphql_server.dart';

enum Mood { happy, sad }

abstract class Shape {
  const Shape();
  int get sides;
}

final class Circle extends Shape {
  const Circle();
  @override
  int get sides => 0;
}

final class Square extends Shape {
  const Square();
  @override
  int get sides => 4;
}

final class Blob extends Shape {
  const Blob();
  @override
  int get sides => -1;
}

sealed class Fruit {
  const Fruit();
}

final class Apple extends Fruit {
  const Apple();
}

final class Pear extends Fruit {
  const Pear();
}

final class AbstractFixture {
  AbstractFixture() {
    final b = ExecutableSchemaBuilder<Object?>();
    final mood = b.enumType<Mood>('Mood', Mood.values);
    final moodArg = Arg('m', mood);
    final shape = b.interface<Shape>(
      'Shape',
      fields: (t) => [
        t
            .field('describe', b.string)
            .resolve((parent, args, context, info) => 'sides ${parent.sides}'),
      ],
    );
    final circle = b.object<Circle>(
      'Circle',
      interfaces: [shape],
      fields: (t) => [t.field('round', b.boolean).pure((_) => true)],
    );
    final square = b.object<Square>(
      'Square',
      interfaces: [shape],
      fields: (t) => [t.field('corners', b.int).pure((_) => 4)],
    );
    final blob = b.object<Blob>(
      'Blob',
      fields: (t) => [t.field('wobble', b.int).pure((_) => 1)],
    );
    final union = b.union<Shape>('Either', members: [circle, square]);
    final wrong = b.union<Shape>(
      'Wrong',
      members: [circle, square],
      resolveType: (_) => circle,
    );
    final outside = b.union<Shape>(
      'Outside',
      members: [circle, square],
      resolveType: (_) => blob,
    );
    late final ObjectTypeDef<Apple> apple;
    late final ObjectTypeDef<Pear> pear;
    final fruit = b.interface<Fruit>(
      'Fruit',
      fields: (t) => [t.field('name', b.string).declareOnly()],
      resolveType: (value) => switch (value) {
        Apple() => apple,
        Pear() => pear,
      },
    );
    apple = b.object<Apple>(
      'Apple',
      interfaces: [fruit],
      fields: (t) => [t.field('name', b.string).pure((_) => 'apple')],
    );
    pear = b.object<Pear>(
      'Pear',
      interfaces: [fruit],
      fields: (t) => [t.field('name', b.string).pure((_) => 'pear')],
    );
    final query = b.object<Object?>(
      'Query',
      fields: (t) => [
        t.field('shape', shape).pure((_) => const Square()),
        t
            .field('shapes', b.list(shape))
            .pure((_) => const [Circle(), Square()]),
        t.field('either', union).pure((_) => const Circle()),
        t.field('lost', shape).pure((_) => const Blob()),
        t.field('wrong', wrong).pure((_) => const Square()),
        t.field('outside', outside).pure((_) => const Circle()),
        t
            .field('fruits', b.list(fruit))
            .pure((_) => const <Fruit>[Pear(), Apple()]),
        t
            .field('moodName', b.string, args: [moodArg])
            .resolve((parent, args, context, info) => 'ok'),
      ],
    );
    built = b.build(query: query);
  }

  late final ExecutableSchema<Object?> built;

  Future<Map<String, Object?>> json(
    String text, {
    Document? document,
    ExecutionOptions options = const ExecutionOptions(),
  }) async {
    final parsed = document ?? parse(text);
    final payload = await built.execute(
      ValidDocument.assumeValid(built.schema, parsed),
      context: null,
      options: options,
    );
    return payload.toJson().toJson();
  }

  Document parse(String text) => const Parser(
    options: ParserOptions(maxTokens: null, maxDepth: null),
  ).parse(Source(text)).requireDocument();
}

void main() {
  final f = AbstractFixture();

  Object? codeOf(Map<String, Object?> json) =>
      (((json['errors']! as List<Object?>).single!
              as Map<String, Object?>)['extensions']!
          as Map<String, Object?>)['code'];

  String messageOf(Map<String, Object?> json) =>
      ((json['errors']! as List<Object?>).single!
              as Map<String, Object?>)['message']!
          as String;

  group('abstract types at run time', () {
    test('an interface resolves to the first accepting object type', () async {
      expect(
        await f.json(
          '{ shape { __typename ... on Square { corners } } '
          'shapes { __typename } }',
        ),
        equals({
          'data': {
            'shape': {'__typename': 'Square', 'corners': 4},
            'shapes': [
              {'__typename': 'Circle'},
              {'__typename': 'Square'},
            ],
          },
        }),
      );
    });

    test('a union resolves by default', () async {
      expect(
        await f.json('{ either { __typename ... on Circle { round } } }'),
        equals({
          'data': {
            'either': {'__typename': 'Circle', 'round': true},
          },
        }),
      );
    });

    test('an inherited interface field runs with the object value', () async {
      expect(
        await f.json('{ shapes { describe } }'),
        equals({
          'data': {
            'shapes': [
              {'describe': 'sides 0'},
              {'describe': 'sides 4'},
            ],
          },
        }),
      );
    });

    test('an explicit resolveType can switch over a sealed class', () async {
      expect(
        await f.json('{ fruits { __typename name } }'),
        equals({
          'data': {
            'fruits': [
              {'__typename': 'Pear', 'name': 'pear'},
              {'__typename': 'Apple', 'name': 'apple'},
            ],
          },
        }),
      );
    });

    test('no accepting possible type is GQL333', () async {
      final json = await f.json('{ lost { __typename } }');
      expect(codeOf(json), 'GQL333');
      expect(
        messageOf(json),
        'Abstract type "Shape" must resolve to an Object type at runtime for '
        'field "Query.lost". Either the "Shape" type should provide a '
        '"resolveType" function or each possible type should provide an '
        '"isTypeOf" function.',
      );
      expect(json['data'], isNull);
    });

    test('a resolved type that is not possible is GQL334', () async {
      final json = await f.json('{ outside { __typename } }');
      expect(codeOf(json), 'GQL334');
      expect(
        messageOf(json),
        'Runtime Object type "Blob" is not a possible type for "Outside".',
      );
    });

    test('a resolved type that cannot hold the value is GQL334', () async {
      final json = await f.json('{ wrong { __typename } }');
      expect(codeOf(json), 'GQL334');
      expect(
        messageOf(json),
        'Runtime Object type "Circle" cannot hold the value of Dart type '
        'Square for "Wrong": it expects Circle.',
      );
    });
  });

  group('plan cache and suggestions', () {
    test('different suggestion flags get their own messages', () async {
      final document = f.parse('{ moodName(m: hapy) }');
      final withHint = await f.json('', document: document);
      final withoutHint = await f.json(
        '',
        document: document,
        options: const ExecutionOptions(includesSuggestions: false),
      );
      expect(messageOf(withHint), contains('Did you mean'));
      expect(messageOf(withoutHint), isNot(contains('Did you mean')));
    });
  });
}
