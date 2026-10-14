import 'package:test/test.dart';
import 'package:typed_graphql/typed_graphql.dart';

import '../built.dart';

void main() {
  List<String> namesOf(Iterable<Object> elements) => [
    for (final element in elements)
      switch (element) {
        SchemaField(:final name) => name,
        InputValue(:final name) => name,
        SchemaEnumValue(:final name) => name,
        AppliedDirective(:final name) => name,
        NamedTypeReference(:final name) => name,
        _ => fail('unexpected $element'),
      },
  ];

  test('extends a scalar with directives', () {
    final schema = Built('''
scalar Date @a
extend scalar Date @b''').schema;
    expect(namesOf(schema.typeNamed('Date')!.appliedDirectives), ['a', 'b']);
  });

  test('extends an object type, definition members first', () {
    final schema = Built('''
extend type Query implements B @b { b: Int }
type Query implements A @a { a: Int }
extend type Query implements C { c: Int }''').schema;
    final query = schema.typeNamed('Query') as ObjectType;
    expect(namesOf(query.fields), ['a', 'b', 'c']);
    expect(namesOf(query.interfaces), ['A', 'B', 'C']);
    expect(namesOf(query.appliedDirectives), ['a', 'b']);
  });

  test('keeps the span of the definition', () {
    final schema = Built('''
type Query { a: Int }
extend type Query { b: Int }''').schema;
    expect(schema.typeNamed('Query')?.span?.text, 'type Query { a: Int }');
  });

  test('extends an interface type', () {
    final schema = Built('''
interface Node { id: ID }
extend interface Node implements Entity @key { name: String }''').schema;
    final node = schema.typeNamed('Node') as InterfaceType;
    expect(namesOf(node.fields), ['id', 'name']);
    expect(namesOf(node.interfaces), ['Entity']);
    expect(namesOf(node.appliedDirectives), ['key']);
  });

  test('extends a union type', () {
    final schema = Built('''
union Result = A
extend union Result @key = B | C''').schema;
    final result = schema.typeNamed('Result') as UnionType;
    expect(namesOf(result.memberTypes), ['A', 'B', 'C']);
    expect(namesOf(result.appliedDirectives), ['key']);
  });

  test('extends an enum type', () {
    final schema = Built('''
enum Color { RED }
extend enum Color @key { GREEN }''').schema;
    final color = schema.typeNamed('Color') as EnumType;
    expect(namesOf(color.values), ['RED', 'GREEN']);
    expect(namesOf(color.appliedDirectives), ['key']);
  });

  test('applies a valid extension after a mismatched one', () {
    final built = Built(
      'type A { a: Int } extend input A { b: Int } extend type A { c: Int }',
    );
    final a = built.partial.typeNamed('A') as ObjectType;
    expect(namesOf(a.fields), ['a', 'c']);
    expect(built.result.diagnostics, hasLength(1));
    expect(
      built.result.diagnostics.single.code,
      DiagnosticCode.extensionKindMismatch,
    );
  });

  test('extends an input object type', () {
    final schema = Built('''
input Filter { a: Int }
extend input Filter @oneOf { b: Int }''').schema;
    final filter = schema.typeNamed('Filter') as InputObjectType;
    expect(namesOf(filter.fields), ['a', 'b']);
    expect(filter.isOneOf, isTrue);
  });

  test('reports a field an extension repeats', () {
    final built = Built('''
type Query { a: Int }
extend type Query { a: String b: Int }''');
    expect(built.errors, [
      '2:21 GQL104 Field "Query.a" can only be defined once.',
    ]);
    expect(built.result.diagnostics.single.related.single.text, 'a: Int');
    final query = built.partial.typeNamed('Query') as ObjectType;
    expect(namesOf(query.fields), ['a', 'b']);
  });

  test('reports a field repeated across two extensions', () {
    final built = Built('''
type Query { a: Int }
extend type Query { b: Int }
extend type Query { b: String }''');
    expect(built.errors, [
      '3:21 GQL104 Field "Query.b" can only be defined once.',
    ]);
  });

  test('reports an enum value an extension repeats', () {
    expect(Built('enum E { A } extend enum E { A }').errors, [
      '1:30 GQL106 Enum value "E.A" can only be defined once.',
    ]);
  });

  test('reports an extension of a type that is not defined', () {
    final built = Built('extend type Missing { a: Int }');
    expect(built.errors, [
      '1:13 GQL109 Cannot extend type "Missing" because it is not defined.',
    ]);
    expect(built.partial.types, isEmpty);
  });

  test('reports an extension of another kind and ignores it', () {
    final built = Built('''
type A { a: Int }
extend input A { b: Int }''');
    expect(built.errors, [
      '2:14 GQL110 Cannot extend non-input object type "A".',
    ]);
    expect(built.result.diagnostics.single.related.single.start, 0);
    expect(namesOf((built.partial.types.single as ObjectType).fields), ['a']);
  });

  test('names the kind the extension expects', () {
    const sdl =
        'scalar S extend type S @a extend interface S @a '
        'extend union S @a extend enum S @a extend scalar Missing @a';
    expect(Built(sdl).errors.map((error) => error.substring(5)), [
      'GQL110 Cannot extend non-object type "S".',
      'GQL110 Cannot extend non-interface type "S".',
      'GQL110 Cannot extend non-union type "S".',
      'GQL110 Cannot extend non-enum type "S".',
      'GQL109 Cannot extend type "Missing" because it is not defined.',
    ]);
    expect(Built('type T extend scalar T @a').errors, [
      '1:22 GQL110 Cannot extend non-scalar type "T".',
    ]);
  });

  test('rejects an extension of a built-in type', () {
    expect(Built('extend scalar String @a').errors, [
      '1:15 GQL103 The built-in type "String" cannot be extended.',
    ]);
  });

  test('extends the first of two types with one name', () {
    final built = Built('''
type A { a: Int }
input A { b: Int }
extend type A { c: Int }''');
    expect(built.errors, hasLength(1));
    expect(namesOf((built.partial.types.single as ObjectType).fields), [
      'a',
      'c',
    ]);
  });

  test('reports an input field an extension repeats', () {
    expect(Built('input F { a: Int } extend input F { a: Int }').errors, [
      '1:37 GQL104 Field "F.a" can only be defined once.',
    ]);
  });

  test('reports an argument an extension\'s field repeats', () {
    expect(Built('type T extend type T { f(x: Int, x: Int): Int }').errors, [
      '1:34 GQL105 Argument "T.f(x:)" can only be defined once.',
    ]);
  });

  test('gives a member an extension adds a span inside the extension', () {
    final schema = Built('''
type T { a: Int }
extend type T { b: Int }
enum E { A }
extend enum E { B }''').schema;
    final type = schema.typeNamed('T') as ObjectType;
    final color = schema.typeNamed('E') as EnumType;
    expect(type.fieldNamed('b')?.span?.text, 'b: Int');
    expect(type.fieldNamed('b')?.span?.start, 34);
    expect(color.values.last.span?.text, 'B');
    expect(color.values.last.span?.start, 72);
  });
}
