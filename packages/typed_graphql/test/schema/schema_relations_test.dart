import 'package:test/test.dart';
import 'package:typed_graphql/typed_graphql.dart';

import 'built.dart';

void main() {
  final schema = Built('''
interface Node { id: ID }
interface Named implements Node { id: ID name: String }
type Dog implements Named & Node { id: ID name: String }
type Cat implements Node { id: ID }
type Query { pet: Pet }
union Pet = Cat | Dog | Missing | Named
enum Mood { HAPPY }
input Filter { mood: Mood }
scalar Date''').schema;

  T type<T extends SchemaType>(String name) => schema.typeNamed(name) as T;
  List<String> names(List<SchemaType> types) => [
    for (final type in types) type.name,
  ];
  TypeRef ref(String text) => switch (const Parser().parseTypeRef(
    Source(text),
  )) {
    ParseElementSuccess(:final value) => value,
    ParseElementFailure(:final diagnostics) => fail('$diagnostics'),
  };

  group('kinds of named types', () {
    test('input types are scalars, enums and input objects', () {
      final inputs = [
        for (final type in schema.types)
          if (type.isInputType) type.name,
      ];
      expect(inputs, ['Mood', 'Filter', 'Date']);
    });

    test('output types are every kind but input objects', () {
      expect(type('Filter').isOutputType, isFalse);
      expect(type('Pet').isOutputType, isTrue);
      expect(type('Mood').isOutputType, isTrue);
    });

    test('leaf, composite and abstract types', () {
      expect(type('Date').isLeafType, isTrue);
      expect(type('Mood').isLeafType, isTrue);
      expect(type('Dog').isLeafType, isFalse);
      expect(type('Dog').isCompositeType, isTrue);
      expect(type('Filter').isCompositeType, isFalse);
      expect(type('Node').isAbstractType, isTrue);
      expect(type('Pet').isAbstractType, isTrue);
      expect(type('Dog').isAbstractType, isFalse);
    });
  });

  group('type references', () {
    test('the named type is found inside its wrappers', () {
      expect(schema.namedTypeOf(ref('[Dog!]!')), same(type('Dog')));
      expect(schema.namedTypeOf(ref('[String]'))?.name, 'String');
      expect(schema.namedTypeOf(ref('Missing')), isNull);
    });

    test('input and output checks look through wrappers', () {
      expect(schema.isInputType(ref('[Filter!]')), isTrue);
      expect(schema.isInputType(ref('Dog')), isFalse);
      expect(schema.isOutputType(ref('[Dog]!')), isTrue);
      expect(schema.isOutputType(ref('Filter')), isFalse);
    });

    test('an unknown named type is neither input nor output', () {
      expect(schema.isInputType(ref('Missing')), isFalse);
      expect(schema.isOutputType(ref('[Missing]')), isFalse);
    });
  });

  group('implementations and possible types', () {
    test('an interface lists the types that declare it, in order', () {
      expect(names(schema.implementations(type('Node'))), [
        'Named',
        'Dog',
        'Cat',
      ]);
      expect(names(schema.implementations(type('Named'))), ['Dog']);
    });

    test('the possible types of an interface are its object types', () {
      expect(names(schema.possibleTypes(type('Node'))), ['Dog', 'Cat']);
    });

    test('a union\'s possible types are its members that are objects', () {
      expect(names(schema.possibleTypes(type('Pet'))), ['Cat', 'Dog']);
    });

    test('an object is its own possible type; a leaf has none', () {
      expect(names(schema.possibleTypes(type('Dog'))), ['Dog']);
      expect(schema.possibleTypes(type('Mood')), isEmpty);
    });

    test('a type that declares an interface twice is listed once', () {
      final twice = Built('''
interface I { a: Int }
type T implements I & I { a: Int }''').schema;
      final interface = twice.typeNamed('I') as InterfaceType;
      expect(names(twice.implementations(interface)), ['T']);
    });
  });

  group('sub types', () {
    test('a member or a declaring type is a sub type', () {
      expect(schema.isSubType(type('Pet'), type('Cat')), isTrue);
      expect(schema.isSubType(type('Node'), type('Named')), isTrue);
      expect(schema.isSubType(type('Named'), type('Cat')), isFalse);
      expect(schema.isSubType(type('Dog'), type('Dog')), isFalse);
    });

    test('a type reference is a sub type through non-null and abstracts', () {
      expect(schema.isTypeSubTypeOf(ref('Dog!'), ref('Dog')), isTrue);
      expect(schema.isTypeSubTypeOf(ref('Dog'), ref('Dog!')), isFalse);
      expect(schema.isTypeSubTypeOf(ref('[Dog!]!'), ref('[Node]')), isTrue);
      expect(schema.isTypeSubTypeOf(ref('[Dog]'), ref('Node')), isFalse);
      expect(schema.isTypeSubTypeOf(ref('Dog'), ref('[Dog]')), isFalse);
      expect(schema.isTypeSubTypeOf(ref('Cat'), ref('Pet')), isTrue);
      expect(schema.isTypeSubTypeOf(ref('Cat'), ref('Named')), isFalse);
      expect(schema.isTypeSubTypeOf(ref('Missing'), ref('Pet')), isFalse);
      expect(schema.isTypeSubTypeOf(ref('Missing'), ref('Missing')), isTrue);
    });

    test('types overlap when an object is possible for both', () {
      expect(schema.typesOverlap(type('Pet'), type('Named')), isTrue);
      expect(schema.typesOverlap(type('Cat'), type('Named')), isFalse);
      expect(schema.typesOverlap(type('Mood'), type('Mood')), isTrue);
    });
  });
}
