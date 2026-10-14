import 'package:test/test.dart';
import 'package:typed_graphql/typed_graphql.dart';

import '../validated.dart';

void main() {
  test('a field of an unknown type points at the type name', () {
    final validated = Validated('''
type Query {
  a: [Missing!]
}''');
    expect(validated.errors, ['2:7 GQL116 Unknown type "Missing".']);
  });

  test('an argument of an unknown type is reported', () {
    final validated = Validated('type Query { a(b: Missing): Int }');
    expect(validated.errors, ['1:19 GQL116 Unknown type "Missing".']);
  });

  test('an input field of an unknown type is reported', () {
    final validated = Validated('''
type Query { a: Int }
input In { b: Missing! }''');
    expect(validated.errors, ['2:15 GQL116 Unknown type "Missing".']);
  });

  test('a directive argument of an unknown type is reported', () {
    final validated = Validated('''
type Query { a: Int }
directive @d(b: Missing) on FIELD''');
    expect(validated.errors, ['2:17 GQL116 Unknown type "Missing".']);
  });

  test('an unknown interface points at its name', () {
    final validated = Validated('type Query implements Missing { a: Int }');
    expect(validated.errors, ['1:23 GQL116 Unknown type "Missing".']);
  });

  test('an unknown union member points at its name', () {
    final validated = Validated('''
type Query { a: U }
union U = Query | Missing''');
    expect(validated.errors, ['2:19 GQL116 Unknown type "Missing".']);
  });

  test('a built-in scalar is a known type', () {
    expect(Validated('type Query { a(b: ID): Boolean }').errors, isEmpty);
  });

  test('an unknown type built in code has no place', () {
    final schema = Schema(
      types: [
        ObjectType(
          'Query',
          fields: [SchemaField('a', const NamedType(Name('Missing')))],
        ),
      ],
      queryTypeName: 'Query',
    );
    expect(Validated.schema(schema).errors, [
      'null GQL116 Unknown type "Missing".',
    ]);
  });
}
