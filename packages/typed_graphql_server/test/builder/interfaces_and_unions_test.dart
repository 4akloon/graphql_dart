import 'package:test/test.dart';
import 'package:typed_graphql_server/src/builder/field_inheritance.dart';
import 'package:typed_graphql_server/typed_graphql_server.dart';

sealed class Pet {
  const Pet();
}

final class Cat extends Pet {
  const Cat();
}

final class Dog extends Pet {
  const Dog();
}

void main() {
  final b = ExecutableSchemaBuilder<Object?>();

  FieldDef<Object?, Object?> pure(
    FieldsBuilder<Object?, Object?> t,
    String name,
  ) => t.field(name, b.string).pure((parent) => name);

  group('interfaces', () {
    final named = b.interface<Pet>(
      'Named',
      fields: (t) => [t.field('name', b.string).declareOnly()],
    );

    test('isSupertypeOf accepts subtypes and rejects others', () {
      expect(named.isSupertypeOf<Cat>(), isTrue);
      expect(named.isSupertypeOf<Pet>(), isTrue);
      expect(named.isSupertypeOf<String>(), isFalse);
    });

    test('an object keeps the interfaces it lists', () {
      final cat = b.object<Cat>(
        'Cat',
        fields: (t) => [t.field('name', b.string).pure((_) => 'c')],
        interfaces: [named],
      );
      expect(cat.interfaces, [named]);
    });
  });

  group('unions', () {
    test('members of subtypes compile and are kept in order', () {
      final cat = b.object<Cat>('Cat', fields: (t) => []);
      final dog = b.object<Dog>('Dog', fields: (t) => []);
      final union = b.union<Pet>('PetUnion', members: [cat, dog]);
      expect(union.members, [cat, dog]);
      expect(cat.accepts(const Cat()), isTrue);
      expect(cat.accepts(const Dog()), isFalse);
    });
  });

  group('inheritance', () {
    final node = b.interface<Object?>(
      'Node',
      fields: (t) => [pure(t, 'id'), pure(t, 'extra')],
    );
    final entity = b.interface<Object?>(
      'Entity',
      fields: (t) => [pure(t, 'created')],
      interfaces: [node],
    );
    final ownFields = b
        .object<Object?>('Own', fields: (t) => [pure(t, 'extra')])
        .fields;

    test('adds interface fields after the own, transitively, in order', () {
      final result = FieldInheritance().collect(ownFields, [entity]);
      expect([for (final f in result) f.name], ['extra', 'created', 'id']);
    });

    test('an own field overrides the interface field of the same name', () {
      final result = FieldInheritance().collect(ownFields, [node]);
      expect(result.first, same(ownFields.first));
      expect(result.where((f) => f.name == 'extra'), hasLength(1));
    });

    test('a declareOnly field is not inherited', () {
      final declared = b.interface<Object?>(
        'Declared',
        fields: (t) => [t.field('x', b.string).declareOnly()],
      );
      expect(FieldInheritance().collect([], [declared]), isEmpty);
    });
  });
}
