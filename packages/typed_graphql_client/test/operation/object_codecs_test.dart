import 'package:test/test.dart';
import 'package:typed_graphql/typed_graphql.dart';
import 'package:typed_graphql_client/typed_graphql_client.dart';

sealed class Color implements DataEnum {
  const Color();

  factory Color.parse(String raw) => switch (raw) {
    'RED' => const KnownColor.red(),
    _ => UnknownColor(raw),
  };
}

final class KnownColor extends Color {
  const KnownColor.red();

  @override
  String get raw => 'RED';
}

final class UnknownColor extends Color {
  const UnknownColor(this.raw);

  @override
  final String raw;
}

final class Person implements DataObject {
  Person._(JsonObject json, DataContext context)
    : name = const ScalarDataCodec(StringCodec()).field(json, 'name', context),
      nickname = const NullableDataCodec(
        ScalarDataCodec(StringCodec()),
      ).field(json, 'nickname', context),
      middle = const NullableDataCodec(
        ScalarDataCodec(StringCodec()),
      ).optionalField(json, 'middle', context);

  static const codec = ObjectDataCodec(Person._);

  final String name;
  final String? nickname;
  final Optional<String?> middle;

  @override
  JsonObject toJson() => JsonObject({'name': JsonString(name)});
}

void main() {
  group('EnumDataCodec', () {
    const codec = EnumDataCodec(Color.parse);

    test('reads a known value', () {
      expect(
        (codec.decode(const JsonString('RED')) as DecodeSuccess<Color>).value,
        isA<KnownColor>(),
      );
    });

    test('reads an unknown value, keeping its name', () {
      final value = (codec.decode(
        const JsonString('BLUE'),
      ) as DecodeSuccess<Color>).value;
      expect(value.raw, 'BLUE');
      expect(value, isA<UnknownColor>());
    });

    test('reports a value that is not a string', () {
      expect(codec.decode(const JsonNull()), isA<DecodeFailure>());
    });

    test('writes the name', () {
      expect(codec.write(const UnknownColor('BLUE')), const JsonString('BLUE'));
    });
  });

  group('ObjectDataCodec', () {
    JsonObject json(Map<String, JsonValue> fields) => JsonObject(fields);

    Person read(JsonObject object) =>
        (Person.codec.decode(object) as DecodeSuccess<Person>).value;

    test('reads the members', () {
      final person = read(json({'name': const JsonString('Ada')}));
      expect(person.name, 'Ada');
    });

    test('writes through toJson', () {
      final person = read(json({'name': const JsonString('Ada')}));
      expect(
        Person.codec.write(person),
        json({'name': const JsonString('Ada')}),
      );
    });

    test('reports a value that is not an object', () {
      expect(Person.codec.decode(const JsonNull()), isA<DecodeFailure>());
    });

    test('reports a bad member at its key', () {
      final result = Person.codec.decode(json({'name': JsonNumber(1)}));
      expect((result as DecodeFailure).path, [const PathKey('name')]);
    });

    test('reads a missing member as null', () {
      final person = read(json({'name': const JsonString('Ada')}));
      expect(person.nickname, isNull);
    });

    test('reads the optional field of a missing member as absent', () {
      final person = read(json({'name': const JsonString('Ada')}));
      expect(person.middle, const Optional<String?>.absent());
    });

    test('reads the optional field of null as present null', () {
      final person = read(
        json({'name': const JsonString('Ada'), 'middle': const JsonNull()}),
      );
      expect(person.middle, const Optional<String?>.present(null));
    });
  });

  group('decode', () {
    final kinds = <JsonValue>[
      const JsonNull(),
      const JsonBool(true),
      JsonNumber(1),
      const JsonString('x'),
      JsonArray(const []),
      JsonObject(const {}),
    ];
    final codecs = <String, DataCodec<Object?>>{
      'scalar': const ScalarDataCodec(StringCodec()),
      'nullable': const NullableDataCodec(ScalarDataCodec(StringCodec())),
      'list': const ListDataCodec(ScalarDataCodec(StringCodec())),
      'enum': const EnumDataCodec(Color.parse),
      'object': Person.codec,
      'json': const JsonDataCodec(),
    };

    for (final MapEntry(key: name, value: codec) in codecs.entries) {
      test('$name never throws for any kind of JSON', () {
        for (final kind in kinds) {
          expect(() => codec.decode(kind), returnsNormally);
        }
      });
    }
  });
}
