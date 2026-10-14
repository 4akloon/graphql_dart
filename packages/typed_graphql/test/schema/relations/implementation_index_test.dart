import 'package:test/test.dart';
import 'package:typed_graphql/typed_graphql.dart';

import '../built.dart';

void main() {
  const count = 40000;
  final text = StringBuffer('interface I { a: Int }\n');
  for (var index = 0; index < count; index++) {
    text.writeln('type T$index implements I & I { a: Int }');
  }
  text.writeln(
    'union U = ${[for (var i = 0; i < count; i++) 'T$i'].join('|')}',
  );
  final schema = Built(text.toString()).schema;
  final interface = schema.typeNamed('I')! as InterfaceType;
  final union = schema.typeNamed('U')!;

  test('an interface with many implementers lists each once, in order', () {
    final implementers = schema.implementations(interface);
    expect(implementers, hasLength(count));
    expect(implementers.first.name, 'T0');
    expect(implementers.last.name, 'T${count - 1}');
  });

  test('sub type and overlap questions about many types stay linear', () {
    final watch = Stopwatch()..start();
    for (final type in schema.types) {
      if (type is ObjectType) {
        expect(schema.isSubType(interface, type), isTrue);
        expect(schema.isSubType(union, type), isTrue);
      }
    }
    expect(schema.typesOverlap(interface, union), isTrue);
    expect(schema.typesOverlap(union, interface), isTrue);
    watch.stop();
    expect(watch.elapsed, lessThan(const Duration(seconds: 5)));
  });

  test('possible types are computed once and in declaration order', () {
    final possible = schema.possibleTypes(union);
    expect(possible, hasLength(count));
    expect(possible[1].name, 'T1');
    expect(identical(schema.possibleTypes(union), possible), isTrue);
    expect(
      identical(schema.possibleTypes(interface).first, possible.first),
      isTrue,
    );
    expect(() => possible.add(possible.first), throwsUnsupportedError);
  });

  test('a union member that is not an object is no sub type', () {
    final mixed = Built('''
interface Named { a: Int }
type Cat implements Named { a: Int }
union Pet = Named | Cat | Missing''').schema;
    final pet = mixed.typeNamed('Pet')!;
    expect(mixed.isSubType(pet, mixed.typeNamed('Cat')!), isTrue);
    expect(mixed.isSubType(pet, mixed.typeNamed('Named')!), isFalse);
  });

  test('a union is not a sub type of a union that has it as a member', () {
    final unions = Built('''
type Cat { a: Int }
union B = Cat
union A = B''').schema;
    TypeRef ref(String name) => NamedType(Name(name));
    expect(unions.isTypeSubTypeOf(ref('B'), ref('A')), isFalse);
    expect(unions.isTypeSubTypeOf(ref('Cat'), ref('B')), isTrue);
    expect(unions.isTypeSubTypeOf(ref('Cat'), ref('A')), isFalse);
  });
}
