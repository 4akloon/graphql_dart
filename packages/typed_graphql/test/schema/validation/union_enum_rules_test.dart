import 'package:test/test.dart';
import 'package:typed_graphql/typed_graphql.dart';

import '../validated.dart';

void main() {
  List<String> errorsOf(String sdl) => Validated(sdl).errors;

  test('a union without members points at the union', () {
    expect(
      errorsOf('''
type Query { a: U }
union U'''),
      ['2:1 GQL141 Union type U must define one or more member types.'],
    );
  });

  test('a union member named twice points at both references', () {
    final schema = Schema(
      types: [
        ObjectType(
          'Query',
          fields: [SchemaField('a', const NamedType(Name('U')))],
        ),
        UnionType(
          'U',
          memberTypes: [
            const NamedTypeReference('Query'),
            const NamedTypeReference('Query'),
          ],
        ),
      ],
      queryTypeName: 'Query',
    );
    expect(Validated.schema(schema).errors, [
      'null GQL142 Union type U can only include type Query once.',
    ]);
  });

  test('a union member that is not an object type points at it', () {
    expect(
      errorsOf('''
type Query { a: U }
union U = Query | I
interface I { a: Int }'''),
      [
        '2:19 GQL143 Union type U can only include Object types, it cannot '
            'include I.',
      ],
    );
  });

  test('an enum without values points at the enum', () {
    expect(
      errorsOf('''
type Query { a: E }
enum E'''),
      ['2:1 GQL144 Enum type E must define one or more values.'],
    );
  });

  test('an input object without fields points at the type', () {
    expect(
      errorsOf('''
type Query { a(b: In): Int }
input In'''),
      ['2:1 GQL145 Input Object type In must define one or more fields.'],
    );
  });

  test('a non-null field of a OneOf type points at its type', () {
    expect(
      errorsOf('''
type Query { a(b: In): Int }
input In @oneOf { c: Int! d: Int }'''),
      ['2:22 GQL146 OneOf input field In.c must be nullable.'],
    );
  });

  test('a defaulted field of a OneOf type points at the field', () {
    expect(
      errorsOf('''
type Query { a(b: In): Int }
input In @oneOf { c: Int = 1 d: Int }'''),
      ['2:19 GQL147 OneOf input field In.c cannot have a default value.'],
    );
  });
}
