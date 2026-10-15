import 'package:test/test.dart';
import 'package:typed_graphql/typed_graphql.dart';
import 'package:typed_graphql_server/typed_graphql_server.dart';

enum Color { red, green, blue }

void main() {
  final b = ExecutableSchemaBuilder<Object?>();

  group('enums', () {
    final color = b.enumType<Color>(
      'Color',
      Color.values,
      mapping: EnumValueMapping(
        descriptionOf: (value) => value == Color.red ? 'Warm.' : null,
        deprecationReasonOf: (value) =>
            value == Color.blue ? 'Too cold.' : null,
      ),
      description: 'A colour.',
    );

    test('names default to Enum.name', () {
      expect(color.nameOf(Color.green), 'green');
      expect(color.valueNamed('green'), Color.green);
    });

    test('values keep declaration order with their metadata', () {
      expect(color.values.map((v) => v.name), ['red', 'green', 'blue']);
      expect(color.values.first.description, 'Warm.');
      expect(color.values.last.deprecationReason, 'Too cold.');
      expect(color.description, 'A colour.');
    });

    test('an unknown name has no value', () {
      expect(color.valueNamed('pink'), isNull);
    });

    test('nameOf can be replaced', () {
      final shouting = b.enumType<Color>(
        'Shout',
        Color.values,
        mapping: EnumValueMapping(nameOf: (value) => value.name.toUpperCase()),
      );
      expect(shouting.nameOf(Color.red), 'RED');
      expect(shouting.valueNamed('RED'), Color.red);
    });

    test('a value outside the definition is an ArgumentError', () {
      final partial = b.enumType<Color>('Partial', [Color.red]);
      expect(() => partial.nameOf(Color.blue), throwsArgumentError);
    });

    test('as an input, jsonOf writes the name and adapt casts', () {
      expect(color.jsonOf(Color.red), const JsonString('red'));
      expect(color.adapt(Color.red), Color.red);
      expect(color.nullable.adapt(null), isNull);
    });

    test('refs print as named types', () {
      expect(const Printer().print(color.typeRef), 'Color!');
      expect(const Printer().print(color.nullable.typeRef), 'Color');
    });

    test('the builder records the definition', () {
      expect(b.definitions, contains(color));
    });
  });

  group('Optional', () {
    test('Present values compare by value', () {
      expect(const Present(1), const Present(1));
      expect(const Present(1).hashCode, const Present(1).hashCode);
      expect(const Present(1), isNot(const Present(2)));
    });

    test('Present equality ignores the static type', () {
      const Optional<int?> a = Present<int?>(1);
      const Optional<num> c = Present<num>(1);
      expect(a, c);
    });

    test('Absent equals Absent and nothing else', () {
      expect(const Absent(), const Absent());
      expect(const Absent().hashCode, const Absent().hashCode);
      expect(const Absent(), isNot(const Present<Object?>(null)));
    });

    test('Absent fits every Optional', () {
      const Optional<String> value = Absent();
      expect(value, isA<Absent>());
    });
  });
}
