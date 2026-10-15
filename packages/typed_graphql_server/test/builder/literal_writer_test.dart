import 'package:test/test.dart';
import 'package:typed_graphql/typed_graphql.dart';
import 'package:typed_graphql_server/src/builder/literal_writer.dart';
import 'package:typed_graphql_server/typed_graphql_server.dart';

enum Color { red, green }

void main() {
  final b = ExecutableSchemaBuilder<Object?>();
  final color = b.enumType<Color>('Color', Color.values);
  final x = Arg('x', b.int);
  b.inputObject<Object>(
    'Point',
    fields: () => [x, Arg('colors', b.inputList(color))],
    decode: (_) => const Object(),
  );
  final writer = LiteralWriter(b.definitions);

  String write(JsonValue json, String type) {
    final node = switch (const Parser().parseTypeRef(Source(type))) {
      ParseElementSuccess(:final value) => value,
      _ => throw StateError('bad type $type'),
    };
    return const Printer().print(writer.write(json, node));
  }

  group('LiteralWriter', () {
    test('writes an integral number as an Int, even for a Float', () {
      expect(write(JsonNumber(3), 'Float'), '3');
      expect(write(JsonNumber(3.0), 'Float'), '3');
    });

    test('writes a fraction as a Float', () {
      expect(write(JsonNumber(1.5), 'Float'), '1.5');
    });

    test('writes a number beyond the safe integers as a Float', () {
      expect(write(JsonNumber(1e21), 'Float'), '1e+21');
    });

    test('writes a string, a boolean and null', () {
      expect(write(const JsonString('a"b'), 'String'), r'"a\"b"');
      expect(write(const JsonBool(true), 'Boolean!'), 'true');
      expect(write(const JsonNull(), 'String'), 'null');
    });

    test('writes an enum name as an enum value', () {
      expect(write(const JsonString('red'), 'Color!'), 'red');
    });

    test('writes a string for an unknown type as a string', () {
      expect(write(const JsonString('red'), 'Other'), '"red"');
    });

    test('writes a list through the item type', () {
      final json = JsonArray([
        const JsonString('red'),
        const JsonString('green'),
      ]);
      expect(write(json, '[Color!]!'), '[red, green]');
    });

    test('writes a single value for a list type as the item', () {
      expect(write(const JsonString('red'), '[Color]'), 'red');
    });

    test('writes an input object field by the type of the field', () {
      final json = JsonObject({
        'x': JsonNumber(1),
        'colors': JsonArray([const JsonString('green')]),
      });
      expect(write(json, 'Point'), '{ x: 1, colors: [green] }');
    });

    test('writes a field the input object does not declare by its shape', () {
      final json = JsonObject({'extra': const JsonString('red')});
      expect(write(json, 'Point'), '{ extra: "red" }');
    });

    test('writes by shape without a type', () {
      final json = JsonObject({
        'a': JsonArray([JsonNumber(1), const JsonBool(false)]),
      });
      expect(
        const Printer().print(writer.write(json, null)),
        '{ a: [1, false] }',
      );
    });

    test('the first definition of a name wins', () {
      final other = ExecutableSchemaBuilder<Object?>();
      final first = other.enumType<Color>('Pick', Color.values);
      other.scalar<String>('Pick', const StringCodec());
      expect(
        const Printer().print(
          LiteralWriter(other.definitions).write(
            const JsonString('red'),
            const NamedType(Name('Pick')),
          ),
        ),
        'red',
      );
      expect(first.name, 'Pick');
    });
  });
}
