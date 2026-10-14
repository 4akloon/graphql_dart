import 'package:test/test.dart';
import 'package:typed_graphql/typed_graphql.dart';

import 'parsed.dart';

void main() {
  group('types', () {
    test('parses an object type with a described field and arguments', () {
      const text =
          '"""Hi""" type Hello implements & A & B @d { '
          '"w" world(flag: Boolean = true @e, list: [Int]): String! }';
      final type = Parsed(text).single<ObjectTypeDefinition>();
      expect(type.description?.isBlock, isTrue);
      expect(type.name.value, 'Hello');
      expect(type.interfaces.map((interface) => interface.name.value), [
        'A',
        'B',
      ]);
      final field = type.fields.single;
      expect(field.description?.value, 'w');
      expect(field.arguments.first.defaultValue, isA<BooleanValue>());
      expect(field.arguments.first.directives.single.name.value, 'e');
      expect(field.type, isA<NonNullType>());
      expect([type.start, type.end], [0, text.length]);
    });

    test('parses interfaces, unions, enums, inputs and scalars', () {
      final document = Parsed(
        'interface I implements J { a: Int } '
        'union U = | A | B '
        'enum E { "d" ONE TWO @d } '
        'input In { a: Int = 1 } '
        'scalar S @specifiedBy(url: "u")',
      ).document;
      if (document.definitions case [
        final InterfaceTypeDefinition interface,
        final UnionTypeDefinition union,
        final EnumTypeDefinition enumType,
        final InputObjectTypeDefinition input,
        final ScalarTypeDefinition scalar,
      ]) {
        expect(interface.interfaces.single.name.value, 'J');
        expect(union.types.map((type) => type.name.value), ['A', 'B']);
        expect(enumType.values.map((value) => value.name.value), [
          'ONE',
          'TWO',
        ]);
        expect(enumType.values.first.description?.value, 'd');
        expect(input.fields.single.defaultValue, isA<IntValue>());
        expect(scalar.directives.single.name.value, 'specifiedBy');
      } else {
        fail('unexpected definitions: ${document.definitions}');
      }
    });

    test('a type without fields has none', () {
      expect(
        Parsed('type Hello').single<ObjectTypeDefinition>().fields,
        isEmpty,
      );
    });

    test('a description before a type-system keyword is not misplaced', () {
      final type = Parsed('"d" type Foo { a: Int }')
          .single<ObjectTypeDefinition>();
      expect(type.description?.value, 'd');
    });
  });

  group('schema and directives', () {
    test('parses a described schema definition', () {
      final schema = Parsed(
        '"S" schema @d { query: Q mutation: M subscription: S }',
      ).single<SchemaDefinition>();
      expect(schema.description?.value, 'S');
      expect(schema.operationTypes.map((type) => type.operation), [
        OperationType.query,
        OperationType.mutation,
        OperationType.subscription,
      ]);
    });

    test('parses a repeatable directive definition', () {
      final directive = Parsed(
        'directive @d(a: Int) repeatable on | FIELD | OBJECT',
      ).single<DirectiveDefinition>();
      expect(directive.isRepeatable, isTrue);
      expect(directive.arguments.single.name.value, 'a');
      expect(directive.locations.map((location) => location.value), [
        'FIELD',
        'OBJECT',
      ]);
    });
  });

  group('errors', () {
    test('rejects an unknown directive location', () {
      expect(Parsed('directive @d on FIELD | INCORRECT_LOCATION').errors, [
        '1:25 GQL008 Unexpected Name "INCORRECT_LOCATION".',
      ]);
    });

    test('rejects true, false and null as enum values', () {
      expect(Parsed('enum Test { VALID, true }').errors, [
        '1:20 GQL013 Name "true" is reserved and cannot be used for an '
            'enum value.',
      ]);
    });

    test('rejects a union without members and input fields with arguments', () {
      expect(Parsed('union Hello = |').errors, [
        '1:16 GQL007 Expected Name, found <EOF>.',
      ]);
      expect(Parsed('input Hello { world(foo: Int): String }').errors, [
        '1:20 GQL007 Expected ":", found "(".',
      ]);
    });

    test('type-system directive arguments are constant', () {
      expect(Parsed(r'type T @d(a: $x)').errors, [
        r'1:14 GQL009 Unexpected variable "$x" in constant value.',
      ]);
    });

    test('a bad definition between good ones is dropped', () {
      final parsed = Parsed('type A { a: Int } enum E { null } scalar S');
      expect(parsed.errors, hasLength(1));
      expect(
        parsed.partial.definitions.map((definition) => definition.runtimeType),
        [
          ObjectTypeDefinition,
          ScalarTypeDefinition,
        ],
      );
    });
  });
}
