import 'package:test/test.dart';
import 'package:typed_graphql/typed_graphql.dart';

import '../validated.dart';

void main() {
  const string = NamedType(Name('String'));
  final query = ObjectType('Query', fields: [SchemaField('a', string)]);
  Schema withQuery(List<SchemaType> types) =>
      Schema(types: [query, ...types], queryTypeName: 'Query');

  test('a schema of valid names has no name error', () {
    expect(
      Validated('type Query { a(b: Int): E } enum E { A }').errors,
      isEmpty,
    );
  });

  test('a type name that begins with __ points at the type', () {
    final validated = Validated('''
type Query { a: Int }
scalar __Odd''');
    expect(validated.errors, [
      '2:1 GQL114 Name "__Odd" must not begin with "__", which is reserved '
          'by GraphQL introspection.',
    ]);
  });

  test('a field, an argument and an enum value that begin with __ are '
      'reported in order', () {
    final validated = Validated('''
type Query { __f(__a: Int): E }
enum E { __V }''');
    expect(validated.codes, ['GQL114', 'GQL114', 'GQL114']);
    expect(validated.errors.first, startsWith('1:14 GQL114 Name "__f"'));
    expect(validated.errors[1], startsWith('1:18 GQL114 Name "__a"'));
    expect(validated.errors.last, startsWith('2:10 GQL114 Name "__V"'));
  });

  test('an input field that begins with __ is reported', () {
    final validated = Validated('''
type Query { a: Int }
input In { __f: Int }''');
    expect(validated.errors.single, startsWith('2:12 GQL114 Name "__f"'));
  });

  test('a directive and its argument that begin with __ are reported', () {
    final validated = Validated('''
type Query { a: Int }
directive @__d(__a: Int) on FIELD''');
    expect(validated.codes, ['GQL114', 'GQL114']);
    expect(validated.errors.first, startsWith('2:1 GQL114 Name "__d"'));
    expect(validated.errors.last, startsWith('2:16 GQL114 Name "__a"'));
  });

  test('an empty name built in code is reported', () {
    final schema = withQuery([ScalarType('')]);
    expect(Validated.schema(schema).errors, [
      'null GQL115 Expected name to be a non-empty string.',
    ]);
  });

  test('a name built in code that starts with a digit is reported', () {
    final schema = withQuery([ScalarType('1x')]);
    expect(Validated.schema(schema).errors, [
      'null GQL115 Names must start with [_a-zA-Z] but "1x" does not.',
    ]);
  });

  test('a name built in code with another character is reported', () {
    final schema = withQuery([
      ObjectType('T', fields: [SchemaField('x-y', string)]),
    ]);
    expect(Validated.schema(schema).errors, [
      'null GQL115 Names must only contain [_a-zA-Z0-9] but "x-y" does not.',
    ]);
  });

  test('enum values built in code named true, false and null are '
      'reported', () {
    final schema = withQuery([
      EnumType(
        'E',
        values: [
          SchemaEnumValue('true'),
          SchemaEnumValue('false'),
          SchemaEnumValue('null'),
        ],
      ),
    ]);
    expect(Validated.schema(schema).errors, [
      'null GQL013 Enum values cannot be named: true',
      'null GQL013 Enum values cannot be named: false',
      'null GQL013 Enum values cannot be named: null',
    ]);
  });
}
