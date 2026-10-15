import 'package:test/test.dart';
import 'package:typed_graphql/typed_graphql.dart';
import 'package:typed_graphql_server/typed_graphql_server.dart';

final class Point {
  const Point(this.x, this.y);
  final int x;
  final int y;
}

void main() {
  final b = ExecutableSchemaBuilder<Object?>();
  final first = Arg('first', b.int, defaultValue: 10);
  final after = Arg('after', b.string.nullable);
  final note = Arg.optional('note', b.string.nullable);
  final declared = <Arg<Object?>>[first, after, note];

  Arguments argumentsOf(Map<String, Object?> coerced) =>
      Arguments(declared, coerced);

  group('Arguments', () {
    test('reads a present value', () {
      expect(argumentsOf({'first': 3}).get(first), 3);
    });

    test('reads the default of a missing argument', () {
      expect(argumentsOf({}).get(first), 10);
    });

    test('reads null for a missing nullable argument', () {
      expect(argumentsOf({}).get(after), isNull);
    });

    test('reads an explicit null of a nullable argument', () {
      expect(argumentsOf({'after': null}).get(after), isNull);
    });

    test('an optional argument is absent when missing', () {
      expect(argumentsOf({}).get(note), const Absent());
    });

    test('an optional argument is present when given, even as null', () {
      expect(
        argumentsOf({'note': null}).get(note),
        const Present<String?>(null),
      );
    });

    test('an argument that was not declared is a StateError', () {
      final other = Arg('first', b.int);
      expect(() => argumentsOf({'first': 1}).get(other), throwsStateError);
    });

    test('empty declares nothing', () {
      expect(() => Arguments.empty.get(first), throwsStateError);
    });

    test('a list argument is a real List', () {
      final ids = Arg('ids', b.inputList(b.int));
      final values = Arguments(
        [ids],
        {
          'ids': <Object?>[1, 2],
        },
      );
      expect(values.get(ids), isA<List<int>>());
    });
  });

  group('Arg', () {
    test('has no default JSON without a default', () {
      expect(after.defaultJson, isNull);
    });

    test('writes its default as JSON', () {
      expect(first.defaultJson, JsonNumber(10));
    });

    test('an optional argument keeps the type of its inner reference', () {
      expect(const Printer().print(note.type.typeRef), 'String');
    });
  });

  group('ArgumentsDef', () {
    test('decodes the arguments into a class', () {
      final def = ArgumentsDef<int>([first], (a) => a.get(first) * 2);
      expect(def.decode(Arguments(def.args, {'first': 4})), 8);
    });
  });

  group('InputObjectDef', () {
    late Arg<int> x;
    late Arg<int> y;
    InputObjectDef<Point> make({bool withEncode = false}) {
      x = Arg('x', b.int);
      y = Arg('y', b.int);
      return b.inputObject<Point>(
        'PointInput',
        fields: () => [x, y],
        decode: (v) => Point(v.get(x), v.get(y)),
        encode: withEncode
            ? (p) => JsonObject({'x': JsonNumber(p.x), 'y': JsonNumber(p.y)})
            : null,
      );
    }

    test('decodes its fields', () {
      final def = make();
      final point = def.decode(Arguments(def.fields, {'x': 1, 'y': 2}));
      expect(point.y, 2);
    });

    test('is a non-null reference to itself', () {
      expect(const Printer().print(make().typeRef), 'PointInput!');
    });

    test('evaluates the fields thunk once', () {
      var calls = 0;
      final def = b.inputObject<Point>(
        'Counted',
        fields: () {
          calls++;
          return const <Arg<Object?>>[];
        },
        decode: (v) => const Point(0, 0),
      );
      expect(def.fields, same(def.fields));
      expect(calls, 1);
    });

    test('writes a value as JSON through encode', () {
      expect(
        make(withEncode: true).jsonOf(const Point(1, 2)),
        JsonObject({'x': JsonNumber(1), 'y': JsonNumber(2)}),
      );
    });

    test('a oneOf input object says so', () {
      final def = b.oneOfInputObject<Point>(
        'Either',
        fields: () => const <Arg<Object?>>[],
        decode: (v) => const Point(0, 0),
      );
      expect([def.isOneOf, make().isOneOf], [true, false]);
    });

    test('without encode a value cannot be written', () {
      expect(() => make().jsonOf(const Point(1, 2)), throwsStateError);
    });
  });
}
