import 'package:test/test.dart';
import 'package:typed_graphql/typed_graphql.dart';

import '../built.dart';
import '../sdl.dart';

void main() {
  test('keeps the first of two fields with one name', () {
    final built = Built('''
type Query {
  a: Int
  a: String
}''');
    expect(built.errors, [
      '3:3 GQL104 Field "Query.a" can only be defined once.',
    ]);
    final query = built.partial.typeNamed('Query') as ObjectType;
    expect(query.fields.single.span?.text, 'a: Int');
  });

  test('points a repeated field at the field it repeats', () {
    final built = Built('interface I { a: Int a: Int }');
    expect(built.result.diagnostics.single.related.single.text, 'a: Int');
    expect(built.result.diagnostics.single.related.single.start, 14);
  });

  test('keeps the first of two input fields with one name', () {
    final built = Built('input In { a: Int a: Int b: Int }');
    expect(built.errors, [
      '1:19 GQL104 Field "In.a" can only be defined once.',
    ]);
    final input = built.partial.typeNamed('In') as InputObjectType;
    expect(input.fields.map((field) => field.name), ['a', 'b']);
  });

  test('keeps the first of two enum values with one name', () {
    final built = Built('enum Color { RED GREEN RED }');
    expect(built.errors, [
      '1:24 GQL106 Enum value "Color.RED" can only be defined once.',
    ]);
    final color = built.partial.typeNamed('Color') as EnumType;
    expect(color.values.map((value) => value.name), ['RED', 'GREEN']);
  });

  test('keeps the first of two field arguments with one name', () {
    final built = Built('type Query { f(a: Int, a: Int, b: Int): Int }');
    expect(built.errors, [
      '1:24 GQL105 Argument "Query.f(a:)" can only be defined once.',
    ]);
    final query = built.partial.typeNamed('Query') as ObjectType;
    expect(query.fields.single.arguments.map((argument) => argument.name), [
      'a',
      'b',
    ]);
  });

  test('keeps the first of two directive arguments with one name', () {
    final built = Built('directive @d(a: Int, a: Int) on FIELD');
    expect(built.errors, [
      '1:22 GQL105 Argument "@d(a:)" can only be defined once.',
    ]);
    expect(built.partial.directives.single.arguments, hasLength(1));
  });

  test('checks the arguments of a repeated field too, as graphql-js', () {
    final built = Built('type Query { f: Int f(a: Int, a: Int): Int }');
    expect(built.errors, [
      '1:21 GQL104 Field "Query.f" can only be defined once.',
      '1:31 GQL105 Argument "Query.f(a:)" can only be defined once.',
    ]);
  });

  test('allows one name in different types and fields', () {
    final built = Built('''
type A { f(x: Int): Int g(x: Int): Int }
type B { f: Int }''');
    expect(built.result, isA<BuildSuccess>());
  });

  test('relates a repeated argument to the one it repeats', () {
    final built = Built('type Query { f(a: Int, a: Int): Int }');
    expect(built.result.diagnostics.single.related.single.text, 'a: Int');
    expect(built.result.diagnostics.single.related.single.start, 15);
  });

  test('relates a repeated enum value to the one it repeats', () {
    final built = Built('enum Color { RED RED }');
    expect(built.result.diagnostics.single.related.single.text, 'RED');
    expect(built.result.diagnostics.single.related.single.start, 13);
  });

  test('relates nothing without a source', () {
    final document = Sdl('type Query { a: Int a: Int }').document;
    final result = const SchemaBuilder().fromSdl(document);
    expect(result.diagnostics.single.related, isEmpty);
  });

  test('keeps the interfaces and directives of a type with a repeat', () {
    final built = Built('type T implements I @d { a: Int a: Int }');
    final type = built.partial.typeNamed('T') as ObjectType;
    expect(type.interfaces.single.name.value, 'I');
    expect(type.appliedDirectives.single.name, 'd');
    expect(type.fields.single.name, 'a');
  });
}
